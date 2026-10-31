# ==================================================
# 节点与协议矩阵管理
# ==================================================
cmd_info() {
  [[ -f "$NODE_ENV_FILE" ]] || fail "未找到节点信息文件 ${NODE_ENV_FILE}"
  echo -e "${CYAN}[+] 节点参数${NC}"
  echo "  安装时间:        ${INSTALL_TIME:-未知}"
  echo "  Reality 域名:    ${REALITY_DOMAIN}"
  echo "  CDN 域名:        ${CDN_DOMAIN}"
  echo "  VPS IP:          ${VPS_IP}"
  echo "  UUID1 (Vision):  ${UUID1}"
  echo "  UUID2 (XHTTP):   ${UUID2}"
  echo "  Public Key:      ${PUBLIC_KEY}"
  echo "  Short ID:        ${SHORT_ID}"
  echo "  XHTTP Path:      ${XHTTP_PATH}"
  echo "  VLESS Enc:       ${VLESSENC_ENCRYPTION}"
  echo "  xpadding:        ${FEATURE_XPADDING:-false}"
  [[ "${FEATURE_XPADDING:-false}" == true ]] && \
    echo "  xpadding 字段:   header=${XHTTP_PADDING_HEADER} key=${XHTTP_PADDING_KEY}"
  echo "  CDN ECH:         ${CDN_ECH_ENABLED:-false}"
  local cur_minver
  cur_minver=$(grep -o '"minClientVer"[[:space:]]*:[[:space:]]*"[^"]*"' "$XRAY_CONF" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "")
  if [[ -n "$cur_minver" ]]; then
    echo "  minClientVer:    ${cur_minver}（兼容模式：支持 mihomo/Clash/sing-box）"
  else
    echo "  minClientVer:    未设置（严格模式：Xray 内核默认）"
  fi
  echo ""
  echo -e "${CYAN}[+] 直连 UDP 节点${NC}"
  if [[ "${FEATURE_H3_DIRECT:-false}" == true ]]; then
    echo "  h3-direct:       UDP ${H3_PORT:-443}（Xray 自己监听，不经 nginx）"
  else
    echo "  h3-direct:       未启用"
  fi
  if [[ "${FEATURE_H2_DIRECT:-false}" == true ]]; then
    echo "  h2-direct:       TCP ${H2_PORT:-8445}（h3-direct 的 TCP 孪生体）"
  else
    echo "  h2-direct:       未启用"
  fi
  if [[ "${FEATURE_HY2:-false}" == true ]]; then
    if [[ "${FEATURE_HY2_H3:-false}" == true ]]; then
      echo "  Hysteria2-H3:    UDP ${HY2_H3_PORT}（无混淆，随机端口）"
      echo "    认证密码:      ${HY2_PASSWORD}"
    fi
    if [[ "${FEATURE_HY2_OBFS:-false}" == true ]]; then
      echo "  Hysteria2-obfs:  UDP ${HY2_PORT}（同一认证密码）"
      echo "    混淆:          salamander（Xray finalmask）"
      echo "    混淆密码:      ${OBFS_PASSWORD}"
      echo "    ↑ 两个密码是独立的值，客户端两处都要填对才能握手"
    fi
  else
    echo "  Hysteria2:       未启用"
  fi
  if [[ "${FEATURE_MASQUE:-false}" == true ]]; then
    echo "  MASQUE 隧道:     UDP/TCP ${MASQUE_PORT:-8447}（RFC 9484 CONNECT-IP）"
    echo "    认证账号:      user@${CDN_DOMAIN:-example.com}"
  else
    echo "  MASQUE 隧道:     未启用"
  fi
  if [[ "${FEATURE_XDRIVE:-false}" == true ]]; then
    echo "  XDRIVE 网盘代理: 已启用 (Google Drive 穿透)"
  else
    echo "  XDRIVE 网盘代理: 未启用"
  fi
  if [[ "${FEATURE_NOISE_EXP:-false}" == true ]]; then
    echo "  Noise 动态混淆:  已开启 (${NOISE_EXP_PACKET:-<b 16030100><r 32><t><c><rd 8>})"
  fi
  if [[ -f "$SYSCTL_CONF" ]]; then
    echo "  系统层调优:      已开启（${MANAGE_CMD} tuning off 可回滚）"
  else
    echo "  系统层调优:      未开启（${MANAGE_CMD} tuning on 开启）"
  fi
  echo ""
  echo -e "${YELLOW}[+] 客户端节点${NC}"
  local f="${USER_HOME:-/root}/client-config.txt"
  [[ -f "$f" ]] && cat "$f" || warn "未找到 $f"
}

cmd_sub() {
  [[ -f "$SUB_TOKEN_FILE" ]] || fail "未找到订阅 token，请先运行安装脚本"
  local token base
  token=$(tr -d '\r\n' < "$SUB_TOKEN_FILE")
  base="https://${REALITY_DOMAIN}/sub/${token}"
  echo -e "${CYAN}[+] 订阅链接${NC}"
  echo "  V2RayN (全量 base64):    ${base}/v2rayn.txt"
  echo "  V2RayN (TUN 订阅，全部节点): ${base}/v2rayn-tun.txt"
  echo "  Xray 原生 TUN 配置:      ${base}/xray-tun-{windows,linux,macos}.json  (Xray-core >= 26.9.30)"
  echo "  Shadowrocket (小火箭专属): ${base}/shadowrocket.txt"
  echo "  明文节点（备选）:        ${base}/v2rayn-raw.txt"
  echo "  Mihomo 完整分流:         ${base}/mihomo-full.yaml"
  echo "  Mihomo 完整分流(TUN 按平台): ${base}/mihomo-full-{windows,linux,macos,android}.yaml"
  echo "  Mihomo 纯节点:           ${base}/mihomo-nodes.yaml"
  echo ""
  echo -e "${YELLOW}  订阅拉不到节点时，先在该设备的浏览器里直接打开上面的链接：${NC}"
  echo "    打得开且有内容 → 客户端解析问题，改用明文订阅或手动导入单条节点"
  echo "    打不开         → 该设备到 VPS 的网络问题，与本项目配置无关"
  if command -v qrencode >/dev/null 2>&1; then
    echo ""
    echo -e "${YELLOW}[+] V2RayN 全量订阅二维码${NC}"
    qrencode -t ANSIUTF8 -m 1 "${base}/v2rayn.txt"
  fi
}

# 由 client-config.txt 生成 Xray 原生 TUN 客户端配置（Xray-core >= 26.9.30）：xray-tun-{windows,linux,macos}.json
# 用法：xray_tun_variants <client-config.txt> <输出目录>
xray_tun_variants() {
  local src="$1" outdir="$2"
  [[ -s "$src" ]] || return 0
  python3 - "$src" "$outdir" "${REALITY_DOMAIN:-}" "${CDN_DOMAIN:-}" "${VPS_IP:-}" "${BESTCF_DOMAIN:-}" <<'XTUNPY' || warn "Xray TUN 配置生成失败（不影响其它订阅）"
@@include templates/xray-tun-gen.py.tmpl
XTUNPY
}

# 按客户端平台生成 TUN 自适应的 Mihomo 完整分流配置（mihomo-full-<平台>.yaml）。
# 基础文件的 tun 段 strict-route: false、stack: mixed；各平台只改确有区别的字段：
#   windows：strict-route 开（防止 DNS 经物理网卡泄漏，Wintun 支持）
#   linux  ：strict-route + auto-redirect 开（nftables 重定向，TCP 不再进用户态协议栈，更省 CPU）
#   macos / android：保持基础值（macOS 不支持 strict-route，Android 由 VpnService 接管路由）
# 用法：mihomo_tun_variants <基础 yaml> <输出目录>
mihomo_tun_variants() {
  local src="$1" outdir="$2" p
  [[ -s "$src" ]] || return 0
  for p in windows linux macos android; do
    case "$p" in
      windows) sed 's/^  strict-route: false$/  strict-route: true/' "$src" > "${outdir}/mihomo-full-${p}.yaml" ;;
      linux)   sed -e 's/^  strict-route: false$/  strict-route: true\n  auto-redirect: true/' "$src" > "${outdir}/mihomo-full-${p}.yaml" ;;
      *)       cp "$src" "${outdir}/mihomo-full-${p}.yaml" ;;
    esac
  done
}

# 手工改过 ~/client-config.txt 后，用它把订阅文件重新生成，无需重跑安装脚本
cmd_resub() {
  [[ -f "$SUB_TOKEN_FILE" ]] || fail "未找到订阅 token，请先运行安装脚本"
  local home token subdir
  if [[ -z "${USER_HOME:-}" || ! -f "${USER_HOME}/client-config.txt" ]]; then
    for candidate in /home/ubuntu /home/opc /root; do
      if [[ -f "${candidate}/client-config.txt" ]]; then
        home="$candidate"
        break
      fi
    done
  else
    home="$USER_HOME"
  fi
  home="${home:-/root}"
  token=$(tr -d '\r\n' < "$SUB_TOKEN_FILE")
  subdir="/usr/local/nginx/html/sub/${token}"
  [[ -d "$subdir" ]] || fail "未找到订阅目录 ${subdir}"
  [[ -f "${home}/client-config.txt" ]] || fail "未找到 ${home}/client-config.txt"

  # 按节点名称升序排序
  if [[ -f "${home}/client-config.txt" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys
fpath = sys.argv[1]
with open(fpath, 'r', encoding='utf-8') as f:
    lines = [line.strip() for line in f if line.strip()]
def get_name(line):
    return line.split('#', 1)[1] if '#' in line else line
sorted_lines = sorted(lines, key=get_name)
with open(fpath, 'w', encoding='utf-8') as f:
    for line in sorted_lines:
        f.write(line + '\n')
" "${home}/client-config.txt" 2>/dev/null || true
  fi

  if [[ -f "${home}/client-config-mihomo-nodes.yaml" || -f "${home}/client-config-mihomo-full.yaml" ]] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys, re

def sort_proxies_in_file(fpath):
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            text = f.read()
        match = re.search(r'(proxies:\n)(.*?)(?=\n[a-z\-]+:|\Z)', text, re.DOTALL)
        if not match:
            return
        header = match.group(1)
        body = match.group(2)
        proxy_chunks = re.split(r'\n(?=- name:)', '\n' + body)
        proxy_chunks = [c.strip() for c in proxy_chunks if c.strip()]
        def get_proxy_name(chunk):
            m = re.search(r'^- name:\s*([^\n]+)', chunk)
            return m.group(1).strip() if m else ''
        sorted_chunks = sorted(proxy_chunks, key=get_proxy_name)
        sorted_body = '\n'.join(sorted_chunks) + '\n'
        new_text = text[:match.start()] + header + sorted_body + text[match.end():]
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write(new_text)
    except Exception:
        pass

for p in sys.argv[1:]:
    sort_proxies_in_file(p)
" "${home}/client-config-mihomo-nodes.yaml" "${home}/client-config-mihomo-full.yaml" 2>/dev/null || true
  fi

  cp "${home}/client-config.txt" "${subdir}/v2rayn-raw.txt"
  base64 "${home}/client-config.txt" | tr -d '\n' > "${subdir}/v2rayn.txt"
  [[ -f "${home}/client-config-mihomo-full.yaml" ]]  && cp "${home}/client-config-mihomo-full.yaml"  "${subdir}/mihomo-full.yaml"
  [[ -f "${home}/client-config-mihomo-nodes.yaml" ]] && cp "${home}/client-config-mihomo-nodes.yaml" "${subdir}/mihomo-nodes.yaml"
  mihomo_tun_variants "${home}/client-config-mihomo-full.yaml" "${subdir}"

  xray_tun_variants "${home}/client-config.txt" "${subdir}"

  # 重新生成 Shadowrocket 专属与 v2rayN TUN 订阅
  python3 - "${home}/client-config.txt" "${subdir}/shadowrocket-raw.txt" <<'SRPY'
import sys, urllib.parse

src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, "r", encoding="utf-8") as f:
        lines = [l.strip() for l in f if l.strip()]
except Exception:
    sys.exit(0)

sr_lines = []
for line in lines:
    p = urllib.parse.urlparse(line)
    tag = urllib.parse.unquote(p.fragment or "")
    qs = urllib.parse.parse_qs(p.query)
    q = lambda k, d="": qs.get(k, [d])[0]

    if p.scheme == "hysteria2":
        clean_qs = {k: v[0] for k, v in qs.items() if k not in ("fm", "udp")}
        new_q = urllib.parse.urlencode(clean_qs)
        sr_lines.append(f"{p.scheme}://{p.netloc}{p.path}?{new_q}#{tag}")
    elif p.scheme == "vless":
        sec = q("security", "none")
        net = q("type", "tcp")
        if net == "raw": net = "tcp"
        uid = p.username or ""
        host = p.hostname or ""
        port = p.port or 443
        sni = q("sni")
        fp = q("fp", "chrome")
        path = q("path")
        pbk = q("pbk")
        sid = q("sid")
        host_hdr = q("host")

        if "downloadSettings" in line:
            if "Reality-Up" in tag:
                sr_lines.append(f"vless://{uid}@{host}:{port}?encryption=none&security=reality&sni={sni}&fp={fp}&alpn=h2&pbk={pbk}&sid={sid}&type=xhttp&path={path}&mode=stream-up&tfo=1#{tag}-Direct")
            elif "CDN-Up" in tag:
                sr_lines.append(f"vless://{uid}@{host}:{port}?encryption=none&security=tls&sni={sni}&fp={fp}&alpn=h2&type=xhttp&host={host_hdr}&path={path}&mode=stream-up&tfo=1#{tag}-CDN")
        else:
            clean_qs = {
                "encryption": q("encryption", "none"),
                "security": sec,
                "sni": sni,
                "fp": fp,
                "type": net
            }
            if q("flow"): clean_qs["flow"] = q("flow")
            if q("alpn"): clean_qs["alpn"] = q("alpn")
            if pbk: clean_qs["pbk"] = pbk
            if sid: clean_qs["sid"] = sid
            if host_hdr: clean_qs["host"] = host_hdr
            if path: clean_qs["path"] = path
            if net == "xhttp":
                clean_qs["mode"] = q("mode", "stream-up")
            clean_qs["tfo"] = "1"
            new_q = urllib.parse.urlencode(clean_qs)
            sr_lines.append(f"vless://{uid}@{host}:{port}?{new_q}#{tag}")

with open(dst, "w", encoding="utf-8") as f:
    for s in sr_lines:
        f.write(s + "\n")
SRPY
  if [[ -s "${subdir}/shadowrocket-raw.txt" ]]; then
    base64 "${subdir}/shadowrocket-raw.txt" | tr -d '\n' > "${subdir}/shadowrocket.txt"
  fi
  cp "${home}/client-config.txt" "${subdir}/v2rayn-tun-raw.txt" || true   # v4.9.76 起 TUN 订阅含全部节点（原因见 12-subscription.sh）
  if [[ -s "${subdir}/v2rayn-tun-raw.txt" ]]; then
    base64 "${subdir}/v2rayn-tun-raw.txt" | tr -d '\n' > "${subdir}/v2rayn-tun.txt"
  fi

  info "订阅已按当前 client-config.txt 重新生成（客户端需手动更新订阅）"
  cmd_sub
}

# /etc/sysctl.d/ 里的冲突与残留检测。
# 背景：这台机器上常常跑过不止一个调优脚本。systemd-sysctl 按**文件名字典序**
# 加载，后加载的覆盖先加载的——也就是说别人的文件只要排在 99-xray-xhttp.conf
# 之后，就会静默覆盖掉本项目的值，而且没有任何报错。
# 本函数只报告，不删除任何文件：那些文件不是本项目产生的，脚本无权处置。
cmd_block() {
  local what="${1:-show}" act="${2:-}" key marker
  case "$what" in
    show|status)
      echo ""
      echo -e "${CYAN}=== 出站分流开关 ===${NC}"
      local k name
      for k in cn ads; do
        [[ "$k" == cn ]] && name="屏蔽回国 IP (geoip:cn)" || name="屏蔽广告域名 (geosite:category-ads-all)"
        if grep -q "xh-block-${k}" "$XRAY_CONF" 2>/dev/null; then
          echo -e "  ${name}：${GREEN}已开启${NC}"
        else
          echo -e "  ${name}：${YELLOW}未开启${NC}"
        fi
      done
      echo ""
      echo "用法：${MANAGE_CMD} block cn|ads on|off"
      echo "说明：回国 IP 屏蔽会让依赖本代理访问国内站点的客户端断流，仅在落地机不需要回国流量时开启。"
      echo ""
      return 0
      ;;
    cn)  key="FEATURE_BLOCK_CN";  marker="xh-block-cn" ;;
    ads) key="FEATURE_BLOCK_ADS"; marker="xh-block-ads" ;;
    *)   echo "用法: ${MANAGE_CMD} block [show|cn on|off|ads on|off]"; return 1 ;;
  esac
  [[ "$act" == on || "$act" == off ]] || { echo "用法: ${MANAGE_CMD} block ${what} on|off"; return 1; }
  [[ -f "$XRAY_CONF" ]] || fail "未找到 Xray 配置文件: $XRAY_CONF"
  local tmp="${XRAY_CONF%.json}.block-tmp.json" bak="${XRAY_CONF}.block.bak"   # 临时文件必须以 .json 结尾，Xray 靠扩展名识别格式
  python3 - "$XRAY_CONF" "$tmp" "$what" "$act" <<'BLOCKPY' || fail "改写配置失败，未做任何修改"
