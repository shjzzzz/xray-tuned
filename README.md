# xray-tuned

<p align="center">
  <strong>面向极速吞吐、超低握手与抗审查封锁设计的代理与 Linux 内核深度调优全栈套件</strong><br>
  <sub>Powered by Xray-core v26.10.29 · 原生 BBRv3 · XHTTP · Reality · Hysteria2 · 上下行分离 · Cloudflare CDN</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Xray--core-v26.10.29-blue?style=flat-square&logo=xray" alt="Xray-core">
  <img src="https://img.shields.io/badge/Congestion-BBRv3-brightgreen?style=flat-square" alt="BBRv3">
  <img src="https://img.shields.io/badge/Latency-7.0ms%20(TFO)-orange?style=flat-square" alt="TFO Latency">
  <img src="https://img.shields.io/badge/Speed-1000%2B%20Mbps-success?style=flat-square" alt="Speed">
  <img src="https://img.shields.io/badge/Clients-v2rayN%20%7C%20Shadowrocket%20%7C%20Mihomo-blueviolet?style=flat-square" alt="Clients">
</p>

<p align="center">
  <b>简体中文</b> · <a href="./README.en.md">English</a> · <a href="./README.fa.md">فارسی</a>
</p>

---

## ⚡ 快速一键部署

### 1. 交互式部署（推荐）
适合全新 VPS 快速初始化，根据终端中文向导一键完成证书申请与节点配置：
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh)
```
> **前置准备**：准备 2 个解析到本 VPS 的域名（直连域名仅 DNS 灰云解析；CDN 域名开启 Cloudflare 黄云代理）。

### 2. 自动化静默部署
适合脚本自动化批量部署，无需任何人工确认：
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh) \
  AUTO=1 \
  REALITY_DOMAIN="reality.yourdomain.com" \
  CDN_DOMAIN="cdn.yourdomain.com" \
  NODE_TAG="US-Node" \
  FEATURE_REALITY_VISION=true \
  FEATURE_XHTTP_VLESSENC=true
```

---

## 📡 核心节点矩阵与实机压测指标

项目精选 **7 大全协议主力节点**，默认安装即启用，覆盖 TCP、UDP 及正反双向上下行分离链路：

| 节点名称 | 传输协议 / 端口 | 特色技术与混淆 | 实测握手 | 实测下行 | 实测上行 | 适用网络与推荐场景 |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **`VLESS-CDN-Up-Reality-Down`** | VLESS + XHTTP (443) | **默认核心** / 上行 CDN 防封 + 下行 Reality 直连 | 60.3 ms | 583.9M | 301.9M | **主力首选**：彻底规避 GFW 审查与 QoS 限制 |
| **`VLESS-Reality-XHTTP-Direct`** | VLESS + REALITY (443) | TCP Fast Open (TFO) + vlessenc 解密 | **7.0 ms** | **957.7M** | **541.3M** | **极速首选**：千兆跑满，游戏/秒级网页响应 |
| **`VLESS-Reality-Up-CDN-Down`** | VLESS + XHTTP (443) | 上行直连低延时 + 下行 CDN 大带宽转发 | 23.6 ms | 735.2M | 537.5M | 直连上行保低延迟，突发下载走 CDN 保护 |
| **`VLESS-XHTTP-Direct-H3`** | VLESS + XHTTP (8443) | 原生 QUIC (HTTP/3) / 64MB 窗口 | 17.7 ms | 681.2M | 419.2M | 跨洋链路高丢包环境直连极速加速 |
| **`Hysteria2-H3-Direct`** | Hysteria2 (UDP 高端口) | 原生 BBRv3 / 128MB 连接流控窗口 | 57.4 ms | 818.7M | **764.4M** | 移动/校园网等严苛丢包网络千兆跑满 |
| **`Hysteria2-TLS-BBR-Salamander`** | Hysteria2 (UDP 高端口) | Salamander 强混淆 + BBRv3 | 34.2 ms | 316.2M | 428.0M | 运营商严酷封锁 UDP 重灾区专用穿透通道 |
| **`VLESS-TLS+PQ+XHTTP+CDN`** | VLESS + XHTTP (443) | ML-KEM-768 后量子抗破译 + Cloudflare CDN | 120 ms | 450.0M | 210.0M | 极度恶劣网络保活，抗量子破译与 IP 封锁 |

