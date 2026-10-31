# ==================================================
# 交互式分类导航主菜单 (Interactive Categorized Menu)
# ==================================================

# 菜单数据：数组首元素是标题，其余元素是 "文案::命令行"。
# 命令行词拆分后直接执行（不用 eval），所以参数里不能带空格。
# 嵌套菜单直接写成命令行，如 "menu_choose MENU_HY2"。

# menu_loop <数组名>：反复显示，直到选 0 或输入结束（EOF）。
menu_loop() {
  local -n _m="$1"
  local items=("${_m[@]:1}") choice
  while true; do
    _menu_print "${_m[0]}" "${items[@]}"
    echo "   0) 返回上一级菜单"
    read -rp "请选择 [0-${#items[@]}]: " choice || return 0
    [[ "$choice" == 0 ]] && return 0
    _menu_exec "$choice" "${items[@]}" || warn "无效选择"
  done
}

# menu_choose <数组名>：只选一次；直接回车 = 第 1 项（对应旧菜单里的 ${a:-show}）。
menu_choose() {
  local -n _m="$1"
  local items=("${_m[@]:1}") choice
  _menu_print "${_m[0]}" "${items[@]}"
  echo "   0) 取消"
  read -rp "请选择 [0-${#items[@]}，回车=1]: " choice || return 0
  [[ "$choice" == 0 ]] && return 0
  _menu_exec "${choice:-1}" "${items[@]}" || warn "无效选择"
}

# menu_onoff <cmd_*>：查看 / 开启 / 关闭 三选一。
menu_onoff() {
  # shellcheck disable=SC2034  # 经 nameref 使用
  MENU_ONOFF=("${1#cmd_}" "查看状态::$1 show" "开启::$1 on" "关闭::$1 off")
  menu_choose MENU_ONOFF
}

# menu_ask <提示> <命令行…>：读一行文本追加为最后一个参数；直接回车则取消。
# 只用于值天然自由的场景（版本号、毫秒数、过滤关键词）。
menu_ask() {
  local prompt="$1" v
  shift
  read -rp "  ${prompt}: " v || return 0
  [[ -n "$v" ]] && "$@" "$v"
  return 0
}