import re, sys
src, dst, what, act = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
marker = 'xh-block-' + what
lines = [l for l in s.split('\n') if marker not in l]          # 先清掉旧行，开 / 关都幂等
s = '\n'.join(lines)
if act == 'on':
    if what == 'ads':
        pat = re.compile(r'("geosite:category-pt"\s*\]\s*,\s*"outboundTag"\s*:\s*"block"\s*\})')
        new = '\n            , { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" } // xh-block-ads'
    else:
        pat = re.compile(r'(\{ "action": "block", "ip": \["geoip:private"\] \})')
        new = '\n                    , { "action": "block", "ip": ["geoip:cn"] } // xh-block-cn'
    s, n = pat.subn(lambda m: m.group(1) + new, s, count=1)
    if n != 1:
        sys.stderr.write('没找到插入锚点（配置不是由本脚本生成？）\n'); sys.exit(1)
open(dst, 'w', encoding='utf-8').write(s)
BLOCKPY
  if ! "$XRAY_BIN" -test -format json -config "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; fail "Xray 配置校验失败（geodata 缺少对应规则？），已放弃，未做任何修改"
  fi
  cp -a "$XRAY_CONF" "$bak"
  mv -f "$tmp" "$XRAY_CONF"; chmod 600 "$XRAY_CONF" 2>/dev/null || true
  if svc restart xray; then
    update_node_env "$key" "$([[ "$act" == on ]] && echo true || echo false)"
    info "出站分流 ${what} 已$([[ "$act" == on ]] && echo 开启 || echo 关闭)，xray 已重启"
  else
    cp -a "$bak" "$XRAY_CONF"; svc restart xray >/dev/null 2>&1 || true
    fail "xray 重启失败，已回滚到修改前的配置"
  fi
}

# Reality maxTimeDiff（毫秒）：服务端只接受客户端时间戳与本机相差不超过该值的握手，防重放。
# 参考 XTLS/REALITY README 的可选项。客户端（手机 / 电脑）系统时间偏差超过该值就连不上，需开启自动校时。
cmd_timediff() {
  local action="${1:-show}" ms="${2:-60000}"
  case "$action" in
    show|status)
      local cur
      cur=$(grep -o '"maxTimeDiff"[[:space:]]*:[[:space:]]*[0-9]*' "$XRAY_CONF" 2>/dev/null | head -1 | grep -o '[0-9]*$' || true)
      echo ""
      echo -e "${CYAN}=== Reality maxTimeDiff 状态 ===${NC}"
      if [[ -n "$cur" ]]; then
        echo -e "  当前状态:       ${GREEN}${cur} ms${NC}"
      else
        echo -e "  当前状态:       ${YELLOW}未设置${NC}（不校验客户端时间差）"
      fi
      echo -e "  本机时间同步:   $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo 未知)（yes 表示已校时）"
      echo ""
      echo -e "  ${MANAGE_CMD} timediff on [毫秒]   # 开启，默认 60000；客户端时间偏差超过它会连不上"
      echo -e "  ${MANAGE_CMD} timediff off         # 关闭"
      echo ""
      return 0
      ;;
    on|set|off) : ;;
    *) echo "用法: ${MANAGE_CMD} timediff [show|on [毫秒]|off]"; return 1 ;;
  esac
  [[ -f "$XRAY_CONF" ]] || fail "未找到 Xray 配置文件: $XRAY_CONF"
  if [[ "$action" != off ]]; then
    [[ "$ms" =~ ^[0-9]+$ && "$ms" -ge 1000 ]] || fail "毫秒数必须是 >= 1000 的整数（建议 60000）"
  fi
  local bak="${XRAY_CONF}.bak-timediff"
  cp -a "$XRAY_CONF" "$bak"
  python3 - "$XRAY_CONF" "$action" "$ms" <<'TDPY' || { mv -f "$bak" "$XRAY_CONF"; fail "改写配置失败，已恢复原配置"; }
import re, sys
cfg, action, ms = sys.argv[1:4]
t = open(cfg, encoding='utf-8').read()
t = re.sub(r',\s*"maxTimeDiff"\s*:\s*\d+', '', t)              # 先清掉旧值，开 / 关都幂等
if action != 'off':
    n = [0]
    def add(m):
        n[0] += 1
        return m.group(1) + ',\n                    "maxTimeDiff": ' + ms
    t = re.sub(r'("shortIds"\s*:\s*\[[^\]]*\])', add, t)
    if not n[0]: sys.exit(1)
open(cfg, 'w', encoding='utf-8').write(t)
TDPY
  if "$XRAY_BIN" run -test -c "$XRAY_CONF" >/dev/null 2>&1; then
    rm -f "$bak"
    if svc restart xray; then
      update_node_env "REALITY_MAX_TIME_DIFF" "$([[ "$action" == off ]] && echo "" || echo "$ms")"
      info "Reality maxTimeDiff 已$([[ "$action" == off ]] && echo 关闭 || echo "设为 ${ms} ms")，xray 已重启"
    else
      warn "xray 重启失败，正在回滚..."; cp -a "$XRAY_CONF" "${XRAY_CONF}.failed"; fail "重启失败；坏配置留在 ${XRAY_CONF}.failed，请手动检查"
    fi
  else
    warn "Xray 配置文件测试失败，正在回滚..."
    mv -f "$bak" "$XRAY_CONF"
    fail "配置测试失败，已自动恢复原配置"
  fi
}
cmd_minversion() {
  local action="${1:-show}"
  local target_ver="${2:-1.8.0}"
  case "$action" in
    show|status)
      local cur_minver
      cur_minver=$(grep -o '"minClientVer"[[:space:]]*:[[:space:]]*"[^"]*"' "$XRAY_CONF" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "")
      echo ""
      echo -e "${CYAN}=== Reality minClientVer (minversion) 状态 ===${NC}"
      if [[ -n "$cur_minver" ]]; then
        echo -e "  当前状态:       ${GREEN}${cur_minver}${NC} (兼容模式：允许 mihomo / Clash / sing-box 客户端握手)"
      else
        echo -e "  当前状态:       ${YELLOW}未设置${NC} (严格模式：使用 Xray-core 内核默认版本)"
      fi
      local env_ver="${REALITY_MIN_CLIENT_VER:-}"
      [[ -n "$env_ver" ]] && echo -e "  node.env 设定:  ${env_ver}"
      local cur_core_ver
      cur_core_ver=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')
      cur_core_ver="${cur_core_ver#v}"
      [[ -n "$cur_core_ver" ]] && echo -e "  Xray 内核版本:  ${cur_core_ver}"
      if [[ -n "$cur_core_ver" ]] && ver_ge "$cur_core_ver" "26.9.8"; then
        echo ""
        echo -e "  ${YELLOW}ℹ️ 提示：当前 Xray 内核为 v${cur_core_ver} (>= 26.9.8)${NC}"
        echo -e "  该版本在 REALITY 中启用了后量子混合密钥 (X25519MLKEM768) 握手强校验防 GFW 探测。"
        echo -e "  客户端若使用 REALITY 需支持后量子混合算法；或使用订阅中的 XHTTP / H3 / H2 / Hysteria2 节点。"
      fi
      echo ""
      echo -e "说明："
      echo -e "  • 开启兼容（1.8.0）：支持 mihomo、Clash Meta、sing-box 等非 Xray 官方客户端正常握手。"
      echo -e "  • 关闭兼容（off / default）：恢复内核最新默认限制，非同代 Xray 客户端将握手失败。"
      echo -e "  • 快捷命令:"
      echo -e "      ${MANAGE_CMD} minversion on [版本号]     # 开启兼容模式（1.8.0，默认关闭）"
      echo -e "      ${MANAGE_CMD} minversion off            # 切换为严格模式（内核默认）"
      echo -e "      ${MANAGE_CMD} minversion set <版本号>   # 指定具体最低版本"
      echo ""
      ;;
    on|set)
      local ver="$target_ver"
      [[ -z "$ver" || "$ver" == "on" ]] && ver="1.8.0"
      [[ -f "$XRAY_CONF" ]] || fail "未找到 Xray 配置文件: $XRAY_CONF"

      local bak="${XRAY_CONF}.bak-minver"
      cp -a "$XRAY_CONF" "$bak"

      python3 -c "
import re, sys

cfg = '$XRAY_CONF'
ver = '$ver'
with open(cfg, 'r', encoding='utf-8') as f:
    text = f.read()

if re.search(r'\"minClientVer\"\s*:', text):
    text = re.sub(r'(\"minClientVer\"\s*:\s*)\"[^\"]*\"', lambda m: f'{m.group(1)}\"{ver}\"', text, count=1)
else:
    m = re.search(r'(\"shortIds\"\s*:\s*\[[^\]]*\])', text)
    if m:
        text = text[:m.end()] + f',\n                    \"minClientVer\": \"{ver}\"' + text[m.end():]
    else:
        sys.exit(1)

with open(cfg, 'w', encoding='utf-8') as f:
    f.write(text)
" 2>/dev/null || {
        if grep -q '"minClientVer"' "$XRAY_CONF"; then
          sed -i -E "s/\"minClientVer\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"minClientVer\": \"${ver}\"/" "$XRAY_CONF"
        fi
      }

      if "$XRAY_BIN" run -test -c "$XRAY_CONF" >/dev/null 2>&1; then
        rm -f "$bak"
        svc restart xray
        update_node_env "REALITY_MIN_CLIENT_VER" "$ver"
        info "已成功开启 Reality 兼容模式，minClientVer 设为: ${ver}，并重启 xray 服务"
      else
        warn "Xray 配置文件测试失败，正在回滚..."
        mv -f "$bak" "$XRAY_CONF"
        fail "配置测试失败，已自动恢复原配置"
      fi
      ;;
    off|default|none)
      [[ -f "$XRAY_CONF" ]] || fail "未找到 Xray 配置文件: $XRAY_CONF"

      local bak="${XRAY_CONF}.bak-minver"
      cp -a "$XRAY_CONF" "$bak"

      python3 -c "
import re, sys

cfg = '$XRAY_CONF'
with open(cfg, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(r',\s*(//[^\n]*\n\s*)?\"minClientVer\"\s*:\s*\"[^\"]*\"', '', text, count=1)
text = re.sub(r'\"minClientVer\"\s*:\s*\"[^\"]*\"\s*,?', '', text, count=1)

with open(cfg, 'w', encoding='utf-8') as f:
    f.write(text)
" 2>/dev/null || true

      if "$XRAY_BIN" run -test -c "$XRAY_CONF" >/dev/null 2>&1; then
        rm -f "$bak"
        svc restart xray
        update_node_env "REALITY_MIN_CLIENT_VER" "default"
        info "已关闭 minClientVer，已恢复为 Xray-core 内核默认版本（严格模式），并重启 xray 服务"
      else
        warn "Xray 配置文件测试失败，正在回滚..."
        mv -f "$bak" "$XRAY_CONF"
        fail "配置测试失败，已自动恢复原配置"
      fi
      ;;
    *)
      if [[ "$action" =~ ^[0-9]+ ]]; then
        cmd_minversion set "$action"
      else
        echo "用法: ${MANAGE_CMD} minversion [show|on|off|set <ver>|<ver>]"
        echo "  ${MANAGE_CMD} minversion show        查看当前 minClientVer 配置状态"
        echo "  ${MANAGE_CMD} minversion on          开启兼容模式（设为 1.8.0，支持 mihomo/Clash）"
        echo "  ${MANAGE_CMD} minversion off         恢复内核默认（严格模式）"
        echo "  ${MANAGE_CMD} minversion 1.8.0       设为指定版本"
      fi
      ;;
  esac
}

