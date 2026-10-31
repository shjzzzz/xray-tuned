# xray-tuned

> High-performance proxy and kernel-tuning deployment suite powered by **Xray-core (v26.10.29 stable)**.
> Features **XHTTP + Cloudflare CDN + Reality + Hysteria2** with native BBRv3, TCP Fast Open, 64MB buffer safety, and automated multi-platform subscription distribution.

**语言：** **简体中文** · [English](./README.en.md) · [فارسی](./README.fa.md)

---

## 🌟 最新更新亮点 (v5.3.1 / 2026-10-31)

本项目完成 **全协议握手与速率深度调优及多端客户端（v2rayN / Shadowrocket / Mihomo 新版）兼容性全面强化**：

1. **QUIC / Hysteria2 流控窗口全量对齐与握手加速**：
   - 服务端与客户端双向注入 `finalmask.quicParams`（8MB/64MB 流接收窗口、16MB/128MB 连接接收窗口、10s 保活），消除小窗口对 BBR 吞吐的限制。
   - 实测 Hysteria2-H3 上行从 332 Mbps 跃升至 **764 Mbps**，Salamander 上行从 107 Mbps 翻 4 倍至 **428 Mbps**。
2. **XHTTP 流水线与 TFO 握手零延迟复用**：
   - Reality 443 入站与客户端 URI 全面启用 TCP Fast Open (`tfo=1` / `tfo: true`)，握手延时缩减至 **7.0ms**。
   - `xmux` 注入 `hKeepAlivePeriod: 15`，以 15s 周期发送 HTTP/2 ping 帧保活，实现后续请求 0ms 握手复用；CDN 上行最小 POST 间隔对齐为 10ms，有效降低首包延迟。
3. **跨平台客户端 (Shadowrocket / v2rayN / Mihomo) 全量兼容**：
   - 彻底重构 Shadowrocket 专属订阅生成逻辑，全量生成 7 个纯净 URI（去除小火箭不兼容的嵌套 JSON 与 fm 参数，注入原生 `type=xhttp`、`tfo=1`），解决此前小火箭仅能识别 2 个节点的局限。
   - Mihomo 注入 `recv-window-conn: 134217728`、`recv-window: 67108864` 与 `h-keep-alive-period: 15`，实现多端满血跑满。

---

## 🌟 历史更新亮点 (v5.3.0 / 2026-10-31)

本项目完成 **`xh` 架构深度解耦重构与多协议端到端网速压测/审计全栈集成**：

1. **`xh` 模块化目录解耦与工程化重构**：
   - 彻底拆分庞大的单文件脚本（原 ~5000 行），在 `src/manage/` 建立清晰的 7 大子模块（公共库、服务运维、节点协议、网络调优、Cloudflare隧道、交互菜单、命令分发），保持 100% 向后兼容与免外部依赖单文件打包。
2. **集成全协议端到端网速压测引擎 (`xh bench` / `xh speed`)**：
   - 内置并发轻量客户端，实测全协议代理链路（Reality / Hysteria2 / XHTTP / 上下行分离）真实表现（握手延迟、50MB 下行带宽、10MB 上行带宽及 TTFB）。
   - 单节点测速实测突破千兆（如 VLESS-Reality-XHTTP-Direct 跑满 1023 Mbps，握手 8.1ms）。
3. **集成只读全栈系统性能审计 (`xh audit`)**：
   - 一键采集 CPU 拓扑、网卡中断平衡、BBRv3 状态、NAPI 预算与 sysctl 内核冲突排查，全程零写入安全审计。
4. **交互式全功能分层导航终端升级**：
   - 告别 30 项平铺的杂乱菜单，升级为 6 大功能分类子菜单，新增常用运维快捷直达编号（11-16）。
5. **反向上下行分离节点作为默认安装配置**：
   - 将突破 GFW 握手审查与 QoS 限速的 `VLESS-CDN-Up-Reality-Down`（上行走 CDN 伪装防封，下行走 Reality 极速直连）设为默认安装核心节点，后量子密码学命名统一对齐为 `PQ`。
6. **SSL 证书全生命周期原生集成与智能复用 (`xh cert`)**：
   - 彻底剔除外部繁琐的手工脚本依赖，原生集成 Acme-yg 申请向导、Cloudflare DNS-01 与本地多证书源智能扫描（自动无缝复用 `/root/ygkkkca/`、`/etc/ssl/` 或 `acme.sh` 既有证书）。
   - 支持一键申请 (`xh cert apply` / `xh cert yg`)、智能导入 (`xh cert import`)、强制续期 (`xh cert renew`) 与全链路证书链自动裁剪加速 (`xh-trim-chain`)。

