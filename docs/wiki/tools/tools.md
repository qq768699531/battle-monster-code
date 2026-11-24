# 工具手册（`tools\`）

索引：[`../README.md`](../README.md)

`tools\` 下每个工具一本手册：命令、参数、产出、失败处置。**一般使用只读本组页面，不读工具源码**。

| 页 | 用途 |
| --- | --- |
| [`res-outline.md`](res-outline.md) | `.tres`／`.tscn` 结构清单，按行号精读 |
| [`run-tests.md`](run-tests.md) | 跑指定的 GUT 用例 |

## 通用约定

- 工具一律幂等：重跑不改仓库内容。
- 失败只贴退出码与末几行；不为「弄清楚」去读工具源码。
- `tools\` 带 `.gdignore`，Godot 不扫描本目录，`.py` 不会被当成资源导入。

## 不在本仓库的工具

`probe_ida.py`、`export_*.py`、`convert_ani.py`、`parse_qstlist.py`、`ani_actions.py`、
`check_conventions.py`、`script\legacy\` 的格式解析器，以及它们的手册，都随原版取证材料放在
decompile 仓库：它们读的是原版 APK／IDA 快照，或（`check_conventions.py`）绑定了旧仓库的
`AGENTS.md` 与 `script/ani_actions.py`。