sync_client_configs_ech() {
  local enable="$1"
  local query="${2:-cloudflare-ech.com+https://223.5.5.5/dns-query}"
  python3 -c "
import os, sys, re, urllib.parse, json, yaml

enable = ('$enable' == 'true')
query = '$query'
ech_query_enc = urllib.parse.quote(query, safe='')
user_homes = ['${USER_HOME:-/home/ubuntu}', '/home/ubuntu', '/home/opc', '/root']
seen = set()

for home in user_homes:
    if not home or home in seen or not os.path.isdir(home):
        continue
    seen.add(home)
    txt_file = os.path.join(home, 'client-config.txt')
    nodes_file = os.path.join(home, 'client-config-mihomo-nodes.yaml')
    full_file = os.path.join(home, 'client-config-mihomo-full.yaml')

    if os.path.isfile(txt_file):
        with open(txt_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        new_lines = []
        for line in lines:
            line_str = re.sub(r'\s*([&?])\s*', r'\1', line.strip())
            if not line_str:
                continue
            # v4.9.29：按节点名（URI fragment）不区分大小写匹配。v4.9.21 改名后节点名是
            # VLESS-Reality-Up-CDN-Down，原先按小写 'reality-up-cdn-down' 匹配不上，
            # 分离节点被当成普通 CDN 节点在顶层加了 &ech=（那是 Reality 腿，不该有）。
            node_name = urllib.parse.unquote(line_str.rsplit('#', 1)[-1]).lower()
            is_split = 'reality-up-cdn-down' in node_name
            if not is_split and ('-cdn-' in node_name or 'cdn-up' in node_name):
                if enable:
                    if '&ech=' in line_str:
                        line_str = re.sub(r'&ech=[^&#]*', f'&ech={ech_query_enc}', line_str)
                    else:
                        line_str = re.sub(r'(&security=tls)', f'\\g<1>&ech={ech_query_enc}', line_str)
                else:
                    line_str = re.sub(r'&ech=[^&#]*', '', line_str)
            elif is_split:
                m = re.search(r'&extra=([^#]+)', line_str)
                if m:
                    try:
                        extra_json = json.loads(urllib.parse.unquote(m.group(1)))
                        ds_tls = extra_json.get('downloadSettings', {}).get('tlsSettings', {})
                        if enable:
                            # 放进 JSON 的必须是原文：整个 extra 随后会整体 quote 一次，
                            # 塞已编码的串会变成双重编码（%252B），客户端解不出 DoH 地址。
                            ds_tls['ech'] = urllib.parse.unquote(ech_query_enc)
                        else:
                            ds_tls.pop('ech', None)
                        new_extra_enc = urllib.parse.quote(json.dumps(extra_json, separators=(',', ':')), safe='')
                        line_str = line_str[:m.start()] + f'&extra={new_extra_enc}' + line_str[m.end():]
                    except Exception:
                        pass
            line_str = re.sub(r'\s+&', '&', line_str)
            line_str = re.sub(r'&\s+', '&', line_str)
            new_lines.append(line_str.strip() + '\n')
        with open(txt_file, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

    for yfile in [nodes_file, full_file]:
        if os.path.isfile(yfile):
            with open(yfile, 'r', encoding='utf-8') as f:
                cfg = yaml.safe_load(f)
            if not isinstance(cfg, dict):
                continue
            for p in cfg.get('proxies', []):
                name = p.get('name', '')
                lname = name.lower()
                if ('-cdn-' in lname or 'cdn-up' in lname) and 'reality-up-cdn-down' not in lname:
                    if enable:
                        p['ech-opts'] = {'enable': True, 'query-server-name': 'cloudflare-ech.com'}
                    else:
                        p.pop('ech-opts', None)
                elif 'reality-up-cdn-down' in lname:
                    xopts = p.get('xhttp-opts', {})
                    ds = xopts.get('download-settings', {})
                    if enable:
                        ds['ech-opts'] = {'enable': True, 'query-server-name': 'cloudflare-ech.com'}
                    else:
                        ds.pop('ech-opts', None)
            with open(yfile, 'w', encoding='utf-8') as f:
                yaml.dump(cfg, f, allow_unicode=True, sort_keys=False)
" 2>/dev/null || true
  cmd_resub
}

sync_client_configs_cdnh2() {
  local enable="$1"
  # 优先从备用节点库取节点行与 Mihomo 条目（和全新安装逐字一致）。没有库的旧安装才走下面的克隆兜底。
  if [[ -f "${ALL_STORE_DIR}/client-config.txt" ]]; then
    local _act=off; [[ "$enable" == true ]] && _act=on
    backup_node_sync_files "VLESS-XHTTP-CDN-H2" "$_act" || warn "VLESS-XHTTP-CDN-H2 的客户端文件同步未完成（原因见上）"
    cmd_resub
    return 0
  fi
  python3 -c "
import os, sys, re, yaml, copy

enable = ('$enable' == 'true')
user_homes = ['${USER_HOME:-/home/ubuntu}', '/home/ubuntu', '/home/opc', '/root']
seen = set()

for home in user_homes:
    if not home or home in seen or not os.path.isdir(home):
        continue
    seen.add(home)
    txt_file = os.path.join(home, 'client-config.txt')
    nodes_file = os.path.join(home, 'client-config-mihomo-nodes.yaml')
    full_file = os.path.join(home, 'client-config-mihomo-full.yaml')

    if os.path.isfile(txt_file):
        with open(txt_file, 'r', encoding='utf-8') as f:
            lines = [l.strip() for l in f if l.strip()]
        new_lines = []
        has_h2 = any('#VLESS-XHTTP-CDN-H2' in l for l in lines)
        if enable:
            if not has_h2:
                added = False
                for line in lines:
                    if '#VLESS-XHTTP-CDN-H3' in line:
                        h2_line = line.replace('alpn=h3', 'alpn=h2').replace('#VLESS-XHTTP-CDN-H3', '#VLESS-XHTTP-CDN-H2')
                        new_lines.append(h2_line)
                        added = True
                    elif not added and ('#VLESS-XHTTP-Direct-H3' in line or '#VLESS-Reality' in line):
                        # 兜底：从直连节点提取参数构造
                        h2_line = line.replace('alpn=h3', 'alpn=h2')
                        h2_line = re.sub(r'@[^:]+:[0-9]+', '@${CDN_DOMAIN}:443', h2_line)
                        h2_line = re.sub(r'sni=[^&]+', 'sni=${CDN_DOMAIN}', h2_line)
                        h2_line = re.sub(r'#[^#]+$', '#VLESS-XHTTP-CDN-H2', h2_line)
                        if '&host=' not in h2_line:
                            h2_line = h2_line.replace('&path=', '&host=${CDN_DOMAIN}&path=')
                        new_lines.append(h2_line)
                        added = True
                    new_lines.append(line)
            else:
                new_lines = lines
        else:
            new_lines = [l for l in lines if '#VLESS-XHTTP-CDN-H2' not in l]
        with open(txt_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(new_lines) + '\n')

    for yfile in [nodes_file, full_file]:
        if os.path.isfile(yfile):
            with open(yfile, 'r', encoding='utf-8') as f:
                cfg = yaml.safe_load(f)
            if not isinstance(cfg, dict):
                continue
            proxies = cfg.get('proxies', [])
            has_h2 = any('VLESS-XHTTP-CDN-H2' in p.get('name', '') for p in proxies)
            if enable and not has_h2:
                new_proxies = []
                added = False
                for p in proxies:
                    if 'VLESS-XHTTP-CDN-H3' in p.get('name', ''):
                        h2_p = copy.deepcopy(p)
                        h2_p['name'] = p['name'].replace('VLESS-XHTTP-CDN-H3', 'VLESS-XHTTP-CDN-H2')
                        h2_p['alpn'] = ['h2']
                        new_proxies.append(h2_p)
                        added = True
                    elif not added and ('VLESS-XHTTP-Direct-H3' in p.get('name', '') or 'VLESS-Reality' in p.get('name', '')):
                        h2_p = copy.deepcopy(p)
                        h2_p['name'] = 'VLESS-XHTTP-CDN-H2'
                        h2_p['server'] = '${CDN_DOMAIN}'
                        h2_p['port'] = 443
                        h2_p['servername'] = '${CDN_DOMAIN}'
                        h2_p['alpn'] = ['h2']
                        if 'xhttp-opts' in h2_p:
                            h2_p['xhttp-opts']['host'] = '${CDN_DOMAIN}'
                            h2_p['xhttp-opts']['mode'] = 'stream-up'
                        new_proxies.append(h2_p)
                        added = True
                    new_proxies.append(p)
                cfg['proxies'] = new_proxies
            elif not enable and has_h2:
                cfg['proxies'] = [p for p in proxies if 'VLESS-XHTTP-CDN-H2' not in p.get('name', '')]
            with open(yfile, 'w', encoding='utf-8') as f:
                yaml.dump(cfg, f, allow_unicode=True, sort_keys=False)
" 2>/dev/null || true
  cmd_resub
}

cmd_cdnh2() {
  local action="${1:-show}"
  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== CDN TCP(h2) 节点状态 ===${NC}"
      local cur_h2="${FEATURE_CDN_H2:-false}"
      if [[ "$cur_h2" == "true" ]]; then
        echo -e "  当前状态:       ${GREEN}已开启 (Enabled)${NC}"
      else
        echo -e "  当前状态:       ${YELLOW}未开启 (Disabled)${NC}"
      fi
      local cdn_domain="${CDN_DOMAIN:-}"
      if [[ -n "$cdn_domain" ]]; then
        echo -e "  CDN 域名:       ${cdn_domain}"
      fi
      echo ""
      echo -e "说明："
      echo -e "  • 走 TCP 443 的 VLESS-XHTTP-CDN-H2 节点，经 CDN 的 TCP(h2) 节点，默认开启；不需要时用 xh cdnh2 off 关闭。"
      echo -e "  • 快捷命令:"
      echo -e "      ${MANAGE_CMD} cdnh2 on       # 开启 CDN TCP(h2) 节点并同步更新订阅"
      echo -e "      ${MANAGE_CMD} cdnh2 off      # 关闭 CDN TCP(h2) 节点并恢复精简订阅"
      echo ""
      ;;
    on)
      info "正在开启 CDN TCP(h2) 节点..."
      update_node_env "FEATURE_CDN_H2" "true"
      export FEATURE_CDN_H2=true
      sync_client_configs_cdnh2 "true"
      info "CDN TCP(h2) 节点已成功开启并同步更新订阅！"
      ;;
    off)
      info "正在关闭 CDN TCP(h2) 节点..."
      update_node_env "FEATURE_CDN_H2" "false"
      export FEATURE_CDN_H2=false
      sync_client_configs_cdnh2 "false"
      info "CDN TCP(h2) 节点已成功关闭并恢复精简订阅！"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} cdnh2 [show|on|off]"
      ;;
  esac
}

sync_client_configs_cdnh3() {
  local enable="$1"
  # 优先从备用节点库取节点行与 Mihomo 条目（和全新安装逐字一致）。没有库的旧安装才走下面的克隆兜底。
  if [[ -f "${ALL_STORE_DIR}/client-config.txt" ]]; then
    local _act=off; [[ "$enable" == true ]] && _act=on
    backup_node_sync_files "VLESS-XHTTP-CDN-H3" "$_act" || warn "VLESS-XHTTP-CDN-H3 的客户端文件同步未完成（原因见上）"
    cmd_resub
    return 0
  fi
  python3 -c "
import os, sys, re, yaml, copy

enable = ('$enable' == 'true')
user_homes = ['${USER_HOME:-/home/ubuntu}', '/home/ubuntu', '/home/opc', '/root']
seen = set()

for home in user_homes:
    if not home or home in seen or not os.path.isdir(home):
        continue
    seen.add(home)
    txt_file = os.path.join(home, 'client-config.txt')
    nodes_file = os.path.join(home, 'client-config-mihomo-nodes.yaml')
    full_file = os.path.join(home, 'client-config-mihomo-full.yaml')

    if os.path.isfile(txt_file):
        with open(txt_file, 'r', encoding='utf-8') as f:
            lines = [l.strip() for l in f if l.strip()]
        new_lines = []
        has_h3 = any('#VLESS-XHTTP-CDN-H3' in l for l in lines)
        if enable:
            if not has_h3:
                added = False
                for line in lines:
                    new_lines.append(line)
                    if '#VLESS-XHTTP-CDN-H2' in line:
                        h3_line = line.replace('alpn=h2,http%2F1.1', 'alpn=h3').replace('alpn=h2,h3', 'alpn=h3').replace('alpn=h2', 'alpn=h3').replace('#VLESS-XHTTP-CDN-H2', '#VLESS-XHTTP-CDN-H3')
                        new_lines.append(h3_line)
                        added = True
                if not added:
                    for line in lines:
                        if '#VLESS-XHTTP-Direct-H3' in line:
                            h3_line = line.replace('${REALITY_DOMAIN}', '${CDN_DOMAIN}').replace('${VPS_IP}', '${CDN_DOMAIN}').replace(':${H3_PORT}', ':443').replace('#VLESS-XHTTP-Direct-H3', '#VLESS-XHTTP-CDN-H3')
                            new_lines.append(h3_line)
                        new_lines.append(line)
            else:
                new_lines = lines
        else:
            new_lines = [l for l in lines if '#VLESS-XHTTP-CDN-H3' not in l]
        with open(txt_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(new_lines) + '\n')

    for yfile in [nodes_file, full_file]:
        if os.path.isfile(yfile):
            with open(yfile, 'r', encoding='utf-8') as f:
                cfg = yaml.safe_load(f)
            if not isinstance(cfg, dict):
                continue
            proxies = cfg.get('proxies', [])
            has_h3 = any('VLESS-XHTTP-CDN-H3' in p.get('name', '') for p in proxies)
            if enable and not has_h3:
                new_proxies = []
                for p in proxies:
                    new_proxies.append(p)
                    if 'VLESS-XHTTP-CDN-H2' in p.get('name', ''):
                        h3_p = copy.deepcopy(p)
                        h3_p['name'] = p['name'].replace('VLESS-XHTTP-CDN-H2', 'VLESS-XHTTP-CDN-H3')
                        h3_p['alpn'] = ['h3']
                        new_proxies.append(h3_p)
                cfg['proxies'] = new_proxies
            elif not enable and has_h3:
                cfg['proxies'] = [p for p in proxies if 'VLESS-XHTTP-CDN-H3' not in p.get('name', '')]
            with open(yfile, 'w', encoding='utf-8') as f:
                yaml.dump(cfg, f, allow_unicode=True, sort_keys=False)
" 2>/dev/null || true
  cmd_resub
}

cmd_cdnh3() {
  local action="${1:-show}"
  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== CDN QUIC(h3) 节点状态 ===${NC}"
      local cur_h3="${FEATURE_CDN_H3:-false}"
      if [[ "$cur_h3" == "true" ]]; then
        echo -e "  当前状态:       ${GREEN}已开启 (Enabled)${NC}"
      else
        echo -e "  当前状态:       ${YELLOW}未开启 (Disabled)${NC}"
      fi
      local cdn_domain="${CDN_DOMAIN:-}"
      if [[ -n "$cdn_domain" ]]; then
        echo -e "  CDN 域名:       ${cdn_domain}"
      fi
      echo ""
      echo -e "说明："
      echo -e "  • 开启此项可生成走 UDP 443 (HTTP/3 / QUIC) 的 VLESS-XHTTP-CDN-H3 节点，默认开启；不需要时用 xh cdnh3 off 关闭。"
      echo -e "  • 快捷命令:"
      echo -e "      ${MANAGE_CMD} cdnh3 on       # 开启 CDN QUIC(h3) 节点并同步更新订阅"
      echo -e "      ${MANAGE_CMD} cdnh3 off      # 关闭 CDN QUIC(h3) 节点并恢复精简订阅"
      echo ""
      ;;
    on)
      info "正在开启 CDN QUIC(h3) 节点..."
      update_node_env "FEATURE_CDN_H3" "true"
      export FEATURE_CDN_H3=true
      sync_client_configs_cdnh3 "true"
      info "CDN QUIC(h3) 节点已成功开启并同步更新订阅！"
      ;;
    off)
      info "正在关闭 CDN QUIC(h3) 节点..."
      update_node_env "FEATURE_CDN_H3" "false"
      export FEATURE_CDN_H3=false
      sync_client_configs_cdnh3 "false"
      info "CDN QUIC(h3) 节点已成功关闭并恢复精简订阅！"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} cdnh3 [show|on|off]"
      ;;
  esac
}

