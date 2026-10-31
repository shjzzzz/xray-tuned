# ==================================================
# Cloudflare 智能优选、证书与隧道网络
# ==================================================
# ---------- 证书续期方式（v4.9.45）----------
# 找到本项目双域名证书在 acme.sh 里的域名配置文件
acme_domain_conf() {
  local _d
  for _d in "$HOME/.acme.sh/${REALITY_DOMAIN}_ecc" "$HOME/.acme.sh/${REALITY_DOMAIN}"; do
    [[ -f "$_d/${REALITY_DOMAIN}.conf" ]] && { printf '%s' "$_d/${REALITY_DOMAIN}.conf"; return 0; }
  done
  return 1
}

# CDN 域名是否走了代理：解析结果里不含本机 IP 即视为经 CDN（Cloudflare 橙云）
cdn_behind_proxy() {
  [[ -n "${CDN_DOMAIN:-}" && -n "${VPS_IP:-}" ]] || return 1
  local _ips
  _ips=$(getent ahostsv4 "$CDN_DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)
  [[ -n "$_ips" ]] || return 1
  ! grep -Fxq "$VPS_IP" <<< "$_ips"
}

cmd_cert() {
  local action="${1:-show}" conf
  conf=$(acme_domain_conf) || fail "未找到 acme.sh 的域名配置（${REALITY_DOMAIN:-未设置}）"
  local acct="$HOME/.acme.sh/account.conf"
  case "$action" in
    show|status)
      local wr nr
      wr=$(. "$conf" 2>/dev/null; printf '%s' "${Le_Webroot:-}")
      nr=$(. "$conf" 2>/dev/null; printf '%s' "${Le_NextRenewTimeStr:-}")
      echo "证书到期:   $(openssl x509 -in /etc/ssl/private/fullchain.cer -noout -enddate 2>/dev/null | cut -d= -f2)"
      echo "下次续期:   ${nr:-未知}"
      case "$wr" in
        dns_*) echo "续期方式:   DNS-01（${wr}）" ;;
        *)     echo "续期方式:   standalone（HTTP-01，续期时停 nginx 占用 80 端口）" ;;
      esac
      if cdn_behind_proxy; then echo "CDN 域名:   已走 CDN 代理"; else echo "CDN 域名:   直连本机（或解析失败）"; fi
      grep -q '^SAVED_CF_Token=' "$acct" 2>/dev/null && echo "CF Token:   已保存（account.conf）" || echo "CF Token:   未保存"
      if [[ "$wr" != dns_* ]] && cdn_behind_proxy; then
        warn "CDN 已走代理，standalone 续期会失败：CF_Token=<API Token> ${MANAGE_CMD} cert dnscf"
      fi
      ;;
    dnscf)
      # Token 来源：环境变量 CF_Token 优先，否则沿用 account.conf 里已保存的
      local tok="${CF_Token:-}"
      [[ -n "$tok" ]] || tok=$(sed -nE "s/^SAVED_CF_Token='?([^']*)'?\$/\1/p" "$acct" 2>/dev/null | head -1)
      [[ -n "$tok" ]] || fail "需要 Cloudflare API Token（Zone.DNS 编辑权限）：CF_Token=<token> ${MANAGE_CMD} cert dnscf"
      # 先验证 Token 能看到 CDN 域名所在的 Zone，避免切过去之后续期时才失败
      local zone="${CDN_DOMAIN#*.}" resp
      # 请求头经 stdin（curl -K -）传入，Token 不出现在进程参数里（ps 可见）
      resp=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -fsS --max-time 20 -K - \
        "https://api.cloudflare.com/client/v4/zones?name=${zone}" 2>/dev/null) || fail "Cloudflare API 请求失败（Token 无效或网络不通）"
      python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("success") and d.get("result") else 1)' <<< "$resp" \
        || fail "该 Token 看不到 Zone ${zone}，请检查权限（需 Zone.Zone 读 + Zone.DNS 编辑）"
      info "Token 已验证：可访问 Zone ${zone}"
      if [[ -n "${CF_Token:-}" ]]; then
        cp -a "$acct" "${acct}.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        sed -i '/^SAVED_CF_Token=/d' "$acct"
        printf "SAVED_CF_Token='%s'\n" "$CF_Token" >> "$acct"
        chmod 600 "$acct"
      fi
      cp -a "$conf" "${conf}.bak-$(date +%Y%m%d%H%M%S)"
      # 续期模式记在 Le_Webroot；DNS-01 不需要停 nginx，清空 Pre/PostHook
      sed -i -E "s/^Le_Webroot=.*/Le_Webroot='dns_cf'/; s/^Le_PreHook=.*/Le_PreHook=''/; s/^Le_PostHook=.*/Le_PostHook=''/" "$conf"
      grep -q "^Le_Webroot='dns_cf'" "$conf" || fail "写入续期方式失败：$conf"
      info "已切换为 DNS-01 续期（dns_cf），续期时不再停 nginx"
      info "可用 LE 测试环境演练：acme.sh --issue --server letsencrypt_test --dns dns_cf -d ${REALITY_DOMAIN} -d ${CDN_DOMAIN} --keylength ec-256 --config-home /tmp/acme-test --cert-home /tmp/acme-test/certs"
      ;;
    *) fail "用法: ${MANAGE_CMD} cert [show|dnscf]" ;;
  esac
}

