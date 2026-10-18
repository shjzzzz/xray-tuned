# xray-tuned

> High-performance proxy and kernel-tuning deployment suite powered by **Xray-core (v26.3.27 stable)**.
> Features **XHTTP + Cloudflare CDN + Reality + Hysteria2** with native BBRv3, TCP Fast Open, 64MB buffer safety, and automated multi-platform subscription distribution.

**语言：** **简体中文** · [English](./README.en.md) · [فارسی](./README.fa.md)

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
| **6** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP (H3) | 8446 / UDP (直连) | 原生 QUIC (H3) / 64MB 接收窗口 | 直连低延迟大吞吐，抗跨境链路偶发丢包 |
| **7** | `Hysteria2-H3-Direct` | Hysteria2 | UDP 随机高端口 (如 19142) | BBRv3 / 标准 HTTP/3 握手 | 跨境千兆跑满，高丢包网络（如移动/校园网）极速回血 |
| **8** | `Hysteria2-TLS-BBR-Salamander` | Hysteria2 | UDP 随机高端口 (如 38969) | Salamander 混淆 + BBR + 64MB 窗口 | 运营商严苛封锁 UDP 重灾区专用穿透与防主动探测 |
| **9** | `VLESS-Reality-Vision-Direct` | VLESS + REALITY (RAW) | 443 / TCP (直连标口) | xtls-rprx-vision 零拷贝直通 | 标口 443 直连，免额外端口，享受骨干网最高 QoS |
| **10** | `VLESS-Reality-XHTTP-Direct` | VLESS + REALITY (RAW) | 443 回落至本地 8001 | XHTTP + vlessenc 本地解密 | 标口回落备用，兼具 Reality 伪装与分流兼容性 |

> [!NOTE]
> - **前三大 PQ 核心节点**（1-3）采用 NIST 推荐标准后量子密钥协商套件（ML-KEM-768），提供面向未来的抗量子破解前向安全性。
> - **Hysteria2 节点**（7-8）直连 UDP 采用随机高端口监听并全面启用 BBRv3，客户端配置声明 64MB 流窗口与 128MB 连接窗口，规避跨境长肥管道瓶颈。
> - **可选备用节点**：如需开启 `VLESS-XHTTP-Direct-H2`（8445 TCP 直连），可通过 `xh h2direct on` 随时按需启用。

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
```

---

## 🚀 性能与架构调优特性

1. **拥塞控制与流控基准**：宿主机全面落地 **BBRv3 + FQ**，TCP 读写缓冲上限收敛于 **64MB**，TSQ 队列限制 **4MB**，彻底消灭 Bufferbloat 拥塞膨胀与队头阻塞。
2. **TCP Fast Open (TFO)**：全入站启用 TFO，三次握手携带第一段应用数据，节约 1 个 RTT。
3. **XUDP 封包加速**：订阅与直连链接均注入 `&packetEncoding=xudp`，消除网页 DNS 解析与 UDP 单包传输排队延迟。
4. **XTLS Vision 零拷贝**：Reality Vision 采用 Linux 内核 `splice()` 直发。客户端请务必**关闭 Mux（多路复用）**以释放极速性能。
5. **多端订阅即开即用**：自动适配 v2rayN（全量 base64 / TUN）、Mihomo（完整分流 / 纯节点）、Shadowrocket（自动过滤不兼容协议）及 Sing-box。
