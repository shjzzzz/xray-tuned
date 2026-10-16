# 项目运作与排障记忆 (Memory)

> [!IMPORTANT]
> ### 🏆 生产环境当前权威技术基线速查表（Authoritative Baseline）
> 本文档记录了架构演进与深水区排障的完整探索历史。为避免历史中间方案误导，当前生产环境生效的最终裁定如下：
> 
> | 架构维度 | 当前生产环境权威规范 | 最终裁定章节 |
> | :--- | :--- | :--- |
> | **Xray 内核与通道** | 官方稳定版 **`v26.3.27 stable`** (`XRAY_CHANNEL=stable`)，跳过 pre-release | 第 20 节、第 21 节 |
> | **拥塞控制 (CC)** | 全协议、入站、直连出站统一使用 **`BBRv3 + FQ`**（彻底废止 Brutal，根绝 Bufferbloat） | 第 21 节、第 22 节 |
> | **系统流控与缓冲** | 单流保护上限 **64MB**，TSQ 发送队列限制 **4MB**，反压 `tcp_notsent_lowat=16KB` | 第 7 节、第 22 节 |
> | **CDN-H2 节点** | 严格单一 **`alpn=h2`**，物理连接并发 **`maxConnections: 16`**，Nginx `Alt-Svc: clear` | 第 14 节、第 19 节 |
> | **CDN-H3 节点** | 独立纯 QUIC 节点 **`alpn=h3`**，QUIC 窗口：流 **64MB** / 连接 **128MB** | 第 14 节、第 19 节 |
> | **DNS 回退解析** | 三核 Anycast DOH/DOD（`9.9.9.10` / `1.1.1.1` / `8.8.8.8`，弃用 `127.0.0.53`） | 第 12 节 |
> | **MTU 与防黑洞** | 网卡 MTU **1500**，全链路 iptables **`TCPMSS --clamp-mss-to-pmtu`** | 第 5 节、第 15 节 |
> | **双回环与多端兼容** | 8001（V2RayN/Mihomo，mlkem） / 8002（Shadowrocket，免解密）分立 | 第 1 节、第 8 节 |

---

## 1. Shadowrocket CDN 节点连通性规范与修复记录 (2026-10-07)
- **故障背景**：新版 Shadowrocket 客户端拉取订阅后 CDN 节点不通（或订阅中缺失 CDN 节点）。
- **根因分析**：
  1. `12-subscription.sh` 与 `13-manage-cli.sh` 此前存在强限制：`FEATURE_XHTTP_VLESSENC=true` 时会主动在小火箭专属订阅（`shadowrocket.txt`）中剥离 CDN 节点。
  2. Xray 8001 入站启用了后量子加密（`mlkem768x25519plus`），新版 Shadowrocket 的 VLESS 握手不支持该嵌套解密层，直连报错 `error 5`。
  3. 小火箭对复杂 JSON 参数（如 `extra`、`fm`）解析存在兼容性问题。
- **架构解法（双入站与专属独立路由）**：
  1. **Xray 双回环入站**：
     - `127.0.0.1:8001`：保留给 V2RayN / Mihomo 等，支持 `mlkem768x25519plus`。
     - `127.0.0.1:8002`：专门给 Shadowrocket 等原生客户端，`decryption: none`。
  2. **Nginx 路由分流**：
     - 原始 `/xhttp-path` 路由转到 `8001`。
     - 独立 `/sr-xhttp-path`（即 `/sr${XHTTP_PATH#/}`）路由通过 `upstream xray_xhttp_sr` 转发到 `8002`。
  3. **订阅生成逻辑**：
     - 小火箭专属订阅自动注入标准格式的 `VLESS-XHTTP-CDN-H2` 节点（连接 `bestcf-domain:443`，SNI `cdn-domain`，path `/sr-xhttp-path`，`encryption=none`）。
  4. **Reality 握手兼容**：
     - 配置 `minClientVer: 1.8.0`（通过 `xh minversion on`），避免非官方 Xray 客户端在 Reality 阶段被握手校验拒绝。

## 2. Xray 内核更新通道规范 (2026-10-07)
- **更新策略**：默认通道改为 `stable`（官方正式版）。
  - 自动更新任务（每周日 04:00）默认仅拉取 GitHub Releases 中的正式版本（`/releases/latest`），遇到 Pre-release 自动跳过，保障生产环境稳定。
  - 用户若需体验 Pre-release 版本（如 26.9.30+ 的后量子加密新特性），可通过 `xh autoupdate pre` 或在菜单选择 `6` 手动输入 `pre` 切换。

## 3. Reality 节点连通性与 Xray 26.9+ 后量子强卡控排障 (2026-10-07)
- **故障背景**：Shadowrocket / sing-box / Clash Meta 连接 Reality 节点报错 `reality verification failed`。
- **根因分析**：
  - Xray v26.9.8+ (如 26.9.30) 在 REALITY 握手层对客户端强制要求后量子混合密钥 `X25519MLKEM768`。即便配置了 `minClientVer: 1.8.0`，底层密码学握手仍被内核硬阻断，第三方客户端无法连通。
- **解决对策**：
  - 生产环境将 Xray 内核回退并锁定为官方稳定正式版 **v26.3.27**，并开启 `minClientVer: 1.8.0`。
  - 实测 sing-box / Shadowrocket 与原生 Xray 客户端均秒级握手成功，连通性完全恢复。

## 4. 全节点连接与下载稳定性、持续性调优 (2026-10-07)
- **故障背景**：CDN 节点及部分直连节点在大文件下载、持续测速或长连接时出现断断续续、周期性卡顿或中途断流。
- **根因分析**：
  1. **Nginx 反代超时过紧**：全局 `client_body_timeout 10s` 和 `send_timeout 10s`。在 CDN 大文件传输或网络轻微抖动时，Nginx 在 10 秒无突发吞吐时会主动断开客户端连接。
  2. **XHTTP 上行重连周期过短**：Xray 默认 `scStreamUpServerSecs` 配置为 `"20-50"` 秒，导致服务端每 20~50 秒强制重置上行流，客户端频繁重连切片引发周期性停顿。
  3. **TCP 套接字关闭截断**：Xray policy 的 `uplinkOnly: 5s` 与 `downlinkOnly: 10s` 在单向关闭（FIN）时过快杀死连接，残余下行数据包未接收完毕即被掐断。
- **解决对策与优化项**：
  1. **Nginx 长连接保护**：在 `/xhttp-path` 与 `/sr-xhttp-path` 位置块显式配置 `client_body_timeout 300s` 与 `send_timeout 300s`，配合已有的 `grpc_read_timeout 1h` 与 `grpc_send_timeout 1h`，彻底消除 Nginx 提前切断长连接。
  2. **XHTTP 流保活周期扩容**：将 `scStreamUpServerSecs` 调整放宽至 `"300-600"` 秒（5~10分钟），避免 20 秒短周期频繁握手重连。
  3. **Xray Policy 优雅关闭放宽**：调整 `uplinkOnly: 15s` 与 `downlinkOnly: 30s`，保证大文件下载与尾部数据完整平滑传输。
  4. **系统级持续性参数**：保持内核 `tcpUserTimeout: 300000ms` (5分钟) 与 `tcpKeepAliveIdle: 30s`，抗击跨境链路短暂丢包与抖动。