cmd_bestcf() {
  local action="${1:-show}"
  local dir="/root/cf-bestip"
  local py_script="${dir}/dns_updater.py"
  local timer_file="/etc/systemd/system/cf-bestip.timer"
  local service_file="/etc/systemd/system/cf-bestip.service"

  case "$action" in
    show|status)
      echo ""
      echo -e "${CYAN}=== Cloudflare CDN 优选 IP 状态 ===${NC}"
      local lock_file="${dir}/lock"
      local locked_ip_file="${dir}/locked_ips.txt"
      if [[ -f "$lock_file" || -f "$locked_ip_file" ]]; then
        local l_ips=""
        [[ -f "$locked_ip_file" ]] && l_ips=$(tr '\n' ' ' < "$locked_ip_file" | xargs)
        echo -e "  IP 轮换模式:    ${GREEN}已锁定 (Fixed / 禁止自动轮换)${NC}"
        echo -e "  锁定的 IP:      ${GREEN}${l_ips:-当前解析 IP}${NC}"
        echo -e "  轮换策略:       ${YELLOW}完全由您自主决定，禁止后台自动轮换与漂移${NC}"
      else
        echo -e "  IP 轮换模式:    ${CYAN}自动轮换模式 (Active)${NC}"
        if systemctl is-active --quiet cf-bestip.timer 2>/dev/null; then
          echo -e "  定时轮换:       ${GREEN}运行中 (Active)${NC}"
        else
          echo -e "  定时轮换:       ${YELLOW}未激活 (Inactive)${NC}"
        fi
        local cur_interval="每日高峰模式"
        if [[ -f "$timer_file" ]]; then
          if grep -q 'OnCalendar=' "$timer_file"; then
            cur_interval="每日高峰模式 (12:30, 19:00-23:00 每整点, 04:00)"
          else
            cur_interval=$(grep -oE 'OnUnitActiveSec=[^ ]+' "$timer_file" | cut -d= -f2 || echo "2h")
          fi
        fi
        echo -e "  轮换周期:       ${GREEN}${cur_interval}${NC}"
      fi

      if systemctl is-active --quiet cf-healthcheck.timer 2>/dev/null; then
        echo -e "  健康自愈监听:   ${GREEN}运行中 (每 1 分钟检测握手与延迟)${NC}"
      else
        echo -e "  健康自愈监听:   ${YELLOW}未激活${NC}"
      fi

      if [[ -f "$py_script" ]]; then
        local cur_domain cur_zone
        cur_domain=$(grep -E '^\s*DOMAIN_NAME\s*=' "$py_script" | cut -d'"' -f2 || true)
        cur_zone=$(grep -E '^\s*CF_ZONE_ID\s*=' "$py_script" | cut -d'"' -f2 || true)
        echo -e "  优选域名:       ${GREEN}${cur_domain:-未配置}${NC}"
        echo -e "  Zone ID:        ${cur_zone:-未配置}"

        if [[ -n "$cur_domain" ]] && command -v getent >/dev/null 2>&1; then
          local resolved_ips
          resolved_ips=$(getent ahostsv4 "$cur_domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')
          echo -e "  当前解析 IP:    ${GREEN}${resolved_ips:-未能解析}${NC}"
        fi
      else
        echo -e "  更新脚本:       ${YELLOW}未安装配置 (/root/cf-bestip/dns_updater.py)${NC}"
      fi

      if ! [[ -f "$lock_file" || -f "$locked_ip_file" ]] && command -v systemctl >/dev/null 2>&1; then
        local next_run
        next_run=$(systemctl list-timers cf-bestip.timer --no-pager --no-legend --full 2>/dev/null | grep 'cf-bestip' | awk '{print $1" "$2" "$3" "$4" (剩余 "$5" "$6")"}' || true)
        if [[ -n "$next_run" ]]; then
          echo -e "  下次轮换时间:   ${next_run}"
        fi
      fi
      echo ""
      echo -e "快捷指令:"
      echo -e "  ${MANAGE_CMD} bestcf show             # 查看状态与当前解析"
      echo -e "  ${MANAGE_CMD} bestcf lock             # 锁定当前优选 IP (禁止自动轮换)"
      echo -e "  ${MANAGE_CMD} bestcf unlock           # 解锁并恢复自动轮换"
      echo -e "  ${MANAGE_CMD} bestcf set <IP...>      # 自定义指定优选 IP 并锁定"
      echo -e "  ${MANAGE_CMD} bestcf interval <周期>  # 调整定时周期 (0/peak/1h/2h/4h/6h)"
      echo -e "  ${MANAGE_CMD} bestcf check            # 立即检测当前优选 IP 延迟/握手质量"
      echo -e "  ${MANAGE_CMD} bestcf run              # 强制立即测速与更新 DNS"
      echo -e "  ${MANAGE_CMD} bestcf on / off         # 开启 / 暂停自动更新定时器与健康检查"
      echo ""
      ;;
    setup)
      echo ""
      echo -e "${CYAN}=== 配置 Cloudflare 优选 IP 自动化服务 ===${NC}"
      local default_domain="bestcf.${CDN_DOMAIN#*.}"
      read -rp "请输入优选二级域名 [默认: ${default_domain}]: " input_domain
      local final_domain="${input_domain:-$default_domain}"

      read -rp "请输入 Cloudflare 区域 ID (Zone ID): " input_zone
      [[ -n "$input_zone" ]] || fail "Zone ID 不能为空"

      read -rp "请输入 Cloudflare API Token (需 DNS 编辑权限): " input_token
      [[ -n "$input_token" ]] || fail "API Token 不能为空"

      info "正在部署/更新 /root/cf-bestip 环境..."
      mkdir -p "$dir"
      # 若无 cfst 测速工具，自动拉取
      if [[ ! -x "${dir}/cfst" ]]; then
        local arch
        arch=$(uname -m)
        local cfst_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_linux_amd64.tar.gz"
        if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
          cfst_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_linux_arm64.tar.gz"
        fi
        info "下载 CloudflareSpeedTest (${arch})..."
        curl -fsSL "$cfst_url" | tar -zxvf - -C "$dir" cfst 2>/dev/null || true
        chmod +x "${dir}/cfst" 2>/dev/null || true
      fi

      if [[ ! -f "${dir}/ip.txt" ]]; then
        info "下载 Cloudflare 官方 IPV4 段列表..."
        curl -fsSL -o "${dir}/ip.txt" "https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ip.txt" 2>/dev/null || true
      fi

      cat > "$py_script" <<PYEOF
#!/usr/bin/env python3
import os, sys, json, subprocess, urllib.request, time, shutil, ssl, socket, random, re

CF_TOKEN = "${input_token}"
CF_ZONE_ID = "${input_zone}"
DOMAIN_NAME = "${final_domain}"
DIR = "${dir}"

