# ==================================================
# 服务生命周期与系统运维
# ==================================================
cmd_status() {
  if [[ -s "${STATE_DIR}/updates-available" ]]; then
    echo -e "${YELLOW}[!] 有可用更新（每周检查，需手动执行）：${NC}"
    sed 's/^/  /' "${STATE_DIR}/updates-available"
    echo ""
  fi
  echo -e "${CYAN}[+] 服务状态${NC}"
  for s in xray nginx hysteria-server; do
    if [[ "$SERVICE_TYPE" == "openrc" ]]; then
      [[ -f "/etc/init.d/$s" ]] || continue
    else
      systemctl list-unit-files "${s}.service" >/dev/null 2>&1 || continue
      [[ -f "/etc/systemd/system/${s}.service" || -f "/lib/systemd/system/${s}.service" ]] || continue
    fi
    if svc_active "$s"; then
      echo -e "  ${s}: ${GREEN}running${NC}"
    else
      echo -e "  ${s}: ${RED}stopped${NC}"
    fi
  done

  echo -e "\n${CYAN}[+] 监听端口${NC}"
  if command -v ss >/dev/null 2>&1; then
    ss -tulnp 2>/dev/null | grep -E 'xray|nginx|hysteria' || echo "  （未发现相关监听）"
  else
    warn "未安装 ss，跳过端口检查"
  fi

  echo -e "\n${CYAN}[+] 流控状态${NC}"
  local _cores _mem _arch _tier _buf _buf_mb _cap_mb
  _cores=$(nproc 2>/dev/null || echo '?')
  _mem=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  _arch=$(uname -m 2>/dev/null || echo unknown)
  if   [[ "$_mem" -ge 16384 ]]; then _tier=large; _buf_mb=64; _cap_mb=64;
  elif [[ "$_mem" -ge 4096  ]]; then _tier=medium; _buf_mb=64; _cap_mb=64;
  elif [[ "$_mem" -ge 1536  ]]; then _tier=entry; _buf_mb=32; _cap_mb=32;
  else _tier=small; _buf_mb=16; _cap_mb=16; fi

  echo -e "  推荐缓冲区：             ${GREEN}${_buf_mb}MB${NC}"
  echo -e "  内存保护上限：           ${GREEN}${_cap_mb}MB${NC}"
  echo -e "  队列算法：               ${GREEN}$(sysctl -n net.core.default_qdisc 2>/dev/null || echo n/a)${NC}"
  echo -e "  拥塞控制：               ${GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo n/a)${NC}"
  printf '  %-32s %s\n' "  └─ BBR 版本" "$(detect_bbr_version)"
  echo -e "  tcp_wmem:                 ${GREEN}$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo n/a)${NC}"
  echo -e "  tcp_rmem:                 ${GREEN}$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo n/a)${NC}"
  echo -e "  tcp_limit_output_bytes:   ${GREEN}$(sysctl -n net.ipv4.tcp_limit_output_bytes 2>/dev/null || echo n/a)${NC}"
  echo -e "  tcp_slow_start_after_idle: ${GREEN}$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo n/a)${NC}"
  printf '  %-32s %s\n' "net.core.rmem_max"               "$(sysctl -n net.core.rmem_max 2>/dev/null || echo n/a)"
  printf '  %-32s %s\n' "net.ipv4.tcp_fastopen"           "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo n/a)"
  # config.json 带 // 注释（JSONC），jq 解析不了，用文本提取
  _buf=$(grep -oE '"bufferSize"[[:space:]]*:[[:space:]]*[0-9]+' "$XRAY_CONF" 2>/dev/null \
         | head -1 | grep -oE '[0-9]+$')
  printf '  %-32s %s\n' "机型 / 调优档位" "${_cores} 核 / ${_mem} MB / ${_arch} → ${_tier}"
  printf '  %-32s %s\n' "Xray policy.bufferSize" "${_buf:-未设置} KB"
  if [[ -f "$SYSCTL_CONF" ]]; then
    printf '  %-32s %s\n' "调优配置文件" "$SYSCTL_CONF（已启用）"
  elif [[ -f /etc/sysctl.d/99-sbbox.conf ]]; then
    printf '  %-32s %s\n' "调优配置文件" "/etc/sysctl.d/99-sbbox.conf（已由 sbbox 启用生效）"
  else
    printf '  %-32s %s\n' "调优配置文件" "未启用（安装时自动开启，或手动 xh tuning on）"
  fi
  if [[ "$SERVICE_TYPE" == "systemd" ]] && svc_active xray; then
    local pid
    pid=$(systemctl show -p MainPID --value xray 2>/dev/null)
    if [[ -n "$pid" && "$pid" != "0" && -r "/proc/$pid/limits" ]]; then
      printf '  %-32s %s\n' "xray 进程 nofile" "$(awk '/Max open files/{print $4}' "/proc/$pid/limits")"
    fi
  fi

  echo -e "\n${CYAN}[+] 版本${NC}"
  [[ -x "$XRAY_BIN" ]] && echo "  $($XRAY_BIN version 2>/dev/null | head -1)"
  command -v nginx >/dev/null 2>&1 && echo "  $(nginx -v 2>&1)"
}
cmd_log() {
  case "${1:-xray}" in
    nginx) tail -n "${2:-50}" -f /usr/local/nginx/logs/error.log ;;
    xray)
      if [[ "$SERVICE_TYPE" == "systemd" ]]; then
        journalctl -u xray -n "${2:-50}" -f --no-pager
      else
        tail -n "${2:-50}" -f /var/log/xray/error.log
      fi
      ;;
    *) fail "用法: xh log [xray|nginx] [行数]" ;;
  esac
}

