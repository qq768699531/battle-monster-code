# 目录与资源约定

仓库按**用途**分目录，不按文件类型分层。一个对象的场景、脚本、数据与贴图放在同一个目录：

```text
monsters/mon1/m_f_000/
  m_f_000.tscn      场景
  m_f_000.webp      该对象整张精灵图（无损 WebP）
field/food_shop/
  food_shop.tscn    场景
  food_shop.gd      该场景的脚本
maps/m0/
  m0.tscn           地图场景（挂 scripts maps/map.gd 的 BattleMap 基类）
  t0_0.tscn         地形层
  m0_0.tres         TileSet（普通 Texture2D 引用，不能用 AtlasTexture）
  m0_0.webp         地图图层
core/number/
  number_default.tscn / number_top.tscn / number_small.tscn / number_compact.tscn
  ui_number.webp    数字图集，由预设场景自身持有
core/theme/
  ui_theme.tres     全局主题（字号、字体槽位）
  boutique-*.ttf    原版字体，本地补齐
```

## 顶层目录

| 目录 | 用途 |
| --- | --- |
| `core/` | 跨功能运行时：`story`、`save_store`、`world_resources`、`resource_catalog`、`sprite_index`、`gameplay.tres`、`shaders/` |
| `data/` | 跨功能数据类型定义（`ItemDefinition`、`MonsterDefinition` 等 Resource 脚本） |
| `core/` 下的组件目录 | 通用界面组件（窗框、数字、标签、消息栈等），每个目录内场景+脚本+图集同层 |
| `battle/` `field/` `menu/` `prime/` `main/` | 各自功能的场景、脚本、数据 |
| `actors/` `monsters/` `maps/` | 按对象/地图组存放的角色、怪物、地图 |
| `audio/` | 音频三位一体：`audio_manager.tscn` + `audio_manager.gd` + `default_bus_layout.tres` + 本地 `ogg/` |

脚本与场景同级：共享脚本也有同名目录（`core/story/story.gd`）。

## 入库范围

| 路径 | 入库 | 说明 |
| --- | --- | --- |
| `**/*.tscn` `**/*.gd` `**/*.tres` `**/*.gdshader` | 是 | 场景、脚本、数据表、着色器 |
| `**/*.webp` `**/*.png` `**/*.jpg` | 否 | 原版美术与平台图标，版权归原开发方，本地补齐 |
| `audio/ogg/*.ogg` `core/theme/*.ttf` | 否 | 原版音频与字体 |
| `**/*.import` | 否 | Godot 导入缓存 |

## 精灵图约定

- **一个对象一张图集**：该对象的动画帧合并成 `<对象名>.webp`，网格排布、无损编码。
  （有损 WebP 重编码会让像素画掉色，最坏单通道差 218/255，必须 `lossless=True`。）
- 场景用 `AtlasTexture` 引用帧：`atlas` 指向图集，`region` 是该帧矩形；动画轨道
  `values` 从 `ExtResource` 换成 `SubResource`。
- **地图图层例外**：每层本来就是单帧整图，直接 `<对象名>.webp`，TileSet 用普通
  `Texture2D`——`AtlasTexture` 会让 Godot 拒绝创建任何 tile。
- 运行时按 id 取帧走 `core/sprite_index.gd`：`对象/frame-NNN` → `[图集路径, 帧矩形]`，
  共 6,038 帧；`ResourceCatalog.load_sprite()` 据此切 `AtlasTexture`。
- 通用组件自带图集（如 `core/number/number_*.tscn`），其余场景实例化组件，而不是各自引用贴图。

## 本地补齐二进制资源

克隆后只有场景/脚本/数据，运行前把原版资源按原相对路径放回：

```text
<各功能目录>/<对象>/<对象>.webp
audio/ogg/*.ogg
core/theme/*.ttf
```

放好后导入一次：

```powershell
godot --headless --path . --import
```

## 缺资源时的表现

缺图集或字体时启动会打印 `Failed loading resource: res://...`，场景仍可加载，对应视觉元素为空。
这不是代码缺陷。

## 文本表

正文按来源前缀拆到使用方目录。启动时只加载来源清单 `core/text_sources.gd`（149 个 id，
不含正文），正文在第一次取用时才载入对应文件：

