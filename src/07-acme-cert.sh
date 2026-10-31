# ==================================================
# 证书申请与复用
# ==================================================

info "[2/7] 申请 / 复用 SSL 证书"

if [[ ! -x /root/.acme.sh/acme.sh ]] && ! command -v acme.sh >/dev/null 2>&1; then
  curl -fsSL https://get.acme.sh | sh
fi
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

acme.sh --set-default-ca --server letsencrypt

prefer_ipv4_for_acme() {
  if [[ "$IP_CHOICE" == "1" ]] && ! grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null; then
    echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
  fi
}

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"
ACME_CERT_CONF="${ACME_CERT_HOME}/${REALITY_DOMAIN}.conf"

have_existing_dual_cert() {
  [[ -f "$ACME_CERT_CONF" ]] || return 1
  [[ -f "$ACME_CERT_HOME/fullchain.cer" ]] || return 1
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" ]] || return 1

  openssl x509 -in "$ACME_CERT_HOME/fullchain.cer" -noout -checkend 1209600 >/dev/null 2>&1 || return 1  # 14 天内过期则重签
  local cert_domains
  cert_domains=$(openssl x509 -in "$ACME_CERT_HOME/fullchain.cer" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,[:space:]]*' | sed 's/^DNS://' || true)
  grep -Fxq "$REALITY_DOMAIN" <<< "$cert_domains" &&
    grep -Fxq "$CDN_DOMAIN" <<< "$cert_domains"
}

issue_dual_cert() {
  local force_flag=""
  # 如果已有旧证书或 conf 但不满足双域名 SAN，必须加 --force 强制覆盖申请，否则 acme.sh 会因未到期直接 skip
  if [[ -f "$ACME_CERT_CONF" || -f "$ACME_CERT_HOME/fullchain.cer" ]]; then
    force_flag="--force"
  fi

  # v4.9.45：传入 CF_Token（Cloudflare API Token，Zone.DNS 编辑权限）时走 DNS-01。
  # CDN 域名开了 Cloudflare 代理（橙云）后，HTTP-01 验证会被 CF 的 Always Use HTTPS
  # 301 到 https 再回源 443，而那里是 Reality / 伪装站，不是 acme.sh 的 80 端口——
  # 首次签发时若还是灰云能成功，60 天后自动续期必败，证书到期当天 CDN 526、
  # h3-direct / hy2 握手失败。DNS-01 与代理状态无关，续期时也不必停 nginx。
  # acme.sh 会把 CF_Token 存进 account.conf（SAVED_CF_Token），续期自动沿用。
  if [[ -n "${CF_Token:-}" ]]; then
    acme.sh --issue --dns dns_cf -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --keylength ec-256 $force_flag
    return
  fi

  if [[ "$IP_CHOICE" == "2" ]]; then
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v6 --keylength ec-256 $force_flag \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  else
    prefer_ipv4_for_acme
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v4 --request-v4 --keylength ec-256 $force_flag \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  fi
}

detect_install_cert() {
  # 1. 优先检查 /root/ygkkkca/ (Acme-yg 证书库)
  if [[ -f "/root/ygkkkca/cert.crt" && -f "/root/ygkkkca/private.key" ]]; then
    if openssl x509 -in "/root/ygkkkca/cert.crt" -noout -checkend 86400 >/dev/null 2>&1; then
      printf '%s:%s:%s' "/root/ygkkkca/cert.crt" "/root/ygkkkca/private.key" "Acme-yg 证书库 (/root/ygkkkca/)"
      return 0
    fi
  fi
  # 2. 检查 /etc/ssl/private/ (生产已有有效证书)
  if [[ -f "/etc/ssl/private/fullchain.cer" && -f "/etc/ssl/private/private.key" ]]; then
    if openssl x509 -in "/etc/ssl/private/fullchain.cer" -noout -checkend 86400 >/dev/null 2>&1; then
      printf '%s:%s:%s' "/etc/ssl/private/fullchain.cer" "/etc/ssl/private/private.key" "现有生产证书 (/etc/ssl/private/)"
      return 0
    fi
  fi
  # 3. 检查 acme.sh 官方双域名证书
  if have_existing_dual_cert; then
    printf '%s:%s:%s' "$ACME_CERT_HOME/fullchain.cer" "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" "acme.sh 双域名证书"
    return 0
  fi
  return 1
}