# 出站分流开关：屏蔽回国 IP / 广告域名（默认关闭）。参考 zxcvos/Xray-script 的 cn-ip / ad-domain 规则。
#   cn  → freedom 出站的 finalRules（域名解析成 IP 之后再判），geoip:cn 直接 block
#   ads → routing 规则 domain geosite:category-ads-all → block
# 每条规则占单独一行并带 xh-block-* 标记，开关只增删该行；先 xray -test 校验，失败自动回滚。
cmd_restart() {
  for s in xray nginx; do
    svc restart "$s" && info "${s} 已重启" || warn "${s} 重启失败"
  done
  if [[ -f /etc/hysteria/config.yaml ]]; then
    svc restart hysteria-server >/dev/null 2>&1 && info "hysteria-server 已重启" || true
  fi
}

cmd_start() { for s in xray nginx; do svc start "$s" || warn "${s} 启动失败"; done; }
cmd_stop()  { for s in xray nginx; do svc stop  "$s" || warn "${s} 停止失败"; done; }

# 更新 Xray-core：先备份，配置自检失败自动回滚
# 用法: xh update [<版本号>] [--auto]
cmd_update() {
  local auto=0 target_ver=""
  for arg in "$@"; do
    case "$arg" in
      --auto) auto=1 ;;
      *) [[ -z "$target_ver" ]] && target_ver="$arg" ;;
    esac
  done

  [[ -x "$XRAY_BIN" ]] || fail "未找到 ${XRAY_BIN}"
  local current latest backup
  current=$("$XRAY_BIN" version 2>/dev/null | head -1 | awk '{print $2}')
  current="${current#v}"

  case "$current" in
    26.10.10|26.10.17) warn "当前 Xray ${current} 内置了已被攻破的根证书，官方已撤版，请尽快升级到 26.10.21 或更新版本" ;;
  esac

  local force_channel=""
  if [[ "$target_ver" == "pre" || "$target_ver" == "prerelease" ]]; then
    force_channel="prerelease"
    target_ver=""
  elif [[ "$target_ver" == "stable" ]]; then
    force_channel="stable"
    target_ver=""
  fi

  local active_channel="${force_channel:-${XRAY_CHANNEL:-stable}}"
  if [[ -n "$target_ver" ]]; then
    latest="${target_ver#v}"
  else
    # 自动更新 / 默认更新跟随正式版 (stable /releases/latest)。
    # 仅当手动指定 pre 或 XRAY_CHANNEL=prerelease 时获取 /releases 列表最新 pre-release。
    if [[ "$active_channel" == "prerelease" ]]; then
      latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/XTLS/Xray-core/releases" 2>/dev/null \
        | grep -m1 '"tag_name"' | cut -d'"' -f4)
    else
      latest=$(curl -fsSL --max-time 15 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name"' | cut -d'"' -f4)
    fi
    latest="${latest#v}"
    [[ -z "$latest" ]] && latest="${XRAY_DEFAULT_VERSION:-26.10.21}"
  fi

  if [[ -z "$latest" ]]; then
    warn "无法获取 Xray-core 目标版本号，跳过本次更新"
    return 0
  fi

  # 拦截与检查测试版本 (pre-release)
  local is_prerelease
  is_prerelease=$(curl -fsSL --max-time 15 "https://api.github.com/repos/XTLS/Xray-core/releases/tags/v${latest}" 2>/dev/null | grep -m1 '"prerelease"' | grep -oE 'true|false')
  local ver_type="正式版"
  [[ "$is_prerelease" == "true" ]] && ver_type="增强测试版 / Pre-release"

  info "当前版本: ${current:-未知}  目标版本: ${latest} (${ver_type})"
  if [[ "$current" == "$latest" ]]; then
    info "已是目标版本 (${latest})，无需更新"
    return 0
  fi

  if [[ "$is_prerelease" == "true" ]]; then
    if [[ $auto -eq 1 && "$active_channel" != "prerelease" ]]; then
      warn "正式版 (stable) 自动更新跳过 Pre-release 版本 v${latest}"
      return 0
    fi
    warn "目标版本 v${latest} 被标记为 Pre-release / 测试版本，可能引入实验性更改"
    if [[ $auto -eq 0 ]]; then
      read -rp "确定仍要安装此测试版本吗? [y/N]: " force_reply
      [[ "${force_reply,,}" == "y" ]] || { info "已取消安装测试版本"; return 0; }
    fi
  fi

  if [[ $auto -eq 0 ]]; then
    read -rp "确认安装/更新到 ${latest}? [y/N]: " reply
    [[ "${reply,,}" == "y" ]] || { info "已取消"; return 0; }
  fi

  backup="${XRAY_BIN}.bak-${current:-old}"
  cp -f "$XRAY_BIN" "$backup" || fail "备份 Xray 二进制失败，已中止更新"
  info "已备份旧版本 → ${backup}"

  local ok=0
  if [[ "${OS_ID:-}" != "alpine" ]]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version "v${latest}" && ok=1
  else
    local arch asset tmpdir
    arch=$(uname -m)
    case "$arch" in
      x86_64|amd64) asset="Xray-linux-64.zip" ;;
      aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
      *) warn "Alpine 暂不支持架构 ${arch}"; return 0 ;;
    esac
    tmpdir=$(mktemp -d)
    # 用已检测到的真实最新 tag 下载（releases/latest/download 只指向非 prerelease 的旧版）
    if curl -fL "https://github.com/XTLS/Xray-core/releases/download/v${latest}/${asset}" -o "${tmpdir}/xray.zip" &&
       unzip -qo "${tmpdir}/xray.zip" -d "$tmpdir"; then
      install -m 755 "${tmpdir}/xray" "$XRAY_BIN"
      install -m 644 "${tmpdir}/geoip.dat" /usr/local/share/xray/geoip.dat 2>/dev/null || true
      install -m 644 "${tmpdir}/geosite.dat" /usr/local/share/xray/geosite.dat 2>/dev/null || true
      ok=1
    fi
    rm -rf "$tmpdir"
  fi

  if [[ $ok -ne 1 ]]; then
    warn "下载 / 安装失败，回滚到备份版本"
    cp -f "$backup" "$XRAY_BIN"
    svc restart xray || true
    return 1
  fi

  if ! "$XRAY_BIN" -test -config "$XRAY_CONF" >/dev/null 2>&1; then
    warn "新版本配置自检失败，回滚到 ${current:-旧版本}"
    cp -f "$backup" "$XRAY_BIN"
    svc restart xray || true
    return 1
  fi

  svc restart xray || { warn "重启失败，回滚"; cp -f "$backup" "$XRAY_BIN"; svc restart xray || true; return 1; }
  sleep 1
  if svc_active xray; then
    info "已更新到 $("$XRAY_BIN" version 2>/dev/null | head -1)"
  else
    warn "Xray 未能启动，回滚"
    cp -f "$backup" "$XRAY_BIN"
    svc restart xray || true
    return 1
  fi
}
cmd_guard() {
  local restarted=0
  for s in xray nginx; do
    if ! svc_active "$s"; then
      svc restart "$s" >/dev/null 2>&1 && restarted=1
      logger -t xray-xhttp "guard: restarted ${s}" 2>/dev/null || true
    fi
  done
  if systemctl is-enabled --quiet hysteria-server 2>/dev/null && [[ -f /etc/hysteria/config.yaml ]] && ! svc_active hysteria-server; then
    svc restart hysteria-server >/dev/null 2>&1 || true
  fi
  [[ $restarted -eq 1 ]] && info "已拉起异常服务" || true
  return 0
}