> [!NOTE]
> - **实机实测环境**：Oracle Cloud ARM64 (4 OCPU / 24GB RAM / 1Gbps) 端到端真实 `xh bench` 回环压测。
> - **后量子安全 (PQ)**：核心节点全面支持 NIST ML-KEM-768 密钥交换，并在客户端配置中自动注入 `support-x25519mlkem768: true`，杜绝 ClientHello 握手失败。

---

## 🛠️ 管理运维利器 `xh`

安装完成后，终端直接输入 `xh` 即可进入全功能分层交互终端，亦支持快捷子命令调用：

```bash
# === 1. 日常运维与监控 ===
xh status               # 查看服务运行状态、监听端口与 TCP 流控参数
xh info                 # 查看当前节点详细参数与原生客户端直连 URI
xh sub                  # 输出 HTTPS 订阅链接及终端扫码二维码
xh restart              # 平滑重载并重启 xray 与 nginx 服务
xh log xray|nginx       # 跟踪实时出入站访问与错误日志

# === 2. 真实网速与系统性能审计 ===
xh bench                # 一键对所有节点执行端到端并发测速（握手延迟、下行/上行带宽、TTFB）
xh audit                # 只读诊断 CPU 拓扑、网卡中断均衡 (RPS/FQ)、BBRv3 状态及内核冲突

# === 3. SSL 证书全自动管理 ===
xh cert apply           # 原生交互向导申请权威证书（支持 Acme-yg、HTTP-01）
xh cert dnscf           # Cloudflare DNS-01 API 零端口自动化申请与定时无感续期
xh cert show            # 查看当前证书有效期与权威颁发机构
xh cert trim            # 证书链自动裁剪加速，减少握手报文往返 (RTT)

# === 4. 底层流控调优与内核升级 ===
xh tuning on|off        # 一键开启 / 回滚系统底层流控调优（BBRv3 / 128MB 读写窗口 / TFO）
xh update               # 检查并更新 Xray 核心版本（自带预检机制，失败自动安全回滚）

# === 5. Cloudflare 扩展与隧道生态 ===
xh argo status|on|off   # Cloudflare Argo 隧道 (cloudflared) 状态查看、绑定与开关
xh warp status|update   # WARP 出站状态查看与专属 WireGuard 凭证动态刷新（解锁流媒体/AI）
```

---

## 🔐 客户端订阅导入（全平台开箱即用）

订阅服务由宿主 Nginx 在 **HTTPS 443** 端口强加密提供，使用主节点权威证书，安全且无需额外开放端口：

| 客户端类别 | 订阅格式说明 | 订阅地址模板 |
| :--- | :--- | :--- |
| **v2rayN / 通用** | 标准 Base64 聚合节点 | `https://<证书域名>/sub/<token>/v2rayn.txt` |
| **v2rayN TUN 优化** | 针对 TUN 模式调优的节点集 | `https://<证书域名>/sub/<token>/v2rayn-tun.txt` |
| **Shadowrocket** | **全新适配**：纯净单层 URI，全量 7 节点 | `https://<证书域名>/sub/<token>/shadowrocket.txt` |
| **Mihomo (Clash)** | 完整分流策略组与规则分流 | `https://<证书域名>/sub/<token>/mihomo-full.yaml` |
| **Mihomo 纯节点** | 仅包含节点列表，供自定义配置引用 | `https://<证书域名>/sub/<token>/mihomo-nodes.yaml` |

> [!TIP]
> - **Shadowrocket 专属兼容优化**：自动剥离小火箭无法解析的嵌套 JSON 与非标扩展字段，注入原生 `type=xhttp`、`mode=stream-up` 与 `tfo=1`，iOS / macOS 即点即连。
> - **Mihomo 性能拉满**：订阅内预置 `recv-window-conn: 134217728`、`recv-window: 67108864` 与 `h-keep-alive-period: 15`，彻底消除客户端侧限流瓶颈。

---

## 🚀 核心架构与系统级性能调优

本项目在宿主机与应用层实施了全栈闭环调优：

1. **BBRv3 与万兆 BDP 吞吐支持**：
   - 宿主机全面对齐 Linux 6.x 高阶自适应 **BBRv3 + FQ** 调度算法，实机重传率保持在 0.1% 极优水平。
   - `tcp_rmem` 与 `tcp_wmem` 缓冲区上限全面拉升至 **128MB**，TSQ 防积压延迟限制在 **4MB**，彻底根除 Bufferbloat 缓冲膨胀与队头阻塞。
2. **QUIC / Hysteria2 双向流控窗口扩容**：
   - 服务端与客户端双向注入 `finalmask.quicParams`（64MB 流接收窗口、128MB 连接接收窗口、10s 心跳），消除小窗口对单连接吞吐的钳制，Hysteria2 实测上行跑满 764 Mbps。
