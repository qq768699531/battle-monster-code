# 旧仓库分流对账

2026-11-24 对 `..\BattleMonster`（旧仓库）与新仓库做了一次完整对账，结论：**游戏代码与数据没有丢**，
丢的是流程与知识资产，已按「是否与原版游戏相关」分流。

## 一、代码与数据：无实质丢失

| 维度 | 旧 | 新 | 说明 |
| --- | --- | --- | --- |
| `.tscn` | 826 | 861 | 缺 2：`f_emoticon.tscn` 并入 `field/emotion/emotion.tscn`；`ui_eff.tscn` 拆给图鉴页与状态页 |
| `.gd` | 260 | 358 | 缺 1：`scripts/main.gd` → `prime/entry.gd`（其余差额是迁回的 GUT 与新增用例） |
| `.gdshader` | 11 | 10 | 缺 `prime_screen.gdshader`，被 `native_menu_brightness` 取代 |
| 玩法数据记录 | — | — | `item_definition` 367=367、`passive_definition` 168=168、`encounter_definition` 149=149、`encounter_entry` 337=337、`script_battle_definition` 98=98、`npc_definition` 52=52、`monster_definition` 131=131 |
| 文本正文 | 5069 条 | 5069 条 | 旧的 10 个来源拆成 138 张表，条目数一致 |
| 翻译 `zh_CN.tres` | 358,605 B | 358,605 B | 内容一致 |
| 精灵帧 | 6076 | 6007 | 缺 69，见下 |

`monster_definition` 旧文件里有 132 条记录但其实只有 131 个 id（一条重复），去重后两边一致。

精灵帧缺的 69 张：

| 分组 | 数量 | 去向 |
| --- | --- | --- |
| `common/ui_window` | 22 | 拆成 `core/window_frame/window_frame_*.webp`（13 帧够用） |
| `common/ui_title2` | 3 | 标题闪光改程序化后删除 |
| `obj/ui_eff` | 5 | 拆给图鉴页与状态页 |
| `obj/map1/2/4/5/9_*` | 38 | 旧代码里 0 处引用，属遗留素材；若要做「地图可交互物件」需从原版重抽 |

## 二、分流：哪些进了 decompile 仓库

原则：**内容取自原版 APK／IDA 快照，或内嵌原版美术音频的，进 `battle-monster-decompile`；
本仓库自有的流程、工具与代码留在本仓库。**

| 旧路径 | 去处 | 理由 |
| --- | --- | --- |
| `assets/`（lib、res、sources、classes.dex、resources.arsc，34 MB） | `decompile/apk/` | APK 解包产物 |
| `legacy/assets/`（原版资源目录，21.5 MB） | `decompile/native-assets/` | 原版美术音频，本仓库 README 明确不入库 |
| `script/ida_snapshot/`（6 MB）＋ `probe_ida.py` | `decompile/ida/` | IDA 伪代码快照 |
| `script/export_*.py`、`convert_ani.py`、`parse_qstlist.py`、`ani_actions.py`、`glyph-unicode-map.json` | `decompile/tools/` | 读原版数据格式的导出器 |
| `script/legacy/`（64 个格式解析器）、`script/patch/` | `decompile/tools/` | 原版格式与 APK 补丁 |
| `test/`（31 个 Python 用例） | `decompile/tests/` | 测的是上面这些解析器 |
| `script/check_conventions.py` | `decompile/tools/` | 规则表绑定旧 `AGENTS.md` 与 `script/ani_actions.py`，与本仓库结构未对齐 |
| `wiki/` 的取证与格式页（109 页） | `decompile/wiki/` | 内容来源是原版二进制 |
| `script/local_service/`（3 个文件） | **本仓库** `tools/local_service/` | 自有的回环服务，Python 标准库实现，不含原版内容 |
| `script/res_outline.py` | **本仓库** `tools/res_outline.py` | 通用资源轮廓工具 |
| `script/run_tests.ps1` | **本仓库** `tests/run_tests.ps1` | 重写为适配 `tests/unit` 与无管道输出 |
| `wiki/` 的流程页（15 页） | **本仓库** `docs/wiki/` | 仓库流程与自有工具说明 |
| `skills/`（83 个文件，vendored MIT） | 未迁 | 方法论已被本会话的技能体系覆盖 |
| `.beads/`（462 MB 的 issue 库） | 未迁 | 本地状态，且与新工作流不一致 |

`legacy/` 其余路径、`assets/` 旧规则见旧仓库 `.gitignore`：原版资源在旧仓库是**入库**的，
本仓库按 README 的入库范围改为**一律不入库**，只保留本地补齐（见 [assets.md](assets.md)）。

## 三、连带修掉的问题

- `prime/entry.gd`：本地服务脚本路径改为仓库内 `tools/local_service/local_server.py`；
  `test_local_service_autostart`、`test_local_service_client` 由失败转为通过（回环服务真正可用了）。
- `tools/` 带 `.gdignore`，Godot 不扫描该目录的 `.py`。
