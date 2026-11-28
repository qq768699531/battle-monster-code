extends Node2D
const SaveData = preload("res://engine/data/save_data/save_data.gd")

## 可行动状态（地图）的总控：驱动 Story、角色绘制、镜头、HUD、菜单与战斗的切换。
## 对应原生 Field_Basic / Map_* / Evt_* 这一层；具体规则由 story.gd 与各模型脚本承担，
## 这里只负责「本帧推进什么」以及各视图之间的协调。

signal title_requested
signal shared_page_requested(page: int)
signal settings_changed(settings: Dictionary, saved: bool)
signal music_requested(resource_id: int)
signal effect_requested(resource_id: int)

const Story = preload("res://engine/data/story/story.gd")
const Battle = preload("res://game/battle/combat/battle.gd")
const ChatView = preload("res://game/field/dialogue/chat_view/chat_view.gd")
const TouchView = preload("res://game/field/runtime/touch_controls/touch_controls.gd")
const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const Followers = preload("res://game/field/actors/party_followers/party_followers.gd")
const Wild = preload("res://game/field/encounters/wild_encounters/wild_encounters.gd")
const EncounterScene = preload("res://game/field/encounters/encounter_transition/encounter_transition.tscn")
const BattleScene = preload("res://game/battle/combat/battle.tscn")
const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const BookScene = preload("res://game/menu/book/book.tscn")
const GuildMenuScene = preload("res://game/field/guild/guild_menu/guild_menu.tscn")
const GuildInfoScene = preload("res://game/field/guild/guild_info/guild_info.tscn")
const ShopListScene = preload("res://game/field/shops/shop_list/shop_list.tscn")
const FoodShopScene = preload("res://game/field/shops/food_shop/food_shop.tscn")
const QuestDetailScene = preload("res://game/field/quests/quest_detail/quest_detail.tscn")
const QuestCompleteScene = preload("res://game/field/quests/quest_complete/quest_complete.tscn")
const GuildBattle = preload("res://game/field/guild/guild_battle/guild_battle.gd")
const InnScene = preload("res://game/field/shops/inn/inn.tscn")
const WarpConfirmScene = preload("res://game/field/map/warp_confirm/warp_confirm.tscn")
const WarpWorldScene = preload("res://game/field/map/warp_world/warp_world.tscn")
const MonsterMenuScene = preload("res://game/field/monsters/monster_menu/monster_menu.tscn")
const MonsterEnchantScene = preload("res://game/field/monsters/monster_enchant/monster_enchant.tscn")
const MonsterMixScene = preload("res://game/field/monsters/monster_mix/monster_mix.tscn")
const GuildChallengeScene = preload("res://game/field/guild/guild_challenge/guild_challenge.tscn")
const GuildQuestScene = preload("res://game/field/guild/guild_quest/guild_quest.tscn")
const Book = preload("res://game/menu/book/book_model/book_model.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const WorldMapScene = preload("res://game/menu/world_map/world_map.tscn")
const WorldMap = preload("res://game/menu/world_map/world_map.gd")
## `Game_infoInit` 的任务图标帧（原生立即数 `0x94`）。
## `Item_stdAddEx@0x85BE4:73` 的 `JC_fxt2Return(416)`：正文「获得%s%s X %d」
## （`common/msg.fxt:416`），三个实参依次是品级颜色码、道具名、数量；记录号在 `Msg.Id.ITEM_OBTAINED`。
## `Item_stdGradeINDEX@0x812C8`：品级 0–3 → 行内颜色码（`#C6`–`#C9`），其余品级返回空串。
## 伪道具（组 23–26）的入手提示文案记录（`Item_datBasic@0x843D8:54-64`）：组 23／25 取
## `JC_fxt2Return(413)`「经验值」、组 24／26 取 `(414)`「金币」。正文由 `Item_stdAddEx:56-57`
## 套 `JC_fxt2Return(415)` 拼成，`Game_infoInit` 传 `0xFFFFFFFF`，所以**没有图标**。
const PSEUDO_OBTAINED_LABELS := {
	ItemKind.Pseudo.GROUP_23: Msg.Id.EXPERIENCE_LABEL,
	ItemKind.Pseudo.GROUP_24: Msg.Id.MONEY_LABEL,
	ItemKind.Pseudo.EXPERIENCE: Msg.Id.EXPERIENCE_LABEL,
	ItemKind.Pseudo.MONEY: Msg.Id.MONEY_LABEL,
}
## `Evt_msgSET@0x7CFC8:14` 的 `EX_knlSprintk(s, "#C5")`：任务提示正文的行内颜色码（调色板 5）。
## 事件指令 21 的文本源（`Evt_stdQUEST@0x7EA90:11` 的 `EFC_fsLoadRES("evt/evtlist.fxt")`）。
const EVENT_QUEST_TEXT_SOURCE := "evt/evtlist.fxt"
## 任务表按 id 从 `field/quest_set/qN/quest.tres` 合并；任务门禁与头顶任务图标共用。
const QuestSetLoader = preload("res://game/field/quests/quest_set/quest_set.gd")
const MessageStack = preload("res://engine/ui/message_stack/message_stack.gd")
const MapNameView = preload("res://game/field/map/map_name_view/map_name_view.gd")
## 像素走位的纯几何核心（逐 1px 判碰撞 + 原生侧滑扫向）。
const PixelWalk = preload("res://game/field/runtime/pixel_walk/pixel_walk.gd")
const TILE := 16.0
# Native 6/8px steps at the 50ms base interval; Engine.time_scale applies the speed setting.
const WALK_SPEED := 7.5
const RUN_SPEED := 10.0
const SCRIPT_MOVE_SPEED := 4.0
## 原生 `Field_Basic_mRun` 每帧调一次 `Map_posFOCUS`，所以镜头推进与跟随
## 收敛都以一帧为步长；移植侧一帧按 50ms 基准间隔（`EFC_thrSPEED` 的档位）算。
const CAMERA_FRAME_SECONDS := 0.05
## `Map_posFOCUS` 模式 2／3 走 `Map_posMOVE`，它的 `n7` 就是每帧位移：7／4 px。
const CAMERA_PAN_FAST_STEP := 7.0
const CAMERA_PAN_SLOW_STEP := 4.0
## `Map_posCENTER` 用整数除法做半程收敛，相邻 1px 时算出的结果可能不再变化
## （返回 2 → 原生 `+32 = 1`），所以「到位」的容差就是 1px。
const CAMERA_SETTLE_PIXELS := 1.0
## 事件淡入淡出的黑色值（`Op.FADE` 的 `color`，原生 `Evt_stdPAINT2:58-60` 的 `JC_grpSetRGB(0)`）。
const BLACK_RGB := 0x000000
## 完全不透明的 alpha（`Evt_stdPAINT2:49` 的 `32 * 8` 满档）。
const OPAQUE_ALPHA := 1.0
const DASH_WINDOW_MS := 500
## `Field_Basic_hero_DrawUI:73`：剩余分钟按 `(+7 + 59999) / 60000` 向上取整（`/` 是整数除法）。
const EXP_BONUS_MINUTE_MS := 60000
const EXP_BONUS_MINUTE_ROUND_UP := 59999
const DIRECTION_KEYS := {KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT,
	KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN}
## 地图页触控键（`EFC_mainTouch` 的键码，定义在 `touch_controls.tscn`）。
## 同一个数字在不同页面含义不同——42 在地图是图鉴、在战斗是 MON INFO、战斗页的 AUTO 是 48——所以按页面命名。
## 地图页的面板键（正数）。确认／菜单／存档分别用通用的 `TouchCode.Key.OK`／`BACK`／`HELP`。
enum FieldKey {
	MAP = 35,       ## `Field_MiniMap_init` 的世界地图窗口（面板上的 Exit 键）
	BOOK = 42,      ## 图鉴（面板上的 Action 键）
	NETWORK = 48,   ## 原生 Field_Warp1（面板上的 Network 键）
}
## `Field_Basic_mKeyPressed` 的 key==48 分支：`(1 << map_file_number) & 0x2B`
## （分组 0／1／3／5）才开 `FIELD_STATE_WARP1`。`map_file_number` 就是 MIF 的地图组，
## 工程里是地图 Scene 根节点的 `map_group`（`wiki\field\npc-service-menu.md` §5.1）。
const WARP_BOARD_GROUPS := [0, 1, 3, 5]
## 同一分支的 `& 0x14`（分组 2／4）回 `common/msg.fxt` 37「暂时不可传送」；
## 其余分组（含 25／26 与 > 5）原生直接返回、什么都不显示。
const WARP_BLOCKED_GROUPS := [2, 4]
## `Field_Warp1_mKeyPressed`：登船后待定目的地是飞艇内部地图 148 的 tile (7,12)。
const AIRSHIP_MAP_ID := 148
const AIRSHIP_TILE := Vector2i(7, 12)
## 一次性动作的动画结束模式：停末帧（原生 `ObjectAnimationEndModeType.HOLD_LAST_FRAME`）。
const ONE_SHOT_ANIMATION_END_MODE := Story.AnimationEndMode.HOLD_LAST_FRAME
## 主角朝向位（原生 `direction_code` 的低 4 位）→ 面前那一格。
const FACING_TILES := {
	FieldAction.Facing.LEFT: Vector2i.LEFT, FieldAction.Facing.RIGHT: Vector2i.RIGHT,
	FieldAction.Facing.UP: Vector2i.UP, FieldAction.Facing.DOWN: Vector2i.DOWN,
}

var story: StoryRuntime
var boundary := ""
## 野外提示。**静态文本提示已退役**：非空值一律转成一条提示栈消息（原生 `Game_infoInit`），
## 菜单打开时同时写进菜单页脚（原行为保留）。空串只用于清状态，不推消息。
var note := "":
	set(value):
		note = value
		if value.is_empty() or _note_stays_off_stack:
			return
		MessageStack.say(value)
## 「只走弹窗、不进提示栈」的一次性开关：OPTION 页的存档反馈全由 Box2 弹窗承担
## （`Menu_Option_mPaint` 的层 1／2／3，`Game_saveSAVE` 也不调 `Game_infoInit`）。
var _note_stays_off_stack := false
var menu_open := false
var book_open := false
## 原生 `FieldCanvas` 状态 2（`Field_Save_*`）；页面自己在 `$Save` 里跑开窗／写盘／确认三段。
var save_open := false
## 野外服务页：原生 `FieldLink.state_callbacks[]` 里的那些页。原生只有一份
## `FieldData.current_state_index_bits`（`FieldCanvas_SetNext` 换页时先调旧页的
## `destroy_callback_address`、再置索引、再调新页的 `init_callback_address`），所以同一时刻至多一页在用；
## 这里用同一个字段表示它，不再给每页留一个 `*_open` 布尔。
## 每页的视图、按键与开关登记在 `SERVICE_PAGES`（唯一登记处）。
enum ServicePage {
	NONE,
	GUILD,           ## 状态 6／9：`Field_Guild_List_*`／`Field_Guild_Info_Detail_*`
	SHOP,            ## 状态 12／13／14／15：`Field_Item_List_*`／`Field_Item_Buy_*`／`Field_Item_Sell_*`
	QUEST,           ## 状态 8／10／11：`Field_Quest_Detail_*`／`Field_Quest_Complete_*`
	INN,             ## 状态 16：`Field_Inn_*`
	WARP_CONFIRM,    ## 状态 4：`Field_Warp1_*`（野外触控键 48 进）
	WARP_WORLD,      ## 状态 5：`Field_Warp2_*`（NPC 交互码 4 进）
	MONSTER_MENU,    ## `GAME_STATE_MONSTER_LIST`(21)：`Game_Monster_List_*`
	MONSTER_MIX,     ## `GAME_STATE_MONSTER_MIX`(22)：`Game_Monster_Mix_*`
	MONSTER_ENCHANT, ## `GAME_STATE_MONSTER_ENCHANT`(23)：`Game_Monster_Enchant_*`
}
## 当前在用的服务页（`ServicePage.NONE` = 地图本身）。
var service_page := ServicePage.NONE
var focused := true
var dialogue: Dictionary = {}
var dialogue_index := 0
## 原生 Evt_scr 全屏字幕（opcode 4）与流派选择（opcode 32）各占一个模态层。
var narration: Dictionary = {}
var mastery: Dictionary = {}
var battle_view: Control
var menu_view: Control
var book_view: Control
var world_map_view: WorldMap
## 公会页（原生状态 6／9）：`Field_Guild_List_*`／`Field_Guild_Info_Detail_*`。
var guild_menu_view: Control
var guild_info_view: Control
## 公会挑战页（原生状态 7）。
var guild_challenge_view: Control
## 公会任务页（原生状态 8，实际是任务详情/接受确认，复用 `quest_detail`）。
var guild_quest_view: Control
## 打开公会的那个 NPC 的角色号（原生从 `ObjData+2424` 的当前交互对象取 `resource_id`）。
var guild_npc_id := -1
## 正在进行的是哪种公会战（`GuildBattle.KIND_CHALLENGE` = 3 / `KIND_EVENT` = 4），0 = 不是公会战。
var guild_battle_kind := 0
## 商店页（原生状态 12／13／14）：`Field_Item_List_*`／`Field_Item_Buy_*`／`Field_Item_Sell_*`。
var shop_view: Control
## 食物制作页（原生状态 15，从商店列表第三行进）。
var food_view: Control
var shop_mode_code := 0
## 任务详情页或任务完成页（两者互斥）。
var quest_view: Control
var _quests: QuestTable
## 旅店页（原生状态 16）：`Field_Inn_*`。
var inn_view: Control
## 飞艇登船确认页（原生状态 4 `FIELD_STATE_WARP1`）：野外触控键 48 进。
var warp_confirm_view: Control
## 飞艇世界地图页（原生状态 5 `FIELD_STATE_WARP2`）：NPC 交互码 4 进。
var warp_world_view: Control
## 精灵管理所（原生 `GAME_STATE_MONSTER_LIST`=21，`GameCanvas` 的落点）：NPC 交互码 2 进。
var monster_menu_view: Control
## 合成页（原生 `GAME_STATE_MONSTER_MIX`=22）：管理所游标 0 的 −5 进。
var monster_mix_view: Control
var monster_enchant_view: Control
## 待定传送（原生 `MapData.warp_target_map_id/tile_x/tile_y`）：WARP1／WARP2 只写目的地，
## 换图发生在英雄 ANI 10 播完之后（`Field_Hero_procNext` → `Map_warpProc`）。
var _pending_warp: Dictionary = {}
## 英雄 ANI 10 播完后只置位，等当前帧的对象池推进结束、下一帧 `advance` 再换图；
## 否则换图会在 `field_actors.advance` 的循环里重建 actor 节点，循环继续用已释放的节点崩溃。
var _warp_ready := false
var encounter_view: Control
var _store: RefCounted
var _resources: Object
var _assets: Node
var _world: Node2D
var _map_view: Node2D
var _actors: Node2D
var _chat_view: Control
var _map_name_view: Control
## 原生第二条消息条（`Game_msgInit(0, …)` 的 index 0）：`Map_warpProc:59-60` 的 404 走这里，
## 不进 `Game_infoInit` 的 8 槽提示栈。场景里由 `bar_index = 0` 的同一个 `MapNameView` 实例上移 20 px。
var _warp_blocked_bar: Control

## 下一条地图名称条的来源（`MapNameView.Source`）：原生 `Map_warpProc:54` 在 `GameCanvas_mapLOAD`
## 之后无条件 `Game_msgInit(1, MapData.reserved_0x10)`，同图传送也弹一次；剧情 opcode 14
## （`Evt_stdPROC` 的 case 0xE）载入当前这张图时没有换图，不重播（bm-P2-104）。
var _map_name_source: int = MapNameView.Source.STORY
## 已渲染的地图号：`"map"` 效果与它不同才算真的换了图。
var _shown_map_id := -1
## 跟随对象已被 `Op.CLEAR_ACTORS` 销毁（原生 `Evt_stdPROC:292-293` 的
## `Map_summonREMOVE/FREE`）：要等下一次 `Map_summonLOAD/CREATE`（opcode 0xB 或地图加载）
## 才重建；重建之前一个都不画。
var _summons_removed := false
## 上一帧是否把跟随对象放进了绘制队列（`Followers.visible`）。事件执行期间 `_advance_wild()`
## 整段跳过、不每帧 `_sync_actors()`，所以可见性翻转那一帧要靠这个标志补一次 sync。
var _followers_visible := true
## 事件里是否已经整屏黑过（bm-P2-103）：原生在事件期间照常绘制跟随对象（`Field_Basic_mPaint:11`
## 的 `Object_procDRAW` 只按 `active_state > 0` 收集，`Field_procCurr:144` 只跳过演算），换掉它们
## 的是黑屏之后的 `Op.LOAD_MAP`／`Op.CLEAR_ACTORS`。所以隐藏点取「第一次黑屏」——淡黑期间
## 跟随精灵随画面一起淡出，黑屏之后到事件结束都不再单独画；步号回到 0 时解锁。
var _event_covered := false
var _hero_summary: Control
var _minimap: Control
## 经验 +20% 窗口的 HUD（`Field_Basic_hero_DrawUI:64-77`）：图标是第 7 组第 18 号道具，
## 右侧数字是 `(+7 + 59999) / 60000` 的剩余分钟。
var _exp_bonus_hud: Control
var _exp_bonus_minutes: Control
var _exp_bonus_ms_remainder := 0.0
var _exp_bonus_shown_minutes := -1
var _touch_view: Node2D
var _fade: ColorRect
var _cover: ColorRect
var _map_tint: ColorRect
var _map_effect: Node2D
var _narration_view: Control
## 一级（状态 15，`Game_Character_Select`）与二级（状态 16，与图鉴同一张 `Game_Book_Monster`）。
var _mastery_view: Control
var _starter_view: Control
## 当前显示的是哪一级：原生 `current_state_index_bits` 的 15／16 两位。
var _mastery_stage := Story.MasteryStage.MASTERY
## 第 7 组 16「专家的印章」打开的流派页：不走剧情事件门，只写 `preferredMastery`。
var _mastery_item_active := false
var _save_view: Control
var _motions: Dictionary = {}
## 进行中的采集：`{kind, tile, facing, action, from_action, play, hit}`。两遍英雄动作，
## 每遍第 6 帧让物件反应一次，第二遍命中帧才发道具（见 `_tick_map_harvest`）。
var _harvest: Dictionary = {}
var _focus := Vector2.ZERO
var _camera_center := Vector2.ZERO
var _camera_initialized := false
## 进行中的事件镜头推进（原生 `MapData+26` 的模式 + `+32` 未置位）：`{"id", "mode"}`。
var _camera_pan: Dictionary = {}
## 原生 `MapData +6` 的镜头锁定对象（`Evt_stdPROC` case 9 的 `MOVE_ACTOR` 带跟随参数时
## 把该对象挂上去、`+31=1`）。锁着时相机跟这个对象；否则按 `Map_posFRONT` 跟主角并
## 按面向偏移（垂直 30 px、水平 50 px）。-1 表示没有对象锁。
var _camera_actor := -1
## 交互开始前抓的野外帧：任务详情与世界地图共用这张定格背景（原生 `Field_Basic_Capture`），
## 不能等对话窗关掉后再抓，否则会把 NPC 对话一起拍进背景。
var _service_snapshot: Image = null
## NPC 待机游走（原生 `Field_Npc_procNext` → `Field_procNext(npc, 40)`）：
## 无事件时每段待机结束有 50% 概率在**出生点** ±40 px 内随机走一段（`Object_objARRIVE`
## 的目标就是 `&y+3/+4` 的 home 坐标），走近主角 30 px 内则 `Object_objLOOK` 转向主角。
const NPC_WANDER_RADIUS := 40.0
## 原生 `Field_procCurr` 的 NPC 逐帧位移约 1 px / 50 ms（20 px/s）。
const NPC_WALK_SPEED := 20.0
var _npc_home: Dictionary = {}
var _npc_home_map := -1
var _npc_idle: Dictionary = {}
var _shake := Vector2.ZERO
var _battle_id := -1
var _touch_key := 0
## 没有触控落点时的哨兵值（屏幕坐标恒为正）。
const NO_TOUCH := Vector2i(-1000, -1000)
## 帧号分派见 `MapItemInteraction`（166 → 167、152 反应帧 153..155、0／5／10 只对第 0 组）。
## 组号门控（`MapData.map_file_number` 由 `Map_mifLOAD:47` 从 MIF 头读出，
## 对应地图 Scene 根节点的 `map_group`）。
const MAP_OBJECT_GROUP_0 := 0
var _last_touch := NO_TOUCH
var _walk_direction := Vector2i.ZERO
## 方向键堆栈：后按下的在栈顶，移动方向永远取栈顶；松开栈顶就回到底下那个按着的方向。
var _walk_stack: Array[Vector2i] = []
## 像素走位的亚像素累加与当前所在格（只用于同步剧情坐标与传送判定）。
var _walk_remainder_px := 0.0
var _walk_tile := Vector2i(-1, -1)
var _running := false
var _last_walk_direction := Vector2i.ZERO
var _last_walk_time := -1
var _played_time_remainder := 0.0
var _legacy_time_reported := false
## 消息提示栈（`main.tscn` 的 `MessageStack`，原生 `Game_infoDraw`）。
var messages: Control
var _followers: Dictionary = {}
var _encounter: Dictionary = {}
## 战斗 ANI 场景预读队列（identity）。`MonsterAnimation.warm()` 读入该场景并清掉
## `resource_local_to_scene`——不预读时首次开战的 `_load_action` 会按「物种 × 动作」各
## `instantiate()` 一次，每次实例化都深拷贝整份动画库（实测 6 只的首次开战 ≈0.8 s，
## 预读后 ≈20 ms）。启动预载（`startup_preload.gd`）已把整个 `scenes/monsters` 装进缓存，
## 之后取一个 identity 只是缓存查表（复测 0.01–0.05 ms）；冷缓存仍要 12–16 ms，所以只在
## 进场与遇敌转场时逐帧读一个。见 `wiki\battle\battle-performance.md`「复核（2026-11-23）」。
var _battle_warmup: Array[String] = []
## 原生 `Evt_chtMENU` 的交互码（NPC 记录第 18 字节，`NpcDefinition.interaction_code`）：
## 只有 `MONSTER_LIST`／`WARP`／`INN` 三条分支不问任务门、直接切页；`GUILD`／`SHOP_BUY`／
## `SHOP_SELL` 先问 `Qst_chtMENU(id, 交互码)`，default（`NONE` 与 7 以上的任意码）只问
## `Qst_chtMENU`、不开任何页面。
enum InteractionCode {
	NONE = 0,          ## default 分支：`Qst_chtMENU(id, 交互码)`，返回 0 就停在野外
	GUILD = 1,         ## → `FIELD_STATE_GUILD_LIST`(6)，问 `Qst_chtMENU(id, 1)`
	MONSTER_LIST = 2,  ## → `GAME_STATE_MONSTER_LIST`(21)
	SHOP_BUY = 3,      ## → `FIELD_STATE_ITEM_LIST`(12) + `shop_mode_code = 1`
	WARP = 4,          ## → `FIELD_STATE_WARP2`(5)
	INN = 5,           ## → `FIELD_STATE_INN`(16)
	SHOP_SELL = 6,     ## → `FIELD_STATE_ITEM_LIST`(12) + `shop_mode_code = 0`
}

## `ItemData.shop_mode_code` 的两个取值（`Evt_chtMENU`：交互码 3 写 1 装备店、6 写 0 道具店）。
const SHOP_MODE_ITEMS = 0
const SHOP_MODE_EQUIPMENT = 1
## `SERVICE_ROUTES` 里的 `shop_mode` 取它表示这个交互码开的不是商店页。
const SHOP_MODE_NONE = -1

## 原生 `Evt_chtMENU` 的跳转表（`CMP R1,#6` + 7 项表，含 default）：
## 交互码 → `{page, shop_mode}`；目标状态写在 `InteractionCode` 各成员注释里（2 号的目标在
## `GameCanvas`，不是 `FIELD_STATE_*`）。`shop_mode` 只在 `FIELD_STATE_ITEM_LIST` 上有意义
## （3 = 装备商店买，6 = 道具商店卖），其余是 `SHOP_MODE_NONE`。
const SERVICE_ROUTES := {
	InteractionCode.GUILD: {"page": ServicePage.GUILD, "shop_mode": SHOP_MODE_NONE},
	InteractionCode.MONSTER_LIST: {"page": ServicePage.MONSTER_MENU, "shop_mode": SHOP_MODE_NONE},
	InteractionCode.SHOP_BUY: {"page": ServicePage.SHOP, "shop_mode": SHOP_MODE_EQUIPMENT},
	InteractionCode.WARP: {"page": ServicePage.WARP_WORLD, "shop_mode": SHOP_MODE_NONE},
	InteractionCode.INN: {"page": ServicePage.INN, "shop_mode": SHOP_MODE_NONE},
	InteractionCode.SHOP_SELL: {"page": ServicePage.SHOP, "shop_mode": SHOP_MODE_ITEMS},
}
## `Evt_chtMENU` 里不问任务门的三条分支（case 2／4／5 直接 `FieldCanvas_SetNext`）；
## 其余交互码都先问 `Qst_chtMENU`（`_quest_gate`）。
const SERVICE_QUEST_GATE_EXEMPT := [
	InteractionCode.MONSTER_LIST, InteractionCode.WARP, InteractionCode.INN]
## 服务页按键映射：原生各页 `mKeyPressed` 收到的都是同一次 `JC_keyMODIFY` 的结果码
## （`-5` 确认／`-16` 返回／`-3`／`-4` 左右／`-1`／`-2` 上下，见 `Field_Inn_mKeyPressed`），
## 这里把物理键折成页面 `handle_key()` 认的动作名。
const SERVICE_KEYS := {
	KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
	KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown",
	KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace",
}
## `Game_Monster_List_mKeyPressed` 只收上下与确认／返回，没有左右分支。
const MONSTER_LIST_KEYS := {
	KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
	KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace",
}
## 野外服务页的唯一登记处，对应原生 `FieldLink.state_callbacks[]` 的同一条目：
## `FieldCanvas_SetNext` 按 `current_state_index_bits` 取 destroy／init 回调，
## `FieldCanvas_mKeyPressed` 取 `key_pressed_callback_address`。列：
## - `views`：该页当前持有的视图，按顺序取第一个存在的（子页在前——原生换页后只有新页在跑）；
## - `key_map`：按键映射（各页 `mKeyPressed` 收的键码集合）；
## - `close`：关闭者（原生 `destroy_callback_address`），由 `close_service_page()` 统一调用。
## 表里不登记「打开者」：能由交互码进入的页只在 `_dispatch_npc_service()` 里显式列出（原生
## `Evt_chtMENU` 的六条分支）。`ServicePage.QUEST` 没有交互码路由——原生 `field_state` 表里也没有
## 「任务列表」这一档，`FIELD_STATE_QUEST_DETAIL`(10) 与 `FIELD_STATE_QUEST_COMPLETE`(11) 只由
## `Qst_chtMENU` 切进（`_quest_gate` → `_open_quest_detail`／`_open_quest_complete`）。
## 原生出处：公会 `Field_Guild_List_mKeyPressed`、商店 `Field_Item_List_mKeyPressed`、
## 任务 `Qst_chtKeyPress`／`Battle_Win_mKeyPressed`、旅店 `Field_Inn_mKeyPressed`、
## 飞艇 `Field_Warp1_mKeyPressed`／`Field_Warp2_mKeyPressed`、
## 精灵三页 `Game_Monster_{List,Mix,Enchant}_mKeyPressed`。
## 新增一页 = 在 `ServicePage` 加一个成员 + 这里加一行。
const SERVICE_PAGES := {
	ServicePage.GUILD: {
		"views": ["guild_info_view", "guild_challenge_view", "guild_quest_view", "guild_menu_view"],
		"key_map": SERVICE_KEYS, "close": "_close_guild"},
	ServicePage.SHOP: {
		"views": ["food_view", "shop_view"],
		"key_map": SERVICE_KEYS, "close": "_close_shop"},
	ServicePage.QUEST: {
		"views": ["quest_view"],
		"key_map": SERVICE_KEYS, "close": "_close_quest"},
	ServicePage.INN: {
		"views": ["inn_view"],
		"key_map": SERVICE_KEYS, "close": "_close_inn"},
	ServicePage.WARP_CONFIRM: {
		"views": ["warp_confirm_view"],
		"key_map": SERVICE_KEYS, "close": "_close_warp_confirm"},
	ServicePage.WARP_WORLD: {
		"views": ["warp_world_view"],
		"key_map": SERVICE_KEYS, "close": "_free_warp_world"},
	ServicePage.MONSTER_MENU: {
		"views": ["monster_menu_view"],
		"key_map": MONSTER_LIST_KEYS, "close": "_close_monster_menu"},
	ServicePage.MONSTER_MIX: {
		"views": ["monster_mix_view"],
		"key_map": SERVICE_KEYS, "close": "_close_monster_mix"},
	ServicePage.MONSTER_ENCHANT: {
		"views": ["monster_enchant_view"],
		"key_map": SERVICE_KEYS, "close": "_close_monster_enchant"},
}


## 宿主（`main.gd`）在加入场景后挂上提示栈：全局顶层 HUD，位置与地图／菜单无关。
func set_messages(node: Control) -> void:
	messages = node


## `Game_infoInit(icon_frame, text)`：图标帧号 < 0 表示无图标。
func _push_message(icon_frame: int, text: String) -> void:
	MessageStack.notify(icon_frame, text)


## 原生 `Item_stdAddEx@0x85BE4:47-76` 的两种入手提示：普通道具进袋后推「获得<品级色>名字
## X 数量」，图标帧是道具记录第 133 字节（`kind_specific_85_bits`，即 `ItemDefinition.icon` 的
## `common/ui_item` 帧号）；组 23–26 的伪道具不入袋，按 `Item_datBasic` 的 detail_text 与数量推
## 「获得经验值／金币 N」，无图标。查不到记录时原生整条提示都不发（`Item_datBasic` 失败返回 0）。
func _present_item_obtained(item_id: int, count: int, icon_frame: int) -> void:
	if _assets == null:
		return
	var type := ItemKind.kind_of(item_id)
	if PSEUDO_OBTAINED_LABELS.has(type):
		MessageStack.push_pseudo_item(
			_assets.text_message(Msg.SOURCE, PSEUDO_OBTAINED_LABELS[type]), count)
		return
	if _resources == null or not _resources.has_method("load_gameplay"):
		return
	var catalog: Variant = _resources.call("load_gameplay")
	if not catalog is GameplayData:
		return
	var record: ItemDefinition = catalog.item(item_id)
	if record == null:
		return
	# 书类（`item_skill.dat`）与普通道具（`item_basic.dat`）的名称在不同文本源，按记录键选源。
	var item_name: String = _assets.text_message(
		ItemDefinition.name_source(record.name_record), record.name_record)
	MessageStack.push_item(item_name, count, icon_frame, int(record.grade_index))


## 任务接取／完成提示（原生 `Game_infoInit(0x94, "#C5"+标题+后缀)`）：事件指令 21
## （`Evt_stdPROC@0x7EC3C:462` → `Evt_msgSET@0x7CFC8:14-32`，文本源 `evt/evtlist.fxt`）、
## 任务页接受（`Qst_chtKeyPress@0x943A0:87` → `Qst_stdSET@0x93B34:37-43`）与任务完成
## （`Qst_stdComplete@0x93730:15-21`）是同一句文案，只有文本源与后缀记录不同。
func _present_quest_set(quest_id: int, source := TextTables.QUEST_SOURCE,
		suffix_record := Msg.Id.QUEST_ACCEPT_SUFFIX) -> void:
	if quest_id < 0 or _assets == null:
		return
	var quest_title := _quest_title(quest_id, source)
	MessageStack.push_quest(quest_title, suffix_record)


## `JC_fxtQUEST@0x20B64:10-33`：取文本资源第 3 页，把其中的「0/」换成「<当前>/」；
## 页里没有「0/」时原样返回。
func _quest_goal_text(quest_id: int, source: String, count: int) -> String:
	var payload: String = _assets.text_message(source, quest_id)
	var pages := payload.split("\t")
	var page: String = pages[2] if pages.size() > 2 else ""
	var marker := page.find("0/")
	if marker < 0:
		return page
	var prefix := page.substr(0, marker)
	if not prefix.is_empty() and not prefix.ends_with(" "):
		prefix += " "
	return "%s%d/%s" % [prefix, count, page.substr(marker + 2)]


## 原生 `Evt_stdCHECK@0x7E3C4:20-28`／`Qst_stdCHECK@0x94004:63-80` 的进度提示：
## 第一条是任务图标（帧 148）＋「#C5」＋标题，第二条无图标、「#C5[」＋目标页＋「]」。
func _present_quest_progress(quest_id: int, count: int, from_event: bool) -> void:
	if quest_id < 0 or _assets == null:
		return
	var source := EVENT_QUEST_TEXT_SOURCE if from_event else TextTables.QUEST_SOURCE
	MessageStack.push_quest_progress(_quest_title(quest_id, source),
		_quest_goal_text(quest_id, source, count))


func _ready() -> void:
	_world = get_node("World")
	_map_view = get_node("World/MapView")
	_map_effect = get_node("World/MapEffect")
	_map_effect.settled.connect(_on_map_effect_settled)
	_actors = get_node("World/Actors")
	_actors.connect("animation_finished", _on_actor_animation_finished)
	_chat_view = get_node("ChatView")
	_map_name_view = get_node("MapNameView")
	_warp_blocked_bar = get_node("WarpBlockedBar")
	_hero_summary = get_node("HeroSummary")
	_minimap = get_node("Minimap")
	_exp_bonus_hud = get_node("ExpBonus")
	_exp_bonus_minutes = get_node("ExpBonus/Minutes")
	_touch_view = get_node("TouchView")
	_fade = get_node("Fade")
	_cover = get_node("Cover")
	_map_tint = get_node("MapTint")
	_narration_view = get_node("Narration")
	_mastery_view = get_node("Mastery")
	_starter_view = get_node("Starter")
	_starter_view.back_requested.connect(_return_starter)
	_starter_view.starter_confirmed.connect(submit_mastery)
	_save_view = get_node("Save")
	_save_view.save_requested.connect(_save_page_requested)
	_save_view.closed.connect(_close_save)


func start_slot(store: RefCounted, slot: int, resources: Object, assets: Node) -> bool:
	_store = store
	_resources = resources
	_assets = assets
	if messages != null and messages.has_method("configure"):
		messages.call("configure", _assets)
	_chat_view.configure(assets)
	var loaded: Dictionary = store.load_slot(slot)
	if loaded.status == "error":
		boundary = "存档 %d 无法读取：%s；未覆盖损坏存档。" % [slot + 1, error_string(loaded.error)]
		_refresh()
		return false
	_actors.configure(assets)
	_map_effect.clear()
	story = Story.new(resources, loaded.progress)
	story.initialize(loaded.status == "ready")
	# 原生 `FieldCanvas_load`：载入存档／进野外画布时，HP 归 0 的精灵恢复成 1 HP。
	story.restore_downed_monsters()
	_prepare_exp_bonus_hud()
	_queue_party_battle_animations()
	_drain_effects()
	_refresh()
	return boundary.is_empty()


## 队伍成员的战斗 ANI 排进预读队列：脚本战斗与公会挑战没有遇敌转场可用，
## 只能靠进图时的前几帧预热（野生遇敌另在 `_begin_encounter` 排入本场实际出场的物种）。
func _queue_party_battle_animations() -> void:
	var catalog = _assets.load_gameplay_catalog()
	for index: int in MenuModel.native_party_order(story.progress):
		var details: Dictionary = MenuModel.native_member_details(story.progress, catalog, index)
		var ball: Variant = details.get("ball")
		if ball is Dictionary and not (ball as Dictionary).is_empty():
			_queue_battle_identity(MonsterAnimation.battle_identity(int(ball.species)))


## 本场战斗的全部出场物种（我方 3 只 + 敌方）→ 预读队列；空球与重复 identity 跳过。
func _queue_battle_animations(balls: Array) -> void:
	for ball: Variant in balls:
		if ball is Dictionary and not (ball as Dictionary).is_empty():
			_queue_battle_identity(MonsterAnimation.battle_identity(int(ball.species)))


func _queue_battle_identity(identity: String) -> void:
	if identity.is_empty() or _battle_warmup.has(identity):
		return
	_battle_warmup.append(identity)


func _advance_battle_warmup() -> void:
	if _battle_warmup.is_empty():
		return
	MonsterAnimation.warm(_battle_warmup.pop_front())


## 开战前把队列读空：脚本战／公会战没有遇敌转场，等不到逐帧推进。
func _flush_battle_warmup() -> void:
	while not _battle_warmup.is_empty():
		_advance_battle_warmup()


## 经验加成窗口（`ParamData.standard_progress + 7`）的 HUD 图标：原生画的就是第 7 组第 18 号
## 的道具图标（`Field_Basic_hero_DrawUI:66` 的 `Menu_Item_DrawItem(60, 9, {1, 0x120007})`）。
func _prepare_exp_bonus_hud() -> void:
	var icon: Texture2D = null
	if _assets != null and _resources != null and _resources.has_method("load_gameplay"):
		var catalog: Variant = _resources.call("load_gameplay")
		if catalog is GameplayData:
			var bonus: ItemDefinition = catalog.item(ItemKind.id_of(
				ItemKind.Kind.GROUP_7, ItemEffect.EXP_BONUS_INDEX))
			if bonus != null:
				icon = _assets.item_icon(bonus.icon)
	_exp_bonus_hud.get_node("Icon").texture = icon


## `GameCanvas_mPaint:29-40`：`+5` 记本帧累计毫秒、`+7` 按同样的耗时递减；本帧耗时已经
## 不小于剩余值时直接清零（原生 `+7 = 0`），所以不会出现负数。
func _advance_exp_bonus(delta: float) -> void:
	if story == null:
		return
	var parameter: Variant = story.progress.get("parameter")
	if not parameter is Dictionary:
		return
	var remaining := Story.exp_bonus_remaining(parameter)
	if remaining <= 0:
		_exp_bonus_ms_remainder = 0.0
		return
	_exp_bonus_ms_remainder += delta * 1000.0
	var elapsed := int(_exp_bonus_ms_remainder)
	if elapsed <= 0:
		return
	_exp_bonus_ms_remainder -= elapsed
	parameter[Story.EXP_BONUS_KEY] = 0 if elapsed >= remaining else remaining - elapsed


## HUD 只在 `+7 > 0` 且地图 HUD 本身可见时出现（`Field_Basic_hero_DrawUI:64` 的两层条件）。
func _sync_exp_bonus_hud(style: int) -> void:
	var remaining := 0
	if story != null:
		remaining = Story.exp_bonus_remaining(story.progress.get("parameter"))
	_exp_bonus_hud.visible = style != 0 and remaining > 0
	if not _exp_bonus_hud.visible:
		_exp_bonus_shown_minutes = -1
		return
	var minutes := (remaining + EXP_BONUS_MINUTE_ROUND_UP) / EXP_BONUS_MINUTE_MS
	if minutes != _exp_bonus_shown_minutes:
		_exp_bonus_shown_minutes = minutes
		_exp_bonus_minutes.call("present", str(minutes))


## 每帧推进：先决定角色动画是否运行，再按「菜单／遇敌转场／普通对话／正常地图」分派。
## 返回到处保持幂等——任何分支都只影响自己的部分。
func advance(delta: float) -> void:
	# 原生 `Object_procRUN:13`：事件执行中（`EvtData.step_index > 0`）且暂停位（`EvtData+12`，
	# 事件 opcode 22 的首个参数）恰为 1 时，整轮对象池推进被跳过——帧位移
	# （`Object_procCURR` → `Object_procMOVE`）、`decode_frame`／`current_frame` 回调与
	# `recent_positions` 滚动都在这一轮里，所以英雄的逐格位移与逐帧动画一起冻结。
	# 这是本文件唯一的暂停判据：动画开关与位移推进都从它取。
	var objects_paused: bool = story != null and story.objects_paused()
	# 原生每次绘制都重算 `v13`，所以已显示的消息在切档时立刻跟着走，不等下一条。
	# `GameCanvas_mPaint:29-40` 在每次绘制里推进经验加成窗口，与本帧其余推进无关。
	_advance_exp_bonus(delta)
	_actors.set_monster_running(story != null and focused and boundary.is_empty() and
		not menu_open and not book_open and not save_open and not service_open() and battle_view == null and
		_encounter.is_empty() and
		not dialogue.get("ordinary", false) and narration.is_empty() and mastery.is_empty() and
		not objects_paused)
	if story == null or not focused or not boundary.is_empty() or \
			not is_finite(delta) or delta < 0:
		return
	_map_name_view.advance(delta)
	_warp_blocked_bar.advance(delta)
	# 预读排在菜单／转场／对话这些等待帧里做，不额外占一帧。
	_advance_battle_warmup()
	if menu_open or book_open or save_open or service_open():
		return
	if not narration.is_empty():
		_narration_view.advance(delta)
		_advance_narration()
		_refresh()
		return
	if _mastery_item_active or not mastery.is_empty():
		_refresh()
		return
	if not _encounter.is_empty() and _encounter.stage != "battle":
		return
	if _minimap.visible:
		_minimap.advance(delta)
	if dialogue.get("ordinary", false):
		# 普通 NPC 对话只开聊天窗，不冻结地图：继续推进 NPC 待机／环境动画；
		# 只有任务接取等服务页才按窗口通用逻辑冻结。
		_actors.advance(delta, true)
		_advance_npc_idle(delta)
		_chat_view.advance(delta)
		_refresh()
		return
	# 原生存的是环绕的毫秒累计，这里按整数毫秒进位后回写，保持与原版一致的回绕行为。
	if story.progress.has("playedTimeMs"):
		_played_time_remainder += delta * 1000.0
		var elapsed := int(_played_time_remainder)
		_played_time_remainder -= elapsed
		story.progress.playedTimeMs = (int(story.progress.playedTimeMs) + elapsed) & 0xFFFFFFFF
	elif not _legacy_time_reported:
		push_warning("Legacy save has no recorded play time; its historical duration remains unknown.")
		_legacy_time_reported = true
	if battle_view == null:
		if _warp_ready and not _pending_warp.is_empty():
			_apply_pending_warp()
			return
		var manual_movement := false
		# 暂停期间对象池整段不推进：已在飞的脚本位移冻在原地（剩余时间不消费、也不补帧）。
		var remaining := 0.0 if objects_paused else _advance_motions(delta)
		_drain_effects()
		# 脚本位移跑完后的剩余时间交给像素走位（原生也是对象池推进完再吃输入）。
		if not objects_paused and _motions.is_empty() and _walk_direction != Vector2i.ZERO:
			manual_movement = _advance_manual_walk(remaining)
		_drain_effects()
		# 松开按键立刻停在当前像素位置（原版走位不是整格步进）。
		if _walk_direction == Vector2i.ZERO and int(_actor(0).action) in \
				[FieldAction.Hero.WALK, FieldAction.Hero.RUN]:
			_actor(0).action = FieldAction.Hero.IDLE
			_sync_actors()
		if not dialogue.get("ordinary", false):
			story.advance(delta)
		_drain_effects()
		# 步号回到 0（事件链结束）就解锁「黑屏后不画」；隐藏点由淡黑那一帧的
		# `_mark_event_screen_black()` 落地，这里只补可见性翻转时那一次 sync。
		if not Followers.event_step_running(story.progress):
			_event_covered = false
		_refresh_followers()
		_position_camera(delta)
		_advance_npc_idle(delta)
		_actors.advance(delta, not objects_paused, not manual_movement)
		_tick_map_harvest()
		_drain_effects()
		_chat_view.advance(delta)
		_advance_wild(delta)
	_refresh()


func _advance_wild(delta: float) -> void:
	if not _encounter.is_empty() or not dialogue.is_empty() or \
			story.stable_state().is_empty():
		return
	var hero := Vector2(_actor(0).x, _actor(0).y) * TILE
	var contacted := Wild.contact(story.progress.actors, hero)
	if contacted.is_empty():
		var remaining := delta
		while remaining > 0.0:
			var step := minf(remaining, 0.05)
			Wild.advance(story.progress.actors, story.map.terrain, hero, step, story._roll)
			remaining -= step
			contacted = Wild.contact(story.progress.actors, hero)
			if not contacted.is_empty():
				break
		_sync_actors()
	if not contacted.is_empty():
		_begin_encounter(contacted)


func _begin_encounter(contacted: Dictionary) -> void:
	if not _encounter.is_empty() or battle_view != null:
		return
	var ready_party := false
	for index: int in MenuModel.native_party_order(story.progress):
		var details := MenuModel.native_member_details(story.progress, _assets.load_gameplay_catalog(), index)
		if details.hp != null and int(details.hp) > 0:
			ready_party = true
			break
	if not ready_party:
		note = "没有可行动的出战怪物；不能开始野怪战斗。"
		return
	story.combat = Wild.battle_entry(story, contacted)
	# 遇敌转场（0.75 s）期间逐帧预读本场 6 只的 ANI：首次开战的同步加载不再落在 `start()` 里。
	_queue_battle_animations(story.combat.balls)
	_encounter = {"stage": "capture", "actor": int(contacted.id)}
	story.paused = true
	_clear_walk_input()
	# 撞怪可能发生在走位中途：丢掉那一步，否则战斗结束后它会接着滑完（角色已是待机动作）。
	_motions.erase(-1)
	_actor(0).action = FieldAction.Hero.IDLE
	_sync_actors()
	music_requested.emit(0)
	_refresh()
	call_deferred("_capture_encounter")


func _capture_encounter() -> void:
	if _encounter.get("stage") != "capture":
		return
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _encounter.get("stage") != "capture":
		return
	_complete_encounter_capture(get_viewport().get_texture().get_image())


func _complete_encounter_capture(image: Image) -> void:
	story.progress.actors = story.progress.actors.filter(
		func(actor: Dictionary) -> bool: return int(actor.id) != int(_encounter.actor))
	_sync_actors()
	_encounter.stage = "transition"
	_create_encounter_view()
	encounter_view.present(image, _world.position + _point(_actor(0)))


func _create_encounter_view() -> void:
	encounter_view = EncounterScene.instantiate()
	encounter_view.z_index = 320
	add_child(encounter_view)
	encounter_view.completed.connect(_encounter_finished)
	encounter_view.battle_ready.connect(_encounter_ready)
	encounter_view.effect_requested.connect(func(id: int): effect_requested.emit(id))


## 「战斗准备」动画播完：战斗界面先开在转场层下面，再由 `Battle_Ready_mPaint`
## 那 5 帧黑幕淡出把它露出来，避免直接闪到战斗界面。
func _encounter_ready() -> void:
	if _encounter.get("stage") != "transition" or battle_view != null:
		return
	_encounter.stage = "battle"
	if encounter_view != null:
		move_child(encounter_view, get_child_count() - 1)
		encounter_view.z_index = 320
	_create_battle_view(int(_encounter.get("battle_id", -2)))


func _encounter_finished() -> void:
	if _encounter.get("stage") != "battle" or encounter_view == null:
		return
	remove_child(encounter_view)
	encounter_view.queue_free()
	encounter_view = null
	# 剧情战的转场层收掉就只剩战斗界面：清 `_encounter` 并把暂停交回 `_field_paused()`，
	# 否则战斗结束后的 `story.complete_battle()` 会被暂停挡住、后续剧情不再推进。
	if _battle_id != -2:
		_encounter.clear()
		_restore_field_pause()
	_refresh()


## 消费 Story 产出的场景效果（Evt_* 指令的结果），逐个落到视图上。
## 遇到 boundary（未接通的原生分支）立即停止，不再继续套用后续效果。
func _drain_effects() -> void:
	for effect: Dictionary in story.take_effects():
		if not boundary.is_empty():
			break
		match effect.kind:
			"map":
				# 换图：清掉未完成的脚本移动，重画地块、小地图与动态物件。
				# 镜头中心跟着留用旧值：原生换图链路 `Map_warpProc:21-22` →
				# `GameCanvas_mapLOAD:10-14`（`Map_mifLOAD`／`Map_mdtLOAD`）从不写
				# `MapData.camera_origin`；清零只发生在 `Map_Init`，调用者只有
				# `GameCanvas_load:10`（开局）与 `Map_Initialize:7`（引擎初始化）。
				var switched: bool = _shown_map_id != int(effect.mapId)
				for id: int in _motions:
					story.cancel_move(id)
				_motions.clear()
				# 载荷要整个传进去：`BattleMap.setup()` 同时要 `info` 与 `terrain`，
				# 只给 `info` 会被当成“Map rules rejected the payload”。
				if not _map_view.render_map(effect.map):
					_stop(_map_view.last_error)
				else:
					_shown_map_id = int(effect.mapId)
					if switched:
						_map_name_source = MapNameView.Source.WARP
					_minimap.set_map(effect.map)
					_followers.clear()
					# 地图加载就是原生 `FieldCanvas_load:146-147` 的 `Map_summonLOAD/CREATE`，
					# 之前被 `Op.CLEAR_ACTORS` 销毁的跟随对象在这里重建。
					_summons_removed = false
					_harvest = {}
					_walk_tile = Vector2i(-1, -1)
					if _actors.set_map_objects(effect.map.info, story.event_map_objects(),
							_map_object_state(int(effect.map.get("id", -1)))):
						_sync_actors()
					else:
						_stop("地图物件绘制失败，请查看资源错误。")
			"map-name":
				_map_name_view.present(effect.text, _map_name_source)
				_map_name_source = MapNameView.Source.STORY
			"actors":
				_sync_actors()
			"summons-removed":
				# 原生 `Evt_stdPROC:292-293`（opcode 0xC）：`Map_summonREMOVE` + `Map_summonFREE`，
				# 跟随对象整个销毁，重建要等下一次 `Map_summonLOAD/CREATE`。
				_followers.clear()
				_summons_removed = true
				_sync_actors()
			"summons-rebuilt":
				# 原生 `Map_summonLOAD` + `Map_summonCREATE`（opcode 0xB 与地图加载）：按当前队伍
				# 重新建三个跟随对象并摆到主角坐标。
				_followers.clear()
				_summons_removed = false
				_sync_actors()
			"focus":
				_camera_actor = -1
				_focus = _point(effect.position)
				_position_camera()
			"camera-pan":
				# `Map_posFOCUS` 的模式 2／3／4：目标瓦片挂进 `+10`／`+14` 后逐帧推进，
				# 到位那一刻才置 `+32`（由 `_step_camera_pan` 回调 `story.complete_camera`）。
				_camera_actor = -1
				_focus = _point(effect.position)
				_camera_pan = {"id": int(effect.id), "mode": int(effect.mode)}
			"move":
				var actor: Dictionary = _actor(int(effect.actor.id))
				if actor.is_empty():
					story.fail_effect(effect.id, "移动角色不存在")
				else:
					# 原生一个对象只有一份 start/dest（新的 `Object_objARRIVE` 直接覆盖旧的），
					# 先把同一演员的上一段移动取消，避免两个目的地同时生效、互相对拉。
					for motion_id: int in _motions.keys():
						if int(_motions[motion_id].actor.get("id", -1)) == int(actor.id):
							story.cancel_move(motion_id)
							_motions.erase(motion_id)
					_motions[int(effect.id)] = {"actor": actor,
						"destination": effect.destination, "follow": effect.follow}
					# `p[2] > 0`：原版把移动对象本身锁成镜头目标（`+6`），相机跟着它走；
					# 这条锁会持续到下一次 `Evt_camSET`／事件链结束，不是只跟一段。
					if bool(effect.follow):
						_camera_actor = int(actor.id)
			"item-obtained":
				_present_item_obtained(int(effect.itemId), int(effect.count),
					int(effect.iconFrame))
			"quest-set":
				_present_quest_set(int(effect.questId), EVENT_QUEST_TEXT_SOURCE)
			"quest-progress":
				_present_quest_progress(int(effect.questId), int(effect.count),
					bool(effect.fromEvent))
			"dialogue":
				dialogue = effect
				dialogue_index = 0
			"narration":
				narration = effect
				if not _narration_view.present(effect.records, int(effect.placement)):
					narration = {}
					_stop("原叙事字幕无法显示：%s" % _narration_view.last_error)
			"mastery-select":
				mastery = effect
				_mastery_stage = int(effect.get("stage", Story.MasteryStage.MASTERY))
				if _mastery_stage == Story.MasteryStage.STARTER:
					# 原生状态 15 → 16 是 `GameCanvas_SetNext`：上一页不再画，二级页自己播开窗动画。
					_mastery_view.clear()
					var catalog := _gameplay_catalog()
					if catalog == null or not _present_starter(effect, catalog):
						mastery = {}
						_clear_mastery_pages()
						_stop("原初始精灵页无法显示：缺少原物种或游戏数值表。")
				elif not _mastery_view.present(_mastery_names(effect.species)):
					mastery = {}
					_clear_mastery_pages()
					_stop("原流派选择无法显示：%s" % _mastery_view.last_error)
			"map-filter":
				var shader_material := _map_tint.material as ShaderMaterial
				shader_material.set_shader_parameter("mode", int(effect.mode))
				_map_tint.visible = int(effect.mode) != 0
			"map-effect":
				_map_effect.present(effect)
			"objects-paused":
				# 暂停位本身不画东西：冻结／恢复由 `advance` 每帧的 `objects_paused` 重算
				# （原生 `Object_procRUN:13` 是逐帧判定，不是一次性效果）。
				pass
			"map-objects":
				if not _actors.set_map_objects(story.map.info, story.event_map_objects(),
						_map_object_state(int(story.map.get("id", -1)))):
					_stop("地图物件绘制失败，请查看资源错误。")
			"save":
				_save_from_event()
			"fade":
				var color := int(effect.color)
				_fade.color = Color(float((color >> 16) & 255) / 255.0,
					float((color >> 8) & 255) / 255.0, float(color & 255) / 255.0,
					clampf(float(effect.alpha), 0, 1))
				_fade.visible = effect.alpha > 0
				if color == BLACK_RGB and float(effect.alpha) >= OPAQUE_ALPHA:
					_mark_event_screen_black()
			"cover":
				var cover_color := int(effect.get("color", BLACK_RGB))
				_cover.color = Color(float((cover_color >> 16) & 255) / 255.0,
					float((cover_color >> 8) & 255) / 255.0,
					float(cover_color & 255) / 255.0, 1.0)
				_cover.visible = effect.enabled
				if effect.enabled:
					_mark_event_screen_black()
			"shake":
				_shake = Vector2(effect.x, effect.y)
				_position_camera()
			"battle":
				_open_battle(int(effect.id))
			"game-over":
				# 原事件战败北（`Battle_Die_mRun` 子状态 2／6 → `Game_out()`）：回标题即终局，
				# 后续效果不再套用。
				_back_to_title()
				return
			"blocked":
				_stop(str(effect.detail))
			"music":
				music_requested.emit(int(effect.track))
			"changed":
				pass
			_:
				_stop("原场景效果尚未接通：%s" % effect.kind)
	_map_name_source = MapNameView.Source.STORY
	if not story.boundary.is_empty():
		_stop(story.boundary)


func _stop(detail: String) -> void:
	boundary = detail
	if story != null:
		story.paused = true
	MessageStack.say(detail)


## 分级地图特效播完 5 帧爬坡：放行原事件（原生这一步不占帧，见 `wiki\field\map-effects.md` 第 5 节）。
func _on_map_effect_settled(effect_id: int) -> void:
	if story != null:
		story.complete_effect(effect_id)


func _actor(id: int) -> Dictionary:
	for actor: Dictionary in story.progress.actors:
		if int(actor.id) == id:
			return actor
	return {}


func _sync_actors() -> void:
	# Only explicit record-index bindings are accepted; resource IDs are not sprite IDs.
	Wild.bind(story.progress.actors, story.map.info.get("monster_spawns", []), _assets)
	_sync_quest_icons()
	var actors: Array = story.progress.actors.duplicate()
	# 跟随精灵的可见性只有两个依据：被 `Op.CLEAR_ACTORS` 清场（等下一次 `Map_summonLOAD/CREATE`
	# 才重建），以及事件里第一次整屏黑过（`Followers.visible` 的原生依据写在那一处）。
	_followers_visible = Followers.visible(_summons_removed, _event_covered)
	if _followers_visible:
		actors.append_array(Followers.sync(_followers, story.progress, _actor(0)))
	_actors.sync(actors, story.map.info.get("npc_bindings", []))


## 跟随精灵可见性翻转时补一次 `_sync_actors()`：事件执行期间 `_advance_wild()` 整段跳过、
## 不每帧 sync，靠这一处把隐藏／恢复落在触发它的同一帧。
func _refresh_followers() -> void:
	if Followers.visible(_summons_removed, _event_covered) != _followers_visible:
		_sync_actors()


## 事件里第一次整屏黑（`Op.FADE` 的黑色到不透明、`Op.WAIT` 的整屏填充）：锁存到事件结束，
## 期间不再单独绘制跟随精灵。原生就是在这之后重建／销毁跟随对象（`Map_warpProc:21-22` 的地图
## 重载与 `Evt_stdPROC:292-293` 的清场都在黑屏记录之后），画面已经全黑，不该再单独露出来。
func _mark_event_screen_black() -> void:
	if _event_covered or story == null or not Followers.event_step_running(story.progress):
		return
	_event_covered = true
	_refresh_followers()


## `Qst_icoSET`：原生给每个 `object_kind == 3`（NPC）对象写 `Qst_icoGET` 的结果，
## 由 `Field_Emoticon_procDraw` 画头顶图标、`Map_miniDRAW` 画小地图色块。
## 本工程的 kind 3 就是「有 NPC 绑定」的那些 actor（主角与怪物没有这个字段）。原生在
## `Field_Basic_init`／事件推进／计数达标／对话结束／任务页确认时刷新；这里随角色同步与 HUD 刷新
## 重算，覆盖同样的时机。
func _sync_quest_icons() -> void:
	if story == null:
		return
	var info: Dictionary = story.map.get("info", {})
	# `Qst_icoGET:15-17` 先把「事件步」的状态读一次（原生 `EvtData.step_index/step_kind/
	# item_condition_parameter` 是全局快照），整张图共用同一份，不必每个 NPC 各取一遍事件资源。
	var step: Dictionary = story.event_step()
	for binding: Dictionary in info.get("npc_bindings", []):
		var npc_id := int(binding.get("record_index", -1))
		var actor := _actor(npc_id)
		var code := _quest_icon_code(npc_id, step)
		if actor.is_empty() or code < 0:
			continue
		actor["quest_status"] = code
	_actors.refresh_emotions()


## `Qst_icoGET` 的返回码（0 无／2 可接／3 进行中／4 达成／5 事件任务）；任务表或任务日志取不到时
## 返回 −1 表示「未知」，这时不覆盖对象上已有的任务码、也不报错——缺表是移植侧的问题，报错归
## `_quest_table_resource()` 在真正需要任务门禁的路径上做。
func _quest_icon_code(npc_id: int, step: Dictionary) -> int:
	if story == null:
		return -1
	# `:15-16`：事件正在执行记录时**一律 0**，连任务表那套 2／3／4 都不画。
	if QuestMark.suppresses_marks(step):
		return QuestMark.Code.NONE
	# `:17`：停在首记录且这一步是「等与该交互号对象对话」时，只有被等的那一个对象拿 5。
	var event_code := QuestMark.event_step_code(step, npc_id)
	if event_code != QuestMark.Code.NONE:
		return event_code
	var log: QuestLog = story.quest_log()
	if log == null:
		return -1
	if _quests == null:
		_quests = QuestSetLoader.load_table()
		if _quests == null:
			return -1
	return log.status(_quests, npc_id, _quest_context())


static func _point(point: Dictionary) -> Vector2:
	return Vector2(float(point.x), float(point.y)) * TILE + Vector2(8, 8)


func _position_camera(delta: float = 0.0) -> void:
	var dimensions := Vector2(_map_view.map_size_tiles) * TILE
	# `Map_posFOCUS` 的 `+33 == 1` 是事件锁定的镜头：`+6` 有对象就锁对象（`MOVE_ACTOR` 带
	# 跟随参数时写进去），否则锁 `+10/+14` 的瓦片。`+33 == 0` 时跟主角，并按 `Map_posFRONT`
	# 把目标往面向方向偏（水平 50、垂直 30），所以剧情里主角一转身镜头也跟着变，
	# 面向侧的头顶表情不会被自己的取景框切掉。
	var idle: bool = not story.running and int(story.progress.cursor) == 0 and \
		story._pending.is_empty() and story._motions.is_empty()
	if idle:
		_camera_actor = -1
	var fixed_tile: bool = story.progress.camera != null
	var fixed_actor := false
	var target: Vector2
	if fixed_tile:
		target = _point(story.progress.camera)
	elif _camera_actor >= 0:
		var locked := _actor(_camera_actor)
		if locked.is_empty():
			_camera_actor = -1
		else:
			fixed_actor = true
			target = _point(locked)
	if not fixed_tile and not fixed_actor:
		var hero := _actor(0)
		target = _focus if hero.is_empty() else _point(hero)
		if not hero.is_empty():
			var direction := int(hero.get("lastDirection", int(hero.direction) & FieldAction.VERTICAL_MASK))
			match direction:
				FieldAction.Facing.LEFT: target.x -= 50
				FieldAction.Facing.RIGHT: target.x += 50
				FieldAction.Facing.UP: target.y -= 30
				FieldAction.Facing.DOWN: target.y += 30
	target = Vector2(
		dimensions.x / 2 if dimensions.x < 400 else clampf(target.x, 200, dimensions.x - 200),
		dimensions.y / 2 if dimensions.y < 240 else clampf(target.y, 120, dimensions.y - 120))
	if not _camera_initialized:
		_camera_center = target
		_camera_initialized = true
	elif not _camera_pan.is_empty():
		_camera_center = _step_camera_pan(target, delta)
	elif fixed_tile or fixed_actor:
		# `+33 == 1` 的模式 1／4：原生每次都按 `Map_posCENTER(x, y, 1)` 立即定位。
		_camera_center = target
	elif delta > 0:
		# Map_posFRONT retains three quarters per native frame; keep the Godot motion continuous.
		_camera_center = _camera_center.lerp(target,
			1.0 - pow(0.75, delta / CAMERA_FRAME_SECONDS))
	_world.position = Vector2(200, 120) - _camera_center + _shake
	# 特效层在 World 里夹在 MapView 与 Actors 之间，要自己抵消镜头偏移才始终盖满视口
	# （原生 `Map_eftDRAW` 填的就是整个屏幕矩形）。
	_map_effect.position = -_world.position
	_actors.set_visible_world_rect(Rect2(Vector2.ZERO, Vector2(400, 240)))


## `Map_posFOCUS` 在 `+33 == 1` 且 `+26` 为 2／3／4 时的那一步推进。
## `delta <= 0`（特效即时重排）时原样返回当前中心，不动镜头。
static func camera_step(center: Vector2, target: Vector2, mode: int, delta: float) -> Vector2:
	if delta <= 0.0:
		return center
	var native_frames := delta / CAMERA_FRAME_SECONDS
	match mode:
		Story.CameraMode.PAN_FAST:
			return center.move_toward(target, CAMERA_PAN_FAST_STEP * native_frames)
		Story.CameraMode.PAN_SLOW:
			return center.move_toward(target, CAMERA_PAN_SLOW_STEP * native_frames)
		Story.CameraMode.HALF_CONVERGE:
			return center.lerp(target, 1.0 - pow(0.75, native_frames))
	return center


## 推进中镜头：模式 2／3 精确吸附到目标（`Map_posMOVE` 返回 0），模式 4 距离 ≤ 1px 即视为
## `Map_posCENTER` 返回 2。到位后把 `+32` 交给 `story.complete_camera` 放行事件。
func _step_camera_pan(target: Vector2, delta: float) -> Vector2:
	var mode := int(_camera_pan["mode"])
	var center := camera_step(_camera_center, target, mode, delta)
	var settle := CAMERA_SETTLE_PIXELS if mode == Story.CameraMode.HALF_CONVERGE else 0.0
	if center.distance_to(target) > settle:
		return center
	var id := int(_camera_pan["id"])
	_camera_pan = {}
	story.complete_camera(id)
	return center


func _advance_motions(delta: float) -> float:
	var remaining := delta if _motions.is_empty() else 0.0
	for id: int in _motions.keys():
		var motion: Dictionary = _motions[id]
		var actor: Dictionary = motion.actor
		# 原生 `Field_procCurr` case 1 只在对象 `animation_id == 6`（脚本走）时推进移动；
		# 摆位／剧情动作／删除对象都会让这一段移动作废。否则旧目的地会继续拉扯演员，
		# 与后来的移动互相对拉，`_motions` 永远清不掉（角色卡死、没有触控界面）。
		var live := _actor(int(actor.get("id", -1)))
		if live.is_empty() or int(actor.get("action", 0)) != FieldAction.Hero.SCRIPT_WALK:
			_motions.erase(id)
			story.cancel_move(id)
			continue
		var current := Vector2(actor.x, actor.y)
		var destination := Vector2(motion.destination.x, motion.destination.y)
		var next := current.move_toward(destination, SCRIPT_MOVE_SPEED * delta)
		actor.x = next.x
		actor.y = next.y
		if int(actor.id) == 0:
			# `Field_procCurr:143`：事件执行记录期间（原生 `EvtData.step_index > 0`）跟随对象
			# 直接返回、位置与轨迹都不推进；`Evt_stdPROC` case 9 的脚本走位也在事件内，所以
			# 判据只有 `event_step_running` 一处，不按这次移动是谁发起的分叉。
			Followers.advance(_followers, current, next, int(actor.action) == FieldAction.Hero.RUN,
				not Followers.event_step_running(story.progress))
			_sync_actors()
		else:
			_actors.update_position(actor)
		if motion.follow:
			_focus = _point(actor)
			_position_camera()
		if next != destination:
			continue
		_motions.erase(id)
		story.complete_effect(id)
		_sync_actors()
	return remaining


func confirm_dialogue() -> bool:
	if story == null or dialogue.is_empty() or menu_open or book_open or save_open or service_open() or \
			world_map_view != null or not focused or not boundary.is_empty():
		return false
	if not _chat_view.is_text_page_complete():
		_chat_view.reveal_text_page()
		return true
	if _chat_view.advance_text_page():
		return true
	dialogue_index += 1
	if dialogue_index >= dialogue.records.size():
		var ordinary: bool = dialogue.get("ordinary", false)
		var id := int(dialogue.get("id", -1))
		var npc_id := int(dialogue.get("npc_id", -1))
		dialogue = {}
		dialogue_index = 0
		var completed := true
		if ordinary:
			_dispatch_npc_service(npc_id)
		else:
			completed = story.complete_effect(id)
			_drain_effects()
		_refresh()
		return completed
	_refresh()
	return true


func handle_touch(position: Vector2, phase: String) -> bool:
	if phase == "up":
		var handled := _last_touch != NO_TOUCH
		_last_touch = NO_TOUCH
		if TouchView.DIRECTIONS.has(_touch_key):
			_release_walk_direction(TouchView.DIRECTIONS[_touch_key])
		_touch_key = 0
		_chat_view.set_touch_key(0)
		_touch_view.present(_field_touch_style(true), 0)
		if menu_view != null:
			menu_view.set_touch_key(0)
		return handled
	if phase not in ["down", "move"] or not focused or menu_open or book_open or save_open or \
			battle_view != null or world_map_view != null or not boundary.is_empty():
		return false
	var point := Vector2i(position)
	if service_open():
		return _service_touch(position, phase)
	if not narration.is_empty():
		# 原生 `Evt_stdKEY:51-55`：字幕步骤只接受键码 35（确定），其余触控一律吞掉；
		# 确定键＝直接结束整条指令（`+10` 置 1 → `Evt_stdPROC:168-171` 调 `Evt_scrFINAL`）。
		# 字幕期间野外触控面板整个收起（`_field_touch_style()` 返回 0），没有可判的触控键，
		# 所以按「点一下＝确定」处理。
		_narration_view.finish()
		_advance_narration()
		_refresh()
		return true
	if save_open:
		# 存档页只注册一个确认区（原生 DrawOk 的 `EFC_mainTouchSET(-5, …)`），其余触点吞掉。
		if phase == "down" and _save_view.accepts(Vector2(position)):
			_save_view.press("Enter")
		return true
	if _mastery_item_active or not mastery.is_empty():
		if _starter_active():
			# 二级页的格、滚动条与确认框都是真实 Button（`Menu_mon_DrawBookList`／
			# `Menu_win_Box2_DrawSelect`），`down` 已被它们吃掉；这里只吞掉落在空处的触点
			# （原生状态 16 没有登记触控区）。
			return true
		# 原生每格登记的触控键（`Menu_CharacterSelect_Draw:156/168/203`）：非光标格是
		# −3／−4（移动），光标格是 −5（打开确认框），所以点已选那格不会直接提交。
		var row: int = _mastery_view.row_at(Vector2(point))
		if row >= 0:
			_mastery_view.press_row(row)
		_refresh()
		return true
	if phase == "move" and absi(point.x - _last_touch.x) <= 7 and \
			absi(point.y - _last_touch.y) <= 7:
		return true
	_last_touch = point
	var keys: Array[int] = []
	if not dialogue.is_empty():
		var local_point := _chat_view.get_transform().affine_inverse() * Vector2(point)
		var key: int = _chat_view.touch_key(local_point)
		if key != 0:
			keys.append(key)
	else:
		_touch_view.present(_field_touch_style(), _touch_key)
		keys = _touch_view.touch_keys(_touch_view.get_transform().affine_inverse() * Vector2(point))
	# KEY2 processes all matching regions in reverse registration order.
	for key: int in keys:
		if key == _touch_key:
			continue
		var previous_key := _touch_key
		_touch_key = key
		if TouchView.DIRECTIONS.has(previous_key):
			_release_walk_direction(TouchView.DIRECTIONS[previous_key])
		if not TouchView.DIRECTIONS.has(key):
			_running = false
		if not dialogue.is_empty():
			_chat_view.set_touch_key(key)
			if key == TouchCode.Key.OK:
				confirm_dialogue()
			elif key == ChatView.TouchKey.EXIT:
				cancel_dialogue()
		else:
			_press_field_key(key)
	_refresh()
	return not keys.is_empty() or _field_touch_style() != 0


func _field_touch_style(allow_service: bool = false) -> int:
	if story == null or menu_open or book_open or save_open or battle_view != null or \
			(service_open() and not allow_service) or \
			world_map_view != null or not _pending_warp.is_empty() or \
			not _encounter.is_empty() or not boundary.is_empty() or \
			not dialogue.is_empty() or not narration.is_empty() or not mastery.is_empty() or \
			story.stable_state().is_empty() or not _motions.is_empty():
		return 0
	# 服务页（商店/任务等）的窗口操作是原版窗口态：十字 + OK + CLR，没有野外那套 MENU/SAVE
	# 页按钮。OK 确认、CLR 关闭，和 `Menu_win_Box_DrawKeyInfo` 的窗口态一致。
	if allow_service and service_open():
		return TouchView.Style.PAD_KEYS
	return TouchView.field_style(int(story.map.info.map_group))


## 服务页的触控：原版野外触控面板（十字／OK／CLR）在窗口打开时仍在，按键分派给当前页的
## `handle_key`——OK→Enter、CLR→Escape、十字→Arrow*。页内的真实 Button（格子、页签、
## 地图／接受键等）仍先吃自己的点击，只有落在面板上的触点走这里。
func _service_touch(position: Vector2, phase: String) -> bool:
	if phase != "down":
		return true
	_last_touch = Vector2i(position)
	var keys: Array[int] = _touch_view.touch_keys(
		_touch_view.get_transform().affine_inverse() * position)
	for key: int in keys:
		var action := _service_touch_action(key)
		if action.is_empty():
			continue
		_touch_key = key
		_touch_view.present(_field_touch_style(true), key)
		var page: Control = _service_page_view(service_page)
		if page != null:
			page.call("handle_key", action)
		_refresh()
		return true
	return false


func _service_touch_action(key: int) -> String:
	if key == TouchCode.Key.OK:
		return "Enter"
	if key == TouchCode.Key.BACK:
		return "Escape"
	if not TouchView.DIRECTIONS.has(key):
		return ""
	var direction: Vector2i = TouchView.DIRECTIONS[key]
	if direction.x < 0:
		return "ArrowLeft"
	if direction.x > 0:
		return "ArrowRight"
	if direction.y < 0:
		return "ArrowUp"
	return "ArrowDown"


## 野外服务页（原生 `FIELD_STATE` 4..16 的那批页面：飞艇两页／公会／商店／任务／旅店，以及
## `GAME_STATE_MONSTER_*` 三页）任一在用时为 true。页面本身、视图与按键都登记在 `SERVICE_PAGES`，
## 新增一页只加一行，不再往二十多处守卫链里逐条加布尔。
func service_open() -> bool:
	return service_page != ServicePage.NONE


## 服务页当前持有的视图：按 `SERVICE_PAGES` 登记的 `views` 顺序取第一个存在的。
## 顺序即优先级——原生换页后只有新页的 `run_callback_address` 在跑，所以子页排在父页前面。
func _service_page_view(page: ServicePage) -> Control:
	for member: String in SERVICE_PAGES[page].views:
		var view: Control = get(member)
		if view != null:
			return view
	return null


## 关掉当前服务页：走 `SERVICE_PAGES` 里登记的关页方法（原生 `SetNext` 里的
## `destroy_callback_address`）。没有服务页在用时什么也不做。
func close_service_page() -> void:
	if service_page == ServicePage.NONE:
		return
	call(str(SERVICE_PAGES[service_page].close))


## 「整份野外推进是否停住」的唯一判据：服务页／菜单／存档页／边界文本／遇敌转场任一在用就停住
## （`FieldCanvas_mRun` 只跑当前页的 `run_callback_address`，弹出框
## `Field_Box_mRun` 返回 1 时连那一页也不跑）。
func _field_paused() -> bool:
	return not focused or menu_open or book_open or save_open or service_open() or \
		not boundary.is_empty() or not _encounter.is_empty()


## 服务页关窗后把野外推进交回地图（原生关窗计数到 −4 → `SetNext(FIELD_STATE_BASIC)`）。
func _restore_field_pause() -> void:
	if story != null:
		story.paused = _field_paused()


func _press_field_key(key: int) -> void:
	if TouchView.DIRECTIONS.has(key):
		_begin_walk(TouchView.DIRECTIONS[key])
		return
	match key:
		TouchCode.Key.OK:
			# 原生 `Field_Basic_mKeyPressed`：先看对话目标，再 `Object_objHIT` 找面前的可交互物件。
			if not interact_npc():
				interact_map_object()
		TouchCode.Key.BACK:
			_open_menu()
		TouchCode.Key.HELP:
			_open_save()
		FieldKey.MAP:
			_open_world_map()
		FieldKey.BOOK:
			_open_book()
		FieldKey.NETWORK:
			_open_warp_confirm()


func _begin_walk(direction: Vector2i) -> void:
	_start_manual_walk(direction)


## 开始／继续按住一个方向：压栈后以栈顶为准（多键同时按不会互相抢方向）。
func _start_manual_walk(direction: Vector2i) -> void:
	if _field_touch_style() == 0 or not _pending_warp.is_empty() or \
			absi(direction.x) + absi(direction.y) != 1:
		return
	var now := Time.get_ticks_msec()
	_running = _running or (_last_walk_direction == direction and
		_last_walk_time >= 0 and now - _last_walk_time <= DASH_WINDOW_MS)
	_last_walk_direction = direction
	_last_walk_time = now
	_push_walk_direction(direction)


func _push_walk_direction(direction: Vector2i) -> void:
	# 同一个方向再按一次（触控重复报同一键）只把它提到栈顶，不重复入栈。
	_walk_stack.erase(direction)
	_walk_stack.push_back(direction)
	_walk_remainder_px = 0.0
	_apply_walk_top()


## 松开一个方向：从栈里移除；栈空就停，栈非空则回到底下那个按着的方向。
func _release_walk_direction(direction: Vector2i) -> void:
	if not _walk_stack.has(direction):
		return
	_walk_stack.erase(direction)
	_walk_remainder_px = 0.0
	_apply_walk_top()


## 把栈顶同步成当前的移动方向、朝向与走跑动作；栈空时回待机。
func _apply_walk_top() -> void:
	var hero := _actor(0)
	if hero.is_empty():
		return
	if _walk_stack.is_empty():
		_walk_direction = Vector2i.ZERO
		_running = false
		if int(hero.action) in [FieldAction.Hero.WALK, FieldAction.Hero.RUN]:
			hero.action = FieldAction.Hero.IDLE
			_sync_actors()
		return
	_walk_direction = _walk_stack.back()
	_face(_walk_direction)
	hero.action = FieldAction.Hero.RUN if _running else FieldAction.Hero.WALK
	hero.erase("animationEndMode")
	_sync_actors()


## 原生 `Object_objNEAR(3, -1, -1, x, y, direction_code, 900)`：只找 kind 3（NPC），按
## `direction_code` 的半平面筛选（上：候选 y ≤ 主角 y；下：≥；左：x ≤；右：≥），
## 距离平方 < 900（30 px）取最近。`Field_Basic_mRun:24` 每帧调它。
func _facing_npc(hero: Dictionary, facing: int) -> Dictionary:
	var picked: Dictionary = {}
	var best := 900.0
	for actor: Dictionary in story.progress.actors:
		if int(actor.id) == 0 or int(actor.id) >= 1000:
			continue
		var dx := (float(actor.x) - float(hero.x)) * TILE
		var dy := (float(actor.y) - float(hero.y)) * TILE
		if (facing == FieldAction.Facing.UP and dy > 0.0) or \
				(facing == FieldAction.Facing.DOWN and dy < 0.0) or \
				(facing == FieldAction.Facing.LEFT and dx > 0.0) or \
				(facing == FieldAction.Facing.RIGHT and dx < 0.0):
			continue
		var distance := dx * dx + dy * dy
		if distance >= best:
			continue
		picked = actor
		best = distance
	return picked


## 原生 `Object_objLOOK(hero, npc)` → `Object_objLookAt`：先调非主轴、再调主轴，
## 所以 `direction_code` 是主轴、`direction_flags` 保留另一轴。
func _look_at(hero: Dictionary, target: Dictionary) -> void:
	_face_pixel(hero, _point(target))
	_sync_actors()


## 朝向一个**像素**点：`Object_objLookAt`／`Object_objARRIVE` 的同一套主轴规则。
func _face_pixel(actor: Dictionary, pixel: Vector2) -> void:
	var center := Vector2(float(actor.x), float(actor.y)) * TILE + Vector2(8, 8)
	var dx := pixel.x - center.x
	var dy := pixel.y - center.y
	var facings: Array[int] = []
	if absf(dx) < absf(dy):
		if dx != 0.0:
			facings.append(FieldAction.Facing.LEFT if dx < 0.0 else FieldAction.Facing.RIGHT)
		if dy != 0.0:
			facings.append(FieldAction.Facing.UP if dy < 0.0 else FieldAction.Facing.DOWN)
	else:
		if dy != 0.0:
			facings.append(FieldAction.Facing.UP if dy < 0.0 else FieldAction.Facing.DOWN)
		if dx != 0.0:
			facings.append(FieldAction.Facing.LEFT if dx < 0.0 else FieldAction.Facing.RIGHT)
	var flags := int(actor.get("direction", 0))
	var code := int(actor.get("lastDirection", FieldAction.Facing.DOWN))
	for facing: int in facings:
		var pair: Array[int] = Story._object_direct(flags, facing)
		flags = pair[0]
		code = pair[1]
	actor["direction"] = flags
	actor["lastDirection"] = code


## NPC 的出生点（原生 `&y+3/+4` 的 home）：地图 NPC 取 MIF 记录，事件 NPC 取 `extraNpcs`。
## 换图时清空；之后第一次见到的坐标就是它的 home。
func _sync_npc_home() -> void:
	var map_id := int(story.map.get("id", -1))
	if map_id == _npc_home_map:
		return
	_npc_home_map = map_id
	_npc_home.clear()
	_npc_idle.clear()
	if not story.map.get("info") is Dictionary:
		return
	for npc: Dictionary in story.map.info.get("npcs", []):
		_npc_home[int(npc.resource_id)] = Vector2(float(npc.tile_x), float(npc.tile_y))
	for row: Array in story.progress.extraNpcs:
		if row[0] == map_id:
			_npc_home[int(row[3])] = Vector2(float(row[1]), float(row[2]))


## NPC 记录第 20 字节（`NpcDefinition.idle_movement_gate`，`Field_Npc_procNext` 的
## `out_bytes[36]`）：0 表示不随机游走，只会在主角靠近时转身。
func _npc_movement_gate(npc_id: int) -> int:
	var binding: Dictionary = _npc_binding(npc_id)
	return int(binding.get("idle_movement_gate", 0))


## `Field_Npc_procNext`：无事件时，主角在 30 px 内就先 `Object_objLOOK` 转向主角；否则
## 50% 概率 `Field_procNext(npc, 40)` → 在 home ±40 px 内随机 `Object_objARRIVE(..., 5)`
## 走一段。每段结束回待机，等下一次判定。
func _advance_npc_idle(delta: float) -> void:
	if story == null or not focused or story.running or story.objects_paused() or \
			int(story.progress.cursor) != 0 or not story._pending.is_empty() or \
			not story._motions.is_empty() or not _motions.is_empty() or \
			(not dialogue.is_empty() and not dialogue.get("ordinary", false)) or \
			menu_open or book_open or save_open or service_open() or \
			world_map_view != null or battle_view != null or not boundary.is_empty() or \
			not _encounter.is_empty() or not narration.is_empty() or not mastery.is_empty():
		return
	_sync_npc_home()
	var talking := int(dialogue.get("npc_id", -1)) if dialogue.get("ordinary", false) else -1
	var hero := _actor(0)
	var dimensions := Vector2(_map_view.map_size_tiles) * TILE
	for actor: Dictionary in story.progress.actors:
		var id := int(actor.id)
		if id == 0 or id >= 1000 or id == talking or bool(actor.get("party_follower", false)):
			continue
		if not _npc_home.has(id):
			_npc_home[id] = Vector2(float(actor.x), float(actor.y))
		var state: Dictionary = _npc_idle.get(id, {"wait": 0.3 + randf() * 0.9, "target": null})
		if state.get("target") is Vector2:
			var target: Vector2 = state.target
			var pixel := Vector2(float(actor.x), float(actor.y)) * TILE + Vector2(8, 8)
			var next := pixel.move_toward(target, NPC_WALK_SPEED * delta)
			if not _npc_pixel_free(next, id):
				# 地形／其它实体挡住就到不了：原地待机，不穿墙。
				state["target"] = null
				state["wait"] = 0.5 + randf() * 0.5
				actor.action = FieldAction.Hero.IDLE
				_sync_actors()
				_npc_idle[id] = state
				continue
			actor.x = (next.x - 8.0) / TILE
			actor.y = (next.y - 8.0) / TILE
			_actors.update_position(actor)
			if next.distance_to(target) < 0.5:
				state["target"] = null
				state["wait"] = 0.5 + randf() * 0.5
				actor.action = FieldAction.Hero.IDLE
				_sync_actors()
			_npc_idle[id] = state
			continue
		if int(actor.action) not in [FieldAction.Hero.IDLE, FieldAction.Hero.WALK,
				FieldAction.Hero.RUN, 5, FieldAction.Hero.SCRIPT_WALK]:
			continue
		if int(actor.action) != FieldAction.Hero.IDLE:
			# 上一段剧情走位结束后可能停在 5／6；待机逻辑接手时先回 0。
			actor.action = FieldAction.Hero.IDLE
			_sync_actors()
		state["wait"] = float(state["wait"]) - delta
		if float(state["wait"]) > 0.0:
			_npc_idle[id] = state
			continue
		if not hero.is_empty():
			var dx := (float(actor.x) - float(hero.x)) * TILE
			var dy := (float(actor.y) - float(hero.y)) * TILE
			if dx * dx + dy * dy <= 899.0:
				_look_at(actor, hero)
				state["wait"] = 0.4 + randf() * 0.4
				_npc_idle[id] = state
				continue
		if _npc_movement_gate(id) != 0 and randf() > 0.5:
			var home: Vector2 = _npc_home.get(id, Vector2(float(actor.x), float(actor.y)))
			var chosen := Vector2.ZERO
			var found := false
			for attempt in range(8):
				var px := clampf(home.x * TILE + 8.0 +
					randf_range(-NPC_WANDER_RADIUS, NPC_WANDER_RADIUS), 8.0, maxf(8.0, dimensions.x - 8.0))
				var py := clampf(home.y * TILE + 8.0 +
					randf_range(-NPC_WANDER_RADIUS, NPC_WANDER_RADIUS), 8.0, maxf(8.0, dimensions.y - 8.0))
				if _npc_pixel_free(Vector2(px, py), id):
					chosen = Vector2(px, py)
					found = true
					break
			if found:
				_face_pixel(actor, chosen)
				actor.action = 5
				state["target"] = chosen
				_sync_actors()
			else:
				state["wait"] = 0.5 + randf() * 0.5
		else:
			state["wait"] = 0.5 + randf() * 0.5
		_npc_idle[id] = state


## NPC 的 16×16 脚点碰撞：地形格不可走、或与其它实体（含主角，排除自己）重叠都算挡住。
## 原生 NPC 走到墙前就停，不会穿地形；随机目标也要先过这一步才采用。
func _npc_pixel_free(pixel: Vector2, npc_id: int) -> bool:
	if story == null or not story.map.get("terrain") is Dictionary:
		return false
	var terrain: Dictionary = story.map.terrain
	var min_px := pixel - Vector2(TILE, TILE) * 0.5
	var x0 := floori(min_px.x / TILE)
	var y0 := floori(min_px.y / TILE)
	var x1 := floori((min_px.x + TILE - 0.001) / TILE)
	var y1 := floori((min_px.y + TILE - 0.001) / TILE)
	if x0 < 0 or y0 < 0 or x1 >= int(terrain.width_tiles) or y1 >= int(terrain.height_tiles):
		return false
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if story.tile_blocked(tx, ty):
				return false
	var rect := Rect2(min_px, Vector2(TILE, TILE))
	for actor: Dictionary in story.progress.actors:
		if int(actor.id) == npc_id:
			continue
		if rect.intersects(Rect2(Vector2(float(actor.x), float(actor.y)) * TILE, Vector2(TILE, TILE))):
			return false
	return true


## 原生 Object_objDIRECT：新方向写入 direction_code，复合 direction_flags 保留
## 上一次的垂直／水平位（横向保留 0x30 并以 32 兜底，纵向保留 0x03 并以 1 兜底）。
func _face(direction: Vector2i) -> void:
	var hero := _actor(0)
	if hero.is_empty():
		return
	hero.lastDirection = FieldAction.Facing.LEFT if direction.x < 0 else FieldAction.Facing.RIGHT if direction.x > 0 else FieldAction.Facing.UP if direction.y < 0 else FieldAction.Facing.DOWN
	var retained := int(hero.direction) & (FieldAction.VERTICAL_MASK if direction.x != 0 else 3)
	hero.direction = (retained if retained != 0 else FieldAction.Facing.DOWN if direction.x != 0 else FieldAction.Facing.LEFT) | int(hero.lastDirection)


func _clear_walk_input() -> void:
	_walk_stack.clear()
	_walk_direction = Vector2i.ZERO
	_walk_remainder_px = 0.0
	_running = false
	_last_walk_direction = Vector2i.ZERO
	_last_walk_time = -1


func handle_key(event: InputEventKey) -> bool:
	var key := int(event.keycode)
	if DIRECTION_KEYS.has(key):
		if not event.pressed:
			_release_walk_direction(DIRECTION_KEYS[key])
		elif not event.echo:
			if _field_touch_style() != 0 and focused:
				_begin_walk(DIRECTION_KEYS[key])
			else:
				press(key)
		return true
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_BACKSPACE]:
		if event.pressed and not event.echo:
			press(key)
		return true
	# 桌面端没有 BOOK 触控键，用 B 打开图鉴（原生触控键 42 的同一入口）。
	if key == KEY_B:
		if event.pressed and not event.echo and not menu_open and book_view == null:
			# Shift+B 是调试预览：换成全开知识表，看到的条目与存档无关。
			show_book(Book.all_records() if event.shift_pressed else {})
		return true
	return false


