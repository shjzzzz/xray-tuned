# ==================================================
# 基础输出与环境检测
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 支持 `bash install.sh key=value ...` 位置参数传入（与环境变量前缀等价，且彻底规避终端换行/转义断行报错）
for arg in "$@"; do
  case "$arg" in
    [A-Za-z_]*=*) export "$arg" ;;
    *=*) warn "忽略无法识别的参数: $arg" ;;
  esac
done

[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="${ID:-}"
  case "$OS_ID" in
    debian|ubuntu|centos|rhel|almalinux|rocky|ol|amzn|fedora|alpine|opensuse*|sles) ;;
    *) for _l in ${ID_LIKE:-}; do
         case "$_l" in
           debian|ubuntu) OS_ID=$_l; break ;;
           rhel|fedora|centos) OS_ID=$_l; break ;;
           suse) OS_ID=sles; break ;;
         esac
       done ;;
  esac
else
  error "无法识别当前系统发行版"
fi

# ==================================================
# 项目常量
# ==================================================

PROJECT_NAME="xray-xhttp"
PROJECT_VERSION="5.2.4"
PROJECT_REPO="shjzzzz/xray-tuned"
# 默认推荐的 Xray-core 版本：回退版本 v26.10.21（含 v26.9.30 起的 XDRIVE / MASQUE / Noise / WFP 特性，并移除了 3 张被攻破的中间 CA 根证书；
# v26.10.10 / v26.10.17 已被官方撤版）。正常情况下按通道（stable=/releases/latest）自适应取最新，查询失败才用它。
XRAY_DEFAULT_VERSION="26.10.21"
MANAGE_CMD="xh"
MANAGE_BIN="/usr/local/bin/${MANAGE_CMD}"
STATE_DIR="/etc/xhttp-cdn"
NODE_ENV_FILE="${STATE_DIR}/node.env"
SYSCTL_CONF="/etc/sysctl.d/99-xray-xhttp.conf"
LIMITS_CONF="/etc/security/limits.d/99-xray-xhttp.conf"

# ==================================================
# 功能开关（均可用环境变量覆盖）
# 端口规划 (默认配置，全部单端口，默认关闭端口跳跃)
# ==================================================
# 443      TCP (Xray VLESS 兜底)
# 8443     UDP (Xray h3-direct)
# 8445     TCP (Xray h2-direct，默认关闭)
# 8446     UDP (Xray Hysteria 2 / 备用)
# 80       TCP (Nginx HTTP 验证与重定向)
# 8001     TCP (Xray XHTTP CDN 回源入站，仅监听 127.0.0.1)
# 8002     TCP (Nginx 反代分流，仅监听 127.0.0.1)
# 8003     TCP (Nginx SSL 回落与伪装站点，仅监听 127.0.0.1)

# ==================================================
# 客户端 / 调优管理命令别名
# ==================================================
MANAGE_CMD="xh"

# ==================================================
# 流控调优开关（默认开启）
# ==================================================
# 系统级调优默认开启；安装期只写内核与网卡队列，
# systemd 层的调优全部收进管理命令，按需 `xh tuning on`。
# ==================================================

FEATURE_KEEPALIVE=${FEATURE_KEEPALIVE:-true}
FEATURE_AUTOUPDATE=${FEATURE_AUTOUPDATE:-true}
# Xray-core 通道：prerelease（默认，安装与每周自动更新都取 GitHub 最新含 pre-release 的版本）| stable
XRAY_CHANNEL=${XRAY_CHANNEL:-stable}
# XRAY_DEFAULTS=true（默认）：服务端与客户端链接里一律使用 Xray 官方默认参数，不写调优项
# （policy、sockopt 的 TFO/MPTCP/keepalive/tcpUserTimeout/拥塞算法、xPadding*、scStreamUpServerSecs、
#  scMinPostsIntervalMs、QUIC 窗口 fm）。XHTTP 服务端 mode 用默认 auto（同时接受 auto / packet-up / stream-up 客户端）。
# 拥塞算法由内核 net.ipv4.tcp_congestion_control 决定。XRAY_DEFAULTS=false 恢复旧版调优输出。
XRAY_DEFAULTS=${XRAY_DEFAULTS:-true}
if [[ "$XRAY_DEFAULTS" == true ]]; then
  FEATURE_XPADDING=false
fi
AUTO=${AUTO:-0}

