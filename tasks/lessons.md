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

## 5. 多入站架构下的 Client 凭据与模板闭环红线 (2026-10-19)
- **错误现象**：`VLESS-REALITY+PQ+Vision（自域名）`（TCP 8447）节点导入客户端后完全不通，连接握手无响应或被直接回落拦截。
- **根本原因**：独立直连入站（`reality-pq-vision-in`）在历史注入时，`settings.clients` 数组为空（`"clients": []`），缺少 UUID1 与 `flow: xtls-rprx-vision` 的授权条目。导致任何客户端连接因无匹配用户被判定未授权并强制走 fallback。且源码模板未设立统一的入站插槽变量，导致模板缺乏该入站的自动生成逻辑。
- **治理与防范规则**：
  1. 任何新增的独立入站（如独立非标端口 REALITY/XHTTP）必须将配置模板抽象为函数与变量（如 `xray_reality_pq_vision_inbound` 与 `XRAY_REALITY_PQ_VISION_INBOUND`），统一由 `node.env` 的 Feature 开关控制，坚决杜绝脱离模板的实机裸写；
  2. 严格核验客户端与服务端凭据对齐：客户端链接所用的 UUID 与 flow 必须 100% 存在于服务端对应的 `settings.clients` 列表中；
  3. 完成前验证：必须运行本地模拟测试，针对真实端口发起握手验证。

## 6. GitHub 远程同步审批红线 (2026-11-01)
- **核心铁律**：任何代码、脚本、配置或文档推送到远程仓库（`git push`、创建或推送 Release Tag 等），**必须由用户明确批准后方可执行**。
- **治理与防范规则**：
  1. 无论本地代码是否通过测试，修改验证完毕后仅在本地做 `git commit` 保存，严禁擅自执行 `git push`；
  2. 必须在回复中向用户展示修改摘要与测试结果，明确请求确认：“是否批准推送到 GitHub 远程仓库？”；
  3. 仅在收到用户明确肯定的指示后，方可执行远程同步。


## 7. 沙箱回归必须隔离所有带路径的变量，并校验线上文件未被改动 (2026-11-02)
- **事故**：`tools/xh-sandbox-test.sh` 只把写死的路径常量替换成临时目录，漏了 `node.env` 里的 `USER_HOME=/root`。xh 据此读写 `client-config*`，结果沙箱里的开关实际改写了线上订阅文件。直到把本机文件以只读方式挂进 Ubuntu 容器，才暴露出来。
- **治理与防范规则**：
  1. 沙箱要同时改写**路径常量**与**环境变量/配置里的路径**（`USER_HOME`、`STATE_DIR` 等），并在跑完后断言线上文件哈希与跑之前一致；
  2. 在容器里用只读挂载跑一遍，是发现泄漏最便宜的办法；
  3. 判断「默认值」「基线」前，先 `git pull` 并以当前 `origin/main` 为准，不要用落后的本地克隆（上一轮据此写错了 README 的开关列表）；
  4. REALITY+PQ+Vision 与 Vision-Direct 共用 443 上同一个 Vision 客户端项，任何关闭 Vision 的操作都要先检查 PQ-Vision 是否还在用。

