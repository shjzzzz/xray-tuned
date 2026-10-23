#!/usr/bin/env python3
"""把 /usr/local/etc/xray/config.json 拆成两份（config.json 仍是唯一的真源，xh 的各种改配置命令照常工作）：
  /run/xray-split/main.json     —— 新内核（xray）：除 REALITY 外的所有入站
  /run/xray-split/reality.json  —— 兼容内核（xray-legacy，< 26.9.8）：security=reality 的入站
原因：xtls/reality 自 2026-09-08 起服务端拒绝不带 X25519MLKEM768 的 ClientHello，
Shadowrocket / 旧 utls 指纹的客户端因此连不上 REALITY；兼容内核不做这个检查。
由 xray.service / xray-reality.service 的 ExecStartPre 调用；xh 的 `systemctl restart xray` 会经 PartOf 一并重启兼容实例。"""
import json, os, re, sys, grp

SRC = "/usr/local/etc/xray/config.json"
DST = "/run/xray-split"

def strip_jsonc(s):
    out, i, n, instr = [], 0, len(s), False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if c == "\\" and i + 1 < n: out.append(s[i + 1]); i += 1
            elif c == '"': instr = False
        elif c == '"': instr = True; out.append(c)
        elif c == "/" and s[i:i + 2] == "//":
            while i < n and s[i] != "\n": i += 1
            continue
        elif c == "/" and s[i:i + 2] == "/*":
            i = s.index("*/", i + 2) + 1
        else: out.append(c)
        i += 1
    t = "".join(out)
    t = re.sub(r",(\s*[}\]])", r"\1", t)          # 尾逗号
    t = re.sub(r"(\[\s*),", r"\1", t)             # 注释块删掉后留下的前导逗号
    return t

def is_reality(ib):
    return (ib.get("streamSettings") or {}).get("security") == "reality"

cfg = json.loads(strip_jsonc(open(SRC, encoding="utf-8").read()))
rea = [i for i in cfg["inbounds"] if is_reality(i)]
# xh minversion 只改第一个 REALITY 入站；这里让其余入站沿用同一个 minClientVer，
# 否则第三方客户端（版本字段为 0）会被内核默认的 26.3.27 下限拒绝
_mv = next((i["streamSettings"]["realitySettings"]["minClientVer"] for i in rea
            if i["streamSettings"].get("realitySettings", {}).get("minClientVer")), None)
if _mv:
    for i in rea: i["streamSettings"]["realitySettings"].setdefault("minClientVer", _mv)
main = dict(cfg, inbounds=[i for i in cfg["inbounds"] if not is_reality(i)])
legacy = dict(cfg, inbounds=rea)

os.makedirs(DST, exist_ok=True)
gid = grp.getgrnam("xray").gr_gid
os.chown(DST, 0, gid); os.chmod(DST, 0o750)

def put(name, obj):
    p = os.path.join(DST, name)
    if obj is None:
        try: os.remove(p)
        except FileNotFoundError: pass
        return
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f: json.dump(obj, f, ensure_ascii=False, indent=2)
    os.chown(tmp, 0, gid); os.chmod(tmp, 0o640)
    os.replace(tmp, p)

put("main.json", main)
put("reality.json", legacy if rea else None)
print(f"xh-split-config: main {len(main['inbounds'])} 入站, reality {len(rea)} 入站", file=sys.stderr)