func cancel_dialogue() -> bool:
	if story == null or dialogue.is_empty() or menu_open or book_open or save_open or service_open() or \
			not focused or not boundary.is_empty():
		return false
	var ordinary: bool = dialogue.get("ordinary", false)
	var id := int(dialogue.get("id", -1))
	var npc_id := int(dialogue.get("npc_id", -1))
	dialogue = {}
	dialogue_index = 0
	if ordinary:
		_dispatch_npc_service(npc_id)
	elif not story.complete_effect(id):
		_stop("原生对话退出未能完成对应剧情门；未推进后续记录。")
		_refresh()
		return false
	else:
		_drain_effects()
	_refresh()
	return true


func interact_npc() -> bool:
	if story == null or menu_open or book_open or save_open or service_open() or world_map_view != null or \
			not focused or \
			battle_view != null or \
			not boundary.is_empty() or not dialogue.is_empty() or not _motions.is_empty() or \
			not narration.is_empty() or not mastery.is_empty() or \
			story.stable_state().is_empty():
		return false
	var hero := _actor(0)
	if hero.is_empty():
		return false
	var viewport := get_viewport()
	_service_snapshot = viewport.get_texture().get_image() if viewport != null else null
	var facing_npc := _facing_npc(hero, int(hero.get("lastDirection",
		int(hero.get("direction", FieldAction.Facing.DOWN)))))
	if facing_npc.is_empty():
		note = ""
		_refresh()
		return false
	_look_at(hero, facing_npc)
	for actor: Dictionary in story.progress.actors:
		if int(actor.id) != int(facing_npc.id):
			continue
		# 原生 `Field_Basic_mRun` 每帧用 `Object_objNEAR(3, -1, -1, hero.x, hero.y, direction_code, 900)`
		# 选出「面前最近的 NPC」：朝向上的半平面 + 30 px 半径；`Field_Basic_mKeyPressed` 的 -5
		# 只对这一个成立，并先 `Object_objLOOK(hero, npc)` 把主角转向 NPC。
		# 原生 Evt_stdKEY：事件首记录是触发器 4 且定义号匹配时，
		# 确定键先满足剧情门，不再只播 NPC 的 CHT 组 0。
		if story.trigger_interaction(int(actor.id)):
			_drain_effects()
			_refresh()
			return true
		var bound := false
		for binding: Dictionary in story.map.info.get("npc_bindings", []):
			if int(binding.record_index) == int(actor.id):
				bound = true
				break
		if not bound:
			_stop("NPC %d 没有 NPC 绑定记录；未猜测对话编号。" % int(actor.id))
			_refresh()
			return false
		var npc_id := int(actor.id)
		var source := _npc_dialogue_source(npc_id)
		if source.is_empty():
			_stop("NPC %d 的地图节点没有声明 npc_dialogue；未猜测对话编号。" % npc_id)
			_refresh()
			return false
		# `Field_Basic_Chat:13-42`：`Qst_icoGET(npc_id)` 是 2／3／4 时**不读 NPC CHT**，
		# 改读 `qst/qst%04d.cht`（任务号来自 `Qst_stdQuest`），组号 0／1／2 对应
			# 可接／进行中／目标达成；读不到才回退到 NPC CHT 组 0。
		var group := 0
		var doc: Variant = null
		var icon := _quest_icon_code(npc_id, story.event_step())
		if icon in [2, 3, 4]:
			var log: QuestLog = story.quest_log()
			var table: QuestTable = _quest_table_resource()
			var quest_id := -1
			if log != null and table != null:
				quest_id = log.offered(table, npc_id, _quest_context())
			if quest_id >= 0:
				var quest_source := "qst/qst%04d.cht" % quest_id
				var quest_group := icon - 2
				var quest_doc: Variant = _dialogue_doc(quest_source)
				var quest_records: Array = _dialogue_records(quest_doc, quest_group)
				if not quest_records.is_empty():
					doc = quest_doc
					source = quest_source
					group = quest_group
		if doc == null:
			doc = _dialogue_doc(source)
			group = 0
		var records: Array = _dialogue_records(doc, group)
		if records.is_empty():
			_stop("NPC %d 的 CHT 组 %d 缺失或契约不兼容：%s" % [npc_id, group, source])
			_refresh()
			return false
		dialogue = {"ordinary": true, "source": source, "group": group,
			"npc_id": npc_id, "records": records.duplicate(true)}
		dialogue_index = 0
		note = ""
		_refresh()
		return true
	note = ""
	_refresh()
	return false


