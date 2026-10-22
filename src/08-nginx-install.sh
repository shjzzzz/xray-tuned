# ==================================================
# Nginx 编译安装与服务配置
# ==================================================

info "[3/7] 编译安装 Nginx"
NGINX_VER="1.31.6"
NGINX_PGP_KEYS="${NGINX_PGP_KEYS:-pluknet arut thresh sb}"
NGINX_PGP_FPRS="${NGINX_PGP_FPRS:-D6786CE303D9A9022998DC6CC8464D549AF75C0A 43387825DDB1BB97EC36BA5D007C8D7C15D87369 13C82A63B603576156E30A4EA0EA981B66B0D967 7338973069ED3F443F4D37DFA64FD5B17ADB39A8}"

nginx_verify_pgp() {
  local tgz="$1" asc="$2" gh k fpr ok=1
  command -v gpg >/dev/null 2>&1 || { warn "未安装 gpg，无法校验 nginx 签名"; return 1; }
  gh=$(mktemp -d) && chmod 700 "$gh"
  for k in $NGINX_PGP_KEYS; do
    curl -fsSL --max-time 20 "https://nginx.org/keys/${k}.key" 2>/dev/null | GNUPGHOME="$gh" gpg -q --batch --import 2>/dev/null
  done
  fpr=$(GNUPGHOME="$gh" gpg --batch --status-fd 1 --verify "$asc" "$tgz" 2>/dev/null | awk '$2=="VALIDSIG"{print $NF}')
  rm -rf "$gh"
  if [[ -n "$fpr" ]] && [[ " $NGINX_PGP_FPRS " == *" $fpr "* ]]; then
    info "nginx 源码 PGP 签名校验通过（签名者主指纹 ${fpr}）"; ok=0
  else
    warn "nginx 源码 PGP 签名校验失败（签名者：${fpr:-无有效签名}），拒绝使用"
  fi
  return $ok
}

install_nginx() {
  info "安装编译依赖..."
  install_build_deps
  command -v gpg >/dev/null 2>&1 || pkg_install gnupg >/dev/null 2>&1 || true

  local tmpdir
  tmpdir=$(mktemp -d)
  chmod 700 "$tmpdir"

  info "下载 Nginx ${NGINX_VER} 源码与 PGP 签名..."
  if ! curl -fsSL --max-time 120 "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz" -o "$tmpdir/nginx.tar.gz" || \
     ! curl -fsSL --max-time 30 "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz.asc" -o "$tmpdir/nginx.tar.gz.asc"; then
    rm -rf "$tmpdir"
    error "下载 Nginx 源码包或签名失败"
  fi

  if ! nginx_verify_pgp "$tmpdir/nginx.tar.gz" "$tmpdir/nginx.tar.gz.asc"; then
    rm -rf "$tmpdir"
    error "Nginx 源码 PGP 签名验证失败，已中止安装"
  fi

  tar -xf "$tmpdir/nginx.tar.gz" -C "$tmpdir"
  cd "$tmpdir/nginx-${NGINX_VER}"

  info "编译 Nginx ${NGINX_VER} ..."
  ./configure \
    --prefix=/usr/local/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --with-cc-opt="-Wno-error" \
    --with-http_stub_status_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_sub_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-http_v2_module \
    --with-http_v3_module

  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  make install

  cd /root
  rm -rf "$tmpdir"
  mkdir -p /var/log/nginx

  info "创建 ${SERVICE_TYPE} 服务..."
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    cat > /etc/init.d/nginx << 'SERVICEEOF'
#!/sbin/openrc-run

name="nginx"
description="Nginx web server"
command="/usr/sbin/nginx"
command_args="-g 'daemon off; master_process on;'"
command_background="yes"
pidfile="/run/nginx.pid"
required_files="/etc/nginx/nginx.conf"
extra_started_commands="reload"

depend() {
    need net
}

start_pre() {
    checkpath --directory --mode 0755 /run
    /usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
}

reload() {
    start_pre || return 1
    ebegin "Reloading nginx"
    /usr/sbin/nginx -s reload
    eend $?
}
SERVICEEOF
    chmod +x /etc/init.d/nginx
    service_enable nginx
  else
    cat > /etc/systemd/system/nginx.service << 'SERVICEEOF'
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/bin/kill -s QUIT $MAINPID
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    service_enable nginx.service
  fi
  echo ""
}

if command -v nginx >/dev/null 2>&1 &&
   nginx -v 2>&1 | grep -Fq "nginx/${NGINX_VER}" &&
   nginx -V 2>&1 | grep -q -- '--with-http_v3_module'; then
  info "Nginx ${NGINX_VER} 已安装，跳过编译"
else
  install_nginx
fi
