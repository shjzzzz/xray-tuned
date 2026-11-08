"""把 sbbox(sing-box)的 Mihomo 节点并入 Xray 的 Mihomo 订阅文件。

用法: merge_sbbox_mihomo.py <目标 yaml> [clmi.yaml，缺省 /root/sbbox/clmi.yaml]
- 数据源 clmi.yaml 由 sbbox 维护，已是 Mihomo 格式；本脚本只搬运，不改参数。
- 节点名加 SB- 前缀（sing-box 的 Hysteria2-TLS-BBR-Salamander 与 Xray 同名）。
- 文本级插入，保留目标文件的缩进与注释；幂等：目标里已有的同名节点不会重复添加。
- clmi.yaml 不存在 / 没有 PyYAML / 没有 proxies → 原样退出 0（sbbox 是可选组件）。
- Mihomo 没有 Naive 出站，clmi.yaml 里本来就没有，这里不处理。
"""
import os
import re
import sys

PREFIX = "SB-"
DIRECT_GROUP = "直连择优"  # 唯一以显式列表（非 include-all）列节点的组，且只含直连节点


def load_proxies(clmi_path):
    try:
        import yaml
    except ImportError:
        return []
    if not os.path.isfile(clmi_path):
        return []
    with open(clmi_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    out = []
    for p in data.get("proxies") or []:
        if isinstance(p, dict) and p.get("name"):
            q = dict(p)
            q["name"] = PREFIX + str(p["name"])
            out.append(q)
    return out


def merge(text, proxies):
    import yaml
    lines = text.split("\n")
    try:
        start = lines.index("proxies:")
    except ValueError:
        return text
    # proxies 块：之后的缩进行、列表项、注释与空行；遇到下一个顶层键结束
    end = start + 1
    last = start
    item_indent = ""
    while end < len(lines):
        ln = lines[end]
        if ln.strip() and not ln.startswith((" ", "-", "#")):
            break
        if ln.strip() and not ln.lstrip().startswith("#"):
            last = end
            m = re.match(r"^(\s*)- name:", ln)
            if m and not item_indent:
                item_indent = m.group(1)
        end += 1
    existing = set(re.findall(r"^\s*- name:\s*(.+?)\s*$", "\n".join(lines[start:end]), re.M))
    new = [p for p in proxies if p["name"] not in existing]
    if not new:
        return text
    dumped = yaml.safe_dump(new, default_flow_style=False, sort_keys=False, allow_unicode=True)
    block = [(item_indent + l) if l else l for l in dumped.rstrip("\n").split("\n")]
    lines[last + 1:last + 1] = block

    # 直连择优：在该组 proxies 列表末尾追加
    for i, ln in enumerate(lines):
        if re.match(r"^\s*-?\s*name:\s*%s\s*$" % DIRECT_GROUP, ln):
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*proxies:\s*$", lines[j]):
                if re.match(r"^\s*- name:", lines[j]):
                    j = len(lines)  # 下一个组了，本组没有显式列表
                    break
                j += 1
            if j >= len(lines):
                break
            k = j + 1
            item = None
            while k < len(lines) and re.match(r"^\s*(- |#)", lines[k]):
                if lines[k].lstrip().startswith("- "):
                    item = k
                k += 1
            if item is not None:
                ind = re.match(r"^(\s*)", lines[item]).group(1)
                lines[item + 1:item + 1] = [f"{ind}- {p['name']}" for p in new]
            break
    return "\n".join(lines)


if __name__ == "__main__":
    target = sys.argv[1]
    clmi = sys.argv[2] if len(sys.argv) > 2 else "/root/sbbox/clmi.yaml"
    if not os.path.isfile(target):
        sys.exit(0)
    proxies = load_proxies(clmi)
    if not proxies:
        sys.exit(0)
    with open(target, encoding="utf-8") as f:
        src = f.read()
    out = merge(src, proxies)
    if out != src:
        tmp = target + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(out)
        os.replace(tmp, target)