# ==================================================
# 节点集：默认 8 条核心节点（与实机当前一致），全部由 Xray 单核心提供
# ==================================================
#   1. VLESS-TLS+后量子+XHTTP+CDN     经 CDN，TLS 1.3 + ML-KEM-768
#   2. VLESS-REALITY+后量子+Vision    直连 TCP 443，REALITY + ML-KEM-768
#   3. VLESS-XHTTP-Direct-H3         直连 UDP 8443，QUIC/h3
#   4. VLESS-XHTTP-Direct-H2         直连 TCP 8445，h2
#   5. Hysteria2-H3-Direct           直连 UDP 随机高端口，标准 HTTP/3
#   6. Hysteria2-TLS-BBR-Salamander  直连 UDP 随机高端口，salamander 混淆
#   7. VLESS-Reality-Vision-Direct   直连 TCP 443，xtls-rprx-vision 零拷贝直通
#   8. VLESS-Reality-XHTTP-Direct    直连 TCP 443，XHTTP 上下行不分离
# 备用（默认关闭）：CDN-H2、CDN-H3、上下行分离、MASQUE 等。
#
FEATURE_H3_DIRECT=${FEATURE_H3_DIRECT:-true}
# v4.9.78 起 Hysteria2 重新默认安装（与本机当前节点集一致）；不需要时 FEATURE_HY2=false，或装好后 xh hy2 off。
FEATURE_HY2=${FEATURE_HY2:-true}
# FEATURE_HY2_H3（v4.9.26）：在 UDP 443 上再开一条**不加混淆**的 Hysteria2（Hysteria2-H3-Direct），
# 流量形态就是一个普通网站的 HTTP/3，是 UDP 里最不容易被运营商按端口/特征 QoS 的样子。
# 依附于 FEATURE_HY2（共用认证密码与证书）；UDP 443 被占用时自动关闭。v4.9.28 起为 Xray 唯一的 Hysteria2 节点。
FEATURE_HY2_H3=${FEATURE_HY2_H3:-true}
# FEATURE_HY2_OBFS（v4.9.28）：salamander 混淆的 Hysteria2-Obfs-Direct。v4.9.78 起默认开启（依附于 Hysteria2 总开关）。
# 不需要时：FEATURE_HY2_OBFS=false bash install.sh，或装好后 xh hy2 obfs off。
# FEATURE_HY2 仍是 Hysteria2 的总开关（内核版本不够、缺证书时两条一起关）。
FEATURE_HY2_OBFS=${FEATURE_HY2_OBFS:-true}
# v4.9.73: Hysteria2 改为默认随机高端口（避免固定端口被运营商 QoS / 探测阻断）。
# 允许环境变量显式指定，未指定时由 05-base-env.sh 自动生成随机可用端口。
HY2_H3_PORT=${HY2_H3_PORT:-}
HY2_PORT=${HY2_PORT:-}

# FEATURE_CDN_H2：是否生成经 CDN 的 TCP(h2) 节点 VLESS-XHTTP-CDN-H2（默认关闭；需要开启时 FEATURE_CDN_H2=true 或装好后 xh cdnh2 on）。
FEATURE_CDN_H2=${FEATURE_CDN_H2:-false}

# FEATURE_CDN_H3：是否生成经 CDN 的 QUIC(h3) 节点 VLESS-XHTTP-CDN-H3（默认关闭；需要开启时 FEATURE_CDN_H3=true 或装好后 xh cdnh3 on）。
FEATURE_CDN_H3=${FEATURE_CDN_H3:-false}

# FEATURE_BLOCK_CN / FEATURE_BLOCK_ADS（v4.9.53，默认关闭）：出站屏蔽回国 IP（geoip:cn）/ 广告域名
# （geosite:category-ads-all），参考 zxcvos/Xray-script 的可选规则。运行期用 xh block cn|ads on|off 切换。
# 回国 IP 屏蔽会让依赖本代理访问国内站点的客户端断流，仅在落地机不需要回国流量时开启。
FEATURE_BLOCK_CN=${FEATURE_BLOCK_CN:-false}
FEATURE_BLOCK_ADS=${FEATURE_BLOCK_ADS:-false}

# REALITY_MAX_TIME_DIFF（毫秒，默认不设）：Reality 只接受客户端时间戳与本机相差不超过该值的握手，防重放。
# 客户端系统时间偏差超过它就连不上，需开启自动校时；运行期用 xh timediff on [毫秒] / off 切换。
REALITY_MAX_TIME_DIFF=${REALITY_MAX_TIME_DIFF:-}

# FEATURE_REALITY_SPX（默认开启）：Reality 客户端链接附带 spx（spiderX）参数，值由 UUID 派生。关闭用 FEATURE_REALITY_SPX=false。
FEATURE_REALITY_SPX=${FEATURE_REALITY_SPX:-true}

# FEATURE_H2_DIRECT（v4.7.0 新增）：h3-direct 的 TCP 孪生体（监听 TCP 8445）。
# 默认开启（与实机当前节点集一致）；不需要时 FEATURE_H2_DIRECT=false 或装好后 xh h2direct off。
FEATURE_H2_DIRECT=${FEATURE_H2_DIRECT:-true}