cron_write() {
  local body="$1"
  local tmp
  tmp=$(mktemp)
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" > "$tmp" || true
  [[ -n "$body" ]] && printf '%s\n' "$body" >> "$tmp"
  crontab "$tmp" && rm -f "$tmp"
}

cmd_keepalive() {
  case "${1:-show}" in
    on)
      cron_write "$(crontab -l 2>/dev/null | grep "$CRON_TAG" | grep -v 'guard'; \
        echo "*/5 * * * * /usr/local/bin/xh guard >/dev/null 2>&1 ${CRON_TAG} guard"; \
        echo "@reboot /usr/local/bin/xh guard >/dev/null 2>&1 ${CRON_TAG} guard")"
      info "保活已开启（每 5 分钟检查 + 开机自启）"
      ;;
    off)
      cron_write "$(crontab -l 2>/dev/null | grep "$CRON_TAG" | grep -v 'guard')"
      info "保活已关闭"
      ;;
    show|*)
      crontab -l 2>/dev/null | grep "$CRON_TAG" || info "未配置任何本项目 cron 任务"
      ;;
  esac
}

cmd_autoupdate() {
  local act="${1:-show}" sub="${2:-}"
  case "$act" in
    on)
      cron_write "$(crontab -l 2>/dev/null | grep "$CRON_TAG" | grep -v 'update --auto'; \
        echo "0 4 * * 0 /usr/local/bin/xh update --auto >/dev/null 2>&1 ${CRON_TAG} autoupdate")"
      info "自动更新已开启（每周日 04:00：自动更新至最新正式版、失败回滚；nginx / tcp-brutal 只检查并提醒；日志 journalctl -t xh-autoupdate）"
      ;;
    off)
      cron_write "$(crontab -l 2>/dev/null | grep "$CRON_TAG" | grep -v 'update --auto')"
      info "内核自动更新已关闭"
      ;;
    stable)
      update_node_env XRAY_CHANNEL stable
      export XRAY_CHANNEL=stable
      info "Xray 内核通道已设置为: stable (仅更新官方正式版)"
      ;;
    pre|prerelease)
      update_node_env XRAY_CHANNEL prerelease
      export XRAY_CHANNEL=prerelease
      info "Xray 内核通道已设置为: prerelease (允许自动更新 Pre-release 测试版)"
      ;;
    show|status|*)
      echo ""
      echo -e "${CYAN}=== Xray 内核自动更新与通道设置 ===${NC}"
      local cron_status="${YELLOW}未开启${NC}"
      crontab -l 2>/dev/null | grep -q 'update --auto' && cron_status="${GREEN}已开启 (每周日 04:00)${NC}"
      echo -e "  自动更新状态:  ${cron_status}"
      local ch="${XRAY_CHANNEL:-stable}"
      if [[ "$ch" == "prerelease" ]]; then
        echo -e "  更新通道模式:  ${YELLOW}Pre-release 测试版通道 (prerelease)${NC}"
      else
        echo -e "  更新通道模式:  ${GREEN}官方正式版通道 (stable, 默认推荐)${NC}"
      fi
      echo ""
      echo "  快捷命令:"
      echo "    xh autoupdate on / off        # 开启 / 关闭自动更新任务"
      echo "    xh autoupdate stable          # 设置为稳定正式版通道 (推荐)"
      echo "    xh autoupdate pre             # 设置为 Pre-release 测试版通道"
      echo ""
      ;;
  esac
}
nginx_latest_mainline() {
  curl -fsSL --max-time 20 https://nginx.org/en/download.html 2>/dev/null \
    | sed 's/Stable version.*//' | grep -o 'nginx-[0-9][0-9.]*\.tar\.gz' | head -1 \
    | sed 's/^nginx-//; s/\.tar\.gz$//'
}