## 原生 `Evt_chtDESTROY`：对话窗销毁时（确认播完或 CLR 退出都一样）调
## `Evt_chtMENU`，按 NPC 记录第 18 字节（`NpcDefinition.interaction_code`）决定目标页。
## 剧情门（`ordinary == false`）走事件记录，不进这里。
func _dispatch_npc_service(npc_id: int) -> void:
	var binding := _npc_binding(npc_id)
	if binding.is_empty():
		_stop("NPC %d 没有 NPC 绑定记录；无法读取交互码。" % npc_id)
		return
	var code := int(binding.interaction_code)
	# 原生 `Evt_chtMENU` 只有交互码 2／4／5 不问 `Qst_chtMENU`（任务图标状态门）；其余（含 0 与
	# 7 以上的 default 分支）都先问它，返回 1 表示已切到任务页、调用方不再开自己的服务页。
	if code not in SERVICE_QUEST_GATE_EXEMPT and _quest_gate(code, npc_id):
		return
	if not SERVICE_ROUTES.has(code):
		# 原生 default 分支只问 `Qst_chtMENU`（任务门）就返回，不开任何页面。
		return
	var route: Dictionary = SERVICE_ROUTES[code]
	_freeze_field()
	var page: ServicePage = route.page
	var shop_mode := int(route.shop_mode)
	# 原生交互码 1 走到这里说明 `Qst_chtMENU(id, 1)` 没切页（状态 2 的「可接」在交互码 1 上
	# 不切详情，见 `Qst_chtMENU` 的 `a2 == 1` 分支），落点是 `FIELD_STATE_GUILD_LIST`(6)；
	# 公会页要先记住这只见习 NPC。
	var opened := false
	if page == ServicePage.GUILD:
		guild_npc_id = npc_id
		opened = _open_guild_menu(0)
	elif shop_mode != SHOP_MODE_NONE:
		# 交互码 3／6 都进商店列表页，靠 `shop_mode` 区分买卖（见 `SERVICE_ROUTES`）。
		opened = _open_shop(shop_mode)
	elif page == ServicePage.MONSTER_MENU:
		opened = _open_monster_menu()
	elif page == ServicePage.WARP_WORLD:
		opened = _open_warp_world()
	elif page == ServicePage.INN:
		opened = _open_inn()
	# 页面没打开（缺资源／数据、或前置条件不满足）时不能把野外留在 `_freeze_field()` 的冻结里：
	# 原生这一步等价于 `SetNext(FIELD_STATE_BASIC)`，这里补一次解冻＋重绘，否则角色不能动、
	# 底部操作界面也不会画出来。
	if not opened and not service_open():
		_restore_field_pause()
		_refresh()