sys.path.insert(0, DIR)
from probe import origin_ok  # 真实 XHTTP 隧道探测

def run_cfst():
    cmd = [
        f"{DIR}/cfst",
        "-f", f"{DIR}/ip.txt",
        "-tp", "443",
        "-url", "https://speed.cloudflare.com/__down?bytes=10000000",
        "-t", "3", "-n", "200", "-dn", "5", "-dt", "5", "-p", "5",
        "-o", f"{DIR}/result.csv"
    ]
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 开始 Cloudflare 优选测速...")
    subprocess.run(cmd, cwd=DIR, check=True)

def get_best_ips(limit=2):
    csv_path = f"{DIR}/result.csv"
    ips = []
    if not os.path.exists(csv_path): return ips
    with open(csv_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for l in lines[1:]:
        parts = l.strip().split(",")
        if parts and len(parts) >= 6:
            ips.append({"ip": parts[0].strip(), "speed": parts[5].strip(), "latency": parts[4].strip()})
            if len(ips) >= limit: break
    return ips

def cf_api_request(method, endpoint, data=None):
    url = f"https://api.cloudflare.com/client/v4/zones/{CF_ZONE_ID}/{endpoint}"
    headers = {"Authorization": f"Bearer {CF_TOKEN}", "Content-Type": "application/json"}
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)

def get_existing_records():
    try:
        res = cf_api_request("GET", f"dns_records?type=A&name={DOMAIN_NAME}")
        return res.get("result", [])
    except Exception:
        pass
    cf_bin = shutil.which("cf") or "/usr/local/bin/cf"
    if os.path.exists(cf_bin) and os.access(cf_bin, os.X_OK):
        try:
            env = os.environ.copy()
            env["CLOUDFLARE_API_TOKEN"] = CF_TOKEN
            cmd = [cf_bin, "dns", "records", "list", "--zone", CF_ZONE_ID, "-q"]
            res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=15)
            if res.returncode == 0:
                raw = res.stdout
                s_idx = raw.find("[")
                if s_idx != -1:
                    records = json.loads(raw[s_idx:])
                    return [r for r in records if r.get("name") == DOMAIN_NAME and r.get("type") == "A"]
        except Exception:
            pass
    return []

def sync_dns(ips):
    if not ips:
        print("未检测到有效优选 IP，跳过 DNS 更新")
        return
    print(f"最优 IP: {[x['ip'] + ' (' + x['speed'] + 'MB/s, ' + x['latency'] + 'ms)' for x in ips]}")
    current_records = get_existing_records()
    target_ips = [x["ip"] for x in ips]
    if sorted(target_ips) == sorted([r["content"] for r in current_records]):
        print("当前 DNS 记录已是最优 IP，无需更新。")
        return

    cf_bin = shutil.which("cf") or "/usr/local/bin/cf"
    used_cli_batch = False
    if os.path.exists(cf_bin) and os.access(cf_bin, os.X_OK):
        try:
            deletes = [{"id": r["id"]} for r in current_records]
            posts = [{
                "type": "A", "name": DOMAIN_NAME, "content": ip, "ttl": 60, "proxied": False,
                "comment": f"Auto BestCF {time.strftime('%Y-%m-%d %H:%M:%S')}"
            } for ip in target_ips]
            batch_body = {"deletes": deletes, "posts": posts}
            env = os.environ.copy()
            env["CLOUDFLARE_API_TOKEN"] = CF_TOKEN
            cmd = [cf_bin, "dns", "records", "batch", "--zone", CF_ZONE_ID, "--body", json.dumps(batch_body), "-q"]
            res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=20)
            if res.returncode == 0:
                print(f"通过 cf CLI batch 成功更新 DNS 记录: {DOMAIN_NAME} -> {target_ips} (TTL=60, 仅DNS)")
                used_cli_batch = True
        except Exception as e:
            print("cf CLI batch 执行异常，回退到 HTTP API 模式:", e)

    if not used_cli_batch:
        for r in current_records:
            cf_api_request("DELETE", f"dns_records/{r['id']}")
            print(f"已删除旧 DNS 记录: {r['content']}")
        for ip in target_ips:
            cf_api_request("POST", "dns_records", {
                "type": "A", "name": DOMAIN_NAME, "content": ip, "ttl": 60, "proxied": False,
                "comment": f"Auto BestCF {time.strftime('%Y-%m-%d %H:%M:%S')}"
            })
            print(f"成功添加优选 DNS 记录: {DOMAIN_NAME} -> {ip} (TTL=60, 仅DNS)")

# 优质 Anycast 纯净优选 IP 候选池 (实测对国内三网连通率最高并支持 XHTTP 隧道回源)
CMCC_PREFERRED_IPS = [
    "%d.%d.%d.%d" % (a, b, c, d) for a, b, c, d in [
        (162, 159, 192, 1),   (162, 159, 237, 59), (104, 18, 40, 34),   (172, 64, 152, 180),
        (104, 16, 160, 187), (104, 16, 161, 187), (104, 16, 160, 1),   (104, 16, 161, 1)
    ]
]

def get_cmcc_candidates():
    candidates = []
    # 1. 优先复用当前 DNS 中已有的且探测健康通过的 IP（避免无故障盲目漂移）
    try:
        current_records = get_existing_records()
        for r in current_records:
            cip = r.get("content")
            if cip and (cip in CMCC_PREFERRED_IPS or cip.startswith("104.16.")):
                ok, why = origin_ok(cip, attempts=1)
                if ok:
                    lat = "25"
                    m = re.search(r'\(([0-9.]+)ms\)', why)
                    if m: lat = f"{float(m.group(1)):.0f}"
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 保持当前健康优选 IP {cip}: {why}")
                    candidates.append({"ip": cip, "speed": "CMI-HKG", "latency": lat, "loss": "0.00"})
                    if len(candidates) >= 2:
                        return candidates
    except Exception as e:
        print(f"检查现有记录异常: {e}")

    # 2. 若现有 IP 不足 2 个健康节点，从 CMCC 纯净候选池中探测补充
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 探测中国移动 CMI 香港纯净优选池补充节点...")
    existing_ips = [c["ip"] for c in candidates]
    for ip in CMCC_PREFERRED_IPS:
        if ip in existing_ips:
            continue
        ok, why = origin_ok(ip, attempts=1)
        if ok:
            lat = "25"
            m = re.search(r'\(([0-9.]+)ms\)', why)
            if m: lat = f"{float(m.group(1)):.0f}"
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ✅ 移动优选候选 {ip}: 探测通过 (延迟 {lat}ms)")
            candidates.append({"ip": ip, "speed": "CMI-HKG", "latency": lat, "loss": "0.00"})
            if len(candidates) >= 2:
                break
        else:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ❌ 移动优选候选 {ip}: {why}")
    return candidates

