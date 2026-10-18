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

## 📡 10 Core Node Matrix

| # | Node Name | Protocol & Transport | Port / Mode | Obfuscation / Cipher | Recommended Use Case |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | `VLESS-TLS+PQ+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | ML-KEM-768 Post-Quantum + TLS 1.3 | **Daily Driver**: Universal CDN acceleration, quantum-resistant forward secrecy |
| **2** | `VLESS-TLS+PQ+Vision+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | ML-KEM-768 + Vision dynamic flow | Eliminates TLS-in-TLS fingerprinting, QoS-evasive |
| **3** | `VLESS-REALITY+PQ+Vision（自域名）` | VLESS + REALITY (RAW) | 8447 / TCP (Direct) | ML-KEM-768 + Vision (0.05ms local gateway) | **High-Speed Direct**: Linux kernel `splice()` zero-copy, line-rate Gigabit throughput |
| **4** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | TLS 1.3 / xpadding / 16 Concurrency | Standard CDN fallback, compatible with legacy Xray clients |
| **5** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP (H3) | 443 (Cloudflare CDN) | QUIC (H3) 0-RTT / 64MB window | Packet-loss resistant CDN acceleration on unstable mobile networks |
| **6** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP (H3) | 8446 / UDP (Direct) | Native QUIC (H3) / 64MB window | Direct low-latency cross-ocean high throughput |
| **7** | `Hysteria2-H3-Direct` | Hysteria2 | UDP Dynamic Port (e.g., 19142) | BBRv3 / Standard HTTP/3 | Gigabit line-rate throughput & instant recovery from packet loss |
| **8** | `Hysteria2-TLS-BBR-Salamander` | Hysteria2 | UDP Dynamic Port (e.g., 38969) | Salamander Obfs + BBR + 64MB window | Extreme ISP UDP throttling & active-probing evasion |
| **9** | `VLESS-Reality-Vision-Direct` | VLESS + REALITY (RAW) | 443 / TCP (Direct) | xtls-rprx-vision zero-copy | Standard port 443 direct connection enjoying highest carrier QoS |
| **10** | `VLESS-Reality-XHTTP-Direct` | VLESS + REALITY (RAW) | 443 fallback to 8001 | XHTTP + vlessenc local fallback | Dual-layer fallback combining Reality camouflage with protocol routing |

> [!NOTE]
> - **Top 3 PQ Core Nodes** (1-3) implement NIST-standard Post-Quantum key exchange (ML-KEM-768) for quantum-resistant forward secrecy.
> - **Hysteria2 Nodes** (7-8) operate over dynamic high UDP ports and declare 64MB stream / 128MB connection receive windows to eliminate BDP bottlenecks.
> - **Optional Direct Node**: `VLESS-XHTTP-Direct-H2` (8445 TCP Direct) can be toggled on-demand via `xh h2direct on`.

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