## 8. REALITY 后量子握手与内核版本兼容红线 (2026-11-05)
- **错误现象**：客户端导入 `VLESS-REALITY+PQ+Vision` 后完全不通，连接握手直接超时；服务端报 `proxy/vless/inbound: fallback starts > proxy/vless/encoding: invalid request version`，随后进入 fallback 导致连接中断（`write: broken pipe`）。
- **根本原因**：新版客户端（如 v2rayN >= 26.9+ 或配置了 `support-x25519mlkem768: true` 的 Mihomo）向 REALITY 发送了后量子混合密钥 `X25519MLKEM768`。若服务端 443 端口由兼容旧内核 `xray-legacy` (26.7.28) 承载，该旧内核不认识后量子扩展，导致 ECDH 共享密钥计算不一致引发认证失败。认证失败后作为普通 TLS 密文回落至 8001 XHTTP 入站被直接重置。
- **治理与防范规则**：
  1. 开启 `FEATURE_REALITY_PQ_VISION=true` 或客户端需要后量子抗量子破译时，443 端口必须使用原生最新版 Xray 内核（>= 26.9.30，实机当前 26.10.31），严禁绑定不支持 ML-KEM-768 的旧版 legacy 内核；
  2. `src/09a-reality-legacy.sh` 需具备后量子感知逻辑，当 `FEATURE_REALITY_PQ_VISION=true` 且未强制指定 legacy 时自动选用原生最新内核承载；
  3. 完成前验证：必须模拟带后量子 ClientHello 针对 443 发起端到端握手测试，断言返回 HTTP 200/204。

## 9. Reality 与 XHTTP 客户端链接标准规范与鉴权闭环 (2026-11-06)
- **错误现象**：v2rayN 客户端对 `VLESS-REALITY+PQ+Vision`、`VLESS-Reality-XHTTP-Direct`、`VLESS-Reality-Up-CDN-Down` 测速报 `-1`，连接无法建立。
- **根本原因**：
  1. **UUID2 鉴权缺失**：443 端口 Reality 入站的 `settings.clients` 仅包含 UUID1，使用 UUID2 的 Reality-XHTTP 直连及上下行分离节点在解密后 VLESS 认证直接被拒；
  2. **客户端链接非标准传输参数**：`type=raw` 无法被 v2rayN 正确解析为底层 tcp 流；`alpn=h2,http/1.1` 包含逗号在 v2rayN 中被解析为单一字面量导致 ALPN 协商失败；
  3. **TFO 阻断**：Windows 套接字默认不支持客户端 TFO，且国内运营商中间设备丢弃带数据的 SYN 包导致连接挂起超时；
  4. **路径尾斜杠与 Nginx 重写**：Xray XHTTP 期望尾部斜杠（`/path/`），缺少尾部斜杠且 Nginx 未做重写时导致 404/400 路由失效。
- **治理与防范规则**：
  1. **443 入站全量 UUID 注入**：443 入站的 clients 必须完整包含 UUID1 与 UUID2（flow 均为 `xtls-rprx-vision`）；
  2. **协议传输标准规范**：直连 Vision 统一使用 `type=tcp` 与 `alpn=h2`，移除阻碍连接的 `tfo=1`；
  3. **路径尾斜杠与 Nginx 兜底**：所有 XHTTP 链接路径统一规范为带尾部斜杠 `/path/`，且 Nginx location 中必须配置 `rewrite ^${XHTTP_PATH}$ ${XHTTP_PATH}/ break;` 做严格容错兜底；
  4. **全端编译分发**：执行 `xh resub` 重新分发全量订阅并经真实握手测试。

## 2026-11-06 节点在 v2rayN 与 Shadowrocket 客户端连通性修复
- **TFO (TCP Fast Open) 破坏 iOS/移动端握手**：
  在 `02-node.sh` 的 `SRPY`（Shadowrocket 专属订阅转换）中切勿向直连节点强插 `&tfo=1`。iOS 移动网络和国内多数家庭路由器会丢弃携带数据的 TCP SYN 包，导致握手直接挂死超时。
- **XTLS Vision 的 ALPN 规范**：
  Reality Vision 链接不应硬编码 `alpn=h2`。官方规范是由客户端 uTLS 模拟指纹（Chrome / Safari）自行协商真实 ALPN (`h2, http/1.1`)。强制写死 `alpn=h2` 会导致 ALPN 协商错乱或被防火墙指纹识别。
- **废弃字段 allowInsecure 彻底剔除**：
  Xray 26.10+ 内核已完全删除 `allowInsecure`。链接中携带该参数会导致现代客户端解析报致命异常，必须全部清理。
