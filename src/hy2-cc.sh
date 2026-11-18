# Hysteria2 服务端 quicParams 的拥塞控制片段（含行尾逗号），供安装脚本与 xh 的入站模板共用。
# 默认 bbr；HY2_UP_MBPS / HY2_DOWN_MBPS 显式设置时改 brutal，与客户端链接（hy2_client_fm_param）声明的带宽一致。
# 方向以服务端为视角：brutalUp = 服务端发往客户端 = 客户端下载 = HY2_DOWN_MBPS；
#                     brutalDown = 客户端上传 = HY2_UP_MBPS。
# 实测（Xray 26.11.9，本机回环）：服务端 brutalUp=100mbps 时客户端下载封顶 12.8MB/s，brutalDown=100mbps 不影响下载；
# 客户端 brutalDown=100mbps 同样封顶下载。方向写反会让上下行限速互换。
# 当前拥塞控制的人类可读描述（菜单 / 状态页用），与 hy2_cc_json 同一判据。
hy2_cc_label() {
  if [[ -n "${HY2_UP_MBPS:-}${HY2_DOWN_MBPS:-}" ]]; then
    printf 'Brutal（上行 %s / 下行 %s Mbps）' "${HY2_UP_MBPS:-未设}" "${HY2_DOWN_MBPS:-未设}"
  else
    printf 'BBR（自适应）'
  fi
}

hy2_cc_json() {
  local ind='                        '
  if [[ -n "${HY2_UP_MBPS:-}${HY2_DOWN_MBPS:-}" ]]; then
    printf '"congestion": "brutal",'
    if [[ -n "${HY2_DOWN_MBPS:-}" ]]; then printf '\n%s"brutalUp": "%smbps",' "$ind" "$HY2_DOWN_MBPS"; fi
    if [[ -n "${HY2_UP_MBPS:-}" ]]; then printf '\n%s"brutalDown": "%smbps",' "$ind" "$HY2_UP_MBPS"; fi
  else
    printf '"congestion": "bbr",'
  fi
}
