# ==================================================
# 网络流控、诊断、性能审计与节点测速
# ==================================================
cmd_conflict() {
  local ours="99-xray-xhttp.conf" d=/etc/sysctl.d
  echo -e "${CYAN}[+] sysctl 配置冲突检测${NC}"
  [[ -f "$SYSCTL_CONF" ]] || { info "本项目未写入 sysctl（系统层调优关闭），无冲突可言"; echo ""; return 0; }

  local ourkeys conflict=0
  ourkeys=$(sed 's/#.*//; s/=.*//; s/[[:space:]]//g' "$SYSCTL_CONF" | grep -E '^[a-z]' | sort -u)

  for f in "$d"/*.conf; do
    [[ -f "$f" ]] || continue
    local base; base=$(basename "$f")
    [[ "$base" == "$ours" ]] && continue
    local dup; dup=$(sed 's/#.*//; s/=.*//; s/[[:space:]]//g' "$f" | grep -E '^[a-z]' | sort -u |
                     comm -12 - <(echo "$ourkeys") 2>/dev/null)
    [[ -z "$dup" ]] && continue
    conflict=1
    if [[ "$base" > "$ours" ]]; then
      echo -e "  ${RED}[!!]${NC} $base 排在本项目之后，会**覆盖**以下参数："
    else
      echo -e "  ${YELLOW}[--]${NC} $base 与本项目重叠，但排序在前，被本项目覆盖（当前无害）："
    fi
    echo "$dup" | sed 's/^/         /'
  done
  [[ "$conflict" -eq 0 ]] && echo -e "  ${GREEN}[OK]${NC}   未发现与其它 sysctl 文件的参数重叠"

  # 不会被加载的残留（systemd-sysctl 只读 *.conf）
  local junk; junk=$(ls "$d" 2>/dev/null | grep -vE '\.conf$|^README' || true)
  if [[ -n "$junk" ]]; then
    echo ""
    echo -e "  ${YELLOW}[--]${NC} 以下文件不以 .conf 结尾，systemd-sysctl 不会加载（仅占位，可自行清理）："
    echo "$junk" | sed 's/^/         /'
    echo "         清理: mkdir -p /root/sysctl-backup && mv /etc/sysctl.d/*.disabled.* /etc/sysctl.d/*.bak /root/sysctl-backup/"
  fi

  echo ""
  echo -e "  ${CYAN}实际生效值（以内核为准，与文件内容无关）${NC}"
  for k in net.core.somaxconn net.core.netdev_max_backlog net.ipv4.tcp_max_syn_backlog \
           net.core.rmem_max net.ipv4.tcp_congestion_control net.core.default_qdisc; do
    printf '    %-36s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo n/a)"
  done
  echo ""
}