---

## 🌟 历史更新亮点 (v5.2.5 / 2026-10-30)

本项目已实现 **xh 与 sbbox 全链路流控对齐与端口冲突消解**，提供多套件同机混部的最高稳定性保障：

1. **同机混部全端口保护锁定**：在 `ip_local_reserved_ports` 中全量纳入并锁定同机运行的 sbbox 端口（16387, 18048, 25742, 29879）及 Xray 端口，杜绝系统出站短连接随机占用代理监听。
2. **内存行为与脏页刷盘统一**：注入 `vm.dirty_background_ratio = 5` 与 `vm.dirty_ratio = 10`，彻底替代外部独立调优，避免高并发大流量写入时的 I/O 阻塞。
3. **TCP Brutal 协同调优**：主干流量统一走原生自适应 BBRv3，Brutal 温备通道规则对齐 500 Mbps 黄金速率，杜绝客户端下行恶性丢包。

---

## 🌟 历史更新亮点 (v5.2.4 / 2026-10-30)

本项目已实现 **Nginx 1.31.8 主线版深度性能调优与高可用加固**，全面对齐百万并发与内网低延迟解析：

1. **文件描述符与百万并发对齐**：`worker_rlimit_nofile` 提升至 `1048576`（1M 句柄），与 systemd LimitNOFILE 和内核 `fs.file-max` 完全对齐，杜绝海量 XHTTP 长连接与回源双向并发触顶。
2. **TLS 会话复用与 TTFB 首包延迟优化**：`ssl_session_cache` 扩容至 `shared:SSL:64m`，会话缓存超时延长至 `1d`，降低 CPU 握手开销；注入 `ssl_buffer_size 8k`，显著压缩首包往返延迟 (TTFB)。
3. **套接字生命周期与端口均衡**：启用 `reset_timedout_connection on` 快速回收死连接；HTTP 80 端口升级为 `reuseport backlog=65535`，结合多核心调度对齐内核积压队列。
4. **回落伪装站内网 DNS 高可用与解析韧性**：优先引入云内网低延迟解析器 `169.254.169.254`（<1ms），并配置 `1.1.1.1` 灾备，彻底根除回落伪装站偶发的 502/504 域名解析超时。

---

## 🌟 历史更新亮点 (v5.2.3 / 2026-10-29)

本项目已全面适配 **Xray-core v26.10.29** 最新内核与后量子安全规范，并注入全链路性能与防主动探测调优：

1. **Mihomo 后量子混合密钥交换适配 (`support-x25519mlkem768`)**：
   - 适配 Xray-core (>= 26.9.8) 对 REALITY 握手严格校验 `X25519MLKEM768` 份额的要求。
   - 在全平台 Mihomo 订阅与配置模板中注入 `support-x25519mlkem768: true`，杜绝 ClientHello 握手密钥份额被 uTLS 剥离引发的 `REALITY authentication failed`。
2. **Freedom 出站 `blockDelay` 防主动探测黑洞机制**：
   - 适配 Xray 26.10.29 对 DispatchLink 调度入站 `blockDelay` 的修复，注入 `"blockDelay": "30-90"`。
   - 遭遇未授权内网探测、云元数据嗅探或非法扫描时，服务端保持 30~90 秒静默黑洞延迟断开，杜绝扫描器依据即时 RST 判定代理拓扑与端口属性。
3. **突破 ARM64 吞吐瓶颈的全局 Policy 缓冲调优**：
   - 解决 ARM64 架构下未声明 policy 时 Xray 默认单连接缓冲仅 4 KB 的吞吐瓶颈，注入 `bufferSize: 4096KB`（4 MB 单连接缓冲）。
   - 协同设置 `connIdle: 1800s`、`uplinkOnly: 15s`、`downlinkOnly: 30s` 优雅半关闭机制，彻底消除大文件持续拉取与流媒体长视频截断。
4. **全链路 Socket 选项与流控优化 (`sockopt`)**：
   - 核心出入站统一注入 `tcpcongestion: "bbr"`、`tcpNoDelay: true`、`tcpKeepAlive` 与 `tcpUserTimeout: 300000`（5 分钟保护，防跨境抖动误杀连接，同时自愈僵尸套接字）。
   - Hysteria2 入站设置 `udpIdleTimeout: 60`，大幅增强移动蜂窝网络息屏与切网保活能力。
