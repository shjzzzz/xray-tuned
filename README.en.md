# xray-tuned

> High-performance proxy and kernel-tuning deployment suite powered by **Xray-core (v26.3.27 stable)**.
> Features **XHTTP + Cloudflare CDN + Reality + Hysteria2** with native BBRv3, TCP Fast Open, 64MB buffer safety, and automated multi-platform subscription distribution.

**Languages:** [简体中文](./README.md) · **English** · [فارسی](./README.fa.md)

---

## ⚡ Quick Start

### 1. Xray-Tuned Automated Silent Deployment (Recommended)
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh) \
  AUTO=1 \
  REALITY_DOMAIN="reality.yourdomain.com" \
  CDN_DOMAIN="cdn.yourdomain.com" \
  NODE_TAG="US-Node" \
  FEATURE_REALITY_VISION=true \
  FEATURE_XHTTP_VLESSENC=true
```

### 2. sbbox-tuned Automated Deployment
```bash
bash <(curl -Ls https://raw.githubusercontent.com/shjzzzz/sbbox-tuned/main/sbbox.sh) hyp=1 anyp=1 nvp=1 tup=1 alns=1 sub=1 sbrel=pre ym=reality.yourdomain.com
```

### 3. Interactive Installation
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh)
```
> **Prerequisites**: 2 subdomains pointing to your VPS IP (Direct domain: DNS-only grey cloud; CDN domain: Proxied orange cloud).

---

## 📡 Core Node Matrix

| # | Node Name | Protocol | Port / Transport | Obfuscation | Recommended Use Case |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP | 443 (CF CDN) / h2 | xpadding obfs | Censorship-resilient IP masking fallback |
| **2** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP | 443 (CF CDN) / h3 | QUIC (H3) 0-RTT | Packet-loss resistant CDN acceleration |
| **3** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP | 8446 / h3 (UDP) | Native QUIC (H3) | Cross-ocean low-latency high throughput |
| **4** | `VLESS-XHTTP-Direct-H2` | VLESS + XHTTP | 8445 / h2 (TCP) | TLS 1.3 direct | Reliable direct connection when UDP is blocked |
| **5** | `Hysteria2-H3-Direct` | Hysteria2 | 33385 / UDP | BBRv3 / standard H3 | Max throughput & fast recovery from packet loss |
| **6** | `Hysteria2-Obfs-Direct` | Hysteria2 | 37987 / UDP | Salamander obfs | ISP UDP QoS / active-probing evasion |
| **7** | `VLESS-Reality-Vision-Direct` | VLESS + Reality | 443 / TCP (RAW) | xtls-rprx-vision | **Recommended Daily Driver**; lowest latency & zero-copy |
| **8** | `VLESS-Reality-PQ-Vision` | VLESS + Reality | 8447 / TCP (RAW) | mlkem768x25519plus | Post-Quantum encryption forward secrecy |

---

## 🛠️ Management CLI (`xh`)

Run `xh` without arguments for an interactive dashboard, or use CLI commands:

```bash
xh status             # View services, listening ports, and kernel flow parameters
xh info               # Display node parameters and raw client URIs
xh sub                # Output subscription URLs and terminal QR code
xh reality            # Inspect and toggle Reality Vision / XHTTP nodes
xh restart            # Gracefully restart Xray and Nginx services
xh log xray           # Follow live Xray connection logs
xh tuning on|off      # Enable / rollback system-level tuning (BBRv3 / Buffers / TFO)
xh update             # Update Xray-core (stable channel with automated rollback)
```

---

## 🚀 Performance Highlights

1. **Kernel Flow Control**: System-wide **BBRv3 + FQ**, TCP socket buffer locked at **64MB**, TSQ queue limited to **4MB** to eliminate Bufferbloat.
2. **TCP Fast Open (TFO)**: Enabled on all inbounds to eliminate 1 RTT during handshakes.
3. **XUDP Multi-Packet Packing**: Links include `&packetEncoding=xudp` for instantaneous DNS and UDP streaming without head-of-line blocking.
4. **XTLS Vision Zero-Copy**: Directly uses Linux kernel `splice()`. **Ensure client-side Mux is OFF** to preserve line-rate throughput.
5. **Subscription Out-of-the-Box**: Compatible with v2rayN, Mihomo, Shadowrocket, and Sing-box.