# UDP / HTTP3 节点连不上时的自检。
#
# v4.0.0 起本项目有三类 UDP 节点，排查路径互不相同：
#   1. Vless-xhttp-tls-cdn —— 经 CDN。**不经过本机任何 QUIC 配置**：
#      Cloudflare 边缘用 HTTP/3 面对客户端，回源到本机仍是 TCP。
#      它不通 = 常规 XHTTP 链路的问题，与本机 UDP 无关。
#   2. Vless-xhttp-h3-direct / Hysteria2-obfs —— 由 **Xray 自己 bind UDP**，
#      既不经 nginx 也没有独立 hysteria 二进制。查的是 xray 进程的监听。
#   3. add-quic-h3 扩展的节点 —— 由 nginx listen quic 提供（下方单独检查）。
# 判据：1 通而 2 全不通 → 云厂商安全组没放行 UDP，或内核 <26.3.27。
# UDP 端口劫持自检。
# 背景：Hysteria2 端口跳跃靠 nat 表里的「端口段」规则（DNAT/REDIRECT）实现。
# 这类规则按端口范围匹配，会把落在范围内的**任何**本机 UDP 服务端口一并改写。
# 真实事故：同机另一套脚本的 Hysteria2 基础端口 44116 落在本项目建议的跳跃段
# 40000-50000 内，于是所有直连 44116 的包被 REDIRECT 到 8443（本项目的实例），
# 因两边 obfs 密码不同而被静默丢弃——现象是「节点链接里的基础端口连不上，
# 只有跳跃段能连」，且被劫持方服务端日志里**没有任何记录**，极难排查。
cmd_portconflict() {
  echo -e "${CYAN}[+] UDP 端口段劫持检测${NC}"
  command -v iptables >/dev/null 2>&1 || { info "未安装 iptables，跳过"; echo ""; return 0; }

  local ranges listen found=0
  ranges=$(iptables -t nat -S PREROUTING 2>/dev/null | grep -E '\-\-dport [0-9]+:[0-9]+')
  [[ -z "$ranges" ]] && { info "未发现端口段规则，无劫持风险"; echo ""; return 0; }

  # 只统计「真实服务端口」，排除代理进程的临时出站 UDP socket（它们同样
  # 绑在通配地址上，直接取 ss 输出会大量误报）。判据：服务端口在 INPUT 链里
  # 有一条显式的单端口 ACCEPT 规则，临时出站 socket 没有。
  local svc_ports
  svc_ports=$(iptables -S INPUT 2>/dev/null \
              | grep -E '\-p udp .*--dport [0-9]+ -j ACCEPT' \
              | grep -oE '\-\-dport [0-9]+' | awk '{print $2}' | sort -un)
  listen=$(ss -uln 2>/dev/null | tail -n +2 | awk '{print $4}' \
           | sed 's/.*://' | grep -E '^[0-9]+$' | sort -un)
  # 取交集：既在监听、又被防火墙显式放行的端口
  # （用 grep -Fx 而非 comm：comm 要求字典序，这里两侧都是数值序）
  listen=$(echo "$listen" | grep -Fx -f <(echo "$svc_ports") 2>/dev/null)

  while read -r line; do
    local rng lo hi tgt
    rng=$(echo "$line" | grep -oE '\-\-dport [0-9]+:[0-9]+' | awk '{print $2}')
    tgt=$(echo "$line" | grep -oE '(to-destination :|--to-ports )[0-9]+' | grep -oE '[0-9]+$')
    lo=${rng%%:*}; hi=${rng##*:}
    for p in $listen; do
      # 已插入 RETURN 例外的端口视为已修复，不再报警
      if iptables -t nat -C PREROUTING -p udp --dport "$p" -j RETURN 2>/dev/null; then
        continue
      fi
      if [[ "$p" -ge "$lo" && "$p" -le "$hi" && "$p" != "$tgt" ]]; then
        echo -e "  ${RED}[!!]${NC}   UDP $p 落在端口段 ${lo}-${hi} 内（该段被导向 $tgt）"
        echo -e "         直连 $p 的流量会被改写投递到 $tgt，两端密钥不同则静默丢弃。"
        echo -e "         修复：${YELLOW}iptables -t nat -I PREROUTING 1 -p udp --dport $p -j RETURN${NC}"
        found=1
      fi
    done
  done <<< "$ranges"

  [[ "$found" -eq 0 ]] && echo -e "  ${GREEN}[OK]${NC}   无端口被跳跃段劫持"
  echo ""
}
cmd_diag() {
  cmd_conflict
  cmd_portconflict
  local ok=0 bad=0
  chk() { # chk 描述 结果(0/1) 补充说明
    if [[ "$2" -eq 0 ]]; then echo -e "  ${GREEN}[OK]${NC}   $1${3:+ — $3}"; ok=$((ok+1))
    else echo -e "  ${RED}[!!]${NC}   $1${3:+ — $3}"; bad=$((bad+1)); fi
  }

  echo -e "${CYAN}[+] 服务端侧自检${NC}"

  if nginx -t >/dev/null 2>&1; then
    chk "nginx -t 配置有效" 0
  else
    chk "nginx -t 失败" 1 "执行 nginx -t 看具体报错"
  fi

  if svc_active nginx; then chk "nginx 运行中" 0; else chk "nginx 未运行" 1 "${MANAGE_CMD} restart"; fi
  if svc_active xray;  then chk "xray 运行中"  0; else chk "xray 未运行"  1 "${MANAGE_CMD} restart"; fi

  # 全部 CDN 流量经 Xray:443 fallback 落到 nginx:8003，再 grpc_pass 到 127.0.0.1:8001
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -qE ':443\b'  && chk "已监听 TCP 443"  0 || chk "未监听 TCP 443"  1 "Xray 未启动？"
    ss -lntp 2>/dev/null | grep -qE ':8003\b' && chk "已监听 TCP 8003" 0 || chk "未监听 TCP 8003" 1 "nginx 未启动？"
  else
    warn "未安装 ss，跳过端口监听检查"
  fi

  # location 的 gRPC 超时：缺失会让 XHTTP 长连接每 60 秒被 nginx 切断
  if grep -q 'grpc_read_timeout' /etc/nginx/nginx.conf 2>/dev/null; then
    chk "nginx location 已放大 grpc 读写超时" 0
  else
    chk "nginx location 缺少 grpc_read_timeout" 1 "XHTTP 长连接会每 60 秒断一次；重跑安装脚本"
  fi

  # ---------- 直连 UDP / QUIC（add-quic-h3 与 Hysteria2 扩展）----------
  # 走 CDN 的节点不碰这些；只有**直连 VPS 裸 IP 的 UDP** 节点依赖它们。
  # 三条 h3 节点同时不通、而经 CDN 的 h3 节点正常时，唯一共同点就是这一层。
  QUIC_PORTS=""
  if grep -q '# BEGIN quic-h3' /etc/nginx/nginx.conf 2>/dev/null; then
    QUIC_PORTS=$(grep -A2 '# BEGIN quic-h3' /etc/nginx/nginx.conf | grep -oE 'listen [0-9]+ quic' | grep -oE '[0-9]+')
    chk "nginx 已配置 quic-h3 段（UDP ${QUIC_PORTS:-?}）" 0
  fi
  if grep -q '# BEGIN quic xhttp' /etc/nginx/nginx.conf 2>/dev/null; then
    QUIC_PORTS="${QUIC_PORTS} $(grep -A2 '# BEGIN quic xhttp' /etc/nginx/nginx.conf | grep -oE 'listen [0-9]+ quic' | grep -oE '[0-9]+')"
    chk "nginx 已配置 quic xhttp 段" 0
  fi

  if [[ -n "${QUIC_PORTS// /}" ]] && command -v ss >/dev/null 2>&1; then
    for p in $QUIC_PORTS; do
      # 配置里写了 listen quic，但进程没真的 bind UDP —— nginx -t 查不出这种情况（L14）
      if ss -lnup 2>/dev/null | grep -qE ":${p}\b"; then
        chk "已监听 UDP ${p}" 0
      else
        chk "未监听 UDP ${p}" 1 "配置里有 listen ${p} quic 但进程未 bind；查 ${MANAGE_CMD} log nginx"
      fi
    done
  fi

  # ---------- v4.0.0 的两条直连 UDP 节点（由 Xray 自己监听）----------
  # 与上面 nginx quic 段的区别：h3-direct 与 Hysteria2 都是 Xray 直接 bind UDP，
  # 既不经 nginx 也没有独立的 hysteria 二进制，所以要查的是 xray 进程的监听。
  if command -v ss >/dev/null 2>&1; then
    if [[ "${FEATURE_H3_DIRECT:-false}" == true ]]; then
      if ss -lnup 2>/dev/null | grep -qE ":${H3_PORT:-443}\b"; then
        chk "h3-direct 已监听 UDP ${H3_PORT:-443}" 0
      else
        chk "h3-direct 未监听 UDP ${H3_PORT:-443}" 1 "config.json 里有该 inbound 但未 bind；查 ${MANAGE_CMD} log xray"
      fi
    fi
    # h2-direct 是 TCP，查 -lnt
    if [[ "${FEATURE_H2_DIRECT:-false}" == true ]]; then
      if ss -lnt 2>/dev/null | grep -qE ":${H2_PORT:-8445}\b"; then
        chk "h2-direct 已监听 TCP ${H2_PORT:-8445}" 0
      else
        chk "h2-direct 未监听 TCP ${H2_PORT:-8445}" 1 "config.json 里有该 inbound 但未 bind；查 ${MANAGE_CMD} log xray"
      fi
    fi
    if [[ "${FEATURE_HY2:-false}" == true && "${FEATURE_HY2_H3:-false}" == true ]]; then
      if ss -lnup 2>/dev/null | grep -qE ":${HY2_H3_PORT}\b"; then
        chk "Hysteria2-H3 已监听 UDP ${HY2_H3_PORT}" 0
      else
        chk "Hysteria2-H3 未监听 UDP ${HY2_H3_PORT}" 1 "查 ${MANAGE_CMD} log xray；确认 UDP ${HY2_H3_PORT} 未被其他进程占用"
      fi
    fi
    if [[ "${FEATURE_HY2:-false}" == true && "${FEATURE_HY2_OBFS:-false}" == true ]]; then
      if ss -lnup 2>/dev/null | grep -qE ":${HY2_PORT}\b"; then
        chk "Hysteria2 已监听 UDP ${HY2_PORT}" 0
      else
        chk "Hysteria2 未监听 UDP ${HY2_PORT}" 1 "查 ${MANAGE_CMD} log xray；确认内核 ≥26.3.27"
      fi
    fi
    if [[ "${FEATURE_MASQUE:-false}" == true ]]; then
      if ss -lnup 2>/dev/null | grep -qE ":${MASQUE_PORT:-8447}\b"; then
        chk "MASQUE 已监听 UDP ${MASQUE_PORT:-8447}" 0
      else
        chk "MASQUE 未监听 UDP ${MASQUE_PORT:-8447}" 1 "查 ${MANAGE_CMD} log xray"
      fi
    fi
    if [[ "${FEATURE_XDRIVE:-false}" == true ]]; then
      chk "XDRIVE 网盘代理 (Google Drive) 已激活" 0
    fi
  fi

  # 内核版本闸门：低于 26.3.27 时缺少原生 Hysteria 2 inbound。
  if [[ "${FEATURE_HY2:-false}" == true || "${FEATURE_H3_DIRECT:-false}" == true ]]; then
    XV=$([[ -x "$XRAY_BIN" ]] && "$XRAY_BIN" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$XV" ]]; then
      if [[ "$(printf '%s\n26.3.27\n' "$XV" | sort -V | head -n1)" == "26.3.27" ]]; then
        chk "Xray ${XV} ≥ 26.3.27（Hysteria2、XHTTP 与 v26.9.30+ 特性可用）" 0
      else
        chk "Xray ${XV} < 26.3.27" 1 "当前内核版本低于 26.3.27，缺少 Hysteria 2 原生支持，执行 ${MANAGE_CMD} update"
      fi
    fi
  fi

  # 证书自动续期链路自检。
  #
  # 本项目的 xray 8443（h3-direct）、独立 hysteria 8446、nginx 8003 三者都直接读
  # /etc/ssl/private/ 下的证书副本，而不是 acme.sh 自己的目录。这份副本靠安装时
  # 配置的 `acme.sh --install-cert --key-file/--fullchain-file` 在每次续期后自动
  # 更新——那几个路径记在域名配置的 Le_RealKeyPath / Le_RealFullChainPath 里。
  #
  # 真实事故：同机另一套脚本执行 `--install-cert` 时只传了 --reloadcmd，acme.sh
  # 会连带重写整组部署配置、把这几个路径清空。之后续期照常成功、reloadcmd 照常
  # 重启服务，但服务重新加载的还是那份从未更新过的旧文件——直到旧证书到期当天，
  # h3-direct / hy2 / 全部 CDN 节点同时失效。续期成功、重启成功、日志无异常，
  # 问题要到一个月后才发作，因此必须靠自检提前拦下。
  if [[ -n "${REALITY_DOMAIN:-}" ]] && [[ -d "$HOME/.acme.sh" ]]; then
    local _ac=""
    for _d in "$HOME/.acme.sh/${REALITY_DOMAIN}_ecc" "$HOME/.acme.sh/${REALITY_DOMAIN}"; do
      [[ -f "$_d/${REALITY_DOMAIN}.conf" ]] && _ac="$_d/${REALITY_DOMAIN}.conf" && break
    done
    if [[ -n "$_ac" ]]; then
      local _fc _kf _rc
      _fc=$(. "$_ac" 2>/dev/null; printf '%s' "${Le_RealFullChainPath:-}")
      _kf=$(. "$_ac" 2>/dev/null; printf '%s' "${Le_RealKeyPath:-}")
      _rc=$(. "$_ac" 2>/dev/null; printf '%s' "${Le_ReloadCmd:-}")
      case "$_rc" in
        *__ACME_BASE64__START_*)
          _rc=$(printf '%s' "$_rc" | sed -e 's/^__ACME_BASE64__START_//' -e 's/__ACME_BASE64__END_$//' | base64 -d 2>/dev/null) ;;
      esac

      if [[ -z "$_fc" || -z "$_kf" ]]; then
        chk "acme 未配置证书落地路径（Le_RealFullChainPath/Le_RealKeyPath 为空）" 1 \
          "续期后 /etc/ssl/private/ 不会更新，旧证书到期时 h3-direct/hy2/CDN 节点会同时失效。修复: acme.sh --install-cert -d ${REALITY_DOMAIN} --ecc --key-file /etc/ssl/private/private.key --fullchain-file /etc/ssl/private/fullchain.cer --reloadcmd '<原有 reloadcmd>'"
      elif [[ "$_fc" != "/etc/ssl/private/fullchain.cer" ]]; then
        chk "acme 落地路径与本项目使用的不一致（$_fc）" 1 \
          "本项目各服务读的是 /etc/ssl/private/fullchain.cer"
      else
        chk "acme 证书落地路径已配置（$_fc）" 0
      fi

      # 已部署副本与 acme 源的指纹是否一致——不一致说明续期后没落地
      local _src="${_ac%/*}/fullchain.cer"
      if [[ -f "$_src" && -f /etc/ssl/private/fullchain.cer ]]; then
        local _f1 _f2
        _f1=$(openssl x509 -in "$_src" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        _f2=$(openssl x509 -in /etc/ssl/private/fullchain.cer -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        if [[ -n "$_f1" && "$_f1" == "$_f2" ]]; then
          chk "已部署证书与 acme 源一致" 0
        else
          chk "已部署证书与 acme 源不一致（续期后未落地）" 1 \
            "执行 acme.sh --install-cert 重新落地，或手工复制后重启 nginx/xray"
        fi
      fi

      # v4.9.45：续期方式与 CDN 代理状态是否冲突。
      # CDN 域名开了 Cloudflare 代理后，standalone（HTTP-01）续期会被 CF 301 到 https
      # 再回源 443（Reality / 伪装站），60 天后续期必败，而平时一切正常、日志无异常。
      local _wr; _wr=$(. "$_ac" 2>/dev/null; printf '%s' "${Le_Webroot:-}")
      case "$_wr" in
        dns_*) chk "acme 续期方式: DNS-01（${_wr}），与 CDN 代理状态无关" 0 ;;
        *)
          if cdn_behind_proxy; then
            chk "acme 续期方式为 standalone，但 ${CDN_DOMAIN} 已走 CDN 代理，自动续期会失败" 1 \
              "执行 CF_Token=<Cloudflare API Token> ${MANAGE_CMD} cert dnscf 切换为 DNS-01"
          else
            chk "acme 续期方式: standalone（${CDN_DOMAIN:-CDN 域名} 当前直连本机，可用）" 0
          fi
          ;;
      esac

      # reloadcmd 是否覆盖了所有读这份证书的服务
      if [[ -z "$_rc" ]]; then
        chk "acme reloadcmd 为空" 1 "续期后没有任何服务会重新加载新证书"
      else
        local _miss=""
        [[ "$_rc" == *nginx* ]] || _miss="$_miss nginx"
        [[ "$_rc" == *xray* ]]  || _miss="$_miss xray"
        # 仅当本机确实跑着独立 hysteria 时才要求它出现在 reloadcmd 里
        if systemctl is-active --quiet hysteria-server 2>/dev/null; then
          [[ "$_rc" == *hysteria-server* ]] || _miss="$_miss hysteria-server"
        fi
        if [[ -n "$_miss" ]]; then
          chk "acme reloadcmd 未覆盖:${_miss}" 1 \
            "这些服务读 /etc/ssl/private/ 的证书，续期后不重启会继续用旧证书"
        else
          chk "acme reloadcmd 覆盖了全部读证书的服务" 0
        fi
      fi
    fi
  fi

  # 独立 hysteria 二进制的处置判断。
  #
  # v4.0.0 起本项目的 Hysteria2 可由 Xray 原生 inbound（"protocol": "hysteria"）提供，
  # 此时独立二进制是冗余的、且可能与之抢同一个 UDP 端口。
  #
  # 但**不能一看到 /etc/hysteria/config.yaml 就报错并建议停用**：
  # 当 xray 配置里并没有原生 hy2 inbound 时（例如安装时未取得 acme 证书而自动
  # 跳过了该 inbound，或用户有意用官方二进制），这个独立进程就是该 Hysteria2
  # 节点的**唯一提供者**——按旧提示执行 `systemctl disable --now hysteria-server`
  # 会直接打掉一条正在用的节点。所以先看 xray 到底提不提供，再决定怎么报。
  if [[ -f /etc/hysteria/config.yaml ]]; then
    local hy_std_port hy_xray_port
    hy_std_port=$(grep -oE '^listen:[[:space:]]*:?[0-9]+' /etc/hysteria/config.yaml 2>/dev/null \
                  | grep -oE '[0-9]+$' | head -1)
    # 取 xray 原生 hysteria inbound 的端口：从含 "protocol": "hysteria" 的那段
    # 往回找最近的 "port"（inbound 里 port 在 protocol 之前）
    hy_xray_port=""
    if grep -q '"protocol"[[:space:]]*:[[:space:]]*"hysteria"' "$XRAY_CONF" 2>/dev/null; then
      hy_xray_port=$(grep -B5 '"protocol"[[:space:]]*:[[:space:]]*"hysteria"' "$XRAY_CONF" \
                     | grep -oE '"port"[[:space:]]*:[[:space:]]*[0-9]+' | tail -1 \
                     | grep -oE '[0-9]+$')
    fi

    if [[ -z "$hy_xray_port" ]]; then
      # xray 不提供原生 hy2 —— 独立二进制是该节点的唯一提供者，保留它是正确的
      chk "Hysteria2 由独立 hysteria 二进制提供（UDP ${hy_std_port:-?}）" 0 \
        "xray 配置中无原生 hysteria inbound，请勿停用 hysteria-server，否则该节点会立即失效"
    elif [[ -n "$hy_std_port" && "$hy_std_port" == "$hy_xray_port" ]]; then
      # 真冲突：两者抢同一个端口
      chk "独立 hysteria 与 Xray 原生 hy2 抢占同一端口 UDP ${hy_std_port}" 1 \
        "二选一；用 Xray 原生请执行: systemctl disable --now hysteria-server"
    else
      # 两者都在但端口不同：冗余而非故障
      chk "独立 hysteria（UDP ${hy_std_port:-?}）与 Xray 原生 hy2（UDP ${hy_xray_port}）并存" 0 \
        "端口不冲突；如无需两套，可停用其一"
    fi
  fi

  # 本机防火墙：只报告，不改动（规则可能是用户或云厂商 agent 写的）
  # 判据是「input 链是否默认拒绝」，不是「有没有 UDP 规则」：
  # 默认放行时没有 UDP 规则完全正常，旧写法在只装了 fail2ban / mangle 表
  # （policy accept）的机器上必然误报，把人往云安全组的方向带偏。
  if command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q .; then
    if nft list ruleset 2>/dev/null | grep -qE 'hook input .*policy drop'; then
      nft list ruleset 2>/dev/null | grep -qiE 'udp.*(accept|dport)' \
        && chk "nftables input 默认拒绝，但有 UDP 放行规则" 0 \
        || chk "nftables input 链 policy drop 且未放行 UDP" 1 "直连 UDP 节点会被本机防火墙挡下"
    else
      chk "nftables input 链默认放行（不拦 UDP）" 0
    fi
  elif command -v iptables >/dev/null 2>&1; then
    if iptables -S 2>/dev/null | grep -qE '^-P INPUT (DROP|REJECT)'; then
      iptables -S 2>/dev/null | grep -qi 'udp' \
        && chk "iptables INPUT 默认拒绝，但有 UDP 放行规则" 0 \
        || chk "iptables INPUT 链 policy DROP 且未放行 UDP" 1 "直连 UDP 节点会被本机防火墙挡下"
    else
      chk "iptables INPUT 链默认放行（不拦 UDP）" 0
    fi
  fi

  echo ""
  echo -e "${CYAN}[+] 结论与下一步${NC}"
  if [[ $bad -eq 0 ]]; then
    echo "  服务端侧未发现问题（$ok 项通过）。"
  else
    echo "  发现 $bad 项异常，先按上面的提示处理。"
  fi
  echo ""
  echo -e "${YELLOW}  ⚠ 直连 UDP 节点全不通、而经 CDN 的节点正常时，先查云厂商安全组${NC}"
  echo "  这一项**在机器里查不出来**——安全组在虚拟机外面，本机 ss 显示监听正常、"
  echo "  防火墙也放行，包仍可能在到达网卡之前就被云平台丢掉。"
  echo ""
  echo "    Oracle Cloud : 网络 → VCN → 安全列表 → 入站规则"
  echo "    AWS          : EC2 → 安全组 → 入站规则"
  echo "    GCP          : VPC 网络 → 防火墙"
  echo "  需要一条：协议 UDP / 源 0.0.0.0/0 / 目标端口 = 上面列出的 UDP 端口。"
  echo "  默认规则通常只开 TCP 22 与 TCP 443，加 TCP 时**不会自动带上 UDP**。"
  echo ""
  echo "  判据（Hysteria2 也是直连 VPS 裸 IP 的 UDP）："
  echo "    Hysteria2 通、h3 不通  ⇒ UDP 通路没问题，问题在 nginx QUIC 这一层"
  echo "    Hysteria2 也不通       ⇒ UDP 到本机的路被挡，先查安全组再查本机防火墙"
  echo ""
  echo -e "${YELLOW}  节点 VLESS-XHTTP-CDN-H3（备用，默认关闭，xh cdnh3 on 开启）经 Cloudflare CDN 转发${NC}"
  echo "  走 QUIC/UDP 443，依赖：① Cloudflare 区域开启 HTTP/3  ② 客户端网络允许 UDP 443 出站。"
  echo "  若所处网络环境对 UDP 443 存在限速或丢包，可通过 FEATURE_CDN_H2=true 启用 TCP/h2 备用节点。"
  echo ""
  echo "  另：开启 TUN 时务必确认节点自身流量已豁免（client-config-mihomo-full.yaml"
  echo "  已内置 route-exclude-address / 首条 DIRECT 规则），否则 QUIC 会在 TUN 里自环。"
}
cmd_tuning() {
  case "${1:-show}" in
    show)
      local _mem _buf_mb _cap_mb
      _mem=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
      if   [[ "$_mem" -ge 4096  ]]; then _buf_mb=64; _cap_mb=64;
      elif [[ "$_mem" -ge 1536  ]]; then _buf_mb=32; _cap_mb=32;
      else _buf_mb=16; _cap_mb=16; fi

      echo -e "${CYAN}[+] 流控状态摘要${NC}"
      echo -e "  推荐缓冲区：             ${GREEN}${_buf_mb}MB${NC}"
      echo -e "  内存保护上限：           ${GREEN}${_cap_mb}MB${NC}"
      echo -e "  队列算法：               ${GREEN}$(sysctl -n net.core.default_qdisc 2>/dev/null || echo n/a)${NC}"
      echo -e "  拥塞控制：               ${GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo n/a)${NC}"
      printf '  %-32s %s\n' "  └─ BBR 版本" "$(detect_bbr_version)"
      echo -e "  tcp_wmem:                 ${GREEN}$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo n/a)${NC}"
      echo -e "  tcp_rmem:                 ${GREEN}$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo n/a)${NC}"
      echo -e "  tcp_limit_output_bytes:   ${GREEN}$(sysctl -n net.ipv4.tcp_limit_output_bytes 2>/dev/null || echo n/a)${NC}"
      echo -e "  tcp_slow_start_after_idle: ${GREEN}$(sysctl -n net.ipv4.tcp_slow_start_after_idle 2>/dev/null || echo n/a)${NC}"
      echo ""

      if [[ -f "$SYSCTL_CONF" ]]; then
        echo -e "${CYAN}[+] ${SYSCTL_CONF}${NC}"
        cat "$SYSCTL_CONF"
      elif [[ -f /etc/sysctl.d/99-sbbox.conf ]]; then
        echo -e "${CYAN}[+] /etc/sysctl.d/99-sbbox.conf（已由 sbbox 启用生效）${NC}"
        cat /etc/sysctl.d/99-sbbox.conf
      else
        info "系统层调优未开启。安装时默认自动执行（跳过用 FEATURE_AUTO_TUNING=false），也可手动 ${MANAGE_CMD} tuning on"
      fi
      [[ -f "$LIMITS_CONF" ]] && { echo ""; echo -e "${CYAN}[+] ${LIMITS_CONF}${NC}"; cat "$LIMITS_CONF"; }
      return 0
      ;;
    on)
      [[ -f "$SYSCTL_CONF" ]] && { info "系统层调优已处于开启状态（重跑请先 ${MANAGE_CMD} tuning off）"; return 0; }
      # v2.0.0：调优逻辑内联在本命令里，不再需要重跑安装脚本。
      # 全部 best-effort，逐项能力探测（BBR / 只读 sysctl / limits.d 是否存在），
      # 任何一项失败只 warn，不影响已经跑通的节点。
      apply_system_tuning
      ;;
    off)
      rm -f "$SYSCTL_CONF" "$LIMITS_CONF" /etc/modules-load.d/xray-xhttp-conntrack.conf
      # v4.9.44：网卡运行时参数的开机重设（xray-xhttp-nic.service）一并移除；
      # 当前的 fq / initcwnd 保持到下次重启，与 sysctl 的回滚方式一致。
      remove_nic_tune
      # v4.7.3：只删本项目自己的 drop-in。用户手工加固的 override.conf 一律不动
      # ——除非它的内容与旧版生成物逐字一致（说明是本项目留下的，用户没改过）。
      # 旧实现无条件 rm override.conf，会连用户的 Restart=always / OOMScoreAdjust
      # 一起删掉，且不留任何提示。
      local d kept_user=0
      for d in /etc/systemd/system/xray.service.d /etc/systemd/system/nginx.service.d /etc/systemd/system/hysteria-server.service.d /etc/systemd/system/sing-box.service.d; do
        rm -f "${d}/10-xray-xhttp.conf"
        if [[ -f "${d}/override.conf" ]]; then
          if [[ "$(grep -vE '^\s*(#|$)' "${d}/override.conf" | tr -d '[:space:]')" \
                == "[Service]LimitNOFILE=1048576LimitNPROC=infinity" ]]; then
            rm -f "${d}/override.conf"
          else
            kept_user=1
          fi
        fi
        rmdir "$d" 2>/dev/null || true
      done
      [[ "$kept_user" -eq 1 ]] && \
        warn "你自己修改过的 override.conf 已保留（本命令只移除本项目写入的 10-xray-xhttp.conf）"
      # 与 fs.nr_open 对齐用的 DefaultLimitNOFILE drop-in 也一并移除（见
      # align_default_nofile）。删掉后 systemd 回到 /etc/systemd/system.conf 的值。
      if [[ -f /etc/systemd/system.conf.d/10-xray-xhttp-nofile.conf ]]; then
        rm -f /etc/systemd/system.conf.d/10-xray-xhttp-nofile.conf
        rmdir /etc/systemd/system.conf.d 2>/dev/null || true
        systemctl daemon-reexec >/dev/null 2>&1 || true
      fi
      [[ "$SERVICE_TYPE" == "systemd" ]] && systemctl daemon-reload >/dev/null 2>&1
      sysctl --system >/dev/null 2>&1 || true
      info "已移除本项目写入的全部调优配置"
      warn "已生效的运行时内核参数需重启系统才能完全恢复默认值"
      ;;
    client)
      show_client_tuning "${2:-all}"
      ;;
    win|windows|mac|macos|linux|sb|singbox)
      show_client_tuning "$1"
      ;;
    *) fail "用法: ${MANAGE_CMD} tuning [show|on|off|client|win|mac|linux|sb]" ;;
  esac
}