5. **REALITY 服务实例原生升级**：
   - `xray-reality.service` 原生统一升级至 `Xray 26.10.29`，全链路无缝享受后量子混合加密与内核性能优化。

---

## ⚡ 快速一键部署

### 1. Xray-Tuned 自动化静默部署（推荐）
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh) \
  AUTO=1 \
  REALITY_DOMAIN="reality.yourdomain.com" \
  CDN_DOMAIN="cdn.yourdomain.com" \
  NODE_TAG="US-Node" \
  FEATURE_REALITY_VISION=true \
  FEATURE_XHTTP_VLESSENC=true
```


### 3. 交互式部署
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh)
```
> **前置要求**：准备 2 个解析到 VPS 的域名（直连域名灰云仅 DNS，CDN 域名黄云开启代理）。

---

## 📡 10 大核心节点矩阵

| 序号 | 节点名称 | 核心协议与传输 | 端口 / 连接方式 | 伪装 / 密钥 / 混淆 | 推荐适用场景 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | `VLESS-TLS+PQ+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | ML-KEM-768 后量子 + TLS 1.3 | **日常主力推荐**：全平台通用 CDN，抗量子计算破译与 IP 封锁 |
| **2** | `VLESS-TLS+PQ+Vision+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | ML-KEM-768 + Vision 动态控流 | 深度混淆消除 TLS-in-TLS 特征，晚高峰抗 QoS 封锁 |
| **3** | `VLESS-REALITY+PQ+Vision（自域名）` | VLESS + REALITY (RAW) | 8447 / TCP (直连) | ML-KEM-768 + Vision (0.05ms 自域名伪装) | **直连极速推荐**：内核 `splice` 零拷贝跑满千兆，极致低延迟 |
| **4** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | TLS 1.3 / xpadding 填充 / 16 并发 | 标准 CDN 容灾节点，支持老版本 Xray 客户端 |
| **5** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP (H3) | 443 (Cloudflare CDN) | QUIC (H3) 0-RTT / 64MB 接收窗口 | 跨洋 UDP 丢包恶劣链路下的 CDN 极速加速 |
| **6** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP (H3) | 8443 / UDP (直连) | 原生 QUIC (H3) / 64MB 接收窗口 | 直连低延迟大吞吐，抗跨境链路偶发丢包 |
| **7** | `Hysteria2-H3-Direct` | Hysteria2 | UDP 随机高端口 (如 19142) | BBRv3 / 标准 HTTP/3 握手 | 跨境千兆跑满，高丢包网络（如移动/校园网）极速回血 |
| **8** | `Hysteria2-TLS-BBR-Salamander` | Hysteria2 | UDP 随机高端口 (如 38969) | Salamander 混淆 + BBR + 64MB 窗口 | 运营商严苛封锁 UDP 重灾区专用穿透与防主动探测 |
| **9** | `VLESS-Reality-Vision-Direct` | VLESS + REALITY (RAW) | 443 / TCP (直连标口) | xtls-rprx-vision 零拷贝直通 | 标口 443 直连，免额外端口，享受骨干网最高 QoS |
| **10** | `VLESS-Reality-XHTTP-Direct` | VLESS + REALITY (RAW) | 443 回落至本地 8001 | XHTTP + vlessenc 本地解密 | 标口回落备用，兼具 Reality 伪装与分流兼容性 |

> [!NOTE]
> - **前三大 PQ 核心节点**（1-3）采用 NIST 推荐标准后量子密钥协商套件（ML-KEM-768），提供面向未来的抗量子破解前向安全性。
> - **Hysteria2 节点**（7-8）直连 UDP 采用随机高端口监听并全面启用 BBRv3，客户端配置声明 64MB 流窗口与 128MB 连接窗口，规避跨境长肥管道瓶颈。
> - **默认节点集**：默认完整安装并激活实测精选的 **8 大核心节点**（涵盖 Hysteria2-H3-Direct、Hysteria2-TLS-BBR-Salamander、VLESS-Reality-XHTTP-Direct、VLESS-TLS+PQ+XHTTP+CDN、VLESS-XHTTP-Direct-H2、VLESS-XHTTP-Direct-H3、VLESS-Reality-Up-CDN-Down、VLESS-CDN-Up-Reality-Down），客户端订阅与配置按节点名称严格升序排序分发，覆盖 TCP、UDP 及正反双向上下行分离最佳全协议栈。备用节点（CDN-H2/H3、Reality-Vision、PQ-Vision 等）默认置于备用库，可随时通过 `xh` 菜单或 CLI 命令一键启用。