nginx_build_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y -qq gcc make libpcre2-dev zlib1g-dev libssl-dev gnupg >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q gcc make pcre2-devel zlib-devel openssl-devel gnupg2 >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q gcc make pcre2-devel zlib-devel openssl-devel gnupg2 >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache build-base pcre2-dev zlib-dev openssl-dev linux-headers gnupg >/dev/null 2>&1
  fi
}

# nginx_verify_pgp <tarball> <asc>：签名有效且签名者主指纹在固定列表内才返回 0
nginx_verify_pgp() {
  local tgz="$1" asc="$2" gh k fpr ok=1
  command -v gpg >/dev/null 2>&1 || { warn "未安装 gpg，无法校验 nginx 签名"; return 1; }
  gh=$(mktemp -d) && chmod 700 "$gh"
  for k in $NGINX_PGP_KEYS; do
    curl -fsSL --max-time 20 "https://nginx.org/keys/${k}.key" 2>/dev/null | GNUPGHOME="$gh" gpg -q --batch --import 2>/dev/null
  done
  # VALIDSIG 行最后一个字段是签名密钥的主指纹
  fpr=$(GNUPGHOME="$gh" gpg --batch --status-fd 1 --verify "$asc" "$tgz" 2>/dev/null | awk '$2=="VALIDSIG"{print $NF}')
  rm -rf "$gh"
  if [[ -n "$fpr" ]] && [[ " $NGINX_PGP_FPRS " == *" $fpr "* ]]; then
    info "nginx 源码 PGP 签名校验通过（签名者主指纹 ${fpr}）"; ok=0
  else
    warn "nginx 源码 PGP 签名校验失败（签名者：${fpr:-无有效签名}），拒绝使用"
  fi
  return $ok
}

