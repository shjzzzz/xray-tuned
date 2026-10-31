# ==================================================
# 交互式分类导航主菜单 (Interactive Categorized Menu)
# ==================================================

cmd_menu() {
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
    read -rp "请选择操作分类 [0-7] 或快捷数字: " choice

    case "$choice" in
      1)
        while true; do
          echo ""
          echo -e "${CYAN}--- [1] 节点与协议矩阵管理 ---${NC}"
          echo "  1) 查看全部节点参数与客户端链接 (info)"
          echo "  2) 查看订阅链接与全端二维码 (sub)"
          echo "  3) 重新生成全量订阅文件 (resub)"
          echo "  4) Reality 核心节点管理 (show / vision on|off / xhttp on|off)"
          echo "  5) 上下行分离节点管理 (split: reality-up / cdn-up)"
          echo "  6) Hysteria2 直连与混淆管理 (hy2 on|off / obfs on|off)"
          echo "  7) XHTTP-Direct-H2 直连管理 (h2direct on|off)"
          echo "  8) CDN TCP(h2) / QUIC(h3) 节点开关 (cdnh2 / cdnh3)"
          echo "  9) Reality 兼容模式与最低版本 (minversion 1.8.0)"
          echo " 10) Reality 时间差校验 (timediff on [毫秒] / off)"
          echo " 11) 出站分流开关 (屏蔽回国 IP / 广告域名: block cn|ads)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-11]: " n_sub
          case "$n_sub" in
            1) cmd_info ;;
            2) cmd_sub ;;
            3) cmd_resub ;;
            4) read -rp "  show / vision on|off / xhttp on|off / updown on|off: " a; cmd_reality ${a:-show} ;;
            5)
              echo "  1) 上行 Reality / 下行 CDN (reality-up on|off)"
              echo "  2) 上行 CDN / 下行 Reality (cdn-up on|off)"
              read -rp "  请选择 [1-2]: " s_act
              case "$s_act" in
                1) read -rp "    show / on / off: " a; cmd_split reality-up "${a:-show}" ;;
                2) read -rp "    show / on / off: " a; cmd_split cdn-up "${a:-show}" ;;
                *) cmd_split show ;;
              esac
              ;;
            6)
              echo "  1) 查看 Hysteria2 状态 (show)"
              echo "  2) 开启 Hysteria2 直连节点 (hy2 on)"
              echo "  3) 关闭全部 Hysteria2 节点 (hy2 off)"
              echo "  4) 开启 Hysteria2 混淆节点 (hy2 obfs on)"
              echo "  5) 关闭 Hysteria2 混淆节点 (hy2 obfs off)"
              read -rp "  请选择 [1-5]: " h_act
              case "$h_act" in
                1) cmd_hy2 show ;;
                2) cmd_hy2 on ;;
                3) cmd_hy2 off ;;
                4) cmd_hy2 obfs on ;;
                5) cmd_hy2 obfs off ;;
                *) cmd_hy2 show ;;
              esac
              ;;
            7) read -rp "  show / on / off: " a; cmd_h2direct "${a:-show}" ;;
            8)
              echo "  1) CDN TCP(h2) 节点 (cdnh2 on|off)"
              echo "  2) CDN QUIC(h3) 节点 (cdnh3 on|off)"
              read -rp "  请选择 [1-2]: " c_act
              case "$c_act" in
                1) read -rp "    show / on / off: " a; cmd_cdnh2 "${a:-show}" ;;
                2) read -rp "    show / on / off: " a; cmd_cdnh3 "${a:-show}" ;;
              esac
              ;;
            9) read -rp "  show / on / off / 版本号: " a; cmd_minversion "${a:-show}" ;;
            10) read -rp "  show / on [毫秒] / off: " a; cmd_timediff ${a:-show} ;;
            11) read -rp "  show / cn on|off / ads on|off: " a; cmd_block ${a:-show} ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
      2)
        while true; do
          echo ""
          echo -e "${CYAN}--- [2] 链路测速与性能审计 ---${NC}"
          echo "  1) 🚀 节点全量真实网速与吞吐压测 (bench / speed)"
          echo "  2) 🔍 只读全栈系统与网络性能审计 (audit)"
          echo "  3) 🌐 UDP 节点全协议连通性自检 (diag)"
          echo "  4) ⚠️ sysctl 参数冲突与覆盖检测 (conflict)"
          echo "  5) 🔌 端口占用与冲突检测 (portconflict)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-5]: " b_sub
          case "$b_sub" in
            1)
              read -rp "  输入关键词过滤测速(直接回车全量测速): " b_flt
              cmd_bench "${b_flt}"
              ;;
            2) cmd_audit ;;
            3) cmd_diag ;;
            4) cmd_conflict ;;
            5) cmd_portconflict ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
      3)
        while true; do
          echo ""
          echo -e "${CYAN}--- [3] 系统网络与流控调优 ---${NC}"
          echo "  1) 系统层流控调优 show / on / off (BBRv3 + FQ + 128MB缓冲区)"
          echo "  2) TCP Brutal 极速加速模式与速率调节 (brutal)"
          echo "  3) TCP ECN 显式拥塞通知开关 (ecn show / on / off)"
          echo "  4) 客户端本地网络调优指南 (client: win / mac / linux / sb)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-4]: " t_sub
          case "$t_sub" in
            1) read -rp "  show / on / off: " a; cmd_tuning "${a:-show}" ;;
            2) read -rp "  show / on / off / speed: " a; cmd_brutal "${a:-show}" ;;
            3) read -rp "  show / on / off: " a; cmd_ecn "${a:-show}" ;;
            4) read -rp "  平台类型 (win / mac / linux / sb): " a; cmd_tuning "${a:-client}" ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
      4)
        while true; do
          echo ""
          echo -e "${CYAN}--- [4] Cloudflare 智能优选与证书 ---${NC}"
          echo "  1) 查看当前优选 IP 状态与解析 (bestcf show)"
          echo "  2) 锁定当前优选 IP (bestcf lock: 禁止自动轮换)"
          echo "  3) 解锁恢复定时自适应轮换 (bestcf unlock)"
          echo "  4) 手动自定义优选 IP 并锁定 (bestcf set)"
          echo "  5) 调整优选 IP 定时轮换周期 (bestcf interval)"
          echo "  6) 立即执行链路延迟与握手健康检测 (bestcf check)"
          echo "  7) 立即强制重新测速并更新 DNS (bestcf run)"
          echo "  8) Cloudflare DNS 全面规范性体检 (bestcf audit)"
          echo "  9) 配置 Cloudflare 凭据与域名 (bestcf setup)"
          echo " 10) 证书续期方式查看 / 切换 DNS-01 (cert: show / dnscf)"
          echo " 11) Cloudflare CDN ECH 加密 SNI 开关 (ech show / on / off)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-11]: " c_sub
          case "$c_sub" in
            1) cmd_bestcf show ;;
            2) cmd_bestcf lock ;;
            3) cmd_bestcf unlock ;;
            4) cmd_bestcf set ;;
            5) cmd_bestcf interval ;;
            6) cmd_bestcf check ;;
            7) cmd_bestcf run ;;
            8) cmd_bestcf audit ;;
            9) cmd_bestcf setup ;;
            10) read -rp "  show / dnscf: " a; cmd_cert "${a:-show}" ;;
            11) read -rp "  show / on / off: " a; cmd_ech "${a:-show}" ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
      5)
        while true; do
          echo ""
          echo -e "${CYAN}--- [5] 服务生命周期与系统运维 ---${NC}"
          echo "  1) 查看服务与流控运行状态 (status)"
          echo "  2) 查看运行日志 (log: xray / nginx)"
          echo "  3) 重启全部服务 (restart)"
          echo "  4) 启动服务 (start) / 停止服务 (stop)"
          echo "  5) 更新 Xray-core 内核版本 (update [ver|pre])"
          echo "  6) Nginx 版本检查与升级编译 (nginx show / check / update)"
          echo "  7) 保活自愈服务管理 (keepalive on / off / show)"
          echo "  8) 内核每周自动更新设置 (autoupdate on / off / show)"
          echo "  9) 执行一次异常守护检查 (guard)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-9]: " s_sub
          case "$s_sub" in
            1) cmd_status ;;
            2) read -rp "  服务名称 (xray / nginx): " a; cmd_log "${a:-xray}" ;;
            3) cmd_restart ;;
            4)
              echo "  1) 启动 (start)"
              echo "  2) 停止 (stop)"
              read -rp "  请选择: " st_act
              [[ "$st_act" == "1" ]] && cmd_start
              [[ "$st_act" == "2" ]] && cmd_stop
              ;;
            5) read -rp "  回车更新正式版，或指定版本(如 pre, 26.10.29): " a; cmd_update "${a}" ;;
            6) read -rp "  show / check / update: " a; cmd_nginx "${a:-show}" ;;
            7) read -rp "  on / off / show: " a; cmd_keepalive "${a:-show}" ;;
            8) read -rp "  show / on / off / stable / pre: " a; cmd_autoupdate "${a:-show}" ;;
            9) cmd_guard ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
      6)
        while true; do
          echo ""
          echo -e "${CYAN}--- [6] 高级隧道与扩展网络 ---${NC}"
          echo "  1) 查看 Cloudflare Argo 隧道状态 (argo status)"
          echo "  2) 开启/配置 Argo 隧道 (argo on)"
          echo "  3) 关闭 Argo 隧道 (argo off)"
          echo "  4) 更新 cloudflared 官方内核 (argo update)"
          echo "  5) WARP 出站解锁状态与配置 (warp status / on / off / update)"
          echo "  0) 返回上一级菜单"
          read -rp "请选择 [0-5]: " a_sub
          case "$a_sub" in
            1) cmd_argo status ;;
            2) cmd_argo on ;;
            3) cmd_argo off ;;
            4) cmd_argo update ;;
            5) read -rp "  status / on / off / update: " w_act; cmd_warp "${w_act:-status}" ;;
            0) break ;;
            *) warn "无效选择" ;;
          esac
        done
        ;;
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
