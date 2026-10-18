# 经验教训与规则库 (Lessons Learned & Rules)

## 1. Xray XHTTP xmux 参数互斥红线 (2026-10-18)
- **错误现象**：客户端导入 `VLESS-TLS+PQ+XHTTP+CDN` 或 `VLESS-TLS+PQ+Vision+XHTTP+CDN` 后，v2rayN 启动内核崩溃，提示 `Failed to start: main: failed to load config files: [...] > infra/conf: maxConnections cannot be specified together with maxConcurrency`。
- **根本原因**：Xray 源码（`infra/conf`）明确限制：`xmux` 中的 `maxConnections`（最大底层物理连接数）与 `maxConcurrency`（单连接最大多路复用并发流数）属于互斥逻辑。若同时设置二者，Xray 在初始化 outbound streamSettings 时会直接拦截报错退出。
- **治理与防范规则**：
  1. **CDN 节点**：使用 `maxConnections: 16`，由客户端维护多条物理连接并行突破 Cloudflare 边缘单流限速；**严禁在 CDN 节点的 `extra.xmux` 中同时注入 `maxConcurrency`**。
  2. **直连节点**：使用 `maxConcurrency: "16-32"`，在单条物理长连接中多路复用并进行流控混淆。
  3. **完成前验证（Verification Before Done）**：每次修改客户端链接参数或生成脚本后，必须运行测试脚本，调用 `/usr/local/bin/xray -test -config` 模拟客户端 outbound 完整 JSON 结构进行内核配置语法与语义校验，确保 100% 通过方可标记完成。

## 2. iptables 端口重定向、CDN IP 还原与协议族绑定规范 (2026-10-18)
- **iptables 规则覆盖与清理**：向 PREROUTING 注入 `-j REDIRECT --to-ports` 时，必须预先检测并清除旧端口历史规则，严禁直接使用 `-A` 盲目追加，否则按顺序匹配会导致旧端口持续命中产生黑洞。
- **Cloudflare 真实 IP 传递**：Nginx `http_realip_module` 在接入 Cloudflare CDN 时必须使用 `real_ip_header CF-Connecting-IP;`，不可误写为 `X-Real-IP`，否则无法正确还原访客真实源 IP，连带影响日志与频控。
- **双栈入站隔离**：Xray 模板中的 `"listen"` 参数须依据 `IP_CHOICE` 动态分流（IPv4 绑定 `0.0.0.0`，IPv6 绑定 `::`），确保在纯 IPv4 或纯 IPv6 单栈 VPS 上平滑自适应。

## 3. 纯单栈（IPv4-only）环境下的 sniffing 与 destOverride 红线 (2026-10-18)
- **错误现象**：客户端通过 CDN 或直连访问双栈大站（如 Cloudflare、Google、Bing 等）时频繁断连、卡死，报错 `unexpected eof while reading`；Nginx 报 `upstream rejected request with error 5`。
- **根本原因**：双栈客户端本地解析出 IPv6 地址并将其作为代理目标发送至服务端。服务端入站 sniffing 设置了 `"routeOnly": true`，导致 Xray 仅将嗅探出的 SNI 域名用于路由匹配，而未将请求目标地址重写为域名（destOverride）。Freedom 出站直接尝试对客户端发来的 IPv6 字面地址发起 `connect()`，在纯 IPv4 单栈 VPS 上内核直接返回 `[Errno 101] Network is unreachable`，连接被瞬间切断。
- **治理与防范规则**：
  1. 服务端所有代理入站的 `sniffing.routeOnly` 必须设为 `false`（或保持缺省，启用 destOverride 目标重写）；
  2. 嗅探重写目标为域名后，freedom 出站依据 `sockopt.domainStrategy: "UseIPv4"` 由服务端本地解析出可达的 IPv4 地址出站直连，彻底消除 IPv6 路由黑洞。

## 4. Xray 服务端 DNS 高可用与 DoH 意外断流防护 (2026-10-18)
- **错误现象**：Xray 日志反复出现 `app/dns: failed to retrieve response ... unexpected EOF` 与 `failed to resolve ip > features/dns: empty response`，导致出站连接解析失败、stream 频繁被 RST。
- **根本原因**：配置单一远端 DoH 服务器（如 Quad9 9.9.9.10）时，HTTP/2 长连接在空闲时易被远端重置，Go http2 抛出 unexpected EOF。且未配快速标准 DNS 备援，导致 DNS 模块超时返回 empty response 并断流。
- **治理与防范规则**：
  1. 采用与 Anycast CDN 拓扑高度贴合的极速 Anycast DoH（如 `1.1.1.1`、`8.8.8.8`）；
  2. 必须包含标准公共 DNS 兜底（`"1.1.1.1"`, `"8.8.8.8"`），确保任何 DoH 重连/瞬断时均能在 2ms 内拿到 A 记录解析，保证 0 empty response。