# nginx 只接受 HTTP/2（请求层）：开 = 在两个真实 server 块里写入 xh-h2only 标记块，关 = 整块删除。
# nginx 的 ALPN 握手里始终会列出 http/1.1，没有指令可以去掉；这里是对 HTTP/1.x 请求直接 return 444。
# 例外：/sub/ 订阅页与 /.well-known/（部分订阅客户端只会 HTTP/1.1）。
# 注意：经 Cloudflare 回源时 CF 对普通页面可能用 HTTP/1.1，打开 h2only 后用浏览器访问 CDN 域名首页会看到 CF 的 52x 错误页；
# xhttp / gRPC 流量本来就是 HTTP/2，不受影响。
nginx_h2only() {
  local act="${1:-show}" conf="/etc/nginx/nginx.conf" cur=off tmp bak
  [[ -f "$conf" ]] || fail "未找到 ${conf}"
  grep -q '# >>xh-h2only' "$conf" && cur=on
  case "$act" in
    show|status)
      echo -e "${CYAN}=== nginx 只接受 HTTP/2 ===${NC}"
      [[ "$cur" == on ]] && echo -e "  当前状态:  ${GREEN}已开启${NC}（HTTP/1.x 请求被断开，/sub/ 例外）" || echo -e "  当前状态:  ${YELLOW}未开启${NC}"
      echo -e "  ${MANAGE_CMD} nginx h2only on|off"
      return 0 ;;
    on|off) ;;
    *) echo "用法: ${MANAGE_CMD} nginx h2only [show|on|off]"; return 1 ;;
  esac
  [[ "$cur" == "$act" ]] && { info "nginx h2only 本来就是 ${act}"; return 0; }
  tmp="${conf}.h2only-tmp"; bak="${conf}.h2only.bak"
  python3 - "$conf" "$tmp" "$act" <<'H2PY' || { rm -f "$tmp"; fail "改写 nginx 配置失败，未做任何修改"; }