## 5. 网卡 MTU 1500 调优与系统持久化规范 (2026-10-07)
- **背景与原因**：
  - Oracle Cloud 等云厂商默认网卡 MTU 为 9000（巨型帧），而公网标准物理以太网 MTU 为 1500。
  - 超过 1500 的巨帧在出公网边界时会遭遇 PMTU 黑洞（因中间节点丢弃 ICMP Fragmentation Needed 导致大包被静默丢弃，表现为握手成功但传输大文件/TLS 证书时断流）。
  - 因此将物理网卡 MTU 严格锁定为标准以太网上限 **1500**，并配合 `TCPMSS --clamp-mss-to-pmtu` 确保端到端通信无分片丢包。
- **持久化方案**：
  1. 系统配置 `/etc/netplan/99-mtu.yaml` 覆盖 cloud-init 默认值（锁定 `mtu: 1500`），经 `netplan generate` 注入底层 `systemd-networkd`（`MTUBytes=1500`）。
  2. 开机调优脚本（`xray-xhttp-nic-tune` / `sbbox-nic-tune`）将 MTU 校验上下限均对齐至 **1500**，杜绝开机回退为 1480 或 9000。
## 6. 全链路网络与节点性能排障与“罪证”清理规范 (2026-10-08)
- **故障背景**：节点网络吞吐受限、出现周期性微抖动，以及 TCP 握手重传率高（SNMP 显示重传数达 33 万+）。
- **根因分析**：
  1. **Xray Freedom 直连出站拥塞控制与 MPTCP 误配**：
     - `xray-config.json.tmpl` 中 freedom 出站误继承了 `${XRAY_TCP_CC:-brutal}` 以及 `tcpMptcp: true`。
     - TCP Brutal 属于单向固定速率算法，强行作用于 VPS 访问公网目标（Google、YouTube、Cloudflare）的自由出站连接时，导致拥塞窗口畸形膨胀（高达 14855 报文）并引发中间路由器缓冲区溢出与丢包。
     - 公网绝大多数目标服务器和防火墙不识别 TCP SYN 中的 `MP_CAPABLE` 选项，易引发 1~3 秒 RTO 超时重传。
  2. **DNS 本地解析死地址**：
     - Xray 配置 fallback 的 DNS 服务器填写了 `localhost`（即 127.0.0.1:53），而 systemd-resolved 仅监听在 127.0.0.53，导致本地回退查询被拒绝连接。
  3. **Cloudflare 优选 IP 测速逻辑颠倒**：
     - 在美西 VPS 上执行 `cfst` 测速只会选出美西本地（SJC 0.8ms）节点并同步至 DNS，给国内客户端造成跨洋劣质路由。
- **解决对策与优化规范**：
  1. **锁定 Freedom 出站协议栈**：
     - 显式将 freedom 出站中的 `tcpcongestion` 锁定为标准的 `"bbr"`，同时关闭 `"tcpMptcp": false`，严禁在直连出站上使用 Brutal。
     - `06-tuning-lib.sh` 中的 `set_tcp_brutal_xray` 在开启 Brutal 时通过正则守卫，确保 freedom 出站始终维持 BBR。
  2. **修复 DNS 本地解析（注意：后续已被第 12 节升级替代）**：
     - `xray-config.json.tmpl` 中的 fallback DNS 此前修正为 `127.0.0.53`。
     - *演进标注*：在 **第 12 节 (第 4 条)** 中发现 `127.0.0.53` 处理特定压缩标签会报 `segment prefix is reserved` 崩溃，当前已全面升级替换为权威 Anycast DNS `8.8.8.8` / `9.9.9.10` / `1.1.1.1`。
  3. **停用境外服务端优选定时器**：
     - 明确优选 IP 测速必须在客户端或本地网关执行，停用服务端的 `cf-bestip.timer` 与 `cf-healthcheck.timer`。

## 7. 全局单流缓冲区保护上限 64MB 规格调整与 Brutal 卸载 (2026-10-08)
> [!NOTE]
> **演进与权威状态**：本节确立的 **64MB 单流保护上限** 始终权威有效（参见第 22 节）。其中关于 Brutal 退役的结论，在第 17/20 节曾尝试按档位限速重新引入，但最终在 **第 21 节** 经国内移动真实连接抓包证实其缺乏退避机制必将导致晚高峰 2.75 秒 Bufferbloat，因而在第 21 节已最终定案彻底废止 Brutal，全协议永久回归 BBRv3。

- **背景与原因**：
  - 此前 medium/large 档位将单流缓冲区保护上限与 TCP 读写缓冲直接开至 128MB (`134217728` 字节)。
  - 在高突发多并发连接场景下，单流无节制增长至 128MB 会导致内存池被局部大流侵占，增加系统 OOM 风险。
  - 彻底停用并卸载内核 `brutal` 模块，使全协议回归标准 BBRv3 控制环路。
- **调整规范**：
  1. **缓冲区保护上限降至 64MB**：
     - `net.core.rmem_max` 与 `net.core.wmem_max` 调整为 `67108864` (64MB)。
     - `net.ipv4.tcp_rmem` 与 `net.ipv4.tcp_wmem` 的最大值从 128MB 收敛为 `67108864` (64MB)。
     - `06-tuning-lib.sh`、`13-manage-cli.sh`、`ubuntu_vps_optimize.sh`、`vps-tune.sh` 中的 large/medium 档位计算及 `show` 摘要展示统一对齐 64MB 规格。
  2. **Brutal 彻底退役**：
     - 内核中通过 `rmmod brutal` 卸载模块，禁用 `tcp-brutal-rules.service`，清理开机加载项。

## 8. CDN 节点连通性排障与多客户端兼容性规范 (2026-10-08)
- **故障背景**：客户端拉取订阅后测试 CDN 节点显示延迟为 `-1`（连接超时/不可达）。
- **根因分析**：
  1. **Cloudflare 默认 Anycast IP 遭遇 GFW 阻断**：
     - 服务端自动同步将优选域名绑定到了美西本地 SJC 的 `104.21.x.x` IP，而 CDN 域名默认解析也是 Cloudflare 易被墙的 `172.67 / 104.21` 段。大陆网络环境下该 IP 段的 443 端口被运营商与 GFW 大面积阻断丢包，TCP 握手无法完成，直接超时报 `-1`。
  2. **Shadowrocket 专属订阅回退 Bug**：
     - `node.env` 缺少 `BESTCF_DOMAIN` 时，小火箭订阅中的 CDN 节点连接地址回退成了被墙的默认 CDN 域名，而非优选 IP。
  3. **客户端对后量子加密（ML-KEM-768）不兼容**：
     - Mihomo (Clash Meta) 与旧版 V2RayN (Xray < 26.9) 不支持 VLESS 嵌套后量子加密（`mlkem768x25519plus`），带该加密的节点在上述客户端测速必然报错 `-1`。
  4. **Sing-box 客户端 TUN MTU 9000 巨帧黑洞**：
     - `sbox_client.json` 中 TUN 入站硬编码 `"mtu": 9000`，客户端发出巨型帧在公网触发 PMTU 黑洞丢包。
- **解决对策与多端兼容规范**：
  1. **优选 IP 绑定纯净 Anycast 段**：
     - 优选域名必须绑定国内运营商访问优良的官方纯净 Anycast IP 段（如 `104.16.x.x`、`162.159.x.x` 优质节点）。
  2. **小火箭专属 CDN 节点规范**：
     - 补齐 `BESTCF_DOMAIN`，小火箭订阅中的 CDN 节点连接地址锁定为优选域名端口 443，SNI/Host 保持 CDN 域名，路由走免加密的 8002 入站（`/sr-path`，`encryption=none`）。
  3. **客户端协议差异化下发**：
     - Mihomo/Clash 与普通客户端使用免后量子加密的标准节点。
     - Shadowrocket TUIC 链接显式补齐 `version=5`，Naive 转换为 `http3://` / `http2://`，过滤不支持的 `anytls`。
     - Sing-box 客户端 TUN 入站 MTU 严格锁定为标准物理以太网 `1500`。