local_cert_meta=""
if local_cert_meta=$(detect_install_cert); then
  _c="${local_cert_meta%%:*}"
  _rest="${local_cert_meta#*:}"
  _k="${_rest%%:*}"
  _desc="${_rest#*:}"
  info "检测到可复用有效证书（${_desc}），自动复用并部署，跳过重新申请"
  mkdir -p /etc/ssl/private
  cp -f "$_c" /etc/ssl/private/fullchain.cer
  cp -f "$_k" /etc/ssl/private/private.key
  chmod 644 /etc/ssl/private/fullchain.cer 2>/dev/null || true
  chmod 640 /etc/ssl/private/private.key 2>/dev/null || true
  chown root:xray /etc/ssl/private/private.key 2>/dev/null || true
else
  if [[ -n "${CF_Token:-}" ]]; then
    info "未检测到可复用证书，使用 Cloudflare DNS-01 申请（CF_Token 已提供）..."
  else
    info "未检测到可复用证书，开始自动申请 (需要 80 端口空闲)..."
  fi
  if ! ISSUE_OUTPUT=$(issue_dual_cert 2>&1); then
    echo "$ISSUE_OUTPUT"
    warn "双域名证书自动申请未成功（通常是 80 端口占用或 CDN 域名已开启代理）"
    if [[ "$AUTO" != "1" ]]; then
      read -rp "是否立即调用 Acme-yg 证书全能向导完成申请？[Y/n]: " run_yg
      if [[ "${run_yg:-y}" =~ ^[Yy]$ ]]; then
        info "正在唤起 Acme-yg 证书向导..."
        bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
        if [[ -f "/root/ygkkkca/cert.crt" && -f "/root/ygkkkca/private.key" ]]; then
          info "Acme-yg 证书已生成，自动导入生产目录..."
          mkdir -p /etc/ssl/private
          cp -f /root/ygkkkca/cert.crt /etc/ssl/private/fullchain.cer
          cp -f /root/ygkkkca/private.key /etc/ssl/private/private.key
          chmod 644 /etc/ssl/private/fullchain.cer 2>/dev/null || true
          chmod 640 /etc/ssl/private/private.key 2>/dev/null || true
          chown root:xray /etc/ssl/private/private.key 2>/dev/null || true
        fi
      fi
    fi
    if [[ ! -f "/etc/ssl/private/fullchain.cer" ]] && ! have_existing_dual_cert; then
      error "证书申请失败且未获取到有效证书。装完后可通过 xh cert apply 重新配置"
    fi
  else
    echo "$ISSUE_OUTPUT"
  fi
fi

if [[ -z "${CF_Token:-}" ]] && ! grep -q "^Le_Webroot='dns_" "$ACME_CERT_CONF" 2>/dev/null; then
  warn "证书续期方式为 standalone（HTTP-01）：CDN 域名开启 Cloudflare 代理后自动续期会失败"
  warn "装完后执行 CF_Token=<API Token> ${MANAGE_CMD:-xh} cert dnscf 切换为 DNS-01（xh diag 会持续检查）"
fi

echo ""