cmd_ech() {
  local action="${1:-show}"
  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== Cloudflare CDN ECH (Encrypted Client Hello) 状态 ===${NC}"
      local cur_ech="${CDN_ECH_ENABLED:-false}"
      if [[ "$cur_ech" == "true" ]]; then
        echo -e "  当前状态:       ${GREEN}已开启 (Enabled)${NC}"
        echo -e "  DoH 查询端点:   ${CDN_ECH_QUERY:-cloudflare-ech.com+https://223.5.5.5/dns-query}"
      else
        echo -e "  当前状态:       ${YELLOW}未开启 (Disabled)${NC}"
      fi
      local cdn_domain="${CDN_DOMAIN:-}"
      if [[ -n "$cdn_domain" ]]; then
        echo -e "  CDN 域名:       ${cdn_domain}"
        echo -n "  Cloudflare 记录: "
        local ech_probe=""
        if command -v dig >/dev/null 2>&1; then
          ech_probe=$(dig +short HTTPS "$cdn_domain" @1.1.1.1 2>/dev/null | grep -o 'ech=[^ ]*' || true)
        fi
        if [[ -n "$ech_probe" ]]; then
          echo -e "${GREEN}检测到有效 ECH 记录${NC} (${ech_probe:0:32}...)"
        else
          echo -e "${YELLOW}未检测到 ECH 记录 (请在 Cloudflare SSL/TLS 边缘证书中开启 ECH)${NC}"
        fi
      else
        echo -e "  CDN 域名:       ${YELLOW}未配置${NC}"
      fi
      echo ""
      echo -e "说明："
      echo -e "  • ECH 加密 TLS ClientHello 中的 SNI，将真实 CDN 域名隐藏在 cloudflare-ech.com 之后。"
      echo -e "  • 开启后自动更新全套客户端配置与订阅 (v2rayN / Mihomo / Clash / v2rayNG)。"
      echo -e "  • 快捷命令:"
      echo -e "      ${MANAGE_CMD} ech on       # 开启 CDN ECH 并同步更新订阅"
      echo -e "      ${MANAGE_CMD} ech off      # 关闭 CDN ECH 并恢复标准 TLS 订阅"
      echo ""
      ;;
    on)
      info "正在开启 CDN ECH..."
      local cdn_query="${2:-cloudflare-ech.com+https://223.5.5.5/dns-query}"
      update_node_env "FEATURE_CDN_ECH" "true"
      update_node_env "CDN_ECH_ENABLED" "true"
      update_node_env "CDN_ECH_QUERY" "$cdn_query"
      export FEATURE_CDN_ECH=true
      export CDN_ECH_ENABLED=true
      export CDN_ECH_QUERY="$cdn_query"
      sync_client_configs_ech "true" "$cdn_query"
      info "CDN ECH 已成功开启并同步更新订阅！"
      ;;
    off)
      info "正在关闭 CDN ECH..."
      update_node_env "FEATURE_CDN_ECH" "true"
      update_node_env "CDN_ECH_ENABLED" "false"
      update_node_env "CDN_ECH_QUERY" ""
      export FEATURE_CDN_ECH=true
      export CDN_ECH_ENABLED=false
      export CDN_ECH_QUERY=""
      sync_client_configs_ech "false" ""
      info "CDN ECH 已成功关闭并恢复标准订阅！"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} ech [show|on|off]"
      ;;
  esac
}
backup_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

backup_store_check() {
  [[ -f "${ALL_STORE_DIR}/client-config.txt" ]] || fail "缺少备用节点库 ${ALL_STORE_DIR}（本机由旧版安装脚本部署，或安装时生成失败，见 ${STATE_DIR}/all-render.log）。需用最新安装命令重新部署一次才有这些开关。"
}

# 把一条节点加进 / 移出本机的 client-config.txt 与两份 Mihomo yaml。
# $1 = 节点名（链接 # 后面的名字，不含 NODE_SUFFIX），$2 = on|off
# 先在内存里算好所有文件的新内容，全部成功才写盘（逐个 tmp + rename）。失败返回非零，不留半改状态。
# 返回 0 = 已处理，2 = 节点库里没有该节点（on）或本机没有该节点（off）。
backup_node_sync_files() {
  python3 - "$ALL_STORE_DIR" "$1" "$2" "${USER_HOME:-/home/ubuntu}" /home/ubuntu /home/opc /root <<'SYNCPY'
import copy, os, sys

try:
    import yaml
except ImportError:
    sys.stderr.write('缺少 python3-yaml，无法同步 Mihomo 配置\n')
    sys.exit(1)

store, name, act = sys.argv[1:4]
homes = sys.argv[4:]
enable = (act == 'on')

def frag(line):
    return line.rsplit('#', 1)[-1]

def match(line):
    if frag(line).startswith(name):
        return True
    if name in ('Hysteria2-TLS-BBR-Salamander', 'Hysteria2-Obfs-Direct') and any(frag(line).startswith(x) for x in ('Hysteria2-TLS-BBR-Salamander', 'Hysteria2-Obfs-Direct')):
        return True
    return False

def insert_pos(all_items, idx, live_keys, key):
    """新节点放在节点库顺序里「前一个本机已有的节点」之后，都没有就放最前。"""
    for prev in reversed(all_items[:idx]):
        k = key(prev)
        if k in live_keys:
            return live_keys.index(k) + 1
    return 0

pending = []      # (路径, 新内容)
found_any = False
seen = set()
try:
    for home in homes:
        if not home or home in seen or not os.path.isdir(home):
            continue
        seen.add(home)

        tf = os.path.join(home, 'client-config.txt')
        sf = os.path.join(store, 'client-config.txt')
        if os.path.isfile(tf) and os.path.isfile(sf):
            all_lines = [l.strip() for l in open(sf, encoding='utf-8') if l.strip()]
            live = [l.strip() for l in open(tf, encoding='utf-8') if l.strip()]
            has = any(match(l) for l in live)
            if enable:
                src = [l for l in all_lines if match(l)]
                if not src:
                    sys.stderr.write('节点库里没有 %s（节点被改过名？）\n' % name)
                    sys.exit(2)
                found_any = True
                if not has:
                    pos = insert_pos(all_lines, all_lines.index(src[0]), [frag(l) for l in live], frag)
                    live.insert(pos, src[0])
                    pending.append((tf, '\n'.join(live) + '\n'))
            else:
                if has:
                    found_any = True
                    live = [l for l in live if not match(l)]
                    pending.append((tf, '\n'.join(live) + '\n'))

        for fname in ('client-config-mihomo-nodes.yaml', 'client-config-mihomo-full.yaml'):
            if name.startswith('VLESS-Reality-XHTTP'):
                continue    # Reality-XHTTP 与最新版 Mihomo(Clash) 不兼容，不同步进 Mihomo 配置
            lf = os.path.join(home, fname)
            sf = os.path.join(store, fname)
            if not (os.path.isfile(lf) and os.path.isfile(sf)):
                continue
            live = yaml.safe_load(open(lf, encoding='utf-8'))
            ref = yaml.safe_load(open(sf, encoding='utf-8'))
            if not isinstance(live, dict) or not isinstance(ref, dict):
                raise ValueError('%s 不是有效的 Mihomo 配置' % lf)
            lp = live.setdefault('proxies', [])
            rp = ref.get('proxies', [])
            pm = lambda p: str(p.get('name', '')).startswith(name)
            has = any(pm(p) for p in lp)
            changed = False
            if enable and not has:
                src = [p for p in rp if pm(p)]
                if not src:
                    continue
                p = copy.deepcopy(src[0])
                names = [x.get('name') for x in lp]
                lp.insert(insert_pos(rp, rp.index(src[0]), names, lambda x: x.get('name')), p)
                ref_groups = {g.get('name'): g for g in (ref.get('proxy-groups') or []) if isinstance(g, dict)}
                for g in (live.get('proxy-groups') or []):
                    r = ref_groups.get(g.get('name'))
                    if r and isinstance(r.get('proxies'), list) and isinstance(g.get('proxies'), list) and p['name'] in r['proxies']:
                        if p['name'] not in g['proxies']:
                            i = r['proxies'].index(p['name'])
                            g['proxies'].insert(insert_pos(r['proxies'], i, g['proxies'], lambda x: x), p['name'])
                changed = True
            elif not enable and has:
                gone = [p.get('name') for p in lp if pm(p)]
                live['proxies'] = [p for p in lp if not pm(p)]
                for g in (live.get('proxy-groups') or []):
                    if isinstance(g.get('proxies'), list):
                        g['proxies'] = [n for n in g['proxies'] if n not in gone]
                changed = True
            if changed:
                pending.append((lf, yaml.dump(live, allow_unicode=True, sort_keys=False)))
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write('同步客户端文件失败：%s\n' % e)
    sys.exit(1)

if not enable and not found_any and not pending:
    sys.stderr.write('本机的客户端文件里没有 %s，无需移除\n' % name)
    sys.exit(2)

try:
    for path, content in pending:
        tmp = path + '.xh-new'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(content)
        st = os.stat(path)
        os.chmod(tmp, st.st_mode & 0o7777)
        try:
            os.chown(tmp, st.st_uid, st.st_gid)
        except PermissionError:
            pass
        os.replace(tmp, path)
except Exception as e:
    sys.stderr.write('写入客户端文件失败：%s\n' % e)
    sys.exit(1)
SYNCPY
}

# 往 / 从线上 Xray 配置里加一条服务端入站。入站文本来自节点库，用成对的 // 注释标记包起来，
# 关闭时按标记整块删掉，配置字节级还原。安装脚本（09）也用同样的标记写入这两条入站。
# $1 = h2direct|hy2obfs，$2 = on|off，$3 = 端口（off 时用来发现「没有标记但端口已在配置里」的情况）
# 返回 0 = 已改并重启成功，3 = 无需改动，其余 = 失败（已回滚，原因已打印）。
backup_inbound_edit() {
  local key="$1" act="$2" port="$3" tmp="${XRAY_CONF%.json}.bk-tmp.json" bak="${XRAY_CONF}.bk.bak" rc err   # 临时文件必须以 .json 结尾
  [[ -f "$XRAY_CONF" ]] || { backup_error "未找到 Xray 配置文件: $XRAY_CONF"; return 1; }
  python3 - "$XRAY_CONF" "$tmp" "${ALL_STORE_DIR}/inbound-${key}.json" "$key" "$act" "$port" <<'INBPY'
import re, sys

src, dst, store, key, act, port = sys.argv[1:7]
s = open(src, encoding='utf-8').read()
# port 参数以 tag: 开头时按入站 tag 判断
pat = ('"tag"\\s*:\\s*"%s' % re.escape(port[4:])) if port.startswith('tag:') else ('"port"\\s*:\\s*%s\\b' % re.escape(port))
begin = '        // >>xh:' + key
end = '        // <<xh:' + key
has = ('// >>xh:' + key) in s

def inbounds_close(s):
    """返回 "inbounds" 数组结尾 ] 的下标（跳过字符串与 // /* */ 注释）。"""
    i, n, depth = 0, len(s), 0
    target = None
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n and s[j] != '"':
                j += 2 if s[j] == '\\' else 1
            tok = s[i + 1:j]
            i = j + 1
            if target is None and depth == 1 and tok == 'inbounds':
                k = i
                while k < n and s[k] in ' \t\r\n':
                    k += 1
                if k < n and s[k] == ':':
                    k += 1
                    while k < n and s[k] in ' \t\r\n':
                        k += 1
                    if k < n and s[k] == '[':
                        depth += 1
                        target = depth
                        i = k + 1
            continue
        if s.startswith('//', i):
            while i < n and s[i] != '\n':
                i += 1
            continue
        if s.startswith('/*', i):
            i = s.index('*/', i) + 2
            continue
        if c in '{[':
            depth += 1
        elif c in '}]':
            if c == ']' and target is not None and depth == target:
                return i
            depth -= 1
        i += 1
    return -1

def strip_comments(t):
    return re.sub(r'(?m)^\s*//.*$', '', t)

if act == 'off':
    if not has:
        if re.search(pat, strip_comments(s)):
            sys.stderr.write('配置里有 %s 的入站，但没有 xh 标记（不是由 xh 开关写入）。请手动删除该入站后再关闭。\n' % port)
            sys.exit(4)
        sys.exit(3)
    a = s.index('\n' + begin)
    b = s.index(end, a) + len(end)
    s = s[:a] + s[b:]
else:
    if has:
        sys.exit(3)
    if re.search(pat, strip_comments(s)):
        sys.stderr.write('配置里已经有 %s 的入站（不是由 xh 开关写入），不重复添加。\n' % port)
        sys.exit(4)
    text = open(store, encoding='utf-8').read().rstrip('\n')
    pos = inbounds_close(s)
    if pos < 0:
        sys.stderr.write('没找到 inbounds 数组\n')
        sys.exit(1)
    while pos > 0 and s[pos - 1] in ' \t\r\n':
        pos -= 1
    s = s[:pos] + '\n' + begin + '\n' + text + '\n' + end + '\n' + s[pos:]
open(dst, 'w', encoding='utf-8').write(s)
INBPY
  rc=$?
  [[ $rc -eq 3 ]] && return 3
  if [[ $rc -ne 0 ]]; then rm -f "$tmp"; backup_error "改写配置失败（代码 ${rc}），未做任何修改"; return 1; fi
  if ! err=$("$XRAY_BIN" -test -format json -config "$tmp" 2>&1); then
    rm -f "$tmp"; backup_error "Xray 配置校验失败，已放弃，未做任何修改。最后几行输出："; echo "$err" | tail -n 5 >&2; return 1
  fi
  cp -a "$XRAY_CONF" "$bak"
  chown --reference="$XRAY_CONF" "$tmp" 2>/dev/null || true
  chmod --reference="$XRAY_CONF" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$XRAY_CONF" || { backup_error "无法替换 $XRAY_CONF"; return 1; }
  if ! svc restart xray; then
    cp -a "$bak" "$XRAY_CONF"
    if svc restart xray >/dev/null 2>&1; then
      backup_error "xray 重启失败，已回滚到修改前的配置并重新启动"
    else
      backup_error "xray 重启失败，回滚后也无法启动！请立即检查：journalctl -u xray -n 30"
    fi
    return 1
  fi
  return 0
}

