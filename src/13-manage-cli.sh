# ==================================================
# 安装管理命令 xh + 保活自愈 + 内核自动更新
# ==================================================

info "[7/7] 安装管理命令 ${MANAGE_CMD}"

cat > "$MANAGE_BIN" << 'XHMANAGEEOF'
@@include src/manage/00-header.sh
@@include src/manage/01-service.sh
@@include src/manage/02-node.sh
@@include src/manage/03-network.sh
@@include src/manage/04-cloudflare.sh
@@include src/manage/05-menu.sh
@@include src/manage/06-dispatch.sh
XHMANAGEEOF

# 把版本号注入生成好的 xh。上面的 heredoc 是 quoted 的（不展开变量），这是刻意的：
# xh 里满是 ${VAR} 与 $(...)，一旦改成非 quoted，整个脚本会在安装时就被展开掉。
# 因此版本号只能事后替换。占位符用 @@..@@ 而非 ${..}，就是为了不与 shell 语法冲突。
sed -i "s|@@XH_VERSION@@|${PROJECT_VERSION}|" "$MANAGE_BIN" || \
  warn "版本号注入失败，${MANAGE_CMD} version 将显示占位符（不影响其它功能）"

chmod +x "$MANAGE_BIN"
info "管理命令已安装: ${MANAGE_BIN}"

# v4.2.0：内核层调优在安装时自动执行（best-effort，失败不阻断）。
# OpenVZ / LXC 只读 sysctl 会自动跳过并告警，不影响已跑通的节点。
# 回滚: xh tuning off  /  跳过: FEATURE_AUTO_TUNING=false
FEATURE_AUTO_TUNING=${FEATURE_AUTO_TUNING:-true}
if [[ "$FEATURE_AUTO_TUNING" == true ]]; then
  "$MANAGE_BIN" tuning on >/dev/null 2>&1 && info "系统层调优已自动应用（BBR / 缓冲区 / 句柄 / TFO）" || \
    warn "自动调优未生效（不影响节点功能），可稍后手动 ${MANAGE_CMD} tuning on"
fi

if [[ "$FEATURE_KEEPALIVE" == true ]]; then
  if command -v crontab >/dev/null 2>&1; then
    "$MANAGE_BIN" keepalive on >/dev/null 2>&1 && info "保活自愈已开启（每 5 分钟 + 开机自启）" || \
      warn "保活 cron 写入失败，可稍后手动执行 ${MANAGE_CMD} keepalive on"
  else
    warn "未找到 crontab，跳过保活配置"
  fi
fi

if [[ "$FEATURE_AUTOUPDATE" == true ]]; then
  if command -v crontab >/dev/null 2>&1; then
    "$MANAGE_BIN" autoupdate on >/dev/null 2>&1 && info "Xray 内核自动更新已开启（每周日 04:00）" || \
      warn "自动更新 cron 写入失败，可稍后手动执行 ${MANAGE_CMD} autoupdate on"
  fi
fi

echo ""