import re, sys
src, dst, act = sys.argv[1:4]
s = open(src, encoding='utf-8').read()
BLOCK = (
    '        # >>xh-h2only\n'
    '        # 只接受 HTTP/2：HTTP/1.x 请求直接断开。/sub/ 与 /.well-known/ 例外。xh nginx h2only off 可关闭。\n'
    '        set $h2only 1;\n'
    '        if ($server_protocol = "HTTP/2.0") { set $h2only 0; }\n'
    '        if ($uri ~ "^/(sub|\\.well-known)/") { set $h2only 0; }\n'
    '        if ($h2only) { return 444; }\n'
    '        # <<xh-h2only\n')
if act == 'off':
    s, n = re.subn(r'[ \t]*# >>xh-h2only\n.*?# <<xh-h2only\n', '', s, flags=re.S)
else:
    line = '        http2        on;\n'
    if s.count(line) < 1:
        sys.stderr.write('没找到 http2 on 行（配置不是由本脚本生成？）\n'); sys.exit(1)
    s = s.replace(line, line + BLOCK)
open(dst, 'w', encoding='utf-8').write(s)
H2PY
  if ! nginx -t -c "$tmp" >/dev/null 2>&1; then
    nginx -t -c "$tmp" 2>&1 | tail -3; rm -f "$tmp"; fail "nginx 配置校验失败，已放弃，未做任何修改"
  fi
  cp -a "$conf" "$bak"
  chown --reference="$conf" "$tmp" 2>/dev/null || true; chmod --reference="$conf" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$conf"
  if nginx -t >/dev/null 2>&1 && nginx -s reload 2>/dev/null; then
    info "nginx h2only 已$([[ "$act" == on ]] && echo 开启 || echo 关闭)（nginx 已重载，Xray 没有重启，客户端不需要重连）"
  else
    cp -a "$bak" "$conf"; nginx -s reload 2>/dev/null || true
    fail "nginx 重载失败，已回滚到修改前的配置"
  fi
}