@@include src/06-tuning-lib.sh
cmd_brutal() {
  local action="${1:-show}"
  shift || true
  case "$action" in
    show|status|list|ls)
      echo ""
      local max_spd default_spd
      max_spd=$(get_machine_max_speed_mbps)
      default_spd=$(get_default_brutal_speed_mbps)
      echo -e "${CYAN}=== TCP Brutal 状态 ===${NC}"
      if lsmod | grep -qw brutal; then
        echo -e "  内核模块:       ${GREEN}已加载 (v$(cat /sys/module/brutal/version 2>/dev/null || echo '2.x'))${NC}"
      else
        echo -e "  内核模块:       ${RED}未加载${NC}"
      fi
      local cc_xray
      cc_xray=$(grep -o '"tcpcongestion"[[:space:]]*:[[:space:]]*"[^"]*"' /usr/local/etc/xray/config.json 2>/dev/null | head -1 | cut -d'"' -f4)
      [[ -z "$cc_xray" ]] && cc_xray="未显式配置 (随系统默认 BBR)"
      echo -e "  Xray 入站 CC:   ${YELLOW}${cc_xray}${NC}"
      local cur_rate
      cur_rate=$(sed -n -E 's/^0\.0\.0\.0\/0[[:space:]]+([0-9]+).*/\1/p' "$TCP_BRUTAL_RULES_FILE" 2>/dev/null | head -1)
      [[ -n "$cur_rate" ]] || cur_rate="$default_spd"
      echo -e "  本机网卡规格:   ${GREEN}${max_spd} Mbps${NC}"
      echo -e "  当前 Brutal 速率: ${GREEN}${cur_rate} Mbps${NC}"
      if [[ "$cur_rate" -gt 1500 ]]; then
        echo -e "  ${YELLOW}提示：Brutal 属固定速率发包；若远超客户端宽带会引发严重丢包，推荐对齐实际宽带 (如 300M)：${MANAGE_CMD} brutal speed 300${NC}"
      fi
      echo ""
      echo -e "${CYAN}=== 当前 Brutal 规则与实时连接 ===${NC}"
      if command -v brutalctl >/dev/null 2>&1; then
        brutalctl list
      else
        echo "  未安装 brutalctl"
      fi
      echo ""

      # 路由级 congctl lock 会按**目的地**强制 CC，优先级压过入站的 sockopt 分工，
      # 把本该走 BBR 的入站（乃至 SSH）一并拽进 brutal 定速。单独列出来提醒。
      local _rlocks
      _rlocks=$(ip route show 2>/dev/null | grep -E 'congctl[[:space:]]+lock')
      if [[ -n "$_rlocks" ]]; then
        echo -e "${YELLOW}=== 路由级 congctl lock（按目的地强制 CC，会覆盖入站分工）===${NC}"
        echo "$_rlocks" | sed 's/^/  /'
        echo -e "  ${YELLOW}提示：该锁对目的地的所有 TCP 连接生效，不区分是否代理流量；${NC}"
        echo -e "  ${YELLOW}      如需恢复「Xray 走 brutal / 其余走 BBR」的分工，用 brutalctl del <prefix> 移除。${NC}"
        echo ""
      fi

      # 实测口径的效果对比：Brutal 是定速算法，速率超过链路真实容量时不会退让，
      # 表现为重传率飙升。这里按 CC 汇总在线连接的发送量与重传量——
      # brutal 重传率显著高于 bbr 即说明速率超配，应下调而不是继续加码。
      echo -e "${CYAN}=== 在线连接实际 CC 分布与重传率 ===${NC}"
      local _cc_stat
      _cc_stat=$(ss -tin state established 2>/dev/null | awk '
        /^[[:space:]]/ {
          cc=""
          for (i=1; i<=NF; i++)
            if ($i=="bbr" || $i=="brutal" || $i=="cubic" || $i=="reno") { cc=$i; break }
          if (cc=="") next
          s=0; r=0
          for (i=1; i<=NF; i++) {
            if ($i ~ /^bytes_sent:/)    { t=$i; sub(/^bytes_sent:/,"",t);    s=t+0 }
            if ($i ~ /^bytes_retrans:/) { t=$i; sub(/^bytes_retrans:/,"",t); r=t+0 }
          }
          n[cc]++; sent[cc]+=s; ret[cc]+=r
        }
        END {
          for (c in n) {
            p = sent[c]>0 ? ret[c]*100.0/sent[c] : 0
            printf "  %-7s 连接 %-4d 发送 %8.1f MB  重传 %7.1f MB (%.1f%%)\n", c, n[c], sent[c]/1048576, ret[c]/1048576, p
          }
        }')
      if [[ -n "$_cc_stat" ]]; then
        echo "$_cc_stat"
        echo -e "  ${YELLOW}注：CC 在连接建立时确定，改了规则后需客户端重连才会切换。${NC}"
      else
        echo "  (当前无已建立的 TCP 连接)"
      fi
      echo ""
      ;;
    on)
      local mbps="${1:-}"
      if [[ -z "$mbps" || "$mbps" == "auto" ]]; then
        mbps="$(choose_brutal_speed auto)"
      fi
      set_tcp_brutal_xray on "$mbps"
      set_tcp_brutal_speed "$mbps"
      ;;
    off)
      set_tcp_brutal_xray off
      ;;
    speed)
      local mbps="${1:-}"
      if [[ -z "$mbps" || "$mbps" == "auto" ]]; then
        mbps="$(choose_brutal_speed auto)"
      fi
      set_tcp_brutal_speed "$mbps"
      ;;
    add)
      add_tcp_brutal_rule "$@"
      ;;
    del|rm)
      del_tcp_brutal_rule "$@"
      ;;
    update|up)
      update_tcp_brutal
      [[ " $* " == *" --now "* ]] && reload_tcp_brutal
      ;;
    reload)
      reload_tcp_brutal
      ;;
    *)
      echo "用法: ${MANAGE_CMD} brutal [show|on|off|speed|add|del|update|reload]"
      echo "  ${MANAGE_CMD} brutal show          查看 TCP Brutal 状态与活跃连接"
      echo "  ${MANAGE_CMD} brutal on [mbps]     开启 Xray TCP Brutal（默认设为本机最大速率的 95%）"
      echo "  ${MANAGE_CMD} brutal off           关闭 Xray TCP Brutal（回落至 BBR）"
      echo "  ${MANAGE_CMD} brutal speed [mbps]  修改全局默认下发速率（不填则自动设为本机 95% 速率）"
      echo "  ${MANAGE_CMD} brutal add <IP> [M]  为指定客户端 IP 设定独立下发速率"
      echo "  ${MANAGE_CMD} brutal del <IP>      删除指定客户端 IP 规则"
      echo "  ${MANAGE_CMD} brutal update [--now] 更新内核模块到上游最新版（校验 sha256；默认下次开机生效，--now 立即重载）"
      echo "  ${MANAGE_CMD} brutal reload        立即重载为已编译的新版模块（Xray 停止数秒）"
      ;;
  esac
}

