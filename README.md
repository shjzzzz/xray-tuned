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

### 2. sbbox-tuned 自动化部署
```bash
bash <(curl -Ls https://raw.githubusercontent.com/shjzzzz/sbbox-tuned/main/sbbox.sh) hyp=1 anyp=1 nvp=1 tup=1 alns=1 sub=1 sbrel=pre ym=reality.yourdomain.com
```

### 3. 交互式部署
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh)
```
> **前置要求**：准备 2 个解析到 VPS 的域名（直连域名灰云仅 DNS，CDN 域名黄云开启代理）。

---

## 📡 核心节点矩阵

| 序号 | 节点名称 | 核心协议 | 端口 / 传输 | 伪装 / 混淆 | 适用场景 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP | 443 (CF CDN) / h2 | xpadding 流量填充 | IP 容灾防封、晚高峰保底 |
| **2** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP | 443 (CF CDN) / h3 | QUIC (H3) 0-RTT | 抗丢包 CDN 加速 |
| **3** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP | 8446 / h3 (UDP) | QUIC (H3) 直连 | 跨洋 UDP 低延迟与大吞吐 |
| **4** | `VLESS-XHTTP-Direct-H2` | VLESS + XHTTP | 8445 / h2 (TCP) | TLS 1.3 直连 | UDP 受限场景 TCP 直连 |
| **5** | `Hysteria2-H3-Direct` | Hysteria2 | 33385 / UDP | BBRv3 / 标准 H3 | 跨洋千兆跑满、丢包极速回血 |
| **6** | `Hysteria2-Obfs-Direct` | Hysteria2 | 37987 / UDP | Salamander 密码混淆 | 运营商 UDP 封锁重灾区穿透 |
| **7** | `VLESS-Reality-Vision-Direct` | VLESS + Reality | 443 / TCP (RAW) | xtls-rprx-vision 零拷贝 | 低延迟与跑满千兆 |
| **8** | `VLESS-Reality-PQ-Vision` | VLESS + Reality | 8447 / TCP (RAW) | mlkem768x25519plus 后量子 | 强前向保密、抗量子计算破译 |

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