| 来源前缀 | 文件 | 体量 |
| --- | --- | --- |
| `evt/` | `field/text/evt.tres` | 83 条 / 396 KB |
| `npc/` | `field/text/npc.tres` | 27 条 / 14 KB |
| `qst/` | `field/text/qst.tres` | 18 条 / 16 KB |
| `common/` | `core/text/common.tres` | 11 条 / 262 KB |
| `skt/` `ktf/` `lgt/` … | `monsters/text/creature_names.tres` | 10 条 / 39 KB |

拆表前后 149 条正文逐条比对 sha1 一致。

## 窗框图集的拆分

`ui_window.webp` 原本是 12 个控件区域混在一张图里，19 个场景各自用 AtlasTexture 裁不同区域。
现在按实际使用的区域拆开：

| 区域 | 去处 | 说明 |
| --- | --- | --- |
| 被多个场景使用 | `core/ui_parts/<name>/` | `gold_icon`、`plus_minus`、`tab_cell`、`stat_icon`、`party_heading`、`mix_marker`，每个目录内 `.webp` + `.tscn` + `.gd` |
| 只被一个场景使用 | 该场景同目录 | `status_header`、`empty_book`、`lock`、`quest_row`、`list_button`、`rarity_bar` |
| 窗框本体 | `core/window_frame/box4.webp`、`box2.webp` | 由 `window_frame.tscn` 持有 |

整张 `ui_window.webp` 已删除，不再有脚本从图集取帧：

- 运行时仍需要的 13 个原生帧裁成独立图片，放在 `core/window_frame/frames/window-NNN.webp`；
- 脚本改用 `ResourceCatalog.load_window_frame(N)` 取图，不再经过精灵 id；
- `core/sprite_index` 里 22 条 `common/ui_window/frame-NNN` 记录一并删除；
- `core/window_frame/slot/` 的四个 30×30 格底样式改为直接引用 `frames/window-016.webp`。

## 玩法数据表

`core/gameplay.tres`（322 KB，6 张表塞在一起）已按功能拆开，各自放到使用它的目录：

| 表 | 文件 | 记录数 | 体量 |
| --- | --- | --- | --- |
| `items` | `menu/items/items.tres` | 367 | 125 KB |
| `monsters` | `core/monster_animation/monsters.tres` | 132 | 50 KB |
| `passives` | `battle/battle/passives.tres` | 168 | 26 KB |
| `encounters` | `field/field_runtime/encounters.tres` | 149 | 73 KB |
| `script_battles` | `battle/battle/script_battles.tres` | 98 | 32 KB |
| `npcs` | `field/field_actors/npcs.tres` | 52 | 8 KB |

`ResourceCatalog.load_gameplay_catalog()` 在首次访问时把六份拼回一个 `GameplayData` 门面对象，
所以 `catalog.monster(id)`、`catalog.item(id)` 等调用点与传入 `GameplayData` 的 40 多处签名都不用改。

## 数据表归属

数据表不再单独躺在功能根目录，而是移入使用它的场景目录（该目录同时有 `.tscn` 和 `.gd`）：

| 数据表 | 现在的位置 |
| --- | --- |
| 任务 / 任务文本 | `field/quest_detail/` |
| 事件文本 | `field/quest_detail/evt.tres` |
| NPC 文本 | `field/dialogue_window/npc.tres` |
| 通用文本 / 翻译 | `core/message_stack/` |
| 主题 | `core/native_label/ui_theme.tres` |
| 事件脚本表 | `main/main/events.tres` |
| 物品表 | `menu/items/items.tres` |
| 被动 `passives` / 脚本战斗 `script_battles` / 物种 | `battle/battle/` |
| 怪物表 `monsters` / 合成表 / 精灵原点 / 名称表 | `core/monster_animation/` |
| 遭遇表 `encounters` / NPC 定义 `npcs` | `field/field_runtime/`、`field/field_actors/` |
| 食谱 / 商店 / 造型 / 世界地图 | `field/food_shop/`、`field/shop_goods/`、`battle/actor/`、`menu/world_map/` |
| 音频总线布局 | `audio/default_bus_layout.tres`（与 `audio_manager` 场景同级） |

地图 TileSet（125 个）仍留在 `maps/mN/`：同目录有地图场景与地形场景，但没有脚本——它们是编辑器资源，
给每个 TileSet 配一个脚本只会产生空壳。

## 逐对象资源（monsters）

131 个怪物对象各自放在它的动画目录里，和场景、图集同级：

```text
monsters/mon2/m_b_001_1/
  m_b_001_1.tres    MonsterDefinition
  m_b_001_1.tscn    ANI 场景
  m_b_001_1.webp    图集
```

