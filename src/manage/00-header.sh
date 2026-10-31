#!/bin/bash
# xray-xhttp 管理命令
# 用法: xh [子命令]，不带参数进入交互菜单

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ver_ge() {
  [[ "$1" == "$2" ]] && return 0
  local lowest
  lowest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
  [[ "$lowest" == "$2" ]]
}

try_sysctl() {
  if sysctl -w "${1}=${2}" >/dev/null 2>&1; then
    declare -p SYSCTL_APPLIED >/dev/null 2>&1 && SYSCTL_APPLIED+=("${1} = ${2}")
    return 0
  else
    declare -p SYSCTL_SKIPPED >/dev/null 2>&1 && SYSCTL_SKIPPED+=("$1")
    return 1
  fi
}

# 本脚本自身的版本，由安装时的 sed 从占位符替换而来（见本文件末尾）。
# 不能直接写 ${PROJECT_VERSION}：外层 heredoc 是 quoted 的，不做变量展开。
#
# 它与 node.env 里的 PROJECT_VERSION 是**两个不同的东西**：
#   XH_VERSION      —— 生成这个 xh 脚本的版本
#   PROJECT_VERSION —— 当初安装这套节点的版本（node.env，装完就不再变）
# 两者不一致是正常的（升级过 xh、或手工替换过），`xh version` 会同时打印，
# 这样"我这台机器的 xh 是新是旧"一眼可见——此前只能靠 grep 源码里的特征字符串判断。
XH_VERSION="@@XH_VERSION@@"

MANAGE_CMD="xh"
STATE_DIR="/etc/xhttp-cdn"
NODE_ENV_FILE="${STATE_DIR}/node.env"
SUB_TOKEN_FILE="${STATE_DIR}/sub_token"
SYSCTL_CONF="/etc/sysctl.d/99-xray-xhttp.conf"
LIMITS_CONF="/etc/security/limits.d/99-xray-xhttp.conf"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
CRON_TAG="# xray-xhttp"

[[ $EUID -ne 0 ]] && fail "请使用 root 用户运行"

if [[ -f "$NODE_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$NODE_ENV_FILE"
else
  warn "未找到 ${NODE_ENV_FILE}，部分信息不可用（是否尚未运行安装脚本？）"
fi

if [[ -z "${SERVICE_TYPE:-}" ]]; then
  if command -v systemctl >/dev/null 2>&1; then SERVICE_TYPE="systemd"; else SERVICE_TYPE="openrc"; fi
fi

# 兜底：node.env 通常带这两项，但老版本或文件缺失时 tuning 仍要能跑
PROJECT_NAME="${PROJECT_NAME:-xray-xhttp}"
if [[ -z "${OS_ID:-}" && -f /etc/os-release ]]; then
  OS_ID=$(. /etc/os-release && echo "$ID")
fi

svc() {
  local action="$1" name="$2"
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$name" "$action"
  else
    systemctl "$action" "$name"
  fi
}

svc_active() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" status >/dev/null 2>&1
  else
    systemctl is-active --quiet "$1"
  fi
}

update_node_env() {
  local key="$1" val="$2"
  [[ -f "$NODE_ENV_FILE" ]] || return 0
  local tmp="${NODE_ENV_FILE}.tmp$$"
  grep -v "^${key}=" "$NODE_ENV_FILE" > "$tmp" || true
  printf "%s=%q\n" "$key" "$val" >> "$tmp"
  mv -f "$tmp" "$NODE_ENV_FILE"
}

# ---------------- 子命令 ----------------