---

## 🛠️ 管理工具 `xh`

安装后终端直接输入 `xh` 即可呼出管理交互菜单，或使用常用子命令：

```bash
xh status             # 查看服务运行状态、监听端口与 TCP 流控参数
xh info               # 查看节点参数明细与客户端直连链接
xh sub                # 输出各平台订阅链接与终端二维码
xh reality            # 查看与开关 Reality Vision / XHTTP 节点
xh restart            # 平滑重启 xray 与 nginx 服务
xh log xray           # 跟踪查看 Xray 实时访问与连接日志
xh tuning on|off      # 开启 / 回滚系统底层流控调优（BBRv3 / 缓冲区 / TFO）
xh update             # 检查并更新 Xray 内核（稳定版通道，自检失败自动回滚）
xh cert show|dnscf    # 查看证书状态或切换 Cloudflare DNS-01 自动续签
xh argo status|update # Cloudflare Argo 隧道 (cloudflared) 状态与一键内核更新
xh warp status|update # Cloudflare WARP 出站状态查看与账户凭据动态更新
```

---

## 🔐 订阅服务（HTTPS）

`xh sub` 输出的订阅由安装时部署的 Nginx 通过 **HTTPS（443）** 提供，使用与节点相同的 ACME 证书，无需额外订阅服务和端口：

```text
https://<证书域名>/sub/<token>/v2rayn.txt         # v2rayN / 通用 Base64
https://<证书域名>/sub/<token>/v2rayn-tun.txt     # v2rayN TUN 优化
https://<证书域名>/sub/<token>/shadowrocket.txt   # Shadowrocket
https://<证书域名>/sub/<token>/mihomo-full.yaml   # Mihomo 完整分流
https://<证书域名>/sub/<token>/mihomo-nodes.yaml  # Mihomo 纯节点
```

* **token 路径**：`<token>` 为随机字符串，token 不对或不存在时返回 404；HTTP（80）请求会 301 跳转到 HTTPS。
* **证书续期**：acme.sh 续期后自动重启 Nginx 与 Xray，订阅证书随之更新，无需手工处理。
* **私钥权限**：`/etc/ssl/private/private.key` 仅 `root:xray` 可读（640），不再对所有用户开放。
* **二维码**：安装结束时输出 V2RayN、V2RayN TUN、Shadowrocket、Mihomo 完整/纯节点订阅的终端二维码，并保存为 `~/subscription-*.png`。

---

## 🔒 Cloudflare 证书申请与管理 (SSL/TLS)

本项目配备针对真实域名的高效自动化证书管理流水线，支持两种最佳工程实践：