cmd_nginx() {
  local action="${1:-show}" a
  local bin cur latest
  bin=$(command -v nginx) || fail "未找到 nginx"
  cur=$("$bin" -v 2>&1 | sed -n 's|.*nginx/||p')
  case "$action" in
    h2only) shift; nginx_h2only "$@"; return $? ;;
    show|status)
      latest=$(nginx_latest_mainline)
      echo "nginx 当前: ${cur}   mainline 最新: ${latest:-查询失败}"
      "$bin" -V 2>&1 | grep -E 'built with|running with'
      ;;
    check)
      # 每周任务调用：只检查、写提醒
      latest=$(nginx_latest_mainline)
      [[ -n "$latest" ]] || { warn "查询 nginx 最新版本失败"; return 0; }
      if [[ "$(printf '%s\n%s\n' "$latest" "$cur" | sort -V | tail -1)" != "$cur" ]]; then
        update_notice nginx "${cur} → ${latest}（手动更新：${MANAGE_CMD} nginx update）"
        info "nginx 有新版本：${cur} → ${latest}"
      else
        update_notice nginx ""
        info "nginx 已是最新 mainline：${cur}"
      fi
      ;;
    update|up)
      latest=$(nginx_latest_mainline)
      [[ -n "$latest" ]] || { warn "无法从 nginx.org 获取最新版本"; return 1; }
      if [[ "$(printf '%s\n%s\n' "$latest" "$cur" | sort -V | tail -1)" == "$cur" ]]; then
        info "nginx 已是最新 mainline：${cur}"; update_notice nginx ""; return 0
      fi
      info "nginx ${cur} → ${latest}"
      if [[ " $* " != *" -y "* ]]; then
        read -rp "下载并校验签名、按原编译参数重新编译并替换 nginx（约需数分钟，替换时重启 nginx）？[y/N] " a
        [[ "${a,,}" == "y" ]] || { info "已取消"; return 0; }
      fi
      local args tmp src log="/var/log/xh-nginx-build.log"
      args=$("$bin" -V 2>&1 | sed -n 's/^configure arguments: //p')
      [[ -n "$args" ]] || { warn "读取不到原编译参数"; return 1; }
      nginx_build_deps
      tmp=$(mktemp -d) || return 1
      if ! curl -fsSL --max-time 120 "https://nginx.org/download/nginx-${latest}.tar.gz" -o "$tmp/n.tgz" \
         || ! curl -fsSL --max-time 20 "https://nginx.org/download/nginx-${latest}.tar.gz.asc" -o "$tmp/n.asc"; then
        warn "下载 nginx ${latest} 源码或签名失败"; rm -rf "$tmp"; return 1
      fi
      nginx_verify_pgp "$tmp/n.tgz" "$tmp/n.asc" || { rm -rf "$tmp"; return 1; }
      tar -xzf "$tmp/n.tgz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
      src="$tmp/nginx-${latest}"
      info "编译中（日志 ${log}）..."
      # 参数来自本机二进制自身的 nginx -V，含 --with-cc-opt 等，需 eval 还原
      if ! ( cd "$src" && eval "./configure $args" && make -j"$(nproc 2>/dev/null || echo 1)" ) >"$log" 2>&1; then
        warn "nginx ${latest} 编译失败，保留 ${cur}（详见 ${log}）"; rm -rf "$tmp"; return 1
      fi
      if ! "$src/objs/nginx" -t -q >>"$log" 2>&1; then
        warn "新二进制测试现有配置失败，保留 ${cur}（详见 ${log}）"; rm -rf "$tmp"; return 1
      fi
      local bak="${bin}.bak-${cur}"
      cp -a "$bin" "$bak" || { rm -rf "$tmp"; fail "备份旧 nginx 失败"; }
      install -m 755 "$src/objs/nginx" "${bin}.new" && mv -f "${bin}.new" "$bin"
      rm -rf "$tmp"
      if svc restart nginx >/dev/null 2>&1 && sleep 1 && "$bin" -v 2>&1 | grep -q "nginx/${latest}" \
         && ss -lnt 2>/dev/null | grep -q ':8003 '; then
        local o; for o in "${bin}".bak-*; do [[ "$o" == "$bak" ]] || rm -f "$o"; done
        update_notice nginx ""
        info "nginx 已更新：${cur} → ${latest}（旧二进制备份 ${bak}）"
      else
        warn "新 nginx 启动或端口复核失败，回滚到 ${cur}"
        cp -a "$bak" "$bin"; svc restart nginx || true
        return 1
      fi
      ;;
    *) echo "用法: ${MANAGE_CMD} nginx [show|check|update [-y]]" ;;
  esac
}
cmd_uninstall() {
  echo -e "${RED}[!] 将删除 Xray / Nginx / ACME / Hysteria2 及本项目的配置、证书、订阅文件${NC}"
  read -rp "确认卸载？输入 yes 继续: " reply
  [[ "$reply" == "yes" ]] || { info "已取消"; return 0; }

  # 停服务后**必须复核进程真的死了**再删文件。
  # 原先是 `systemctl stop ... || true` 一笔带过：stop 失败被吞掉，随后单元文件与
  # /usr/local/bin/xray 照删不误，留下「进程还活着、unit 和二进制都没了」的中间态
  # （Linux 上删掉正在运行的二进制，进程照常从内存继续跑）。
  # 下次装官方 Xray-install 时，它检测到 pidof xray 非空就去 systemctl stop xray.service，
  # 而单元已被删 → "Unit xray.service not loaded" → 脚本 exit 1，安装直接卡死。
  # 这个中间态用户自己看不出问题在哪，只能看到官方脚本报错。
  ensure_stopped() {  # ensure_stopped 进程名... —— 温和停不掉就强杀，并等它真的消失
    local p
    for p in "$@"; do
      pgrep -x "$p" >/dev/null 2>&1 || continue
      warn "${p} 在停止服务后仍在运行，强制结束"
      pkill -x "$p" >/dev/null 2>&1 || true
      sleep 1
      pgrep -x "$p" >/dev/null 2>&1 && { pkill -9 -x "$p" >/dev/null 2>&1 || true; sleep 1; }
      pgrep -x "$p" >/dev/null 2>&1 && warn "${p} 仍无法结束，请手动检查 pgrep -a ${p}"
    done
  }

  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    for s in xray nginx hysteria-server; do
      rc-service "$s" stop >/dev/null 2>&1 || true
      rc-update del "$s" default >/dev/null 2>&1 || true
      rm -f "/etc/init.d/$s"
    done
    ensure_stopped xray nginx hysteria
  else
    systemctl stop xray nginx hysteria-server >/dev/null 2>&1 || true
    systemctl disable xray nginx hysteria-server >/dev/null 2>&1 || true
    ensure_stopped xray nginx hysteria
    rm -f /etc/systemd/system/xray.service \
          /etc/systemd/system/xray@.service \
          /etc/systemd/system/nginx.service \
          /etc/systemd/system/hysteria-server.service
    rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d \
           /etc/systemd/system/nginx.service.d
  fi

  rm -f  /usr/local/bin/xray /usr/local/bin/xray.bak-*
  rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray
  rm -f  /usr/sbin/nginx
  rm -rf /usr/local/nginx /etc/nginx /var/log/nginx
  rm -f  /usr/local/bin/hysteria
  rm -rf /etc/hysteria
  rm -f  /var/log/hysteria-server.log

  crontab -l 2>/dev/null | grep -v ".acme.sh" | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
  rm -f  /usr/local/bin/acme.sh
  rm -rf /root/.acme.sh
  rm -f  /etc/ssl/private/private.key /etc/ssl/private/fullchain.cer

  rm -f "$SYSCTL_CONF" "$LIMITS_CONF"
  rm -f /etc/profile.d/xh-updates.sh
  remove_nic_tune
  sysctl --system >/dev/null 2>&1 || true

  local home="${USER_HOME:-/root}"
  rm -f "${home}"/client-config.txt "${home}"/client-config-mihomo-*.yaml \
        "${home}"/client-config-v2rayn-tun.txt \
        "${home}"/subscription-links.txt "${home}"/subscription-*.png
  rm -f /root/client-config.txt /root/client-config-mihomo-*.yaml \
        /root/client-config-v2rayn-tun.txt \
        /root/subscription-links.txt /root/subscription-*.png
  rm -rf "$STATE_DIR"

  if [[ "$SERVICE_TYPE" == "systemd" ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    # 不 reset-failed 的话，被删掉的 unit 会以 not-found/failed 状态挂在 systemctl 里，
    # 干扰下次安装时的状态判断
    systemctl reset-failed >/dev/null 2>&1 || true
  fi
  # 收尾自检：卸载后仍有残留进程是下次安装失败的主要来源，这里必须说出来
  for p in xray nginx hysteria; do
    pgrep -x "$p" >/dev/null 2>&1 && warn "注意：仍检测到 ${p} 进程，请手动确认: pgrep -a ${p}"
  done
  info "卸载完成（保留了 ${home}/dist 下你自己上传的回落页面）"
  rm -f /usr/local/bin/xh
}

# ==================================================
# 可选节点开关：h2direct / hy2obfs / split（上下行分离两条）；各自的默认开关状态见 01-env.sh
# ==================================================
# 备用节点库 /etc/xhttp-cdn/all/ 由安装脚本在「全部备用节点开启」的参数下渲染一遍得到
# （见 11-client-config.sh、09-server-config.sh）。开关只从库里取节点行 / Mihomo 条目 /
# 服务端入站文本，不在这里重新拼装，所以和全新安装逐字一致。
# 限制：库是安装时的快照。装好后用 xh ech 改过的 ECH 设置不会同步进库；节点被 NODE_NAME_MAP
# 改过名时，按默认名匹配会找不到，开关会明确报错而不是静默跳过。
ALL_STORE_DIR="/etc/xhttp-cdn/all"