# ==================================================
# 证书链裁剪脚本落地（握手提速，v4.9.0）
# ==================================================
# Let's Encrypt 的 fullchain 末尾带交叉签名的根证书（ISRG Root X2 by X1）。
# 根证书本来就该由客户端信任库提供，服务端每次握手重传一遍纯属浪费。
# 对 QUIC（h3-direct / Hysteria2 / CDN-H3）尤其贵：客户端地址被验证前，
# 服务端受 3 倍放大限制，首包群越大越容易多吃一个 RTT。
#
# 实测本域证书 4 张 → 3 张、4841 → 3243 字节，每次握手少传 1598 字节；
# 单条 TLS 1.3 握手服务端出向字节数 5509 → 4364（tcpdump 实测）。
# 再往下裁不动：只留 leaf + YE2 时 openssl verify 直接失败（Root YE 尚未进
# 主流信任库），脚本会自己停手——它的判据是「从尾部逐张试删、每删一张验一次」，
# 不是按张数写死的，所以换签发方 / 换根证书都不需要改这里。
#
# 必须落成独立文件而不是内联进 reloadcmd：install.sh 是 src/*.sh 拼出来的单文件，
# 装完就没了，而续期发生在几十天以后，那时只有 /usr/local/sbin 里的这份还在。
install -d /usr/local/sbin
cat > /usr/local/sbin/xh-trim-chain <<'XH_TRIM_CHAIN_EOF'
#!/bin/sh
# xh-trim-chain <fullchain.pem>
#
# 从证书链尾部逐张试删，每删一张就拿本机信任库验一次；验得过才落实，
# 验不过立刻停手。裁掉的都是客户端信任库里本来就有的根证书，服务端每次
# 握手重传一遍纯属浪费。对 QUIC（h3 / hy2 / tuic）尤其贵：QUIC 在客户端
# 地址被验证前有 3 倍放大限制，服务端首包群越大越容易多吃一个 RTT。
#
# 判据不能用「自签根」：Let's Encrypt 链尾那张是交叉签名的
# （ISRG Root X2 由 X1 签发），subject != issuer，按自签找一张都裁不掉。
# 找不到 CA bundle 时直接放弃裁剪——宁可慢一点，也不能生成连不上的链。
set -u
f="${1:-}"
[ -n "$f" ] && [ -s "$f" ] || exit 0
command -v openssl >/dev/null 2>&1 || exit 0

bundle=""
for b in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
         /etc/ssl/cert.pem /etc/ssl/certs/ca-bundle.crt; do
  [ -s "$b" ] && { bundle="$b"; break; }
done
[ -n "$bundle" ] || exit 0

d=$(mktemp -d) || exit 0
trap 'rm -rf "$d"' EXIT
awk -v d="$d" 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} n>0{print > (d "/c" n ".pem")}' "$f"
n=$(find "$d" -name 'c*.pem' | wc -l)
[ "$n" -ge 2 ] || exit 0

# 注意：POSIX sh 的函数没有局部变量，这里刻意用 _ck / _ci 而不是 keep / i——
# 早先版本在函数里复用了外层的 keep，函数每调一次就把外层游标改掉，
# 结果验证失败也照样把链砍短了一张（实测把 3 张链砍成 2 张，客户端验不过）。
chain_ok() {
  _ck=$1; _ci=2; set --
  while [ "$_ci" -le "$_ck" ]; do set -- "$@" -untrusted "$d/c$_ci.pem"; _ci=$((_ci+1)); done
  openssl verify -CAfile "$bundle" "$@" "$d/c1.pem" >/dev/null 2>&1
}

# 完整链本来就验不过（私有 CA / 缺中间证书）就别动它
chain_ok "$n" || exit 0

keep=$n
while [ "$keep" -gt 1 ] && chain_ok $((keep-1)); do keep=$((keep-1)); done
[ "$keep" -lt "$n" ] || exit 0

tmp="$d/trimmed.pem"; i=1; : > "$tmp"
while [ "$i" -le "$keep" ]; do cat "$d/c$i.pem" >> "$tmp"; i=$((i+1)); done
before=$(wc -c < "$f"); after=$(wc -c < "$tmp")
cp -f "$f" "$f.full" 2>/dev/null
cat "$tmp" > "$f"
chmod 644 "$f" "$f.full" 2>/dev/null   # 证书链是公开内容；xray 以 xray 用户运行，必须可读（600 会让续期后 xray 起不来）
echo "证书链已裁剪：$n → $keep 张（${before} → ${after} 字节，每次握手少传 $((before-after)) 字节）"
XH_TRIM_CHAIN_EOF
chmod 755 /usr/local/sbin/xh-trim-chain