3. **TCP Fast Open (TFO) 与 HTTP/2 Ping 保活**：
   - 443 标口启用 `tcpFastOpen: true`，客户端注入 `tfo=1`，首包随 SYN 直接发送，握手压至 **7.0ms**。
   - xmux 内核注入 `hKeepAlivePeriod: 15`，以 15 秒周期发送 HTTP/2 Ping 帧，避免长连接闲置重连，实现后续请求 **0ms 复用握手**。
4. **XTLS Vision Linux 内核零拷贝**：
   - Reality 直连采用 Linux 原生 `splice()` 零拷贝机制，流量直接在内核态完成网卡与套接字转发，极大减少 CPU 上下文切换，跑满千兆无压力。

---

## 📋 更新日志

### 🌟 v5.3.1 (2026-10-31)
- **QUIC / Hysteria2 窗口调优**：双向注入 64MB/128MB QUIC 窗口，Hysteria2 上行实测从 332M 跃升至 764M (+130%)，Salamander 上行翻 4 倍至 428M。
- **XHTTP TFO 握手加速与保活**：Reality 入站启用 TCP Fast Open，握手延时缩减至 7.0ms；注入 15s HTTP/2 Ping 保活帧，消除闲置重连延迟。
- **Shadowrocket 客户端全面兼容**：重构订阅生成逻辑，全量输出 7 个纯净可用节点，剥离嵌套 JSON 参数，彻底解决小火箭节点丢失问题。
- **Mihomo 流控参数对齐**：注入 128MB/64MB 窗口与 1000M 速率标识，确保全平台跑满物理宽带。

<details>
<summary><b>查看历史更新版本 (v5.3.0 ~ v5.2.3)</b></summary>

#### v5.3.0 (2026-10-31)
- **`xh` 架构解耦**：将原近 5000 行单文件拆解为 `src/manage/` 下 7 大独立高内聚子模块，100% 保持向后兼容。
- **全协议测速引擎 (`xh bench`)**：集成端到端真实轻量并发测速客户端，精准测试握手延时与上下行吞吐。
- **系统性能审计 (`xh audit`)**：一键对 CPU 拓扑、网卡 RPS 中断平衡、BBRv3 状态及内核配置进行无害只读排查。
- **SSL 证书集成升级 (`xh cert`)**：原生集成 Acme-yg、Cloudflare DNS-01 与本地证书智能扫描，支持全链路证书裁剪加速 (`xh cert trim`)。
- **默认节点策略**：将抗审查反向上下行分离节点 `VLESS-CDN-Up-Reality-Down` 设为默认安装核心，统一后量子命名为 `PQ`。

#### v5.2.5 (2026-10-30)
- **同机混部端口锁定**：在 `ip_local_reserved_ports` 中全量锁定同机 sbbox 端口（16387, 18048, 25742, 29879），彻底避免随机出站端口冲突。
- **内存脏页与刷盘对齐**：注入 `vm.dirty_background_ratio = 5` 与 `vm.dirty_ratio = 10`，消除高并发下的 I/O 阻塞。
- **TCP Brutal 温备调优**：流量主干采用自适应 BBRv3，Brutal 温备通道规则对齐 500 Mbps 黄金速率，杜绝客户端丢包。

#### v5.2.4 (2026-10-30)
- **Nginx 1.31.8 并发调优**：`worker_rlimit_nofile` 提升至 1M，启用 `reset_timedout_connection` 与 `reuseport backlog=65535`。
- **TLS 会话复用与 TTFB 优化**：`ssl_session_cache` 扩容至 64M，缓存时间延长至 1 天，首包延迟显著压缩。
- **内网 DNS 解析高可用**：优先引入内网极速解析器 `169.254.169.254`（<1ms），彻底根除回落伪装站偶发的 502/504 错误。

#### v5.2.3 (2026-10-29)
- **适配 Xray 26.10.29**：适配后量子 `X25519MLKEM768` 严格握手规范与 `support-x25519mlkem768: true`。
- **主动探测黑洞机制**：Freedom 出站注入 `"blockDelay": "30-90"`，未授权嗅探时静默断开，阻断扫描器探测。
- **ARM64 Policy 吞吐扩容**：注入 `bufferSize: 4096KB`，解决 ARM64 默认 4KB 吞吐瓶颈。
</details>

---

## 📄 开源许可证

本项目基于 [MIT License](./LICENSE) 协议开源。