# FEATURE_REALITY_UP_CDN_DOWN（v4.9.64 起默认开启）：上下行分离节点
# VLESS-Reality-Up-CDN-Down（上行 Reality 直连 443 / 下行 CDN H2 443）。
# v4.9.78 起默认关闭（备用节点）；需要时 FEATURE_REALITY_UP_CDN_DOWN=true，或装好后 xh split reality-up on。
FEATURE_REALITY_UP_CDN_DOWN=${FEATURE_REALITY_UP_CDN_DOWN:-false}
FEATURE_UP_CDN_DOWN_MIHOMO=${FEATURE_UP_CDN_DOWN_MIHOMO:-${FEATURE_REALITY_UP_CDN_DOWN}}

# FEATURE_CDN_UP_REALITY_DOWN（v4.9.29 新增，v4.9.36 默认关闭）：反向的上下行分离节点
# VLESS-CDN-Up-Reality-Down —— 上行 XHTTP+TLS 经 Cloudflare CDN，下行 XHTTP+Reality 直连。
# 与 Reality-Up-CDN-Down 一样落到同一个 8001 入站（Reality 443 回落 / Nginx 8003 回源），
# 默认关闭保持核心节点精简，需要时可通过 FEATURE_CDN_UP_REALITY_DOWN=true 开启。
FEATURE_CDN_UP_REALITY_DOWN=${FEATURE_CDN_UP_REALITY_DOWN:-false}

# FEATURE_XHTTP_VLESSENC（v4.9.29）：8001 XHTTP 入站启用 VLESS Encryption（默认关闭设为 none，杜绝客户端 -1 报错）。
FEATURE_XHTTP_VLESSENC=${FEATURE_XHTTP_VLESSENC:-false}

# FEATURE_PORT_HOPPING：UDP 端口跳跃（默认关闭）。
# 避免客户端在服务端未配置 nat/iptables 端口段重定向时握手失败，或劫持同机其他 UDP 服务。
FEATURE_PORT_HOPPING=${FEATURE_PORT_HOPPING:-false}

# FEATURE_BRUTAL：TCP Brutal (HyNetworks/tcp-brutal) 极速拥塞控制（默认开启）。
# 当系统内核存在 brutal 模块时，自动为 Xray TCP 入站启用 Brutal 拥塞控制。
# 记下用户是否显式传了 FEATURE_BRUTAL：平台识别（05-base-env.sh）要在小内存机上改默认，但不能覆盖用户的明确选择。
FEATURE_BRUTAL_EXPLICIT="${FEATURE_BRUTAL+set}"
FEATURE_BRUTAL=${FEATURE_BRUTAL:-true}
BRUTAL_DEFAULT_MBPS=${BRUTAL_DEFAULT_MBPS:-auto}

# REALITY_MIN_CLIENT_VER：Reality 客户端最低版本，默认 1.8.0（兼容 Shadowrocket / mihomo / sing-box 等非 Xray 内核客户端，它们的版本字段为 0，会被内核默认下限 26.3.27 拒绝）。
# 设为 none 或 default 则不写 minClientVer（严格模式，只放行最新 Xray 内核客户端）。
# 兼容别名：MIN_CLIENT_VER、MINVERSION、MIN_VERSION。
REALITY_MIN_CLIENT_VER="${REALITY_MIN_CLIENT_VER:-${MIN_CLIENT_VER:-${MINVERSION:-${MIN_VERSION:-1.8.0}}}}"

# ==================================================
# Xray v26.9.30+ 前沿新特性开关（默认可选）
# ==================================================
# FEATURE_MASQUE: IETF RFC 9484 CONNECT-IP 标准 L3 隧道
FEATURE_MASQUE=${FEATURE_MASQUE:-false}
MASQUE_PORT=${MASQUE_PORT:-}
MASQUE_PASSWORD=${MASQUE_PASSWORD:-""}

# FEATURE_XDRIVE: 基于云存储 (Google Drive) 的穿透代理（应对极端 IP 白名单/无公网 IP）
FEATURE_XDRIVE=${FEATURE_XDRIVE:-false}
XDRIVE_FOLDER=${XDRIVE_FOLDER:-""}
XDRIVE_CLIENT_ID=${XDRIVE_CLIENT_ID:-""}
XDRIVE_CLIENT_SECRET=${XDRIVE_CLIENT_SECRET:-""}
XDRIVE_REFRESH_TOKEN=${XDRIVE_REFRESH_TOKEN:-""}
# Xray >= 26.10.17：XDRIVE 只接受 VLESS + VLESS Encryption（无 flow），客户端必须开 mux；service 名改为 google-drive。
# 密钥对由 xray vlessenc 生成（X25519 认证），留空时开启 XDRIVE 自动生成。
XDRIVE_ENCRYPTION=${XDRIVE_ENCRYPTION:-""}
XDRIVE_DECRYPTION=${XDRIVE_DECRYPTION:-""}

