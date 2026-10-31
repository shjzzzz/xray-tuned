# ==================================================
# 命令行参数帮助与顶级分发器 (CLI Usage & Dispatcher)
# ==================================================

usage() {
  cat << USAGEEOF
xray-xhttp 全能管理命令 (v${XH_VERSION:-5.2.2})

【基础运维与状态】
  xh                    进入交互式全功能分层导航终端
  xh help [<命令>]      显示全部命令；带命令名时只显示该命令的用法 (也可 xh <命令> --help)
  xh status             查看服务运行状态、监听端口与流控指标
  xh info               查看当前全部节点参数与明文链接
  xh sub                查看订阅链接与多端二维码
  xh resub              按当前配置重新生成全量订阅文件 (v2rayN/Mihomo/小火箭)
  xh start | stop | restart  服务启动 / 停止 / 重启
  xh log [xray|nginx] [行数] 查看实时运行日志 (默认 50 行)
  xh update [<ver>] [--auto] 更新 Xray-core 内核版本 (支持 pre 尝鲜版)
  xh uninstall          卸载全部组件并清理配置

【链路压测与性能审计 (集成)】
  xh bench [<filter>]   🚀 真实端到端网速压测 (50MB下行/10MB上行/TTFB/延时)，别名: xh speed
  xh audit              🔍 只读全栈系统性能审计 (CPU拓扑/中断平衡/BBRv3/NAPI队列)
  xh diag               UDP 与 HTTP/3 节点连通性链路自检
  xh conflict           sysctl 内核参数冲突与覆盖检测
  xh portconflict       系统端口占用排查

【节点与协议矩阵管理】
  xh reality [show|vision on|off|xhttp on|off]  Reality 核心节点管理
  xh split [show|reality-up on|off|cdn-up on|off] 上下行分离节点开关
  xh hy2 [show|on|off]  Hysteria2 原生直连节点开关
  xh hy2 obfs [on|off]  Hysteria2 Salamander 混淆节点开关 (别名: xh hy2obfs)
  xh h2direct [on|off]  XHTTP-Direct-H2 直连节点开关
  xh cdnh2 [on|off]     CDN TCP(h2) 节点开关
  xh cdnh3 [on|off]     CDN QUIC(h3) 节点开关
  xh minversion [show|on|off|<ver>] Reality 客户端最低版本控制 (1.8.0 兼容模式)
  xh timediff [show|on [毫秒]|off]  Reality maxTimeDiff 时间差校验
  xh ech [show|on|off]  Cloudflare CDN ECH 加密 SNI 开关
  xh block [show|cn on|off|ads on|off]  出站屏蔽回国 IP / 广告域名

【网络流控调优与加速】
  xh tuning [show|on|off|client|win|mac|linux|sb]  系统级流控调优与多端网络指南
  xh brutal [show|on|off|speed|add|del|update]     TCP Brutal 极速拥塞控制模式
  xh ecn [show|on|off]  TCP ECN 显式拥塞通知开关

【Cloudflare 智能生态与隧道】
  xh bestcf [show|lock|unlock|set|interval|check|run|audit|setup|on|off]  优选 IP 智能管理
  xh cert [show|apply|import|renew|dnscf|yg]  SSL证书全生命周期管理 (申请/导入/续期/DNS-01)
  xh nginx [show|check|update]  Nginx mainline 版本检查与自动安全升级
  xh nginx h2only [on|off]      Nginx 强制 HTTP/2 模式
  xh argo [status|on|off|update] Cloudflare Argo 穿透隧道管理
  xh warp [status|update] WARP 出站解锁流媒体与 AI

【自愈与自动化维护】
  xh guard              执行异常健康检查并自动拉起异常服务 (cron 调用)
  xh keepalive [on|off|show]  保活守护自愈开关 (每 5 分钟 + 开机自启)
  xh autoupdate [on|off|show] 每周日 04:00 自动更新 Xray-core 内核
  xh version            查看当前管理工具与节点版本
USAGEEOF
}

