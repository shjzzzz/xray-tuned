# xray-tuned

> High-performance proxy and kernel-tuning deployment suite powered by **Xray-core (v26.3.27 stable)**.
> Features **XHTTP + Cloudflare CDN + Reality + Hysteria2** with native BBRv3, TCP Fast Open, 64MB buffer safety, and automated multi-platform subscription distribution.

**语言：** **简体中文** · [English](./README.en.md) · [فارسی](./README.fa.md)

---
先申请证书：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)

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
xh cert show|dnscf    # 查看证书状态或切换 Cloudflare DNS-01 自动续签
xh argo status|update # Cloudflare Argo 隧道 (cloudflared) 状态与一键内核更新
xh warp status|update # Cloudflare WARP 出站状态查看与账户凭据动态更新
```

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