## 原生交互码 3／6 → `FIELD_STATE_ITEM_LIST`(12)，差别只在 `ItemData.shop_mode_code`
## （3 写 1 = 买、6 写 0 = 卖），同一个列表页按它决定「买卖入口」的两行内容。
func _open_shop(shop_mode: int) -> bool:
	if story == null or service_open() or _assets == null:
		return false
	shop_view = ShopListScene.instantiate()
	shop_view.z_index = 250
	add_child(shop_view)
	shop_view.closed.connect(_close_shop)
	shop_view.completed.connect(_shop_completed)
	shop_view.food_requested.connect(_open_food_shop)
	shop_mode_code = shop_mode
	service_page = ServicePage.SHOP
	_clear_walk_input()
	story.paused = true
	shop_view.call("present", story, _assets, shop_mode)
	_refresh()
	return true


## 原生 CLR 走 `mRun` 的关窗计数到 −4 才 `SetNext(FIELD_STATE_BASIC)`。
func _close_shop() -> void:
	if food_view != null and is_instance_valid(food_view):
		remove_child(food_view)
		food_view.queue_free()
	food_view = null
	if shop_view != null and is_instance_valid(shop_view):
		remove_child(shop_view)
		shop_view.queue_free()
	shop_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## 原生 `Field_Item_List_mKeyPressed` 的第三行 → `SetNext(FIELD_STATE_ITEM_FOOD)`(15)。