- **订阅重写顺序陷阱**：
  在 `PYRESUB` 循环中，若要在重定向 CDN 地址时调用 `urlunparse(p)`，必须置于字符串参数替换（如 `re.sub` 清除 `tfo`、`insecure`、添加斜杠）之前执行，否则 `urlunparse` 会使用旧的 `p.query` 覆盖所有后续清理结果。
- **开启可靠 CDN 兜底节点**：
  在任何情况下均应启用 `FEATURE_CDN_H2=true`，生成走 Cloudflare 443 的 TCP 节点，作为直连 IP 遭遇干扰或 UDP 被封禁时的全天候网络生命线。

## 10. 跨境网络 PMTU 黑洞与流媒体 Bufferbloat 综合治理 (2026-11-07)
- **现象与瓶颈**：
  1. 跨境高延迟链路（如中美 140~180ms RTT）下，若中间设备对 ICMP Type 3 Code 4（Fragmentation Needed）静默丢弃，遇非对称 MTU（PPPoE 1492 / 移动 4G 1420）易发生 PMTU 黑洞死锁，导致 TLS 证书握手与大包静默超时；
  2. 套接字未发送缓冲区 `tcp_notsent_lowat` 过大（512KB）会导致 BBR 调步发送队列积压，在 YouTube 4K/8K 等流媒体高突发下载时造成显著 Bufferbloat 与往返抖动，拖慢首屏与暂停恢复。
- **治理与防范规则**：
  1. **PLPMTUD 主动探测与底线锁定**：开启 `net.ipv4.tcp_mtu_probing = 1`（RFC 4821）时，**必须同步显式设置 `net.ipv4.tcp_base_mss = 1360`、`net.ipv4.tcp_mtu_probe_floor = 1360` 与 `net.ipv4.tcp_min_snd_mss = 536`**。若保留内核默认底线（`tcp_base_mss=1024, tcp_mtu_probe_floor=48`），在跨境移动高丢包链路（8%+ 重传）发生连续 RTO 时，内核会误判为 PMTU 黑洞并将 MSS 二分腰斩至 `512 -> 256 -> 64 -> 48` 字节，导致 850KB 发送队列被切碎为 3300+ 个极小分片、`cwnd` 锁死为 1、吞吐跌至 7kbps（表现为 Reality 彻底断流）；锁定 `1360`（对应 MTU 1400）既兼容 PPPoE 1492 / 蜂窝 1420，又彻底杜绝 MSS 崩塌。
  2. **发送缓冲收敛**：`tcp_notsent_lowat` 收敛至 **128KB (131072)**，既满足千兆 BDP 管道吞吐，又杜绝发送端缓冲膨胀，平滑流媒体 Pacing；
  3. **客户端 QUIC 策略**：跨境 UDP 443 易受运营商 QoS 丢包影响，客户端路由规则中阻断国外 UDP 443 强制回退 HTTP/2 over Vision TCP，吃满内核 splice 零拷贝硬件加速。

## 2026-11-08 sing-box(sbbox)节点并入 Mihomo 订阅
- Mihomo 没有 Naive 出站,sbbox 的 naive 节点无法进入 Mihomo 订阅;hy2 / anytls / tuic 可以。
- 合并只作用于订阅目录里的 `mihomo-*.yaml` 副本(`mihomo_merge_sbbox`,`tools/merge_sbbox_mihomo.py`),源文件 `client-config-mihomo-*.yaml` 保持纯 Xray 节点,避免与其它重生成逻辑冲突;节点名加 `SB-` 前缀(sing-box 与 Xray 都有 `Hysteria2-TLS-BBR-Salamander`)。
- 数据源是 `/root/sbbox/clmi.yaml`(可用 `SBBOX_CLMI` 覆盖);sbbox 改端口/密码后需再执行 `xh resub` 才会同步。