## 9. sbbox 多端客户端全兼容规范与发布落地 (v2.7.65, 2026-10-08)
- **多端适配矩阵**：
  1. **Sing-box 原生客户端**：
     - TUN 入站 MTU 全面修正为 `1500`（物理以太网标准），消灭 PMTU 巨帧丢包黑洞。
  2. **Shadowrocket (小火箭)**：
     - TUIC 链接显式补齐 `version=5`，防止小火箭误判为 v4 导致握手失败。
     - Naive 链接在识别小火箭 UA 时自动由 `naive+quic://` / `naive+https://` 转换为 `http3://` / `http2://`。
     - 自动过滤剔除小火箭不支持的 `anytls://` 协议，确保导入节点 100% 可用。
  3. **Clash / Mihomo**：
     - `clmi.yaml` 默认隔离 `type: anytls`，并在 `sub_server.py` 下发时执行 `sanitize_clash_yaml` 清洗，防止内核因未知代理类型报错崩溃。
     - 保持 TUIC (`congestion-controller: cubic`) 与 Hysteria2 (`obfs: salamander`) 规范完全兼容。
  4. **v2rayN**：
     - `anytls://` 与 `tuic://` 强校验携带 `security=tls`，满足 core 解析要求，防止无 TLS 配置闪退。
- **发布记录**：
  - 仓库：`ShJChow/New-sing-box-naiveproxy-tuic-hy2-tuning`
  - 版本：`v2.7.65`，Commit: `fc14735`


## 10. CDN 节点自适应 ALPN (h2, h3) 规范与落地 (2026-10-09)
> [!WARNING]
> **【已废弃 / SUPERSEDED BY 第 14 节】本章节设想的 `alpn=h2,h3` 自适应方案在实际生产中已被推翻，请勿采纳！**
> * **废弃原因**：Cloudflare CDN 边缘对 XHTTP 不支持 H3 长连接流（`stream-up` 模式会被切断）；且 Shadowrocket (小火箭) 收到 `h2,h3` 后会在 443 上强行发起 UDP 握手，导致连通性彻底归零。
> * **最终权威方案**：见 **第 14 节**。`CDN-H2` 严格锁定单一 `alpn=h2`；QUIC 协议则分立为独立的 `CDN-H3` 节点 (`alpn=h3`)。

- **背景与需求**：
  - 此前 CDN 节点在客户端 URI 和配置中写死为单一协议（如仅 `alpn=h2` 或仅 `alpn=h3`）。
  - 当客户端网络环境或代理工具对 HTTP/2 与 HTTP/3 (QUIC) 具备不同支持度时，单一协议锁定会导致无法动态协商最优传输层。
  - 调整 CDN 节点为自适应协商 ALPN (`h2, h3`)。
- **调整规范与多端落地**：
  1. **VLESS URI 链接规范**：
     - CDN 节点链接中的 `alpn` 参数调整为 `alpn=h2,h3`（小火箭/v2rayN/Xray 原生均支持逗号分隔解析为 `["h2", "h3"]` 列表）。
  2. **Mihomo (Clash Meta) 代理条目**：
     - `VLESS-XHTTP-CDN-H2` 的 `alpn` 配置更新为 `[h2, h3]` 列表。
     - 同时保留纯 QUIC 的 `VLESS-XHTTP-CDN-H3` (`alpn: [h3]`)，使 Mihomo 的「自动选择」测速组能在 TCP 与 QUIC 间智能择优。
  3. **小火箭 (Shadowrocket) 专属订阅**：
     - 免加密 8002 入站通道下发的 CDN 节点同步下发 `alpn=h2,h3` 与 `alpn=h3,h2`，由客户端自主发起握手协商。
  4. **管理脚本与安装包对齐**：
     - `11-client-config.sh`、`12-subscription.sh`、`13-manage-cli.sh`、`/usr/local/bin/xh` 以及 `dist/` 安装包全量更新。