# 放行端口（只开不关：关闭节点时保留规则，和安装脚本一致）。$1 = tcp|udp，$2 = 端口，$3 = 是否加 QUIC 握手限速
# 有规则没写进去时打印警告，不再把失败当成功。
backup_open_port() {
  local proto="$1" port="$2" qdos="${3:-}" ipt failed=0
  for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    "$ipt" -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || "$ipt" -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || failed=1
    if [[ -n "$qdos" ]]; then
      "$ipt" -C INPUT -p udp --dport "$port" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 50/sec --hashlimit-burst 100 --hashlimit-mode srcip --hashlimit-name "hy_qdos_${port}" -j DROP 2>/dev/null || \
        "$ipt" -I INPUT 1 -p udp --dport "$port" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 50/sec --hashlimit-burst 100 --hashlimit-mode srcip --hashlimit-name "hy_qdos_${port}" -j DROP 2>/dev/null || failed=1
    fi
  done
  if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | grep -q "^Status: active"; then
    ufw allow "${port}/${proto}" >/dev/null 2>&1 || failed=1
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || failed=1
  elif command -v iptables-save >/dev/null 2>&1 && [[ -d /etc/iptables ]]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || failed=1
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || failed=1
  fi
  [[ $failed -eq 0 ]] || warn "端口 ${proto^^} ${port} 的防火墙规则没有全部写入或保存，请手动检查：iptables -S INPUT | grep ${port}"
}

backup_port_busy() {   # $1 = tcp|udp，$2 = 端口，$3 = key (可选，如 h2direct, hy2h3, hy2obfs, masque)
  local proto="$1" port="$2" key="${3:-}"
  local flag="-ltnpH"
  [[ "$proto" == udp ]] && flag="-lunpH"

  local listeners
  listeners=$(ss $flag "sport = :$port" 2>/dev/null)
  [[ -z "$listeners" ]] && return 1

  # 检查是否有非 xray 进程占用
  local non_xray
  non_xray=$(echo "$listeners" | grep -v '"xray"')
  if [[ -n "$non_xray" ]]; then
    return 0
  fi

  # 若仅有 xray 占用，检查是否正是本节点自身的入站标记（配置已包含该入站但状态不同步时不阻断开启）
  local conf="${XRAY_CONF:-/usr/local/etc/xray/config.json}"
  if [[ -n "$key" && -f "$conf" ]]; then
    if grep -q "// >>xh:${key}" "$conf"; then
      return 1
    fi
  fi

  return 0
}

# 需要服务端入站的备用节点：h2direct（TCP H2_PORT）、hy2obfs（UDP HY2_PORT）与 masque（UDP MASQUE_PORT）。$1 = key，$2 = show|on|off
# 顺序：开启时先改客户端文件（可原子撤销），再改服务端，最后写标志位；任何一步失败都撤销前面的步骤。
cmd_backup_server_node() {
  local key="$1" action="${2:-show}" flag name label proto port cur rc
  case "$key" in
    h2direct) flag=FEATURE_H2_DIRECT; name="VLESS-XHTTP-Direct-H2"; label="XHTTP-Direct-H2（TCP 直连，h3-direct 的孪生体）"; proto=tcp; port="${H2_PORT:-8445}" ;;
    hy2obfs)  flag=FEATURE_HY2_OBFS;  name="Hysteria2-TLS-BBR-Salamander"; label="Hysteria2-TLS-BBR-Salamander（salamander 混淆）";       proto=udp; port="${HY2_PORT}" ;;
    masque)   flag=FEATURE_MASQUE;    name="MASQUE-CONNECT-IP";     label="MASQUE 标准 L3 隧道 (RFC 9484 CONNECT-IP)";        proto=udp; port="${MASQUE_PORT:-8447}" ;;
  esac
  cur="${!flag:-false}"
  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== ${label} ===${NC}"
      local has_inbound=false
      [[ -f "$XRAY_CONF" ]] && grep -q "// >>xh:${key}" "$XRAY_CONF" && has_inbound=true
      if [[ "$cur" == true || "$has_inbound" == true ]]; then
        echo -e "  当前状态:       ${GREEN}已开启${NC}  (${proto^^} ${port})"
      else
        echo -e "  当前状态:       ${YELLOW}未开启${NC}  (开启后监听 ${proto^^} ${port})"
      fi
      if [[ "$key" == hy2obfs ]]; then
        echo -e "  ${MANAGE_CMD} hy2 obfs on   # 开启：加服务端入站、放行端口、重启 xray、更新订阅"
        echo -e "  ${MANAGE_CMD} hy2 obfs off  # 关闭：移除入站并从订阅中去掉（防火墙规则保留）"
      elif [[ "$key" == masque ]]; then
        echo -e "  ${MANAGE_CMD} masque on     # 开启：加服务端入站、放行端口、重启 xray、更新订阅"
        echo -e "  ${MANAGE_CMD} masque off    # 关闭：移除入站并从订阅中去掉（防火墙规则保留）"
      else
        echo -e "  ${MANAGE_CMD} ${key} on     # 开启：加服务端入站、放行端口、重启 xray、更新订阅"
        echo -e "  ${MANAGE_CMD} ${key} off    # 关闭：移除入站并从订阅中去掉（防火墙规则保留）"
      fi
      echo ""
      ;;
    on)
      local has_inbound=false
      [[ -f "$XRAY_CONF" ]] && grep -q "// >>xh:${key}" "$XRAY_CONF" && has_inbound=true
      [[ "$cur" == true && "$has_inbound" == true ]] && { info "${label} 已经是开启状态"; return 0; }
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
      if [[ ! -s "${ALL_STORE_DIR}/inbound-${key}.json" ]]; then
        if [[ "$key" == masque ]]; then
          mkdir -p "${ALL_STORE_DIR}"
          render_masque_inbound > "${ALL_STORE_DIR}/inbound-masque.json"
          chmod 600 "${ALL_STORE_DIR}/inbound-masque.json"
        else
          fail "备用节点库缺少 inbound-${key}.json，需用最新安装命令重新部署"
        fi
      fi
      [[ -s /etc/ssl/private/fullchain.cer ]] || fail "未找到证书 /etc/ssl/private/fullchain.cer，无法开启直连类节点"
      if [[ "$key" == hy2obfs ]]; then
        [[ "${FEATURE_HY2:-false}" == true ]] || fail "Hysteria2 总开关未开启，不能开混淆节点。先执行：${MANAGE_CMD} hy2 on"
        [[ "${FEATURE_PORT_HOPPING:-false}" != true ]] || fail "本机开着端口跳跃（FEATURE_PORT_HOPPING），该开关暂不处理跳跃规则"
      fi
      local occupier="" flag_chk="-ltnpH"; [[ "$proto" == udp ]] && flag_chk="-lunpH"
      occupier=$(ss $flag_chk "sport = :$port" 2>/dev/null | grep -o 'users:(([^)]*' | head -1)
      backup_port_busy "$proto" "$port" "$key" && fail "${proto^^} ${port} 已被其他进程占用${occupier:+ ($occupier)}，未做任何修改"
      info "正在开启 ${label} ..."
      backup_node_sync_files "$name" on || fail "更新客户端文件失败，未改动服务端（原因见上）"
      backup_inbound_edit "$key" on "$port"; rc=$?
      if [[ $rc -ne 0 && $rc -ne 3 ]]; then
        backup_node_sync_files "$name" off >/dev/null 2>&1 || true
        fail "服务端入站写入失败，已撤销客户端文件改动"
      fi
      if ! update_node_env "$flag" "true" || ! grep -qE "^${flag}='?true'?\$" "$NODE_ENV_FILE"; then
        backup_inbound_edit "$key" off "$port" >/dev/null 2>&1 || true
        backup_node_sync_files "$name" off >/dev/null 2>&1 || true
        fail "无法写入 ${NODE_ENV_FILE}，已撤销本次改动"
      fi
      export "$flag"=true
      if [[ "$key" == hy2obfs ]]; then backup_open_port udp "$port" qdos; else backup_open_port "$proto" "$port"; fi
      info "${label} 已开启（${proto^^} ${port}）。云厂商安全组 / 安全列表需自行放行该端口。"
      cmd_resub
      ;;
    off)
      local has_inbound=false
      [[ -f "$XRAY_CONF" ]] && grep -q "// >>xh:${key}" "$XRAY_CONF" && has_inbound=true
      if [[ "$cur" != true && "$has_inbound" != true ]]; then
        info "${label} 本来就是关闭状态"
        return 0
      fi
      [[ "$key" != hy2obfs || "${FEATURE_PORT_HOPPING:-false}" != true ]] || fail "本机开着端口跳跃，关闭混淆节点会留下跳跃规则，请先手动处理 FEATURE_PORT_HOPPING"
      backup_store_check
      info "正在关闭 ${label} ..."
      backup_inbound_edit "$key" off "$port"; rc=$?
      [[ $rc -eq 0 || $rc -eq 3 ]] || fail "移除服务端入站失败（原因见上），未改动客户端文件和标志位"
      backup_node_sync_files "$name" off || warn "服务端入站已移除，但客户端文件没有同步（原因见上）。请手动检查 client-config.txt 与订阅"
      update_node_env "$flag" "false"
      export "$flag"=false
      info "${label} 已关闭"
      cmd_resub
      ;;
    *) echo "用法: ${MANAGE_CMD} ${key} [show|on|off]" ;;
  esac
}

cmd_h2direct() { cmd_backup_server_node h2direct "$@"; }
cmd_hy2obfs()  { cmd_hy2 obfs "$@"; }

render_masque_inbound() {
  cat <<MASQUEEOF
,
        {
            "listen": "0.0.0.0",
            "port": ${MASQUE_PORT:-8447},
            "protocol": "masque",
            "settings": {
                "users": [
                    {
                        "email": "user@${CDN_DOMAIN:-example.com}",
                        "pass": "${MASQUE_PASSWORD:-${UUID2}}",
                        "level": 0
                    }
                ],
                "address": [
                    "10.13.0.1/24",
                    "fd13::1/64"
                ],
                "mtu": 1400
            },
            "streamSettings": {
                "network": "masque",
                "security": "tls",
                "tlsSettings": {
                    "minVersion": "1.3",
                    "maxVersion": "1.3",
                    "rejectUnknownSni": true,
                    "certificates": [
                        {
                            "certificateFile": "${CERT_FILE:-/etc/ssl/private/fullchain.cer}",
                            "keyFile": "${CERT_KEY:-/etc/ssl/private/private.key}"
                        }
                    ],
                    "alpn": ["h3", "h2"]
                },
                "sockopt": {
                    "tcpcongestion": "bbr"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": false
            }
        }
MASQUEEOF
}

cmd_masque() {
  local subcmd="${1:-show}" port="${MASQUE_PORT:-8447}"
  case "$subcmd" in
    show|status)
      echo ""
      echo -e "${CYAN}=== MASQUE 标准 L3 隧道 (RFC 9484 CONNECT-IP) ===${NC}"
      if [[ "${FEATURE_MASQUE:-false}" == true ]]; then
        echo -e "  MASQUE 隧道节点:      ${GREEN}已开启${NC}  (UDP/TCP ${port}，alpn: h3,h2)"
      else
        echo -e "  MASQUE 隧道节点:      ${YELLOW}未开启${NC}  (开启后监听 UDP/TCP ${port})"
      fi
      echo -e "  认证邮箱:             user@${CDN_DOMAIN:-example.com}"
      echo -e "  内网虚拟 IP 池:       10.13.0.1/24, fd13::1/64"
      echo -e "  协议标准:             IETF RFC 9484 (CONNECT-IP) / RFC 8441 Extended CONNECT"
      echo ""
      echo -e "  常用指令:"
      echo -e "    ${MANAGE_CMD} masque on            # 开启 MASQUE 隧道节点（UDP/TCP ${port}）"
      echo -e "    ${MANAGE_CMD} masque off           # 关闭 MASQUE 隧道节点"
      echo ""
      ;;
    on)
      cmd_backup_server_node masque on
      ;;
    off)
      cmd_backup_server_node masque off
      ;;
    *)
      echo "用法: ${MANAGE_CMD} masque [show|on|off]"
      ;;
  esac
}

# Hysteria2 直连与混淆节点统一管理（UDP 随机高端口）
cmd_hy2() {
  local subcmd="${1:-show}" port="${HY2_H3_PORT:-}" obfs_port="${HY2_PORT:-}" rc
  [[ -z "$port" ]] && port="未设置"
  [[ -z "$obfs_port" ]] && obfs_port="未设置"

  case "$subcmd" in
    obfs)
      shift
      cmd_backup_server_node hy2obfs "${1:-show}"
      ;;
    show|status)
      echo ""
      echo -e "${CYAN}=== Hysteria2 节点与混淆管理 ===${NC}"
      if [[ "${FEATURE_HY2:-false}" == true && "${FEATURE_HY2_H3:-false}" == true ]]; then
        echo -e "  Hysteria2 直连节点:   ${GREEN}已开启${NC}  (UDP ${port}，随机端口)"
      else
        echo -e "  Hysteria2 直连节点:   ${YELLOW}未开启${NC}  (开启后监听 UDP ${port})"
      fi
      if [[ "${FEATURE_HY2_OBFS:-false}" == true ]]; then
        echo -e "  Hysteria2 混淆节点:   ${GREEN}已开启${NC}  (UDP ${obfs_port}，salamander 混淆)"
      else
        echo -e "  Hysteria2 混淆节点:   ${YELLOW}未开启${NC}  (开启后监听 UDP ${obfs_port})"
      fi
      echo ""
      echo -e "  常用指令:"
      echo -e "    ${MANAGE_CMD} hy2 on            # 开启 Hysteria2 直连节点（UDP ${port}）"
      echo -e "    ${MANAGE_CMD} hy2 off           # 关闭全部 Hysteria2 节点（直连与混淆）"
      echo -e "    ${MANAGE_CMD} hy2 obfs on       # 开启 Hysteria2 混淆节点（UDP ${obfs_port}）"
      echo -e "    ${MANAGE_CMD} hy2 obfs off      # 关闭 Hysteria2 混淆节点"
      echo ""
      ;;
    on)
      if [[ "${FEATURE_HY2:-false}" == true && "${FEATURE_HY2_H3:-false}" == true ]]; then info "Hysteria2 已经是开启状态"; return 0; fi
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
      [[ -s "${ALL_STORE_DIR}/inbound-hy2h3.json" ]] || fail "备用节点库缺少 inbound-hy2h3.json，需用最新安装命令重新部署"
      [[ -s /etc/ssl/private/fullchain.cer ]] || fail "未找到证书 /etc/ssl/private/fullchain.cer，无法开启 Hysteria2"
      local occupier
      occupier=$(ss -lunpH "sport = :$port" 2>/dev/null | grep -o 'users:(([^)]*' | head -1)
      backup_port_busy udp "$port" hy2h3 && fail "UDP ${port} 已被其他进程占用${occupier:+ ($occupier)}，未做任何修改"
      info "正在开启 Hysteria2 直连节点 ..."
      backup_node_sync_files "Hysteria2-H3-Direct" on || fail "更新客户端文件失败，未改动服务端（原因见上）"
      backup_inbound_edit hy2h3 on "tag:hy2-h3"; rc=$?
      if [[ $rc -ne 0 && $rc -ne 3 ]]; then
        backup_node_sync_files "Hysteria2-H3-Direct" off >/dev/null 2>&1 || true
        fail "服务端入站写入失败，已撤销客户端文件改动"
      fi
      if ! update_node_env FEATURE_HY2 true || ! update_node_env FEATURE_HY2_H3 true \
         || ! grep -qE "^FEATURE_HY2_H3='?true'?\$" "$NODE_ENV_FILE"; then
        backup_inbound_edit hy2h3 off "tag:hy2-h3" >/dev/null 2>&1 || true
        backup_node_sync_files "Hysteria2-H3-Direct" off >/dev/null 2>&1 || true
        fail "无法写入 ${NODE_ENV_FILE}，已撤销本次改动"
      fi
      export FEATURE_HY2=true FEATURE_HY2_H3=true
      backup_open_port udp "$port" qdos
      info "Hysteria2 直连节点已开启（UDP ${port}）。云厂商安全组 / 安全列表需自行放行该端口。"
      cmd_resub
      ;;
    off)
      if [[ "${FEATURE_HY2:-false}" != true && "${FEATURE_HY2_H3:-false}" != true ]]; then info "Hysteria2 本来就是关闭状态"; return 0; fi
      backup_store_check
      if [[ "${FEATURE_HY2_OBFS:-false}" == true ]]; then
        info "混淆节点依附于 Hysteria2，先一并关闭 ..."
        cmd_backup_server_node hy2obfs off
      fi
      info "正在关闭 Hysteria2 ..."
      backup_inbound_edit hy2h3 off "tag:hy2-h3"; rc=$?
      [[ $rc -eq 0 || $rc -eq 3 ]] || fail "移除服务端入站失败（原因见上），未改动客户端文件和标志位"
      backup_node_sync_files "Hysteria2-H3-Direct" off || warn "服务端入站已移除，但客户端文件没有同步（原因见上）。请手动检查 client-config.txt 与订阅"
      update_node_env FEATURE_HY2 false
      update_node_env FEATURE_HY2_H3 false
      export FEATURE_HY2=false FEATURE_HY2_H3=false
      info "Hysteria2 已关闭"
      cmd_resub
      ;;
    obfs-on) cmd_backup_server_node hy2obfs on ;;
    obfs-off) cmd_backup_server_node hy2obfs off ;;
    *) echo "用法: ${MANAGE_CMD} hy2 [show|on|off|obfs on|obfs off]" ;;
  esac
}