## 11. Xray XHTTP 长连接周期性卡顿断流与 Nginx/客户端全链路参数协调性治理 (2026-11-08)
- **错误现象**：Xray 内核节点在连接运行一段时间后，突然出现卡顿、新建网页连接挂死或断流，且 `ss -tinp` 观测到同一客户端并存多条半闲置连接与回环 `127.0.0.1:8001` 虚假重传（`dsack_dups: 38`）。
- **根本原因（基于 `/usr/local/bin/xray` 26.10.31 机器码反汇编与 `ss -tinp` 实证）**：
  1. **`scStreamUpServerSecs: "300-600"` 语义误解导致服务端保活饥饿**：反汇编 `splithttp.(*requestHandler).ServeHTTP.func1` (`0xb5b880`) 证实，该参数并非断流超时，而是服务端在 `stream-up` POST 响应流上定时写入随机长度 `'X'` (`0x58`) 保活填充块（heartbeat padding）的 `time.Sleep` 间隔（官方默认 `"20-80"` 秒，`GetNormalizedScStreamUpServerSecs` @ `0xb4b980`）。误设为 `"300-600"` 导致 5~10 分钟无保活包，被 Cloudflare CDN（100s）、Nginx（`send_timeout 300s`）及运营商 NAT 静默掐断。
  2. **客户端 `xmux` 过度限制（`cMaxReuseTimes: "16-32"`, `hMaxRequestTimes: "100-200"`, `hMaxReusableSecs: "300-600"`）**：反汇编 `newXmuxClient` (`0xb56120`) 与 `getXmuxClient` (`0xb564a0`) 证实，`stream-up` 模式下每条代理流消耗 2 次 HTTP 请求（1 GET + 1 POST），导致单条 H2 连接仅承载 16~32 条流（约 1~3 分钟网页浏览）即耗尽配额，迫使客户端在高丢包跨境链路（实测移动 7.9% 重传率）上频繁重做 TCP+REALITY 握手，一旦新握手丢包即触发全连接卡死；且 Mihomo 模板内 Direct-H2/H3 (`16-32 / 0 / 600-900 / 1800-3000`) 与 Reality-XHTTP (`8-16 / 16-32 / 100-200 / 300-600`) 严重分裂。
  3. **回环入站 `127.0.0.1:8001/8002` 未显式指定拥塞控制**：省略 `tcpcongestion` 导致回环套接字继承系统全局 `bbr`，当公网 443 腿因客户端接收窗口打满（`rwnd_limited: 83.6%`）产生背压时，回环 RTT 从 `0.007ms` 飙升至 `14.6ms`，触发 BBR 虚假重传（`dsack_dups: 38`）并将 `cwnd` 压垮至 9。
  4. **Nginx 与 Xray 超时倒挂及配置失步**：Nginx `upstream xray_xhttp` 的 `keepalive_timeout 3600s` 大于 Xray `connIdle: 1800s`，存在复用已关闭连接触发 502 RST 的竞态；`location /cc3939d7` 的 `client_body_timeout 300s` 与 `grpc_read_timeout 1h` 冲突，5 分钟无上行数据即掐断 `stream-up` POST 请求体；`reality.cch.us.kg` 伪装站错误广播 `Alt-Svc: h3=":443"`。
  5. **`tcpUserTimeout: 60000` (60s) 过短与 `freedom` 出站 `tcpFastOpen: true`**：60s 传输出局超时在跨境高抖动下易误杀整条多路复用连接；出站开启 TFO 易被目标网站防火墙丢弃 SYN。
