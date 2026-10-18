# 经验教训与规则库 (Lessons Learned & Rules)

## 1. Xray XHTTP xmux 参数互斥红线 (2026-10-18)
- **错误现象**：客户端导入 `VLESS-TLS+PQ+XHTTP+CDN` 或 `VLESS-TLS+PQ+Vision+XHTTP+CDN` 后，v2rayN 启动内核崩溃，提示 `Failed to start: main: failed to load config files: [...] > infra/conf: maxConnections cannot be specified together with maxConcurrency`。
- **根本原因**：Xray 源码（`infra/conf`）明确限制：`xmux` 中的 `maxConnections`（最大底层物理连接数）与 `maxConcurrency`（单连接最大多路复用并发流数）属于互斥逻辑。若同时设置二者，Xray 在初始化 outbound streamSettings 时会直接拦截报错退出。
- **治理与防范规则**：
  1. **CDN 节点**：使用 `maxConnections: 16`，由客户端维护多条物理连接并行突破 Cloudflare 边缘单流限速；**严禁在 CDN 节点的 `extra.xmux` 中同时注入 `maxConcurrency`**。
  2. **直连节点**：使用 `maxConcurrency: "16-32"`，在单条物理长连接中多路复用并进行流控混淆。
  3. **完成前验证（Verification Before Done）**：每次修改客户端链接参数或生成脚本后，必须运行测试脚本，调用 `/usr/local/bin/xray -test -config` 模拟客户端 outbound 完整 JSON 结构进行内核配置语法与语义校验，确保 100% 通过方可标记完成。
