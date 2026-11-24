# 目录结构

仓库按**分层 + 模块 + 子域**三级组织。每个对象目录里场景、脚本、数据、贴图同层（一个对象一个目录）。

```text
engine/          与玩法无关、可复用的底层
  ui/            通用控件：窗框、数字、标签、触控、消息栈、主题…
  data/          装载与索引：resource_catalog、sprite_index、gameplay_data、text_tables、story、save_store
  anim/          ANI 播放器：monster_animation、ani_action、ani_back_buffer

game/            玩法模块（每个模块内部按子域分组）
  battle/        combat（逻辑与数据）／presentation（画面与表现）／arena（战场场景）
  field/         runtime／map／quests／guild／shops／dialogue／encounters／monsters／actors／network
  menu/          screen／book／item／party／status／quest／world_map／options／network
  prime/         entry／startup／title／network／settings／slots／pages／ui／data
  growth/        怪物养成规则：属性、成长、合成、合成表

content/         美术与音频内容
  actors/        hero／npc／portrait（每个对象一个目录：场景 + 图集）
  monsters/      mon1／mon2（怪物 ANI 场景与定义）／b_effect／b_icon／b_icon2
  audio/         audio_manager 与本地 ogg

tests/           GUT 用例与测试脚本
tools/           自有工具（资源轮廓、本地服务），带 .gdignore 不被引擎扫描
docs/            文档：结构、资源约定、wiki、对账记录
addons/          GUT 9.6.1（vendored，MIT）
```

## 全局单例（autoload）

| 名字 | 资源 | 作用 |
| --- | --- | --- |
| AssetCatalog | ngine/data/resource_catalog/resource_catalog.gd | 贴图/音频/数据/文本的唯一入口 |
| AudioManager | content/audio/audio_manager/audio_manager.tscn | 音频播放与总线 |
| NativeTouchFeedback | game/field/runtime/native_touch_feedback/native_touch_feedback.tscn | 触控反馈 |
| Messages | ngine/ui/message_stack/message_stack.tscn | 原生 Game_infoDraw 提示栈：全局浮层，任何脚本用 MessageStack.say* 静态入口推送，不再从主场景下发节点 |

## 三条约定

1. **分层看依赖方向**：`content ← game ← engine`。`engine` 不引用 `game`/`content` 的场景；
   `game` 可以引用 `engine` 与 `content`。
2. **模块内部再分一层子域**：一个子域放同一功能的若干对象目录（例如 `game/field/quests/` 下的
   `quest_complete`、`quest_detail`、`quest_set`），不再把 40 多个目录平铺在一层。
3. **对象目录不拆**：`<对象>/` 里放它自己的 `.tscn`、`.gd`、`.tres`、`.webp`，方便整目录移动。

## 与原版无关的内容不进这个仓库

原版解包材料、IDA 快照、格式解析器与取证 wiki 在独立的 decompile 仓库，见
[port-audit.md](port-audit.md)。