if __name__ == "__main__":
    try:
        good = get_cmcc_candidates()
        if len(good) < 2:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 移动专属池可用 IP 不足 2 个，启动全量测速兜底...")
            run_cfst()
            for c in get_best_ips(limit=30):
                if c["ip"] in [b["ip"] for b in good]:
                    continue
                ok, why = origin_ok(c["ip"])
                print("[%s] 候选 %s: %s" % (time.strftime('%Y-%m-%d %H:%M:%S'), c["ip"], why))
                if ok:
                    good.append(c)
                if len(good) >= 2:
                    break
        if not good:
            print("没有通过源站探测的候选 IP，保持现有 DNS 不变")
            sys.exit(1)
        sync_dns(good)
    except Exception as e:
        print("执行出错:", e)
        sys.exit(1)
PYEOF
      chmod 700 "$py_script"

      cat > "${dir}/probe.py" <<'PROBEEOF'
#!/usr/bin/env python3
"""优选 IP 真实通路探测：用订阅里的 CDN-H2 链接起临时 xray 客户端，把地址换成候选 IP，经 socks 取 204。
坏 IP 能完成 TLS 握手、GET / 也返回 200，但 XHTTP 数据通不过，所以只能用真实隧道判断。"""
import glob, json, os, shutil, socket, subprocess, tempfile, time, urllib.parse as u

SUB_GLOB = "/usr/local/nginx/html/sub/*/v2rayn-raw.txt"
TEST_URLS = ("https://www.gstatic.com/generate_204", "https://cp.cloudflare.com/generate_204")

def _link():
    for f in glob.glob(SUB_GLOB):
        for l in open(f, encoding="utf-8"):
            if l.startswith("vless://") and "XHTTP-CDN-H2" in l:
                return l.strip()
    return None

def _config(link, ip, port):
    p = u.urlparse(link); q = {k: v[0] for k, v in u.parse_qs(p.query).items()}
    tls = {"serverName": q.get("sni", p.hostname), "fingerprint": q.get("fp", "chrome")}
    if q.get("alpn"): tls["alpn"] = q["alpn"].split(",")
    if q.get("ech"): tls["echConfigList"] = q["ech"]
    x = {"path": q.get("path", "/"), "mode": q.get("mode", "auto")}
    if q.get("host"): x["host"] = q["host"]
    if q.get("extra"): x["extra"] = json.loads(q["extra"])
    ob = {"protocol": "vless", "settings": {"vnext": [{"address": ip, "port": p.port or 443,
          "users": [{"id": p.username, "encryption": q.get("encryption", "none")}]}]},
          "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": tls, "xhttpSettings": x}}
    return {"log": {"loglevel": "none"},
            "inbounds": [{"listen": "127.0.0.1", "port": port, "protocol": "socks", "settings": {"udp": False}}],
            "outbounds": [ob]}

def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); return s.getsockname()[1]

def origin_ok(ip, attempts=2):
    link = _link(); xray = shutil.which("xray") or "/usr/local/bin/xray"
    if not link or not os.path.exists(xray):
        return True, "探测不可用(无订阅链接或 xray)，跳过"
    port = _free_port(); d = tempfile.mkdtemp(prefix="bestcf-probe-")
    try:
        cfg = os.path.join(d, "c.json"); json.dump(_config(link, ip, port), open(cfg, "w"))
        pr = subprocess.Popen([xray, "run", "-c", cfg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(1.5)
            for i in range(attempts):
                t_req = time.time()
                r = subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "6", "-w", "%{http_code}",
                    "-x", "socks5h://127.0.0.1:%d" % port, TEST_URLS[i % len(TEST_URLS)]], capture_output=True, text=True)
                cost_ms = (time.time() - t_req) * 1000.0
                if r.stdout.strip() == "204":
                    return True, "XHTTP 隧道探测通过 (%.1fms)" % cost_ms
            return False, "XHTTP 隧道探测失败(握手正常但数据不通)"
        finally:
            pr.terminate()
            try: pr.wait(timeout=3)
            except Exception: pr.kill()
    finally:
        shutil.rmtree(d, ignore_errors=True)
PROBEEOF
      chmod 600 "${dir}/probe.py"

      # 写入健康检查脚本（检测延迟与握手，异常立即自愈）
      local hc_script="${dir}/health_check.py"
      cat > "$hc_script" <<'HCEOF'
#!/usr/bin/env python3
import os, sys, time, subprocess, socket, ssl

DIR = "/root/cf-bestip"
PY_UPDATER = f"{DIR}/dns_updater.py"
DOMAIN_NAME = "bestcf.example.com"
SNI_HOST = "speed.cloudflare.com"
MAX_LATENCY_MS = 300.0
TIMEOUT_SECS = 3.5

sys.path.insert(0, DIR)
from probe import origin_ok  # 真实 XHTTP 隧道探测

