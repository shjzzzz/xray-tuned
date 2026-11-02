#!/usr/bin/env bash
# xh 开关回归测试：把本机的真实配置拷进临时目录，对每个节点开关做 on/off，
# 每步用 `xray -test` 校验配置、用 PyYAML 校验 Mihomo 文件。不触碰线上任何文件，也不会重启服务。
#
# 用法（在仓库根目录、root 下）：bash tools/xh-sandbox-test.sh
# 要求：本机已按本项目部署（有 /etc/xhttp-cdn、/usr/local/etc/xray/config.json），装有 python3-yaml 与 xray。
# 局限：systemctl / 防火墙 / ss 被替身代替，因此「端口是否真的监听」不在验证范围内。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
[[ $EUID -eq 0 ]] || { echo "需要 root（xh 自身要求）"; exit 2; }
[[ -f /etc/xhttp-cdn/node.env && -f /usr/local/etc/xray/config.json ]] || { echo "未找到本机节点配置"; exit 2; }

S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
mkdir -p "$S"/{etc,xray,home,nginx,shim,build}

OUT_DIR="$S/build" bash "$ROOT/.github/scripts/build-install.sh" >/dev/null || { echo "构建失败"; exit 1; }
bash -n "$S/build/xh" || { echo "xh 语法错误"; exit 1; }

cp -a /etc/xhttp-cdn "$S/etc/"
cp /usr/local/etc/xray/config.json "$S/xray/"
for f in /root/client-config*; do [[ -f "$f" ]] && cp "$f" "$S/home/"; done
mkdir -p "$S/nginx/sub/$(tr -d '\r\n' < "$S/etc/xhttp-cdn/sub_token")"

# 替身：这些命令只回显，不做事。ss 输出为空，避免被线上正在运行的 xray 占用端口干扰「开启」检查。
for c in systemctl ufw iptables ip6tables nft firewall-cmd nginx netfilter-persistent; do
  printf '#!/bin/sh\nexit 0\n' > "$S/shim/$c"
done
cp "$S/shim/systemctl" "$S/shim/ss"; chmod +x "$S/shim/"*

sed -e "s#/etc/xhttp-cdn#$S/etc/xhttp-cdn#g" -e "s#/usr/local/etc/xray#$S/xray#g" \
    -e "s#/home/ubuntu /home/opc /root#$S/home#g" -e "s#/usr/local/nginx/html#$S/nginx#g" \
    "$S/build/xh" > "$S/xh"
chmod +x "$S/xh"

fail=0
check() {  # $1 = 描述
  local chk; chk="$("$XRAY_BIN" -test -config "$S/xray/config.json" 2>&1 | tail -1)"
  if [[ "$chk" != "Configuration OK." ]]; then echo "FAIL $1：xray -test: $chk"; fail=$((fail + 1)); return 1; fi
}
run() {  # $1 = xh 参数串
  local out err
  out="$(cd "$S" && PATH="$S/shim:$PATH" timeout 90 ./xh $1 </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
  err="$(grep -E '\[ERROR\]|失败|拒绝' <<<"$out" | head -2 | cut -c1-120)"
  if [[ -n "$err" ]]; then echo "FAIL xh $1"; sed 's/^/        /' <<<"$err"; fail=$((fail + 1)); return; fi
  check "xh $1" && echo "ok   xh $1"
}

# 结构断言：h3direct 关/开会真的增删带标记的入站与订阅行
n_inb() { grep -c '"port": 8443' "$S/xray/config.json"; }
n_sub() { grep -c '#VLESS-XHTTP-Direct-H3' "$S/home/client-config.txt"; }

for t in "h3direct on" "h3direct off" "h3direct on" \
         "h2direct on" "h2direct off" "hy2 obfs off" "hy2 obfs on" "hy2 h3 off" "hy2 on" "hy2 off" "hy2 on" \
         "cdnh2 on" "cdnh2 off" "cdnh3 on" "cdnh3 off" \
         "pq xhttp on" "pq xhttp off" "pq vision on" "pq vision off" "pq reality off" "pq reality on" \
         "reality vision on" "reality vision off" "reality xhttp off" "reality xhttp on" "reality updown on" "reality updown off" \
         "split reality-up on" "split reality-up off" "split cdn-up on" "split cdn-up off"; do
  run "$t"
  case "$t" in
    "h3direct on")  [[ $(n_inb) -eq 1 && $(n_sub) -eq 1 ]] || { echo "FAIL $t：入站=$(n_inb) 订阅行=$(n_sub)，期望 1/1"; fail=$((fail + 1)); } ;;
    "h3direct off") [[ $(n_inb) -eq 0 && $(n_sub) -eq 0 ]] || { echo "FAIL $t：入站=$(n_inb) 订阅行=$(n_sub)，期望 0/0"; fail=$((fail + 1)); } ;;
    "reality vision off")  # PQ-Vision 与 Vision-Direct 共用 443 的 Vision 客户端项，PQ-Vision 开着时不能被删
      if grep -q "^FEATURE_REALITY_PQ_VISION=.\?true" "$S/etc/xhttp-cdn/node.env" \
         && ! grep -q '>>xh:realityvision' "$S/xray/config.json"; then
        echo "FAIL $t：PQ-Vision 开着，但 443 的 Vision 客户端项被删了（客户端会测速 -1）"; fail=$((fail + 1))
      fi ;;
  esac
done

python3 -I - "$S" <<'PY' || fail=$((fail + 1))
import glob, sys, yaml
s = sys.argv[1]
for f in glob.glob(s + '/home/client-config-mihomo-*.yaml') + glob.glob(s + '/etc/xhttp-cdn/all/client-config-mihomo-*.yaml'):
    yaml.safe_load(open(f, encoding='utf-8'))
print('ok   Mihomo YAML（订阅目录 + 节点库）全部合法')
PY

echo "失败数=$fail"
exit $((fail > 0))