## 商店列表页留在树上（原生关窗后还要回来），这里只把它藏起来。
func _open_food_shop() -> void:
	if story == null or _assets == null or food_view != null:
		return
	food_view = FoodShopScene.instantiate()
	food_view.z_index = 250
	add_child(food_view)
	food_view.closed.connect(_close_food_shop)
	food_view.completed.connect(_shop_completed)
	if shop_view != null:
		shop_view.hide()
	food_view.call("present", story, _assets)
	_refresh()


## 原生 `Field_Item_Food_mRun`：关窗 −4 → `SetNext(ITEM_LIST, 2)`（光标回第三行）。
func _close_food_shop() -> void:
	if food_view != null and is_instance_valid(food_view):
		remove_child(food_view)
		food_view.queue_free()
	food_view = null
	if shop_view != null and is_instance_valid(shop_view):
		shop_view.call("present", story, _assets, shop_mode_code, 2)
		shop_view.show()
	else:
		_close_shop()
		return
	_refresh()


## 成交过就把 HUD 的金钱重画一遍（`_refresh()` 会带 `_hero_summary`）。
func _shop_completed() -> void:
	_refresh()


## `Qst_chtMENU(id, 交互码)`：任务图标状态门（`Qst_icoGET` 的返回码），返回 true 表示
## 已经切到任务页、`Evt_chtMENU` 的调用方不再开自己的服务页。原生三档：
## - 码 4（`Qst_icoGET` 目标达成）→ `Qst_stdQuest` 取在册任务号 → `FieldCanvas_SetNext(FIELD_STATE_QUEST_COMPLETE, 任务号)`；
## - 码 2（可接）且交互码不是 1 → `Qst_stdQuest` 取任务号，`< 0` 返回 0，否则 → `FIELD_STATE_QUEST_DETAIL`(10)；
## - 码 3（进行中）只 `Qst_icoSET` 刷新图标后返回 0，其余码返回 0 让调用方继续。
func _quest_gate(code: int, npc_id: int) -> bool:
	var table := _quest_table_resource()
	if table == null or story == null:
		return false
	var log: QuestLog = story.quest_log()
	if log == null:
		return false
	var context := _quest_context()
	var state := log.status(table, npc_id, context)
	if state == QuestMark.Code.GOAL_REACHED:
		var active := log.active_for(npc_id)
		if active >= 0:
			return _open_quest_complete(active)
		return false
	if state == QuestMark.Code.ACCEPTABLE and code != InteractionCode.GUILD:
		var offered: Array[int] = log.available(table, npc_id, context)
		if not offered.is_empty():
			return _open_quest_detail(offered[0], QuestLog.CONTEXT_NPC)
	return false


## `Qst_stdQuest` 的两个上下文量：`guild_code_bits` 与
## `current_event_resource_id % 1000`。公会码唯一读点是 `Story.guild_code()`（缺键取原生初值 99），
## 与状态页 RANK、公会任务判定读同一个值。
func _quest_context() -> Dictionary:
	return {"guild_code": Story.guild_code(story.progress),
		"event_id": int(story.progress.get("eventId", 0))}


func _quest_table_resource() -> QuestTable:
	if _quests == null:
		_quests = QuestSetLoader.load_table()
		if _quests == null:
			_stop("任务目录 field/quest_set 缺失；无法判定任务状态。")
	return _quests


## 原生 `Field_Quest_Detail_init`（场景 `SetNext(8)` 或 `SetNext(10)`，同一张详情页）。
## `context` = `Qst_chtINIT(context, quest_id)` 写进 `QstData.context_parameter_bits` 的值，
## 它同时决定标题（513 公会任务／514 支线任务）与写哪个槽区间。
func _open_quest_detail(quest_id: int, context: int) -> bool:
	var table := _quest_table_resource()
	if table == null or story == null or service_open() or _assets == null:
		return false
	# 原生进门先 `Field_Basic_Capture`；任务详情与世界地图共用这张定格背景（窗口栈的底），
	# 地图压上来时不再重新抓帧，详情窗不会出现在自己的背景里。
	var snapshot: Image = _service_snapshot
	if snapshot == null or snapshot.is_empty():
		var viewport := get_viewport()
		snapshot = viewport.get_texture().get_image() if viewport != null else null
	quest_view = QuestDetailScene.instantiate()
	quest_view.z_index = 250
	add_child(quest_view)
	quest_view.closed.connect(_close_quest)
	quest_view.accepted.connect(_quest_accepted)
	service_page = ServicePage.QUEST
	_clear_walk_input()
	story.paused = true
	var shown: bool = quest_view.call("present", _assets, table, story.quest_log(), quest_id, context,
		{}, story.progress, snapshot)
	if not shown:
		_close_quest()
		return false
	_refresh()
	return true


## 原生状态 11：整页复用 `Battle_Win_*`（228×240），`Field_Quest_Complete_SetResult` 算奖。
func _open_quest_complete(quest_id: int) -> bool:
	var table := _quest_table_resource()
	if table == null or story == null or service_open() or _assets == null:
		return false
	quest_view = QuestCompleteScene.instantiate()
	quest_view.z_index = 250
	add_child(quest_view)
	quest_view.rewarded.connect(_quest_rewarded)
	quest_view.finished.connect(_close_quest)
	service_page = ServicePage.QUEST
	_clear_walk_input()
	story.paused = true
	var shown: bool = quest_view.call("present_quest", _assets, table, story.quest_log(),
		quest_id, story.progress)
	if not shown:
		_close_quest()
		return false
	_refresh()
	return true


func _quest_accepted(quest_id: int, _slot: int) -> void:
	# 原生 `Qst_stdSET@0x93B34:27-43` 先推「(接受)」，再由 `Qst_chtKeyPress@0x943A0:72-80`
	# 按任务自己的 goal 现场清点一次（已有数量以 `[N/M]` 提示出来）。
	_present_quest_set(quest_id)
	if story != null:
		story.refresh_quest_goal(quest_id)
		_drain_effects()
	_close_quest()


## 任务／事件提示记录的第一页（标题）：原生 `JC_fxtPAGE(resource, 0)`，页分隔是制表符
## （`JC_fntCHANGE(resource, 9, 10)` 把它换成换行，见 `Qst_stdSET@0x93B34:34`）。
func _quest_title(quest_id: int, source := TextTables.QUEST_SOURCE) -> String:
	if _assets == null:
		return ""
	var payload: String = _assets.text_message(source, quest_id)
	return payload.split("\t")[0].strip_edges() if payload.contains("\t") else payload.strip_edges()


## 入账：金钱／经验／属性进度由 `QuestReward.apply()` 写，道具走 `Story` 的背包规则。
func _quest_rewarded(quest_id: int, model: RefCounted) -> void:
	if story == null or model == null:
		return
	var report: Dictionary = story.grant_quest_reward(model)
	if not report.get("full", []).is_empty():
		_stop("任务奖励道具 %s 背包已满，未能入包。" % str(report.full))
	# 原生 `Field_Quest_Complete_SetResult@0x3E490:72-76` 先 `Item_stdAddEx`（奖励道具的
	# 入手提示）再 `Qst_stdComplete`（「#C5」+任务标题+「(完成)」），所以先把道具提示落地再推完成提示。
	_drain_effects()
	_present_quest_set(quest_id, TextTables.QUEST_SOURCE, Msg.Id.QUEST_DONE)
	_refresh()


func _close_quest() -> void:
	if quest_view != null and is_instance_valid(quest_view):
		remove_child(quest_view)
		quest_view.queue_free()
	quest_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## 原生交互码 5 → `FIELD_STATE_INN`(16)：`Field_Inn_mPaint` 画的是
## `Menu_win_Box2_DrawSelect(160, null, fxt 90, …)` 的两选一确认（160×70 @ (120,85)）。
func _open_inn() -> bool:
	if story == null or service_open() or _assets == null:
		return false
	inn_view = InnScene.instantiate()
	inn_view.z_index = 250
	add_child(inn_view)
	inn_view.closed.connect(_close_inn)
	service_page = ServicePage.INN
	_clear_walk_input()
	story.paused = true
	inn_view.call("present", _assets, story)
	_refresh()
	return true


## 原生 `Field_Inn_mRun` 的关窗计数到 −4 才 `SetNext(FIELD_STATE_BASIC)`。
func _close_inn() -> void:
	if inn_view != null and is_instance_valid(inn_view):
		remove_child(inn_view)
		inn_view.queue_free()
	inn_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## 野生触控键 48 → 原生 `Field_Basic_mKeyPressed` 的 key==48 分支 → `FIELD_STATE_WARP1`(4)。
## 只有 `(1 << map_group) & 0x2B` 的分组开页；`& 0x14` 的分组提示「暂时不可传送」，其余静默返回。
func _open_warp_confirm() -> bool:
	if story == null or warp_confirm_view != null or _assets == null or \
			not _pending_warp.is_empty() or menu_open or book_open or save_open or \
			service_open() or battle_view != null or world_map_view != null or \
			not _encounter.is_empty() or not boundary.is_empty() or not dialogue.is_empty() or \
			not _motions.is_empty() or not focused:
		return false
	# 原生 `Field_Basic_mKeyPressed:88-103` 的 key 48 只按 game mode 与 `map_file_number` 分组判定，
	# 没有剧情门；37「暂时不可传送」只属于分组 `& 0x14` 那一支。
	var group := int(story.map.info.get("map_group", -1))
	if group in WARP_BLOCKED_GROUPS:
		MessageStack.say_record(Msg.Id.WARP_UNAVAILABLE)
		return false
	if not group in WARP_BOARD_GROUPS:
		return false
	warp_confirm_view = WarpConfirmScene.instantiate()
	warp_confirm_view.z_index = 250
	add_child(warp_confirm_view)
	warp_confirm_view.closed.connect(_close_warp_confirm)
	warp_confirm_view.board_requested.connect(_board_airship)
	service_page = ServicePage.WARP_CONFIRM
	_clear_walk_input()
	story.paused = true
	warp_confirm_view.call("open", _assets)
	_refresh()
	return true


## 原生 `Field_Warp1_mRun`：关窗计数到 −4 才回 `FIELD_STATE_BASIC`。
func _close_warp_confirm() -> void:
	if warp_confirm_view != null and is_instance_valid(warp_confirm_view):
		remove_child(warp_confirm_view)
		warp_confirm_view.queue_free()
	warp_confirm_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## `Field_Warp1_mKeyPressed` 的 −5 且光标 0（是）：先把上船位置记进
## `ParamData.warp_saved_*`，再把待定目的地写成飞艇内部地图 148 / tile (7,12)。
func _board_airship() -> void:
	if story == null or not _pending_warp.is_empty():
		return
	var parameter: Variant = story.progress.get("parameter")
	var player: Variant = story.progress.get("player")
	if not parameter is Dictionary:
		return
	var hero := _actor(0)
	var fallback_x := int(hero.x) if not hero.is_empty() else 0
	var fallback_y := int(hero.y) if not hero.is_empty() else 0
	parameter["warp_saved_map_id"] = int(story.map.get("id", 0))
	parameter["warp_saved_tile_x"] = int(player.get("x", fallback_x)) if player is Dictionary else fallback_x
	parameter["warp_saved_tile_y"] = int(player.get("y", fallback_y)) if player is Dictionary else fallback_y
	_begin_pending_warp(AIRSHIP_MAP_ID, AIRSHIP_TILE.x, AIRSHIP_TILE.y)


## 原生把目的地写进 `MapData.warp_target_map_id/tile_x/tile_y` 后播英雄 ANI 10；
## 换图由 `Field_Hero_procNext` 的 ANI 10 分支在动画结束时调 `Map_warpProc` 完成。
func _begin_pending_warp(map_id: int, tile_x: int, tile_y: int) -> void:
	var hero := _actor(0)
	if hero.is_empty():
		return
	_pending_warp = {"map_id": map_id, "tile_x": tile_x, "tile_y": tile_y}
	_warp_ready = false
	_clear_walk_input()
	# 待定传送会作废脚下的脚本移动；模型里那份也要取消，否则 `stable_state()` 永远为空，
	# 换图动画播完后仍不出触控界面。
	if story != null:
		for motion_id: int in _motions.keys():
			story.cancel_move(motion_id)
	_motions.clear()
	hero.action = FieldAction.Hero.WARP
	hero["animationEndMode"] = ONE_SHOT_ANIMATION_END_MODE
	_sync_actors()
	_refresh()


## 原生 `Map_warpProc`。目标地图有效才换图（`Map_warpIsAble`）；`n3 >= 0` 让
## `Map_warpIsEnable` 的检查短路，所以飞艇目的地不看 `warpEnabled`。`EvtData.step_index <= 0`
## 时把目标图记为已通过（`Map_warpSetPASS`），随后英雄落到目标格中心、跟随者贴齐。
## `Field_Hero_procNext` 的 ANI 10 分支之后还会播 ANI 11（落地动作）。
func _apply_pending_warp() -> void:
	_warp_ready = false
	var target := int(_pending_warp.get("map_id", -1))
	var tile_x := int(_pending_warp.get("tile_x", 0))
	var tile_y := int(_pending_warp.get("tile_y", 0))
	_pending_warp = {}
	if story == null:
		return
	var loaded: Variant = _resources.call("load_map", target) \
		if _resources.has_method("load_map") else null
	if loaded is Resource:
		loaded = loaded.get_meta("payload", null)
	if loaded is Dictionary:
		loaded = Story._native_numbers(loaded)
	if not loaded is Dictionary or loaded.get("id") != target or \
			not loaded.get("terrain") is Dictionary or \
			not loaded.get("info") is Dictionary or \
			not loaded.get("sheets") is Array or \
			not Story._uint(loaded.terrain.get("width_tiles")) or \
			not Story._uint(loaded.terrain.get("height_tiles")) or \
			tile_x >= loaded.terrain.width_tiles or tile_y >= loaded.terrain.height_tiles:
		_stop("传送目标缺失或落点越界：m%d；未替换地图。" % target)
		var failed := _actor(0)
		if not failed.is_empty():
			failed.action = FieldAction.Hero.IDLE
			failed.erase("animationEndMode")
			_sync_actors()
		_refresh()
		return
	if int(story.progress.get("cursor", 0)) <= 0:
		var passed: Variant = story.progress.get("warpPassed")
		if not passed is Dictionary:
			passed = {}
			story.progress["warpPassed"] = passed
		passed[str(target)] = true
	# 换图成功：原生 `Map_warpProc:54` 无条件 `Game_msgInit(1, …)`，目标图就是当前图也弹。
	_map_name_source = MapNameView.Source.WARP
	story.after_move(loaded, {"x": tile_x, "y": tile_y}, true)
	var hero := _actor(0)
	if not hero.is_empty():
		hero.action = FieldAction.Hero.ARRIVE
		hero["animationEndMode"] = ONE_SHOT_ANIMATION_END_MODE
		_sync_actors()
	_drain_effects()
	_refresh()


## 英雄的非循环动作播完（`field_actors.animation_finished`）：ANI 10 落地换图，其余一次性动作回待机。
func _on_actor_animation_finished(actor_id: int) -> void:
	if actor_id != 0 or story == null:
		return
	var hero := _actor(0)
	var action := int(hero.get("action", 0))
	if action == FieldAction.Hero.WARP and not _pending_warp.is_empty():
		# 不在这里换图：当前正处在 `field_actors.advance` 的 body 动画回调里，
		# 换图会重建/释放 actor；下一帧 `advance` 开头再执行。
		_warp_ready = true
	elif action in [FieldAction.Hero.MINE_ORE, FieldAction.Hero.SHAKE_TREE]:
		# 采集是「一遍一播 + 显式重播」：每遍末帧算一次，第二遍结束才收回待机并结算。
		if not _harvest.is_empty() and int(_harvest.get("action", -1)) == action:
			_next_map_harvest_play()
		else:
			_clear_hero_gesture(hero)
	elif action == FieldAction.Hero.ARRIVE:
		_clear_hero_gesture(hero)


func _clear_hero_gesture(hero: Dictionary) -> void:
	hero.action = FieldAction.Hero.IDLE
	hero.erase("animationEndMode")
	_sync_actors()


## 原生交互码 4 → `FIELD_STATE_WARP2`(5)。`Field_Warp2_init` 只载 `common/ui_world.fbm`
## 并把选中项放到「当前」；候选下标 3 来自 `ParamData.warp_saved_*`（上船位置），
## 其余四项是静态表 `world_warp_candidates`（.rodata 0x98A9C）。
func _open_warp_world() -> bool:
	if story == null or warp_world_view != null or _assets == null or \
			not _pending_warp.is_empty() or battle_view != null or \
			not _encounter.is_empty() or not boundary.is_empty():
		return false
	var data: Variant = _assets.call("load_world_map") \
		if _assets.has_method("load_world_map") else null
	if data == null:
		_stop("世界地图节点表缺失；未打开飞艇世界地图。")
		_refresh()
		return false
	var parameter: Dictionary = story.progress["parameter"]
	warp_world_view = WarpWorldScene.instantiate()
	warp_world_view.z_index = 250
	add_child(warp_world_view)
	warp_world_view.closed.connect(_free_warp_world)
	warp_world_view.close_requested.connect(_close_warp_world)
	warp_world_view.move_requested.connect(_begin_pending_warp)
	if not warp_world_view.call("open", _assets, data,
			int(parameter.get("warp_saved_map_id", Story.WARP_SAVED_MAP_INITIAL)),
			int(parameter.get("warp_saved_tile_x", Story.WARP_SAVED_TILE_INITIAL)),
			int(parameter.get("warp_saved_tile_y", Story.WARP_SAVED_TILE_INITIAL)),
			story.progress.warpEnabled, story.progress.warpPassed):
		remove_child(warp_world_view)
		warp_world_view.queue_free()
		warp_world_view = null
		return false
	service_page = ServicePage.WARP_WORLD
	_clear_walk_input()
	story.paused = true
	_refresh()
	return true


func _close_warp_world() -> void:
	if warp_world_view == null or warp_world_view.closing():
		return
	warp_world_view.closed.connect(_free_warp_world, CONNECT_ONE_SHOT)
	warp_world_view.call("close")


func _free_warp_world() -> void:
	if warp_world_view != null and is_instance_valid(warp_world_view):
		remove_child(warp_world_view)
		warp_world_view.queue_free()
	warp_world_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## 原生交互码 2 → `GameCanvas_SetNext(GAME_STATE_MONSTER_LIST=21, 0)`（`Evt_chtMENU`
## 的 `0x7DA14`–`0x7DA1C`，先 `Field_Basic_Capture()`）。这一页不在 `FieldCanvas` 的 13 页里，
## 但它是交互码分派的一部分；两行分别进合成（22，`_open_monster_mix`）与强化（23，`_open_monster_enchant`）。
## `position` 是 `GameCanvas_SetNext` 的 transition：两页关窗时回本页并给 0／1
## （`Game_Monster_Mix_mRun` 给 0、`Game_Monster_Enchant_mRun` 给 1）。
func _open_monster_menu(position: int = 0) -> bool:
	if story == null or monster_menu_view != null or monster_mix_view != null or \
			monster_enchant_view != null or _assets == null or not _pending_warp.is_empty() or \
			battle_view != null or not _encounter.is_empty() or not boundary.is_empty():
		return false
	monster_menu_view = MonsterMenuScene.instantiate()
	monster_menu_view.z_index = 250
	add_child(monster_menu_view)
	monster_menu_view.closed.connect(_close_monster_menu)
	monster_menu_view.selected.connect(_monster_menu_selected)
	monster_menu_view.call("present", _assets, position)
	service_page = ServicePage.MONSTER_MENU
	_clear_walk_input()
	story.paused = true
	_refresh()
	return true


## `Game_Monster_List_mRun` 是空壳、CLR 直接 `SetNext(GAME_STATE_FIELD, 1)`：
## 关页瞬时，野外由 `Field_Basic_init` 重新初始化（本移植等价于一次 `_refresh()`）。
func _close_monster_menu() -> void:
	if monster_menu_view != null and is_instance_valid(monster_menu_view):
		remove_child(monster_menu_view)
		monster_menu_view.queue_free()
	monster_menu_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


## `Game_Monster_List_mKeyPressed` 的 −5：游标 0 → `GAME_STATE_MONSTER_MIX`(22)、
## 游标 1 → `GAME_STATE_MONSTER_ENCHANT`(23)，两页都已落地（取证见 `wiki\growth\game-monster-list.md`）。
func _monster_menu_selected(action: String) -> void:
	_close_monster_menu()
	if action == "mix":
		if _open_monster_mix():
			return
		_stop("精灵合成页打不开：当前流程不稳定或页面已在用。")
		_refresh()
		return
	if action == "enchant":
		if _open_monster_enchant():
			return
		_stop("精灵强化页打不开：当前流程不稳定或页面已在用。")
		_refresh()
		return
	_stop("精灵管理所的未知条目 %s。" % action)
	_refresh()


## `GAME_STATE_MONSTER_MIX`(22)：`Game_Monster_Mix_init` 建的显示表**排除**出战三只
## （`Game_Monster_SetList(0)`），页面自己管六个子状态。
func _open_monster_mix() -> bool:
	if story == null or monster_mix_view != null or _assets == null or \
			not _pending_warp.is_empty() or battle_view != null or \
			not _encounter.is_empty() or not boundary.is_empty():
		return false
	monster_mix_view = MonsterMixScene.instantiate()
	monster_mix_view.z_index = 250
	add_child(monster_mix_view)
	monster_mix_view.closed.connect(_close_monster_mix)
	monster_mix_view.completed.connect(_monster_mix_completed)
	monster_mix_view.call("present", story, _assets)
	service_page = ServicePage.MONSTER_MIX
	_clear_walk_input()
	story.paused = true
	_refresh()
	return true


## `Game_Monster_Mix_mRun` 的相位 −4 → `GameCanvas_SetNext(GAME_STATE_MONSTER_LIST, 0)`：
## 回精灵管理所并把游标停在「精灵合成」那一行。落点是 `GAME_STATE_MONSTER_LIST` 而不是野外
## （它的 `mRun` 是空壳），所以这一帧野外仍按 `_restore_field_pause()` 判据冻结；
## 只有管理所自己 CLR（`Game_Monster_List_mKeyPressed` 的 −16 → `SetNext(FIELD_STATE_BASIC)`）
## 才把推进交回地图。
func _close_monster_mix() -> void:
	if monster_mix_view != null and is_instance_valid(monster_mix_view):
		remove_child(monster_mix_view)
		monster_mix_view.queue_free()
	monster_mix_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	# 管理所重建失败（如边界文本未清）时野外仍冻结，这一帧要自己把面板刷成边界面。
	if not _open_monster_menu(0):
		_refresh()


## `Game_Monster_Mix_Proc` 末尾的 `Game_saveSAVE()`：写当前槽，不弹存盘提示。
func _monster_mix_completed() -> void:
	if _store != null and story != null:
		_commit_save()
	_refresh()


## `GAME_STATE_MONSTER_ENCHANT`(23)：`Game_Monster_Enchant_init` 建的是一整包精灵表
## （`Game_Monster_SetList(1)` 含出战精灵），页面自己管六个子状态。
func _open_monster_enchant() -> bool:
	if story == null or monster_enchant_view != null or _assets == null or \
			not _pending_warp.is_empty() or battle_view != null or \
			not _encounter.is_empty() or not boundary.is_empty():
		return false
	monster_enchant_view = MonsterEnchantScene.instantiate()
	monster_enchant_view.z_index = 250
	add_child(monster_enchant_view)
	monster_enchant_view.closed.connect(_close_monster_enchant)
	monster_enchant_view.completed.connect(_monster_enchant_completed)
	monster_enchant_view.call("present", story, _assets)
	service_page = ServicePage.MONSTER_ENCHANT
	_clear_walk_input()
	story.paused = true
	_refresh()
	return true


## `Game_Monster_Enchant_mRun` 的相位 −4 → `GameCanvas_SetNext(GAME_STATE_MONSTER_LIST, 1)`：
## 回精灵管理所并把游标停在「精灵强化」那一行，不直接回野外（同合成页，野外此时仍冻结）。
func _close_monster_enchant() -> void:
	if monster_enchant_view != null and is_instance_valid(monster_enchant_view):
		remove_child(monster_enchant_view)
		monster_enchant_view.queue_free()
	monster_enchant_view = null
	service_page = ServicePage.NONE
	_restore_field_pause()
	if not _open_monster_menu(1):
		_refresh()