def check_ip_health(ip):
    t0 = time.time()
    ctx = ssl.create_default_context()
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    try:
        with socket.create_connection((ip, 443), timeout=TIMEOUT_SECS) as sock:
            with ctx.wrap_socket(sock, server_hostname=SNI_HOST) as ssock:
                latency = (time.time() - t0) * 1000.0
                cipher = ssock.cipher()[0] if ssock.cipher() else "TLS"
                if latency > MAX_LATENCY_MS:
                    return False, latency, f"延迟过高 ({latency:.1f}ms > {MAX_LATENCY_MS}ms)"
                ok, why = origin_ok(ip)
                if not ok:
                    return False, latency, why
                return True, latency, f"正常 (TLS握手成功, {cipher}, 握手耗时: {latency:.1f}ms, {why})"
    except socket.timeout:
        return False, 9999.0, "连接超时 (Timeout)"
    except Exception as e:
        return False, 9999.0, f"TLS 握手失败: {e}"

def main():
    global DOMAIN_NAME
    if os.path.exists(PY_UPDATER):
        with open(PY_UPDATER, "r", encoding="utf-8") as f:
            for l in f:
                if l.strip().startswith("DOMAIN_NAME"):
                    DOMAIN_NAME = l.split('"')[1]
                    break

    try:
        current_ips = list(set(socket.gethostbyname_ex(DOMAIN_NAME)[2]))
    except Exception as e:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 无法解析 {DOMAIN_NAME}: {e}，立刻重新优选！")
        subprocess.run([sys.executable, PY_UPDATER], cwd=DIR)
        return

    if not current_ips:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 域名未返回任何 IP，立刻触发测速更新！")
        subprocess.run([sys.executable, PY_UPDATER], cwd=DIR)
        return

    all_failed = True
    any_degraded = False

    for ip in current_ips:
        ok, lat, reason = check_ip_health(ip)
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 检测 IP {ip}: {reason}")
        if ok: all_failed = False
        else: any_degraded = True

    if all_failed or any_degraded:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ⚠️ 检测到当前优选 IP 不佳或链路异常，立刻自动重新测速并更新 DNS！")
        res = subprocess.run([sys.executable, PY_UPDATER], cwd=DIR)
        if res.returncode == 0:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ✅ 自动应急切换成功！")
        else:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ❌ 应急切换失败，退出码: {res.returncode}")
    else:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ✅ 所有优选 IP 链路健康稳定，无需切换。")

if __name__ == "__main__":
    main()
HCEOF
      chmod 700 "$hc_script"

      # 写入 systemd 配置
      cat > "$service_file" <<SVCEOF
[Unit]
Description=Cloudflare Best IP DNS Auto-Updater
After=network-online.target

[Service]
Type=oneshot
User=root
WorkingDirectory=${dir}
ExecStart=${py_script}
SVCEOF

      cat > "$timer_file" <<TMREOF
[Unit]
Description=Run Cloudflare Best IP DNS Auto-Updater periodically

[Timer]
OnBootSec=3min
# 每日高峰时段自动测速与优选轮换 (UTC+8 北京时间)
# 1. 凌晨低峰基准同步: 04:00
# 2. 午高峰时段: 12:30
# 3. 晚间核心高峰时段 (19:00 - 23:00 每整点轮换): 19:00, 20:00, 21:00, 22:00, 23:00
OnCalendar=*-*-* 04:00:00
OnCalendar=*-*-* 12:30:00
OnCalendar=*-*-* 19..23:00:00
Persistent=true

[Install]
WantedBy=timers.target
TMREOF

      # 写入健康检查自愈定时器（每 1 分钟自动探测一次）
      local hc_service="/etc/systemd/system/cf-healthcheck.service"
      local hc_timer="/etc/systemd/system/cf-healthcheck.timer"
      cat > "$hc_service" <<HCSVCEOF
[Unit]
Description=Cloudflare Best IP Health Check and Auto Fallback
After=network-online.target

[Service]
Type=oneshot
User=root
WorkingDirectory=${dir}
ExecStart=${hc_script}
HCSVCEOF

      cat > "$hc_timer" <<HCTMREOF
[Unit]
Description=Run Cloudflare Best IP Health Check every minute

[Timer]
OnBootSec=2min
OnActiveSec=30s
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
HCTMREOF

      systemctl daemon-reload
      systemctl enable --now cf-bestip.timer
      systemctl enable --now cf-healthcheck.timer
      info "服务已配置完成并启动："
      info "  1. 高峰期轮换定时器 (每日高峰时段: 12:30, 19:00-23:00 每整点, 04:00 自动测速与优选)"
      info "  2. 故障自愈监测定时器 (每 1 分钟检测握手与源站可达性，异常立刻自动换 IP)"
      read -rp "是否立即运行一次测速与 DNS 同步？[Y/n]: " run_now
      if [[ "${run_now:-y}" =~ ^[Yy]$ ]]; then
        cmd_bestcf run
      fi
      ;;
    check)
      local hc_script="${dir}/health_check.py"
      if [[ ! -x "$hc_script" ]]; then
        fail "未找到 ${hc_script}，请先执行 ${MANAGE_CMD} bestcf setup"
      fi
      info "正在执行优选 IP 链路质量与握手检测..."
      "$hc_script"
      ;;
    audit)
      info "正在调用 Cloudflare CLI 执行 DNS 全面规范性体检..."
      local cf_bin
      cf_bin=$(command -v cf || echo "/usr/local/bin/cf")
      if [[ ! -x "$cf_bin" ]]; then
        fail "未找到 cf 命令，请先运行: npm i -g cf"
      fi
      local cur_zone="" cur_token=""
      if [[ -f "$py_script" ]]; then
        cur_token=$(grep -E '^\s*CF_TOKEN\s*=' "$py_script" | cut -d'"' -f2 || true)
        [[ -f "${dir}/.env" ]] && cur_token=$(awk -F= '$1 ~ /^CF_TOKEN/ {gsub(/[" '\''[:space:]]/, "", $2); print $2}' "${dir}/.env" || true)
        cur_zone=$(grep -E '^\s*CF_ZONE_ID\s*=' "$py_script" | cut -d'"' -f2 || true)
      fi
      [[ -n "$cur_zone" ]] || cur_zone="${CF_ZONE_ID:-}"
      [[ -n "$cur_token" ]] || cur_token="${CF_TOKEN:-${CF_Token:-}}"
      [[ -n "$cur_zone" && -n "$cur_token" ]] || fail "缺少 Cloudflare 凭据，请先执行 ${MANAGE_CMD} bestcf setup"

      python3 -c "
