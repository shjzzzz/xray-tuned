# ==================================================
# REALITY 兼容内核（xray-legacy）：新内核拒绝不带 X25519MLKEM768 的客户端
# ==================================================
# xtls/reality 自 2026-09-08（Xray 26.9.9+）起，服务端直接拒绝没有 X25519MLKEM768 key share 的 ClientHello，
# Shadowrocket 等 utls 指纹较旧的客户端连不上 REALITY，minClientVer 也无法绕过。
# 做法：config.json 仍是唯一真源；xh-split-config 在服务启动前把 security=reality 的入站拆给兼容内核
# （XRAY_LEGACY_VERSION，默认 26.7.28，最后一个不做该检查的正式版），其余入站留给最新内核。
# 两个实例经 PartOf 联动，xh 里所有 systemctl restart xray 照常生效。FEATURE_REALITY_LEGACY=false 可关闭。
FEATURE_REALITY_LEGACY="${FEATURE_REALITY_LEGACY:-true}"
XRAY_LEGACY_VERSION="${XRAY_LEGACY_VERSION:-26.7.28}"

setup_reality_legacy() {
  [[ "$FEATURE_REALITY_LEGACY" == true ]] || return 0
  [[ "$SERVICE_TYPE" == "systemd" ]] || { warn "兼容内核仅支持 systemd，已跳过"; return 0; }
  command -v python3 >/dev/null 2>&1 || pkg_install python3 >/dev/null 2>&1 || { warn "缺少 python3，跳过兼容内核"; return 0; }
  grep -q '"security"[[:space:]]*:[[:space:]]*"reality"' /usr/local/etc/xray/config.json 2>/dev/null || return 0

  local cur arch asset tmp
  cur=$(/usr/local/bin/xray-legacy version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ "$cur" != "$XRAY_LEGACY_VERSION" ]]; then
    case "$(uname -m)" in
      x86_64|amd64)  asset="Xray-linux-64.zip" ;;
      aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
      *) warn "兼容内核不支持架构 $(uname -m)，已跳过"; return 0 ;;
    esac
    command -v unzip >/dev/null 2>&1 || pkg_install unzip >/dev/null 2>&1 || true
    tmp=$(mktemp -d)
    if curl -fsSL --retry 3 --max-time 120 "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_LEGACY_VERSION}/${asset}" -o "$tmp/x.zip" \
       && curl -fsSL --max-time 30 "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_LEGACY_VERSION}/${asset}.dgst" -o "$tmp/x.dgst" \
       && [[ "$(sha256sum "$tmp/x.zip" | cut -d' ' -f1)" == "$(grep -i '^SHA2-256=' "$tmp/x.dgst" | head -1 | cut -d= -f2 | tr -d ' ')" ]] \
       && unzip -qo "$tmp/x.zip" xray -d "$tmp"; then
      install -m 755 "$tmp/xray" /usr/local/bin/xray-legacy
      info "已安装 REALITY 兼容内核 xray-legacy ${XRAY_LEGACY_VERSION}"
    else
      rm -rf "$tmp"; warn "兼容内核下载或校验失败，REALITY 仍由新内核承载（部分客户端可能连不上）"; return 0
    fi
    rm -rf "$tmp"
  fi

  cat > /usr/local/sbin/xh-split-config <<'XH_SPLIT_EOF'
@@include templates/xh-split-config.py
XH_SPLIT_EOF
  chmod 755 /usr/local/sbin/xh-split-config

  mkdir -p /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/xray.service.d/20-reality-split.conf <<'SPLITDROPEOF'
# REALITY 入站拆给兼容内核 xray-legacy（见 /usr/local/sbin/xh-split-config）；本实例只跑其余入站。
[Unit]
Wants=xray-reality.service

[Service]
ExecStartPre=
ExecStartPre=+/usr/local/sbin/xh-split-config
ExecStart=
ExecStart=/usr/local/bin/xray run -config /run/xray-split/main.json
SPLITDROPEOF
  cat > /etc/systemd/system/xray-reality.service <<'REALITYUNITEOF'
[Unit]
Description=Xray REALITY (legacy core, accepts clients without X25519MLKEM768)
After=network.target nss-lookup.target
PartOf=xray.service
StartLimitIntervalSec=0

[Service]
User=xray
Group=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
UMask=0077
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
ExecStartPre=+/usr/local/sbin/xh-split-config
ExecStart=/usr/local/bin/xray-legacy run -config /run/xray-split/reality.json
Restart=always
RestartSec=2
LimitNOFILE=1048576
LimitNPROC=infinity
Nice=-10
Environment="GOGC=200"
Environment="GOMAXPROCS=4"
Environment="GODEBUG=madvdontneed=1"

[Install]
WantedBy=multi-user.target
REALITYUNITEOF
  systemctl daemon-reload
  systemctl enable xray-reality.service >/dev/null 2>&1 || true
  info "REALITY 已拆给兼容内核 xray-legacy ${XRAY_LEGACY_VERSION}（xray-reality.service），其余入站仍由最新内核承载"
}
setup_reality_legacy
