#!/usr/bin/env python3
"""去掉 Godot 4.4+ 写进 .tscn/.tres 的 uid="uid://…" 属性。

用法：
  python tools/strip_uid.py            # 遍历仓库里的 .tscn/.tres，原地清理
  python tools/strip_uid.py --stdin    # 读 stdin 写 stdout（给 git clean filter 用）

只删 `[gd_scene … uid="…"]`、`[gd_resource … uid="…"]`、`[ext_resource … uid="…"]` 里的
uid 属性；`unique_id=`（节点身份）与其它内容不动。
"""
import re
import sys
from pathlib import Path

UID_ATTR = re.compile(r' uid="uid://[^"]*"')
ROOT = Path(__file__).resolve().parents[1]
SKIP_PARTS = {".godot", ".tmp", ".import"}


def strip(text: str) -> str:
	return UID_ATTR.sub("", text)


def main() -> None:
	if "--stdin" in sys.argv:
		sys.stdout.write(strip(sys.stdin.read()))
		return
	count = 0
	for path in sorted(ROOT.rglob("*")):
		if path.suffix not in (".tscn", ".tres"):
			continue
		if any(part in SKIP_PARTS for part in path.parts):
			continue
		text = path.read_text(encoding="utf-8")
		new = strip(text)
		if new != text:
			path.write_text(new, encoding="utf-8", newline="\n")
			count += 1
	print("stripped %d files" % count)


if __name__ == "__main__":
	main()