# 确保 XDRIVE 的 VLESS Encryption 密钥对存在（Xray >= 26.10.17 强制），缺失时用 xray vlessenc 生成并写入 node.env
xdrive_ensure_keys() {
  [[ -n "${XDRIVE_DECRYPTION:-}" && -n "${XDRIVE_ENCRYPTION:-}" ]] && return 0
  local out enc dec
  out=$(xray vlessenc 2>/dev/null) || fail "xray vlessenc 失败，无法生成 XDRIVE 加密密钥"
  enc=$(awk -F'"' '/Authentication: X25519/{f=1} f && /"encryption"/{print $4; exit}' <<< "$out")
  dec=$(awk -F'"' '/Authentication: X25519/{f=1} f && /"decryption"/{print $4; exit}' <<< "$out")
  [[ -n "$enc" && -n "$dec" ]] || fail "解析 xray vlessenc 输出失败"
  update_node_env XDRIVE_ENCRYPTION "$enc"
  update_node_env XDRIVE_DECRYPTION "$dec"
  export XDRIVE_ENCRYPTION="$enc" XDRIVE_DECRYPTION="$dec"
}

render_xdrive_inbound() {
  xdrive_ensure_keys
  cat <<XDRIVEEOF
,
        {
            "tag": "vless-xdrive",
            "listen": "127.0.0.1",
            "port": 1,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID2}",
                        "level": 0
                    }
                ],
                "decryption": "${XDRIVE_DECRYPTION}"
            },
            "streamSettings": {
                "network": "xdrive",
                "xdriveSettings": {
                    "service": "google-drive",
                    "remoteFolder": "${XDRIVE_FOLDER:-unknown}",
                    "secrets": [
                        "${XDRIVE_CLIENT_ID:-unknown}",
                        "${XDRIVE_CLIENT_SECRET:-unknown}",
                        "${XDRIVE_REFRESH_TOKEN:-unknown}"
                    ]
                }
            }
        }
XDRIVEEOF
}

generate_xdrive_client_config() {
  xdrive_ensure_keys
  local target="${USER_HOME:-/root}/xdrive-client.json"
  cat > "$target" <<XCEOF
{
    "remarks": "XDRIVE-Google-Drive",
    "outbounds": [
        {
            "tag": "proxy-xdrive",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "127.0.0.1",
                        "port": 0,
                        "users": [
                            {
                                "id": "${UUID2}",
                                "encryption": "${XDRIVE_ENCRYPTION}"
                            }
                        ]
                    }
                ]
            },
            "mux": { "enabled": true },
            "streamSettings": {
                "network": "xdrive",
                "xdriveSettings": {
                    "service": "google-drive",
                    "remoteFolder": "${XDRIVE_FOLDER:-your_folder_id}",
                    "secrets": [
                        "${XDRIVE_CLIENT_ID:-your_client_id}",
                        "${XDRIVE_CLIENT_SECRET:-your_client_secret}",
                        "${XDRIVE_REFRESH_TOKEN:-your_refresh_token}"
                    ]
                }
            }
        }
    ]
}
XCEOF
  chmod 600 "$target" 2>/dev/null || true
  chown "$(stat -c '%u:%g' "${USER_HOME:-/root}")" "$target" 2>/dev/null || true
}

# XDRIVE 网盘穿透代理管理 (Google Drive)
cmd_xdrive() {
  local subcmd="${1:-show}" rc
  case "$subcmd" in
    show|status)
      echo ""
      echo -e "${CYAN}=== XDRIVE 网盘穿透代理 (Google Drive) ===${NC}"
      if [[ "${FEATURE_XDRIVE:-false}" == true ]]; then
        echo -e "  XDRIVE 网盘代理:      ${GREEN}已开启${NC}  (零公网 IP / 极端白名单网络穿透)"
      else
        echo -e "  XDRIVE 网盘代理:      ${YELLOW}未开启${NC}"
      fi
      echo -e "  云存储服务类型:       Google Drive (原生 HTTP API，无需第三方 SDK)"
      echo -e "  远程中转目录 ID:      ${XDRIVE_FOLDER:-未配置}"
      if [[ -n "${XDRIVE_CLIENT_ID:-}" ]]; then
        local masked_cid="${XDRIVE_CLIENT_ID:0:8}***.apps.googleusercontent.com"
        echo -e "  OAuth Client ID:      ${masked_cid}"
      else
        echo -e "  OAuth Client ID:      未配置"
      fi
      echo -e "  客户端配置示例:       ${USER_HOME:-/root}/xdrive-client.json"
      echo ""
      echo -e "  使用说明与提示 (Google Drive OAuth):"
      echo -e "    1. 在 Google Cloud Console 创建 OAuth 2.0 Client ID (类型选桌面应用或 Web)"
      echo -e "    2. 在 Google Drive 新建一个中转文件夹，获取 URL 中的 folderId"
      echo -e "    3. 获取 OAuth Refresh Token 并运行: ${MANAGE_CMD} xdrive setup 进行配置"
      echo ""
      echo -e "  常用指令:"
      echo -e "    ${MANAGE_CMD} xdrive show          # 查看 XDRIVE 状态与配置"
      echo -e "    ${MANAGE_CMD} xdrive setup         # 交互式配置 Google Drive 凭据"
      echo -e "    ${MANAGE_CMD} xdrive on            # 开启 XDRIVE 网盘穿透代理入站"
      echo -e "    ${MANAGE_CMD} xdrive off           # 关闭 XDRIVE 网盘穿透代理入站"
      echo ""
      ;;
    setup)
      echo ""
      echo -e "${CYAN}=== 配置 XDRIVE Google Drive 网盘穿透凭证 ===${NC}"
      echo "提示: 请先在 Google Cloud Console 创建 OAuth 2.0 桌面客户端，并在 Google Drive 新建中转目录。"
      read -rp "请输入 Google Drive 中转目录 ID (Folder ID) [${XDRIVE_FOLDER:-}]: " folder
      [[ -z "$folder" ]] && folder="${XDRIVE_FOLDER:-}"
      read -rp "请输入 Google OAuth Client ID [${XDRIVE_CLIENT_ID:-}]: " cid
      [[ -z "$cid" ]] && cid="${XDRIVE_CLIENT_ID:-}"
      read -rp "请输入 Google OAuth Client Secret: " csec
      [[ -z "$csec" ]] && csec="${XDRIVE_CLIENT_SECRET:-}"
      read -rp "请输入 Google OAuth Refresh Token: " rtok
      [[ -z "$rtok" ]] && rtok="${XDRIVE_REFRESH_TOKEN:-}"

      if [[ -z "$folder" || -z "$cid" || -z "$csec" || -z "$rtok" ]]; then
        fail "所有 4 项凭据均不能为空！"
      fi

      update_node_env XDRIVE_FOLDER "$folder"
      update_node_env XDRIVE_CLIENT_ID "$cid"
      update_node_env XDRIVE_CLIENT_SECRET "$csec"
      update_node_env XDRIVE_REFRESH_TOKEN "$rtok"
      export XDRIVE_FOLDER="$folder" XDRIVE_CLIENT_ID="$cid" XDRIVE_CLIENT_SECRET="$csec" XDRIVE_REFRESH_TOKEN="$rtok"

      mkdir -p "${ALL_STORE_DIR}"
      render_xdrive_inbound > "${ALL_STORE_DIR}/inbound-xdrive.json"
      chmod 600 "${ALL_STORE_DIR}/inbound-xdrive.json"

      generate_xdrive_client_config

      info "Google Drive 凭据配置成功并已保存！"
      if [[ "${FEATURE_XDRIVE:-false}" == true ]]; then
        info "正在重新加载线上 XDRIVE 配置 ..."
        backup_inbound_edit xdrive off "tag:vless-xdrive" >/dev/null 2>&1 || true
        backup_inbound_edit xdrive on "tag:vless-xdrive"
      else
        info "可运行 ${MANAGE_CMD} xdrive on 开启入站"
      fi
      ;;
    on)
      if [[ "${FEATURE_XDRIVE:-false}" == true ]]; then info "XDRIVE 网盘代理已经是开启状态"; return 0; fi
      if [[ -z "${XDRIVE_FOLDER:-}" || "${XDRIVE_FOLDER:-}" == "unknown" || -z "${XDRIVE_CLIENT_ID:-}" || "${XDRIVE_CLIENT_ID:-}" == "unknown" || -z "${XDRIVE_CLIENT_SECRET:-}" || "${XDRIVE_CLIENT_SECRET:-}" == "unknown" || -z "${XDRIVE_REFRESH_TOKEN:-}" || "${XDRIVE_REFRESH_TOKEN:-}" == "unknown" ]]; then
        warn "XDRIVE 凭据尚未完整配置，现在进入交互式配置："
        cmd_xdrive setup || return 1
      fi
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
      [[ -s "${ALL_STORE_DIR}/inbound-xdrive.json" ]] || {
        mkdir -p "${ALL_STORE_DIR}"
        render_xdrive_inbound > "${ALL_STORE_DIR}/inbound-xdrive.json"
        chmod 600 "${ALL_STORE_DIR}/inbound-xdrive.json"
      }
      info "正在开启 XDRIVE 网盘穿透代理 ..."
      backup_inbound_edit xdrive on "tag:vless-xdrive"; rc=$?
      if [[ $rc -ne 0 && $rc -ne 3 ]]; then
        fail "服务端入站写入失败，未改动配置"
      fi
      update_node_env FEATURE_XDRIVE true
      export FEATURE_XDRIVE=true
      generate_xdrive_client_config
      info "XDRIVE 网盘穿透入站已开启（tag: vless-xdrive）。"
      info "客户端配置文件已生成: ${USER_HOME:-/root}/xdrive-client.json"
      ;;
    off)
      if [[ "${FEATURE_XDRIVE:-false}" != true ]]; then info "XDRIVE 网盘代理本来就是关闭状态"; return 0; fi
      backup_store_check
      info "正在关闭 XDRIVE 网盘穿透代理 ..."
      backup_inbound_edit xdrive off "tag:vless-xdrive"; rc=$?
      [[ $rc -eq 0 || $rc -eq 3 ]] || fail "移除服务端入站失败"
      update_node_env FEATURE_XDRIVE false
      export FEATURE_XDRIVE=false
      info "XDRIVE 网盘穿透代理已关闭"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} xdrive [show|setup|on|off]"
      ;;
  esac
}

