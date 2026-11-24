"""把 `.tres`／`.tscn` 压成「结构 + 行号」清单，供按行号精读。

Godot 资源文件是纯文本，但动辄上千行（`game/assets/text-tables.tres` 34692 行、
`game/scenes/actors/obj/obj_f_99.tscn` 1.4 MB），整读一次就烧掉整个上下文预算。
本脚本只输出骨架：段头、节点、顶层属性的行号，之后用 `code_read` 取窗口。

用法：
  python script\\res_outline.py <文件>              # 结构清单（默认 40 条、按节点树缩进）
  python script\\res_outline.py <文件> --res         # 另外列出 ext_resource／sub_resource
  python script\\res_outline.py <文件> --grep 正则    # 只看命中行（可先看资源名）
  python script\\res_outline.py <文件> --max 80      # 放宽条数
  python script\\res_outline.py <文件> --full        # 不截断

判定规则（Godot 文本格式）：
  `.tscn` 段头 `[node name="X" type="Y" parent="P"]`，缩进由 parent 链推出；
          资源默认只报条数，`--res` 才逐条列出（1.4 MB 场景常有几百张纹理）。
  `.tres` `[resource]` 段内 `键 = 值` 是顶层属性；容器按括号配对（跳过引号内文本）算行数，
          只报首行与行数，不展开内容。
"""

import argparse
import re
import sys
from pathlib import Path

HEADER_RE = re.compile(r"^\[(\w+)(.*)\]\s*$")
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
PROP_RE = re.compile(r"^([A-Za-z_][\w/]*) = (.*)$")
DEFAULT_MAX = 40
PREVIEW = 60


def read_lines(path):
    return Path(path).read_text(encoding="utf-8", errors="replace").splitlines()


def scan_sections(lines, wanted):
    """返回 (1 基行号, 标签, 属性字典) 列表。"""
    out = []
    for number, line in enumerate(lines, 1):
        match = HEADER_RE.match(line)
        if match and match.group(1) in wanted:
            out.append((number, match.group(1), dict(ATTR_RE.findall(match.group(2)))))
    return out


def section_end(lines, number):
    """下一段头的 1 基行号（没有则文件末行 + 1）。"""
    for index in range(number, len(lines)):
        if HEADER_RE.match(lines[index]):
            return index + 1
    return len(lines) + 1


def container_end(lines, index):
    """多行容器的末行 0 基下标：按括号配对计数，跳过双引号内文本。"""
    depth = 0
    quoted = False
    escaped = False
    for number in range(index, len(lines)):
        line = lines[number]
        start = line.find("= ") + 2 if number == index else 0
        for char in line[start:]:
            if escaped:
                escaped = False
            elif quoted and char == "\\":
                escaped = True
            elif char == '"':
                quoted = not quoted
            elif not quoted and char in "{[":
                depth += 1
            elif not quoted and char in "}]":
                depth -= 1
                if depth <= 0:
                    return number
    return len(lines) - 1


def outline_scene(lines, rows, with_resources):
    nodes = {}
    counts = {"ext_resource": 0, "sub_resource": 0, "connection": 0}
    sections = scan_sections(lines, ("node", "ext_resource", "sub_resource", "connection"))
    for number, tag, attrs in sections:
        if tag in counts:
            counts[tag] += 1
        if tag == "ext_resource" and with_resources:
            rows.append((0, f"L{number} ext {attrs.get('id', '?')} {attrs.get('type', '?')} {attrs.get('path', '')}"))
        elif tag == "sub_resource":
            if with_resources:
                props = section_end(lines, number) - number - 1
                rows.append((0, f"L{number} sub {attrs.get('id', '?')} ({attrs.get('type', '?')}, {props} 属性)"))
        elif tag == "node":
            name = attrs.get("name", "?")
            parent = attrs.get("parent")
            if parent is None:
                depth, path = 0, name
            else:
                base = "" if parent == "." else parent
                depth = nodes.get(base, parent.count("/") + (0 if base else -1)) + 1
                path = f"{base}/{name}" if base else name
            nodes[path] = depth
            kind = attrs.get("type") or f"实例 {attrs.get('instance', '?')}"
            rows.append((depth, f"L{number} {name} ({kind})"))
    rows.insert(0, (0, f"# 节点 {len(nodes)}，ext {counts['ext_resource']}，sub {counts['sub_resource']}，连接 {counts['connection']}"))


def outline_resource(lines, rows):
    sections = scan_sections(lines, ("gd_resource", "ext_resource", "sub_resource", "resource"))
    ext = sum(1 for _, tag, _ in sections if tag == "ext_resource")
    sub = sum(1 for _, tag, _ in sections if tag == "sub_resource")
    for number, tag, attrs in sections:
        if tag == "gd_resource":
            rows.append((0, f"L{number} {attrs.get('type', '?')} script_class={attrs.get('script_class', '-')}"))
        elif tag == "ext_resource":
            rows.append((1, f"L{number} ext {attrs.get('id', '?')} {attrs.get('type', '?')} {attrs.get('path', '')}"))
        elif tag == "sub_resource":
            props = section_end(lines, number) - number - 1
            rows.append((1, f"L{number} sub {attrs.get('id', '?')} ({attrs.get('type', '?')}, {props} 属性)"))
        else:
            for index in range(number, section_end(lines, number) - 1):
                match = PROP_RE.match(lines[index])
                if not match:
                    continue
                key, value = match.group(1), match.group(2)
                if value[:1] in "{[":
                    end = container_end(lines, index)
                    rows.append((1, f"L{index + 1} {key} = <容器 {end - index + 1} 行>"))
                else:
                    rows.append((1, f"L{index + 1} {key} = {value[:PREVIEW]}"))
    rows.insert(0, (0, f"# ext {ext}，sub {sub}"))


def main():
    parser = argparse.ArgumentParser(description="Godot .tres／.tscn 结构清单")
    parser.add_argument("file")
    parser.add_argument("--res", action="store_true", help="列出 ext_resource／sub_resource")
    parser.add_argument("--grep", default=None, help="只保留匹配该正则的行")
    parser.add_argument("--max", type=int, default=DEFAULT_MAX, help=f"最多输出条数（默认 {DEFAULT_MAX}）")
    parser.add_argument("--full", action="store_true", help="不截断")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.is_file():
        sys.exit(f"找不到文件：{path}")
    suffix = path.suffix.lower()
    if suffix not in (".tres", ".tscn"):
        sys.exit(f"只吃 .tres／.tscn，收到 {suffix or '无扩展名'}")

    lines = read_lines(path)
    rows = []
    if suffix == ".tscn":
        outline_scene(lines, rows, args.res)
    else:
        outline_resource(lines, rows)

    pattern = re.compile(args.grep) if args.grep else None
    shown = 0
    total = len(rows)
    for depth, text in rows:
        if pattern and not pattern.search(text):
            continue
        if not args.full and shown >= args.max:
            break
        print("  " * depth + text)
        shown += 1
    if not args.full and shown < total:
        print(f"-- 共 {total} 条，已显示 {shown} 条；--max 调大或 --grep 收窄 --")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