import json, subprocess, sys

token = '${cur_token}'
zone = '${cur_zone}'
cf_bin = '${cf_bin}'

cmd = [cf_bin, 'dns', 'records', 'list', '--zone', zone, '-q']
env = {'CLOUDFLARE_API_TOKEN': token, 'PATH': '/usr/local/bin:/usr/bin:/bin'}
res = subprocess.run(cmd, env=env, capture_output=True, text=True)

if res.returncode != 0:
    print('调用 cf CLI 失败:', res.stderr)
    sys.exit(1)

raw = res.stdout[res.stdout.find('['):]
try:
    records = json.loads(raw)
except Exception as e:
    print('解析 Cloudflare 返回数据失败:', e)
    sys.exit(1)

print('')
print(f'\033[1;36m=== Cloudflare DNS 全面规范性体检 (共 {len(records)} 条解析) ===\033[0m')
for r in records:
    name = r.get('name', '')
    rtype = r.get('type', '')
    content = r.get('content', '')
    proxied = r.get('proxied', False)
    ttl = r.get('ttl', 0)
    
    proxy_str = '\033[1;33m已开启 (小黄云代理)\033[0m' if proxied else '\033[1;32m仅DNS (灰色云朵)\033[0m'
    print(f'• [{rtype}] {name} -> {content} | 状态: {proxy_str} | TTL: {ttl}s')

    if name.startswith('bestcf.'):
        if proxied:
            print('  \033[1;31m[严重异常] 优选域名绝对不能开启 CDN 代理，必须为灰云！\033[0m')
        elif ttl > 120:
            print('  \033[1;33m[优化建议] 优选域名 TTL 建议设为 60s 以便故障极速切换。\033[0m')
        else:
            print('  \033[1;32m[配置正确] 优选域名为纯 DNS 极速直连 (TTL 60s)。\033[0m')
    elif name.startswith('cdn.'):
        if not proxied:
            print('  \033[1;33m[警告] CDN 域名未开启小黄云代理，真实 IP 未被隐藏。\033[0m')
        else:
            print('  \033[1;32m[配置正确] CDN 域名已开启小黄云回源代理。\033[0m')
    elif name.startswith('reality.'):
        if proxied:
            print('  \033[1;31m[严重异常] Reality 直连域名不能开启小黄云代理！\033[0m')
        else:
            print('  \033[1;32m[配置正确] Reality 域名为纯 DNS 直连。\033[0m')
