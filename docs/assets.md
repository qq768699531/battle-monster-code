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

整张 `ui_window.webp` 仍保留，仅作为运行时精灵 id（`common/ui_window/frame-NNN`）的图集，
供 6 个数据驱动脚本按 id 取帧；界面场景已不再引用它。

## 玩法数据表

`core/gameplay.tres`（322 KB，6 张表塞在一起）已按功能拆开，各自放到使用它的目录：

| 表 | 文件 | 记录数 | 体量 |
| --- | --- | --- | --- |
| `items` | `core/gameplay_items.tres` | 367 | 125 KB |
| `monsters` | `monsters/gameplay_monsters.tres` | 132 | 50 KB |
| `passives` | `battle/gameplay_passives.tres` | 168 | 26 KB |
| `encounters` | `field/gameplay_encounters.tres` | 149 | 73 KB |
| `script_battles` | `battle/gameplay_script_battles.tres` | 98 | 32 KB |
| `npcs` | `field/gameplay_npcs.tres` | 52 | 8 KB |

`ResourceCatalog.load_gameplay_catalog()` 在首次访问时把六份拼回一个 `GameplayData` 门面对象，
所以 `catalog.monster(id)`、`catalog.item(id)` 等调用点与传入 `GameplayData` 的 40 多处签名都不用改。
