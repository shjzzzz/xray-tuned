# ==================================================
# 包管理与服务管理适配
# ==================================================

case "$OS_ID" in
  debian|ubuntu)
    # 非交互 + 等待 apt 锁（新机 unattended-upgrades/cloud-init 常占锁；needrestart 会弹框）
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
    APT_OPTS=(-o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
    pkg_update()  { apt-get "${APT_OPTS[@]}" update; }
    pkg_install() { apt-get "${APT_OPTS[@]}" install -y "$@"; }
    install_build_deps() {
      # 优先 pcre2（Debian 13 已无 libpcre3），旧系统回退 pcre3
      apt-get "${APT_OPTS[@]}" install -y gcc g++ libpcre2-dev zlib1g-dev libssl-dev libcrypt-dev wget make 2>/dev/null || \
        apt-get "${APT_OPTS[@]}" install -y gcc g++ libpcre3-dev zlib1g-dev libssl-dev libcrypt-dev wget make
    }
    ;;
  centos|rhel|almalinux|rocky|ol|amzn)
    pkg_update()  { yum makecache; }
    pkg_install() { yum install -y "$@"; }
    install_build_deps() {
      yum groupinstall -y "Development Tools"
      yum install -y pcre-devel zlib-devel openssl-devel wget make 2>/dev/null || \
        yum install -y pcre2-devel zlib-devel openssl-devel wget make
    }
    ;;
  fedora)
    pkg_update()  { dnf makecache; }
    pkg_install() { dnf install -y "$@"; }
    install_build_deps() {
      dnf groupinstall -y "Development Tools"
      dnf install -y pcre-devel zlib-devel openssl-devel wget make 2>/dev/null || \
        dnf install -y pcre2-devel zlib-devel openssl-devel wget make
    }
    ;;
  opensuse*|sles)
    pkg_update()  { zypper refresh; }
    pkg_install() { zypper install -y "$@"; }
    install_build_deps() {
      zypper install -y -t pattern devel_basis
      zypper install -y pcre2-devel zlib-devel libopenssl-devel wget make
    }
    ;;
  alpine)
    pkg_update()  { apk update; }
    pkg_install() { apk add --no-cache "$@"; }
    install_build_deps() {
      apk add --no-cache build-base linux-headers pcre2-dev zlib-dev openssl-dev wget make
    }
    ;;
  *)
    error "不支持的发行版: $OS_ID，目前支持 Debian/Ubuntu/CentOS/RHEL/Fedora/openSUSE/SLES/Alpine"
    ;;
esac

if [[ "$OS_ID" == "alpine" ]]; then
  SERVICE_TYPE="openrc"
  NGINX_STOP_CMD="rc-service nginx stop"
  NGINX_START_CMD="rc-service nginx start"
  NGINX_RESTART_CMD="rc-service nginx restart"
  XRAY_RESTART_CMD="rc-service xray restart"
else
  SERVICE_TYPE="systemd"
  NGINX_STOP_CMD="systemctl stop nginx"
  NGINX_START_CMD="systemctl start nginx"
  NGINX_RESTART_CMD="systemctl restart nginx"
  XRAY_RESTART_CMD="systemctl restart xray"
fi
# XRAY_RESTART_CMD 用于 acme.sh 的 --reloadcmd（10-service-check.sh）。
# 那条命令将来由 acme 的 cron 执行，届时本脚本的 shell 函数（service_restart）
# 并不存在，所以必须是可独立运行的完整系统命令，不能复用函数。

service_enable() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-update add "$1" default >/dev/null 2>&1 || true
  else
    systemctl enable "$1" >/dev/null 2>&1 || true
  fi
}

service_restart() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" restart || rc-service "$1" start
  else
    systemctl reset-failed "$1" >/dev/null 2>&1 || true
    systemctl restart "$1"
  fi
}

service_is_active() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" status >/dev/null 2>&1
  else
    systemctl is-active --quiet "$1"
  fi
}