print('')
"
      ;;
    run)
      if [[ ! -x "$py_script" ]]; then
        fail "未找到 ${py_script}，请先执行 ${MANAGE_CMD} bestcf setup"
      fi
      local lock_file="${dir}/lock"
      local locked_ip_file="${dir}/locked_ips.txt"
      if [[ -f "$lock_file" || -f "$locked_ip_file" ]]; then
        echo -e "${YELLOW}[!] 当前优选 IP 正处于【锁定模式】${NC}"
        read -rp "是否确认强制重新测速并同步最优 IP？[y/N]: " confirm_run
        if [[ ! "${confirm_run:-n}" =~ ^[Yy]$ ]]; then
          info "已取消操作，保持当前优选 IP 锁定状态不变。"
          return 0
        fi
      fi
      info "正在手动触发测速与 DNS 解析同步 (约需 10~30 秒)..."
      "$py_script" --force
      if [[ -f "$lock_file" || -f "$locked_ip_file" ]]; then
        # 同步更新锁定列表中的 IP
        if [[ -n "$cur_domain" ]] && command -v getent >/dev/null 2>&1; then
          getent ahostsv4 "$cur_domain" 2>/dev/null | awk '{print $1}' | sort -u > "${dir}/locked_ips.txt"
        fi
      fi
      info "测速与 DNS 解析同步完成！"
      ;;
    lock)
      mkdir -p "$dir"
      local cur_domain cur_zone cur_token
      if [[ -f "$py_script" ]]; then
        cur_domain=$(grep -E '^\s*DOMAIN_NAME\s*=' "$py_script" | cut -d'"' -f2 || true)
        cur_zone=$(grep -E '^\s*CF_ZONE_ID\s*=' "$py_script" | cut -d'"' -f2 || true)
        cur_token=$(grep -E '^\s*CF_TOKEN\s*=' "$py_script" | cut -d'"' -f2 || true)
        [[ -f "${dir}/.env" ]] && cur_token=$(awk -F= '$1 ~ /^CF_TOKEN/ {gsub(/[" '\''[:space:]]/, "", $2); print $2}' "${dir}/.env" || true)
      fi
      local cur_records=""
      if [[ -n "$cur_domain" ]] && command -v getent >/dev/null 2>&1; then
        cur_records=$(getent ahostsv4 "$cur_domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')
      fi
      if [[ -z "$cur_records" && -n "$cur_zone" && -n "$cur_token" ]]; then
        cur_records=$(python3 -c "
import urllib.request, json
try:
    url = f'https://api.cloudflare.com/client/v4/zones/${cur_zone}/dns_records?type=A&name=${cur_domain}'
    req = urllib.request.Request(url, headers={'Authorization': 'Bearer ${cur_token}'})
    with urllib.request.urlopen(req) as resp:
        print(' '.join([r['content'] for r in json.load(resp).get('result', [])]))
except Exception:
    pass
" 2>/dev/null || true)
      fi
      local lock_ips="${2:-$cur_records}"
      [[ -n "$lock_ips" ]] || fail "未能获取当前解析 IP，请通过: ${MANAGE_CMD} bestcf set <IP...> 手动指定"

      echo "$lock_ips" | tr ' ' '\n' | grep -E '^[0-9.]+$' > "${dir}/locked_ips.txt"
      touch "${dir}/lock"
      systemctl stop cf-bestip.timer 2>/dev/null || true
      systemctl disable cf-bestip.timer 2>/dev/null || true

      info "已成功锁定当前优选 IP: $(tr '\n' ' ' < "${dir}/locked_ips.txt")"
      info "已停止并禁用后台定时轮换 (cf-bestip.timer)"
      info "已开启 IP 防漂移保护，后续更新与切换完全由您自主决定！"
      ;;
    unlock)
      rm -f "${dir}/lock" "${dir}/locked_ips.txt"
      systemctl enable --now cf-bestip.timer 2>/dev/null || true
      systemctl enable --now cf-healthcheck.timer 2>/dev/null || true
      info "已解除优选 IP 锁定，恢复定时自动轮换与自愈监听。"
      ;;
    set)
      local cur_domain="" cur_zone="" cur_token=""
      if [[ -f "$py_script" ]]; then
        cur_domain=$(grep -E '^\s*DOMAIN_NAME\s*=' "$py_script" | cut -d'"' -f2 || true)
        cur_zone=$(grep -E '^\s*CF_ZONE_ID\s*=' "$py_script" | cut -d'"' -f2 || true)
        cur_token=$(grep -E '^\s*CF_TOKEN\s*=' "$py_script" | cut -d'"' -f2 || true)
        [[ -f "${dir}/.env" ]] && cur_token=$(awk -F= '$1 ~ /^CF_TOKEN/ {gsub(/[" '\''[:space:]]/, "", $2); print $2}' "${dir}/.env" || true)
      fi

      local input_ips="${2:-}"
      if [[ -z "$input_ips" ]]; then
        local cur_ip_str=""
        [[ -f "${dir}/locked_ips.txt" ]] && cur_ip_str=$(tr '\n' ' ' < "${dir}/locked_ips.txt")
        [[ -z "$cur_ip_str" && -n "$cur_domain" ]] && cur_ip_str=$(getent ahostsv4 "$cur_domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')
        echo -e "当前解析 IP: ${cur_ip_str:-未获取到}"
        read -rp "请输入要指定并锁定的 Cloudflare IP (多个 IP 空格隔开): " input_ips
      fi
      [[ -n "$input_ips" ]] || fail "IP 不能为空"

      if [[ -n "$cur_domain" && -n "$cur_zone" && -n "$cur_token" ]]; then
        python3 -c "
import urllib.request, json
ips = '${input_ips}'.strip().split()
headers = {'Authorization': 'Bearer ${cur_token}', 'Content-Type': 'application/json'}
url = f'https://api.cloudflare.com/client/v4/zones/${cur_zone}/dns_records?type=A&name=${cur_domain}'
req = urllib.request.Request(url, headers=headers)
with urllib.request.urlopen(req) as resp:
    records = json.load(resp).get('result', [])
deletes = [{'id': r['id']} for r in records]
posts = [{'type': 'A', 'name': '${cur_domain}', 'content': ip, 'ttl': 60, 'proxied': False, 'comment': 'Auto BestCF Locked'} for ip in ips]
batch_url = f'https://api.cloudflare.com/client/v4/zones/${cur_zone}/dns_records/batch'
b_req = urllib.request.Request(batch_url, headers=headers, data=json.dumps({'deletes': deletes, 'posts': posts}).encode('utf-8'))
with urllib.request.urlopen(b_req) as resp:
    res = json.load(resp)
if res.get('success'):
    print('已成功同步至 Cloudflare DNS 记录！')
else:
    print('DNS 批量更新未成功:', res.get('errors'))
" 2>/dev/null || true
      fi

      mkdir -p "$dir"
      echo "$input_ips" | tr ' ' '\n' | grep -E '^[0-9.]+$' > "${dir}/locked_ips.txt"
      touch "${dir}/lock"
      systemctl stop cf-bestip.timer 2>/dev/null || true
      systemctl disable cf-bestip.timer 2>/dev/null || true
      info "已更新 DNS 并锁定为目标 IP: ${input_ips}"
      info "后台定时轮换已停用，后续更新由您自主决定。"
      ;;
    interval)
      local int_val="${2:-}"
      if [[ -z "$int_val" ]]; then
        echo -e "定时周期预设:"
        echo -e "  0) lock  - 锁定当前 IP，关闭自动轮换 (完全由我自主决定)"
        echo -e "  1) peak  - 每日高峰模式 (推荐: 12:30, 19:00-23:00 每整点, 04:00 凌晨基准)"
        echo -e "  2) 1h    - 每 1 小时定时轮换"
        echo -e "  3) 2h    - 每 2 小时定时轮换"
        echo -e "  4) 4h    - 每 4 小时定时轮换"
        echo -e "  5) 6h    - 每 6 小时定时轮换"
        read -rp "请输入选项 [0/peak/1h/2h/4h/6h]: " int_val
      fi
      [[ -n "$int_val" ]] || fail "周期不能为空"
      case "$int_val" in
        0|lock|LOCK)
          cmd_bestcf lock
          return 0
          ;;
        1|peak|PEAK) int_val="peak" ;;
        2) int_val="1h" ;;
        3) int_val="2h" ;;
        4) int_val="4h" ;;
        5) int_val="6h" ;;
        *)
          # 若输入纯数字，默认单位是小时 (例如输入 4 -> 4h，避免 systemd 误按秒执行导致死循环)
          if [[ "$int_val" =~ ^[0-9]+$ ]]; then
            int_val="${int_val}h"
          fi
          ;;
      esac
      rm -f "${dir}/lock" "${dir}/locked_ips.txt"
      [[ -f "$timer_file" ]] || fail "定时器文件不存在，请先执行 ${MANAGE_CMD} bestcf setup"
      if [[ "$int_val" == "peak" ]]; then
        cat > "$timer_file" <<TMREOF
[Unit]
Description=Run Cloudflare Best IP DNS Auto-Updater periodically

[Timer]
OnBootSec=3min
OnCalendar=*-*-* 04:00:00
OnCalendar=*-*-* 12:30:00
OnCalendar=*-*-* 19..23:00:00
Persistent=true

[Install]
WantedBy=timers.target
TMREOF
        int_val="每日高峰模式 (12:30, 19:00-23:00 每整点, 04:00)"
      else
        cat > "$timer_file" <<TMREOF