- **治理与防范规则**：
  1. **服务端保活恢复**：所有 XHTTP 入站统一设置 `"scStreamUpServerSecs": "20-80"`，移除冗余 `"extra"` 嵌套块；
  2. **客户端 `xmux` 全节点统一**：直连与上下行分离节点统一为 `maxConcurrency: "16-32"`（CDN URI 节点用 `maxConnections: 16`）、`cMaxReuseTimes: 0`、`hMaxRequestTimes: "600-900"`、`hMaxReusableSecs: "1800-3000"`、`hKeepAlivePeriod: 15`，彻底清除残留 `tfo: true`；
  3. **回环与公网 `sockopt` 隔离**：回环 `8001/8002` 显式声明 `"tcpcongestion": "cubic"`；公网入站 `443/8445` 与 `freedom` 出站统一设置 `tcpKeepAliveIdle: 60, tcpKeepAliveInterval: 15, tcpUserTimeout: 300000`，出站移除 `tcpFastOpen`；
  4. **Nginx 超时严格对齐**：`upstream` `keepalive_timeout 900s`（严格小于 Xray `connIdle 1800s`），XHTTP location 的 `client_body_timeout / send_timeout / grpc_read_timeout / grpc_send_timeout` 全部对齐为 `1h`，移除 `reality.cch.us.kg` 的 `Alt-Svc: h3=":443"`。

## 2026-11-11 Mihomo 的 VLESS encryption 必须与服务端 decryption 一致
- **现象**：mihomo 客户端 Reality-XHTTP / XHTTP-Direct-H2 / H3 全部 502，Xray 客户端同样节点正常。
- **根因**：服务端 XHTTP 入站（8001 / 8443 / 8445）启用 VLESS Encryption（`mlkem768x25519plus`），v2rayN 链接带 `encryption=<串>`，但 `templates/mihomo-proxies.yaml.tmpl` 与 `cmd_resub` 里重建 Reality-XHTTP 节点的代码都写死 `encryption: none`。Vision 入站（443，`decryption=none`）才应写 none。
- **实测**（mihomo v1.19.34，直连监听口）：`none` → 502；链接里的加密串 → 204。mihomo v1.19.10 即使写对也不通（内核太旧，不支持 VLESS Encryption）。
- **规则**：
  1. mihomo 节点的 `encryption` 以 `client-config.txt` 链接为准（`cmd_resub` 已按节点名同步）；模板里 XHTTP 节点用 `${XHTTP_ENCRYPTION}`。
  2. 客户端需更新到支持 VLESS Encryption 的 mihomo（v1.19.34 实测可用，v1.19.10 不可用）。
  3. 沙箱跑 `cmd_resub` 抽出的 Python 前，必须隔离脚本里硬编码的 `/etc/xhttp-cdn/all/*` 路径（本次漏了，改写了 3 个线上节点库文件，见 lessons #7）。

## 2026-11-11 microsoft 规则集 404 与分组成员被清空
- **microsoft 404**：`Loyalsoldier/clash-rules@release` 没有 `microsoft.txt`（jsDelivr 404，其余 22 个规则集均 200）。改用 MetaCubeX `meta-rules-dat@meta/geo/geosite/microsoft.yaml`（`behavior: domain`，756 条，mihomo 实测加载成功）；`cmd_resub` 会把已部署文件里的旧地址自动换掉。
- **线上 `mihomo-full.yaml` 曾无法被 mihomo 加载**：11-10 14:36 重新生成后，所有分组的静态成员被清空（`节点选择`、`谷歌服务`……`proxies: []`），`广告过滤` / `全局拦截` 既无 proxies 也无 include-all，mihomo 报 `proxy group[2]: 广告过滤: use or proxies missing` 并拒绝加载整份配置。
- **未定位到清空动作的来源**：沙箱里用 v5.6.0 / HEAD 的渲染函数、`cmd_resub` 的 Python、`backup_node_sync_files` 的 on/off 逐一复现，产物分组都正常，故不是这几处。`cmd_resub` 现在对「成员为空且无 use 的分组」按模板默认值补回（只补空组），并在写回前校验。再出现请先查是谁在 11-10 之后改写了客户端文件。
- **验证口径**：订阅文件必须用 `mihomo -t -f` 实际校验，仅 PyYAML 能解析不代表 mihomo 能加载；此前所有节点测试都用独立监听口、绕过了分组，因此没发现这个问题。