## `Game_Monster_Enchant_Proc` 末尾的 `Game_saveSAVE()`：写当前槽，不弹存盘提示。
func _monster_enchant_completed() -> void:
	if _store != null and story != null:
		_commit_save()
	_refresh()


## 原生交互码 1 → `FIELD_STATE_GUILD_LIST`(6)。`Field_Guild_List_mPaint` 画的是
## `Game_Menu_List_Draw` 的三行固定菜单（排名挑战／公会任务／会长的建议，`msg` 51/52/53），
## 没有名录、没有成员列表——这三行和一行提示就是公会的全部入口。
func _open_guild_menu(position: int = 0) -> bool:
	if story == null or service_open() or _assets == null:
		return false
	guild_menu_view = GuildMenuScene.instantiate()
	guild_menu_view.z_index = 250
	add_child(guild_menu_view)
	guild_menu_view.selected.connect(_guild_menu_selected)
	guild_menu_view.closed.connect(_close_guild)
	service_page = ServicePage.GUILD
	_clear_walk_input()
	story.paused = true
	guild_menu_view.call("present", _assets, position)
	_refresh()
	return true


## 公会子页的 CLR 在原生是 `SetNext(FIELD_STATE_GUILD_LIST, 0/1/2)`——一次状态切换，中间没有
## 「没有服务页」的一帧。本工程靠 `service_page` 登记当前页，重开菜单前必须先把它清掉，
## 否则 `_open_guild_menu` 的 `service_open()` 守卫会挡住这次重开，页面全被释放而登记还留着，
## 野外就再无任何页面可交互（表现为永久冻结）。
func _reopen_guild_menu(position: int) -> void:
	_free_guild_pages()
	service_page = ServicePage.NONE
	_open_guild_menu(position)


## 原生状态 6 的确认直接 `SetNext(7 / 8 / 9)`，不播关窗（新页自己重播开窗动画）。
func _guild_menu_selected(action: String) -> void:
	match action:
		"info":
			_free_guild_pages()
			_open_guild_info(0)
		"challenge":
			_free_guild_pages()
			_open_guild_challenge()
		_:
			_free_guild_pages()
			_open_guild_quest()


## 原生状态 8：`Field_Guild_List_mKeyPressed` 的 case 1 先 `Qst_stdQuest(npc)`，取到才
## `Qst_chtINIT(2, quest_id)` + `SetNext(8)`；状态 8 自己不画窗，整页由 `Qst_chtDRAW` 出，
## 所以直接复用 `quest_detail`（公会上下文 = 槽 0、标题 513）。
func _open_guild_quest() -> bool:
	var table := _quest_table_resource()
	if table == null or story == null or _assets == null or guild_quest_view != null:
		return false
	guild_quest_view = GuildQuestScene.instantiate()
	guild_quest_view.z_index = 250
	add_child(guild_quest_view)
	guild_quest_view.closed.connect(_close_guild_quest)
	guild_quest_view.accepted.connect(_quest_accepted)
	var shown: bool = guild_quest_view.call("present_for_npc", _assets, table,
		story.quest_log(), guild_npc_id, _quest_context())
	if not shown:
		# 原生这时不建窗口，改用 `Game_infoInit` 弹一行野外信息（47 可接受排名／48 没有任务／49 已最高），
		# 所以走提示栈而不是 `_stop`——「今天没任务」不是代码缺陷。
		var notice := str(guild_quest_view.get("notice"))
		var record := int(guild_quest_view.get("notice_id"))
		if record >= 0:
			MessageStack.say_record(record)
		else:
			MessageStack.say(notice)
		_reopen_guild_menu(1)
		return true
	return true


## 原生 CLR 回状态 6 且 `FieldData+0x14` 带 1（光标停在第二行「公会任务」）。
func _close_guild_quest() -> void:
	_reopen_guild_menu(1)


## 原生状态 7：`Field_Guild_Challenge_*/0x40044/0x3EF00/0x3E968`，窗口 180×136 +
## `Menu_win_Box2_DrawSelect(160, …, msg 59)` 的确认框。确认后 `Game_Guild_Battle_init` 开战。
func _open_guild_challenge() -> bool:
	if story == null or _assets == null or guild_challenge_view != null:
		return false
	var catalog: Variant = _resources.call("load_gameplay") if _resources != null and \
		_resources.has_method("load_gameplay") else null
	if catalog == null:
		_stop("游戏数值表缺失；无法读取公会战对手。")
		return false
	guild_challenge_view = GuildChallengeScene.instantiate()
	guild_challenge_view.z_index = 250
	add_child(guild_challenge_view)
	guild_challenge_view.closed.connect(_close_guild_challenge)
	guild_challenge_view.started.connect(_start_guild_challenge)
	guild_challenge_view.call("present", _assets, catalog,
		Story.guild_code(story.progress))
	_queue_guild_challenge_animations(catalog)
	return true


## 挑战页一打开就把对手 3 只排进预读：确认后 `_open_battle` 只剩结算，冷缓存读盘
## 摊在页面停留的帧里（原生 ANI 常驻 `MemorySlot`，没有首次加载这一档）。
func _queue_guild_challenge_animations(catalog: Variant) -> void:
	var resolved: Dictionary = GuildBattle.enemy_constructors(catalog, Story.guild_code(story.progress))
	if not bool(resolved.get("ok", false)):
		return
	for constructor: Variant in resolved.constructors:
		_queue_battle_identity(MonsterAnimation.battle_identity(int(constructor[0])))


## 原生挑战页 CLR 回状态 6 且 `FieldData+0x14` 带 0（光标回第一行）。
func _close_guild_challenge() -> void:
	_reopen_guild_menu(0)


## `Game_Guild_Battle_init`：`battle.kind = 3`（名次挑战），敌方三只来自
## `Item_datBasic` 类型 28 的组 `99 − code%1000`。战斗沿用野外战那条回收分支（`_battle_id == -2`
## 会写回队员数值并落结算），胜利时额外调 `GuildBattle.apply_win()` 把名次推进一格。
func _start_guild_challenge(constructors: Array) -> void:
	if story == null or _assets == null:
		return
	var catalog: Variant = _resources.call("load_gameplay") if _resources != null and \
		_resources.has_method("load_gameplay") else null
	if catalog == null:
		_stop("游戏数值表缺失；无法组建公会战。")
		return
	var built := GuildBattle.create_battle(catalog, story.progress, constructors, story._roll)
	if not bool(built.get("ok", false)):
		_stop("公会战无法开始：%s" % str(built.get("error", "未知原因")))
		_reopen_guild_menu(0)
		return
	close_service_page()
	story.combat = built.battle
	guild_battle_kind = GuildBattle.KIND_CHALLENGE
	story.paused = true
	_open_battle(-2)


## 原生交互码 1 → 6 → 9：`Field_Guild_Info_Detail_*/0x3FFFC/0x3B61C/0x3E9B0`，
## 窗口 228×208、侧白边 12，正文是 `common/guild.fxt` 的 3 页 ×（标签 + 9 行）。
func _open_guild_info(page: int = 0) -> bool:
	if story == null or _assets == null or guild_info_view != null:
		return false
	guild_info_view = GuildInfoScene.instantiate()
	guild_info_view.z_index = 250
	add_child(guild_info_view)
	guild_info_view.closed.connect(_close_guild_info)
	guild_info_view.call("present", _assets, page)
	return true


## 原生资料页 CLR 回状态 6，且 `FieldData+0x14` 带 2（光标停在第三行）。
func _close_guild_info() -> void:
	_reopen_guild_menu(2)


## 原生 CLR 走 `mRun` 的关窗计数到 −4 才 `SetNext(FIELD_STATE_BASIC)`：关窗动画播完才放行。
func _close_guild() -> void:
	_free_guild_pages()
	service_page = ServicePage.NONE
	_restore_field_pause()
	_refresh()


func _free_guild_pages() -> void:
	for view: Control in [guild_menu_view, guild_info_view, guild_challenge_view, guild_quest_view]:
		if view != null and is_instance_valid(view):
			remove_child(view)
			view.queue_free()
	guild_menu_view = null
	guild_info_view = null
	guild_challenge_view = null
	guild_quest_view = null


## 原生 `Field_Basic_Capture` 把地图拷进 scratch image 再切页。本移植没有野外截图缓冲，
## 冻结的等价做法是停掉整份野外推进（脚本、怪物、镜头都不再前进）。
func _freeze_field() -> void:
	if story != null:
		story.paused = true


## 原生 `Field_Basic_Chat` 按 NPC 记录的 `resource_id` 播 `npc/npcNNNN.cht` 组 0。
## 静态 NPC 的对白源由地图节点的 `metadata/npc_dialogue` 声明（「谁用谁声明」）；事件
## `Op.NPC_RECORDS` 生成的 NPC 没有场景节点，退回 `NpcDefinition.dialogue_source()` 这一处规则。
func _npc_dialogue_source(npc_id: int) -> String:
	if story == null or not story.map.get("info") is Dictionary:
		return NpcDefinition.dialogue_source(npc_id)
	var npcs: Variant = story.map.info.get("npcs", [])
	if npcs is Array:
		for npc: Variant in npcs:
			if npc is Dictionary and int(npc.get("resource_id", -1)) == npc_id:
				var declared: Variant = npc.get("npc_dialogue", "")
				return declared if declared is String else ""
	# 事件 `Op.NPC_RECORDS`（`progress.extraNpcs`）生成的 NPC 没有地图节点，按 NPC 记录号取默认源。
	return NpcDefinition.dialogue_source(npc_id)


## `Field_Basic_Chat:32-42` 的 CHT 装载：`Evt_chtINIT(RES, n3, 0)` 里 `n3` 选组，
## 找不到资源时原生回退到 `npc/npc%04d.cht` 组 0（由调用方处理）。
func _dialogue_doc(source: String) -> Variant:
	if _resources == null or not _resources.has_method("load_dialogue"):
		return null
	var doc: Variant = _resources.call("load_dialogue", source)
	if doc is Resource:
		doc = doc.get_meta("payload", null)
	if not doc is Dictionary or not doc.get("groups") is Array:
		return null
	return doc


## 组内每条记录必须带 `text`（可空但 `text_status == "unmapped"`），否则整组不采用。
func _dialogue_records(doc: Variant, group: int) -> Array:
	if not doc is Dictionary or not doc.get("groups") is Array:
		return []
	var groups: Array = doc.groups
	if group < 0 or group >= groups.size() or not groups[group] is Dictionary:
		return []
	var records: Variant = groups[group].get("records")
	if not records is Array or records.is_empty():
		return []
	for record: Variant in records:
		if not record is Dictionary or not record.has("text") or \
				not (record.text is String or \
				(record.text == null and record.get("text_status") == "unmapped")):
			return []
	return records


func _npc_binding(npc_id: int) -> Dictionary:
	if story == null or not story.map.get("info") is Dictionary:
		return {}
	var bindings: Variant = story.map.info.get("npc_bindings", [])
	if not bindings is Array:
		return {}
	for binding: Variant in bindings:
		if binding is Dictionary and int(binding.get("record_index", -1)) == npc_id:
			return binding
	return {}


## 地图物件的存档态：传送门帧（164／165）看 `warpEnabled`，宝箱帧（176／177）看已开记录。
## `map_id` 必须显式传：`Map_objCREATE` 的宝箱状态是按 `MapData.map_id` 记的，而 `info` 里没有这个号。
func _map_object_state(map_id: int) -> Dictionary:
	return {"map_id": map_id, "warps": story.progress.get("warpEnabled", {}),
		"boxes": story.progress.get("openedBoxes", [])}


## 原生 `Field_Basic_mKeyPressed` 在对话分支之后调
## `Object_objHIT(hero.x, hero.y, direction_code, 1200)`：面前 32 像素内 kind 8 的物件里
## 只有帧 0／5／10（第 0 组）、152、166、176 会被命中，按帧分派见 `MapItemInteraction`。
## 宝箱保留原生三步：`Object_objANI(obj, 177)` → `Field_Box_Set()`（`Map_boxSetExist` +
## `Battle_Drop_BOX`）→ `Game_saveSAVE()`。
func interact_map_object() -> bool:
	if story == null or menu_open or book_open or save_open or service_open() or world_map_view != null or \
			not focused or \
			battle_view != null or not _encounter.is_empty() or \
			not boundary.is_empty() or not dialogue.is_empty() or not _motions.is_empty() or \
			not narration.is_empty() or not mastery.is_empty() or \
			story.stable_state().is_empty():
		return false
	var hero := _actor(0)
	if hero.is_empty():
		return false
	var facing: Vector2i = FACING_TILES.get(int(hero.get("lastDirection", FieldAction.Facing.DOWN)), Vector2i.ZERO)
	if facing == Vector2i.ZERO:
		return false
	# 主角位移是像素级的（actor 的 x/y 是格单位浮点），命中判定也走像素：
	# 原生 `Object_objHIT(hero.x, hero.y, direction_code, 1200)`。
	var hero_pixel := Vector2(float(hero.x) * TILE + 8.0, float(hero.y) * TILE + 8.0)
	var target: Dictionary = _actors.object_at(hero_pixel, int(hero.lastDirection))
	if target.is_empty():
		return false
	var action := int(target.action)
	var record: Dictionary = target.record
	var tile := Vector2i(int(record.tile_x), int(record.tile_y))
	match MapItemInteraction.kind_of(action, int(story.map.info.map_group) == MAP_OBJECT_GROUP_0):
		MapItemInteraction.Kind.ORE:
			return _mine_map_object(hero, tile, facing, action)
		MapItemInteraction.Kind.TREE:
			return _shake_map_object(hero, tile, facing, action)
		MapItemInteraction.Kind.GLOW:
			return _extinguish_map_object(tile)
		MapItemInteraction.Kind.CHEST:
			return _open_map_chest(tile)
	return false


## 帧 152（水晶矿）：原生 `Object_objANI(hero, 3)`；本工程按原版节奏播两遍英雄动作，
## 每遍第 6 帧让矿石反应一次，第二遍命中帧发道具（见 `_tick_map_harvest`）。
func _mine_map_object(hero: Dictionary, tile: Vector2i, facing: Vector2i, action: int) -> bool:
	return _start_map_harvest(hero, tile, facing, MapItemInteraction.Kind.ORE, action)


## 帧 0／5／10（第 0 组地图的树）：原生 `Object_objANI(hero, 4)`。树木没有原生摇晃帧，
## 抖动是 `map_object.tscn` 补的 Scene 动画，关键帧取宽物件受击动作 53／54／55 的偏移节奏。
func _shake_map_object(hero: Dictionary, tile: Vector2i, facing: Vector2i, action: int) -> bool:
	return _start_map_harvest(hero, tile, facing, MapItemInteraction.Kind.TREE, action)


## 帧 166 → 167：原生只换帧（`Object_objANI(obj, 167)`），没有存档与掉落。
func _extinguish_map_object(tile: Vector2i) -> bool:
	if not _actors.switch_object_at(tile, MapItemInteraction.GLOW_FRAME_FROM,
			MapItemInteraction.GLOW_FRAME_TO):
		_stop("物件 %d → %d 的换帧失败；未猜测替代绘制。" % [MapItemInteraction.GLOW_FRAME_FROM,
			MapItemInteraction.GLOW_FRAME_TO])
		_refresh()
		return true
	note = ""
	_refresh()
	return true


## 开始一次采集（对齐原生 `Field_Hero_procCurr`）：英雄动作 3／4 播两遍，
## 每次命中帧（第 6 帧）让物件反应一次；第二遍命中帧才发道具并递减 active_state。
## 第一遍的 `same_animation_request_count == 0` 只播反应不发奖，结束回调重播后计数变 1。
func _start_map_harvest(hero: Dictionary, tile: Vector2i, facing: Vector2i, kind: int, from_action: int) -> bool:
	if not _harvest.is_empty():
		return true
	var action := FieldAction.Hero.MINE_ORE \
		if kind == MapItemInteraction.Kind.ORE else FieldAction.Hero.SHAKE_TREE
	_harvest = {"kind": kind, "tile": tile, "facing": facing, "action": action,
		"from_action": from_action, "play": 0, "hit": false}
	hero.action = action
	hero["animationEndMode"] = ONE_SHOT_ANIMATION_END_MODE
	_sync_actors()
	note = ""
	_refresh()
	return true


## 每帧看主角当前帧：到达命中帧就只触发一次反应（原生 `Field_Hero_procCurr` 的 case 3／4）。
func _tick_map_harvest() -> void:
	if _harvest.is_empty():
		return
	var action := int(_harvest.get("action", -1))
	if int(_actor(0).get("action", 0)) != action or bool(_harvest.get("hit", false)):
		return
	var hit_frame := MapItemInteraction.MINE_HIT_FRAME \
		if int(_harvest.kind) == MapItemInteraction.Kind.ORE else MapItemInteraction.SHAKE_HIT_FRAME
	if _actors.hero_frame() < hit_frame:
		return
	_harvest["hit"] = true
	_map_harvest_hit(int(_harvest.get("play", 0)) > 0)


## 一次命中：物件反应；第二遍命中才结算道具与 active_state。
func _map_harvest_hit(second: bool) -> void:
	var tile: Vector2i = _harvest.get("tile", Vector2i.ZERO)
	var facing: Vector2i = _harvest.get("facing", Vector2i.DOWN)
	var kind := int(_harvest.get("kind", MapItemInteraction.Kind.NONE))
	if kind == MapItemInteraction.Kind.ORE:
		_actors.react_at(tile, MapItemInteraction.ORE_FRAME,
			MapItemInteraction.reaction_action(facing))
	else:
		var from_action := int(_harvest.get("from_action", 0))
		var reaction := MapItemInteraction.tree_reaction_action(from_action, facing)
		if reaction > 0:
			_actors.react_at(tile, from_action, reaction)
	if not second:
		_refresh()
		return
	if _actors.can_harvest_at(tile, kind):
		if _gather_map_item(kind):
			_actors.consume_harvest_at(tile, kind)
	else:
		# 原生 `Field_Hero_procCurr` 的 fxt 412：树次数用尽但还能摇。
		note = _assets.text_message(Msg.SOURCE, 412)
	_refresh()


## 一遍采集动作播完：第一遍结束重播，第二遍结束回待机（奖励已在命中帧结算）。
func _next_map_harvest_play() -> void:
	var hero := _actor(0)
	if hero.is_empty():
		_harvest = {}
		return
	# 低帧率把命中帧整帧跳掉时补一次，避免漏发反应与道具。
	if not bool(_harvest.get("hit", false)):
		_harvest["hit"] = true
		_map_harvest_hit(int(_harvest.get("play", 0)) > 0)
	var play := int(_harvest.get("play", 0)) + 1
	if play < MapItemInteraction.HARVEST_SWINGS:
		_harvest["play"] = play
		_harvest["hit"] = false
		_actors.restart_hero_action()
		return
	_harvest = {}
	_clear_hero_gesture(hero)
	_refresh()


## 宝箱：帧 176 命中后 `Field_Box_Set` 的相位 4（记已开）与相位 6（抽一件入包）一次跑完。
func _open_map_chest(tile: Vector2i) -> bool:
	if not _actors.has_unopened_box(tile):
		return false
	var map_id := int(story.map.get("id", -1))
	var catalog: Node = get_node_or_null("/root/AssetCatalog")
	var world: Variant = catalog.call("load_world_map") \
		if catalog != null and catalog.has_method("load_world_map") else null
	# 掉落表按 `Map_worldGET` 的列号选：> 99 是室内层（`WorldMapData.interior`）。
	var interior: bool = world != null and world.has_method("interior") and \
		bool(world.interior(map_id))
	var result: Dictionary = story.open_box(map_id, interior)
	if not result.get("ok", false):
		_stop(str(result.get("error", "宝箱流程未接通")))
		_refresh()
		return true
	if not _actors.open_box_at(tile):
		_stop("宝箱物件帧切换失败；未猜测替代绘制。")
		_refresh()
		return true
	note = "" if result.get("added", false) else _assets.text_message(Msg.SOURCE, Msg.Id.BOX_EMPTY)
	_save_from_event()
	_refresh()
	return true


## 兜底采集：原版把采矿／摇树的奖励放在「区域调查」事件里（触发 6）。当前事件正等着
## 这个区域的动作时不掉道具（事件会发），返回 true 表示这次采集算成功。
func _gather_map_item(kind: int) -> bool:
	if story.pending_area_action():
		return true
	var table: Array = MapItemInteraction.gather_table(kind)
	if table.is_empty():
		return false
	var drop := MapItemInteraction.gather_drop(kind, randi_range(0, table.size() - 1))
	var result: Dictionary = story.gather_item(int(drop.get("id", -1)), int(drop.get("count", 0)))
	if not result.get("ok", false):
		note = str(result.get("error", "采集入包失败"))
		return false
	_save_from_event()
	return true


## 原生 `Map_tileIsMoveRect` 的像素版：候选脚点 → 16×16 碰撞盒覆盖的格全部可走。
## 额外把实体占位视为阻挡；传送门在踏进新格时判定是否开放。
func _walk_rect_free(foot: Vector2) -> bool:
	if story == null:
		return false
	var min_px := foot - Vector2(TILE, TILE) * 0.5
	var rect := Rect2(min_px, Vector2(TILE, TILE))
	var terrain: Dictionary = story.map.terrain
	var x0 := floori(min_px.x / TILE)
	var y0 := floori(min_px.y / TILE)
	var x1 := floori((min_px.x + TILE - 0.001) / TILE)
	var y1 := floori((min_px.y + TILE - 0.001) / TILE)
	if x0 < 0 or y0 < 0 or x1 >= int(terrain.width_tiles) or y1 >= int(terrain.height_tiles):
		return false
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if story.tile_blocked(tx, ty):
				return false
	for actor: Dictionary in story.progress.actors:
		if int(actor.id) == 0:
			continue
		var body := Rect2(Vector2(float(actor.x), float(actor.y)) * TILE, Vector2(TILE, TILE))
		if rect.intersects(body):
			return false

	return true


## 原生 `Field_Hero_procMOVE`：每帧按速度走像素，被挡就侧滑；位移驱动步态。
func _advance_manual_walk(delta: float) -> bool:
	if story == null or delta <= 0.0 or _walk_direction == Vector2i.ZERO:
		return false
	var hero := _actor(0)
	if hero.is_empty():
		return false
	_face(_walk_direction)
	hero.action = FieldAction.Hero.RUN if _running else FieldAction.Hero.WALK
	hero.erase("animationEndMode")
	var speed_px := (RUN_SPEED if _running else WALK_SPEED) * TILE
	_walk_remainder_px += speed_px * delta
	var pixels := int(floorf(_walk_remainder_px))
	if pixels <= 0:
		return false
	_walk_remainder_px -= float(pixels)
	var before := Vector2(float(hero.x), float(hero.y))
	var start := before * TILE + Vector2(TILE, TILE) * 0.5
	var result: Dictionary = PixelWalk.move_step(start, _walk_direction, pixels, _walk_rect_free)
	var moved := int(result.moved)
	if moved < pixels:
		var slide: Dictionary = PixelWalk.slide_direction(result.position, _walk_direction,
			pixels - moved, _walk_rect_free)
		if not slide.is_empty():
			var slide_result: Dictionary = PixelWalk.move_step(result.position, slide.direction,
				int(slide.pixels), _walk_rect_free)
			result.position = slide_result.position
			moved += int(slide_result.moved)
			if int(slide_result.moved) > 0:
				_face(slide.direction)
	if moved <= 0:
		return false
	var foot: Vector2 = result.position
	hero.x = (foot.x - TILE * 0.5) / TILE
	hero.y = (foot.y - TILE * 0.5) / TILE
	var after := Vector2(float(hero.x), float(hero.y))
	Followers.advance(_followers, before, after, _running,
		not Followers.event_step_running(story.progress))
	_actors.update_position(hero)
	_actors.advance_hero_motion(float(moved) / TILE)
	_focus = _point(hero)
	var stopped := _follow_walk_tile(hero)
	_sync_actors()
	_position_camera()
	return not stopped


## 跨格时同步剧情坐标 + 触发 + 传送；返回 true 表示已换图/必须停下。
func _follow_walk_tile(hero: Dictionary) -> bool:
	var tile := Vector2i(floori(float(hero.x)), floori(float(hero.y)))
	if tile == _walk_tile:
		return false
	_walk_tile = tile
	story.after_move(story.map, {"x": tile.x, "y": tile.y}, false, false)
	if not boundary.is_empty():
		return true
	for warp: Dictionary in story.map.info.get("warps", []):
		if Vector2i(int(warp.tile_x), int(warp.tile_y)) != tile:
			continue
		return _enter_warp(warp)
	return false