[Unit]
Description=Run Cloudflare Best IP DNS Auto-Updater periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=${int_val}
Persistent=true

[Install]
WantedBy=timers.target
TMREOF
      fi
      systemctl daemon-reload
      systemctl enable --now cf-bestip.timer
      info "定时周期已更新为: ${int_val} (已恢复自动轮换)"
      ;;
    on)
      rm -f "${dir}/lock" "${dir}/locked_ips.txt"
      systemctl enable --now cf-bestip.timer 2>/dev/null || true
      systemctl enable --now cf-healthcheck.timer 2>/dev/null || true
      info "Cloudflare 优选定时轮换与故障自愈监听已开启 (已解除锁定)"
      ;;
    off)
      cmd_bestcf lock
      systemctl stop cf-healthcheck.timer 2>/dev/null || true
      systemctl disable cf-healthcheck.timer 2>/dev/null || true
      info "已暂停后台监听服务，当前 IP 保持锁定"
      ;;
    *)
      fail "用法: ${MANAGE_CMD} bestcf [show|lock|unlock|set|interval|check|run|audit|setup|on|off]"
      ;;
  esac
}

# ---------- Cloudflare Argo 隧道管理 (cloudflared) ----------
ARGO_BIN="/usr/local/bin/cloudflared"
ARGO_SERVICE="cloudflared"

cmd_argo_update() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l|armhf) arch="arm" ;;
    *) warn "暂不支持当前 CPU 架构: $(uname -m)"; return 1 ;;
  esac
  info "正在检测并下载 Cloudflare 官方最新 cloudflared (linux-$arch) 内核……"
  local tmp
  tmp=$(mktemp)
  if curl -fsSL --max-time 120 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o "$tmp"; then
    chmod +x "$tmp"
    if "$tmp" --version >/dev/null 2>&1; then
      mv -f "$tmp" "$ARGO_BIN"
      chmod +x "$ARGO_BIN"
      info "Cloudflare Argo 隧道 (cloudflared) 已成功更新至最新版：$($ARGO_BIN --version 2>/dev/null | head -1)"
      systemctl is-active "$ARGO_SERVICE" >/dev/null 2>&1 && systemctl restart "$ARGO_SERVICE"
      return 0
    else
      rm -f "$tmp"
      warn "下载的 cloudflared 二进制校验失败"
      return 1
    fi
  else
    rm -f "$tmp"
    warn "从 Cloudflare 官方 GitHub 下载 cloudflared 失败"
    return 1
  fi
}

cmd_argo() {
  local action="${1:-status}"
  shift || true
  case "$action" in
    status)
      echo ""
      echo -e "${CYAN}=== Cloudflare Argo 隧道 (cloudflared) 状态 ===${NC}"
      if [[ -x "$ARGO_BIN" ]]; then
        echo -e "  内核版本:     ${GREEN}$($ARGO_BIN --version 2>/dev/null | head -1)${NC}"
      else
        echo -e "  内核版本:     ${YELLOW}未安装 (运行 ${MANAGE_CMD} argo update 即可一键自动安装)${NC}"
      fi
      if systemctl is-active "$ARGO_SERVICE" >/dev/null 2>&1; then
        echo -e "  隧道服务:     ${GREEN}运行中 (active)${NC}"
      else
        echo -e "  隧道服务:     ${YELLOW}未运行 (inactive)${NC}"
      fi
      ;;
    update|up)
      cmd_argo_update
      ;;
    token|run|on)
      local token="${1:-}"
      if [[ -z "$token" ]]; then
        read -rp "请输入 Cloudflare Zero Trust Tunnel Token: " token
      fi
      [[ -n "$token" ]] || { warn "Token 不能为空"; return 1; }
      [[ -x "$ARGO_BIN" ]] || cmd_argo_update || return 1
      info "正在配置并启动 Cloudflare Argo 隧道服务……"
      "$ARGO_BIN" service install "$token" 2>/dev/null || true
      systemctl daemon-reload
      systemctl enable --now "$ARGO_SERVICE" 2>/dev/null || true
      info "Cloudflare Argo 隧道服务已启动并设为开机自启！"
      ;;
    off|stop|disable)
      info "正在停止并卸载 Cloudflare Argo 隧道服务……"
      systemctl stop "$ARGO_SERVICE" 2>/dev/null || true
      systemctl disable "$ARGO_SERVICE" 2>/dev/null || true
      [[ -x "$ARGO_BIN" ]] && "$ARGO_BIN" service uninstall 2>/dev/null || true
      info "Cloudflare Argo 隧道已停止"
      ;;
    *)
      echo "用法: ${MANAGE_CMD} argo [status|update|on [token]|off]"
      ;;
  esac
}

# ---------- Cloudflare WARP 出站状态与更新 ----------
cmd_warp() {
  local action="${1:-status}"
  shift || true
  local warp_conf="/root/sbbox/warp.json"
  case "$action" in
    status)
      echo ""
      echo -e "${CYAN}=== Cloudflare WARP 状态 ===${NC}"
      if [[ -s "$warp_conf" ]]; then
        local warp_v6
        warp_v6=$(python3 -c "import json; print(json.load(open('$warp_conf')).get('v6',''))" 2>/dev/null)
        echo -e "  WARP 凭证:    ${GREEN}已就绪 ($warp_conf)${NC}"
        echo -e "  专属 IPv6:    ${CYAN}${warp_v6}${NC}"
      else
        echo -e "  WARP 凭据:    ${YELLOW}未生成 (可运行 ${MANAGE_CMD} warp update 动态申请)${NC}"
      fi
      ;;
    update|up|rotate)
      info "正在通过 Cloudflare 官方 API 动态申请与更新专属 WARP 账户凭证……"
      if command -v sbbox >/dev/null 2>&1; then
        sbbox warp rotate
      else
        warn "未检测到 sbbox 命令"
      fi
      ;;
    *)
      echo "用法: ${MANAGE_CMD} warp [status|update]"
      ;;
  esac
}