# 健康检查：服务掉线则拉起（由 cron 每 5 分钟调用）
cmd_ecn() {
  local action="${1:-show}"
  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== TCP ECN (Explicit Congestion Notification) 状态 ===${NC}"
      local cur_ecn cur_fallback
      cur_ecn=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo "n/a")
      cur_fallback=$(sysctl -n net.ipv4.tcp_ecn_fallback 2>/dev/null || echo "n/a")
      if [[ "$cur_ecn" == "1" ]]; then
        echo -e "  当前状态:       ${GREEN}已开启 (1 - 主动双向协商)${NC}"
      elif [[ "$cur_ecn" == "2" ]]; then
        echo -e "  当前状态:       ${YELLOW}被动协商 (2 - 仅响应对端 ECN 请求)${NC}"
      else
        echo -e "  当前状态:       ${RED}已关闭 (0)${NC}"
      fi
      echo -e "  自动回退黑洞:   ${cur_fallback} (1=开启，遇到不支持 ECN 的坏中间盒自动回退)"
      local ce_stat
      ce_stat=$(nstat -az 2>/dev/null | grep -iE 'DeliveredCE|InCEPkts' | awk '{printf "%s: %s  ", $1, $2}')
      echo -e "  路径 CE 标记:   ${ce_stat:-无记录或0}"
      echo ""
      echo -e "说明："
      echo -e "  • ECN 允许网络路由器在缓冲区打满前向 TCP 端点标记拥塞（CE 标记），避免直接丢包。"
      echo -e "  • 配合当前主机的 BBRv3 内核，可实现极低抖动拥塞控制响应。"
      echo -e "  • 快捷命令:"
      echo -e "      ${MANAGE_CMD} ecn on       # 开启主动双向 ECN 协商 (tcp_ecn=1)"
      echo -e "      ${MANAGE_CMD} ecn off      # 关闭 ECN 协商 (tcp_ecn=0)"
      echo ""
      ;;
    on)
      info "正在开启 TCP ECN..."
      try_sysctl net.ipv4.tcp_ecn 1 || sysctl -w net.ipv4.tcp_ecn=1 >/dev/null 2>&1 || true
      try_sysctl net.ipv4.tcp_ecn_fallback 1 || sysctl -w net.ipv4.tcp_ecn_fallback=1 >/dev/null 2>&1 || true
      if [[ -f "$SYSCTL_CONF" ]]; then
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn[[:space:]]*=.*/net.ipv4.tcp_ecn = 1/' "$SYSCTL_CONF" 2>/dev/null || true
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn_fallback[[:space:]]*=.*/net.ipv4.tcp_ecn_fallback = 1/' "$SYSCTL_CONF" 2>/dev/null || true
      fi
      if [[ -f "/etc/sysctl.d/99-sbbox.conf" ]]; then
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn[[:space:]]*=.*/net.ipv4.tcp_ecn = 1/' "/etc/sysctl.d/99-sbbox.conf" 2>/dev/null || true
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn_fallback[[:space:]]*=.*/net.ipv4.tcp_ecn_fallback = 1/' "/etc/sysctl.d/99-sbbox.conf" 2>/dev/null || true
      fi
      info "TCP ECN 已成功开启 (net.ipv4.tcp_ecn=1, tcp_ecn_fallback=1)！"
      ;;
    off)
      info "正在关闭 TCP ECN..."
      try_sysctl net.ipv4.tcp_ecn 0 || sysctl -w net.ipv4.tcp_ecn=0 >/dev/null 2>&1 || true
      if [[ -f "$SYSCTL_CONF" ]]; then
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn[[:space:]]*=.*/net.ipv4.tcp_ecn = 0/' "$SYSCTL_CONF" 2>/dev/null || true
      fi
      if [[ -f "/etc/sysctl.d/99-sbbox.conf" ]]; then
        sed -i -E 's/^#?net\.ipv4\.tcp_ecn[[:space:]]*=.*/net.ipv4.tcp_ecn = 0/' "/etc/sysctl.d/99-sbbox.conf" 2>/dev/null || true
      fi
      info "TCP ECN 已关闭 (net.ipv4.tcp_ecn=0)！"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} ecn [show|on|off]"
      ;;
  esac
}