### 方案 A：Cloudflare DNS-01 API Token 自动申请（推荐）
通过 Cloudflare 的 DNS 质询申请 Let's Encrypt 证书，**完全无视运营商 80 端口封锁与公网防火墙拦截**，支持自动续签：
1. 登录 [Cloudflare 控制台](https://dash.cloudflare.com/) -> **我的个人资料** -> **API 令牌** -> **创建令牌**；
2. 选择 **编辑区域 DNS (Edit zone DNS)** 模板，在「区域资源」中包含你托管的域名，点击继续并创建令牌；
3. 在 VPS 终端中执行一键配置命令：
   ```bash
   CF_Token="你的Cloudflare_API_Token" xh cert dnscf
   ```
4. 脚本将自动调用 `acme.sh` 完成 DNS-01 验证、颁发权威证书并自动配置 Nginx，每月自动定时无感续期。

### 方案 B：Cloudflare Origin CA 证书（15 年超长有效期）
若你的直连或 CDN 域名已开启 Cloudflare 代理，推荐使用官方 Origin CA 证书：
1. 登录 Cloudflare 控制台 -> 选择域名 -> **SSL/TLS** -> **源服务器 (Origin Server)** -> **创建证书**；
2. 选择默认的 15 年有效期，生成并复制 **源证书 (Certificate)** 与 **私钥 (Private Key)**；
3. 将证书保存至 `/etc/nginx/certs/fullchain.cer`，私钥保存至 `/etc/nginx/certs/cert.key`；
4. 执行 `xh restart` 平滑重载；在 Cloudflare 的 SSL/TLS 模式中选择 **完全(严格) / Full (Strict)**，实现全链路金融级加密。

### 证书状态检测
随时在终端执行以下命令查看当前证书状态：
```bash
xh cert show
```

---

## ☁️ Cloudflare WARP 与 Argo 隧道原生管理

本项目原生整合了 Cloudflare 官方出站与隧道技术：

* **Cloudflare Argo 隧道 (`cloudflared`)**：
  - `xh argo status`：查看本地 `cloudflared` 内核版本与运行状态；
  - `xh argo update`：一键自动从 Cloudflare 官方检测并下载更新最新内核（已集成官方最新稳定版 **`2026.10.3`**，适配 ARM64 与 AMD64）；
  - `xh argo on <token>`：输入 Cloudflare Zero Trust Tunnel Token，一键配置并注册为 systemd 开机自启服务；
  - `xh argo off`：平滑停止并卸载 Argo 隧道。
* **Cloudflare WARP 原生出站与流媒体解锁**：
  - `xh warp status`：查看 WARP 凭证状态与 Cloudflare 分配的专属出站 IPv6；
  - `xh warp update`：调用官方多 API 接口动态申请、刷新专属 WireGuard 凭据，自动解锁 OpenAI/ChatGPT/Claude/Netflix 等流媒体与 AI 服务。

---

## 🛡️ 安全审计与工程加固细节 (Security Audit Fixes)

本项目于 2026-10-22 完成基于 `security-audit` skill 的全库独立沙箱安全审计（11 项高/中危隐患全部修复并通过双校验器闭环）：

1. **注入攻击全面免疫**：
   - `src/04-input.sh`：`normalize_proxy_origin` 收敛为严格主机名/IP 正则，彻底根绝 Nginx 换行与分号指令注入；
   - `src/11-client-config.sh`：`apply_node_names` 剥离 Perl `/e` 执行模式，采用安全环境变量传递，消灭客户端渲染时命令执行；
   - `src/05-base-env.sh`：加入对 `ip.sb` 返回 IP 的严格正则校验，杜绝网络劫持下的 Python 代码注入；
   - `src/13-manage-cli.sh`：`update_node_env` 废止未转义 `sed -i`，采用原子临时文件与 `%q` 安全转义写入，消灭 root 环境变量加载 RCE。
2. **凭据安全与边界隔离**：
   - 安装器禁止将 `USER_HOME` 盲目降级归属于普通用户（UID 1000），保护节点私钥凭证与 Google Drive OAuth Token；
   - 客户端配置文件生成时强制施加 `chmod 600` 私有权限。
3. **协议与限速防护强化**：
   - Nginx 回落层增加 `CF-Ray` 真实边缘标识校验与合法 IP 格式匹配，阻断外部直连伪造 `CF-Connecting-IP` 绕过 `/sub/` 限速；
   - Xray 配置动态化解密参数，支持与严格后量子加密模式强联动。
4. **依赖供应链强校验**：
   - 初装 Nginx 源码构建迁移至隔离 `mktemp -d` 目录，并引入官方 PGP 签名主指纹强校验；
   - 压测工具监听锁定 `127.0.0.1`，消除公网免密 SOCKS5 开放代理；
   - TCP Brutal 下载彻底剥离非认证管道执行，对齐 Release SHA256 完整性摘要校验。

---

## 🚀 性能与架构调优特性

1. **拥塞控制与流控基准**：宿主机全面落地 **BBRv3 + FQ**，TCP 读写缓冲上限收敛于 **64MB**，TSQ 队列限制 **4MB**，彻底消灭 Bufferbloat 拥塞膨胀与队头阻塞。
2. **TCP Fast Open (TFO)**：全入站启用 TFO，三次握手携带第一段应用数据，节约 1 个 RTT。
3. **XUDP 封包加速**：订阅与直连链接均注入 `&packetEncoding=xudp`，消除网页 DNS 解析与 UDP 单包传输排队延迟。
4. **XTLS Vision 零拷贝**：Reality Vision 采用 Linux 内核 `splice()` 直发。客户端请务必**关闭 Mux（多路复用）**以释放极速性能。
5. **多端订阅即开即用**：自动适配 v2rayN（全量 base64 / TUN）、Mihomo（完整分流 / 纯节点）、Shadowrocket（自动过滤不兼容协议）及 Sing-box。