render_hy2_obfs_inbound() {
  cat <<HY2EOF
,
        {
            "listen": "0.0.0.0",
            "port": ${HY2_PORT},
            "protocol": "hysteria",
            "settings": {
                "version": 2,
                "clients": [
                    {
                        "auth": "${HY2_PASSWORD}",
                        "level": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h3"],
                    "minVersion": "1.3",
                    "maxVersion": "1.3",
                    "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256",
                    "rejectUnknownSni": true,
                    "certificates": [
                        {
                            "certificateFile": "${CERT_FILE:-/etc/ssl/private/fullchain.cer}",
                            "keyFile": "${CERT_KEY:-/etc/ssl/private/private.key}"
                        }
                    ]
                },
                "hysteriaSettings": {
                    "version": 2,
                    "udpIdleTimeout": 60,
                    "masquerade": {
                        "type": "proxy",
                        "url": "https://127.0.0.1:8003",
                        "rewriteHost": false,
                        "insecure": true
                    }
                },
                "sockopt": {
                    "tcpFastOpen": true,
                    "tcpcongestion": "bbr"
                },
                "finalmask": {
                    "quicParams": {
                        "congestion": "bbr",
                        "keepAlivePeriod": 10,
                        "initStreamReceiveWindow": 8388608,
                        "maxStreamReceiveWindow": 67108864,
                        "initConnectionReceiveWindow": 16777216,
                        "maxConnectionReceiveWindow": 134217728
                    },
                    "udp": [
$(if [[ "${FEATURE_NOISE_EXP:-false}" == true ]]; then cat <<NEOF
                        {
                            "type": "noise",
                            "settings": {
                                "noise": [
                                    {
                                        "type": "exp",
                                        "packet": "${NOISE_EXP_PACKET:-<b 16030100><r 32><t><c><rd 8>}",
                                        "delay": "${NOISE_EXP_DELAY:-10-50}"
                                    }
                                ]
                            }
                        },
NEOF
fi)
                        {
                            "type": "salamander",
                            "settings": {
                                "password": "${OBFS_PASSWORD}"
                            }
                        }
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": false
            }
        }
HY2EOF
}

render_hy2_h3_inbound() {
  cat <<HY2H3EOF
,
        {
            "listen": "0.0.0.0",
            "tag": "hy2-h3",
            "port": ${HY2_H3_PORT:-443},
            "protocol": "hysteria",
            "settings": {
                "version": 2,
                "clients": [
                    {
                        "auth": "${HY2_PASSWORD}",
                        "level": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h3"],
                    "minVersion": "1.3",
                    "maxVersion": "1.3",
                    "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256",
                    "rejectUnknownSni": true,
                    "certificates": [
                        {
                            "certificateFile": "${CERT_FILE:-/etc/ssl/private/fullchain.cer}",
                            "keyFile": "${CERT_KEY:-/etc/ssl/private/private.key}"
                        }
                    ]
                },
                "hysteriaSettings": {
                    "version": 2,
                    "udpIdleTimeout": 60,
                    "masquerade": {
                        "type": "proxy",
                        "url": "https://127.0.0.1:8003",
                        "rewriteHost": false,
                        "insecure": true
                    }
                },
                "sockopt": {
                    "tcpFastOpen": true,
                    "tcpcongestion": "bbr"
                },
                "finalmask": {
                    "quicParams": {
                        "congestion": "bbr",
                        "keepAlivePeriod": 10,
                        "initStreamReceiveWindow": 8388608,
                        "maxStreamReceiveWindow": 67108864,
                        "initConnectionReceiveWindow": 16777216,
                        "maxConnectionReceiveWindow": 134217728
                    }$(if [[ "${FEATURE_NOISE_EXP:-false}" == true ]]; then cat <<NEOF
,
                    "udp": [
                        {
                            "type": "noise",
                            "settings": {
                                "noise": [
                                    {
                                        "type": "exp",
                                        "packet": "${NOISE_EXP_PACKET:-<b 16030100><r 32><t><c><rd 8>}",
                                        "delay": "${NOISE_EXP_DELAY:-10-50}"
                                    }
                                ]
                            }
                        }
                    ]
NEOF
fi)
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": false
            }
        }
HY2H3EOF
}

# 让客户端链接里的 Hysteria2 fm 参数与 Noise 开关一致：开启时在 quicParams 之后的 udp 数组最前面放 noise 项，
# 关闭时去掉；保留已有的 salamander 项与 quicParams，其余链接一行不动。改 client-config.txt 与备用节点库里的那份。
# 此前 xh noise on/off/set 只改了服务端入站与备用节点库的入站文本，链接没跟着变，开关和链接就不一致。
sync_noise_links() {
  local home="" candidate files=() f
  if [[ -n "${USER_HOME:-}" && -f "${USER_HOME}/client-config.txt" ]]; then
    home="$USER_HOME"
  else
    for candidate in /home/ubuntu /home/opc /root; do
      [[ -f "${candidate}/client-config.txt" ]] && { home="$candidate"; break; }
    done
  fi
  [[ -n "$home" ]] && files+=("${home}/client-config.txt")
  [[ -f "${ALL_STORE_DIR}/client-config.txt" ]] && files+=("${ALL_STORE_DIR}/client-config.txt")
  [[ ${#files[@]} -gt 0 ]] || { warn "没找到 client-config.txt，链接未同步"; return 0; }
  for f in "${files[@]}"; do
    python3 - "$f" "$([[ "${FEATURE_NOISE_EXP:-false}" == true && "${FEATURE_NOISE_LINKS:-false}" == true ]] && echo true || echo false)" "${NOISE_EXP_PACKET:-<b 16030100><r 32><t><c><rd 8>}" "${NOISE_EXP_DELAY:-10-50}" <<'NLPY' || warn "同步 ${f} 里的 Noise 链接参数失败"
import json, os, re, sys
from urllib.parse import quote, unquote

path, enabled, packet, delay = sys.argv[1:5]
enabled = (enabled == 'true')
text = open(path, encoding='utf-8').read()
out = []
changed = False
for line in text.split('\n'):
    if line.startswith('hysteria2://') and '&fm=' in line:
        m = re.search(r'&fm=([^&#]*)', line)
        try:
            fm = json.loads(unquote(m.group(1)))
        except ValueError:
            out.append(line); continue
        udp = [x for x in fm.get('udp', []) if x.get('type') != 'noise']
        if enabled:
            udp.insert(0, {"type": "noise", "settings": {"noise": [{"type": "exp", "packet": packet, "delay": delay}]}})
        new = {"quicParams": fm.get("quicParams", {})}
        if udp:
            new["udp"] = udp
        enc = quote(json.dumps(new, separators=(',', ':'), ensure_ascii=False), safe='')
        line2 = line[:m.start(1)] + enc + line[m.end(1):]
        if line2 != line:
            changed = True
        line = line2
    out.append(line)
if changed:
    tmp = path + '.xh-new'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    st = os.stat(path)
    os.chmod(tmp, st.st_mode & 0o7777)
    try:
        os.chown(tmp, st.st_uid, st.st_gid)
    except PermissionError:
        pass
    os.replace(tmp, path)
NLPY
  done
}

sync_noise_live_config() {
  local tmp="${XRAY_CONF%.json}.bk-tmp.json" bak="${XRAY_CONF}.bk.bak"
  [[ -f "$XRAY_CONF" ]] || return 0
  python3 - "$XRAY_CONF" "$tmp" "${ALL_STORE_DIR}" <<'NPY'
import sys, os

src, dst, store_dir = sys.argv[1:4]
s = open(src, encoding='utf-8').read()
changed = False

for key in ['hy2h3', 'hy2obfs']:
    begin = '        // >>xh:' + key
    end = '        // <<xh:' + key
    sf = os.path.join(store_dir, 'inbound-%s.json' % key)
    if begin in s and end in s and os.path.isfile(sf):
        a = s.index('\n' + begin)
        b = s.index(end, a) + len(end)
        text = open(sf, encoding='utf-8').read().rstrip('\n')
        s = s[:a] + '\n' + begin + '\n' + text + '\n' + end + '\n' + s[b:]
        changed = True

if not changed:
    sys.exit(3)
open(dst, 'w', encoding='utf-8').write(s)
NPY
  local rc=$?
  if [[ $rc -eq 3 ]]; then
    return 0
  elif [[ $rc -ne 0 ]]; then
    rm -f "$tmp"; warn "替换 Noise 配置失败"; return 1
  fi

  if ! err=$("$XRAY_BIN" -test -format json -config "$tmp" 2>&1); then
    rm -f "$tmp"; warn "Xray 配置校验失败，已放弃修改：$err"; return 1
  fi
  cp -a "$XRAY_CONF" "$bak"
  mv -f "$tmp" "$XRAY_CONF"
  if ! svc restart xray; then
    cp -a "$bak" "$XRAY_CONF"
    svc restart xray >/dev/null 2>&1 || true
    warn "重启 Xray 失败，已回滚"
    return 1
  fi
  return 0
}

# Finalmask Noise 动态混淆管理 (Xray v26.9.30+)
cmd_noise() {
  local subcmd="${1:-show}" cur="${FEATURE_NOISE_EXP:-false}"
  local cur_pkt="${NOISE_EXP_PACKET:-<b 16030100><r 32><t><c><rd 8>}"
  local cur_delay="${NOISE_EXP_DELAY:-10-50}"
  case "$subcmd" in
    show|status)
      echo ""
      echo -e "${CYAN}=== Finalmask Noise 动态混淆 (Xray v26.9.30+) ===${NC}"
      if [[ "$cur" == true ]]; then
        echo -e "  Noise 动态混淆:       ${GREEN}已开启${NC}"
      else
        echo -e "  Noise 动态混淆:       ${YELLOW}未开启${NC}"
      fi
      echo -e "  混淆数据包表达式:     ${CYAN}${cur_pkt}${NC}"
      echo -e "  延迟范围 (毫秒):      ${CYAN}${cur_delay}${NC}"
      echo ""
      echo -e "  支持的动态表达式标签 (AWG 风格):"
      echo -e "    <b hex>   指定十六进制字节（例如: <b 16030100> 伪造 TLS ClientHello 头）"
      echo -e "    <r N>     N 个随机字节（例如: <r 32> 伪造 32 字节 Session ID）"
      echo -e "    <rc>      随机英文字母"
      echo -e "    <rd N>    N 个随机十进制数字"
      echo -e "    <t>       4 字节时间戳"
      echo -e "    <c>       递增计数器"
      echo -e "    <n>       8 字节随机 Nonce"
      echo ""
      echo -e "  常用指令:"
      echo -e "    ${MANAGE_CMD} noise on                 # 开启 Noise 动态混淆"
      echo -e "    ${MANAGE_CMD} noise off                # 关闭 Noise 动态混淆"
      echo -e "    ${MANAGE_CMD} noise set \"<exp>\" [延时]  # 自定义混淆模板与延时"
      echo -e "    ${MANAGE_CMD} noise sync               # 只按当前开关把客户端链接对齐（不重启 Xray）"
      echo -e "    ${MANAGE_CMD} noise links on|off       # 链接里是否带 noise（默认不带；需要客户端内核 >= 26.9.30）"
      echo ""
      ;;
    on)
      if [[ "$cur" == true ]]; then info "Noise 动态混淆已经是开启状态"; return 0; fi
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
      info "正在开启 Noise 动态混淆 ..."
      update_node_env FEATURE_NOISE_EXP true
      export FEATURE_NOISE_EXP=true
      mkdir -p "${ALL_STORE_DIR}"
      render_hy2_obfs_inbound > "${ALL_STORE_DIR}/inbound-hy2obfs.json"
      render_hy2_h3_inbound   > "${ALL_STORE_DIR}/inbound-hy2h3.json"
      chmod 600 "${ALL_STORE_DIR}"/inbound-hy2*.json 2>/dev/null || true
      sync_noise_live_config
      sync_noise_links
      info "Noise 动态混淆已开启！"
      cmd_resub
      ;;
    off)
      if [[ "$cur" != true ]]; then info "Noise 动态混淆本来就是关闭状态"; return 0; fi
      backup_store_check
      info "正在关闭 Noise 动态混淆 ..."
      update_node_env FEATURE_NOISE_EXP false
      export FEATURE_NOISE_EXP=false
      mkdir -p "${ALL_STORE_DIR}"
      render_hy2_obfs_inbound > "${ALL_STORE_DIR}/inbound-hy2obfs.json"
      render_hy2_h3_inbound   > "${ALL_STORE_DIR}/inbound-hy2h3.json"
      chmod 600 "${ALL_STORE_DIR}"/inbound-hy2*.json 2>/dev/null || true
      sync_noise_live_config
      sync_noise_links
      info "Noise 动态混淆已关闭"
      cmd_resub
      ;;
    set)
      shift
      local new_pkt="${1:-}" new_delay="${2:-10-50}"
      [[ -z "$new_pkt" ]] && new_pkt="<b 16030100><r 32><t><c><rd 8>"
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存状态"
      info "正在更新 Noise 混淆模板: packet=${new_pkt}, delay=${new_delay} ..."
      update_node_env NOISE_EXP_PACKET "$new_pkt"
      update_node_env NOISE_EXP_DELAY "$new_delay"
      export NOISE_EXP_PACKET="$new_pkt" NOISE_EXP_DELAY="$new_delay"
      mkdir -p "${ALL_STORE_DIR}"
      render_hy2_obfs_inbound > "${ALL_STORE_DIR}/inbound-hy2obfs.json"
      render_hy2_h3_inbound   > "${ALL_STORE_DIR}/inbound-hy2h3.json"
      chmod 600 "${ALL_STORE_DIR}"/inbound-hy2*.json 2>/dev/null || true
      if [[ "${FEATURE_NOISE_EXP:-false}" == true ]]; then
        sync_noise_live_config
      fi
      sync_noise_links
      info "Noise 混淆模板已更新！"
      cmd_resub
      ;;
    links)
      # 链接里是否带 noise：服务端 noise 开着也可以不带（老客户端不受影响）。noise.exp 需要客户端内核 >= 26.9.30。
      case "${2:-show}" in
        show|status)
          echo -e "  链接里带 noise:       $([[ "${FEATURE_NOISE_LINKS:-false}" == true ]] && echo "${GREEN}是${NC}" || echo "${YELLOW}否（默认，兼容老内核）${NC}")"
          echo -e "  ${MANAGE_CMD} noise links on|off   # 需要客户端内核 >= 26.9.30，否则 v2rayN 会报「运行内核失败」"
          ;;
        on)
          [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存状态"
          warn "链接里的 noise.exp 需要客户端 Xray 内核 >= 26.9.30；v2rayN 自带内核更老时 Hysteria2 节点会「运行内核失败」"
          update_node_env FEATURE_NOISE_LINKS true; export FEATURE_NOISE_LINKS=true
          sync_noise_links; info "已让 Hysteria2 链接带上 noise"; cmd_resub ;;
        off)
          [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存状态"
          update_node_env FEATURE_NOISE_LINKS false; export FEATURE_NOISE_LINKS=false
          sync_noise_links; info "已去掉 Hysteria2 链接里的 noise（服务端 noise 不变，不重启 Xray）"; cmd_resub ;;
        *) echo "用法: ${MANAGE_CMD} noise links [show|on|off]" ;;
      esac
      ;;
    sync)
      # 只按当前开关把客户端链接的 fm 对齐（不动服务端、不重启 Xray）
      sync_noise_links
      info "已按当前 Noise 开关（${cur}）同步客户端链接"
      cmd_resub
      ;;
    *)
      echo "用法: ${MANAGE_CMD} noise [show|on|off|links|sync|set <packet> [delay]]"
      ;;
  esac
}

