# 测试

GUT 9.6.1（`addons/gut`，MIT）＋ `tests/unit/` 下的用例，从旧仓库 `BattleMonster/game/tests` 迁回。

## 跑法

```powershell
.\tests\run_tests.ps1 -Tests test_battle,test_world_map   # 本轮改动覆盖的用例（一次最多 3 个）
.\tests\run_tests.ps1 -All                               # 回归基线
.\tests\run_tests.ps1 -List                              # 只列用例文件名
```

- 一次 Godot 启动跑完清单（`-gtest=` 逗号分隔），冷启动 8–30 秒。
- **不加 `--headless`**：用例里有 `await RenderingServer.frame_post_draw` 和像素断言，headless 下会挂住。
- 第一次跑之前要导一次工程，否则 GUT 的全局类名没进 `.godot/global_script_class_cache.cfg`：

  ```powershell
  godot --headless --path . --import
  ```

- GUT 在脚本解析失败时仍会以 0 退出，`run_tests.ps1` 会拦「没跑到」并返回非 0。

## 当前基线

110 个用例全绿（111 项断言集，Godot 4.7.2，2026-11-24）。

迁移方式见 `tests/tools/migrate_from_legacy.py`：旧用例的 `res://scripts/<名>.gd`、`res://scenes/**/<名>.tscn`
按 basename 改写为新目录，格式串与目录引用留人工处理。

## 失败分类

每个失败先判定是**代码错**还是**用例过期**，再动手：

| 类别 | 用例 | 现象 |
| --- | --- | --- |
| 地图载荷装配失败（连锁） | `test_field_runtime`（大半）、`test_map_switch_keeps_camera_origin`、`test_message_icons`、`test_quest_gate` | `Map rules rejected the payload: res://game/field/map/map_set/m0/m0.tscn`，后续断言全挂 |
| 数据表/存档加载失败 | `test_quests`、`test_story`、`test_guild_quest`、`test_save_store`、`test_original_resource_export` | `Condition "err != OK"` ＋ 对 null 调用，疑 `.tres` 路径或接口变化 |
| 用例已过期 | `test_main_editor_layout`、`test_ui_scene_ownership`、`test_prime_title_resources` | 仍在取已删除的 `common/ui_title2` 帧、仍在扫 `res://scripts/` |
| 环境限制 | `test_prime_settings_store` 等 | `user://` 不可写（沙箱）时会失败，真机未必复现 |
| 像素/绘制断言 | `test_message_stack`（3）、`test_world_map`（2）、`test_warp_world`、`test_menu_map_blur` | 帧缓冲差分，绘制实现与原生不一致 |
| 单点缺失 | `test_field_actors`（`obj/f_emoticon` 动作号）、`test_map_renderer`（TileMapLayer 为空） | 见各用例消息 |

## 迁回过程中改掉的代码问题

- `menu/menu_view/menu_view.gd`：窗框第 5 帧仍走 `common/ui_window` 精灵 id，图集拆分后该 id 已删 → 改走 `load_window_frame(5)`。
- `core/monster_animation/monster_animation.gd`：`scene_path()` 仍按 `actors/<identity>` 拼路径，重构把角色分进
  `actors/{hero,npc,portrait}`、物件进 `field/map_actor`、标题 ANI 进 `prime` → 改为按命名空间查表并缓存。