# usage_for <命令>：只显示 usage() 里属于该命令的行（含"别名: xh <命令>"）；没有则返回 1。
usage_for() {
  local lines
  [[ "$1" =~ ^[a-z0-9_-]+$ ]] || return 1
  lines=$(usage | grep -E "^  xh $1( |\$)|别名: xh $1\b") || return 1
  echo "$lines"
}

# xh <命令> -h|--help 只查看用法，不执行命令；usage 里没有的命令照旧交给下面的分发。
case "${2:-}" in
  -h|--help) usage_for "${1:-}" && exit 0 ;;
esac

case "${1:-}" in
  status)     cmd_status ;;
  info)       cmd_info ;;
  sub)        cmd_sub ;;
  resub)      cmd_resub ;;
  conflict)   cmd_conflict ;;
  portconflict) cmd_portconflict ;;
  diag)       cmd_diag ;;
  bench|speed|test) shift; cmd_bench "$@" ;;
  audit|perf) shift; cmd_audit "$@" ;;
  log)        shift; cmd_log "$@" ;;
  block)      shift; cmd_block "$@" ;;
  timediff)   shift; cmd_timediff "$@" ;;
  restart)    cmd_restart ;;
  start)      cmd_start ;;
  stop)       cmd_stop ;;
  update)     shift; cmd_update "$@" ;;
  tuning|tune) shift; cmd_tuning "$@" ;;
  brutal)     shift; cmd_brutal "$@" ;;
  guard)      cmd_guard ;;
  keepalive)  shift; cmd_keepalive "$@" ;;
  autoupdate) shift; cmd_autoupdate "$@" ;;
  minversion) shift; cmd_minversion "$@" ;;
  cdnh2)      shift; cmd_cdnh2 "$@" ;;
  cdnh3)      shift; cmd_cdnh3 "$@" ;;
  h2direct)   shift; cmd_h2direct "$@" ;;
  hy2)        shift; cmd_hy2 "$@" ;;
  hy2obfs|hy2_obfs) shift; cmd_hy2obfs "$@" ;;
  reality)    shift; cmd_reality "$@" ;;
  split)      shift; cmd_split "$@" ;;
  ech)        shift; cmd_ech "$@" ;;
  ecn)        shift; cmd_ecn "$@" ;;
  nginx)      shift; cmd_nginx "$@" ;;
  cert)       shift; cmd_cert "$@" ;;
  bestcf)     shift; cmd_bestcf "$@" ;;
  argo)       shift; cmd_argo "$@" ;;
  warp)       shift; cmd_warp "$@" ;;
  uninstall)  cmd_uninstall ;;
  version)
    [[ -x "$XRAY_BIN" ]] && "$XRAY_BIN" version | head -1
    echo "xray-xhttp ${XH_VERSION:-unknown} (manage cli)"
    XH_INSTALLED_VER=""
    [[ -f "$NODE_ENV_FILE" ]] && \
      XH_INSTALLED_VER=$(sed -n 's/^PROJECT_VERSION=//p' "$NODE_ENV_FILE" | head -1 | tr -d "\"'")
    if [[ -n "$XH_INSTALLED_VER" && "$XH_INSTALLED_VER" != "${XH_VERSION:-}" ]]; then
      echo "  （本机节点安装于 ${XH_INSTALLED_VER}，之后 xh 被更新过；节点配置不会因 xh 更新而改变）"
    fi
    ;;
  -h|--help)  usage ;;
  help)
    if [[ -z "${2:-}" ]]; then
      usage
    else
      usage_for "$2" || { echo "没有 '$2' 的说明，执行 ${MANAGE_CMD} help 查看全部命令" >&2; exit 1; }
    fi
    ;;
  "")         cmd_menu ;;
  *)          echo "未知命令: $1（执行 ${MANAGE_CMD} help <命令> 查看用法）" >&2; usage; exit 1 ;;
esac