# ==================================================
# Reality 节点管理（xh reality）：Vision / XHTTP 两个直连节点的服务端 + 订阅开关，上下行分离节点转给 xh split
# ==================================================
# 443 的 Reality 入站始终保留（CDN 域名的回源要靠它的 target）；开关只增删入站里的两项：
#   vision：clients 里的 UUID1 + flow（xh:realityvision 标记块）
#   xhttp ：fallbacks 里指向 8001 的那一项（xh:realityxhttp 标记块）
# 已安装的老机器配置里没有标记：关闭时按结构找到那一项直接删掉，开启时再写成带标记的块。
# 返回 0 = 已改并重启成功，3 = 无需改动，其余 = 失败（已回滚，原因已打印）。
reality_server_edit() {
  local key="$1" act="$2" tmp="${XRAY_CONF%.json}.bk-tmp.json" bak="${XRAY_CONF}.bk.bak" rc err
  [[ -f "$XRAY_CONF" ]] || { backup_error "未找到 Xray 配置文件: $XRAY_CONF"; return 1; }
  python3 - "$XRAY_CONF" "$tmp" "$key" "$act" "${UUID1:-}" "${VISION_FLOW:-xtls-rprx-vision}" <<'RSPY'
import re, sys

src, dst, key, act, uuid1, flow = sys.argv[1:7]
s = open(src, encoding='utf-8').read()
tag = 'reality' + key
begin = '        // >>xh:' + tag
end = '        // <<xh:' + tag
if key == 'vision':
    arr = '"clients"'
    if not uuid1:
        sys.stderr.write('node.env 里没有 UUID1\n'); sys.exit(1)
    obj = ('                    {\n'
           '                        "id": "%s",\n'
           '                        "level": 0,\n'
           '                        "flow": "%s"\n'
           '                    }') % (uuid1, flow)
    ident = uuid1
else:
    arr = '"fallbacks"'
    obj = ('                    {\n'
           '                        "dest": "127.0.0.1:8001",\n'
           '                        "xver": 0\n'
           '                    }')
    ident = '127.0.0.1:8001'

def skip_ws_comments(t, i):
    n = len(t)
    while i < n:
        if t[i] in ' \t\r\n':
            i += 1
        elif t.startswith('//', i):
            while i < n and t[i] != '\n':
                i += 1
        elif t.startswith('/*', i):
            i = t.index('*/', i) + 2
        else:
            break
    return i

def match_close(t, i):
    """t[i] 是 { 或 [，返回与之配对的 } / ] 的下标（跳过字符串与注释）。"""
    n, depth = len(t), 0
    while i < n:
        c = t[i]
        if c == '"':
            i += 1
            while i < n and t[i] != '"':
                i += 2 if t[i] == '\\' else 1
        elif t.startswith('//', i):
            while i < n and t[i] != '\n':
                i += 1
            continue
        elif t.startswith('/*', i):
            i = t.index('*/', i) + 2
            continue
        elif c in '{[':
            depth += 1
        elif c in '}]':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

# 443 Reality 入站是 inbounds 里的第一项：取全文第一个 "clients" / "fallbacks" 数组
m = re.search(arr + r'\s*:\s*\[', s)
if not m:
    sys.stderr.write('没找到 %s 数组\n' % arr); sys.exit(1)
lb = m.end() - 1
rb = match_close(s, lb)
inner = s[lb + 1:rb]
has_marker = ('// >>xh:' + tag) in inner
has_obj = ident in inner

if act == 'off':
    if not has_obj:
        sys.exit(3)
    if has_marker:
        a = inner.index('\n' + begin)
        b = inner.index(end, a) + len(end)
        inner2 = inner[:a] + inner[b:]
    else:
        # 没有标记（老机器）：删掉数组里含 ident 的那个对象
        i = skip_ws_comments(inner, 0)
        removed = False
        while i < len(inner) and inner[i] == '{':
            j = match_close(inner, i)
            if ident in inner[i:j + 1]:
                k = i
                while k > 0 and inner[k - 1] in ' \t':
                    k -= 1
                if k > 0 and inner[k - 1] == '\n':
                    k -= 1
                e = j + 1
                if e < len(inner) and inner[e] == ',':
                    e += 1
                inner2 = inner[:k] + inner[e:]
                removed = True
                break
            i = skip_ws_comments(inner, j + 1)
            if i < len(inner) and inner[i] == ',':
                i = skip_ws_comments(inner, i + 1)
        if not removed:
            sys.stderr.write('没找到可删除的 %s 项\n' % ident); sys.exit(1)
else:
    if has_obj:
        sys.exit(3)
    if inner.strip():
        sys.stderr.write('%s 数组里已有其他内容，不自动插入\n' % arr); sys.exit(1)
    inner2 = '\n' + begin + '\n' + obj + '\n' + end + '\n' + inner
s = s[:lb + 1] + inner2 + s[rb:]
open(dst, 'w', encoding='utf-8').write(s)
RSPY
  rc=$?
  [[ $rc -eq 3 ]] && return 3
  if [[ $rc -ne 0 ]]; then rm -f "$tmp"; backup_error "改写配置失败（代码 ${rc}），未做任何修改"; return 1; fi
  if ! err=$("$XRAY_BIN" -test -format json -config "$tmp" 2>&1); then
    rm -f "$tmp"; backup_error "Xray 配置校验失败，已放弃，未做任何修改。最后几行输出："; echo "$err" | tail -n 5 >&2; return 1
  fi
  cp -a "$XRAY_CONF" "$bak"
  chown --reference="$XRAY_CONF" "$tmp" 2>/dev/null || true
  chmod --reference="$XRAY_CONF" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$XRAY_CONF" || { backup_error "无法替换 $XRAY_CONF"; return 1; }
  if ! svc restart xray; then
    cp -a "$bak" "$XRAY_CONF"
    if svc restart xray >/dev/null 2>&1; then
      backup_error "xray 重启失败，已回滚到修改前的配置并重新启动"
    else
      backup_error "xray 重启失败，回滚后也无法启动！请立即检查：journalctl -u xray -n 30"
    fi
    return 1
  fi
  return 0
}

# 单个 Reality 节点开关。$1 = vision|xhttp，$2 = on|off
# 顺序同其它备用节点：开启时先改订阅文件（原子），再改服务端，最后写标志位；任何一步失败都撤销前面的步骤。
reality_toggle() {
  local key="$1" act="$2" flag name label cur rc
  case "$key" in
    vision) flag=FEATURE_REALITY_VISION; name="VLESS-Reality-Vision-Direct"; label="Reality-Vision-Direct（xtls-rprx-vision）" ;;
    xhttp)  flag=FEATURE_REALITY_XHTTP;  name="VLESS-Reality-XHTTP-Direct";  label="Reality-XHTTP-Direct（XHTTP + vlessenc）" ;;
  esac
  cur="${!flag:-true}"
  backup_store_check
  [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
  if [[ "$act" == on ]]; then
    [[ "$cur" == true ]] && { info "${label} 已经是开启状态"; return 0; }
    info "正在开启 ${label} ..."
    backup_node_sync_files "$name" on || fail "更新订阅文件失败，未改动服务端（原因见上）"
    reality_server_edit "$key" on; rc=$?
    if [[ $rc -ne 0 && $rc -ne 3 ]]; then
      backup_node_sync_files "$name" off >/dev/null 2>&1 || true
      fail "服务端写入失败，已撤销订阅文件改动"
    fi
    if ! update_node_env "$flag" "true" || ! grep -qE "^${flag}='?true'?\$" "$NODE_ENV_FILE"; then
      reality_server_edit "$key" off >/dev/null 2>&1 || true
      backup_node_sync_files "$name" off >/dev/null 2>&1 || true
      fail "无法写入 ${NODE_ENV_FILE}，已撤销本次改动"
    fi
    export "$flag"=true
    info "${label} 已开启。xray 已重启，客户端需要更新订阅并重新连接。"
  else
    [[ "$cur" == true ]] || { info "${label} 本来就是关闭状态"; return 0; }
    # 两个 Reality 节点都关掉时，443 上只剩 CDN 回源的壳：允许，但要说一声
    local other_flag other_cur
    [[ "$key" == vision ]] && other_flag=FEATURE_REALITY_XHTTP || other_flag=FEATURE_REALITY_VISION
    other_cur="${!other_flag:-true}"
    [[ "$other_cur" == true ]] || warn "另一个 Reality 节点已经关了：关掉这个以后，443 上不再有可用的 Reality 节点（CDN 回源不受影响）"
    info "正在关闭 ${label} ..."
    reality_server_edit "$key" off; rc=$?
    [[ $rc -eq 0 || $rc -eq 3 ]] || fail "移除服务端项失败（原因见上），未改动订阅文件和标志位"
    backup_node_sync_files "$name" off || warn "服务端项已移除，但订阅文件没有同步（原因见上）。请手动检查 client-config.txt 与订阅"
    update_node_env "$flag" "false"
    export "$flag"=false
    info "${label} 已关闭。xray 已重启，客户端需要更新订阅。"
  fi
  cmd_resub
}

cmd_reality() {
  local what="${1:-show}" act="${2:-show}" v x u sid minv mtd
  local link1 link2 link3 cc="${USER_HOME:-/root}/client-config.txt"
  # 直接取安装时生成的完整链接（bestcf/extra/spx 都已编码在内），不再在此重新拼接
  link1=$(grep -m1 -E '#VLESS-TLS\+(后量子|PQ)\+XHTTP\+CDN' "$cc" 2>/dev/null || true)
  link2=$(grep -m1 -E '#VLESS-TLS\+(后量子|PQ)\+Vision\+XHTTP\+CDN' "$cc" 2>/dev/null || true)
  link3=$(grep -m1 -E '#VLESS-REALITY\+(后量子|PQ)\+Vision' "$cc" 2>/dev/null || true)

  case "$what" in
    show|status|list|"")
      v="${FEATURE_REALITY_VISION:-true}"; x="${FEATURE_REALITY_XHTTP:-true}"; u="${FEATURE_REALITY_UP_CDN_DOWN:-false}"
      sid="${SHORT_ID:-}"; [[ -n "$sid" ]] && sid="${sid:0:2}$(printf '%*s' $(( ${#sid} > 2 ? ${#sid} - 2 : 0 )) '' | tr ' ' '*')"
      minv=$(grep -o '"minClientVer"[[:space:]]*:[[:space:]]*"[^"]*"' "$XRAY_CONF" 2>/dev/null | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
      mtd=$(grep -o '"maxTimeDiff"[[:space:]]*:[[:space:]]*[0-9]*' "$XRAY_CONF" 2>/dev/null | head -1 | grep -o '[0-9]*$')
      echo ""
      echo -e "${CYAN}=== Reality 与后量子精选核心节点 (最佳本机配置) ===${NC}"
      printf '  %-40s %s\n' "1) VLESS-TLS+PQ+XHTTP+CDN" "$([[ "${FEATURE_TLS_PQ_XHTTP:-true}" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  CF CDN(443)  TLS+ML-KEM+XHTTP(16流)"
      printf '  %-40s %s\n' "2) VLESS-TLS+PQ+Vision+XHTTP+CDN" "$([[ "${FEATURE_TLS_PQ_VISION:-false}" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  CF CDN(443)  TLS+ML-KEM+Vision+XHTTP"
      printf '  %-40s %s\n' "3) VLESS-REALITY+PQ+Vision" "$([[ "${FEATURE_REALITY_PQ_VISION:-true}" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  直连(443)    REALITY+ML-KEM+Vision(BBR)"
      echo ""
      echo -e "${CYAN}--- 核心节点链接 (可直接导入客户端) ---${NC}"
      echo -e "  ${YELLOW}[1] VLESS-TLS+PQ+XHTTP+CDN:${NC}"
      echo -e "  ${link1}"
      echo ""
      echo -e "  ${YELLOW}[2] VLESS-TLS+PQ+Vision+XHTTP+CDN:${NC}"
      echo -e "  ${link2}"
      echo ""
      echo -e "  ${YELLOW}[3] VLESS-REALITY+PQ+Vision:${NC}"
      echo -e "  ${link3}"
      echo ""
      echo -e "  伪装目标 target:   127.0.0.1:8003（本机 Nginx，证书域名 ${REALITY_DOMAIN:-?}）"
      echo -e "  serverNames:       ${REALITY_DOMAIN:-?}、${CDN_DOMAIN:-?}"
      echo -e "  后量子加密套件:    ML-KEM-768 (mlkem768x25519plus)"
      echo -e "  拥塞控制与流控:    BBR + FQ / TSQ 4MB 反压 / packetEncoding=xudp"
      echo -e "  shortId:           ${sid:-?}（已隐藏）"
      [[ -n "$minv" ]] && echo -e "  minClientVer:      ${minv}    （${MANAGE_CMD} minversion）"
      echo ""
      echo -e "${CYAN}=== 历史兼容节点 ===${NC}"
      printf '  %-30s %s\n' "VLESS-Reality-Vision-Direct" "$([[ "$v" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  TCP 443  xtls-rprx-vision      ${MANAGE_CMD} reality vision on|off"
      printf '  %-30s %s\n' "VLESS-Reality-XHTTP-Direct" "$([[ "$x" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  TCP 443  XHTTP + vlessenc       ${MANAGE_CMD} reality xhttp on|off"
      printf '  %-30s %s\n' "VLESS-Reality-Up-CDN-Down" "$([[ "$u" == true ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}未开启${NC}")  上行 Reality / 下行 CDN   ${MANAGE_CMD} reality updown on|off"
      echo ""
      ;;
    vision|xhttp)
      case "$act" in
        on|off) reality_toggle "$what" "$act" ;;
        show|status|"") cmd_reality show ;;
        *) echo "用法: ${MANAGE_CMD} reality ${what} [on|off]" ;;
      esac
      ;;
    updown|split)
      case "$act" in
        on|off) cmd_split reality-up "$act" ;;
        *) cmd_split reality-up show ;;
      esac
      ;;
    *) echo "用法: ${MANAGE_CMD} reality [show | list | vision on|off | xhttp on|off | updown on|off]" ;;
  esac
}

# 上下行分离两条（纯客户端链接，不动服务端）
cmd_split() {
  local which="${1:-show}" action="${2:-show}" flag name label
  case "$which" in
    show|status)
      echo ""
      echo -e "${CYAN}=== 上下行分离节点（纯客户端链接，不动服务端）===${NC}"
      [[ "${FEATURE_REALITY_UP_CDN_DOWN:-false}" == true ]] && echo -e "  Reality-Up-CDN-Down:  ${GREEN}已开启${NC}" || echo -e "  Reality-Up-CDN-Down:  ${YELLOW}未开启${NC}"
      [[ "${FEATURE_CDN_UP_REALITY_DOWN:-false}" == true ]] && echo -e "  CDN-Up-Reality-Down:  ${GREEN}已开启${NC}" || echo -e "  CDN-Up-Reality-Down:  ${YELLOW}未开启${NC}"
      echo -e "  ${MANAGE_CMD} split reality-up on|off   # 上行 Reality、下行 CDN"
      echo -e "  ${MANAGE_CMD} split cdn-up on|off       # 上行 CDN、下行 Reality"
      echo ""
      return 0
      ;;
    reality-up) flag=FEATURE_REALITY_UP_CDN_DOWN;  name="VLESS-Reality-Up-CDN-Down"; label="Reality-Up-CDN-Down（上行 Reality、下行 CDN）" ;;
    cdn-up)     flag=FEATURE_CDN_UP_REALITY_DOWN;  name="VLESS-CDN-Up-Reality-Down"; label="CDN-Up-Reality-Down（上行 CDN、下行 Reality）" ;;
    *) echo "用法: ${MANAGE_CMD} split [show|reality-up on|off|cdn-up on|off]"; return 1 ;;
  esac
  case "$action" in
    show|status) cmd_split show ;;
    on)
      backup_store_check
      [[ -f "$NODE_ENV_FILE" ]] || fail "未找到 ${NODE_ENV_FILE}，无法保存开关状态"
      [[ -n "${CDN_DOMAIN:-}" ]] || fail "未配置 CDN 域名，分离节点没有 CDN 腿可用"
      info "正在开启 ${label} ..."
      backup_node_sync_files "$name" on || fail "更新客户端文件失败，未做任何修改（原因见上）"
      update_node_env "$flag" "true"
      export "$flag"=true
      if [[ "$which" == reality-up ]]; then update_node_env FEATURE_UP_CDN_DOWN_MIHOMO true; fi
      info "${label} 已开启"
      cmd_resub
      ;;
    off)
      backup_store_check
      info "正在关闭 ${label} ..."
      backup_node_sync_files "$name" off || warn "客户端文件里没有该节点或同步失败（原因见上），仍按关闭处理标志位"
      update_node_env "$flag" "false"
      export "$flag"=false
      if [[ "$which" == reality-up ]]; then update_node_env FEATURE_UP_CDN_DOWN_MIHOMO false; fi
      info "${label} 已关闭"
      cmd_resub
      ;;
    *) echo "用法: ${MANAGE_CMD} split ${which} on|off" ;;
  esac
}