`ResourceCatalog` 递归扫描 `res://monsters` 收集这些对象并按 `id` 排序，`catalog.monster(id)` 不变。
原表里有一条没有 `id` 的空记录（`fcfde`），拆表时已丢弃。

## 被动表（passives）不拆

`PassiveDefinition` 是被动技能的效果数值（`base` / `effect` / `increment`，效果编号 0–65），
不是图标也不是逐个对象，没有对应的场景。因此它保持为一张表，放在消费它的战斗场景同级：

```text
battle/battle/passives.tres   与 battle.tscn / battle.gd 同级
```

NPC 表（52 条 `NpcDefinition`）仍是一个对象一个文件：

```text
actors/npc/objects/<id>/<id>.tres
```

## battle 的模块划分

`battle/` 只是分类层，不放文件；里面的每个模块各自一个目录：

```text
battle/
  combat/                 战斗主场景：battle.tscn + battle.gd + script_battles.tres + battle-species.tres
  passives/               被动：passives.gd + passives.tscn + passives.tres + passive_definition/
  battle_poses/           战斗定位表：battle_poses.gd + battle-poses.tres
  battle_side/            （原 battle/battle 的子模块，已平铺到这一级）
  battle_species/
  frame_pacing/
  item_effect/
  script_battle_definition/
  status_effect/
  actor/ battle_view/ field/ …（其余模块）
```

被动逻辑（66 项效果折算）从 `battle.gd` 抽到 `passives.gd`，`battle.gd` 只保留
`Passives.effect_table(catalog, slot_table)` 的调用。

## 精灵图命名

图集文件名跟模块名一致：

- 模块只有一张图时，文件名 = 模块目录名（`menu/items/items.webp`、`battle/castle_back/castle_back.webp`）
- 模块有多张图时，以模块名作前缀：`core/window_frame/window_frame_box2.webp`、
  `core/window_frame/frames/window_frame_016.webp`、`main/main/main_title-0.webp`
- 地图是例外：一个地图组目录下有多张图层（`maps/m0/m0_0.webp` …），各自的 TileSet 直接引用，
  无法合成单张图（TileSet 不接受 AtlasTexture），因此保留 `mN_K` 命名

## 目录只有两种角色

- **分类层**：只放子目录，不放任何 `.gd` / `.tscn` / `.tres`（如 `battle/`、`core/`、`field/`）
- **模块**：只放自己的场景、脚本、数据与图集，不再嵌套其他模块

原先嵌在业务模块里的定义已全部提到分类层：`core/msg`、`core/text_tables`、
`core/ani_action`、`core/monster_attribute`、`core/monster_growth`、`core/monster_mix`、
`core/monster_mix_table`、`core/sprite_origins`、`core/touch_code`、`field/encounter_entry`、
`field/field_action`、`field/food_recipes`、`field/quest_goals`、`field/quest_mark`、
`field/quests_def`、`field/shop_table`、`main/event_scripts`、`menu/item_kind`、
`menu/slot_frame`、`menu/slot_frames`、`menu/slot_grade`、`menu/world_map_data`。
`audio/` 的散落文件收进 `audio/audio_manager/`，`core/text_sources.gd` 并入
`core/resource_catalog/`，`core/window_frame/frames/` 的图片平铺回模块根。

## 一个模块一张图

每个模块只保留一张 `<模块名>.webp`，多张图合并成图集，引用改用 `AtlasTexture` 区域：

- `main/main/main.webp`：标题图 0/1 + 标题闪光，`main.gd` 里按 `Rect2` 切
- `menu/status_skill/status_skill.webp`：状态页标题条、空图鉴位、锁标记，场景内用 `AtlasTexture`
- `core/window_frame/window_frame.webp`：窗框 box2/box4 与 13 个原生帧

地图排除：`maps/mN/` 下每张图层仍是独立文件，TileSet 不接受 `AtlasTexture`。
平台图标（`main/platform-images/`）也保持独立，运行时按相对路径取。

## 四位一体：着色器跟着模块走

`core/shaders/` 已删除，11 个 `.gdshader` 分别移入使用它的模块，与场景、脚本、数据同目录：