# FEATURE_NOISE_EXP: Finalmask Noise dynamic expression 动态模板混淆（防 UDP DPI 识别）
FEATURE_NOISE_EXP=${FEATURE_NOISE_EXP:-false}
# FEATURE_NOISE_LINKS（v4.9.81，默认关闭）：客户端链接的 fm 里是否也带 noise 项。服务端入站的 noise 只是发送方行为，
# 老客户端不受影响；但链接里的 noise.exp 在 Xray < 26.9.30 的客户端内核里无法解析，v2rayN 会报「运行内核失败」。
# 确认所有客户端内核都 >= 26.9.30 后再开：xh noise links on。
# 10 大核心节点之三大后量子 (ML-KEM-768) 节点开关（默认全部开启）
FEATURE_TLS_PQ_XHTTP=${FEATURE_TLS_PQ_XHTTP:-true}
FEATURE_TLS_PQ_VISION=${FEATURE_TLS_PQ_VISION:-false}
FEATURE_REALITY_PQ_VISION=${FEATURE_REALITY_PQ_VISION:-false}

# FEATURE_REALITY_VISION / FEATURE_REALITY_XHTTP：Reality 443 入站上的两个直连节点。
# 默认启用 REALITY_XHTTP（标口 443 + XHTTP）；REALITY_VISION 默认关闭（可按需 xh reality vision on 启用）。
# 关闭 = 服务端去掉对应的 clients 项 / fallback 项并从订阅里移除节点；装好后用 xh reality vision|xhttp on|off 切换。
FEATURE_REALITY_VISION=${FEATURE_REALITY_VISION:-false}
FEATURE_REALITY_XHTTP=${FEATURE_REALITY_XHTTP:-true}
NOISE_EXP_PACKET=${NOISE_EXP_PACKET:-"<b 16030100><r 32><t><c><rd 8>"}
NOISE_EXP_DELAY=${NOISE_EXP_DELAY:-"10-50"}


# ==================================================
# 未识别环境变量检查（v4.7.10）
# ==================================================
# 本脚本全靠环境变量做非交互配置，而 bash 对不存在的变量没有任何反馈：
# 拼错一个名字（CDN_DIRECT_PORT、FEATURE_XRAY_AUTO_UPGRADE 这类看起来
# 很合理但脚本里根本没有的），安装照常成功、日志一切正常，
# 用户以为配置生效了，实际被静默忽略——排查时几乎不可能想到这一层。
#
# 已知变量表不写死：直接在脚本自身里搜这个名字有没有被引用。
# 好处是永远不会和实现漂移——新增一个变量就自动被认可，删掉一个就自动开始告警。
# 代价是脚本得能读到自己；`bash <(curl ...)` 这种进程替换下 $0 是
# /dev/fd/63 且已被读尽，读不到就跳过检查（best-effort，绝不因此中断安装）。
check_unknown_env_vars() {
  local self="${BASH_SOURCE[0]}" name unknown=() code
  [[ -r "$self" && -s "$self" ]] || return 0

  # 必须先剥掉整行注释再搜：上面那段注释里举了两个「不存在的变量」当例子，
  # 直接搜原文会把它们搜到，检查永远报不出东西（第一版就栽在这）。
  # 只剥整行注释、不碰行尾注释——后者要正确处理引号内的 # 才不会误伤代码。
  code=$(grep -v '^[[:space:]]*#' "$self")

  # 只看长得像本项目参数的变量，避免把系统里成百上千的环境变量全扫一遍
  while IFS= read -r name; do
    grep -q "\b${name}\b" <<< "$code" || unknown+=("$name")
  done < <(compgen -v | grep -E '^(AUTO|FEATURE_|CDN_|REALITY_|XHTTP_|HY2_|OBFS_|H2_|H3_|IP_CHOICE|FALLBACK_|VISION_|KEEP_|NODE_|XRAY_|MIN_CLIENT_VER|MINVERSION|MIN_VERSION|MASQUE_|XDRIVE_|NOISE_)')

  [[ ${#unknown[@]} -eq 0 ]] && return 0
  warn "以下环境变量本脚本不认识，已被忽略（通常是拼写或版本差异）："
  for name in "${unknown[@]}"; do
    echo -e "         ${YELLOW}${name}${NC}=${!name}"
  done
  warn "确认拼写无误后再继续；可用变量见 README「可用环境变量」一节"
  echo ""
}
check_unknown_env_vars