# ---------- nginx 更新（v4.9.47：每周只提醒，手动更新并校验 PGP 签名）----------
# 跟随 nginx.org 的 mainline（nginx 官方推荐生产使用；安装器同样装 mainline）。
# 源码包必须通过 nginx 官方发布签名校验，且签名密钥的主指纹必须在下面的固定列表里——
# 防止下载源或密钥文件被替换。列表来自 https://nginx.org/en/pgp_keys.html（2026-09-29 核对）：
#   Sergey Kandaurov / Roman Arutyunyan / Konstantin Pavlov / Sergey Budnevitch
NGINX_PGP_KEYS="pluknet arut thresh sb"
NGINX_PGP_FPRS="D6786CE303D9A9022998DC6CC8464D549AF75C0A 43387825DDB1BB97EC36BA5D007C8D7C15D87369 13C82A63B603576156E30A4EA0EA981B66B0D967 7338973069ED3F443F4D37DFA64FD5B17ADB39A8"

# ==================================================
# 节点真实网速压测与吞吐基准 (bench / speed)
# ==================================================
cmd_bench() {
  info "正在准备全协议节点端到端网速压测引擎..."
  local sub_dir="" raw_file=""
  if [[ -d "/usr/local/nginx/html/sub" ]]; then
    sub_dir=$(ls -d /usr/local/nginx/html/sub/*/ 2>/dev/null | head -1 || true)
    [[ -n "$sub_dir" && -f "${sub_dir}v2rayn-raw.txt" ]] && raw_file="${sub_dir}v2rayn-raw.txt"
  fi
  [[ -z "$raw_file" && -f "/root/client-config.txt" ]] && raw_file="/root/client-config.txt"
  [[ -z "$raw_file" && -f "/etc/xhttp-cdn/all/client-config.txt" ]] && raw_file="/etc/xhttp-cdn/all/client-config.txt"
  [[ -f "$raw_file" ]] || fail "未找到节点订阅配置文件，无法执行测速"

  local filter="${1:-}"
  python3 - "$raw_file" "$filter" << 'PYBENCH'
import sys, os, subprocess, json, time, urllib.parse, copy

raw_file = sys.argv[1]
filter_arg = sys.argv[2].lower() if len(sys.argv) > 2 else ""

TMP_DIR = "/tmp/xh_bench_" + str(os.getpid())
os.makedirs(TMP_DIR, exist_ok=True)
UPFILE = TMP_DIR + "/up_10m.bin"
DL_BYTES = 50 * 1024 * 1024
UP_BYTES = 10 * 1024 * 1024

with open(UPFILE, "wb") as f:
    f.write(os.urandom(UP_BYTES))

def cleanup():
    import shutil
    try: shutil.rmtree(TMP_DIR, ignore_errors=True)
    except: pass

import atexit
atexit.register(cleanup)

# 1. 物理基准
print("="*96)
print("【第一阶段：服务器物理直连基准测速（Direct Baseline，不走代理）】")
print("="*96)

def get_stats(proxy=None):
    proxy_arg = f"--socks5-hostname {proxy}" if proxy else ""
    r1 = subprocess.run(f"curl -s -o /dev/null --max-time 5 {proxy_arg} -w '%{{http_code}} %{{time_total}}' http://www.gstatic.com/generate_204", shell=True, capture_output=True, text=True)
    o1 = r1.stdout.split()
    ttfb = float(o1[1]) * 1000 if len(o1) >= 2 and o1[0] in ("200", "204") else None

    r2 = subprocess.run(f"curl -s -o /dev/null --max-time 20 {proxy_arg} -w '%{{http_code}} %{{speed_download}} %{{time_total}}' 'https://speed.cloudflare.com/__down?bytes={DL_BYTES}'", shell=True, capture_output=True, text=True)
    o2 = r2.stdout.split()
    dl_mbps = (float(o2[1]) * 8 / 1e6) if len(o2) >= 3 and o2[0] == "200" else None
    dl_mbytes = (float(o2[1]) / 1024 / 1024) if len(o2) >= 3 and o2[0] == "200" else None
    dl_time = float(o2[2]) if len(o2) >= 3 and o2[0] == "200" else None

    r3 = subprocess.run(f"curl -s -o /dev/null --max-time 20 {proxy_arg} -X POST --data-binary @{UPFILE} -w '%{{http_code}} %{{speed_upload}} %{{time_total}}' https://speed.cloudflare.com/__up", shell=True, capture_output=True, text=True)
    o3 = r3.stdout.split()
    ul_mbps = (float(o3[1]) * 8 / 1e6) if len(o3) >= 3 and o3[0] == "200" else None
    ul_mbytes = (float(o3[1]) / 1024 / 1024) if len(o3) >= 3 and o3[0] == "200" else None
    ul_time = float(o3[2]) if len(o3) >= 3 and o3[0] == "200" else None

    return {"ttfb_ms": ttfb, "dl_mbps": dl_mbps, "dl_mbytes": dl_mbytes, "dl_time": dl_time, "ul_mbps": ul_mbps, "ul_mbytes": ul_mbytes, "ul_time": ul_time}

base = get_stats(None)
if base["ttfb_ms"]:
    print(f"服务器直连延时 (RTT):   {base['ttfb_ms']:.2f} ms")
    print(f"服务器直连下行带宽:     {base['dl_mbps']:.1f} Mbps ({base['dl_mbytes']:.1f} MB/s, 耗时 {base['dl_time']:.2f}s)")
    print(f"服务器直连上行带宽:     {base['ul_mbps']:.1f} Mbps ({base['ul_mbytes']:.1f} MB/s, 耗时 {base['ul_time']:.2f}s)")
else:
    print("基础物理测速超时或异常")

# 2. 解析节点
nodes = []
with open(raw_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        p = urllib.parse.urlparse(line)
        name = urllib.parse.unquote(p.fragment or "")
        if filter_arg and (filter_arg not in name.lower() and filter_arg not in line.lower()):
            continue
        nodes.append((name, line, p))

if not nodes:
    print(f"没有匹配到待测速的节点 (过滤器: '{filter_arg}')")
    sys.exit(0)

print("\n" + "="*96)
print(f"【第二阶段：各代理节点端到端网速实测（共 {len(nodes)} 个节点，50MB 下行 / 10MB 上行）】")
print("="*96)

results = []
base_port = 29500

for idx, (name, raw_line, parsed) in enumerate(nodes, 1):
    port = base_port + idx
    core_type = "xray"
    cfg = {}
    proc = None

    if parsed.scheme == "hysteria2":
        core_type = "sing-box"
        qs = urllib.parse.parse_qs(parsed.query)
        q = lambda k, d=None: qs.get(k, [d])[0]
        ob = {
            "type": "hysteria2",
            "tag": "proxy-out",
            "server": "127.0.0.1",
            "server_port": parsed.port or 443,
            "password": urllib.parse.unquote(parsed.username or ""),
            "tls": {"enabled": True, "server_name": q("sni", ""), "alpn": ["h3"]}
        }
        if q("obfs") == "salamander":
            ob["obfs"] = {"type": "salamander", "password": q("obfs-password", "")}
        cfg = {
            "log": {"level": "error"},
            "inbounds": [{"type": "socks", "tag": "socks-in", "listen": "127.0.0.1", "listen_port": port}],
            "outbounds": [ob, {"type": "direct", "tag": "direct"}],
            "route": {"rules": [{"inbound": ["socks-in"], "outbound": "proxy-out"}]}
        }
        cfg_file = f"{TMP_DIR}/sb_{idx}.json"
        with open(cfg_file, 'w') as f: json.dump(cfg, f)
        sb_bin = "/root/sbbox/sing-box" if os.path.isfile("/root/sbbox/sing-box") else "sing-box"
        proc = subprocess.Popen([sb_bin, "run", "-c", cfg_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        # VLESS 节点解析
        qs = urllib.parse.parse_qs(parsed.query)
        q = lambda k, d=None: qs.get(k, [d])[0]
        sec = q("security", "none")
        net = q("type", "tcp")
        alpn = qs.get("alpn", ["h2"])
        sni = q("sni", "")
        uid = parsed.username or ""
        tgt_addr = "127.0.0.1" if sec != "tls" or "cdn" not in name.lower() else (q("host", "") or "127.0.0.1")

        ob = {
            "tag": "proxy-out",
            "protocol": "vless",
            "settings": {"vnext": [{"address": tgt_addr, "port": parsed.port or 443, "users": [{"id": uid, "encryption": q("encryption", "none")}]}]},
            "streamSettings": {
                "network": net,
                "security": sec
            }
        }
        if q("flow"): ob["settings"]["vnext"][0]["users"][0]["flow"] = q("flow")
        if sec == "reality":
            ob["streamSettings"]["realitySettings"] = {
                "serverName": sni,
                "fingerprint": q("fp", "chrome"),
                "publicKey": q("pbk", ""),
                "shortId": q("sid", ""),
                "spiderX": q("spx", "")
            }
        elif sec == "tls":
            ob["streamSettings"]["tlsSettings"] = {
                "serverName": sni,
                "fingerprint": q("fp", "chrome"),
                "alpn": alpn
            }
        if net == "xhttp":
            xh = {"path": q("path", "/"), "mode": q("mode", "auto")}
            if q("host"): xh["host"] = q("host")
            if q("extra"):
                try: xh["extra"] = json.loads(q("extra"))
                except: pass
            ob["streamSettings"]["xhttpSettings"] = xh

        cfg = {
            "log": {"loglevel": "error"},
            "inbounds": [{"tag": "socks-in", "listen": "127.0.0.1", "port": port, "protocol": "socks", "settings": {"udp": True}}],
            "outbounds": [ob],
            "routing": {"rules": [{"type": "field", "inboundTag": ["socks-in"], "outboundTag": "proxy-out"}]}
        }
        cfg_file = f"{TMP_DIR}/xray_{idx}.json"
        with open(cfg_file, 'w') as f: json.dump(cfg, f)
        proc = subprocess.Popen(["xray", "run", "-c", cfg_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    time.sleep(1.0)
    print(f"[{idx}/{len(nodes)}] 正在测速: {name} ...", end="", flush=True)
    try:
        data = get_stats(f"127.0.0.1:{port}")
        data["name"] = name
        data["core"] = core_type
        results.append(data)
        if data["dl_mbps"]:
            print(f" -> 握手: {data['ttfb_ms']:.1f}ms | 下行: {data['dl_mbps']:.1f} Mbps ({data['dl_mbytes']:.1f}MB/s) | 上行: {data['ul_mbps']:.1f} Mbps", flush=True)
        else:
            print(" -> 失败/超时", flush=True)
    finally:
        if proc:
            proc.terminate()
            try: proc.wait(timeout=1.0)
            except: proc.kill()

print("\n" + "="*112)
print(f"{'节点名称':<38} {'核心':<9} {'握手延时':>9} {'下行带宽(50MB)':>20} {'上行带宽(10MB)':>20} {'状态':>8}")
print("="*112)
for r in results:
    ttfb_s = f"{r['ttfb_ms']:.1f} ms" if r['ttfb_ms'] else "TIMEOUT"
    dl_s = f"{r['dl_mbps']:.1f} Mbps ({r['dl_mbytes']:.1f}MB/s)" if r['dl_mbps'] else "FAIL"
    ul_s = f"{r['ul_mbps']:.1f} Mbps ({r['ul_mbytes']:.1f}MB/s)" if r['ul_mbps'] else "FAIL"
    st = "PASS" if r['dl_mbps'] else "FAIL"
    print(f"{r['name']:<38} {r['core']:<9} {ttfb_s:>9} {dl_s:>20} {ul_s:>20} {st:>8}")
print("="*112)
PYBENCH
}

# ==================================================
# 只读全栈系统性能审计 (perf-audit)
# ==================================================
cmd_audit() {
(
export LC_ALL=C
# ==================================================
# xray-xhttp 运行时性能审计（只读，不修改任何配置）
#
# 用途：采集第一~五阶段的全部检测项，输出结构化报告。
# 安全性：全程只读。没有任何 sysctl -w / 文件写入 / 服务重启 / 包安装。
#         每一项都是 best-effort，命令缺失只打印 n/a，绝不中断（见 tasks/lessons.md L1）。
#
# ---- v2.0.0 起如何读这份报告 ----
# 安装脚本**不再做任何参数优化**：装完之后本机的内核参数就是发行版默认值，
# xray-config.json 与上游 Yulinanami/my-xhttp-cdn-config 逐字节一致（不含
# policy.bufferSize / sockopt），nginx 也没有吞吐旋钮。
# 因此在**未执行 `xh tuning on`** 的机器上，第 1 节读到的全是系统默认值，
# 第 5 节读不到 policy / sockopt —— 这是**预期状态，不是缺陷**。
# 报告开头的「调优状态」一行会明确告诉你当前处于哪一侧。
#
# 最有价值的用法是跑两次做对照：
#   sudo bash perf-audit.sh > before.txt 2>&1
#   xh tuning on
#   sudo bash perf-audit.sh > after.txt 2>&1
#   diff before.txt after.txt
#
# 用法：
#   curl -fsSL <raw-url>/tools/perf-audit.sh -o perf-audit.sh
#   sudo bash perf-audit.sh > perf-report.txt 2>&1
#   然后把 perf-report.txt 完整贴回对话
# ==================================================

# 故意不使用 set -e：审计脚本任何一项失败都不该中断整体采集
export LC_ALL=C

sec()  { printf '\n\n========== %s ==========\n' "$*"; }
sub()  { printf '\n--- %s ---\n' "$*"; }
kv()   { printf '%-40s %s\n' "$1" "${2:-n/a}"; }
have() { command -v "$1" >/dev/null 2>&1; }
sy()   { local v; v=$(sysctl -n "$1" 2>/dev/null); kv "$1" "${v:-<内核不支持>}"; }

echo "xray-xhttp perf-audit  $(date -Is 2>/dev/null)"

# ==================================================
sec "0. 基本环境"
kv "kernel"   "$(uname -r 2>/dev/null)"
kv "arch"     "$(uname -m 2>/dev/null)"
kv "PAGESIZE" "$(getconf PAGESIZE 2>/dev/null)"
[[ -f /etc/os-release ]] && grep -E '^(PRETTY_NAME|VERSION_CODENAME)=' /etc/os-release
kv "uptime"   "$(uptime -p 2>/dev/null)"
kv "MemTotal" "$(awk '/^MemTotal:/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null)"
have systemd-detect-virt && kv "virt" "$(systemd-detect-virt 2>/dev/null)"

sub "调优状态（判读全文的前提）"
# v2.0.0 起 node.env 不再记录调优字段，唯一可信的判据是这两个文件是否存在——
# 它们只由 `xh tuning on` 创建，`xh tuning off` 删除。
TUNED=no
[[ -f /etc/sysctl.d/99-xray-xhttp.conf ]] && TUNED=yes
if [[ "$TUNED" == yes ]]; then
  kv "xh tuning" "已开启 —— 第 1 节的内核参数含本项目写入的值"
else
  kv "xh tuning" "未开启 —— 第 1 节全是系统默认值，第 5 节无 policy/sockopt（预期状态）"
fi

sub "本项目写入的调优文件"
for f in /etc/sysctl.d/99-xray-xhttp.conf /etc/security/limits.d/99-xray-xhttp.conf; do
  if [[ -f "$f" ]]; then
    echo "[存在] $f"
    sed 's/^/    /' "$f"
  else
    echo "[不存在] $f   （未执行 xh tuning on 时本就不存在）"
  fi
done

sub "node.env（本项目安装状态）"
# v2.0.0 移除了 TUNE_TIER / XRAY_BUFFER_KB / TUNING_BBR_OK / FEATURE_TUNING /
# FEATURE_SYSCTL / FEATURE_H3_DIRECT 这些字段——安装期不再做调优，也就无从记录。
# 继续 grep 它们只会在每台机器上打印空行，造成"调优丢了"的错觉。
if [[ -f /etc/xhttp-cdn/node.env ]]; then
  grep -E '^(PROJECT_NAME|INSTALL_TIME|OS_ID|SERVICE_TYPE|IP_CHOICE|FALLBACK_MODE|FEATURE_XPADDING|FEATURE_CDN_ECH|CDN_ECH_ENABLED)=' \
    /etc/xhttp-cdn/node.env
else
  echo "n/a"
fi

sub "所有 sysctl 配置文件内容（查重复 / 冲突）"
grep -RsHE '^[[:space:]]*[a-z]' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null | sed 's/^/  /' || echo "  n/a"

# ==================================================
sec "1. 内核网络参数"

sub "拥塞控制 / 队列规则"
sy net.ipv4.tcp_available_congestion_control
sy net.ipv4.tcp_congestion_control
sy net.core.default_qdisc
kv "tcp_bbr 模块已加载" "$(lsmod 2>/dev/null | grep -c '^tcp_bbr') (0 也可能是编译进内核)"

sub "缓冲区"
for k in net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default \
         net.core.optmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.tcp_mem \
         net.ipv4.udp_mem net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min; do
  sy "$k"
done

# tcp_mem 单位是"页"，页大小不一定是 4K（见 lessons.md L4）。这里做量纲断言。
PS=$(getconf PAGESIZE 2>/dev/null || echo 4096)
TM=$(sysctl -n net.ipv4.tcp_mem 2>/dev/null)
MT=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo 2>/dev/null)
if [[ -n "$TM" && -n "$MT" ]]; then
  awk -v tm="$TM" -v ps="$PS" -v mt="$MT" 'BEGIN{
    n=split(tm,a," "); if(n<3) exit;
    hi=a[3]*ps;
    printf "%-40s %.0f MB (物理内存 %.0f MB) -> %s\n", "tcp_mem 上限换算",
      hi/1048576, mt/1048576, (hi<mt ? "OK 低于物理内存" : "!! 超过物理内存，内存压力机制失效");
  }'
fi

sub "队列 / 积压"
for k in net.core.somaxconn net.core.netdev_max_backlog net.core.netdev_budget \
         net.core.netdev_budget_usecs net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_abort_on_overflow; do
  sy "$k"
done

sub "连接状态与超时"
for k in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.ipv4.tcp_tw_reuse \
         net.ipv4.tcp_max_tw_buckets net.ipv4.tcp_syncookies net.ipv4.tcp_slow_start_after_idle \
         net.ipv4.tcp_mtu_probing net.ipv4.tcp_notsent_lowat net.ipv4.ip_local_port_range \
         net.ipv4.tcp_keepalive_time net.ipv4.tcp_keepalive_intvl net.ipv4.tcp_keepalive_probes; do
  sy "$k"
done

sub "文件句柄"
sy fs.file-max
sy fs.nr_open
kv "fs.file-nr (已分配/空闲/上限)" "$(cat /proc/sys/fs/file-nr 2>/dev/null)"
kv "ulimit -n (当前 shell)" "$(ulimit -n 2>/dev/null)"
for p in xray nginx; do
  pid=$(pgrep -x "$p" 2>/dev/null | head -1)
  if [[ -n "$pid" ]]; then
    kv "$p 进程 nofile (soft/hard)" "$(awk '/Max open files/{print $4" / "$5}' "/proc/$pid/limits" 2>/dev/null)"
  fi
done

sub "vm 参数"
for k in vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.max_map_count vm.overcommit_memory; do
  sy "$k"
done

sub "!! 已废弃 / 无效参数检测"
for k in net.ipv4.tcp_tw_recycle net.ipv4.tcp_low_latency net.ipv4.tcp_no_metrics_save \
         net.ipv4.tcp_frto_response net.ipv4.tcp_bic net.ipv4.tcp_westwood \
         net.ipv4.tcp_vegas_cong_avoid net.ipv4.tcp_default_win_scale; do
  if sysctl -n "$k" >/dev/null 2>&1; then
    echo "  [内核仍支持] $k = $(sysctl -n "$k" 2>/dev/null)"
  else
    echo "  [内核已移除] $k"
  fi
done

echo ""
echo "  配置文件里写了、但当前内核不认的项（这些才是真正需要删除的）："
FOUND_DEAD=0
grep -RshE '^[[:space:]]*(net|fs|vm|kernel)\.' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null |
  sed 's/=.*//; s/[[:space:]]//g' | sort -u | while read -r k; do
    [[ -z "$k" ]] && continue
    sysctl -n "$k" >/dev/null 2>&1 || echo "    !! $k"
  done
[[ "$FOUND_DEAD" -eq 0 ]] && echo "    (以上为空则说明没有失效项)"

# ==================================================
sec "2. Socket / 连接状态"
have ss && ss -s 2>/dev/null

sub "TCP 状态分布"
have ss && ss -ant 2>/dev/null | awk 'NR>1{c[$1]++} END{for(s in c) printf "  %-16s %d\n", s, c[s]}' | sort -k2 -rn

sub "TCP 监听队列（Recv-Q=当前积压, Send-Q=队列上限）"
have ss && ss -lnt 2>/dev/null | sed 's/^/  /'

sub "UDP 监听（QUIC / HTTP3）"
have ss && ss -lnu 2>/dev/null | sed 's/^/  /'

sub "!! Accept / SYN 队列溢出（判定 nginx listen backlog 该不该调的唯一依据）"
# 实际生效的 accept 队列 = min(listen backlog, somaxconn)。
# nginx 不写 backlog= 时默认 511，即使 somaxconn 是 65535 也按 511 生效
# （上面「TCP 监听队列」里 nginx 那几行的 Send-Q 就是这个值）。
kv "net.core.somaxconn" "$(sysctl -n net.core.somaxconn 2>/dev/null)"
kv "nginx listen backlog" "$(grep -rhoE 'backlog=[0-9]+' /etc/nginx/ 2>/dev/null | sort -u | tr '\n' ' ' || true)"
echo "  （nginx 未显式写 backlog= 时为 511，与 somaxconn 取小）"
echo ""
if have nstat; then
  nstat -az 2>/dev/null | grep -E 'ListenOverflows|ListenDrops|TCPReqQFullDrop|TCPBacklogDrop|SyncookiesSent' | sed 's/^/  /'
  OVF=$(nstat -az 2>/dev/null | awk '/TcpExtListenOverflows/{print $2; exit}')
else
  grep -E 'ListenOverflows|ListenDrops' /proc/net/netstat 2>/dev/null | sed 's/^/  /' || echo "  n/a"
  OVF=""
fi
echo ""
echo "  判读规则（这几个计数器是自开机累计值）:"
if [[ -n "${OVF:-}" && "${OVF:-0}" -gt 0 ]] 2>/dev/null; then
  echo "    ListenOverflows = ${OVF} > 0  →  accept 队列**确实**溢出过。"
  echo "    此时把 nginx 的 listen 加上 backlog=65535 属于有故障现象支撑的正确性修复。"
else
  echo "    ListenOverflows = ${OVF:-0}  →  队列从未溢出过，backlog 511 对当前负载够用。"
  echo "    此时调大 backlog 是没有故障现象支撑的吞吐旋钮，按 tasks/lessons.md L25 不应改。"
fi
echo "    注意：XHTTP 是长连接，backlog 影响的是**建连速率**而非并发连接数——"
echo "    与 worker_connections（并发数的硬上限）是两回事，不能类比着一起调。"

sub "!! UDP 错误（RcvbufErrors 非 0 = UDP 收缓冲不足，直接影响 h3 节点）"
have nstat && nstat -az 2>/dev/null | grep -E 'UdpInErrors|UdpRcvbufErrors|UdpSndbufErrors|UdpNoPorts' | sed 's/^/  /'
echo "  /proc/net/snmp Udp 行:"
grep -A1 '^Udp:' /proc/net/snmp 2>/dev/null | sed 's/^/    /'

sub "TCP 重传 / 丢包"
have nstat && nstat -az 2>/dev/null | grep -E 'TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtTCPTimeouts|TcpInErrs' | sed 's/^/  /'

sub "conntrack"
if [[ -f /proc/sys/net/netfilter/nf_conntrack_count ]]; then
  kv "nf_conntrack_count" "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"
  sy net.netfilter.nf_conntrack_max
  sy net.netfilter.nf_conntrack_tcp_timeout_established
  sy net.netfilter.nf_conntrack_buckets
else
  echo "  conntrack 未加载 — 对纯转发场景是好事（没有 NAT/state 的每包开销）"
fi

sub "防火墙规则量（规则越多，每包匹配开销越大）"
if have nft; then
  echo "  nftables 规则行数: $(nft list ruleset 2>/dev/null | wc -l)"
fi
if have iptables; then
  echo "  iptables -S 总条数: $(iptables -S 2>/dev/null | wc -l)"
  iptables -S 2>/dev/null | head -30 | sed 's/^/    /'
fi

# ==================================================
sec "3. CPU 拓扑与多核网络分布【重点】"
have lscpu && lscpu 2>/dev/null | grep -E 'Architecture|^CPU\(s\)|Thread|Core|Socket|NUMA|Model name|BogoMIPS|L3|Vendor'
kv "nproc" "$(nproc 2>/dev/null)"

sub "NUMA"
if have numactl; then
  numactl --hardware 2>/dev/null
else
  echo "  numactl 未安装；/sys 中 NUMA 节点数: $(ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l)"
fi

sub "网卡识别"
NIC=$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -1)
[[ -z "$NIC" ]] && NIC=$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')
kv "默认出口网卡" "${NIC:-未识别}"

if [[ -n "$NIC" ]]; then
  if have ethtool; then
    echo ""
    echo "  驱动 (-i):"
    ethtool -i "$NIC" 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  !! 队列数 (-l) — Combined 若为 1，说明只有单队列，RSS 无从谈起:"
    ethtool -l "$NIC" 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Ring buffer (-g):"
    ethtool -g "$NIC" 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Offload (-k) 关键项:"
    ethtool -k "$NIC" 2>/dev/null |
      grep -E 'tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|large-receive-offload|rx-checksumming|tx-checksumming|scatter-gather' |
      sed 's/^/    /'
  else
    echo "  ethtool 未安装 — 无法读取队列数 / ring / offload（这是本阶段最关键的数据）"
  fi

  echo ""
  echo "  队列 sysfs 目录:"
  ls /sys/class/net/"$NIC"/queues/ 2>/dev/null | sed 's/^/    /'

  echo ""
  echo "  !! RPS / RFS / XPS 当前值（全 0 = 未启用）:"
  for q in /sys/class/net/"$NIC"/queues/rx-*; do
    [[ -e "$q" ]] || continue
    printf '    %-10s rps_cpus=%-12s rps_flow_cnt=%s\n' "$(basename "$q")" \
      "$(cat "$q/rps_cpus" 2>/dev/null)" "$(cat "$q/rps_flow_cnt" 2>/dev/null)"
  done
  for q in /sys/class/net/"$NIC"/queues/tx-*; do
    [[ -e "$q" ]] || continue
    printf '    %-10s xps_cpus=%s\n' "$(basename "$q")" "$(cat "$q/xps_cpus" 2>/dev/null)"
  done
  sy net.core.rps_sock_flow_entries
  kv "MTU" "$(cat /sys/class/net/$NIC/mtu 2>/dev/null)"
  kv "网卡 qdisc" "$(tc qdisc show dev $NIC 2>/dev/null | head -2 | tr '\n' ' ')"
fi

sub "!! 网卡中断分布（关键：看数字是否集中在某一个 CPU 列）"
head -1 /proc/interrupts 2>/dev/null | sed 's/^/  /'
grep -iE 'virtio|eth|ens|enp|mlx|ena' /proc/interrupts 2>/dev/null | sed 's/^/  /'

sub "IRQ affinity"
for i in $(grep -iE 'virtio|eth|ens|enp|mlx|ena' /proc/interrupts 2>/dev/null | awk -F: '{gsub(/ /,"",$1); print $1}'); do
  if [[ -f "/proc/irq/$i/smp_affinity_list" ]]; then
    printf '  IRQ %-6s affinity_list=%s\n' "$i" "$(cat "/proc/irq/$i/smp_affinity_list" 2>/dev/null)"
  fi
done
kv "irqbalance 状态" "$(systemctl is-active irqbalance 2>/dev/null || echo '未安装/未运行')"

sub "!! softnet_stat 每 CPU 统计"
echo "  CPU   processed    dropped     time_squeeze"
# strtonum() 是 gawk 扩展；Debian 默认 awk 是 mawk，不支持它，会静默输出空。
# 改用 bash 的 $((16#..)) 做十六进制转换，任何发行版都可用。
if [[ -r /proc/net/softnet_stat ]]; then
  _c=0
  while read -r f1 f2 f3 _rest; do
    [[ "$f1" =~ ^[0-9a-fA-F]+$ ]] || continue
    printf '  %-5d %-12d %-11d %d\n' "$_c" "$((16#$f1))" "$((16#$f2))" "$((16#$f3))"
    _c=$((_c+1))
  done < /proc/net/softnet_stat
else
  echo "  /proc/net/softnet_stat 不可读"
fi
echo ""
echo "  判读："
echo "    dropped 非 0      -> netdev_max_backlog 不足"
echo "    time_squeeze 非 0 -> netdev_budget 不足（一次 NAPI 轮询没处理完）"
echo "    processed 严重倾斜到 CPU0 -> 单核软中断瓶颈，需要 RSS 多队列或 RPS"

sub "CPU 利用率（3 次采样）"
if have mpstat; then
  mpstat -P ALL 1 3 2>/dev/null
else
  echo "  mpstat 未安装（apt install sysstat 可得精确的 %soft / %sys 分列数据）"
  echo "  /proc/stat 快照（user nice system idle iowait irq softirq）:"
  grep -E '^cpu' /proc/stat 2>/dev/null | sed 's/^/    /'
  sleep 3
  echo "  3 秒后:"
  grep -E '^cpu' /proc/stat 2>/dev/null | sed 's/^/    /'
fi

sub "!! softirq 累计分布（NET_RX / NET_TX 各列 = 各 CPU）"
head -1 /proc/softirqs 2>/dev/null | sed 's/^/  /'
grep -E '^\s*(NET_RX|NET_TX|TIMER|SCHED|RCU)' /proc/softirqs 2>/dev/null | sed 's/^/  /'

sub "负载"
kv "loadavg" "$(cat /proc/loadavg 2>/dev/null)"

# ==================================================
sec "4. Nginx"
have nginx && nginx -v 2>&1 | sed 's/^/  /'
if have nginx; then
  echo "  编译参数中的关键模块:"
  nginx -V 2>&1 | tr ' ' '\n' | grep -E 'http_v2|http_v3|threads|openssl|quic|boringssl' | sed 's/^/    /'
fi

sub "关键指令当前值（从 /etc/nginx 抓取）"
for d in worker_processes worker_connections worker_rlimit_nofile worker_cpu_affinity \
         multi_accept sendfile tcp_nodelay tcp_nopush aio open_file_cache \
         keepalive_timeout keepalive_requests ssl_session_cache ssl_session_tickets \
         ssl_protocols ssl_buffer_size access_log gzip; do
  v=$(grep -RhE "^[[:space:]]*${d}[[:space:]]" /etc/nginx/nginx.conf /etc/nginx/conf.d/ 2>/dev/null |
      sed 's/^[[:space:]]*//' | head -3 | tr '\n' '|')
  kv "$d" "${v:-<未设置，走默认值>}"
done
kv "listen 指令" "$(grep -RhE '^[[:space:]]*listen' /etc/nginx/nginx.conf 2>/dev/null | sed 's/^[[:space:]]*//' | tr '\n' '|')"
kv "http2 / http3" "$(grep -RhE '^[[:space:]]*http[23][[:space:]]' /etc/nginx/nginx.conf 2>/dev/null | sed 's/^[[:space:]]*//' | tr '\n' '|')"

sub "!! 文件描述符上限（worker_connections 的实际天花板）"
# worker_rlimit_nofile 只是 nginx 自己的请求值，真正生效的上限由 systemd unit /
# limits.d 决定。二者取小。若 nofile < worker_connections*2，配置里写多大都没用，
# error.log 会出现 "worker_connections exceed open file resource limit"。
# 本项目所有连接都是代理（grpc_pass / proxy_pass），每条占「客户端+上游」两个 fd。
for unit in nginx xray; do
  kv "systemd ${unit} LimitNOFILE" \
     "$(systemctl show "$unit" -p LimitNOFILE --value 2>/dev/null)"
done
for p in nginx xray; do
  pid=$(pgrep -o -x "$p" 2>/dev/null)
  [[ -n "$pid" ]] && kv "运行中 ${p}(pid ${pid}) Max open files" \
     "$(awk '/^Max open files/{print $4" (soft) / "$5" (hard)"}' "/proc/${pid}/limits" 2>/dev/null)"
done
kv "当前 shell ulimit -n" "$(ulimit -n 2>/dev/null)"
echo "  /etc/security/limits.d/ 内容:"
grep -rhE '^[^#]*nofile' /etc/security/limits.d/ /etc/security/limits.conf 2>/dev/null |
  sed 's/^/    /' || echo "    <无 nofile 配置>"
sy fs.file-max
sy fs.nr_open

sub "!! worker 进程与实际所在 CPU（psr 列）"
ps -eo pid,psr,pcpu,pmem,nlwp,comm 2>/dev/null | awk 'NR==1 || /nginx|xray/' | sed 's/^/  /'
echo "  若 nginx worker 的 psr 全相同或集中在少数几个，说明未做 worker_cpu_affinity"

sub "grpc / proxy 超时（XHTTP 长连接关键项）"
grep -REn 'grpc_(read|send|connect)_timeout|grpc_socket_keepalive|proxy_(read|send)_timeout|client_max_body_size|client_body_buffer_size' \
  /etc/nginx/ 2>/dev/null | sed 's/^/  /'

# ==================================================
sec "5. Xray"
have xray && xray version 2>/dev/null | head -1 | sed 's/^/  /'
XC=/usr/local/etc/xray/config.json
if [[ -f "$XC" ]]; then
  sub "policy / sockopt / xhttp（脱敏：不输出 UUID / 密钥）"
  # v2.0.0 起本项目不再注入 policy 与 sockopt，配置与上游逐字节一致。
  # 所以 policy 为 {}、sockopt 为空是**正确结果**；若这里有值，说明是你自己
  # 或旧版本安装留下的，需要对照 /usr/local/etc/xray/config.json 确认来源。
  if have python3; then
    python3 -c '
import json,sys
c=json.load(open("/usr/local/etc/xray/config.json"))
print("  log.loglevel:", c.get("log",{}).get("loglevel"))
print("  policy:", json.dumps(c.get("policy",{}),ensure_ascii=False))
for i,ib in enumerate(c.get("inbounds",[])):
    ss=ib.get("streamSettings",{})
    print("  inbound[%d] listen=%s port=%s net=%s security=%s" % (
        i, ib.get("listen"), ib.get("port"), ss.get("network"), ss.get("security")))
    if ss.get("sockopt"): print("    sockopt:", json.dumps(ss["sockopt"],ensure_ascii=False))
    if ss.get("xhttpSettings"):
        x=dict(ss["xhttpSettings"])
        print("    xhttpSettings:", json.dumps(x,ensure_ascii=False))
    if ib.get("sniffing"): print("    sniffing:", json.dumps(ib["sniffing"],ensure_ascii=False))
for i,ob in enumerate(c.get("outbounds",[])):
    ss=ob.get("streamSettings",{})
    print("  outbound[%d] tag=%s proto=%s sockopt=%s" % (
        i, ob.get("tag"), ob.get("protocol"), json.dumps(ss.get("sockopt",{}),ensure_ascii=False)))
' 2>/dev/null || grep -E 'bufferSize|connIdle|handshake|uplinkOnly|downlinkOnly|sockopt|tcpcongestion|tcpFastOpen' "$XC" | sed 's/^/  /'
  else
    grep -E 'bufferSize|connIdle|handshake|uplinkOnly|downlinkOnly|sockopt|tcpcongestion|tcpFastOpen' "$XC" | sed 's/^/  /'
  fi

  sub "进程运行态"
  pid=$(pgrep -x xray 2>/dev/null | head -1)
  if [[ -n "$pid" ]]; then
    kv "PID"              "$pid"
    kv "线程数 (Go 调度)" "$(ls /proc/$pid/task 2>/dev/null | wc -l)"
    kv "打开的 fd 数"     "$(ls /proc/$pid/fd 2>/dev/null | wc -l)"
    kv "GOMAXPROCS / GODEBUG" "$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -E 'GOMAXPROCS|GODEBUG' | tr '\n' ' ')"
    have taskset && kv "CPU 亲和性" "$(taskset -pc $pid 2>/dev/null | sed 's/.*: //')"
    kv "VmRSS" "$(awk '/VmRSS/{print $2" "$3}' /proc/$pid/status 2>/dev/null)"
  fi
else
  echo "  未找到 $XC"
fi

# ==================================================
sec "6. 服务状态与日志"
for s in xray nginx; do
  kv "$s active" "$(systemctl is-active $s 2>/dev/null)"
  kv "$s NRestarts/Mem" "$(systemctl show -p NRestarts -p MemoryCurrent $s 2>/dev/null | tr '\n' ' ')"
done

sub "监听端口"
have ss && ss -lntup 2>/dev/null | grep -E 'xray|nginx' | sed 's/^/  /'

sub "最近错误日志"
echo "  [nginx error.log 最后 15 行]"
{ tail -15 /usr/local/nginx/logs/error.log 2>/dev/null || tail -15 /var/log/nginx/error.log 2>/dev/null || echo "n/a"; } | sed 's/^/    /'
echo ""
echo "  [xray journal warning 及以上，最后 15 条]"
{ journalctl -u xray -p warning -n 15 --no-pager 2>/dev/null || echo "n/a"; } | sed 's/^/    /'

sec "采集完成"
echo "把本文件完整内容贴回对话即可。"
echo "全程只读：未执行任何 sysctl -w、未写入任何文件、未重启任何服务。"
echo ""
if [[ "$TUNED" == yes ]]; then
  echo "本机已执行过 xh tuning on：第 1 节的内核参数含本项目写入的值，"
  echo "可与 xh tuning off 之后的一次采集做 diff 来量化差异。"
else
  echo "本机未执行 xh tuning on：第 1 节读到的是系统默认值，第 5 节无 policy/sockopt，"
  echo "这是 v2.0.0 的预期状态。要评估调优收益，请按脚本头部的两次采集法做对照。"
fi
)
}