| 着色器 | 模块 |
| --- | --- |
| `encounter_zoom` | `field/encounter_transition/` |
| `item_cell_frame` | `menu/item_cell/` |
| `map_blend` | `field/map_effect/` |
| `map_filter` | `field/field_runtime/` |
| `menu_map_blur` | `core/screen_shade/` |
| `prime_screen` | `main/title_visual/` |
| `prime_title` | `prime/window_title/` |
| `native_menu_brightness` | `menu/menu/` |
| `ani_brightness` | `core/monster_animation/` |
| `native_number_palette` | `core/number/` |
| `native_touch_blend` | `core/touch_button/`（391 个精灵共用） |

## 标题闪光用 native_menu_brightness

闪光不是一个新写的着色器，而是 `menu/menu/native_menu_brightness.gdshader`
（`brightness` 0–63 的量化提亮）：`Flash/Sprite` 用该材质，脚本在相位出现时把
`brightness` 设为 63。因此：

- `main.webp` 保留三块：标题图 0、标题图 1、闪光图（28×21）
- 删除自造的 `flash_glow.gdshader`，`prime_screen.gdshader` 不再需要
- 其余着色器各归其模块（`native_number_palette` 在 `core/number/`、
  `native_touch_blend` 在 `core/touch_button/`、`ani_brightness` 在 `core/monster_animation/` 等）

## main 只留入口，展示模块并入 prime

`main/` 现在只有一个模块：

```text
main/main/
  main.tscn   main.gd   main.webp
```

原 `main/` 下的展示内容全部并入 `prime/`：`background`、`boundary`、`elogo`、
`ensony`、`loading`、`platform-images`、`title`、`title_item`、`title_visual`、
`ui_select`、`ui_touch`。标题闪光仍在 `prime/title_visual/`，材质用
`menu/menu/native_menu_brightness.gdshader`。

## 入口只有根目录的 main.tscn

`main/` 目录已删除：入口场景是仓库根的 `main.tscn`，它的控制器在 `prime/entry/entry.gd`
（类名 `Main`），标题图并入 `prime/title_visual/title_visual.webp` 的底部两格。

```text
main.tscn                    入口（project.godot 的 run/main_scene）
prime/entry/entry.gd         入口逻辑
prime/title_visual/          标题可视层、标题图、闪光
```

## NPC 数据就近存放

52 条 `NpcDefinition` 不再集中在 `objects/`，而是放进各自角色场景目录（三位一体）：

```text
actors/npc/n_f_04/    n_f_04.tscn + n_f_04.webp + 4.tres
actors/hero/h_f_01/   h_f_01.tscn + h_f_01.webp + 0.tres   （NPC 0 用主角正面）
actors/hero/h_b_01/   h_b_01.tscn + h_b_01.webp + 1.tres   （NPC 1 用主角背面）
```

`ResourceCatalog.GAMEPLAY_OBJECT_DIRS["npcs"]` 改为递归扫描 `res://actors`。

## actors 的分组

`actors/` 不再把立绘、物件、特效都平铺在根上：

```text
actors/
  portrait/fc00 … fc49     角色立绘（face/fcNN）
  objects/obj_f_01 … obj_f_99  场景物件演员
  effects/ui_eff, f_emoticon   特效演员
  hero/h_f_01, h_b_01          主角
  npc/n_f_02 … n_f_49          NPC
  shared/                      共用图集
```

## 共用特效按消费方拆开

`actors/effects/` 已删除：

- `f_emoticon` 无任何引用（重复场景），删除；表情统一走 `field/emotion`。
- `ui_eff` 两个消费方只用 `action_001` 的一帧（64×63），另外 4 帧与 4 段动画无人使用。
  拆成各自模块的资源：

```text
menu/book_monster/book_monster_effect.tscn + .webp
menu/status_portrait/status_portrait_effect.tscn + .webp
```

`obj/ui_eff` 的 5 条精灵索引一并移除。

## 地图物件贴图归入 maps

`actors/objects/` 已删除，7 个物件移到 `maps/objects/`：

```text
maps/objects/obj_f_01  obj_f_02  obj_f_03  obj_f_04  obj_f_07  obj_f_89  obj_f_99
```

这些是**地图上的可交互物品**（宝箱、告示牌等），不是纯装饰：

- 当前已用部分：`field/field_actors/field_actors.gd` 按
  `GROUP_OBJECT_SELECTORS = [1, 2, 3, 4, 7, 99]` 取 `obj/obj_f_%02d` 作静态绘制。
- 每个目录里的 `.tscn` 是**待实现的交互对象场景**，暂无人实例化，属于未完成功能，
  不要当成死资源删除。
- `obj/obj_f_89` 是 `obj_f_02` / `obj_f_04` 共用的帧包。
