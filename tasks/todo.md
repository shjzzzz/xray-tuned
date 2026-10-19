# 任务清单与追踪：将权威 10 大核心节点固化为默认安装节点并同步 GitHub

## Goal
将宿主机当前全面验证通过的权威 10 大核心节点矩阵完整固化为全新安装脚本（`install.sh`）的默认安装配置，确保任意全新 VPS 部署均默认开启并渲染 10 大节点，同时全量同步全端订阅与 GitHub 远程仓库。

## Root Cause & Scope
- 此前安装脚本中三大后量子变量（`FEATURE_TLS_PQ_XHTTP`、`FEATURE_TLS_PQ_VISION`、`FEATURE_REALITY_PQ_VISION`）未在 `01-env.sh` 中显式初始化，且 `templates/client-config.txt.tmpl` 顶部未接入 PQ 链接；
- `FEATURE_REALITY_VISION` 历史默认值为 `false`，导致全新安装时第 9 节点被裁减；
- 本地 8001 入站模板此前仅包含 UUID2，缺少带 `flow: xtls-rprx-vision` 的 UUID1 客户端，导致 CDN Vision 节点（节点 2）回源时无法解密鉴权；
- 需全面升级 `src/01-env.sh`、`src/03-xray-install.sh`、`src/05-base-env.sh`、`src/06-tuning-lib.sh`、`src/09-server-config.sh`、`src/10-service-check.sh`、`src/11-client-config.sh`、`src/13-manage-cli.sh`、`src/14-final-output.sh` 与两份核心模板，构建 `dist/install*.sh` 并脱敏推送到 GitHub。

## Tasks
- [x] 1. 固化功能开关默认值：在 `src/01-env.sh` 与 `build-install.sh` 中将三大 PQ 节点及 `FEATURE_REALITY_VISION` 设为 `true`，`FEATURE_H2_DIRECT` 设为 `false`
- [x] 2. 补齐本地 8001 入站双客户端：在 `templates/xray-config.json.tmpl` 中注入 UUID1 (`flow: xtls-rprx-vision`)，支持 CDN Vision 节点
- [x] 3. 补齐防火墙与端口保护：在 `05-base-env.sh`、`06-tuning-lib.sh`、`03-xray-install.sh` 中放行并保留 TCP 8447
- [x] 4. 固化客户端 10 大核心节点生成与矩阵排序：在 `src/11-client-config.sh` 与 `templates/client-config.txt.tmpl` 中生成权威 10 节点
- [x] 5. 消除管理命令硬编码：`src/13-manage-cli.sh` 中 `spx` 改为动态哈希派生，`src/14-final-output.sh` 提示补充 TCP 8447
- [x] 6. 重新编译 `dist/install.sh` 与 `dist/install-xpadding.sh`，执行全量 `bash -n` 校验
- [x] 7. 实机配置同步验证：在隔离测试环境与实机渲染验证 10 核心节点 100% 吻合，执行 `xh resub` 刷新订阅
- [x] 8. 敏感信息脱敏审查（Sanitization Check）
- [ ] 9. 向用户明确展示待推送仓库、分支及 commit 摘要，请求执行 `git push`（严格红线）

## Verification Results
- V1: 隔离环境模拟渲染实测输出 10 行有效节点链接，与 README 权威 10 节点矩阵严格 1:1 对齐。
- V2: `bash -n` 验证 `dist/install*.sh` 与 `src/*.sh` 全部 100% 语法正确。
- V3: `/usr/local/bin/xray -test -config /usr/local/etc/xray/config.json` 语法与流控校验全部 OK。
- V4: 宿主机实机 `/home/ubuntu/client-config.txt` 成功同步为权威 10 节点，`xh resub` 成功更新全部订阅文件。