## MIF 传送点：目标缺失或落点越界时明确报错，不猜目的地、不改地图。
func _enter_warp(warp: Dictionary) -> bool:
	var hero := _actor(0)
	if hero.is_empty():
		return false
	if not Story._uint(warp.get("destination_map_id")) or \
			not Story._uint(warp.get("destination_tile_x"), 255) or \
			not Story._uint(warp.get("destination_tile_y"), 255):
		_stop("MIF 传送点目标契约不兼容；未猜测目的地。")
		_refresh()
		return true
	var target := int(warp.destination_map_id)
	# 原生 `Map_warpProc:17` 通过、`:59-60` 走 `Game_msgInit(0, fxt404)`：404 落在 index 0 消息条，
	# 不换图，也不进 `Game_infoInit` 的 8 槽提示栈。
	if not bool(story.progress.warpEnabled.get(str(target), false)):
		_warp_blocked_bar.present(_assets.text_message(Msg.SOURCE, Msg.Id.MAP_BLOCKED),
			MapNameView.Source.WARP)
		return true
	var loaded: Variant = _resources.call("load_map", target) \
		if _resources.has_method("load_map") else null
	if loaded is Resource:
		loaded = loaded.get_meta("payload", null)
	if loaded is Dictionary:
		loaded = Story._native_numbers(loaded)
	if not loaded is Dictionary or loaded.get("id") != target or \
			not loaded.get("terrain") is Dictionary or \
			not loaded.get("info") is Dictionary or \
			not loaded.get("sheets") is Array or \
			not Story._uint(loaded.terrain.get("width_tiles")) or \
			not Story._uint(loaded.terrain.get("height_tiles")) or \
			warp.destination_tile_x >= loaded.terrain.width_tiles or \
			warp.destination_tile_y >= loaded.terrain.height_tiles:
		_stop("MIF 传送目标缺失或落点越界：m%d；未替换地图或猜测落点。" % target)
		_refresh()
		return true
	# 原生在脚点矩形刚与传送格相交时就换图，不等走完这一格：
	# 记通行标志、把角色放到目标格中心并回到站立动作，跟随者随位置同步。
	story.progress.warpPassed[str(target)] = true
	hero.action = FieldAction.Hero.IDLE
	hero.erase("animationEndMode")
	_walk_tile = Vector2i(int(warp.destination_tile_x), int(warp.destination_tile_y))
	_clear_walk_input()
	# 换图成功：原生 `Map_warpProc:54` 无条件 `Game_msgInit(1, …)`，目标图就是当前图也弹。
	_map_name_source = MapNameView.Source.WARP
	story.after_move(loaded, {"x": int(warp.destination_tile_x),
		"y": int(warp.destination_tile_y)}, true)
	note = ""
	_drain_effects()
	_refresh()
	return true


## 新手剧情门槛的唯一判定：原生在 `ParamData.current_event_resource_id <= 2`（剧情还没推进到
## 3 号事件之后）时拒绝存档——`Field_Basic_mKeyPressed:62` 的 else 分支回 `common/msg.fxt` 38
## 「现在无法存档」、`Menu_Option_mKeyPressed:37-40` 回 198；`Evt_stdINIT` 那侧把事件号写进
## `ParamData`。本项目的事件号推进与原生不等价（见 `save_game` 的注释），所以等价条件是
## 「没有可写的稳定快照」：事件脚本、对话、战斗期间 `story.stable_state()` 为空。
## 稳定在地图上（没有脚本在跑、`cursor == 0`）时恒为 false，正常存档与飞艇登船不受影响；
## `story == null`（流程还没就绪）也算「未稳定」，这条判定只用于拒绝，不用于放行。
func story_unsettled() -> bool:
	return story == null or story.stable_state().is_empty()


## 原生成功提示为消息 200「存档完毕」，它是 Box2 的 `Menu_win_Box2_DrawOk` 确认框
## （`Field_Save_mPaint:19-21` 的第三段），不是提示栈消息。原生还要求
## `current_event_resource_id > 2` 才允许存档（`Field_Basic_mKeyPressed` 的 FIELD_STATE_SAVE 分支与
## `Menu_Option_mKeyPressed` 存档项），那道门在本项目换成了等价条件 `story_unsettled()`
## （稳定快照为空即拒绝），拒绝时回原生记录 198／38。
func save_game() -> int:
	if story == null:
		note = "当前流程不稳定，无法保存。"
		return ERR_BUSY
	if story_unsettled():
		# 原生 `Menu_Option_mKeyPressed:37-40`：层号不置 1、弹窗不开，只给一条提示栈消息 198。
		note = _assets.text_message(Msg.SOURCE, Msg.Id.OPTION_SAVE_UNAVAILABLE)
		return ERR_BUSY
	if not boundary.is_empty() or battle_view != null or \
			not _encounter.is_empty() or not narration.is_empty() or not mastery.is_empty() or \
			not _motions.is_empty() or not dialogue.is_empty():
		note = "当前流程不稳定，无法保存。"
		return ERR_BUSY
	var error := _commit_save()
	if error == ERR_BUSY:
		note = "仅在原触发条件等待的稳定场景保存；对话/脚本/战斗期间不可保存。"
	elif error == OK:
		# OPTION 页自己那张同一个确认框在跑时（`_note_stays_off_stack`）只把正文交回去，
		# 由菜单换成层 3；其余入口直接开野外存档页的确认框。
		if _note_stays_off_stack:
			note = _assets.text_message(Msg.SOURCE, Msg.Id.SAVE_DONE)
		else:
			_open_save_result(Msg.Id.SAVE_DONE)
	else:
		note = "保存失败：%s；原存档保留。" % error_string(error)
	_refresh()
	return error


## 写当前稳定快照到它自己的槽（原生 `Game_saveSAVE` 也是写当前槽，不选槽）。
## 不产生提示，由调用方决定怎么报结果。
func _commit_save() -> int:
	if _store == null or story == null:
		return ERR_UNAVAILABLE
	var state: Dictionary = story.stable_state()
	if state.is_empty():
		return ERR_BUSY
	return _store.save(int(state.slot), state)


## 原生 `Field_Basic_mKeyPressed`：HELP 键（-10）先过
## `ParamData.current_event_resource_id > 2` 才 `FieldCanvas_SetNext(FIELD_STATE_SAVE)`，
## 否则 `Game_infoInit` 报消息 38「现在无法存档」。本项目的事件号推进与原生不等价
## （见 `save_game`），同一道门换成 `story_unsettled()`，拒绝时不进页、只推那条 38。
func _open_save() -> void:
	if save_open or service_open() or story == null or not focused or menu_open or book_open or \
			battle_view != null or world_map_view != null or not _encounter.is_empty() or \
			not boundary.is_empty() or not dialogue.is_empty() or not narration.is_empty() or \
			not mastery.is_empty():
		return
	if story_unsettled():
		MessageStack.say_record(Msg.Id.FIELD_SAVE_UNAVAILABLE)
		return
	save_open = true
	_clear_walk_input()
	story.paused = true
	_save_view.open(_assets.text_messages(Msg.SOURCE), Msg.Id.FIELD_SAVE_IN_PROGRESS, true)
	_refresh()


func _save_page_requested() -> void:
	_save_view.finish_save(_commit_save() == OK)


## 菜单外的存档入口（脚本／调试直接调 `save_game()`）的成功收尾：原生
## `Field_Save_mPaint:19-21` 的第三段就是 `Menu_win_Box2_DrawOk`，所以开的也是野外存档页那一张
## 确认框，而不是往提示栈推一条「存档完毕」。
func _open_save_result(message_id: int) -> void:
	if save_open or story == null:
		return
	save_open = true
	_clear_walk_input()
	story.paused = true
	_save_view.open(_assets.text_messages(Msg.SOURCE), message_id, false)
	_refresh()


func _close_save() -> void:
	save_open = false
	_restore_field_pause()
	_refresh()


func _open_world_map() -> void:
	if world_map_view != null:
		_close_world_map()
		return
	# 野外任务详情页（`ServicePage.QUEST`）不走这里：它的世界地图是 `Qst_chtKeyPress` 的层 1，
	# 由 `field/quest_detail` 自己那扇 `menu/world_map` 窗承担（`service_open()` 会挡住本入口）。
	if story == null or menu_open or save_open or service_open() or battle_view != null or not _encounter.is_empty() or \
			not boundary.is_empty() or not dialogue.is_empty() or not focused:
		return
	var catalog: Node = get_node_or_null("/root/AssetCatalog")
	var data: Variant = catalog.call("load_world_map") \
		if catalog != null and catalog.has_method("load_world_map") else null
	if data == null:
		note = "世界地图节点表缺失；未打开世界地图。"
		_refresh()
		return
	world_map_view = WorldMapScene.instantiate()
	world_map_view.z_index = 250
	add_child(world_map_view)
	world_map_view.close_requested.connect(_close_world_map)
	if not world_map_view.open(catalog, data, int(story.map.get("id", -1)),
			story.progress.warpEnabled, story.progress.warpPassed):
		remove_child(world_map_view)
		world_map_view.queue_free()
		world_map_view = null
		return
	_clear_walk_input()
	if story != null:
		story.paused = true
	_refresh()


func _close_world_map() -> void:
	if world_map_view == null or world_map_view.closing():
		return
	# 关窗动画播完（`closed`）再释放，期间保持暂停，避免地图继续走。
	world_map_view.closed.connect(_free_world_map, CONNECT_ONE_SHOT)
	world_map_view.close()


func _free_world_map() -> void:
	if world_map_view == null:
		return
	remove_child(world_map_view)
	world_map_view.queue_free()
	world_map_view = null
	_restore_field_pause()
	_refresh()


## BOOK 入口（触控键 42，原生 `Game 18 图鉴`）：停在原地看图鉴，关窗后回到地图。
## `knowledge` 留空就显示存档里的获得记录；传 `Book.all_records()` 或自定义表可以只看／全看
## 指定收录范围（调试、剧情演出用），存档本身不变。
func show_book(knowledge: Dictionary = {}) -> bool:
	return _open_book(knowledge)


func _open_book(knowledge: Dictionary = {}) -> bool:
	if book_view != null:
		return false
	if story == null or menu_open or book_open or save_open or service_open() or battle_view != null or \
			world_map_view != null or \
			not _encounter.is_empty() or not boundary.is_empty() or not dialogue.is_empty() or \
			not focused or not _motions.is_empty():
		return false
	var catalog: GameplayData = null
	if _resources != null:
		catalog = _resources.call("load_gameplay")
	if catalog == null:
		note = "玩法数值目录缺失；未打开图鉴。"
		_refresh()
		return false
	book_view = BookScene.instantiate()
	book_view.z_index = 250
	add_child(book_view)
	book_view.closed.connect(_close_book)
	if not book_view.open(_assets, catalog, story.progress, knowledge):
		remove_child(book_view)
		book_view.queue_free()
		book_view = null
		note = "图鉴打不开：玩法数值目录缺失。"
		_refresh()
		return false
	book_open = true
	_clear_walk_input()
	story.paused = true
	_refresh()
	return true


func _close_book() -> void:
	if book_view == null:
		return
	remove_child(book_view)
	book_view.queue_free()
	book_view = null
	book_open = false
	_restore_field_pause()
	_refresh()


func _open_menu() -> void:
	if menu_view != null or not _encounter.is_empty() or book_view != null:
		return
	var catalog: GameplayData = null
	if _resources != null:
		catalog = _resources.call("load_gameplay")
	var quest: Variant = null
	if story != null and _resources != null and _resources.has_method("quest_label"):
		quest = _resources.call("quest_label", story.progress.quest)
	if not quest is String:
		quest = "【事件提示资源缺失或尚未接通；未替换任务文本】"
	menu_view = MenuScene.instantiate()
	menu_view.z_index = 250
	add_child(menu_view)
	menu_view.close_requested.connect(_close_menu)
	menu_view.title_requested.connect(_menu_title_requested)
	menu_view.shared_page_requested.connect(_menu_shared_page_requested)
	menu_view.save_requested.connect(_menu_save_requested)
	menu_view.progress_changed.connect(_menu_progress_changed)
	menu_view.settings_changed.connect(_menu_settings_changed)
	menu_view.touch_key_pressed.connect(_menu_touch_key_pressed)
	menu_view.mastery_change_requested.connect(_menu_mastery_change_requested)
	menu_view.option_save_blocked = story_unsettled()
	menu_view.bind(story.progress.duplicate(true) if story != null else {}, catalog, quest)
	menu_open = true
	menu_view.set_touch_key(_touch_key)
	if story != null:
		story.paused = true
	if catalog == null:
		_menu_notice("游戏数值目录缺失；菜单没有生成替代数值。")
	else:
		_menu_notice("")
	_refresh()


func _menu_title_requested() -> void:
	if focused and menu_open:
		title_requested.emit()


func _menu_shared_page_requested(page: int) -> void:
	if focused and menu_open:
		shared_page_requested.emit(page)


func _menu_touch_key_pressed(key: int) -> void:
	_touch_key = key


## 第 7 组 16 的页面：原生 `Ball_stdUse` 扣道具后 `SetNext(CHARACTER_SELECT_17)`，
## 选完回 FIELD；本工程复用初始流派页，只把结果写进 `preferredMastery`。
func _menu_mastery_change_requested() -> void:
	if not menu_open or menu_view == null or story == null:
		return
	_close_menu()
	_mastery_stage = Story.MasteryStage.MASTERY
	var parameter: Variant = story.progress.get("parameter")
	var choice := int(parameter.get("preferredMastery", 0)) \
		if parameter is Dictionary else 0
	if not _mastery_view.present(_mastery_names(Story.MASTERY_SPECIES), choice):
		_mastery_item_active = false
		_stop("原流派选择无法显示：%s" % _mastery_view.last_error)
		return
	_mastery_item_active = true
	story.paused = true
	_refresh()


func _close_menu() -> void:
	if menu_view != null:
		remove_child(menu_view)
		menu_view.queue_free()
		menu_view = null
	menu_open = false
	_restore_field_pause()
	_sync_actors()
	_refresh()


func _menu_notice(message: String) -> void:
	note = message
	if menu_view != null:
		menu_view.notice = message
		menu_view._render_content()
	_refresh()


func _menu_save_requested(_progress: Dictionary) -> void:
	if not focused or not menu_open:
		return
	# Never write the view's snapshot wholesale; the host owns the live checkpoint.
	# OPTION 页的存档反馈只有 Box2 弹窗（`Menu_Option_mPaint`），这里写盘产生的 note
	# 不进提示栈——原生 `Game_saveSAVE` 也不推消息。
	_note_stays_off_stack = true
	save_game()
	_menu_notice(note)
	_note_stays_off_stack = false


func _menu_settings_changed(settings: Dictionary, saved: bool) -> void:
	settings_changed.emit(settings.duplicate(true), saved)


## 菜单提交的进度变更必须在这里逐项对照校验：只接受「当前稳定状态下合法」的改动，
## 其余一律拒绝并提示用户，避免菜单写入伪造的进度或绕过原版限制。
func _menu_progress_changed(progress: Dictionary) -> void:
	if not menu_open or menu_view == null or story == null:
		return
	# 菜单声明的道具操作（用／合成／丢弃）：用活存档重放同一操作，结果必须逐字段等于提交快照。
	# 必须放在通用 parameter 差异之前：合成扣钱、经验窗口、能力点退回都会改 parameter。
	var operation: Dictionary = menu_view.take_progress_operation()
	if not operation.is_empty():
		# NET 购买：入包走 Story 的入手入口，效果流里的 item-obtained 才会推标准入手栈消息。
		if str(operation.get("kind", "")) == "network-buy":
			var bought: String = story.network_buy_item(int(operation.get("item_id", -1)),
				int(operation.get("count", 1)))
			if not bought.is_empty() or story.progress != progress or not focused or \
					not boundary.is_empty() or not dialogue.is_empty() or \
					not _motions.is_empty() or battle_view != null or \
					story.stable_state().is_empty() or \
					not Story.validate_progress(progress, int(story.progress.slot)):
				_reject_menu_progress()
				return
			_drain_effects()
			return
		var replay: Dictionary = MenuModel.replay_operation(story.progress,
			menu_view.gameplay_catalog, operation)
		var replayed: Variant = replay.get("progress")
		if not bool(replay.get("ok", false)) or not replayed is Dictionary or \
				replayed != progress or not focused or not boundary.is_empty() or \
				not dialogue.is_empty() or not _motions.is_empty() or battle_view != null or \
				story.stable_state().is_empty() or \
				not Story.validate_progress(replayed, int(story.progress.slot)):
			_reject_menu_progress()
			return
		story.progress = (replayed as Dictionary).duplicate(true)
		return
	if progress.get("parameter") != story.progress.get("parameter"):
		var status_change := MenuModel.status_allocation_change(story.progress, progress)
		if not status_change.get("ok", false) or not status_change.get("changed", false) or \
				not focused or not boundary.is_empty() or not dialogue.is_empty() or \
				not _motions.is_empty() or battle_view != null or \
				story.stable_state().is_empty() or \
				not Story.validate_progress(progress, int(story.progress.slot)):
			_reject_menu_progress()
			return
		story.progress = progress.duplicate(true)
		return
	var discarded := _menu_expected_discard_progress(progress)
	if not discarded.is_empty():
		if not focused or not boundary.is_empty() or not dialogue.is_empty() or \
				not _motions.is_empty() or battle_view != null or story.stable_state().is_empty() or \
				not Story.validate_progress(discarded, int(story.progress.slot)):
			_reject_menu_progress()
			return
		story.progress = discarded
		return
	if not _menu_party_order_valid(progress):
		_reject_menu_progress()
		return
	var candidate: Dictionary = story.progress.duplicate(true)
	var party_order: Variant = SaveData.party_order(progress)
	if party_order is Array:
		candidate["partyOrder"] = party_order.duplicate()
	else:
		candidate.erase("partyOrder")
	var menu_inventory: Variant = progress.get("inventory")
	var live_inventory: Variant = story.progress.get("inventory")
	var inventory_changes: Variant = _menu_inventory_changes(live_inventory, menu_inventory)
	if inventory_changes == null:
		_reject_menu_progress()
		return
	var has_inventory_change: bool = not inventory_changes.is_empty()
	if has_inventory_change and \
			inventory_changes.item_id >= ItemKind.id_of(ItemKind.Kind.CONSUMABLE, 0) and \
			inventory_changes.item_id < ItemKind.id_of(ItemKind.Kind.EQUIPMENT, 0):
		if inventory_changes.direction != 1:
			_reject_menu_progress()
			return
		candidate = _menu_expected_item_use(progress, inventory_changes.item_id)
		if candidate.is_empty():
			_reject_menu_progress()
			return
	else:
		var gear_changes: Variant = _menu_equipment_changes(SaveData.monsters(story.progress),
			SaveData.monsters(progress))
		if gear_changes == null or \
				not _menu_snapshot_matches_except_mutations(story.progress, progress):
			_reject_menu_progress()
			return
		var has_gear_change: bool = not gear_changes.member_indices.is_empty()
		if has_inventory_change != has_gear_change or \
				(has_inventory_change and
				(not gear_changes.has(inventory_changes.item_id) or
				gear_changes[inventory_changes.item_id] != inventory_changes.direction)):
			_reject_menu_progress()
			return
		if has_inventory_change:
			candidate["inventory"] = menu_inventory.duplicate(true)
		if has_gear_change:
			candidate["monsters"] = story.progress.monsters.duplicate(true)
			for member_index: int in gear_changes.member_indices:
				candidate.monsters[member_index]["nativeArguments"] = \
					progress.monsters[member_index]["nativeArguments"].duplicate()
	if not focused or not boundary.is_empty() or not dialogue.is_empty() or \
			not _motions.is_empty() or battle_view != null or story.stable_state().is_empty() or \
			not Story.validate_progress(candidate, int(story.progress.slot)):
		_reject_menu_progress()
		return
	story.progress = candidate


func _menu_expected_discard_progress(proposed: Dictionary) -> Dictionary:
	var before: Variant = SaveData.monsters(story.progress)
	var after: Variant = SaveData.monsters(proposed)
	if not before is Array or not after is Array or before.size() != after.size() + 1:
		return {}
	for index in range(before.size()):
		var candidate: Dictionary = story.progress.duplicate(true)
		if MenuModel.discard_party_member(candidate, index).ok and candidate == proposed:
			return candidate
	return {}


func _menu_party_order_valid(proposed: Dictionary) -> bool:
	if proposed.has("partyOrder") and not proposed.partyOrder is Array:
		return false
	var before := MenuModel.native_party_order(story.progress)
	var after := MenuModel.native_party_order(proposed)
	if before.size() == after.size():
		return before.all(func(index: Variant) -> bool: return after.has(index))
	if after.size() == before.size() + 1 and after.slice(0, before.size()) == before:
		if not after.back() is int:
			return false
		var admitted: Dictionary = story.progress.duplicate(true)
		return MenuModel.join_party(admitted, menu_view.gameplay_catalog, after.back()).ok and \
			MenuModel.native_party_order(admitted) == after
	if after.size() != before.size() - 1:
		return false
	for index: Variant in before:
		var remaining := before.duplicate()
		remaining.erase(index)
		if remaining == after:
			return true
	return false


func _menu_expected_item_use(proposed: Dictionary, item_id: int) -> Dictionary:
	var monsters: Variant = SaveData.monsters(story.progress)
	for member_index in range(monsters.size() if monsters is Array else 0):
		var candidate: Dictionary = story.progress.duplicate(true)
		var result := MenuModel.use_item(candidate, menu_view.gameplay_catalog,
			item_id, member_index)
		if result.get("ok", false) and candidate == proposed:
			return candidate
	return {}


func _menu_snapshot_matches_except_mutations(live: Dictionary, proposed: Dictionary) -> bool:
	var expected := live.duplicate(true)
	var actual := proposed.duplicate(true)
	for state: Dictionary in [expected, actual]:
		state.erase("partyOrder")
		state.erase("inventory")
		state.erase("monsters")
	if expected != actual:
		return false
	var live_monsters: Variant = SaveData.monsters(live)
	var proposed_monsters: Variant = SaveData.monsters(proposed)
	if not live_monsters is Array or not proposed_monsters is Array or \
			live_monsters.size() != proposed_monsters.size():
		return false
	for index in range(live_monsters.size()):
		if not live_monsters[index] is Dictionary or not proposed_monsters[index] is Dictionary:
			return false
		var before: Dictionary = live_monsters[index].duplicate(true)
		var after: Dictionary = proposed_monsters[index].duplicate(true)
		before.erase("nativeArguments")
		after.erase("nativeArguments")
		if before != after:
			return false
	return true