## 11. 借鉴 Yulinanami 项目：静态回落规范化、Nginx Alt-Svc 广播与参考资料体系演进 (2026-10-09)
- **背景与借鉴来源**：
  - 对标并吸收开源项目 [Yulinanami/my-xhttp-cdn-config](https://github.com/Yulinanami/my-xhttp-cdn-config) 的工程实践规范。
- **优化与改进明细**：
  1. **静态站回落目录规范化 (`/var/www/dist`)**：
     - 将静态回落根目录由 `${USER_HOME}/dist` 规范迁移至符合 Linux FHS 标准的 `/var/www/dist`，彻底杜绝 Ubuntu/Debian 普通用户 home 目录权限（700）下 Nginx 运行身份（nobody/www-data）因权限不足导致的 403 报错；
     - 保持向后兼容：当 `${USER_HOME}/dist` 存在时自动平滑识别，目录与文件统一赋予 755/644 安全访问权限；
     - 同步更新 `src/04-input.sh`、`extensions/dual-cdn/01-read-existing.sh`、`extensions/dual-ip/01-read-existing.sh`。
  2. **Nginx HTTP/3 广播声明 (`Alt-Svc`)（注意：CDN 虚拟主机部分已被第 14 节推翻废弃）**：
     - > [!CAUTION]
     - > **【第 2 项部分废弃】**：在 Nginx CDN 虚拟主机上广播 `Alt-Svc: 'h3=":443"'` 会导致客户端强升 H3 并被 Nginx 防探测 444 阻断。该项已在 **第 14 节** 中被彻底推翻，当前 CDN 虚拟主机实际配置已改为 `add_header Alt-Svc 'clear' always;`。普通伪装站或直连站仍可广播。本节第 1/3/4/5 项继续有效。
     - 在 `templates/nginx.conf.tmpl` 与本机运行的 Nginx 对应 server 块中，加入标准 HTTP/3 响应头声明：`add_header Alt-Svc 'h3=":443"; ma=86400' always;`；
     - 使得伪装站点和直接请求对现代浏览器和客户端通告 443 端口支持 HTTP/3，对齐主流互联网大厂（Cloudflare/Google）真实站点行为特征。
  3. **Mihomo TUN DNS 劫持防护强化**：
     - 在 `templates/mihomo-full.yaml.tmpl` 的 `tun.dns-hijack` 中补充 `- tcp://any:53`，MTU 锁定标准 `1500`，杜绝 TCP DNS 查询绕过劫持导致的泄露。
  4. **全套权威参考资料与协议规范体系 (`docs/参考资料.md`)**：
     - 补充 `docs/参考资料.md`，完整收录 Xray-core XHTTP 官方讨论（#4113, #4118）、xpadding 长度混淆泄露分析与 BBS 讨论、Cloudflare ECH 边缘规范与 Xray-core v26.3.27 演进、Mihomo 传输标准、以及 BBRv3 / 64MB 单流保护模型。
  5. **客户端直连与 CDN 灵活路由切换指引**：
     - 在 `README.md` 中补充技术解析：阐明 SNI 锁定 CDN 域名时，客户端 Server 地址在「CDN 优选 IP」与「真实 VPS IP」之间切换的原理，方便用户按需一键切换低延迟直连或抗封锁 CDN。

## 12. 基于 REA-Agents 二进制逆向洞察的 Xray 运行时与硬件级调优 (2026-10-09)
- **背景与逆向发现**：
  - 通过 `rea-agents` 对 `/usr/local/bin/xray` (Xray 26.3.27 ARM64 静态 ELF) 进行结构与 Go buildinfo 深度逆向分析：
    1. **硬件特性匹配**：宿主机为 ARM Neoverse-N1 (ARMv8.2-A)，具备硬件 `atomics` (LSE)、`aes`、`pmull`、`sha1`、`sha2` 与点积指令加速，而预编译版仅锁定 `GOARM64=v8.0`；
    2. **Go 运行时 GC 与调度瓶颈**：当前 VPS 拥有 24GB 物理内存，而默认 Go 运行时无软内存限制（GOMEMLIMIT 未设定），高吞吐并发下容易因默认 GOGC 行为发生不必要的 GC 停顿或抖动。
- **优化与工程落地**：
  1. **自适应 Go 运行时软上限 (`GOMEMLIMIT`)**：
     - 在 `06-tuning-lib.sh` 与系统 drop-in (`10-xray-xhttp.conf`) 中加入动态自适应逻辑：大内存机（>=2GB）将 `GOMEMLIMIT` 设定为物理内存的 75%（24GB 机器设为 `18GiB`），允许 Go 运行时充分享受大物理内存对象池，彻底消除并发激增时的 GC 停顿；小内存机保持 60% 防止 OOM。
  2. **锁定内存与进程调度加固 (`LimitMEMLOCK` / `Nice`)**：
     - drop-in 中追加 `LimitMEMLOCK=infinity`，提升 UDP/QUIC 缓冲区锁定能力；
     - 追加 `Nice=-10`，赋予 Xray 核心更高的系统级 CPU 调度优先级，消除网络包处理的排队调度抖动。
  3. **实时生效与验证**：
     - 本机 `/etc/systemd/system/xray.service.d/10-xray-xhttp.conf` 已更新并重载生效，Xray 进程成功加载 `GOMEMLIMIT=18GiB`、`LimitMEMLOCK=infinity` 并在 7 个核心端口稳定监听。
  4. **彻底修复 systemd-resolved 回退 DNS 异常**：
     - 将 fallback DNS 统一修正为全球权威 Anycast DNS `8.8.8.8`（与 `9.9.9.9`、`1.1.1.1` 组成三核 Anycast 冗余），彻底根除 `127.0.0.53` 在处理特定压缩标签时触发的 `segment prefix is reserved` 异常；
     - 本机 `/usr/local/etc/xray/config.json` 与 `templates/xray-config.json.tmpl` 均已同步修正，Xray 进程零报错稳定运行。

## 13. REA-Agents 工具链集成规范与二进制分析沉淀 (2026-10-09)
- **环境部署与 MCP 对齐规范**：
  1. **配置预校验**：
     - `/root/.gemini/config/mcp_config.json` 严禁出现 0 字节空文件，空文件会触发 Inquirer/CLI 内部 JSON 解析阻断（报 `malformed`）；必须预置基础合法 JSON 对象 `{"mcpServers": {}}`。
  2. **跨 Client 多端自动配置**：
     - 使用命令 `npx -y rea-agents setup --all-detected --yes` 可无交互自动完成当前环境检测到的所有 AI Client 配置（Antigravity、Claude Code、Gemini CLI），三端状态均达成 `aligned` / `configured`。
  3. **逆向 Skill 安装位置**：
     - REA 逆向工程 Skill 固化于 `/root/.agents/skills/reverse-engineer-anything`（v33，集成了 139 个静态分析与探测工具）。
- **Go/ELF 二进制逆向与性能审计实践**：
  1. **Go 构建图谱提取**：
     - 即使 Go 二进制经过 `strip` 剥离了常规符号表，ELF 的 `.go.buildinfo` 段依然完整封装了构建依赖版本树、编译器标志（`-gcflags`、`-trimpath`）、CGO 状态以及架构参数（`GOARM64` 等），可通过 REA 与十六进制解析直接提取。
  2. **指令集与硬件匹配审计**：
     - 将逆向提取的编译架构参数（如 `GOARM64=v8.0`）与宿主 CPU 硬件指令集（如 Neoverse-N1 的 `atomics/LSE`, `aes`, `pmull`, `sha2`, `crc32`）进行对标，能够精准识别并发原子操作（LL/SC 循环 vs 原生 LSE 硬件指令）与硬件加速的潜在性能差距。
  3. **非侵入式运行时性能加固**：
     - 在无法随意替换核心二进制的生产环境中，优先通过 Go 运行时环境变量（`GOMEMLIMIT`、`GODEBUG`、`GOGC`）与 Linux cgroup/systemd 调度参数（`Nice`、`LimitMEMLOCK`）释放机器物理硬件极限，达成零停机零风险的最佳性能调优。

## 14. Shadowrocket 小火箭 CDN-H2 连通性彻底修复与协议解耦 (2026-10-09)
- **故障排查与根因剖析**：
  1. **Cloudflare CDN 特征约束**：
     - Cloudflare 边缘节点对 HTTP/3 (QUIC) 并不支持 XHTTP 双向长连接流（`stream-up` 模式），请求体会被边缘缓冲或切断；XHTTP CDN 必须基于 HTTP/2 (TCP) 稳定承载。
  2. **`alpn=h2,h3` 误导客户端**：
     - 此前将 CDN-H2 节点的 ALPN 调整为自适应 `h2,h3`，小火箭 (Shadowrocket) 收到包含 `h3` 的 ALPN 会在 `bestcf` 优选 IP 上优先发起 UDP 443 QUIC 握手或引发 TLS 协商异常，导致连通性彻底归零。
  3. **Nginx Alt-Svc 广播导致客户端强升 H3**：
     - Nginx 在 `cdn.*` 虚拟主机上广播了 `Alt-Svc: 'h3=":443"; ma=86400'`，小火箭缓存此响应头后后续所有连接会被强制切换到 UDP 443；同时 Nginx 内部的 `$h2only` 防探测规则会将协议非 `HTTP/2.0` 的请求直接 `return 444`。
  4. **Nginx 错误监听宿主机 UDP 443 QUIC**：
     - CDN 流量经 Cloudflare Anycast 回源恒为 TCP，Nginx CDN 虚拟主机不应绑定宿主机 UDP 443。
- **修复方案与落地**：
  1. **CDN-H2 严格锁定 `alpn=h2`**：
     - 在 `11-client-config.sh`、`12-subscription.sh`、`13-manage-cli.sh`、`/usr/local/bin/xh` 中将 `VLESS-XHTTP-CDN-H2` 的 ALPN 严格设回 `alpn=h2`，与独立 QUIC 节点 `VLESS-XHTTP-CDN-H3` (`alpn=h3`) 明确分立。
  2. **Nginx CDN 块精简与缓存即时清除**：
     - 移除 Nginx CDN 虚拟主机的 `listen 443 quic reuseport;` 与 `add_header Alt-Svc ...` 广播；
     - 在 `/sr...` 及主 XHTTP location 显式注入 `add_header Alt-Svc 'clear' always;`，彻底清除所有客户端此前缓存的 Alt-Svc 记录。
  3. **订阅更新与服务验证**：
     - 执行 `xh resub` 重新生成全套明文与 base64 订阅，`nginx -t` 语法检测通过并重载服务，外部 curl 探测验证返回预期的 `HTTP/2 404` 且携带 `alt-svc: clear`。

## 15. 针对中国移动 (CMCC) 链路深度专项网络调优规范 (2026-10-09)
- **中国移动链路特征与核心痛点**：
  1. **跨洋路由绕行与高延迟**：普通 Cloudflare 优选若在美西 VPS 上执行，会选出 San Jose (SJC) 边缘 IP，中国移动客户端请求被迫跨越太平洋，物理延迟高达 180~220ms，晚高峰丢包严重；
  2. **高端口 UDP QoS 与丢包劣化**：中国移动省网及骨干 CMI 节点在晚高峰（20:00-24:00）对非标准高端口 UDP（如 30000+）实行严苛的令牌桶限速或强丢包（丢包率 30%~60%），导致 Hysteria 2 / QUIC 断流；
  3. **PMTU 黑洞丢包**：中国移动家庭宽带普遍采用 PPPoE 拨号（MTU=1492），移动蜂窝网络（4G/5G）经过 GTP-U 隧道封装后 MTU 仅约 1420。若中间防火墙阻断 ICMP Fragmentation Needed，VPS 发出 1500 字节标准以太网大包将被静默丢弃（表现为 TCP 握手正常，但 TLS 握手证书或 HTTP 大响应卡死）；
  4. **高抖动无线链路的拥塞窗口误降与 Bufferbloat**：移动终端在基站切换与弱网抖动时易触发虚假 RTO，导致 TCP 拥塞窗口（cwnd）塌陷；同时过大的套接字未发送缓冲区导致发包队头阻塞。
- **端到端调优与工程落地**：
  1. **CMCC 专属 CMI 香港 Anycast 优选池 (`CMCC_PREFERRED_IPS`)**：
     - 精选经中国移动骨干网 (AS58453 CMI) 直连香港 HKIX 的 Cloudflare Anycast 优质 CMI 节点段；
     - 升级 `dns_updater.py` 与 `probe.py`：优先探测该池中的 CMI 香港边缘，确保 `origin_ok=true` 后写入 Cloudflare DNS 优选记录；实测延迟从 200ms+ 骤降至 15~40ms，彻底消除跨洋丢包。
  2. **TCPMSS 自动钳制 (`--clamp-mss-to-pmtu`)**：
     - 在 iptables `mangle` 表的 `POSTROUTING` 与 `OUTPUT` 链全面注入 `--clamp-mss-to-pmtu`，自动根据客户端报文的 MTU/MSS 进行双向钳制，彻底根除移动宽带 PPPoE (1492) 与移动蜂窝 (1420) 的 PMTU 黑洞。
  3. **内核无线与高 BDP 拥塞控制优化**：
     - `net.ipv4.tcp_notsent_lowat = 16384` (16KB)：根治 TCP send bufferbloat，大幅降低多路复用流的队头阻塞和往返抖动；
     - `net.ipv4.tcp_frto = 2`：启用 Forward RTO 探测，避免移动蜂窝网络偶发抖动误触发 cwnd 骤降；
     - `net.ipv4.tcp_early_retrans = 3`：开启 Tail Loss Probe (TLP)，尾包丢失快速重传，规避耗时极长的全量 RTO 超时。
  4. **Hysteria 2 UDP 443 / 8443 旁路穿透**：
     - 针对中国移动高端口 UDP QoS，在 iptables NAT PREROUTING 注入 `UDP 443 -> HY2_H3_PORT` 与 `UDP 8443 -> HY2_PORT` 重定向规则；
     - UDP 443 伪装为标准公网 HTTP/3 流量，免遭运营商晚高峰高端口限速；在小火箭与订阅系统同步提供 UDP 443 直连节点。
  5. **CDN 优选定时器的高峰期自适应调度 (`OnCalendar`)**：
     - 将此前粗粒度的 12 小时间隔改为中国网络环境的每日高峰时段专属定时调度（北京时间 UTC+8）：
       - 晚间核心高峰（19:00 - 23:00 每整点轮换一次，共 5 次高频重测）；
       - 午间用网高峰（12:30 定时重测）；
       - 凌晨低峰基准同步（04:00 校准）；
     - `probe.py` 补充真实 XHTTP 隧道探测耗时计算（毫秒级），`dns_updater.py` 在测试候选池时随机打乱并解析响应延迟，确保高峰时段由当前真实表现最优的 Anycast 节点提供解析。


## 16. 上下行分离节点 (Reality-Up-CDN-Down) 优选 IP 链路修复规范 (2026-10-10)
- **故障背景**：`VLESS-Reality-Up-CDN-Down`（上行 Reality 直连 VPS / 下行通过 Cloudflare CDN 回传）客户端测速或连接时，发现其下行链路没有走 Cloudflare 优选 IP（`bestcf` 域名），而是走了未优选、易遭阻断的原始 CDN 域名。
- **根因分析**：
  1. `11-client-config.sh` 中 `CDN_CONNECT_ADDR` 变量计算被置于文件后半部分（原仅供 `H2_CDN` / `H3_CDN` 节点使用），位于 `DOWNLOAD_SETTINGS_ENC` 构造之后。
  2. `DOWNLOAD_SETTINGS_ENC` 与 `templates/mihomo-proxies.yaml.tmpl` 的 `download-settings` 将连接地址硬编码为 `${CDN_DOMAIN}`，未继承 `${CDN_CONNECT_ADDR}`。导致客户端在建立下行隧道时直连了未优选的 Cloudflare Anycast IP，失去 `bestcf` 优选加速效果。
  3. 反向分离节点 `CDN-Up-Reality-Down` 的上行连接目标同样未接入 `${CDN_CONNECT_ADDR}`。
- **修复措施与规范**：
  1. **前置 `CDN_CONNECT_ADDR` 计算**：在客户端配置生成器早期解析并校验优选域名/IP（若未配置或不可解析则平滑回退 `${CDN_DOMAIN}`）。
  2. **下行隧道连接目标绑定优选**：
     - Xray URI 参数 `extra.downloadSettings.address` 绑定 `${CDN_CONNECT_ADDR:-${CDN_DOMAIN}}`；TLS SNI (`serverName`) 与 HTTP Host 严格保持 `${CDN_DOMAIN}`。
     - Mihomo 配置 `download-settings.server` 绑定 `${CDN_CONNECT_ADDR:-${CDN_DOMAIN}}`；`servername` 与 `host` 严格保持 `${CDN_DOMAIN}`。
  3. **反向分离节点上行对齐**：`CDN-Up-Reality-Down` 的上行连接地址同样绑定 `${CDN_CONNECT_ADDR:-${CDN_DOMAIN}}`。
  4. **全端订阅与备用节点库重载**：重新渲染本机 `/home/ubuntu/client-config*` 与 `/etc/xhttp-cdn/all/`，并通过 `xh resub` 刷新发布到 Nginx 订阅系统。

## 17. TCP Brutal 极速拥塞控制全面优化与入站分工修复规范 (2026-10-12)
> [!WARNING]
> **【已废弃 / SUPERSEDED BY 第 21 节】本章节的 TCP Brutal 速率调优在真实公网中已被彻底推翻废止，请勿采纳！**
> * **废弃原因**：TCP Brutal 属于单向固定速率算法，缺乏动态拥塞退避机制。在晚高峰跨境公网弱网瓶颈下，固定速率灌包直接引发致命 **Bufferbloat（实测往返时延暴涨 10 倍达 2,745ms，发送队列完全卡死 4.2MB，RTO 飙升至 120 秒，传输速率断崖跌至 186 bps）**。
> * **最终权威方案**：见 **第 21 节**，已执行 `xh brutal off`，全量入站彻底废止 Brutal 并永久回归 **BBRv3 + FQ** 动态自适应拥塞控制。

- **故障与优化背景**：
  1. **Xray Brutal 开启静默失效**：在 `XRAY_DEFAULTS=true` 规范下，`config.json` 不包含预设的 `"tcpcongestion":"bbr"`，导致 `xh brutal on` 的字符串替换落空，Xray 始终未真正应用 Brutal，且 `xh brutal show` 中 `Xray 入站 CC:` 显示为空白。
  2. **默认速率严重超配引发重传风暴**：此前 `get_default_brutal_speed_mbps` 默认绑定物理网卡 95%（Oracle 4000M 网卡即 3800 Mbps）。对于 100M~1000M 的普通家宽客户端，Brutal 不退让的定速发包会导致高达 20%~30% 的丢包和重传风暴，且 3800 Mbps 的 BDP 超过了系统单流缓冲区 64MB 上限。
  3. **双项目诊断体系不同步**：`sbbox brutal show` 缺少 `ss -tin` 实时 CC 连接分布、重传率监测及路由锁检测，且未与 Hysteria 2 原生 Brutal 联动提示。
- **优化对策与工程落地**：
  1. **智能 JSONC 注入与出站保护**：
     - 重构 `set_tcp_brutal_xray`：精准定位 TCP/xhttp/raw 入站并在 `sockopt` 注入 `"tcpcongestion": "brutal"`，`off` 时无缝恢复为 `bbr`；
     - 严格守卫 Freedom 直连出站，确保出站始终维持 `bbr`，防止服务器向外部公网发包时发生拥塞崩溃。
  2. **智能宽带档位推荐交互 (`choose_brutal_speed`)**：
     - 引入多档位智能推荐：100M (90M)、300M (270M，主流推荐)、500M (450M)、1000M (900M)、峰值 (3800M) 与自定义；
     - 当下发速率高于 1500 Mbps 时，`show` 界面主动给出调优告警指引。
  3. **双端管理体系（`xh` / `sbbox`）深度对齐**：
     - 升级 `sbbox brutal show`，同步引入 `ss -tin` 在线连接 CC 吞吐与重传率监控、路由锁检测及 Hysteria 2 Brutal 状态看板；
     - 两端统一交互逻辑与安全边界。

## 18. XHTTP-Direct-H2 入站端口检查修复与 CDN 节点全链路调优规范 (2026-10-13)
> [!NOTE]
> **参数升级标注**：本节关于 `backup_port_busy` 端口检测自锁修复与 Nginx 4MB 缓冲扩容依然权威有效。但其中针对 CDN 节点的参数设定（`maxConnections: 6`，QUIC 窗口 32M/64M）属于中间过渡值，已在 **第 19 节** 中全面升级拉满为 **`maxConnections: 16`** 以及 **流 64MB / 连接 128MB**。

- **背景与核心痛点**：
  1. **Direct-H2 开启冲突与状态脱节自锁**：
     - 在管理脚本 `xh` 菜单 20 开启 `XHTTP-Direct-H2`（TCP 8445）时，报错 `[ERROR] TCP 8445 已被其他进程占用，未做任何修改`。
     - 实际上端口 8445 并非被外部第三方进程占用，而是被 Xray 服务自身正在监听；此时 `node.env` 中 `FEATURE_H2_DIRECT='false'`，管理脚本判定为未开启，执行开启时又被 `backup_port_busy` 拦截，形成不可恢复的死锁循环。
  2. **默认 CDN 节点（CDN-H2 / CDN-H3）实际测速偏慢与链路瓶颈**：
     - 默认生成的 `VLESS-XHTTP-CDN-H2` 与 `VLESS-XHTTP-CDN-H3` 节点通过 Cloudflare CDN 回源，客户端反馈实际测速偏慢。
     - 核心瓶颈集中在：Cloudflare Free Anycast 边缘对单一长连接 TCP/QUIC 物理流的带宽惩罚与限速（通常 15~35 Mbps）；
     - `XRAY_DEFAULTS=true` 策略下客户端 QUIC 接收窗口被降级为默认小窗口，高 RTT 跨洋链路下 BDP 严重受限；
     - Nginx 反代缓冲（`grpc_buffer_size 1024k`、`http2_recv_buffer_size 1024k`）面对高并发多路复用时频繁发生切片与系统调用等待；
     - 优选 IP 解析若漂移至高握手延时的 Anycast 边缘，导致首包和连接握手耗时高达数秒。
- **根因分析**：
  1. **`backup_port_busy` 检测逻辑缺陷**：
     - 原函数直接调用 `ss -Hltn "sport = :$port"` 判断监听，没有区分监听进程是外部竞争进程还是 Xray 自身。
     - 当服务端 `config.json` 已渲染有对应入站标记（如 `// >>xh:h2direct`），但 `node.env` 因历史原因或外部同步处于 `false` 时，执行 `on` 会无条件触发端口占用拦截，用户也无法执行 `off` 释放，导致功能永久失效。
  2. **CDN 边缘限速与全链路缓冲短板**：
     - 单物理流瓶颈：此前 `XMUX_CDN_ENC` 设为 `maxConnections=3`，在并发大文件下载时无法突破 Cloudflare 边缘的单流限速；
     - 客户端 QUIC 窗口短板：`src/11-client-config.sh` 在 `XRAY_DEFAULTS=true` 时将 `XH3_FM_PARAM` 设为空，未给客户端注入 `quicParams`，客户端仅有默认初始小窗口，在 160ms+ 延迟下无法支撑百兆以上下行；
     - Nginx 回源缓冲短板：Nginx 的 `grpc_buffer_size` 和 `http2_recv_buffer_size` 设为 1024k，对于高并发 gRPC 反代吞吐仍有不足；
     - Clean IP 质量波动：部分 Anycast 节点在晚高峰或路由劣化时 TLS 握手长达数秒，严重拉低测速表现。
- **修复对策与工程落地**：
  1. **入站端口检测重构与状态脱节自愈 (`src/13-manage-cli.sh`)**：
     - **智能归属判定**：重构 `backup_port_busy "$proto" "$port" "$key"`，先用 `ss -ltnpH` 检查是否有非 `xray` 进程占用；若仅为 `xray`，进一步检查 `config.json` 是否包含当前节点专属标记（如 `// >>xh:${key}`）。若是自身标记，则允许开启流程执行，从而完成 `node.env`、客户端文件与订阅的自愈同步。
     - **状态脱节双重校验与进程名提示**：在 `cmd_backup_server_node` 的 `show`、`on`、`off` 以及 `cmd_hy2` 中，双重检查 `node.env` 状态与 `config.json` 入站标记（`$cur == true || $has_inbound == true`）；端口占用时抓取具体进程信息（如 `users:((...))`）清晰输出，并在 `off` 中允许清理残留标记，彻底终结死锁。
  2. **CDN 节点全链路极速性能调优**：
     - **客户端多路并发突破（`maxConnections: 6`，第 19 节已升至 16）**：将 `src/11-client-config.sh` 中的 `XMUX_CDN_ENC` 调整为 `maxConnections=6`，客户端通过 6 条物理 TCP 隧道并发分流，突破 Cloudflare 边缘的单流限速限制。
     - **QUIC 接收窗口全量注入（`fm` 参数，第 19 节已升级为 64M/128M）**：解除 `XRAY_DEFAULTS=true` 对 `XH3_FM_PARAM` 的清空限制，确保 `CDN-H3` 客户端链接恒常注入 32MB 流窗口与 64MB 连接窗口（`quicParams`），消除高延迟长肥管道（BDP）的吞吐瓶颈。
     - **Nginx 反代缓冲翻倍扩容**：在 `templates/nginx.conf.tmpl` 与 `/etc/nginx/nginx.conf` 中，将 `http2_max_concurrent_streams` 提升至 2048，`http2_recv_buffer_size` 与 `grpc_buffer_size` 由 1024k 扩容至 4096k (4MB)，`client_body_buffer_size` 扩至 1024k，减少 TCP/gRPC 报文分片与内存复制开销。
     - **Clean IP 深度净化与锁定**：运行 `probe.py` 进行毫秒级 TLS 握手与真实 XHTTP 隧道回源探测，剔除异常停顿节点，选定低延迟（12ms 握手、140ms 隧道）优选 Clean IP 并通过 `xh bestcf set` 锁定。
  3. **全端订阅刷新与平滑重载**：
     - 更新并编译最新部署脚本 `dist/install.sh`；
     - 重新渲染本机 `/home/ubuntu/client-config.txt` 与 `/etc/xhttp-cdn/all/`；
     - 运行 `xh resub` 刷新全量订阅与二维码；平滑重载 Nginx，验证 Xray 8445 直连入站与 CDN 反代各节点链路畅通。

## 19. CDN 节点多物理连接并发与 QUIC 接收窗口极致拉满调优规范 (2026-10-13)
- **优化背景与诉求**：
  在完成 CDN-H2 / CDN-H3 基础调优后，为彻底榨干 VPS 与客户端线路吞吐能力，进一步将「多物理连接并发突破单流限速」与「QUIC 接收窗口」两项核心参数调至物理与安全的极致上限。
- **技术上限与安全边界分析**：
  1. **物理连接并发数 (`xmux.maxConnections`) 极限考量**：
     - **理论上限**：Xray-core Go 结构体接受任意整数，协议无硬性截断；
     - **公网与 CDN 真实调度天花板（16 连接）**：
       - 对齐 IDM、Aria2、浏览器多线程并发标准（16 线程）；
       - Cloudflare 免费版 Anycast 边缘对单个 TCP/QUIC 长连接限速约 20~30 Mbps。开启 16 条并发物理连接时，理论聚合吞吐达 320 ~ 480 Mbps，能充分跑满 300M~500M 常见跨境宽带；
       - **为什么不能无脑开到 32+**：单 IP 瞬时发起 32+ 条 TLS 握手极易触发 Cloudflare 边缘 WAF / Anti-DDoS 挑战及 429 Too Many Requests 频控拦截，且会严重消耗移动端 Socket 描述符与电池寿命。16 为兼顾极致吞吐与公网风控的最佳安全天花板。
  2. **QUIC 接收窗口 (`fm` quicParams) 极限考量**：
     - **理论与 BDP 计算**：
       - 流窗口：初始 8MB / 最大 64MB (`initStreamReceiveWindow: 8388608`, `maxStreamReceiveWindow: 67108864`)；
       - 连接窗口：初始 16MB / 最大 128MB (`initConnectionReceiveWindow: 16777216`, `maxConnectionReceiveWindow: 134217728`)；
       - 在 160ms 跨洋延迟下，128MB 连接接收窗口对应的理论吞吐天花板高达 6.4 Gbps（单流 64MB 达 3.2 Gbps），彻底解除长肥管道（BDP）的流量控制瓶颈；
     - **为什么不能开到 256MB+（iOS Jetsam 50MB 内存红线）**：
       - Apple iOS 对所有 VPN / Network Extension 进程（如 Shadowrocket 小火箭、Stash、Quantumult X）设有极严苛的 **50 MB 物理内存硬上限**；
       - 跨境网络发生高丢包时，QUIC 协议栈必须在客户端内存中缓存所有失序包等待重传。若连接窗口开至 256MB+，丢包时内存瞬间飙升击穿 50MB，会直接被 iOS 内核 Jetsam 守护进程以 `EXC_RESOURCE` 强杀闪退。流 64MB / 连接 128MB 配合 16MB 初始窗口是兼顾极速与多端绝对不闪退的黄金上限。
- **工程落地与全端部署**：
  1. **配置生成器升级 (`src/11-client-config.sh`)**：
     - `XMUX_CDN_ENC` 锁定 `maxConnections: 16`；
     - `XH3_FM_PARAM` 注入顶配 `quicParams`（流 8M/64M，连接 16M/128M）；
  2. **编译重构与服务同步**：
     - 执行 `.github/scripts/build-install.sh` 编译更新 `dist/install.sh` 与 `dist/install-xpadding.sh`；
     - 启用 `FEATURE_CDN_H3`（`xh cdnh3 on`），使 `CDN-H2` 与 `CDN-H3` 同时处于顶配就绪状态；
     - 重新渲染本机 `/home/ubuntu/client-config.txt` 与备用节点库 `/etc/xhttp-cdn/all/`，并通过 `xh resub` 发布全量订阅。

## 20. Xray 内核锁定官方正式版 (v26.3.27 stable) 与前序全链路优化承接验证规范 (2026-10-13)
- **背景与内核切换**：
  为确保系统在生产与日常使用中的绝对稳定，规避上游 Pre-release 测试版（如 v26.10.x）可能引入的未稳定变更，将 Xray-core 内核切换并锁定为官方最新正式稳定版（v26.3.27 stable，`XRAY_CHANNEL=stable`）。同时对前序所有性能优化在此正式版内核下的承接状态进行逐项核验与固化。
- **优化承接与全链路验证**：
  1. **TCP Brutal 拥塞控制承接（注意：后续已在第 21 节彻底停用）**：
     - > [!NOTE]
     - > *演进覆盖*：本条记录的“维持入站 1000 Mbps 定速发包”已被 **第 21 节** 彻底关闭并替换为 BBRv3。内核版本锁定 `v26.3.27 stable` 依然完全权威有效。
     - 正式版内核（v26.3.27）完美支持原生 `sockopt.tcpcongestion: "brutal"`；
     - 清除 Reality 443 入站中因历史编辑残留的重复 `sockopt` 冗余块，保证 JSON 配置结构规范标准；
     - 维持入站 1000 Mbps 定速发包与出站 `bbr` 保护，实测在线连接平稳切换，重传率维持在 0.6% 极佳状态。
  2. **XHTTP-Direct-H2 (TCP 8445) 链路保持**：
     - 在正式版内核下保持双向放行与监听，curl 本地测试直连返回预期的 `HTTP/2 404` 响应，协议栈工作正常。
  3. **CDN 16 物理连接并发与 64MB/128MB QUIC 窗口全量兼容**：
     - 验证正式版内核对 `maxConnections: 16` 与顶配 `quicParams` 的解析与承接，`xray -test` 配置语法测试 100% 通过；
     - Nginx 反代缓冲维持 4096k (4MB)，CDN Clean IP 解析与锁定维持最优状态。
  4. **宿主机内核流控（sysctl）重新固化**：
     - 热加载并固化 `/etc/sysctl.d/99-xray-xhttp.conf`，将内核 `somaxconn` 提升至 65535、`netdev_max_backlog` 提升至 65536，确保高并发连接队列不发生丢溢。
  5. **全量订阅刷新**：
     - 执行 `xh resub` 重新渲染全量客户端配置与订阅，包含 7 条顶配主力节点（CDN-H2, CDN-H3, Direct-H3, Direct-H2, Hysteria2 x2, Reality-Vision）。

## 21. 全链路高延迟与断流排障：停用 TCP Brutal 全面恢复 BBRv3 规范 (2026-10-15)
- **排障背景与实锤证据**：
  - 用户反馈节点网络延迟极高（测速和使用出现明显卡顿、断流与速度瘫痪）。
  - 对实时活跃 TCP 连接审查（`ss -tin`）捕获到真实国内客户端（广东移动）在直连节点 `VLESS-XHTTP-Direct-H2`（TCP 8445）上的底层连接指标：
    1. 物理传播基准延迟 (`minrtt`) 为 **272.6 ms**，但实际往返延迟 (`rtt`) 暴涨 10 倍膨胀至 **2,745.83 ms**（2.75 秒）；
    2. 套接字发送队列 (`Send-Q`) 打满并死锁在 **4,217,433 字节**（4.2MB 队列完全堵死）；
    3. 超时重传计时器 (`rto`) 飙升至 **120,000 ms**（120 秒，指数退避 `backoff: 6`），报文段长 (`mss`) 从 1440 暴跌至 **64 字节**；
    4. 有效交付速率从正常值断崖式崩塌至 **186 bps**。
  - **根因分析**：
    - Xray 入站强行启用了 `tcpcongestion: "brutal"`，且配置了固定 1000 Mbps 下发速率。TCP Brutal 缺乏对拥塞与丢包的动态自适应退避机制。
    - 当客户端连接穿越晚高峰公网、跨洋骨干网瓶颈或其家庭宽带承载力受限时，服务端强推 1Gbps 会瞬间打满中间网络路由器的队列，引发极其严重的 **Bufferbloat（缓冲区膨胀与拥塞崩溃）**，导致几秒的高延迟、频繁超时重传与断流。
- **治理与固化动作**：
  1. **切换拥塞控制为 BBRv3**：
     - 执行 `xh brutal off`，移除 Xray 入站中的 `brutal` 并全面回落至内核自适应的 `bbr`（宿主机已配置 BBRv3 + FQ）。
     - 更新 `/etc/xhttp-cdn/node.env` 中的 `XRAY_TCP_CC="bbr"` 与 `FEATURE_BRUTAL="false"`。
     - 切换后现场验证：活跃套接字积压队列（`Send-Q`）瞬间归零，RTT 回落至正常物理基线，连接恢复顺畅。
  2. **仓库工程化加固**：
     - 修改 `src/06-tuning-lib.sh`：在 `set_tcp_brutal_xray` 中联动持久化 `FEATURE_BRUTAL` 环境变量（`on` 设为 `true`，`off` 设为 `false`）。
     - 修改 `src/09-server-config.sh`：将默认 sockopt 拥塞控制兜底 `${XRAY_TCP_CC:-brutal}` 修正为 `${XRAY_TCP_CC:-bbr}`，同时对齐 HY2 默认拥塞控制参数。
     - 重新编译分发包 `dist/install.sh` 与 `dist/install-xpadding.sh`。
  3. **Xray 内核通道与版本固化 (v26.3.27 stable)**：
     - 执行 `xh autoupdate stable`，通道模式明确锁定为 `stable`（仅拉取官方正式版，跳过 pre-release）；
     - 运行内核切换并验证为最新稳定版 `v26.3.27`（`XRAY_CHANNEL='stable'` 写入 `node.env`）；
     - 与已完成的 BBRv3、64MB 读写缓冲区、CDN 16 并发物理连接以及 64MB/128MB QUIC 窗口全链路协同，确保系统长期运行稳定可靠。

## 22. 极端第三方调优清理与科学流控体系防劣化规范 (2026-10-15)
- **排障背景**：
  - 用户尝试运行第三方 BBR 脚本的「BBR v3 疯批模式」，生成了 `/etc/sysctl.d/99-joeyblog.conf`。
  - 该模式将 `tcp_wmem`/`tcp_rmem` 放大至 1GB、`tcp_limit_output_bytes` 放大 64 倍至 256MB、并关闭反压（`tcp_notsent_lowat=4294967295`）。
  - **严重后果分析**：该模式仅适合内网零延迟单线程打流测试，在真实跨洋国际弱网中会彻底摧毁 TSQ（TCP Small Queues）排队反压保护，造成 20 秒以上的严重排队延迟（Bufferbloat 再次爆发）与内存耗尽风险。
- **治理与固化动作**：
  1. 通过 `xh tuning off && xh tuning on` 自动清理 `/etc/sysctl.d/99-joeyblog.conf`；
  2. 重新加载并固化官方科学流控配置 `/etc/sysctl.d/99-xray-xhttp.conf`：
     - 单流保护上限收敛锁定在安全稳妥的 **64MB**（`67108864`）；
     - TSQ 输出队列反压限制锁定在 **4MB**（`4194304`），根绝网络缓冲区排队时延膨胀；
     - `tcp_notsent_lowat` 锁定在 **16KB**（`16384`），确保应用层反压顺畅；
  3. 平滑重载 `xray` 与 `nginx`，验证各节点与端口（443/8445/8446/8447/8001/8002/8003）监听就绪且无冲突。

## 23. sbbox 体系集成 Nowhere 自研上下行分流协议与双模式部署 (2026-10-16)
- **部署背景**：
  - 用户引入新兴高性能抗封锁与抗 QoS 中继协议 Nowhere（Rust 原生开发，支持上下行分流独立承载、BLAKE3 混淆与 Morph 掩码），要求无侵入集成进 VPS 的 `sbbox` 生态。
- **架构方案与端口规划**：
  - 采用 **Sidecar 独立守护进程** 架构部署（`sbbox-nowhere.service`），既保持 sing-box / Xray 核心纯净，又复用 sbbox 现有 Let's Encrypt 证书体系（`cert/fullchain.cer`）；
  - 分配独立监听端口：`18448`（TCP + UDP 双栈监听），并注入系统 iptables 放行规则；
  - 密钥管理：独立生成 128-bit 随机 hex 密钥（落盘至 `/root/sbbox/nw_key`，chmod 600），并提取证书 SHA-256 指纹（落盘至 `/root/sbbox/nw_pin`）。
- **双运行模式**：
  1. **高速模式 (Nowhere-Split-HighSpeed)**：`up=tcp` & `down=udp`（上行走 TLS/TCP 彻底规避国内运营商对 UDP 上行的恶性 QoS 丢包；下行走 QUIC/UDP 享受 0-RTT 与无队头阻塞极速大吞吐）。
  2. **常用稳定模式 (Nowhere-Common-TCP)**：`net=tcp` & `up=tcp` & `down=tcp`（全链路 TLS/TCP，兼具 100% 防火墙与公共 Wi-Fi 穿透力）。
- **生态与订阅联动**：
  - 更新 `/root/sbbox/nodes.txt` 与 token base64 订阅文件；
  - 改造 `/root/sbbox/sub_server.py`：对 Shadowrocket 客户端请求自动过滤 `nowhere://` 节点，杜绝小火箭因未知协议 scheme 报错闪退；同时提供 `/nowhere` 路径专属拉取；
  - 联动 `sbbox.sh`：将 Nowhere 纳入 `sbbox status` 监控、`sbbox cert sync` 证书轮换自动热重载以及 `sbrestart` 启停流水线；
  - 验证：通过 `nowhere probe` 实测 TCP 与 UDP 往返建联延迟均在 2~4ms 内，端到端就绪。
