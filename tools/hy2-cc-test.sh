#!/usr/bin/env bash
# hy2_cc_json 回归测试：默认 bbr；设置 HY2_UP_MBPS / HY2_DOWN_MBPS 才用 brutal，且方向以服务端为视角（上下行互换）。
# 同时验证构建产物里不再残留整行写死的 "congestion": "bbr",（函数体内的 printf 字面量不算），且 install.sh 与 xh 都带有该函数。
# 用法（仓库根目录）：bash tools/hy2-cc-test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/src/hy2-cc.sh"

# 把片段套进 quicParams 并解析，返回 "congestion brutalUp brutalDown"
probe() {
  python3 -I -c '
import json,sys
q=json.loads("{\"quicParams\":{"+sys.argv[1]+" \"keepAlivePeriod\":10}}")["quicParams"]
print(q["congestion"],q.get("brutalUp","-"),q.get("brutalDown","-"))' "$(hy2_cc_json)"
}
check() { [[ "$2" == "$3" ]] || { echo "FAIL $1: 期望 [$3] 实际 [$2]"; exit 1; }; echo "ok   $1"; }

unset HY2_UP_MBPS HY2_DOWN_MBPS
check "默认保持 bbr"                "$(probe)" "bbr - -"
check "两个都设：服务端方向互换"    "$(HY2_UP_MBPS=50 HY2_DOWN_MBPS=300 probe)" "brutal 300mbps 50mbps"
check "只设下行"                    "$(HY2_DOWN_MBPS=300 probe)" "brutal 300mbps -"
check "只设上行"                    "$(HY2_UP_MBPS=50 probe)" "brutal - 50mbps"
check "空串视为未设置"              "$(HY2_UP_MBPS= HY2_DOWN_MBPS= probe)" "bbr - -"

D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
OUT_DIR="$D" bash "$ROOT/.github/scripts/build-install.sh" >/dev/null
hard='^ *"congestion": "bbr",$'
[[ "$(grep -c "$hard" "$D/install.sh" || true)" == 0 ]] || { echo "FAIL install.sh 仍有写死的 bbr"; exit 1; }
[[ "$(grep -c "$hard" "$D/xh" || true)" == 0 ]]         || { echo "FAIL xh 仍有写死的 bbr"; exit 1; }
[[ "$(grep -c '\$(hy2_cc_json)' "$D/install.sh")" -ge 4 ]] || { echo "FAIL install.sh 模板调用不足 4 处"; exit 1; }
[[ "$(grep -c '\$(hy2_cc_json)' "$D/xh")" == 2 ]]          || { echo "FAIL xh 模板调用应为 2 处"; exit 1; }
grep -q '^hy2_cc_json()' "$D/xh" || { echo "FAIL xh 缺少 hy2_cc_json 定义"; exit 1; }
bash -n "$D/install.sh" && bash -n "$D/xh"
echo "ok   构建产物：无写死 bbr，install.sh / xh 均含 hy2_cc_json"
echo "ALL PASS"