func _menu_inventory_counts(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var counts := {}
	for key: Variant in value:
		if not key is String or not key.is_valid_int() or key.length() > 9 or \
				not value[key] is int or value[key] < 0:
			return null
		var canonical := str(int(key))
		if counts.has(canonical):
			return null
		counts[canonical] = value[key]
	return counts


func _menu_inventory_changes(before: Variant, after: Variant) -> Variant:
	var old_counts: Variant = _menu_inventory_counts(before)
	var new_counts: Variant = _menu_inventory_counts(after)
	if old_counts == null or new_counts == null:
		return null
	var changed_id := -1
	var direction := 0
	var ids: Dictionary = {}
	for key: String in old_counts:
		ids[key] = true
	for key: String in new_counts:
		ids[key] = true
	for key: String in ids:
		var old_count: int = old_counts.get(key, 0)
		var new_count: int = new_counts.get(key, 0)
		if old_count == new_count:
			continue
		var item_id := int(key)
		if item_id < ItemKind.id_of(ItemKind.Kind.CONSUMABLE, 0) or \
				item_id >= ItemKind.id_of(ItemKind.Kind.MATERIAL, 0) or \
				absi(new_count - old_count) != 1 or changed_id >= 0:
			return null
		changed_id = item_id
		direction = 1 if new_count < old_count else -1
	if changed_id < 0:
		return {}
	return {"item_id": changed_id, "direction": direction}


func _menu_equipment_changes(before: Variant, after: Variant) -> Variant:
	if not before is Array or not after is Array or before.size() != after.size():
		return null
	var item_directions := {}
	var changed_members: Array[int] = []
	for member_index in range(before.size()):
		var old_member: Variant = before[member_index]
		var new_member: Variant = after[member_index]
		if not old_member is Dictionary or not new_member is Dictionary:
			return null
		var old_member_fields: Dictionary = old_member.duplicate(true)
		var new_member_fields: Dictionary = new_member.duplicate(true)
		var old_args: Variant = old_member_fields.get("nativeArguments")
		var new_args: Variant = new_member_fields.get("nativeArguments")
		old_member_fields.erase("nativeArguments")
		new_member_fields.erase("nativeArguments")
		if old_member_fields != new_member_fields:
			return null
		if old_args == new_args:
			continue
		if not old_args is Array or not new_args is Array or old_args.size() != 5 or \
				new_args.size() != 5 or not old_args.all(
				func(value: Variant) -> bool: return value is int) or \
				not new_args.all(func(value: Variant) -> bool: return value is int):
			return null
		for argument_index in range(5):
			if argument_index != 3 and old_args[argument_index] != new_args[argument_index]:
				return null
		var old_index: int = old_args[3]
		var new_index: int = new_args[3]
		if old_index == new_index or (old_index != -1 and new_index != -1):
			return null
		var item_id := ItemKind.id_of(ItemKind.Kind.EQUIPMENT,
			new_index if old_index == -1 else old_index)
		if item_id < ItemKind.id_of(ItemKind.Kind.EQUIPMENT, 0) or \
				item_id >= ItemKind.id_of(ItemKind.Kind.MATERIAL, 0) or \
				item_directions.has(item_id):
			return null
		item_directions[item_id] = 1 if old_index == -1 else -1
		changed_members.append(member_index)
	if item_directions.size() > 1:
		return null
	if item_directions.is_empty():
		return {"member_indices": []}
	var item_id: int = item_directions.keys()[0]
	return {"member_indices": changed_members, item_id: item_directions[item_id]}


func _reject_menu_progress() -> void:
	menu_view.bind(story.progress.duplicate(true), menu_view.gameplay_catalog,
		menu_view.text_resource)
	_menu_notice("当前流程不稳定或菜单变更无效；没有改变原流程记录。")


## 原生 `Evt_stdPROC` case 0x21：先把现场抓成一帧（`Field_Basic_Capture` 的 50% 黑 + 3×3 模糊），
## 播完 `Game_Ready_Battle` 的 15 帧后才 `GameCanvas_SetNext(GAME_STATE_GUILD_BATTLE_6, p0)`。
## 所以剧情战也要走和野外接触相同的「战斗准备 → Battle_Ready 淡出」转场，不能直接盖上战斗界面。
## `id == -2` 是已经播过转场或自己负责进场的两条路（野外接触、公会挑战）。
func _open_battle(id: int) -> void:
	if id != -2:
		if _encounter.is_empty():
			_begin_battle_transition(id)
		return
	_create_battle_view(id)


## 剧情战的 `Field_Basic_Capture` 起点：先抓一帧现场，再建转场层。
func _begin_battle_transition(id: int) -> void:
	_battle_id = id
	_encounter = {"stage": "capture", "battle_id": id}
	_clear_walk_input()
	_sync_actors()
	_refresh()
	call_deferred("_capture_battle_transition")


func _capture_battle_transition() -> void:
	if _encounter.get("stage") != "capture":
		return
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _encounter.get("stage") != "capture":
		return
	_encounter.stage = "transition"
	_create_encounter_view()
	encounter_view.present(get_viewport().get_texture().get_image(),
		_world.position + _point(_actor(0)))


func _create_battle_view(id: int) -> void:
	_battle_id = id
	# 敌方 3 只在开战前补进预读队列并一次读完；队内 3 只已由 `start_slot` 排过。
	# `battle_view.start()` 的 `_load_action` 对没读过的物种要同步 `load()` ANI 场景
	# （冷缓存 12～15 ms／只，见 `wiki\battle\battle-performance-notes.md`）。
	if story != null and story.combat != null:
		_queue_battle_animations(story.combat.balls)
		_flush_battle_warmup()
	battle_view = BattleScene.instantiate()
	battle_view.z_index = 300
	# 原生 `Evt_stdSET(3, 物种)`：事件等待触发器 3 时，击杀对应物种会掉它的条件物品。
	battle_view.event_drop = story.event_drop_for
	add_child(battle_view)
	BigScenes.enter_battle(battle_view)
	# `BigScenes` 收野外画布时会把同级的转场层一起藏掉；转场层还要播 `Battle_Ready`
	# 那 5 帧黑幕淡出，所以在它上面重新打开（z 320 仍高于战斗界面）。
	if encounter_view != null:
		encounter_view.visible = true
	battle_view.completed.connect(_battle_completed)
	battle_view.abandoned.connect(_battle_abandoned)
	battle_view.title_requested.connect(_battle_title_requested)
	battle_view.settlement_drops.connect(_battle_settlement_drops)
	# 原生战斗态一套 `height − 51`（`0x788B` 掩码外的状态）；在 `start()` 之前切，战斗内第一条提示就落在基线。
	battle_view.start(story.combat, _resources, _assets, story.progress)


func _battle_completed(outcome: Dictionary) -> void:
	if story.combat == null or story.combat.result == null:
		_stop("战斗尚未产生真实终局；未释放原战斗门。")
		return
	if _battle_id == -2:
		var order: Array = MenuModel.native_party_order(story.progress)
		for slot in order.size():
			var ball: Dictionary = story.combat.balls[3 + slot]
			story.progress.monsters[order[slot]].hp = int(ball.hp)
			story.progress.monsters[order[slot]].sp = int(ball.sp)
			story.progress.monsters[order[slot]].feel = int(ball.get("feel", 0))
			story.progress.monsters[order[slot]].food = int(ball.get("food", ItemEffect.FOOD_MAX))
		if story.combat.result == "lost":
			# 原生状态 28 DIE → `Battle_Die_mRun` 的确认段调用 Game_out()，
			# 非联网战斗走 `EFC_mainSetNEXT(CANVAS_PRIME, 10)`：直接回标题，不回到地图。
			# 这一场用掉的复活道具仍然要扣（`Battle_Die_Revival` 之前就 `Item_stdDel` 了）。
			_apply_used_items(outcome)
			_back_to_title()
			return
		_apply_captures(outcome)
		_apply_settlement(outcome)
		# 原生 `Battle_Win_mRun` 只对 `kind == 3` 结算名次（`guild_code > 1` 时自减）。
		if guild_battle_kind != 0:
			var ranked := GuildBattle.apply_win(story.progress, guild_battle_kind)
			if not bool(ranked.get("ok", false)):
				note = "公会名次未能写回：%s" % str(ranked.get("error", ""))
		guild_battle_kind = 0
		_return_from_wild_battle()
		return
	_close_battle()
	_apply_used_items(outcome)
	# 剧情战收尾兜底：转场层若还在先拆掉，再清 `_encounter`、交回暂停，
	# `story.complete_battle()` 里的 `pump()` 才能继续战后事件。
	if encounter_view != null:
		remove_child(encounter_view)
		encounter_view.queue_free()
		encounter_view = null
	_encounter.clear()
	_restore_field_pause()
	story.complete_battle(_battle_id, outcome.get("settlement"))
	_drain_effects()
	# `game-over`（原事件战败北：`Game_out()`）已经把 `story.combat` 置空并回了标题，没有场景可刷。
	if story.combat != null:
		_refresh()


## 原生 `Game_out()`：非联网战斗的两条路（败北、系统菜单主菜单「是」）都回标题
## （`EFC_mainSetNEXT(CANVAS_PRIME, PRIME_STATE_TITLE)`），不返回地图、不结算、不发奖励；
## 存档文件没有被写过，读档即可回到战前。
func _back_to_title() -> void:
	_close_battle()
	story.combat = null
	story.paused = true
	_encounter.clear()
	_battle_id = -1
	_clear_walk_input()
	title_requested.emit()


## 战斗内用掉的背包物品（捕获球、复活道具）在离开战斗时一次性落实（原生是在战斗里
## `Item_stdDel(item, 1, 1)` 使用时直接写回，本工程由战斗视图记进 outcome 的 `items`）。
func _apply_used_items(outcome: Dictionary) -> void:
	var used: Variant = outcome.get("items")
	if not used is Dictionary:
		return
	for key: Variant in used:
		if not story.consume_item(int(key), int(used[key])):
			note = "道具数量与背包记录不一致；未扣除 %s。" % str(key)


## 捕获与捕获球的消耗：捕获只在野外战开放，入包记录同样来自 outcome。
## 入包提示（fxt478）已在捕获演出第 21 帧由 `battle_view._say_monster_obtained` 推过，
## 跟原生 `Ball_stdAddEx` 同一刻，这里不再重复推一条。
func _apply_captures(outcome: Dictionary) -> void:
	_apply_used_items(outcome)
	var captures: Variant = outcome.get("captures")
	if not captures is Array:
		return
	for record: Dictionary in captures:
		var failure: String = story.capture_monster(record)
		if not failure.is_empty():
			note = failure
			continue


## 原生胜利结算（`Battle_Win_SetResult`）在战斗内就写回了能力值、金币与背包；
## 本工程由战斗视图算好（`BattleSettlement`），这里在离开战斗时一次性写回进度。
func _apply_settlement(outcome: Dictionary) -> void:
	var settlement: Variant = outcome.get("settlement")
	if settlement == null or story == null or story.progress.is_empty():
		return
	# 掉落走故事层唯一的背包规则（原生 `Item_stdAddEx`），入包提示与任务进度在本结算内进栈。
	var report: Dictionary = story.apply_battle_settlement(settlement)
	_drain_effects()
	var full: Array = report.get("full", [])
	if not full.is_empty():
		note = "背包已满：%d 件道具未入包" % full.size()


## 原生 `Battle_Win_mRun@0x322F0:179-191` 的子状态 2：经验与金币发完、结算窗口还开着，
## 这时才逐件 `Item_stdAddEx`——掉落入包并各推一条 fxt416 入手提示。
## 确认离开战斗时只写回其余结算（`_apply_settlement`／`story.complete_battle`），不会重复入包。
func _battle_settlement_drops(settlement: RefCounted) -> void:
	if settlement == null or story == null or story.progress.is_empty():
		return
	var report: Dictionary = story.apply_battle_drops(settlement)
	_drain_effects()
	var full: Array = report.get("full", [])
	if not full.is_empty():
		note = "背包已满：%d 件道具未入包" % full.size()


## 逃跑／放弃／逃生战边界：回野外地图。`outcome` 里是战斗视图交出的本战已用道具与已捕获
## 个体——原生在战斗内使用时就已经 `Item_stdDel`／`Item_stdDels` 写回、捕获成功第 21 帧就
## `Ball_stdAddEx` 入包，所以每条离开战斗的结局都要先兑现再收尾。
func _battle_abandoned(outcome: Dictionary) -> void:
	_apply_captures(outcome)
	if _battle_id == -2:
		note = "本战资料未完整还原，已返回地图；未结算、未改变队员数值。"
		_return_from_wild_battle()
		return
	_stop("原战斗视图到达未迁移边界；未跳过战斗或发放奖励。")
	_close_battle()
	_refresh()


## 系统菜单主菜单的「是」：原生 `Battle_MainMenu_mRun` 返回码 1 → `Game_out()` →
## `EFC_mainSetNEXT(CANVAS_PRIME, PRIME_STATE_TITLE)`。与「逃跑／放弃」（`_battle_abandoned` 回地图）
## 不同，这条不回地图、不结算、不写存档，直接交给启动层回标题（`wiki\battle\battle-exit.md`）。
## `items`／`captures` 与 `abandoned` 同形（原生在战斗内使用时就已经 `Item_stdDel` 写回、
## 捕获成功第 21 帧就已入包），先兑现再走。
func _battle_title_requested(outcome: Dictionary) -> void:
	_apply_captures(outcome)
	_back_to_title()


func _return_from_wild_battle() -> void:
	_close_battle()
	# 战斗阵亡写回的是 0 HP；回野外画布（原生 `FieldCanvas_load`）时恢复成 1 HP。
	story.restore_downed_monsters()
	story.combat = null
	_encounter.clear()
	_battle_id = -1
	_restore_field_pause()
	_clear_walk_input()
	music_requested.emit(int(story.progress.get("music", 0)))
	_refresh()


func _close_battle() -> void:
	if battle_view != null:
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	BigScenes.enter_field(self)



func set_focused(value: bool) -> void:
	focused = value
	_actors.set_monster_running(value and not menu_open and not book_open and not save_open and not service_open() and
		boundary.is_empty() and battle_view == null and _encounter.is_empty() and
		not dialogue.get("ordinary", false))
	if not value:
		handle_touch(Vector2.ZERO, "up")
		_clear_walk_input()
	if story != null:
		story.paused = _field_paused()
	if encounter_view != null:
		encounter_view.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if battle_view != null:
		battle_view.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if menu_view != null:
		menu_view.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if book_view != null:
		book_view.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED


## 把物理按键分派给当前持有输入的视图：战斗 → 菜单 → 对话 → 地图。
## 切页不等于松开，按键释放由 Main 统一处理。
func press(key: int) -> void:
	if not focused or (not _encounter.is_empty() and _encounter.stage != "battle"):
		return
	if service_page != ServicePage.NONE:
		# `FieldCanvas_mKeyPressed` 只把按键交给当前页的 `key_pressed_callback_address`：
		# 按 `SERVICE_PAGES` 取该页的按键映射与当前视图（子页优先），该页不认的键直接丢弃。
		# 各页原生出处：公会 `Field_Guild_List_mKeyPressed`／
		# `Field_Guild_Info_Detail_mKeyPressed`、商店 `Field_Item_List_mKeyPressed`／
		# `Field_Item_Buy_mKeyPressed`／`Field_Item_Sell_mKeyPressed`、任务 `Qst_chtKeyPress`／
		# `Battle_Win_mKeyPressed`、旅店 `Field_Inn_mKeyPressed`、飞艇
		# `Field_Warp1_mKeyPressed`／`Field_Warp2_mKeyPressed`、精灵
		# `Game_Monster_List_mKeyPressed`／`Game_Monster_Mix_mKeyPressed`／
		# `Game_Monster_Enchant_mKeyPressed`。
		var route: Dictionary = SERVICE_PAGES[service_page]
		var key_name := str(route.key_map.get(key, ""))
		var page: Control = _service_page_view(service_page)
		if page != null and not key_name.is_empty():
			page.call("handle_key", key_name)
		return
	if save_open:
		# 原生 `Field_Save_mKeyPressed`：只有确认（-5）与返回（-16）在第三段生效。
		var save_keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
			KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace"}
		if save_keys.has(key):
			_save_view.press(save_keys[key])
		return
	if not narration.is_empty():
		# 原生 `Evt_stdKEY:51-55`：字幕步骤只接受键码 35（确定），其它键一律吞掉、不推进；
		# 确定键直接置 `+10` = 1，下一帧 `Evt_stdPROC:168-171` 调 `Evt_scrFINAL` 清场并结束整条指令。
		if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_narration_view.finish()
			_advance_narration()
			_refresh()
		return
	if _mastery_item_active or not mastery.is_empty():
		if _starter_active():
			# 状态 16 是图鉴页实例：四方向、OK 与 CLR 都在页内按 `Game_Book_Monster_mKeyPressed`
			# 分派（含确认框的翻项与关框）。
			var starter_keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
				KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft",
				KEY_RIGHT: "ArrowRight", KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace"}
			if starter_keys.has(key):
				_starter_view.handle_key(starter_keys[key])
		else:
			match key:
				KEY_LEFT:
					_mastery_view.move(-1)
				KEY_RIGHT:
					_mastery_view.move(1)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					submit_mastery()
		_refresh()
		return
	if world_map_view != null:
		# 原生 Field_MiniMap_mKeyPressed 把按键交给 Map_worldKEY，-16／35 退出；方向键平移。
		var map_keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
			KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp",
			KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace"}
		if map_keys.has(key):
			world_map_view.handle_key(map_keys[key])
		return
	if battle_view != null:
		var keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
			KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp",
			KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape"}
		if keys.has(key):
			battle_view.press(keys[key])
		return
	if book_view != null:
		var book_keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
			KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp",
			KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace"}
		if book_keys.has(key):
			book_view.press(book_keys[key])
		return
	if menu_open:
		var keys := {KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_SPACE: "Space",
			KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp",
			KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape", KEY_BACKSPACE: "Backspace"}
		if keys.has(key):
			menu_view.press(keys[key])
	elif key == KEY_ESCAPE:
		_open_menu()
	elif not boundary.is_empty():
		return
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if dialogue.is_empty():
			interact_npc()
		else:
			confirm_dialogue()
	else:
		if DIRECTION_KEYS.has(key):
			_start_manual_walk(DIRECTION_KEYS[key])
	_refresh()


## 把模型状态同步到视图；只在真正需要时重建，不改动编辑器里的固定布局。
func _refresh() -> void:
	if _chat_view == null:
		return
	# 头顶与小地图的任务图标都读 actor 上的 `quest_status`（原生 `Qst_icoSET` 在任务页确认、
	# 事件推进、计数达标时刷新），所以每次刷新界面状态都重算一次。
	_sync_quest_icons()
	var style := _field_touch_style()
	_touch_view.present(_field_touch_style(true), _touch_key)
	_hero_summary.visible = style != 0
	_sync_exp_bonus_hud(style)
	_minimap.visible = style != 0 and world_map_view == null
	if style != 0:
		_hero_summary.present(story.progress.parameter)
		_minimap.present(story.progress.actors, story.progress.warpEnabled,
			_world.position + _point(_actor(0)))
	if style == 0:
		_clear_walk_input()
	_chat_view.visible = not menu_open and not book_open and not save_open and not service_open() and \
		boundary.is_empty() and \
		not dialogue.is_empty()
	if not boundary.is_empty():
		_actors.set_dialogue_speaker(-1)
	elif not dialogue.is_empty():
		var record: Dictionary = dialogue.records[dialogue_index]
		_actors.set_dialogue_speaker(int(record.get("portrait_id", 999)))
		_chat_view.present_record(record, _speaker_name(int(record.get("portrait_id", 999))),
			dialogue_index)
	else:
		_actors.set_dialogue_speaker(-1)
		_chat_view.clear_dialogue()


## 字幕结束（`Evt_scrFINAL`）后事件才继续下一条记录：自然放完与确定键两条路都先把视图置 `finished()`，
## `Evt_stdPROC:168-171` 只在 `+10 = 1` 时才调 `Evt_scrFINAL` 清场。
func _advance_narration() -> void:
	if narration.is_empty() or not _narration_view.finished():
		return
	var id := int(narration.get("id", -1))
	narration = {}
	_narration_view.clear()
	if not story.complete_effect(id):
		_stop("原叙事字幕结束未能完成对应剧情门；未推进后续记录。")
	_drain_effects()
	_refresh()


## 流派／初始精灵选择的提交入口：宿主的键盘确定（`press()` 的 OK 分支）与两个确认框的触控「是」
## （`mastery_view._choose`／`book_monster._choose`，原生 `Menu_win_Box2_DrawSelect:90` 的 −5）
## 都走这里，视图不再直调私有实现。一级确认框收拢期间（已选「否」）不提交。
func submit_mastery() -> void:
	if _mastery_item_active:
		_submit_mastery_item()
		return
	if not _starter_active() and _mastery_view != null and _mastery_view.confirm_closing():
		return
	_complete_mastery()


## 第 7 组 16 的确认：页面已由 `_menu_mastery_change_requested` 打开，道具在菜单侧已扣。
## 原生 `Game_Character_Select_mKeyPressed:64-65` 选完回 FIELD；这里只落 `preferredMastery`。
func _submit_mastery_item() -> void:
	var index: int = _mastery_view.selected()
	var parameter: Variant = story.progress.get("parameter") if story != null else null
	if index < 0 or index >= Story.MASTERY_SPECIES.size() or not parameter is Dictionary:
		_stop("流派选择结果无法写回存档参数")
		return
	parameter["preferredMastery"] = index
	_mastery_item_active = false
	_mastery_view.clear()
	_restore_field_pause()
	_refresh()


## 选择确认：一级把流派写进 `progress.parameter.preferredMastery` 后换发二级页的同一条事件门
## （原生 `GameCanvas_SetNext(GAME_STATE_BOOK_MONSTER_16, 流派)`，窗由新页自己开）；
## 二级把选中的那只连同两只同伴入队后放行事件。
func _complete_mastery() -> void:
	if mastery.is_empty():
		return
	var id := int(mastery.get("id", -1))
	# 二极页的光标是 24 格里的一格，`complete_mastery` 要的是五只候选里的序号。
	var index: int = _starter_view.starter_choice() if _starter_active() else _mastery_view.selected()
	if index < 0:
		return
	mastery = {}
	if not story.complete_mastery(id, index):
		_clear_mastery_pages()
		_stop("原流派选择结果未能写回事件门。")
		_refresh()
		return
	_drain_effects()
	if mastery.is_empty():
		_clear_mastery_pages()
	_refresh()


## 状态 16 的 CLR（`Game_Book_Monster_mKeyPressed:128-132`）：回 `CHARACTER_SELECT_15`，
## 光标停在 `preferred_mastery_index`。原生是新状态自己开窗，所以一级页重播开窗动画。
func _return_starter() -> void:
	if mastery.is_empty() or not story.return_mastery():
		return
	_starter_view.clear()
	_mastery_stage = Story.MasteryStage.MASTERY
	if not _mastery_view.present(_mastery_names(Story.MASTERY_SPECIES),
			int(story.progress["parameter"].get("preferredMastery", 0))):
		mastery = {}
		_stop("原流派选择无法显示：%s" % _mastery_view.last_error)
	_refresh()


func _starter_active() -> bool:
	return not mastery.is_empty() and _mastery_stage == Story.MasteryStage.STARTER


## 状态 16：图鉴页的初始精灵形态（`Game_Book_Monster_init:12-35`）。候选物种在数值表里查不到时
## 返回 false——原生这时也画不出格内精灵。
func _present_starter(effect: Dictionary, catalog: GameplayData) -> bool:
	for entry: Variant in effect.species:
		if catalog.monster(int(entry)) == null:
			return false
	_starter_view.present_starter(_assets, catalog, int(effect.get("mastery", 0)), effect.species)
	return true


## 两级页都收起（事件门结束或提交失败）：原生换回 FIELD 时两级窗口都不再画。
func _clear_mastery_pages() -> void:
	_mastery_item_active = false
	_mastery_view.clear()
	_starter_view.clear()


## 图鉴页要的数值表：与其它页同一条 `resources.load_gameplay()`。
func _gameplay_catalog() -> GameplayData:
	if _resources == null or not _resources.has_method("load_gameplay"):
		return null
	var catalog: Variant = _resources.call("load_gameplay")
	return catalog if catalog is GameplayData else null


## 原生 `item_mon.group.<物种>.name`（`common/item_mon.dat`）。
func _mastery_names(species: Array) -> Array[String]:
	var messages: Dictionary = _assets.text_messages("common/item_mon.dat")
	var names: Array[String] = []
	for id: Variant in species:
		var text: Variant = messages.get("item_mon.group.%d.name" % int(id), "")
		names.append(str(text) if text is String else "")
	return names


## 原生 opcode 34：Evt_stdINIT 之后同一帧 Game_saveSAVE()。
func _save_from_event() -> void:
	if _store == null:
		push_warning("原指令 34 的自动存档没有可用存档槽；未写入替代存档。")
		return
	var state: Dictionary = story.stable_state()
	if state.is_empty():
		state = story.progress.duplicate(true)
	var error: int = _store.save(int(state.get("slot", 0)), state)
	if error != OK:
		note = "原指令 34 的自动存档失败：%s；原存档保留。" % error_string(error)


func _speaker_name(portrait: int) -> String:
	if portrait < 0 or story == null or not story.map.get("info") is Dictionary:
		return "???"
	var bindings: Variant = story.map.info.get("npc_bindings", [])
	if not bindings is Array or portrait >= bindings.size():
		return "???"
	var binding: Variant = bindings[portrait]
	if not binding is Dictionary:
		return "???"
	var name: Variant = binding.get("name_text")
	return name if name is String and not name.is_empty() else "???"


func _exit_tree() -> void:
	if story != null:
		story.dispose()
