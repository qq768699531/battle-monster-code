"""把旧仓库的 GUT 用例搬到当前仓库，并按文件名把 `res://` 引用改写为重构后的目录。

用法：
    python tests/tools/migrate_from_legacy.py --old ../BattleMonster/game [--apply]

不带 `--apply` 时只打印映射报告（哪些引用找不到对应文件）。
旧用例里的 `res://scripts/<名字>.gd`、`res://scenes/**/<名字>.tscn` 按 basename 在新仓库里定位；
格式串（`res://scenes/ani/%s.tscn`）和目录（`res://scenes/components/`）不会自动改写，需人工处理。
"""
import argparse
import os
import re
import shutil

RES_RE = re.compile(r"res://[A-Za-z0-9_./%-]+")
SKIP_DIRS = (".git", ".godot", ".tmp", "addons")


def build_index(root, ext):
    index = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(ext) and not name.endswith(".uid"):
                rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
                index.setdefault(name, []).append(rel)
    return index


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--old", default="../BattleMonster/game", help="旧仓库的 Godot 工程目录")
    parser.add_argument("--new", default=".", help="当前仓库根目录")
    parser.add_argument("--apply", action="store_true", help="真的写文件（默认只报告）")
    args = parser.parse_args()

    old_root = os.path.abspath(args.old)
    new_root = os.path.abspath(args.new)
    indexes = {
        ".gd": build_index(new_root, ".gd"),
        ".tscn": build_index(new_root, ".tscn"),
        ".tres": build_index(new_root, ".tres"),
    }
    unmapped = {}
    rewritten = [0]

    def resolve(match):
        path = match.group(0)
        if path.startswith("res://tests/"):
            return path
        body = path[len("res://"):]
        name = body.rsplit("/", 1)[-1]
        for ext, index in indexes.items():
            if name.endswith(ext):
                hits = index.get(name, [])
                if len(hits) == 1:
                    rewritten[0] += 1
                    return "res://" + hits[0]
                unmapped.setdefault(path, ("ambiguous" if hits else "missing", len(hits)))
                return path
        if os.path.exists(os.path.join(new_root, body.replace("/", os.sep))):
            return path
        unmapped.setdefault(path, ("missing", 0))
        return path

    old_tests = os.path.join(old_root, "tests")
    copied = 0
    for dirpath, _, filenames in os.walk(old_tests):
        for name in filenames:
            if not name.endswith(".gd") or name.endswith(".uid"):
                continue
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, old_tests)
            with open(src, "r", encoding="utf-8", newline="") as handle:
                text = handle.read()
            migrated = RES_RE.sub(resolve, text)
            copied += 1
            if args.apply:
                dst = os.path.join(new_root, "tests", rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "w", encoding="utf-8", newline="") as handle:
                    handle.write(migrated)

    print(f"tests copied={copied} refs rewritten={rewritten[0]} apply={args.apply}")
    print(f"unmapped={len(unmapped)}")
    for path, (why, count) in sorted(unmapped.items()):
        suffix = f" x{count}" if why == "ambiguous" else ""
        print(f"  {path} -> {why}{suffix}")

    if args.apply:
        for name in (".gutconfig.json",):
            src = os.path.join(old_root, name)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(new_root, name))
        src_addon = os.path.join(old_root, "addons", "gut")
        dst_addon = os.path.join(new_root, "addons", "gut")
        if os.path.isdir(src_addon) and not os.path.isdir(dst_addon):
            shutil.copytree(src_addon, dst_addon,
                            ignore=shutil.ignore_patterns("*.uid", "__pycache__"))
        print("gutconfig + addons/gut copied")


main()
