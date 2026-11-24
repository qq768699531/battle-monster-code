# 测试

GUT 9.6.1（`addons/gut`，MIT）＋ `tests/unit/` 下的用例，从旧仓库 `BattleMonster/game/tests` 迁回。

## 跑法

```powershell
.\tests\run_tests.ps1                                    # 关键项（默认，约 3 秒）
.\tests\run_tests.ps1 -Tests test_battle,test_world_map   # 本轮改动覆盖的用例（一次最多 3 个）
.\tests\run_tests.ps1 -All                               # 全量（6 进程并行，约 12 秒）
.\tests\run_tests.ps1 -All -Jobs 1                       # 全量串行（约 35 秒，排查用）
.\tests\run_tests.ps1 -List                              # 只列用例文件名
```

- 一次 Godot 启动跑完清单（`-gtest=` 逗号分隔），冷启动约 1.5 秒。
- **不加 `--headless`**：用例里有 `await RenderingServer.frame_post_draw` 和像素断言，headless 下会挂住。
- 第一次跑之前要导一次工程，否则 GUT 的全局类名没进 `.godot/global_script_class_cache.cfg`：

  ```powershell
  godot --headless --path . --import
  ```

- GUT 在脚本解析失败时仍会以 0 退出，`run_tests.ps1` 会拦「没跑到」并返回非 0。

## 关键项（默认档）

7 个文件、33 项断言，实测 2.7 秒（2026-11-24）：

| 用例 | 覆盖 |
| --- | --- |
| `test_battle_settlement` | 战斗结算：掉落、金币、经验写回 |
| `test_battle` | 战斗核心：行动、伤害、终局 |
| `test_save_store` | 存档读写与槽位校验 |
| `test_story` | 事件/任务流程与稳定快照 |
| `test_message_stack` | 提示栈绘制、图标、行内换色 |
| `test_quests` | 任务数据装载 |
| `test_original_resource_export` | 数据表条数与启动期资源错误 |

清单在 `run_tests.ps1` 的 `$KeyTests`。加项规矩：**加完量一次默认档总时间，超过 5 秒就换掉最贵的一项**
（各文件单独耗时：`test_ui_scene_ownership` 9.2s、`test_monster_mix` 3.8s、`test_book` 3.0s、
`test_field_runtime` 2.9s、`test_main_editor_layout` 2.4s——这些都是全量档里跑，不进关键项）。

## 全量档

57 个脚本、109 项。**默认 6 个 Godot 进程并行**，实测 12.2–12.5 秒（串行 31 秒）。
进程按「实测耗时」做 LPT 摊派（`$Weights` 表，新增重用例时补一行）；会抢同一份 `user://`
或固定端口的用例（`local_service_*`、`prime_settings_store`、`menu_map_blur`、`menu_scene_render`）
固定在 0 号进程串行跑。

注意：分片会改变同进程内的用例顺序，个别用例依赖前序用例留下的全局状态时会翻车
（`-Jobs 8` 时 `test_warp_world` 曾因前序用例残留的模糊层失败）。遇到这种情况把该用例加进
`$serial`，别靠调小并行数掩盖。

迁移方式见 `tests/tools/migrate_from_legacy.py`：旧用例的 `res://scripts/<名>.gd`、`res://scenes/**/<名>.tscn`
按 basename 改写为新目录，格式串与目录引用留人工处理。

## 失败分类

每个失败先判定是**代码错**还是**用例过期**，再动手。历史分类与已修项见
[`../docs/port-audit.md`](../docs/port-audit.md) 与 git log；当前全量档 109/109 通过。