_menu_print() {
  local title="$1" i
  shift
  local items=("$@")
  echo ""
  echo -e "${CYAN}--- ${title} ---${NC}"
  for ((i = 0; i < ${#items[@]}; i++)); do
    printf '  %2d) %s\n' "$((i + 1))" "${items[i]%%::*}"
  done
}

# _menu_exec <序号> <条目…>：序号越界返回 1；命令自身的返回值不影响菜单。
_menu_exec() {
  local n="$1"
  shift
  local items=("$@")
  [[ "$n" =~ ^[0-9]{1,3}$ ]] && ((10#$n >= 1 && 10#$n <= ${#items[@]})) || return 1
  # shellcheck disable=SC2086
  ${items[10#$n - 1]#*::}
  return 0
}

# 数组按名字经 nameref 使用（menu_loop / menu_choose），ShellCheck 看不到引用，会误报 SC2034。
# shellcheck disable=SC2034
_menu_define() {
  MENU_NODE=("[1] 节点与协议矩阵管理"
    "查看全部节点参数与客户端链接 (info)::cmd_info"
    "查看订阅链接与全端二维码 (sub)::cmd_sub"
    "重新生成全量订阅文件 (resub)::cmd_resub"
    "Reality 核心节点管理 (reality)::menu_choose MENU_REALITY"
    "上下行分离节点管理 (split)::menu_choose MENU_SPLIT"
    "Hysteria2 直连与混淆管理 (hy2)::menu_choose MENU_HY2"
    "XHTTP-Direct-H2 直连管理 (h2direct)::menu_onoff cmd_h2direct"
    "CDN TCP(h2) 节点开关 (cdnh2)::menu_onoff cmd_cdnh2"
    "CDN QUIC(h3) 节点开关 (cdnh3)::menu_onoff cmd_cdnh3"
    "Reality 兼容模式与最低版本 (minversion)::menu_choose MENU_MINVER"
    "Reality 时间差校验 (timediff)::menu_choose MENU_TIMEDIFF"
    "出站分流：屏蔽回国 IP / 广告域名 (block)::menu_choose MENU_BLOCK")

  MENU_REALITY=("Reality 核心节点管理"
    "查看状态::cmd_reality show"
    "Vision 开启::cmd_reality vision on"
    "Vision 关闭::cmd_reality vision off"
    "XHTTP 开启::cmd_reality xhttp on"
    "XHTTP 关闭::cmd_reality xhttp off"
    "上下行分离 开启::cmd_reality updown on"
    "上下行分离 关闭::cmd_reality updown off")

  MENU_SPLIT=("上下行分离节点管理"
    "查看状态::cmd_split show"
    "上行 Reality / 下行 CDN  开启::cmd_split reality-up on"
    "上行 Reality / 下行 CDN  关闭::cmd_split reality-up off"
    "上行 CDN / 下行 Reality  开启::cmd_split cdn-up on"
    "上行 CDN / 下行 Reality  关闭::cmd_split cdn-up off")

  MENU_HY2=("Hysteria2 直连与混淆管理"
    "查看状态::cmd_hy2 show"
    "开启 Hysteria2 直连节点::cmd_hy2 on"
    "关闭全部 Hysteria2 节点::cmd_hy2 off"
    "开启 Hysteria2 混淆节点::cmd_hy2 obfs on"
    "关闭 Hysteria2 混淆节点::cmd_hy2 obfs off")

  MENU_MINVER=("Reality 最低客户端版本"
    "查看状态::cmd_minversion show"
    "开启兼容模式::cmd_minversion on"
    "关闭（使用内核默认版本）::cmd_minversion off"
    "指定版本号…::menu_ask 版本号(如1.8.0) cmd_minversion")

  MENU_TIMEDIFF=("Reality 时间差校验"
    "查看状态::cmd_timediff show"
    "开启（默认阈值）::cmd_timediff on"
    "开启并指定毫秒数…::menu_ask 毫秒数 cmd_timediff on"
    "关闭::cmd_timediff off")

  MENU_BLOCK=("出站分流"
    "查看状态::cmd_block show"
    "屏蔽回国 IP  开启::cmd_block cn on"
    "屏蔽回国 IP  关闭::cmd_block cn off"
    "屏蔽广告域名  开启::cmd_block ads on"
    "屏蔽广告域名  关闭::cmd_block ads off")

  MENU_PERF=("[2] 链路测速与性能审计"
    "🚀 节点全量真实网速与吞吐压测 (bench / speed)::cmd_bench"
    "🚀 按关键词过滤压测…::menu_ask 关键词 cmd_bench"
    "🔍 只读全栈系统与网络性能审计 (audit)::cmd_audit"
    "🌐 UDP 节点全协议连通性自检 (diag)::cmd_diag"
    "⚠️ sysctl 参数冲突与覆盖检测 (conflict)::cmd_conflict"
    "🔌 端口占用与冲突检测 (portconflict)::cmd_portconflict")

  MENU_NET=("[3] 系统网络与流控调优"
    "系统层流控调优 (BBRv3 + FQ + 128MB缓冲区)::menu_onoff cmd_tuning"
    "TCP Brutal 极速加速模式与速率调节 (brutal)::menu_choose MENU_BRUTAL"
    "TCP ECN 显式拥塞通知开关 (ecn)::menu_onoff cmd_ecn"
    "客户端本地网络调优指南 (tuning client)::menu_choose MENU_TUNE_CLIENT")

  MENU_BRUTAL=("TCP Brutal"
    "查看状态::cmd_brutal show"
    "开启::cmd_brutal on"
    "关闭::cmd_brutal off"
    "调整速率::cmd_brutal speed")

  MENU_TUNE_CLIENT=("客户端本地网络调优指南"
    "通用说明::cmd_tuning client"
    "Windows::cmd_tuning win"
    "macOS::cmd_tuning mac"
    "Linux::cmd_tuning linux"
    "sing-box::cmd_tuning sb")

  MENU_CF=("[4] Cloudflare 智能优选与证书"
    "查看当前优选 IP 状态与解析 (bestcf show)::cmd_bestcf show"
    "锁定当前优选 IP，禁止自动轮换 (bestcf lock)::cmd_bestcf lock"
    "解锁，恢复定时自适应轮换 (bestcf unlock)::cmd_bestcf unlock"
    "手动自定义优选 IP 并锁定 (bestcf set)::cmd_bestcf set"
    "调整优选 IP 定时轮换周期 (bestcf interval)::cmd_bestcf interval"
    "立即执行链路延迟与握手健康检测 (bestcf check)::cmd_bestcf check"
    "立即强制重新测速并更新 DNS (bestcf run)::cmd_bestcf run"
    "Cloudflare DNS 全面规范性体检 (bestcf audit)::cmd_bestcf audit"
    "配置 Cloudflare 凭据与域名 (bestcf setup)::cmd_bestcf setup"
    "SSL 证书管理与自动续期 (cert)::menu_loop MENU_CERT"
    "Cloudflare CDN ECH 加密 SNI 开关 (ech)::menu_onoff cmd_ech")

  MENU_CERT=("SSL 证书全生命周期管理"
    "查看证书状态与到期时间 (show)::cmd_cert show"
    "一键申请/重新签发证书 (apply / 调用 Acme-yg)::cmd_cert apply"
    "智能扫描并导入已有证书 (import / 复用 ygkkkca)::cmd_cert import"
    "切换续期模式为 Cloudflare DNS-01 (dnscf)::cmd_cert dnscf"
    "立即测试证书自动续期 (renew)::cmd_cert renew")

  MENU_SVC=("[5] 服务生命周期与系统运维"
    "查看服务与流控运行状态 (status)::cmd_status"
    "查看运行日志 (log)::menu_choose MENU_LOG"
    "重启全部服务 (restart)::cmd_restart"
    "启动 / 停止服务 (start / stop)::menu_choose MENU_STARTSTOP"
    "更新 Xray-core 内核版本 (update)::menu_choose MENU_UPDATE"
    "Nginx 版本检查与升级编译 (nginx)::menu_choose MENU_NGINX"
    "保活自愈服务管理 (keepalive)::menu_onoff cmd_keepalive"
    "内核每周自动更新设置 (autoupdate)::menu_choose MENU_AUTOUPDATE"
    "执行一次异常守护检查 (guard)::cmd_guard")

  MENU_LOG=("运行日志"
    "xray::cmd_log xray"
    "nginx::cmd_log nginx")

  MENU_STARTSTOP=("启动 / 停止服务"
    "启动 (start)::cmd_start"
    "停止 (stop)::cmd_stop")

  MENU_UPDATE=("更新 Xray-core"
    "最新正式版::cmd_update"
    "预览版 (pre)::cmd_update pre"
    "指定版本号…::menu_ask 版本号(如26.10.29) cmd_update")

  MENU_NGINX=("Nginx 版本管理"
    "查看状态::cmd_nginx show"
    "检查新版本::cmd_nginx check"
    "升级::cmd_nginx update")

  MENU_AUTOUPDATE=("Xray 内核自动更新"
    "查看状态::cmd_autoupdate show"
    "开启::cmd_autoupdate on"
    "关闭::cmd_autoupdate off"
    "只跟进正式版 (stable)::cmd_autoupdate stable"
    "跟进预览版 (pre)::cmd_autoupdate pre")

  MENU_TUNNEL=("[6] 高级隧道与扩展网络"
    "查看 Cloudflare Argo 隧道状态 (argo status)::cmd_argo status"
    "开启/配置 Argo 隧道 (argo on)::cmd_argo on"
    "关闭 Argo 隧道 (argo off)::cmd_argo off"
    "更新 cloudflared 官方内核 (argo update)::cmd_argo update"
    "WARP 出站解锁 (warp)::menu_choose MENU_WARP")

  MENU_WARP=("WARP 出站解锁"
    "查看状态::cmd_warp status"
    "更新::cmd_warp update")
}
_menu_define

cmd_menu() {
  local choice
  while true; do
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}           xray-xhttp 全能管理终端 (v${XH_VERSION:-5.2.2})           ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "  ${GREEN}[1]${NC} 节点与订阅管理 (Nodes & Subscriptions)"
    echo -e "  ${GREEN}[2]${NC} 链路测速与性能审计 (Benchmark & Audit)"
    echo -e "  ${GREEN}[3]${NC} 系统网络与流控调优 (Network & Tuning)"
    echo -e "  ${GREEN}[4]${NC} Cloudflare 智能优选与证书 (Cloudflare & Certs)"
    echo -e "  ${GREEN}[5]${NC} 服务生命周期与自愈 (Service & System)"
    echo -e "  ${GREEN}[6]${NC} 高级隧道与扩展网络 (Argo & WARP)"
    echo -e "  ${RED}[7]${NC} 卸载与清理 (Uninstall)"
    echo -e "  ${YELLOW}[0]${NC} 退出终端 (Exit)"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    echo -e "  快捷直达: 11(状态) 12(节点) 13(订阅) 14(重启) 15(日志) 16(测速)"
    read -rp "请选择操作分类 [0-7] 或快捷数字: " choice || break

    case "$choice" in
      1) menu_loop MENU_NODE ;;
      2) menu_loop MENU_PERF ;;
      3) menu_loop MENU_NET ;;
      4) menu_loop MENU_CF ;;
      5) menu_loop MENU_SVC ;;
      6) menu_loop MENU_TUNNEL ;;
      7)
        cmd_uninstall
        break
        ;;
      0)
        break
        ;;
      # 快捷直达
      11) cmd_status ;;
      12) cmd_info ;;
      13) cmd_sub ;;
      14) cmd_restart ;;
      15) cmd_log xray ;;
      16) cmd_bench ;;
      *)
        warn "无效选择"
        ;;
    esac
  done
}
