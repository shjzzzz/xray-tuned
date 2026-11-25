#!/usr/bin/env bash
# xh upgrade 的断言自检：版本比较函数 + 子命令分发（不联网、不改系统）。
# 用法: bash tools/xh-upgrade-test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(sed -n '/^upgrade_ver_lt() {/,/^}/p' "$ROOT/src/manage/01-service.sh")"
lt() { upgrade_ver_lt "$1" "$2"; }
lt 1.2 1.10      || { echo "FAIL 1.2 < 1.10"; exit 1; }
lt 26.10.31 26.11.9 || { echo "FAIL 26.10.31 < 26.11.9"; exit 1; }
! lt 1.10 1.2    || { echo "FAIL 1.10 !< 1.2"; exit 1; }
! lt 3.0.1 3.0.1 || { echo "FAIL 相等必须为否"; exit 1; }

# tag_name 解析：单行（压缩）与多行 JSON 都必须取到版本号，不能取到同一行里的其他字段
parse() { grep -o '"tag_name" *: *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//'; }
[[ "$(echo '{"url":"https://x/1","id":1,"tag_name":"v26.11.9","name":"n"}' | parse)" == 26.11.9 ]] || { echo "FAIL 单行 JSON"; exit 1; }
[[ "$(printf '{\n  "url": "https://x/1",\n  "tag_name": "v3.1.7",\n}\n' | parse)" == 3.1.7 ]] || { echo "FAIL 多行 JSON"; exit 1; }
grep -qF "grep -o '\"tag_name\" *: *\"[^\"]*\"' | head -1" "$ROOT/src/manage/01-service.sh" || { echo "FAIL 测试与源码解析写法不一致"; exit 1; }

# 分发：把各组件函数换成回显桩，断言每个子命令只走对应实现，all 逐项执行且单项失败不中断
{
  sed -n '/^upgrade_ver_lt() {/,/^}/p;/^cmd_upgrade() {/,/^}/p' "$ROOT/src/manage/01-service.sh"
  cat <<'STUB'
ACME_SH=/nonexistent GREEN="" NC="" CYAN="" YELLOW="" MANAGE_CMD=xh ARGO_BIN=/nonexistent
info() { :; }; warn() { echo "WARN $*"; }
upgrade_show() { echo show; }; upgrade_geodata() { echo geodata; }; upgrade_deps() { echo "deps:$1"; }
cmd_update() { echo "xray:$*"; }; cmd_nginx() { echo "nginx:$*"; }; cmd_argo_update() { echo cloudflared; }
STUB
  echo 'for a in "show" "xray" "xray -y" "nginx -y" "geodata" "deps -y" "bogus"; do echo "[$a] $(cmd_upgrade $a 2>&1 | tr "
" " ")"; done'
  echo 'echo "[all] $(cmd_upgrade all -y 2>&1 | tr "
" " ")"'
  echo 'cmd_update() { return 1; }; echo "[all-fail] $(cmd_upgrade all -y >/dev/null 2>&1; echo rc=$?)"'
} > "$(mktemp -d)/d.sh"
OUT=$(bash "$(ls -td /tmp/tmp.*/ | head -1)d.sh" 2>&1)
grep -q '^\[show\] show' <<<"$OUT"            || { echo "FAIL show"; echo "$OUT"; exit 1; }
grep -q '^\[xray\] xray: '  <<<"$OUT"          || { echo "FAIL xray"; echo "$OUT"; exit 1; }
grep -q '^\[xray -y\] xray:--auto' <<<"$OUT"  || { echo "FAIL xray -y"; echo "$OUT"; exit 1; }
grep -q '^\[nginx -y\] nginx:update -y' <<<"$OUT" || { echo "FAIL nginx -y"; echo "$OUT"; exit 1; }
grep -q '^\[deps -y\] deps:1' <<<"$OUT"       || { echo "FAIL deps"; echo "$OUT"; exit 1; }
grep -q '^\[bogus\] 用法' <<<"$OUT"            || { echo "FAIL bogus"; echo "$OUT"; exit 1; }
grep -q 'xray:--auto.*nginx:update -y.*未安装 acme.sh.*geodata.*deps:1' <<<"$OUT" || { echo "FAIL all 顺序/参数"; echo "$OUT"; exit 1; }
grep -q '^\[all-fail\] rc=1' <<<"$OUT"         || { echo "FAIL all 失败汇总"; echo "$OUT"; exit 1; }
echo "PASS xh-upgrade-test"
