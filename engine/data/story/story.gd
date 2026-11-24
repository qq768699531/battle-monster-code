extends RefCounted
class_name StoryRuntime

## Original native-chain event model, independent of scenes and persistence.
## Provider: synchronous load_map/load_event/load_dialogue/load_gameplay methods
## returning Dictionaries or Resources with Dictionary metadata named "payload".
## Drain effects after initialize/advance. Acknowledge dialogue and move effects
## with complete_effect(id); camera pans with complete_camera(id); battle effects
## with complete_battle(id).
## Call advance(_process delta in seconds). Paused/external waits accrue no time.
const Battle = preload("res://game/battle/combat/combat/battle.gd")
const BattleSettlementModel = preload("res://game/battle/combat/battle_settlement/battle_settlement.gd")
const Book = preload("res://game/menu/book/book_model/book_model.gd")
const MapEffectCatalog = preload("res://game/field/map/map/map_effect.gd")
const MonsterAttribute = preload("res://game/growth/monster_attribute/monster_attribute.gd")
const QuestLogModel = preload("res://game/field/quests/quest_log/quest_log.gd")
## 事件记录的等待、淡入淡出、闪光与抖动都按帧计数（`Evt_stdPROC` 的 `step_count`），
## 折成秒一律乘 `FramePacing.NATIVE_FRAME_SECONDS`（原生默认档 50 ms/帧，
## `EFC_thrInitialize:14` → `EFC_thrSPEED(4)` → 50 ms；`EFC_thrPLAY:3-5`）。
const STANDARD_PROGRESS_POINTS_MAX := 99000
## 经验 +20% 的剩余窗口毫秒数（`ParamData.standard_progress + 7`，随存档保存的运行时字段）。
## 道具 `Ball_stdUse:1060-1070` 写 3600000（1 小时），`GameCanvas_mPaint:29-40` 逐帧递减，
## 两处结算（`Battle_Win_SetResult:180`／`Field_Quest_Complete_SetResult:40`）在 `> 0` 时加成。
const EXP_BONUS_KEY := "exp_bonus_milliseconds"
const EXP_BONUS_MILLISECONDS := 3600000
## 加成口径：`Battle_Win_SetResult:181` 的 `n20 = 20`（百分比）与
## `Field_Quest_Complete_SetResult:41` 的 `v2 += v2 / 5` 是同一个 +20%，整数除法都是除以 5。
const EXP_BONUS_PERCENT := 20
const EXP_BONUS_DIVISOR := 5
## 存档校验上限：`validate_progress` 用 `_uint(parameter["moneyBalance"], MONEY_MAX)` 判钱；
## 加钱一律夹到这个上限（原生 `Param_moneySET` 的饱和值）。
const MONEY_MAX := 999999999

## 原生事件记录第一个字段的 opcode（`Evt_stdPROC` 的动作号）。触发条件（`_trigger`）与
## 指令（`_instruction`）共用同一个数值空间：0–9 既是首记录的触发条件，也是可执行指令。
## 名字取自反编译分支的实际行为；未接通的分支仍按数值报错。
enum Op {
	NONE = 0,
	JUMP = 1,
	FADE = 2,
	SCREEN_EFFECT = 3,
	NARRATION = 4,
	## `Evt_stdPROC:173-176`：`p[0]` 写进 `MapData.reserved_0x152[0]` 后 `Map_eftReset(1)`，
	## 该字节由 `Evt_eftSET` 读成 1 灰／2 暗滤镜。同一数值当首记录时是 `Trigger.RECT`
	## （`Evt_stdIsPROC:44-57` 判玩家在矩形里），两个名字不是一回事。
	MAP_FILTER = 5,
	FREE_RESOURCE = 6,
	PLACE_ACTOR = 7,
	REMOVE_ACTOR = 8,
	MOVE_ACTOR = 9,
	ACTOR_ANIMATION = 10,
	RELOAD_MAP = 11,
	CLEAR_ACTORS = 12,
	WARP_ENABLE = 13,
	LOAD_MAP = 14,
	## `Evt_stdPROC:306-325`：`p[0]` 帧优先，其次累计毫秒到 `1000 * p[1]`；
	## 等待期间的整屏填充见 `Evt_stdPAINT2:21-33`（`p[2]` 走 `WaitCover`）。
	WAIT = 15,
	WAIT_ANIMATIONS = 16,
	## `Evt_stdPROC:422-427`：`Item_stdAddEx(组 = p[0] / 1000, 号 = p[0] % 1000, 数量 = p[1])`；
	## 这一步不吞按键（`Evt_stdKEY:47-48` 原样放行）。
	ADD_ITEM = 17,
	REMOVE_ITEM = 18,
	CAMERA = 19,
	DIALOGUE = 20,
	SET_QUEST = 21,
	PAUSE_OBJECTS = 22,
	EMOTION = 23,
	MUSIC = 24,
	REFRESH = 25,
	EVENT_OBJECTS = 26,
	MOVE_RECTS = 27,
	NPC_RECORDS = 28,
	HEAL_PARTY = 29,
	INIT_PARAMETERS = 30,
	ADD_MONSTER = 31,
	## `Evt_stdPROC:1085-1104`：`Field_Basic_Capture()` + `GameCanvas_SetNext(GAME_STATE_CHARACTER_SELECT_15)`，
	## 回到野外后推进一步；`EFC_mainTouchSTYLE:375-380` 在等待期间只放行键码 35。
	MASTERY_SELECT = 32,
	## `Evt_stdPROC:1105-1108`：`Field_Basic_Capture()` + `GameCanvas_SetNext(GAME_STATE_GUILD_BATTLE_6, p[0])`。
	BATTLE = 33,
	## `Evt_stdPROC:1109-1123`：进 `GAME_STATE_HEROINE_SELECT`，回来按 `EvtData+13` 选 `p[1]`（选了）
	## 或 `p[0]`，再 `Game_saveSAVE()`；本移植没有 heroine 数据，只走 `p[0]`。
	JUMP_AND_SAVE = 34,
}

## `Evt_stdPAINT2:21-33`：等待（`Op.WAIT`）期间的整屏填充色，取自记录第三个参数
## （`EvtData.match_parameter`）。1 填黑、2 填白，0 与其它值不填。
enum WaitCover {
	NONE = 0,
	BLACK = 1,
	WHITE = 2,
}

## 原生 `ObjectAnimationEndModeType`：opcode 10 的 `p[2]` 被原样写进对象 `animation_end_mode`
## （`Evt_stdPROC` case 0xA），末帧由 `Object_procNEXT` 消费——1 重播、2 停末帧，
## 0 交给该 resource 的 next 回调（剧情动作在回调里同样重播）。
enum AnimationEndMode {
	CALLBACK_OR_RESTART = 0,
	RESTART = 1,
	HOLD_LAST_FRAME = 2,
}

## 初始精灵选择的两级（原生 `GAME_STATE_CHARACTER_SELECT_15` → `GAME_STATE_BOOK_MONSTER_16`，
## 两次选择都在 `Evt_stdPROC` case 0x20 的等待期内完成，见 wiki\growth\starter-select.md）。
enum MasteryStage {
	MASTERY = 0,  ## 六个流派候选（`Game_Character_Select_init`）
	STARTER = 1,  ## 所选流派的五只初始精灵（`Game_Book_Monster_init:12-35`）
}

## 剧情动作号从 `+100` 起（`Evt_stdPROC` case 0xA：`Object_objANI(obj, p[1] + 100)`）。
## `Field_Hero_procNext` 与 `Field_Npc_procNext` 对 100..199 重播，
## 只有 ≤99 的对象动作会在末帧 `Object_objANI(obj, 0)`。见 wiki\field\field-animation-wait.md。
const SCRIPTED_ANIMATION_FIRST := 100

## 原生 `Object_objDIRECT` 的方向表：下标 0–3 依次是左／右／下／上。
## `PLACE_DIRECTION_FLAGS` 写复合的 `direction_flags`，`PLACE_DIRECTION_CODES` 写 `direction_code`。
const PLACE_DIRECTION_FLAGS := [
	FieldAction.Facing.LEFT | FieldAction.Facing.DOWN,
	FieldAction.Facing.RIGHT | FieldAction.Facing.DOWN,
	FieldAction.Facing.RIGHT | FieldAction.Facing.DOWN,
	FieldAction.Facing.RIGHT | FieldAction.Facing.UP,
]
const PLACE_DIRECTION_CODES := [
	FieldAction.Facing.LEFT, FieldAction.Facing.RIGHT,
	FieldAction.Facing.DOWN, FieldAction.Facing.UP,
]
## JSON 数值上限（存档里 `emotionRevision` 只要求是非负整数）。
const MAX_SAFE_INTEGER := 9007199254740991

## 原指令 `SCREEN_EFFECT`（case 3）的子模式；其余子模式的含义未确认。
enum ScreenEffect {
	FLASH = 3,
	SHAKE = 4,
	## `Evt_stdPROC:105` 的子模式 5：`p[2] == 4` 时 `Map_eftSET(1, 3, 0, 0, 1)` 整屏黑，
	## 其余值 `Map_eftReset(1)`；两种都是立即推进记录。见 `wiki\field\map-effects.md`。
	MAP_EFFECT = 5,
	## `Evt_stdPROC:120-124` 的子模式 6 只把 `p[2]` 写进 `EvtData+0x11`（`cht_destroy_flag`），
	## 下一帧由 `Evt_stdPAINT2:88-92` 读到 1 才 `Evt_chtDESTROY()` 并清 0——销毁的是原版那扇
	## 常驻对话窗，**不是**全屏遮罩，任何一帧都不填色。见 `wiki\event\event-chain-audit.md`
	## 「动作／特效播放语义」。
	CHT_DESTROY = 6,
}

## `Evt_stdPAINT2:70-81` 的闪光曲线：`GRP_MODE_LINEAR_DODGE`（加色）叠加
## `RGB = 300 - 60 * 帧号`，负值按 0 处理；`Evt_stdPROC:132-133` 的 `step_count > 5`
## 决定闪 6 帧。加色 0 等于不画，所以闪光是「白光往透明收」，最后一帧不是黑色。
const FLASH_PEAK := 300
const FLASH_STEP := 60
const FLASH_FRAMES := 6

## 原生 `MapData+46` 的地图滤镜（`Evt_eftSET`／`Evt_eftRESET`）。
enum MapFilter {
	NONE = 0,
	GRAY = 1,
	DARK = 2,
}

## `Evt_camSET(a1, a2, a3, n2)` 的 `n2`：`MapData.reserved_0x126[26]`（+26）里存的
## 不是帧数而是「`Map_posFOCUS` 用哪条推进路径」的模式号。
enum CameraMode {
	## `n2 <= 0`：`+33 = 0` 回到跟随英雄，`+32 = 1` 立即放行。
	FOLLOW = 0,
	## `n2 == 1`：`Evt_camSET` 当场 `Map_posFOCUS()`（模式 1 → `Map_posCENTER(x, y, 1)` 一步定位）
	## 并把 `+32` 置 1，所以也不等待。
	INSTANT = 1,
	## `n2 == 2`：逐帧 `Map_posMOVE(&p_x, &p_y, x, y, 7)` 每帧 7 px，到位才置 `+32`。
	PAN_FAST = 2,
	## `n2 == 3`：同上，`n7 = 4`，每帧 4 px。
	PAN_SLOW = 3,
	## `n2 == 4`：逐帧 `Map_posCENTER(x, y, 0)` 半程收敛，`Map_posCENTER` 返回 2（没变化）才置 `+32`。
	HALF_CONVERGE = 4,
}

var progress: Dictionary
var running := false
var paused := false
var boundary := ""
var message := ""
var trace: Array[String] = []
var map: Dictionary = {}
var combat: RefCounted
var _provider: Object
var _random: Callable
var _disposed := false
var _initialized := false
var _battle_returned := false
var _effects: Array[Dictionary] = []
var _effect_serial := 0
var _pending: Dictionary = {}
var _motions: Dictionary = {}
var _timed: Array[Dictionary] = []
var _remaining := 0.0
var _battle_order: Array = []
var _battle_effect := -1
## 已在结算窗口的 `items` 阶段入包的战斗（原生 `Battle_Win_mRun@0x322F0:179-191` 子状态 2）：
## 键是 `BattleSettlement` 实例 id，值是那一次入包的报告。确认离开战斗时只把报告并回结果，
## 不再重复入包，也不再重复推 fxt416 入手提示。
var _battle_drops: Dictionary = {}
var _opcode := 0
## 初始精灵选择停在哪一级（`MasteryStage`）。原生用状态 15／16 两个状态号表达，
## 本工程两级共用一条事件门，所以单开一个运行时标志（不进存档）。
var _mastery_stage := MasteryStage.MASTERY
## 原生 `EvtData` 尾部两个在 IDB 里没有成员名的字段（反编译只能写成
## `EvtData.condition_probability_threshold + N`：该字段本身在 +0x1C，所以「+12 字节」＝ +0x28、
## 「+12 个 int」＝ +0x4C）：
##   +0x28 `pause_objects`（u8）＝ opcode 22 的对象处理暂停位。唯一写点 `Evt_stdPROC:465`
##     （case 0x16，整字节写入 `p[0]`）；唯一消费点 `Object_procRUN:13`（`!= 1` 时冻结对象池）。
##   +0x4C `event_music_track`（int）＝ 事件 BGM 轨道号，≤0 表示没有事件曲。写点
##     `Evt_stdPROC:473-476`（case 0x18，与旧值不同才写并 `EFC_mdaFreeALL()`）与
##     `Evt_stdINIT:42`（`step_kind != 0` 时置 −1 并 `EFC_mdaFreeALL()`）；读点
##     `GameCanvas_mdaPlay:110/118`（`<= 0` 回默认曲，否则 `EFC_mdaPlayBACK(轨道 + 100)`）。
## 暂停位是运行时标志（不进存档）；轨道号进存档，键名沿用 `music`（`field_runtime` 读同一个键）。
## 原生把 `p[0]` 整字节写进 `EvtData+0x28`（`pause_objects`），消费端 `Object_procRUN:13`
## 用 `!= 1` 判定，只有恰好 1 冻结对象池的逐帧推进，其余取值（含 0）都是恢复。
const PAUSE_OBJECTS_ON := 1
## `EvtData+0x4C`（`event_music_track`）在存档里的键名；字符串沿用 `music` 以兼容既有存档。
const MUSIC_TRACK_KEY := "music"
## `GameCanvas_mdaPlay:118` 的实参偏移：`EFC_mdaPlayBACK(轨道 + 100)`（资源号从 101 起）。
const MUSIC_CHANNEL_OFFSET := 100
## 两种「没有事件曲」的取值：`Evt_stdINIT:42` 置 −1，`GameCanvas_mdaPlay:110` 的 `<= 0` 分支。
const MUSIC_TRACK_CLEARED := -1
const MUSIC_STOP := 0
## 存档校验的轨道号上限（沿用既有取值；原生是否恰为轨道上限未确认）。
const MUSIC_TRACK_MAX := 51
## 原生 EvtData 的另一个运行时标志（不进存档）：+0x25 触发器锁存。
var _trigger_latch := false
var _pause_objects := false
## 原生 `EvtData.step_index` 的「无效值」（`Evt_stdINIT:35` 写 −1，`Evt_stdPROC:92`
## 见到它就返回 0）：没有事件在跑。本工程 `progress["cursor"]` 只存非负步号，所以用这个运行时标志
## 表达同一状态；它不进存档，重进游戏时 `initialize()` 按存档里的 `eventId` 重新判一次。
var _step_index_idle := false
## 原生 MapData+46 的地图滤镜（0 无、1 灰、2 暗）。
var _map_filter := 0
## 原生 `Map_eftSET` 的全屏特效状态（`MapData.reserved_0x152[2..9]`），
## 档位表在 `scripts\data\map_effect.gd`。空字典＝没有特效。
var _map_effect: Dictionary = {}
## 原生 ParamData 的事件表（不进存档）：opcode 27 的通行矩形与 opcode 26 的地图物件。
var _move_rects: Array = []
var _event_objects: Array = []
## 原生 ParamData.current_quest_progress（触发 3 写入的条件数量）。
var quest_progress := 0
## Game_Character_Select_init 载入的六个流派候选（Object_resLOAD(12, n + 1000)）。
## 每 22 个物种一组（`Book.MONSTER_SLOTS`），这六只是每组最后一只（`22 * m + 21`）。
const MASTERY_SPECIES := [21, 43, 65, 87, 109, 131]
## 二级页的可选格：`Game_Book_Monster_init:18-26` 把 `22 * 流派 + 4 .. + 8` 的
## `Param_bookIsMonster` 位置 1（其余清零），`:151` 确认前再按同一式子校验。
const STARTER_FIRST_SLOT := 4
const STARTER_COUNT := 5
## `Game_Book_Monster_mKeyPressed:69-80` 的 `Ball_stdSet` 实参：等级 1、未觉醒。
const STARTER_LEVEL := 1
const STARTER_AWAKENED := 0
## `Ball_stdSet` 的 `mastery_value`（`r3_0`）：初始精灵传 −1（同 `nativeArguments` 第 4 项）。
const STARTER_MASTERY_VALUE := -1
## 选完主精灵后还赠两只同伴（`Game_Book_Monster_mKeyPressed:85-94`）：所在组是
## `22 * ((流派 + 4) % 6)` 与 `22 * ((流派 + 2) % 6)`，组内序号取 `EFC_mainGetRAND() % 4`。
const COMPANION_GROUP_SHIFTS := [4, 2]
const COMPANION_SLOT_COUNT := 4
## 旅店一次住宿的金币（`Field_Inn_mKeyPressed` 的 `Param_moneySET(-50)`，要求钱 > 49）。
const INN_COST := 50
## 第 2／4 组道具的固定出手价（`Field_Item_Sell_Price`：`100 × 数量`）。
const SELL_FIXED_PRICE := 100
## 公会码（原生 `ParamData.guild_code_bits`，`ParamDataType+0xb3` 的 u8）。存档里就是
## `GameSaveFilePartialType.player_state.guild_code_bits`——`player_state` 在文件 +0x8、结构 664 字节，
## `Param_saveGET` 用 `memcpy(&ptr->player_state, &ParamData, sizeof(ptr->player_state))` 整块写、
## `Param_saveSET` 用 `memcpy(&ParamData, &ptr->player_state, 0x298)` 整块读回，
## 所以字节偏移是 `save1/2.dat + 0x8 + 0xb3 = +0xbb`。
## 初值 99 有据：`Param_stdInit` 的第三参数直接写 `ParamData.guild_code_bits`（0x98172），
## 开局调用点是 `Param_stdInit(0, 1, 0x63)`（0x53409，0x63 = 99）⇒ 99 = **最差名次**。
## 原生**没有**「0 = 未入会」这一态（0 只出现在 `Param_saveINIT` 的 memset 缓冲里）。
## 方向「数字越小越好」：`Battle_Win_mRun`（0x32888 起）只在 `kind == 3` 且
## `guild_code > 1` 时自减，`<= 1` 即最高名次（`Field_Guild_*` 回 fxt 49「最高公会排名」）；
## 于是 `Qst_stdQuest`（0x125056）与 NPC 页（0x125486）的
## `guild_rank != 0 && guild_code > guild_rank` 就是「名次比任务要求的数字更大（更差）→ 拒任务」。
## 新档 99 会让带 `guild_rank` 的公会任务全部被拒，与原生开局一致。
## 本工程只留一个存档键：顶层 `guildCode`。原生只有 `guild_code_bits` 一个字节，状态页
## RANK（`Menu_Hero_Draw1:42` 直接传 `ParamData.guild_code_bits`）与任务判定读的都是它；
## 老存档曾把它同时记在 `parameter.rank`，`initialize()` 把旧键迁到 `guildCode` 后删除。
const GUILD_CODE_KEY := "guildCode"
const GUILD_CODE_MIN := 1
const GUILD_CODE_MAX := 99
const GUILD_CODE_INITIAL := 99


## 公会码的唯一读点：新档／新存档读 `guildCode`，老存档回落 `parameter.rank`，都缺时取
## 原生初值 99（`Param_stdInit` 的 `0x63`）。越界值原样返回，是否损坏由
## `validate_progress()` 判定，`MenuModel.guild_grade()` 按原生比较链落到 0 档。
static func guild_code(progress: Dictionary) -> int:
	var value: Variant = progress.get(GUILD_CODE_KEY)
	if value is int:
		return value
	var parameter: Variant = progress.get("parameter")
	if parameter is Dictionary and parameter.get("rank") is int:
		return parameter.rank
	return GUILD_CODE_INITIAL


## 飞艇传送前的原地记录（原生 `ParamData.warp_saved_map_id / warp_saved_tile_x / warp_saved_tile_y`，
## 结构 `ParamDataType` 里是 `u16 / u8 / u8`）。初值三项全 0：新档只有
## `Param_saveINIT` 的 `memset(a1, 0, sizeof(GameSaveFilePartialType))`，`Param_stdInit`
## 从头到尾不碰这三项；唯一写入点是 `Field_Warp1_mKeyPressed` 的 −5 分支（游标 0）：
## `warp_saved_map_id = MapData.map_id`、`warp_saved_tile_x/y = 英雄.x/y / 16`。
## 0 号地图在世界地图里是真实节点，所以没登过船时 `Field_Warp2_Draw:44-46` 展示的就是
## 0 号地图的 (0, 0)——与原生一致，不是「空图哨兵」。老存档读取方一律 `parameter.get(键, 默认)`。
const WARP_SAVED_MAP_INITIAL := 0
const WARP_SAVED_TILE_INITIAL := 0
## 原生 `Battle_Drop_BOX` 的两张 (道具号, 数量) 表（.rodata 0x97BB8／0x97C10）。
## 选哪张看该地图在世界地图记录里的列号（`Map_worldGET` 的 +38）：> 99 是室内层。
const BOX_DROPS_OUTDOOR := [
	[1003, 5], [1004, 5], [1006, 5], [1007, 3], [1017, 3], [1037, 5],
	[1019, 1], [1020, 1], [1021, 1], [1022, 1], [1023, 1], [1024, 1],
	[5000, 5], [7000, 1], [7004, 1], [7006, 1], [7013, 1], [7019, 1], [7020, 1],
	[26000, 1000], [26000, 2000], [26000, 3000],
]
const BOX_DROPS_INTERIOR := [
	[1003, 5], [1004, 5], [1006, 5], [1007, 5], [1017, 5],
	[1019, 1], [1020, 1], [1021, 1], [1022, 1], [1023, 1], [1024, 1],
	[7000, 1], [7002, 1], [7004, 1], [7005, 1], [7006, 1], [7007, 1],
	[7009, 1], [7010, 1], [7013, 1], [7014, 1], [7019, 1], [7020, 1],
	[26000, 2000], [26000, 3000], [26000, 4000], [26000, 5000],
]


static func initial_development() -> Dictionary:
	return {"experience": 0, "growth": [1, 1, 1, 1, 1, 1],
		"points": 0, "allocated": [0, 0, 0],
		"masteryExperience": MonsterAttribute.zero_points()}


static func initial_progress(slot: int, trait_value: int = -1) -> Dictionary:
	if slot not in [0, 1] or trait_value < -1 or trait_value > 5:
		return {}
	return {
		"schema": "battlemonster.native-chain", "version": 1, "slot": slot,
		"mapId": 0, "player": {"x": 8, "y": 8},
		"actors": [_new_actor(0, 8, 8)], "eventId": 0, "cursor": 0,
		"quest": 0, MUSIC_TRACK_KEY: 0, "warpEnabled": {}, "warpPassed": {},
		"parameter": {"identity": 0, "level": 1, "moneyBalance": 0,
			"standardProgressPoints": 0,
			EXP_BONUS_KEY: 0,
			"trait": randi_range(0, 5) if trait_value == -1 else trait_value,
			"development": initial_development(),
			"warp_saved_map_id": WARP_SAVED_MAP_INITIAL,
			"warp_saved_tile_x": WARP_SAVED_TILE_INITIAL,
			"warp_saved_tile_y": WARP_SAVED_TILE_INITIAL},
		"itemCapacity": [72, 72, 72, 72, 72, 72], "monsterCapacity": 20,
		"inventory": {}, "monsters": [], "extraNpcs": [], "camera": null,
		"book": {Book.BOOK_MONSTERS: [], Book.BOOK_SKILLS: []},
		"quests": QuestLogModel.empty_dict(),
		"openedBoxes": [],
		"guildCode": GUILD_CODE_INITIAL,
		"playedTimeMs": 0,
	}


## 经验加成窗口的剩余毫秒（`standard_progress + 7`）：`<= 0`（未生效或老存档缺键）按 0。
static func exp_bonus_remaining(parameter: Variant) -> int:
	if not parameter is Dictionary:
		return 0
	var remaining: Variant = parameter.get(EXP_BONUS_KEY, 0)
	return int(remaining) if remaining is int and remaining > 0 else 0


## `Field_Quest_Complete_SetResult:40-41` 的加成：窗口内 `v2 += v2 / 5`（整数除法）。
## 战斗那一路走 `Battle_Win_SetResult:181` 的 `n20 = 20` 百分比，两处都是 +20%。
static func experience_with_bonus(parameter: Variant, base: int) -> int:
	if exp_bonus_remaining(parameter) <= 0:
		return base
	return base + base / EXP_BONUS_DIVISOR


static func normalize_integer_types(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key: Variant in value:
			normalized[key] = normalize_integer_types(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for entry: Variant in value:
			normalized.append(normalize_integer_types(entry))
		return normalized
	if value is float and is_finite(value) and floor(value) == value and \
			absf(value) <= 9007199254740991.0:
		return int(value)
	return value


static func _uint(value: Variant, maximum: int = 65535) -> bool:
	return value is int and value >= 0 and value <= maximum


static func _point_valid(value: Variant) -> bool:
	return value is Dictionary and _uint(value.get("x"), 255) and _uint(value.get("y"), 255)


static func _numeric_key(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	for character in value:
		if character < "0" or character > "9":
			return false
	return true


static func _item_bag(type: int, index: int) -> int:
	return ItemKind.bag_of(type, index)


static func _item_max_stack(type: int, index: int) -> int:
	return ItemKind.max_stack(type, index)


static func _stack_slots(quantity: int, maximum: int) -> int:
	return int((quantity + maximum - 1) / maximum)


static func _canonical_numeric_key(value: String) -> String:
	var first_nonzero := 0
	while first_nonzero < value.length() - 1 and value.substr(first_nonzero, 1) == "0":
		first_nonzero += 1
	return value.substr(first_nonzero)


static func _integer_array(value: Variant, size: int) -> bool:
	return value is Array and value.size() == size and value.all(
		func(n: Variant) -> bool: return n is int)


static func validate_progress(value: Variant, slot: int) -> bool:
	if not value is Dictionary or slot not in [0, 1]:
		return false
	var p: Dictionary = value
	if p.has("playedTimeMs") and not _uint(p.playedTimeMs, 4294967295):
		return false
	if p.get("schema") != "battlemonster.native-chain" or p.get("version") != 1 or p.get("slot") != slot:
		return false
	for key in ["mapId", "eventId", "cursor", "quest"]:
		if not _uint(p.get(key)):
			return false
	if not (p.get(MUSIC_TRACK_KEY) == MUSIC_TRACK_CLEARED or
			_uint(p.get(MUSIC_TRACK_KEY), MUSIC_TRACK_MAX)) or not _point_valid(p.get("player")):
		return false
	var parameter: Variant = p.get("parameter")
	if not parameter is Dictionary or not _uint(parameter.get("identity"), 255) or \
			not _uint(parameter.get("level"), MonsterAttribute.LEVEL_MAX) or \
			parameter["level"] < MonsterAttribute.LEVEL_MIN or not _uint(parameter.get("trait"), 5):
		return false
	if parameter.has("preferredMastery") and not _uint(parameter["preferredMastery"], 5):
		return false
	if parameter.has("moneyBalance") and not _uint(parameter["moneyBalance"], MONEY_MAX):
		return false
	if parameter.has("standardProgressPoints") and \
			not _uint(parameter["standardProgressPoints"], STANDARD_PROGRESS_POINTS_MAX):
		return false
	# 经验加成窗口：原生是 dword，只有道具会写成 3600000（1 小时），旧存档没有这个键按 0。
	if parameter.has(EXP_BONUS_KEY) and not _uint(parameter[EXP_BONUS_KEY], EXP_BONUS_MILLISECONDS):
		return false
	# 飞艇传送前的原地记录：原生类型是地图号 u16、tile x／y 各 u8。
	if parameter.has("warp_saved_map_id") and not _uint(parameter["warp_saved_map_id"]):
		return false
	if parameter.has("warp_saved_tile_x") and not _uint(parameter["warp_saved_tile_x"], 255):
		return false
	if parameter.has("warp_saved_tile_y") and not _uint(parameter["warp_saved_tile_y"], 255):
		return false
	if parameter.has("development"):
		var development: Variant = parameter["development"]
		if not development is Dictionary or not _uint(development.get("experience"), 2147483647) or \
				not _uint(development.get("points")) or not _integer_array(development.get("growth"), 6) or \
				not development["growth"].all(func(n: int) -> bool: return _uint(n, 99) and n > 0) or \
				not _integer_array(development.get("allocated"), 3) or \
				not development["allocated"].all(func(n: int) -> bool: return _uint(n, 240)):
			return false
		# 六格属性经验（＝ `ParamData.mastery_progress[i].point_remainder`）。老存档没有这个键，
		# 由 `initialize()` 补零，所以这里只在键存在时校验。
		if development.has("masteryExperience") and \
				(not _integer_array(development["masteryExperience"], MonsterAttribute.COUNT) or \
				not development["masteryExperience"].all(
					func(n: int) -> bool: return _uint(n, 2147483647))):
			return false
	# 公会码只认原生可达的 1..99（新档 99、每胜一场 −1、1 为最高名次）；0 是原生不存在的
	# 未初始化值，越界一律判损坏（由 `_init` 的 `_block("原流程状态损坏/版本不兼容")` 报出），
	# 不在这里夹断成合法值。缺这个键的老存档靠 `initialize()` 的补齐路径。
	if p.has("guildCode") and (not p["guildCode"] is int or
			p["guildCode"] < GUILD_CODE_MIN or p["guildCode"] > GUILD_CODE_MAX):
		return false
	if not p.get("actors") is Array or p["actors"].size() > 200:
		return false
	for a: Variant in p["actors"]:
		if not a is Dictionary or not _uint(a.get("id")) or \
				not (a.get("x") is int or a.get("x") is float) or \
				not (a.get("y") is int or a.get("y") is float) or \
				not is_finite(float(a["x"])) or not is_finite(float(a["y"])) or \
				not _uint(a.get("action")) or not _uint(a.get("direction"), 255) or \
				not a.has("emotion") or not (a["emotion"] == null or _uint(a["emotion"])):
			return false
		if a.has("animationEndMode") and a["animationEndMode"] not in [
				AnimationEndMode.CALLBACK_OR_RESTART, AnimationEndMode.RESTART,
				AnimationEndMode.HOLD_LAST_FRAME]:
			return false
		for pair in [["emotionFrame", 127], ["emotionRepeats", 127],
				["emotionRevision", MAX_SAFE_INTEGER], ["lastDirection", 255]]:
			if a.has(pair[0]) and not _uint(a[pair[0]], pair[1]):
				return false
	if not p.get("monsters") is Array or p["monsters"].size() > 20:
		return false
	for m: Variant in p["monsters"]:
		if not m is Dictionary or not _uint(m.get("species")) or not _uint(m.get("level"), 99) or \
				not _integer_array(m.get("nativeArguments"), 5):
			return false
		for pair in [["nickname", 6], ["hp", 65535], ["sp", 127],
				["brainCurrent", 255], ["brainLimit", 255]]:
			if m.has(pair[0]) and not _uint(m[pair[0]], pair[1]):
				return false
		if m.has("experience") and not _uint(m["experience"], 2147483647):
			return false
	if p.has("partyOrder"):
		var order: Variant = p["partyOrder"]
		if not order is Array or order.size() > mini(3, p["monsters"].size()):
			return false
		var seen := {}
		for index: Variant in order:
			if not _uint(index, p["monsters"].size() - 1) or seen.has(index):
				return false
			seen[index] = true
	if not p.get("extraNpcs") is Array:
		return false
	for row: Variant in p["extraNpcs"]:
		if not _integer_array(row, 5) or not row.all(func(n: int) -> bool: return _uint(n, 255)):
			return false
	if p.get("itemCapacity") != [72, 72, 72, 72, 72, 72] or p.get("monsterCapacity") != 20:
		return false
	if p.has("book"):
		var book: Variant = p["book"]
		if not book is Dictionary:
			return false
		# 图鉴按升序记录已获得的 id：怪物 0-131、技能书 0-167，重复或乱序都算损坏。
		for pair in [[Book.BOOK_MONSTERS, Book.MONSTER_CATEGORIES * Book.MONSTER_SLOTS - 1],
				[Book.BOOK_SKILLS, Book.SKILL_SLOTS - 1]]:
			var entries: Variant = book.get(pair[0])
			if not entries is Array or entries.size() > pair[1] + 1:
				return false
			var previous := -1
			for entry: Variant in entries:
				if not _uint(entry, pair[1]) or entry <= previous:
					return false
				previous = entry
	# 任务槽（`ParamData.quests[11]`）与完成位图，布局见 `quest_log.gd`。
	if p.has("quests") and not QuestLogModel.validate(p["quests"]):
		return false
	for key in ["inventory", "warpEnabled", "warpPassed"]:
		if not p.get(key) is Dictionary:
			return false
		for entry: Variant in p[key]:
			if not _numeric_key(entry):
				return false
			if key == "inventory":
				if not _uint(p[key][entry]):
					return false
			elif not p[key][entry] is bool:
				return false
	# 已开的宝箱按地图号升序记录（原生 `MapData.box_missing_bits` 的逐位存档）。
	if p.has("openedBoxes"):
		var boxes: Variant = p["openedBoxes"]
		if not boxes is Array or boxes.size() > 256:
			return false
		var previous_box := -1
		for entry: Variant in boxes:
			if not _uint(entry) or entry <= previous_box:
				return false
			previous_box = entry
	return p.has("camera") and (p["camera"] == null or _point_valid(p["camera"]))


static func _new_actor(id: int, x: int, y: int) -> Dictionary:
	return {"id": id, "x": x, "y": y, "direction": 32, "action": FieldAction.Hero.IDLE, "emotion": null}


func _init(provider: Object, state: Dictionary, random: Callable = Callable()) -> void:
	_provider = provider
	_random = random
	progress = state.duplicate(true)
	if not validate_progress(progress, int(progress.get("slot", -1))):
		_block("原流程状态损坏/版本不兼容")
		return
	for actor: Dictionary in progress["actors"]:
		if actor["emotion"] != null and not actor.has("emotionRepeats"):
			_set_emotion(actor, 0, 0)


func _roll(limit: int) -> int:
	var result := int(_random.call(limit)) if _random.is_valid() else randi_range(0, limit - 1)
	assert(result >= 0 and result < limit)
	return result


func _load(method: String, argument: Variant = null) -> Dictionary:
	if _provider == null or not _provider.has_method(method):
		_block("资源接口缺少 %s" % method)
		return {}
	var value: Variant = _provider.call(method) if argument == null else _provider.call(method, argument)
	if value is Resource:
		value = value.get_meta("payload", null)
	if not value is Dictionary or value.is_empty():
		_block("原资源缺失: %s %s" % [method, str(argument)])
		return {}
	return _native_numbers(value)


## 事件表里有没有这一号（原生 `Evt_stdSTYLE:20` 的 `JC_memGET(...) == nullptr`）：
## provider 没有这项查询能力时按「存在」处理，让 `_load` 走原来的报错路径，不静默吞掉缺表。
func _has_event(id: int) -> bool:
	if _provider != null and _provider.has_method("has_event"):
		return bool(_provider.call("has_event", id))
	return true


## 读不到事件资源时的收尾（原生 `Evt_stdINIT:33-38`）：`Evt_stdSTYLE` 返回 0 →
## `EvtData.step_index = -1`、`Evt_stdQUEST(-1)` 清任务提示。之后 `Evt_stdPROC:92` 每帧
## 直接 `return 0`，`Evt_stdRUN` 退出循环，`GameCanvas_mRun:13` 不看返回值 →
## 野外拿回控制权。所以这里不写 `boundary`（那是数据缺损的报错），只留一条便于排查的 trace。
func _mark_step_idle(id: int) -> void:
	_step_index_idle = true
	trace.append("Evt_stdINIT(%d):无事件资源→EvtData.step_index=-1（安静结束）" % id)


## 玩法数据是 typed 资源，不走 `_load` 的字典载荷路径。
func _gameplay() -> GameplayData:
	if _provider == null or not _provider.has_method("load_gameplay"):
		_block("资源接口缺少 load_gameplay")
		return null
	var data: GameplayData = _provider.call("load_gameplay")
	if data == null:
		_block("原资源缺失: load_gameplay")
	return data


static func _native_numbers(value: Variant) -> Variant:	# Converted .tres payloads carry integral floats; model state uses integers.
	# Fractional/non-finite inputs remain unchanged so instruction validation fails.
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_native_numbers(entry))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _native_numbers(value[key])
		return result
	return value


func _emit(kind: String, data: Dictionary = {}) -> int:
	_effect_serial += 1
	var effect := data.duplicate(true)
	effect["kind"] = kind
	effect["id"] = _effect_serial
	_effects.append(effect)
	return _effect_serial


func take_effects() -> Array[Dictionary]:
	var result := _effects
	_effects = []
	return result


func _block(detail: String) -> void:
	if boundary.is_empty():
		boundary = "%s：%s" % [message, detail]
		_emit("blocked", {"detail": boundary, "eventId": progress.get("eventId", -1),
			"cursor": progress.get("cursor", -1)})


func dispose() -> void:
	_disposed = true
	_pending.clear()
	_motions.clear()
	_timed.clear()
	_battle_drops.clear()


func initialize(continuing: bool = false) -> void:
	if _initialized or _disposed or not boundary.is_empty():
		return
	trace.append("Prime11→Game13:Game_Continue" if continuing else "Prime11→Game12:Game_New")
	trace.append("Game14:Game_Next→Game1:Field")
	# 老存档没有图鉴字段、或怪物／技能书被直接写进 `monsters`／`inventory` 时，
	# 进图前用「当前持有」把获得记录补齐（幂等，只会增长）。
	Book.record_owned(progress)
	# 老存档没有任务槽字段：补一份全空槽（`ParamData.quests` 在 `Qst_Initialize` 里是 memset）。
	if not progress.has("quests"):
		progress["quests"] = QuestLogModel.empty_dict()
	# 老存档没有公会码字段：原生只有 `ParamDataType+0xb3` 一个字节，本工程统一记在顶层
	# `guildCode`。旧存档把它同时记在 `parameter.rank`，所以缺键时按旧键补；旧键也非法
	# （例如全零缓冲的 0）才回落到新档初值 99（`Param_stdInit`）。迁完删掉旧键，保证只有一处。
	var parameter: Variant = progress.get("parameter")
	if parameter is Dictionary:
		var legacy_rank: Variant = parameter.get("rank")
		if not progress.has(GUILD_CODE_KEY):
			progress[GUILD_CODE_KEY] = legacy_rank if legacy_rank is int and \
				legacy_rank >= GUILD_CODE_MIN and legacy_rank <= GUILD_CODE_MAX else \
				GUILD_CODE_INITIAL
		parameter.erase("rank")
	# 老存档没有六格属性经验：按 `Param_stdInit` 的清零值补（`mastery_progress[0..5]
	# .point_remainder = 0`，等级仍是 `growth` 里的初值 1）。
	var legacy_development: Variant = progress["parameter"].get("development")
	if legacy_development is Dictionary and not legacy_development.has("masteryExperience"):
		legacy_development["masteryExperience"] = MonsterAttribute.zero_points()
	# 老存档的怪物记录没有 BRAIN 这两项：按 `Ball_stdSet` 建记录的初值补
	# （`brain_limit` 恒 99、`brain_current` 由调用方给，事件 0x1F 那支传 0）。
	for legacy_member: Variant in progress.get("monsters", []):
		if legacy_member is Dictionary:
			if not legacy_member.has("brainCurrent"):
				legacy_member["brainCurrent"] = Battle.BRAIN_CURRENT_INITIAL
			if not legacy_member.has("brainLimit"):
				legacy_member["brainLimit"] = Battle.BRAIN_LIMIT
	map = _load("load_map", progress["mapId"])
	# 原生 `Game_Next_mRun:17` 是 `Evt_stdINIT(ParamData.current_event_resource_id)`：
	# 存档里的当前事件号在事件表里不存在时（事件链从末端结束过）也只是 `step_index = -1`，
	# 地图照常可玩，不是数据缺损。
	if _has_event(progress["eventId"]):
		_load("load_event", progress["eventId"])
	else:
		_mark_step_idle(progress["eventId"])
	if not boundary.is_empty() or not _populate():
		return
	_emit("map", {"mapId": progress["mapId"], "map": map})
	_emit("focus", {"position": progress["camera"] if progress["camera"] != null else progress["player"]})
	var music_track := int(progress[MUSIC_TRACK_KEY])
	if music_track > 0:
		_music(MUSIC_CHANNEL_OFFSET + music_track)
	_initialized = true
	pump()


## 原生事件曲只有这一个出口：`GameCanvas_mdaPlay:118` 的 `EFC_mdaPlayBACK(轨道 + 100)`；
## 没有事件曲（≤0）时回到默认曲，对应 `:110` 的 `<= 0` 分支。
func _music(id: int) -> void:
	_emit("music", {"track": id})


## 原生 `EvtData+0x4C`（`event_music_track`）的写点集中在这里：
## `Evt_stdPROC:473-476`（case 0x18）与 `Evt_stdINIT:42`。
func _set_event_music_track(track: int) -> void:
	progress[MUSIC_TRACK_KEY] = track
	_music(MUSIC_CHANNEL_OFFSET + track if track > 0 else MUSIC_STOP)


func _actors() -> void:
	_emit("actors", {"actors": progress["actors"]})


func _actor(id: int) -> Dictionary:
	var target := 0 if id <= 1 else 1000 + id % 1000 if id > 999 else id
	for actor: Dictionary in progress["actors"]:
		if actor["id"] == target or (target >= 1000 and actor.get("species", -1) == target % 1000):
			return actor
	return {}


## 本次进图解析出的遇敌池与野外怪物等级（原生 `Map_mifLOAD` 加载时定好）。
var encounter_pool: Array = []
var encounter_level := 0


func _populate() -> bool:
	if not map.get("info") is Dictionary:
		_block("地图未加载")
		return false
	var catalog: GameplayData = _gameplay()
	if catalog == null or not boundary.is_empty():
		return false
	var encounter: EncounterDefinition = catalog.encounter(int(map["id"]))
	encounter_pool = []
	encounter_level = 0
	if encounter != null:
		encounter_level = encounter.resolved_world_level(_player_level())
		if encounter.is_dynamic():
			# `Map_mifLOAD` 的动态分支：权重按玩家等级行取、物种按稀有度现抽。
			encounter_pool = encounter.dynamic_pool(catalog, _player_level(), _roll)
			if encounter_pool.is_empty():
				_block("原动态地图怪物池无法生成：入口等级 %d 没有可用物种" % _player_level())
				return false
		else:
			encounter_pool = encounter.pool
	var actors: Array = progress["actors"].filter(func(a: Dictionary) -> bool: return a["id"] == 0)
	for npc: Dictionary in map["info"].get("npcs", []):
		actors.append(_new_actor(npc["resource_id"], npc["tile_x"], npc["tile_y"]))
	for row: Array in progress["extraNpcs"]:
		if row[0] == map["id"]:
			var actor := _new_actor(row[3], row[1], row[2])
			actor["direction"] = (FieldAction.Facing.LEFT | FieldAction.Facing.DOWN) if row[4] == 1 else (FieldAction.Facing.RIGHT | FieldAction.Facing.DOWN)
			actors.append(actor)
	var total := 0
	for entry: EncounterEntry in encounter_pool:
		total += entry.weight
	if total > 0:
		for spawn: Dictionary in map["info"].get("monster_spawns", []):
			var choice := _roll(total)
			for entry: EncounterEntry in encounter_pool:
				choice -= entry.weight
				if choice < 0:
					var id := 1000 + entry.species
					if actors.any(func(actor: Dictionary) -> bool: return int(actor.id) == id):
						id = 10000 + actors.size()
					var actor := _new_actor(id, spawn["tile_x"], spawn["tile_y"])
					actor.species = entry.species
					actors.append(actor)
					break
	progress["actors"] = actors
	_actors()
	# 原生 `Map_summonLOAD` + `Map_summonCREATE` 与地图资源在同一处（`FieldCanvas_load`、
	# `Evt_stdPROC` 的 opcode 0xB）：重建跟随对象，之前被 `Op.CLEAR_ACTORS` 销毁的在这里回来。
	_emit("summons-rebuilt")
	return true


func _player_level() -> int:
	return int(progress["parameter"].get("level", 1))


## 原生 `EvtData.step_kind`：`Evt_stdSTYLE:32` 按 `step_index` 从当前 11 字节事件记录
## 取首字节写进去（记录布局 `<B5h`，见 `script/legacy/qst.py`）。停在首记录时它是触发条件
## （`Evt_stdIsPROC`），执行指令时同一个字节就是 `Op`，所以两套名字共用 0–9 的数值空间。
## 4 既是触发条件，也是 `Qst_icoGET:17` 判事件任务码用的取值。
## **只有 0–9 是触发条件**：`Evt_stdIsPROC:93-94` 的 `default` 落到 `LABEL_2` 返回 0，
## 所以 10 以上的取值（15／17／32–34 等）当首记录时事件永远不会开始，它们只在后续步骤里是 `Op`。
## 出货数据里首记录只出现 0–9，见 wiki\event\event-chain-audit.md「事件步骤类型取值表」。
enum Trigger {
	ALWAYS = 0,
	MAP = 1,
	MAP_WITHOUT_MONSTER = 2,
	ITEM_COUNT = 3,
	INTERACT_LATCH = 4,
	## `Evt_stdIsPROC:44-57`：同图且**主角**在矩形里；`Object_objNPC(0)` 等于 `Object_objFIND(1, 0)`
	## （`Object_objNPC:6-10`），组 1 号 0 就是主角（`Game_Next_mRun:9-13` 建的）。
	RECT = 5,
	AREA_ACTION = 6,
	BATTLE_RETURNED = 7,
	## 8 与 7 的置锁存点相同（`Battle_Win_mKeyPressed:18-22` 对 7／8 都写 `EvtData+9`），
	## 差别只在打输：`Battle_Position_mRun:504-508` 对 8 先 `Param_ballFULL(0)`（全队 HP／SP 回满）
	## 再置同一个锁存，所以 8 允许打输后继续剧情；7 与其它触发器打输走 `Battle_Die`。
	BATTLE_RETURNED_ALT = 8,
	LEVEL = 9,
}


func _trigger(opcode: int, p: Array) -> bool:
	match opcode:
		Trigger.ALWAYS: return true
		Trigger.MAP: return progress["mapId"] == p[0]
		# 2：同图且没有任何怪物对象（`Object_objFIND(2, -1) == nullptr`）。
		Trigger.MAP_WITHOUT_MONSTER: return progress["mapId"] == p[0] and not _monster_present()
		# 3：持有物品达到数量；同时把这那次判定记成当前任务进度。
		Trigger.ITEM_COUNT: return _item_condition(p)
		# 4：玩家在同图的可交互对象上按下确定（Event_stdSET(4, 定义号) 的锁存）。
		Trigger.INTERACT_LATCH: return _trigger_latch
		Trigger.RECT:
			return progress["mapId"] == p[0] and progress["player"]["x"] >= int(p[1] / 100) and \
				progress["player"]["y"] >= p[1] % 100 and \
				progress["player"]["x"] < int(p[1] / 100) + int(p[2] / 100) and \
				progress["player"]["y"] < p[1] % 100 + p[2] % 100
		# 6：在区域里做过动作（动画 3／4）并已停下。
		Trigger.AREA_ACTION: return _area_action_trigger(p)
		Trigger.BATTLE_RETURNED, Trigger.BATTLE_RETURNED_ALT: return _battle_returned
		Trigger.LEVEL: return progress["parameter"]["level"] >= p[0]
		# 原生 `Evt_stdIsPROC:93-94` 对 10 以上一律返回 0（永不触发），本工程按「未接通的触发器」报错；
		# 出货数据里首记录只出现 0–9，所以这条分支不可达（见 wiki\event\event-chain-audit.md 取值表）。
		_: _block("尚未接通原触发器 %d" % opcode)
	return false


func _monster_present() -> bool:
	for actor: Dictionary in progress["actors"]:
		if actor.has("species"):
			return true
	return false


func _item_condition(p: Array) -> bool:
	var required: int = p[1]
	var count := _item_count(p[0])
	if count < required:
		return false
	quest_progress = required
	return true


func _item_count(item_id: int) -> int:
	var inventory: Dictionary = progress["inventory"]
	for key: Variant in inventory:
		if _canonical_numeric_key(str(key)) == str(item_id):
			return int(inventory[key])
	return 0


## `Evt_stdIsPROC` 的 case 6：英雄脚点 24×24 与区域矩形相交，
## 期间出现过动画 3／4（调查动作）就锁存，等动画回到 0 时再放行。
func _area_action_trigger(p: Array) -> bool:
	if progress["mapId"] != p[0]:
		return false
	var hero := _actor(0)
	if hero.is_empty():
		return false
	var area_x := int(p[1]) / 100 * 16
	var area_y := int(p[1]) % 100 * 16
	var area_w := int(p[2]) / 100 * 16
	var area_h := int(p[2]) % 100 * 16
	var hero_x := float(hero["x"]) * 16.0 + 8.0
	var hero_y := float(hero["y"]) * 16.0 + 8.0
	if hero_x + 12.0 < area_x or hero_x - 12.0 > area_x + area_w or \
			hero_y + 12.0 < area_y or hero_y - 12.0 > area_y + area_h:
		return false
	var action := int(hero.get("action", 0))
	if action != 0:
		if action in [3, 4]:
			_trigger_latch = true
		return false
	return _trigger_latch


func _records(id: int) -> Array:
	var event := _load("load_event", id)
	if not event.get("records") is Array or event["records"].is_empty():
		_block("原事件记录缺失")
		return []
	return event["records"]


func _next_event() -> bool:
	# `Evt_stdNEXT:10-14`：步号跨过末尾时把后继号按「当前事件号 + 1」交给 `Evt_stdINIT`。
	var successor: int = progress["eventId"] + 1
	if not _has_event(successor):
		_end_chain(successor)
		return false
	var next := _records(successor)
	if not boundary.is_empty():
		return false
	progress["eventId"] = successor
	progress["cursor"] = 0
	progress["camera"] = null
	_trigger_latch = false
	_reset_map_filter()
	_reset_map_effect()
	_emit("focus", {"position": progress["player"]})
	_emit("cover", {"enabled": false})
	if next[0]["opcode"] != Op.NONE:
		_set_event_music_track(MUSIC_TRACK_CLEARED)
	trace.append("Evt_stdNEXT→evt%d" % progress["eventId"])
	return true


## 事件链的末端：`Evt_stdNEXT:14` 的后继号在事件表里不存在时，原生照样把它写进
## `ParamData.current_event_resource_id`（`Evt_stdINIT:14`），然后由那次 INIT 的
## `Evt_stdSTYLE` 失败落到 `step_index = -1`。工程沿用同一份状态（`eventId` 前进到不存在的号），
## 并用 `_step_index_idle` 表达「没有事件在跑」；清掉待办效果相当于 INIT 里的
## `Evt_stdDESTROY(0)`、`Map_eftReset`／`Map_eftVIBRATE(0, 0)`。
func _end_chain(id: int) -> void:
	progress["eventId"] = id
	progress["cursor"] = 0
	progress["camera"] = null
	_pending.clear()
	_motions.clear()
	_timed.clear()
	_trigger_latch = false
	_battle_returned = false
	_reset_map_filter()
	_reset_map_effect()
	# INIT 把 `MapData.reserved_0x126` 那组镜头字段清零，镜头回到跟随英雄。
	_emit("focus", {"position": progress["player"]})
	_mark_step_idle(id)


func _jump_event(id: int) -> bool:
	# Evt_stdPROC..0x7f8a0 calls INIT(p0), returns 1 without NEXT.
	# INIT resets cursor/trigger flags and field effects, not the map.
	if not _uint(id):
		_block("原跳转事件 ID 无效")
		return false
	# 跳转分支也是 `Evt_stdINIT(p0)`：目标事件不存在时同样落到 `step_index = -1` 的安静收尾
	# （跳转本身成立，只是目标没有步可以跑），所以按成功返回、由 `pump` 的 idle 判断收手。
	if not _has_event(id):
		_end_chain(id)
		return true
	var records := _records(id)
	if not boundary.is_empty():
		return false
	if not records[0] is Dictionary or not records[0].get("opcode") is int or \
			not _integer_array(records[0].get("params"), 5):
		_block("原跳转事件触发器构造输入损坏")
		return false
	_step_index_idle = false
	progress["eventId"] = id
	progress["cursor"] = 0
	progress["camera"] = null
	_battle_returned = false
	_trigger_latch = false
	_reset_map_filter()
	_reset_map_effect()
	_emit("focus", {"position": progress["player"]})
	_emit("cover", {"enabled": false})
	_emit("shake", {"x": 0, "y": 0})
	_emit("fade", {"color": 0, "alpha": 0.0})
	if records[0]["opcode"] != Op.NONE:
		_set_event_music_track(MUSIC_TRACK_CLEARED)
	trace.append("Evt_stdINIT→evt%d" % id)
	return true


func pump() -> void:
	if running or paused or _disposed or not _initialized or not boundary.is_empty() or \
			_step_index_idle:
		return
	if not _pending.is_empty():
		# case 0x10：每帧检查对象动画是否播完；还有在播的就继续等。
		if _pending.get("kind") != "animations" or _actors_animating():
			return
		_finish_pending()
		return
	running = true
	for _budget in range(500):
		# `Evt_stdPROC:92`：`step_index` 是无效值（−1）时每帧直接返回 0，不再碰事件资源。
		if _step_index_idle:
			break
		var records := _records(progress["eventId"])
		if not boundary.is_empty():
			break
		if progress["cursor"] >= records.size():
			if not _next_event():
				break
			continue
		var record: Dictionary = records[progress["cursor"]]
		if not record.get("opcode") is int or not _integer_array(record.get("params"), 5):
			_block("原事件构造输入损坏")
			break
		var opcode: int = record["opcode"]
		_opcode = opcode
		message = "evt%d #%d opcode %d" % [progress["eventId"], progress["cursor"], opcode]
		if progress["cursor"] == 0:
			if not _trigger(opcode, record["params"]):
				message += " · 等待原触发条件"
				break
			# 原生 `Evt_stdPROC` 在 `Evt_stdSTYLE` 之后立刻把「已打回来」标志清 0：
			# 这个标志只服务于一次触发器 7／8 的判定，不能留到后面的事件。
			_battle_returned = false
			progress["cursor"] += 1
		else:
			var event_id: int = progress["eventId"]
			var cursor: int = progress["cursor"]
			if not _instruction(opcode, record["params"]):
				break
			if not _pending.is_empty() or not boundary.is_empty():
				break
			if opcode not in [Op.JUMP, Op.BATTLE, Op.JUMP_AND_SAVE]:
				progress["cursor"] += 1
			_record_trace(event_id, cursor, opcode)
	running = false


func _record_trace(event_id: int, cursor: int, opcode: int) -> void:
	trace.append("evt%d#%d:%d" % [event_id, cursor, opcode])
	if trace.size() > 160:
		trace.pop_front()


func _gate(kind: String, id: int = -1) -> void:
	_pending = {"kind": kind, "id": id, "eventId": progress["eventId"],
		"cursor": progress["cursor"], "opcode": _opcode}


func _finish_pending() -> void:
	var previous := _pending
	_pending = {}
	if previous["kind"] != "battle":
		progress["cursor"] += 1
	_record_trace(previous["eventId"], previous["cursor"], previous["opcode"])
	pump()


func _schedule(steps: Array[Dictionary]) -> void:
	_gate("time")
	_timed = steps
	_remaining = FramePacing.seconds_of_frames(_timed[0].get("ticks", 1))
	if _timed[0].has("kind"):
		_emit(_timed[0]["kind"], _timed[0].get("data", {}))


func advance(delta: float) -> void:
	if delta < 0 or not is_finite(delta) or paused or _disposed or not boundary.is_empty():
		return
	pump()
	var available := delta
	while _pending.get("kind") == "time" and not paused and boundary.is_empty():
		if available + 0.000000001 < _remaining:
			_remaining -= available
			break
		available = maxf(0, available - _remaining)
		var ended: Dictionary = _timed.pop_front()
		if ended.has("final"):
			_emit(ended["final"]["kind"], ended["final"].get("data", {}))
		if _timed.is_empty():
			_finish_pending()
		else:
			_remaining = FramePacing.seconds_of_frames(_timed[0].get("ticks", 1))
			if _timed[0].has("kind"):
				_emit(_timed[0]["kind"], _timed[0].get("data", {}))


func complete_effect(id: int) -> bool:
	if _disposed or not boundary.is_empty():
		return false
	if _motions.has(id):
		var motion: Dictionary = _motions[id]
		_motions.erase(id)
		var actor: Dictionary = motion["actor"]
		actor["x"] = motion["destination"]["x"]
		actor["y"] = motion["destination"]["y"]
		actor["action"] = FieldAction.Hero.IDLE
		if actor["id"] == 0:
			progress["player"] = motion["destination"].duplicate()
		_actors()
		return true
	if _pending.get("id") == id and _pending.get("kind") in ["dialogue", "narration", "map-effect"]:
		_finish_pending()
		return true
	return false


## 镜头推进到位：原生 `Map_posFOCUS` 把 `+32` 置 1 后，`Evt_stdPROC`
## 的 case 0x13 才会 `goto LABEL_7` 继续下一条。几何推进在 field 侧（它才有视口与地图尺寸）。
func complete_camera(id: int) -> bool:
	if _disposed or not boundary.is_empty() or _pending.get("kind") != "camera" or \
			_pending.get("id") != id:
		return false
	_finish_pending()
	return true


## 初始精灵选择（opcode 32）确认。两级共用同一道 `mastery` 门：
## * 第一级（`Game_Character_Select_mKeyPressed:23-61`）写
##   `ParamData.preferred_mastery_index`，再把候选换成
##   `GameCanvas_SetNext(GAME_STATE_BOOK_MONSTER_16, …)` 那一页的五只；
## * 第二级（`Game_Book_Monster_mKeyPressed:148-159` 校验、
##   `:38-94` 入队）把选中的那只写进 `progress.monsters` 并进队伍，然后放行事件。
func complete_mastery(id: int, index: int) -> bool:
	if _disposed or not boundary.is_empty() or _pending.get("kind") != "mastery" or \
			_pending.get("id") != id:
		return false
	if _mastery_stage == MasteryStage.STARTER:
		return _recruit_starter(index)
	if index < 0 or index >= MASTERY_SPECIES.size():
		return false
	progress["parameter"]["preferredMastery"] = index
	_mastery_stage = MasteryStage.STARTER
	_gate("mastery", _emit("mastery-select", {"species": starter_candidates(index),
		"stage": _mastery_stage, "mastery": index}))
	return true


## 二级页 BACK：原生 `Game_Book_Monster_mKeyPressed:128-130` 的 CLR 是
## `GameCanvas_SetNext(GAME_STATE_CHARACTER_SELECT_15, preferred_mastery_index)`——回第一级，
## 光标停回已选流派。这里只把门退回第一级，不发新效果（视图自己翻页）。
func return_mastery() -> bool:
	if _disposed or not boundary.is_empty() or _pending.get("kind") != "mastery" or \
			_mastery_stage != MasteryStage.STARTER:
		return false
	_mastery_stage = MasteryStage.MASTERY
	return true


## 二级页的候选物种（`22 * 流派 + 4 .. + 8`）：`Game_Book_Monster_init:18-26`
## 把这几格标成 `Param_bookIsMonster` = 1。
func starter_candidates(mastery: int) -> Array[int]:
	var result: Array[int] = []
	if mastery < 0 or mastery >= MASTERY_SPECIES.size():
		return result
	for slot in STARTER_COUNT:
		result.append(Book.monster_id(mastery, STARTER_FIRST_SLOT + slot))
	return result


## 第二级确认：原生 `Game_Book_Monster_mKeyPressed:38-94` 先把队伍 `party_monsters[0..2]` 与
## 132 位怪物图鉴／168 位技能图鉴全部清零，再 `Ball_stdSet` 建记录、`Ball_stdAddEx` 入包、
## `Ball_stdPartyOn` 进队伍；主精灵之后还照同一套实参补两只同伴（`:84-94`），它们同样
## `Ball_stdPartyOn`，三只正好填满队伍。记录字段与 `Op.ADD_MONSTER`（原生 0x1F）同一套。
## 图鉴清零是剧情临时精灵的回收点：`Op.ADD_MONSTER` 会在图鉴里留下它们，而
## `Op.INIT_PARAMETERS`（`Param_stdInit` → `Ball_bagInit`）只清背包、不动图鉴位图。
func _recruit_starter(index: int) -> bool:
	var mastery := int(progress["parameter"].get("preferredMastery", -1))
	var candidates := starter_candidates(mastery)
	if index < 0 or index >= candidates.size():
		return false
	var recruits := _starter_recruits(candidates[index], mastery)
	var catalog := _gameplay()
	if catalog == null:
		return false
	for species: int in recruits:
		if catalog.monster(species) == null:
			_block("缺少原物种 %d" % species)
			return false
	if progress["monsters"].size() + recruits.size() > progress["monsterCapacity"]:
		_block("原怪物背包已满")
		return false
	Book.reset_records(progress)
	var first: int = progress["monsters"].size()
	for species: int in recruits:
		progress["monsters"].append({"species": species, "level": STARTER_LEVEL,
			"nativeArguments": [species, STARTER_LEVEL, STARTER_AWAKENED, STARTER_MASTERY_VALUE, 0],
			"nickname": Battle.roll_nickname(_roll), "experience": 0, "feel": 0, "food": ItemEffect.FOOD_MAX,
			"brainCurrent": Battle.BRAIN_CURRENT_INITIAL, "brainLimit": Battle.BRAIN_LIMIT})
		Book.discover_monster(progress, species)
	var party: Array = []
	for offset in recruits.size():
		party.append(first + offset)
	# 原生先 `party_monsters[0..2] = nullptr` 再由 `Ball_stdPartyOn` 依次填入；这里整份替换出战顺序
	# （新游戏走到这一步时队伍已被 `Op.INIT_PARAMETERS` 清空）。
	progress["partyOrder"] = party
	_mastery_stage = MasteryStage.MASTERY
	_finish_pending()
	return true


## 主精灵与两只同伴的物种：`Game_Book_Monster_mKeyPressed:85-94` 的
## `EFC_mainGetRAND() % 4 + 22 * ((流派 + 4) % 6)`／`% 4 + 22 * ((流派 + 2) % 6)`。
func _starter_recruits(species: int, mastery: int) -> Array[int]:
	var result: Array[int] = [species]
	for shift: int in COMPANION_GROUP_SHIFTS:
		var group := (mastery + shift) % MASTERY_SPECIES.size()
		result.append(Book.MONSTER_SLOTS * group + _roll(COMPANION_SLOT_COUNT))
	return result


func fail_effect(id: int, detail: String) -> bool:
	if _disposed or not boundary.is_empty() or (not _motions.has(id) and _pending.get("id") != id):
		return false
	_block("原场景效果失败：%s" % detail)
	return true


func cancel_move(id: int) -> bool:
	# Map replacement disposes the old view's non-blocking movement. Do not
	# commit its old-map destination over a subsequent teleport/new-map pose.
	if _disposed or not _motions.has(id):
		return false
	_motions.erase(id)
	return true


func _set_emotion(actor: Dictionary, action: int, repeats: int) -> void:
	var count := ((repeats & 255) ^ 128) - 128
	actor["emotion"] = ((action & 255) ^ 128) - 128 if count > 0 else null
	actor["emotionFrame"] = 0
	actor["emotionRepeats"] = maxi(0, count)
	actor["emotionRevision"] = actor.get("emotionRevision", 0) + 1


func _instruction(opcode: int, p: Array) -> bool:
	var s := progress
	var point := {"x": int(p[1] / 100), "y": p[1] % 100}
	match opcode:
		Op.NONE: pass
		Op.JUMP: return _jump_event(p[0])
		Op.ADD_ITEM: return _add_inventory_item(p[0], p[1])
		Op.REMOVE_ITEM: return _delete_inventory_item(p[0], p[1])
		Op.MUSIC:
			# case 0x18（`Evt_stdPROC:473-476`）：`EvtData+0x4C`（`event_music_track`）与 `p[0]`
			# 不同才写入并 `EFC_mdaFreeALL()`，所以同一首重复发指令不会重播。
			if s[MUSIC_TRACK_KEY] != p[0]:
				_set_event_music_track(p[0])
		Op.LOAD_MAP:
			var destination := _load("load_map", p[0])
			if not boundary.is_empty():
				return false
			map = destination
			s["mapId"] = p[0]
			var hero := _actor(0)
			if not hero.is_empty():
				hero["x"] = 246
				hero["y"] = 246
				s["player"] = {"x": 246, "y": 246}
			if not _populate():
				return false
			if p[1] > 0:
				s["warpPassed"][str(p[0])] = true
			_emit("map", {"mapId": p[0], "map": map})
			_emit("map-name", {"text": map.info.name_text})
			_actors()
		Op.CLEAR_ACTORS:
			s["actors"] = s["actors"].filter(func(a: Dictionary) -> bool: return a["id"] == 0)
			_actors()
			# 原生 `Evt_stdPROC:292-293`：opcode 0xC 连跟随对象一起 `Map_summonREMOVE/FREE`，
			# 所以清场之后剧情里一个跟随精灵都不显示，直到下一次地图加载／opcode 0xB 重建。
			_emit("summons-removed")
		Op.REMOVE_ACTOR:
			var removed := _actor(p[0])
			# Compare IDs, not Dictionary value equality or a fabricated actor.
			if not removed.is_empty():
				s["actors"] = s["actors"].filter(func(a: Dictionary) -> bool: return a["id"] != removed["id"])
			_actors()
		Op.PLACE_ACTOR:
			var id: int = 0 if p[0] <= 1 else p[0]
			var actor := _actor(id)
			if actor.is_empty():
				actor = _new_actor(id, point["x"], point["y"])
				s["actors"].append(actor)
			if p[1] != 0:
				actor["x"] = point["x"]
				actor["y"] = point["y"]
			# 方向表只有 4 项；越界时原生两次 objDIRECT(0)，direction_flags 与 code 都清零。
			var facing: int = PLACE_DIRECTION_FLAGS[p[2]] if p[2] >= 0 and p[2] <= 3 else 0
			var facing_code: int = PLACE_DIRECTION_CODES[p[2]] if p[2] >= 0 and p[2] <= 3 else 0
			actor["direction"] = facing
			actor["lastDirection"] = facing_code
			actor["action"] = FieldAction.Hero.IDLE
			actor.erase("animationEndMode")
			if id == 0:
				s["player"] = {"x": actor["x"], "y": actor["y"]}
			_actors()
		Op.MOVE_ACTOR:
			var actor := _actor(p[0])
			if actor.is_empty():
				return true
			var dx: float = point["x"] - actor["x"]
			var dy: float = point["y"] - actor["y"]
			if dx != 0 or dy != 0:
				var direction := (FieldAction.Facing.LEFT if dx < 0 else FieldAction.Facing.RIGHT) \
					if absf(dx) > absf(dy) else \
					(FieldAction.Facing.UP if dy < 0 else FieldAction.Facing.DOWN)
				actor["lastDirection"] = direction
				var old: int = actor["direction"]
				var retained := old & (FieldAction.VERTICAL_MASK if direction <= FieldAction.Facing.RIGHT else 3)
				actor["direction"] = (retained if retained != 0 else
					FieldAction.Facing.DOWN if direction <= FieldAction.Facing.RIGHT else
					FieldAction.Facing.LEFT) | direction
			actor["action"] = FieldAction.Hero.SCRIPT_WALK
			actor.erase("animationEndMode")
			_actors()
			var id := _emit("move", {"actor": actor, "destination": point, "follow": p[2] > 0})
			_motions[id] = {"actor": actor, "destination": point}
		Op.CAMERA:
			# `Evt_stdPROC` case 0x13 → `Evt_camSET(x, y, 0, p[1])`：`p[0]` 是
			# `瓦片 x * 100 + 瓦片 y`，`p[1]` 是 `CameraMode` 的模式号（不是帧数）。
			var camera_mode: int = p[1]
			if camera_mode > CameraMode.HALF_CONVERGE:
				# 原生 `Map_posFOCUS` 只认 1–4，其余取值两支都不置 `+32`，事件永远停在这一条。
				_block("原指令 %d 的镜头模式 %d 在原版里永不释放" % [Op.CAMERA, camera_mode])
				return false
			s["camera"] = null if camera_mode <= CameraMode.FOLLOW else \
				{"x": int(p[0] / 100), "y": p[0] % 100}
			if camera_mode <= CameraMode.INSTANT:
				# `n2 <= 0`（回到跟随）与 `n2 == 1`（当场 `Map_posFOCUS` 定位）都把 `+32` 置 1，
				# 所以这两条路径一步到位、不等待。
				_emit("focus", {"position": s["camera"] if s["camera"] != null else s["player"]})
			else:
				# 模式 2／3／4 只写 `+10`／`+14`／`+26`，`+32` 留给逐帧回调；
				# 收敛判定要用视口与地图尺寸，只有 field 侧知道，所以由它回调 `complete_camera`。
				_gate("camera", _emit("camera-pan",
					{"position": s["camera"], "mode": camera_mode}))
		Op.NARRATION:
			# Evt_scrInit／Evt_scrDRAW：CHT 组的每条记录是一页字幕，按版式全屏居中逐行显示。
			# `Evt_scrDRAW:18-35`／`:144-151` 对 1–3 之外的版式号走「`x = 0`、块心 `0`、不设字色」的
			# 兜底路径：整块画到屏幕外，但时间轴照常推进，所以这里不拦截、原样交给视图。
			var narration_source := "evt/evt%04d.cht" % s["eventId"]
			var narration := _load("load_dialogue", narration_source)
			if not boundary.is_empty():
				return false
			var narration_groups: Variant = narration.get("groups")
			if not narration_groups is Array or p[0] < 0 or p[0] >= narration_groups.size() or \
					not narration_groups[p[0]].get("records") is Array or \
					narration_groups[p[0]]["records"].is_empty():
				_block("CHT 组不存在或为空")
				return false
			_gate("narration", _emit("narration", {"source": narration_source, "group": p[0],
				"placement": p[1], "records": narration_groups[p[0]]["records"]}))
		Op.MAP_FILTER:
			# Evt_eftSET／Evt_eftRESET：MapData+46 存地图滤镜，0 无、1 灰、2 暗。
			# 其它值原样存下，但两个绘制函数都不会动作（Evt_eftSET 没有 else 分支，
			# Evt_eftRESET 只在 (+46 − 1) <= 1 时解锁），所以按「无滤镜」静默处理。
			_map_filter = p[0]
			var filter_mode: int = p[0] if p[0] in [MapFilter.GRAY, MapFilter.DARK] else MapFilter.NONE
			_emit("map-filter", {"mode": filter_mode})
		Op.FREE_RESOURCE:
			# Evt_stdPROC case 6：Object_resFREE(资源组, id) 只释放原生图片缓存。
			# 本移植的贴图由 AssetCatalog 按需加载，没有对应的常驻缓存可释放。
			pass
		Op.WAIT_ANIMATIONS:
			# case 0x10：等待所有对象播完当前动画（`animation_id != 0` 即仍在播）。
			_gate("animations")
		Op.PAUSE_OBJECTS:
			# case 0x16（`Evt_stdPROC:465`）：`EvtData+0x28`（`pause_objects`）整字节写入 `p[0]`，
			# 立即推进下一条。消费点 `Object_procRUN:13` 是 `!= 1` 比较，所以只有恰好 1 冻结整个
			# 对象池的逐帧推进，0 与其它取值都是恢复。
			_set_pause_objects(p[0])
		Op.EVENT_OBJECTS:
			if not _event_object_update(p):
				return false
			_emit("map-objects")
		Op.MOVE_RECTS:
			if not _move_rect_update(p):
				return false
		Op.HEAL_PARTY:
			if not _heal_party(p[0], p[1]):
				return false
		Op.MASTERY_SELECT:
			# case 0x20：Field_Basic_Capture() → GameCanvas_SetNext(GAME_STATE_CHARACTER_SELECT_15)
			# → 状态 16。两级都在这道门里：先六个流派候选，再所选流派的五只初始精灵。
			_mastery_stage = MasteryStage.MASTERY
			_gate("mastery", _emit("mastery-select", {"species": MASTERY_SPECIES.duplicate(),
				"stage": _mastery_stage}))
		Op.JUMP_AND_SAVE:
			# case 0x22：Heroine_Select 之后 Evt_stdINIT(选中 ? p[1] : p[0]) 并立即存档。
			# 本移植没有 heroine 数据，按「未选择」走 p[0]，不伪造 p[1] 分支。
			if not _jump_event(p[0]):
				return false
			_emit("save")
		Op.FADE:
			if p[0] < 0 or p[0] > 5:
				_block("未确认淡入淡出模式")
				return false
			var steps: Array[Dictionary] = []
			for tick in range(9):
				var opacity := 1.0 if p[0] == 5 else 0.0 if p[0] == 0 else \
					tick / 8.0 if p[0] <= 2 else 1.0 - tick / 8.0
				steps.append({"kind": "fade", "data": {
					"color": 0xffffff if p[0] in [2, 4] else 0, "alpha": opacity}})
			steps[-1]["final"] = {"kind": "fade", "data": {"color": 0, "alpha": 0.0}}
			_schedule(steps)
		Op.WAIT:
			# `Evt_stdPROC:306-325`：p[0] 帧数优先，其次 p[1] 秒（原生逐帧累加帧间隔到 `1000 * p[1]`）；
			# 两者都是 0 时原生就停在等待里（没有按键退出）。p[2] 是等待期间整屏填充色
			# （`Evt_stdPAINT2:21-33`，见 `WaitCover`）。
			var ticks: int = p[0] if p[0] > 0 else \
				int(ceil(p[1] / FramePacing.NATIVE_FRAME_SECONDS)) if p[1] > 0 else 0
			if ticks == 0:
				_block("原指令 %d 的空等待：原生会一直停在此处且不响应按键" % Op.WAIT)
				return false
			var blank := 0x000000 if p[2] == WaitCover.BLACK else 0xffffff if p[2] == WaitCover.WHITE else -1
			var steps: Array[Dictionary] = [{"ticks": ticks}]
			if blank >= 0:
				steps[0]["kind"] = "cover"
				steps[0]["data"] = {"enabled": true, "color": blank}
				steps[-1]["final"] = {"kind": "cover", "data": {"enabled": false}}
			_schedule(steps)
		Op.DIALOGUE:
			var source := "evt/evt%04d.cht" % s["eventId"]
			var document := _load("load_dialogue", source)
			var groups: Variant = document.get("groups")
			# Native 0x804e8..0x804fa; also preserved by qst.validate_links.
			var group: int = 42 if s["eventId"] == 2 and p[0] == 41 else p[0]
			if not groups is Array or group < 0 or group >= groups.size() or \
					not groups[group].get("records") is Array or groups[group]["records"].is_empty():
				_block("CHT 组不存在或为空")
				return false
			_gate("dialogue", _emit("dialogue", {"source": source, "group": group,
				"records": groups[group]["records"]}))
		Op.EMOTION:
			var actor := _actor(p[0])
			if not actor.is_empty():
				_set_emotion(actor, p[1], p[2])
				_actors()
		Op.INIT_PARAMETERS:
			# `Param_stdInit` 只写金钱、能力、进度这几项，**不碰** `warp_saved_*`
			# （那三项的初值来自 `Param_saveINIT` 的 memset 0），所以这里沿用已记录的上船位置。
			var previous: Dictionary = s["parameter"] if s["parameter"] is Dictionary else {}
			s["parameter"] = {"identity": p[0], "level": p[1], "moneyBalance": 0,
				"standardProgressPoints": 0, "trait": _roll(6),
				EXP_BONUS_KEY: 0,
				"development": initial_development(),
				"warp_saved_map_id": int(previous.get("warp_saved_map_id", WARP_SAVED_MAP_INITIAL)),
				"warp_saved_tile_x": int(previous.get("warp_saved_tile_x", WARP_SAVED_TILE_INITIAL)),
				"warp_saved_tile_y": int(previous.get("warp_saved_tile_y", WARP_SAVED_TILE_INITIAL))}
			# 同一条 `Param_stdInit` 调用也把第三参数写进 `guild_code_bits`（0x98172），
			# 所以公会码跟着重置（`events.tres` 的两处用法是 (0, 1, 99) 与 (1, 78, 1)）。
			s["guildCode"] = p[2]
			s["inventory"] = {}
			s["monsters"] = []
			s.erase("partyOrder")
		Op.ADD_MONSTER:
			var catalog: GameplayData = _gameplay()
			if catalog == null or catalog.monster(int(p[0])) == null:
				_block("缺少原物种 %d" % p[0])
				return false
			if s["monsters"].size() >= s["monsterCapacity"]:
				_block("原怪物背包已满")
				return false
			# 同一支 `Ball_stdSet`：`feel_value` 与 `brain_current` 都传 0、`food_value` 写死 100、
			# `brain_limit` 写死 99（`Evt_stdPROC` 的 0x1F 分支）。
			s["monsters"].append({"species": p[0], "level": p[1],
				"nativeArguments": p.duplicate(), "nickname": Battle.roll_nickname(_roll), "experience": 0,
				"feel": 0, "food": ItemEffect.FOOD_MAX,
				"brainCurrent": Battle.BRAIN_CURRENT_INITIAL, "brainLimit": Battle.BRAIN_LIMIT})
			Book.discover_monster(s, int(p[0]))
			# 原生事件建球同样经 `Ball_stdAddEx`，入包后清点一次精灵袋。
			_check_monster_quest(int(p[0]))
		Op.WARP_ENABLE: s["warpEnabled"][str(p[0])] = (p[1] & 255) == 1
		Op.REFRESH: _emit("changed")
		Op.NPC_RECORDS:
			# case 0x1C：事件 NPC 记录表（map_id、tile_x、tile_y、npc、direction_code），p[4] 非 0 时删除匹配项。
			if not _npc_record_update(p):
				return false
			_emit("actors")
		Op.SET_QUEST:
			s["quest"] = p[0]
			# 原生 `Evt_stdPROC@0x7EC3C:459-462`（case 0x15）：`Evt_stdQUEST(p)` 与
			# `ParamData.current_quest_progress = 0` 之后推 `Evt_msgSET(current_quest_text_resource, -1, 0)`，
			# 也就是 `Game_infoInit(0x94, "#C5"+任务标题+"(接受)")`（`Evt_msgSET@0x7CFC8:14-32`）。
			if p[0] >= 0:
				_emit("quest-set", {"questId": p[0]})
		Op.RELOAD_MAP:
			if not _populate():
				return false
		Op.SCREEN_EFFECT:
			if p[0] == ScreenEffect.MAP_EFFECT:
				# Evt_stdPROC case 3 子模式 5：match_parameter（p[2]）为 4 时
				# Map_eftSET(1, 3, 0, 0, 1)（整屏黑），其余值 Map_eftReset(1)。原生两种都立即推进。
				_map_effect = MapEffectCatalog.from_request(p[2])
				var map_effect_id := _emit("map-effect", _map_effect)
				if MapEffectCatalog.is_graded(int(_map_effect["tier"])):
					_gate("map-effect", map_effect_id)
			elif p[0] == ScreenEffect.CHT_DESTROY:
				# 子模式 6 只写 `EvtData+0x11`（`Evt_stdPROC:120-124`），下一帧
				# `Evt_stdPAINT2:88-92` 读到 1 才 `Evt_chtDESTROY()` 并清 0：销毁的是原版那扇
				# 常驻对话窗，`p[2] == 0` 时连这条也不做；两种取值都立即推进记录。
				# 工程的对话窗随 `Op.DIALOGUE` 的记录建立、那道门一收就拆，没有常驻窗可销毁，
				# 所以这里不画任何东西（曾经误当成全屏黑遮罩，把整段演出压成黑屏）。
				pass
			elif p[0] == ScreenEffect.SHAKE:
				var steps: Array[Dictionary] = []
				for offset in [[p[1], p[1]], [-p[1], p[1]], [p[1], -p[1]], [-p[1], -p[1]]]:
					steps.append({"kind": "shake", "data": {"x": offset[0], "y": offset[1]}})
				steps[-1]["final"] = {"kind": "shake", "data": {"x": 0, "y": 0}}
				_schedule(steps)
			elif p[0] == ScreenEffect.FLASH:
				var steps: Array[Dictionary] = []
				for tick in range(FLASH_FRAMES):
					steps.append({"kind": "fade", "data": {
						"color": 0xffffff,
						"alpha": float(maxi(0, FLASH_PEAK - FLASH_STEP * tick)) / float(FLASH_PEAK)}})
				_schedule(steps)
			else:
				_block("原画面效果 %d 的生命周期尚未接通" % p[0])
				return false
		Op.ACTOR_ANIMATION:
			var actor := _actor(p[0])
			if actor.is_empty():
				return true
			# `Evt_stdPROC` case 0xA：`Object_objANI(obj, p[1] + 100)` 后把 p[2] 原样写进
			# `animation_end_mode`。`Object_procNEXT` 只有 1（重播）与 2（停末帧）两个分支，
			# 0 走该 resource 的 next 回调而剧情动作 100..199 在回调里同样重播——所以只有 2 会停。
			if p[2] not in [AnimationEndMode.CALLBACK_OR_RESTART, AnimationEndMode.RESTART,
					AnimationEndMode.HOLD_LAST_FRAME]:
				_block("原 Object_procNEXT 结束模式 %d 不在原生枚举里" % p[2])
				return false
			actor["action"] = SCRIPTED_ANIMATION_FIRST + p[1]
			actor["animationEndMode"] = p[2]
			_actors()
		Op.BATTLE: return _start_battle(p[0])
		_:
			_block("原指令 %d 尚未实现；没有跳过或发放替代奖励" % opcode)
			return false
	return boundary.is_empty()


## case 0x1A：事件地图物件表（map_id、tile_x、tile_y、frame_code），p[3] 非 0 时删除匹配项。
func _event_object_update(p: Array) -> bool:
	var entry := [p[0], int(p[1] / 100), p[1] % 100, p[2]]
	if p[3] == 0:
		_event_objects.append(entry)
		return true
	for index in range(_event_objects.size()):
		if _event_objects[index] == entry:
			_event_objects.remove_at(index)
			break
	return true


## case 0x1B：通行矩形表（map_id、tile_x、tile_y、宽、高），p[3] 非 0 时撤掉匹配项。
func _move_rect_update(p: Array) -> bool:
	var entry := [p[0], int(p[1] / 100), p[1] % 100, int(p[2] / 100), p[2] % 100]
	if p[3] == 0:
		_move_rects.append(entry)
		return true
	for index in range(_move_rects.size()):
		if _move_rects[index] == entry:
			_move_rects.remove_at(index)
			break
	return true


## case 0x1C：事件 NPC 记录（map_id、tile_x、tile_y、npc、direction_code），p[4] 非 0 时删除匹配项。
func _npc_record_update(p: Array) -> bool:
	var entry := [p[0], int(p[1] / 100), p[1] % 100, p[2], p[3]]
	if p[4] == 0:
		progress["extraNpcs"].append(entry)
		return true
	for index in range(progress["extraNpcs"].size()):
		if progress["extraNpcs"][index] == entry:
			progress["extraNpcs"].remove_at(index)
			return true
	return true


## case 0x1D：`Ball_stdHP／Ball_stdSP(ball, 0, 百分比)`，只补当前值，不超上限。
func _heal_party(hp_percent: int, sp_percent: int) -> bool:
	var catalog: GameplayData = _gameplay()
	if catalog == null or not boundary.is_empty():
		return false
	for index: int in _party_indices():
		var member: Dictionary = progress["monsters"][index]
		var args: Array = member["nativeArguments"]
		var nickname: Variant = member.get("nickname")
		if not nickname is int or nickname < 0:
			_block("原队员 %d 缺少个体性格，无法计算上限" % index)
			return false
		var ball: Dictionary = Battle.make_ball(catalog,
			[args[0], args[1], -1, 0, 0, args[2], 0, 0, args[3], -1], nickname)
		var max_hp := int(ball.max_hp)
		var max_sp := int(ball.max_sp)
		member["hp"] = maxi(0, mini(max_hp,
			int(member.get("hp", max_hp)) + int(max_hp * hp_percent / 100)))
		member["sp"] = maxi(0, mini(max_sp,
			int(member.get("sp", max_sp)) + int(max_sp * sp_percent / 100)))
	return true


## 出战队伍（原生 `ItemData.party_monsters[0..2]`）。
func _party_indices() -> Array:
	var recorded: Variant = progress.get("partyOrder")
	if recorded is Array:
		return recorded
	var order: Array = []
	for index in range(mini(3, progress["monsters"].size())):
		order.append(index)
	return order


## 原生 `Map_tileSetMove` 的最终通行判定：事件矩形内可走，其余按地形标志。
## 规则实现只有一份，在 BattleMap.blocked()；这里只提供地图载荷与事件矩形。
func tile_blocked(x: int, y: int) -> bool:
	var terrain: Dictionary = map.get("terrain", {})
	return BattleMap.blocked(terrain, _move_rects, int(progress["mapId"]), Vector2i(x, y))


func map_filter() -> int:
	return _map_filter


## 当前全屏地图特效状态（原生 `MapData.reserved_0x152[2..9]`）。
func map_effect() -> Dictionary:
	return _map_effect.duplicate(true)


## 原生 Evt_stdINIT 把 MapData+46 清 0：换事件时地图滤镜复位。
func _reset_map_filter() -> void:
	if _map_filter == 0:
		return
	_map_filter = 0
	_emit("map-filter", {"mode": 0})


## 同一条 `Evt_stdINIT:29` 也调 `Map_eftReset(1)`：换事件时全屏特效复位。
func _reset_map_effect() -> void:
	if _map_effect.is_empty() or int(_map_effect["tier"]) == MapEffectCatalog.Kind.BLANK:
		return
	_map_effect = MapEffectCatalog.blank()
	_emit("map-effect", _map_effect)


## 原生 `Object_procRUN:13` 的整轮跳过条件：`EvtData.step_index > 0`（正在执行记录）
## 且 `EvtData+0x28`（`pause_objects`）`== 1`。标志本身只由 opcode 22 写（`Evt_stdPROC:465`）、
## `Evt_stdINIT` 不清，所以链尾与等触发器（`cursor == 0`，原生 `step_index == 0`）
## 时对象照常推进。
func objects_paused() -> bool:
	return _pause_objects and int(progress["cursor"]) > 0


## 原生 `Evt_stdPROC:465` 对 `EvtData+0x28` 的整字节写入点。
func _set_pause_objects(value: int) -> void:
	_pause_objects = value == PAUSE_OBJECTS_ON
	_emit("objects-paused", {"paused": _pause_objects})


## 当前地图上由 opcode 26 增删的事件物件（原生 event_map_object 表）。
func event_map_objects() -> Array:
	var result: Array = []
	for entry: Array in _event_objects:
		if int(entry[0]) != int(progress["mapId"]):
			continue
		result.append({"frame_id": int(entry[3]), "tile_x": int(entry[1]), "tile_y": int(entry[2])})
	return result


## 原生 `Evt_stdPROC` case 0x10：对象池里每个 `active_state > 0` 的对象都要
## `animation_id == 0` 才放行（见 wiki\field\field-animation-wait.md）。
## 表情不算「在播」：它画在对象自身的 +272／+273／+274，次数用完由 `Field_Emoticon_procSet` 清
## （`Field_Emoticon_procDraw`），不占对象池的 `animation_id`。
func _actors_animating() -> bool:
	for actor: Dictionary in progress["actors"]:
		if int(actor.get("action", 0)) != 0:
			return true
	return false


## 原生 `Evt_stdSET(3, 物种)`（`Battle_Win_SetResult` 每个敌人调一次）：当前事件还在等待
## 触发器 3、条件物品不足、物种匹配、`rand()%100 < 概率` 时，把该条件物品当战利品掉一件。
## 返回物品 id，-1 表示这次不掉。
func event_drop_for(species: int) -> int:
	if _disposed or not boundary.is_empty() or _step_index_idle or int(progress["cursor"]) != 0:
		return -1
	var records := _records(int(progress["eventId"]))
	if not boundary.is_empty() or records.is_empty():
		return -1
	var trigger: Dictionary = records[0]
	if int(trigger["opcode"]) != Trigger.ITEM_COUNT:
		return -1
	var p: Array = trigger["params"]
	if p[2] % 1000 != species % 1000:
		return -1
	if _item_count(p[0]) >= p[1]:
		return -1
	if _roll(100) >= p[3]:
		return -1
	return p[0]


## 原生 `EvtData.step_index` 的两个边界值：0 是 `Evt_stdINIT:20` 的初值（停在首记录等
## 触发器判定），−1 由 `:35` 写（事件链安静结束，工程用 `_step_index_idle` 表达）。中间的正数就是
## 正在执行／等待的那条记录下标。
const STEP_INDEX_TRIGGER := 0
const STEP_INDEX_ENDED := -1


## 当前事件步的两个原生字段：`Evt_stdSTYLE:32` 写 `EvtData.step_kind`、`:36` 写
## `EvtData.item_condition_parameter`，都按 `step_index` 从记录里取。`kind` 是记录首字节
## （停在首记录＝`Trigger`，执行指令＝`Op`），`parameter` 是其后第一个 int16——触发器 4 与
## `Qst_icoGET:17` 都把它当交互号／NPC 号。`index` 见上面两个常量。
func event_step() -> Dictionary:
	var index: int = STEP_INDEX_ENDED if _step_index_idle else int(progress["cursor"])
	var step := {"index": index, "kind": Trigger.ALWAYS, "parameter": 0}
	if index == STEP_INDEX_ENDED:
		return step
	var records := _records(int(progress["eventId"]))
	if not boundary.is_empty() or index >= records.size():
		return step
	var record: Dictionary = records[index]
	if not record.get("opcode") is int or not _integer_array(record.get("params"), 5):
		_block("原事件构造输入损坏")
		return step
	step["kind"] = int(record["opcode"])
	step["parameter"] = int(record["params"][0])
	return step


## 触发 4 的锁存入口：玩家在可交互对象上按确定（`Evt_stdSET(4, 定义号)`）。
func trigger_interaction(id: int) -> bool:
	if _disposed or not boundary.is_empty() or _step_index_idle or not _pending.is_empty():
		return false
	if int(progress["cursor"]) != 0:
		return false
	var records := _records(int(progress["eventId"]))
	if not boundary.is_empty() or records.is_empty():
		return false
	var trigger: Dictionary = records[0]
	if int(trigger["opcode"]) != Trigger.INTERACT_LATCH or int(trigger["params"][0]) != id:
		return false
	_trigger_latch = true
	pump()
	return true


func _add_inventory_item(item_id: int, quantity: int, blocking := true) -> bool:
	if item_id < 0 or quantity <= 0:
		_inventory_block("原添加物品指令参数未确认", blocking)
		return false
	var type := ItemKind.kind_of(item_id)
	if ItemKind.is_pseudo(type):
		match type:
			# 原生 `Item_stdAdd` 组 26 → `Param_moneySET(数量)`：直接加 `parameter.moneyBalance`，
			# 不入任何背包、不登记图鉴。事件 2 初始包的 `Op.ADD_ITEM(26000, 2000)` 就是 2000 块钱。
			ItemKind.Pseudo.MONEY:
				progress["parameter"]["moneyBalance"] = mini(MONEY_MAX,
					int(progress["parameter"].get("moneyBalance", 0)) + quantity)
			# 原生 `Item_stdAdd:93` 的组 25 → `Param_expSET(6u, 数量)`：数量直接加进主角
			# `player_progress`（余数 `development.experience`、等级 `parameter.level`），
			# 每升一级 `ability_points += 3`（＝ `development.points`）。
			ItemKind.Pseudo.EXPERIENCE:
				BattleSettlementModel.add_hero_experience(progress["parameter"], quantity)
			_:
				# 组 23／24：原生 `LABEL_58` 只把记录清零后返回成功，不入包也不报错。
				pass
		# 原生 `Item_stdAddEx@0x85BE4:47-59`：组 23–26 入账后一律由 `Item_datBasic` 填好的
		# detail_text（组 23／25「经验值」、组 24／26「金币」）与数量套 `JC_fxt2Return(415)`，
		# 最后 `Game_infoInit(0xFFFFFFFF, s)` 推一条**无图标**的入手提示。
		_emit("item-obtained", {"itemId": item_id, "count": quantity, "iconFrame": -1})
		return true
	var index := ItemKind.index_of(item_id)
	var catalog: GameplayData = _gameplay()
	if catalog == null or (blocking and not boundary.is_empty()):
		return false
	var record: ItemDefinition = catalog.item(item_id)
	if record == null or record.type != type or record.index != index:
		_inventory_block("原物品目录缺少 %d:%d" % [type, index], blocking)
		return false
	var bag := _item_bag(type, index)
	if bag < 0:
		_inventory_block("原物品类型 %d 没有可用背包" % type, blocking)
		return false

	var inventory: Dictionary = progress["inventory"]
	var existing_key := ""
	for key: Variant in inventory:
		if _canonical_numeric_key(str(key)) == str(item_id):
			if not existing_key.is_empty():
				_inventory_block("原物品背包存在重复数值键", blocking)
				return false
			existing_key = str(key)
	var previous: int = inventory[existing_key] if not existing_key.is_empty() else 0
	if previous + quantity > 65535:
		_inventory_block("原物品数量超出可保存范围", blocking)
		return false
	var occupied := 0
	for key: Variant in inventory:
		if str(key) == existing_key:
			continue
		var numeric_key := _canonical_numeric_key(str(key))
		if numeric_key.length() > 9:
			_inventory_block("原物品背包键无法判定容量分类", blocking)
			return false
		var existing_id := int(numeric_key)
		var existing_type := ItemKind.kind_of(existing_id)
		var existing_index := ItemKind.index_of(existing_id)
		if _item_bag(existing_type, existing_index) == bag:
			occupied += _stack_slots(int(inventory[key]),
				_item_max_stack(existing_type, existing_index))
	var final_slots := occupied + _stack_slots(previous + quantity,
		_item_max_stack(type, index))
	if final_slots > progress["itemCapacity"][bag]:
		_inventory_block("原物品包已满（分类 %d）" % bag, blocking)
		return false
	if existing_key.is_empty():
		existing_key = str(item_id)
	inventory[existing_key] = previous + quantity
	Book.discover_item(progress, item_id)
	# 原生 `Item_stdAddEx@0x85BE4:73-76`：普通道具真正进袋的分支推一条
	# `Game_infoInit(kind_specific_85_bits, fxt416)`，图标帧就是道具记录第 133 字节
	# （`ItemDefinition.icon`，`common/ui_item` 的帧号）。伪道具走 fxt415（无图标），不在此列。
	_emit("item-obtained", {"itemId": item_id, "count": quantity, "iconFrame": record.icon})
	# 原生 `Item_stdAddEx@0x85BE4:77-78`：入袋后先 `Qst_stdCHECK(2, 道具号)`（素材袋清点），
	# 再 `Evt_stdCHECK(3, 道具号)`（当前事件步的「持有数量」条件）。
	_check_material_quest(item_id)
	_check_event_item_quest(item_id)
	return true


## `Qst_stdCHECK@0x94004` 的推进：按槽里记录的 `goal_kind` 取数量，命中的槽各推一对进度提示。
## 提示文本由 `field_runtime` 按 `fromEvent` 选文本源（槽 = `qst/qstlist.fxt`，事件 = `evt/evtlist.fxt`）。
func _advance_quest_goals(goal_kind: int, target: int, amount: int, from_event := false) -> void:
	for report: Dictionary in quest_log().advance(goal_kind, target, amount):
		_emit("quest-progress", {"questId": int(report["quest"]),
			"count": int(report["count"]), "fromEvent": from_event})


## 原生 `Item_stdAddEx@0x85BE4:77` → `Qst_stdCHECK(2, 道具号)`：只有素材（第 3 组）会命中，
## 清点数就是素材袋里的持有量。
func _check_material_quest(item_id: int) -> void:
	if ItemKind.kind_of(item_id) != ItemKind.Kind.MATERIAL:
		return
	var index := ItemKind.index_of(item_id)
	_advance_quest_goals(QuestTable.GOAL_MATERIAL, index,
		QuestGoals.material_count(progress, index))


## 原生 `Ball_stdAddEx@0x85310:35` → `Qst_stdCHECK(1, 定义号)`：精灵袋里同一物种的个体数
## （排除上阵成员，`Ball_bagFindCount(a2 = 0)`）。
func _check_monster_quest(species: int) -> void:
	_advance_quest_goals(QuestTable.GOAL_MONSTER, species % ItemKind.ID_SCALE,
		QuestGoals.bag_monster_count(progress, species))


## 原生 `Evt_stdCHECK@0x7E3C4:8-28`：只在事件停在首步、触发条件就是「持有物品达到数量」
## 且物品号一致时推那一对提示；进度同样夹到条件数量。
func _check_event_item_quest(item_id: int) -> void:
	if int(progress["cursor"]) != 0 or int(progress["quest"]) < 0:
		return
	var records := _records(int(progress["eventId"]))
	if records.is_empty():
		return
	var trigger: Dictionary = records[0]
	var params: Array = trigger.get("params", [])
	if int(trigger["opcode"]) != Trigger.ITEM_COUNT or params.size() < 2 or \
			int(params[0]) != item_id:
		return
	var required := int(params[1])
	_emit("quest-progress", {"questId": int(progress["quest"]),
		"count": mini(_item_count(item_id), required), "fromEvent": true})


## 结算窗口的 `items` 阶段（`Battle_Win_mRun@0x322F0:173-191` 进入子状态 2）：这时经验与金币
## 已经发完、窗口还开着，原生逐件 `Item_stdAddEx`——入包并推 fxt416 入手提示。
## 经验与金币仍留给 `apply_battle_settlement`，所以这里不碰能力值、金币与队员记录。
func apply_battle_drops(settlement: RefCounted) -> Dictionary:
	var report := {"items": [], "full": []}
	if settlement == null:
		return report
	var key := settlement.get_instance_id()
	if _battle_drops.has(key):
		return _battle_drops[key]
	var drops: Variant = settlement.get("items")
	if drops is Array:
		for item: Dictionary in drops:
			var item_id := int(item.get("id", -1))
			var count := int(item.get("count", 0))
			if item_id < 0 or count <= 0:
				continue
			if _add_battle_drop(item_id, count):
				report.items.append(item_id)
			else:
				report.full.append(item_id)
	# 原生 `Battle_Win_mRun@0x322F0:192-197` 在同一子状态紧接着对每只在场敌人
	# `Qst_stdCHECK(0, 定义号)`，所以「击倒 N 只」的进度提示与入手提示同一刻进栈。
	_check_defeated_monster_quests()
	_battle_drops[key] = report
	return report


## 战斗胜利结算的唯一入口（原生 `Battle_Win_SetResult`）：奖励与掉落由 `BattleSettlement` 算，
## 掉落入包走本文件唯一的背包规则（`Item_stdAddEx@0x85BE4`），因此会推 fxt416 入手提示与素材任务进度；
## 随后按 `Battle_Win_mRun@0x322F0:192-197` 对每只在场的敌人推进「击倒 N 只」类任务。
## 掉落已在窗口的 `items` 阶段入包（`apply_battle_drops`）时，这里只写回经验与金币，报告沿用那次结果。
func apply_battle_settlement(settlement: RefCounted) -> Dictionary:
	var granted: Variant = _battle_drops.get(settlement.get_instance_id())
	var report: Dictionary = settlement.apply(progress,
		_keep_granted_drop if granted is Dictionary else _add_battle_drop)
	if granted is Dictionary:
		report.items = granted.get("items", [])
		report.full = granted.get("full", [])
		_battle_drops.erase(settlement.get_instance_id())
	else:
		# 没有经历结算窗口的路径（直接驱动模型）在这里补一次击倒类任务的清点。
		_check_defeated_monster_quests()
	return report


## 原生 `Battle_Win_mRun@0x322F0:192-197`：对每只在场敌人推进「击倒 N 只」类任务。
func _check_defeated_monster_quests() -> void:
	if combat == null:
		return
	for index in range(3):
		var ball: Dictionary = combat.balls[index]
		if not ball.is_empty():
			_check_monster_quest(Battle.combat_species(int(ball.species)))


## 结算掉落的背包入口：与剧情同一条规则；背包满只告警，不把事件推进边界（原生 `Param_ballFULL`）。
func _add_battle_drop(item_id: int, count: int) -> bool:
	return _add_inventory_item(item_id, count, false)


## `BattleSettlement.apply()` 再列一遍掉落时的回执：掉落已由 `apply_battle_drops` 入包，
## 这里只回答「已在包里」，既不重复写背包，也不重复推 fxt416 入手提示。
func _keep_granted_drop(_item_id: int, _count: int) -> bool:
	return true


## 原生 `Qst_chtKeyPress@0x943A0:72-80`：接取后按任务自己的 `goal_kind` 现场清点一次，
## 已有数量立刻以 `[N/M]` 提示出来（1 → 精灵袋，2 → 素材袋）。
func refresh_quest_goal(quest_id: int) -> void:
	var goal := quest_log().goal_of(quest_id)
	if goal.is_empty():
		return
	var target := int(goal["target"])
	match int(goal["kind"]):
		QuestTable.GOAL_MONSTER:
			_check_monster_quest(target)
		QuestTable.GOAL_MATERIAL:
			_advance_quest_goals(QuestTable.GOAL_MATERIAL, target,
				QuestGoals.material_count(progress, target))


## `blocking` 为 false 的调用（如开宝箱）只报告失败，不把事件执行器推进边界。
func _inventory_block(message: String, blocking: bool) -> void:
	if blocking:
		_block(message)
	else:
		push_warning(message)


func _delete_inventory_item(item_id: int, quantity: int) -> bool:
	if item_id < 0 or quantity <= 0:
		_block("原删除物品指令参数未确认")
		return false
	var type := ItemKind.kind_of(item_id)
	var index := ItemKind.index_of(item_id)
	var catalog: GameplayData = _gameplay()
	if catalog == null or not boundary.is_empty():
		return false
	var record: ItemDefinition = catalog.item(item_id)
	if record == null or record.type != type or record.index != index:
		_block("原物品目录缺少 %d:%d" % [type, index])
		return false
	if _item_bag(type, index) < 0:
		_block("原物品类型 %d 没有可用背包" % type)
		return false

	var inventory: Dictionary = progress["inventory"]
	var existing_key := ""
	for key: Variant in inventory:
		if _canonical_numeric_key(str(key)) == str(item_id):
			if not existing_key.is_empty():
				_block("原物品背包存在重复数值键")
				return false
			existing_key = str(key)
	if existing_key.is_empty() or inventory[existing_key] < quantity:
		_block("原物品数量不足；未执行部分删除")
		return false
	var remaining: int = inventory[existing_key] - quantity
	if remaining == 0:
		inventory.erase(existing_key)
	else:
		inventory[existing_key] = remaining
	return true


## 原生 `Field_Item_Buy_Price`：总价 = 记录首 dword（购买价）× 数量。
static func shop_buy_price(record: ItemDefinition, quantity: int) -> int:
	if record == null or quantity <= 0 or record.purchase_price < 0:
		return 0
	return int(record.purchase_price) * quantity


## 原生 `Field_Item_Sell_Price`：第 2／4 组每件固定 100，其余「购买价 / 2」× 数量。
static func shop_sell_price(record: ItemDefinition, quantity: int) -> int:
	if record == null or quantity <= 0:
		return 0
	if record.type in [ItemKind.Kind.EQUIPMENT, ItemKind.Kind.SKILL_BOOK]:
		return SELL_FIXED_PRICE * quantity
	if record.purchase_price < 0:
		return 0
	return quantity * int(int(record.purchase_price) / 2)


## 原生 `Field_Item_Buy_mKeyPressed`：钱够就 `Item_stdAddEx` 入包再 `Param_moneySET(-总价)`。
## 返回空串表示成功，否则是给页面显示的拒绝原因。
func buy_item(item_id: int, quantity: int) -> String:
	if progress.is_empty() or not boundary.is_empty():
		return "存档尚未载入或流程被拦住"
	var catalog: GameplayData = _gameplay()
	if catalog == null:
		return "原道具目录未载入"
	var total := shop_buy_price(catalog.item(item_id), quantity)
	if total <= 0:
		return "原物品目录缺少 %d 的购买价" % item_id
	var money := int(progress["parameter"].get("moneyBalance", 0))
	if money < total:
		return "金币不足"
	if not _add_inventory_item(item_id, quantity):
		return "背包放不下这些道具"
	progress["parameter"]["moneyBalance"] = money - total
	return ""


## 原生 `Field_Item_Sell_mKeyPressed`：有货就扣货再 `Param_moneySET(+总价)`。
func sell_item(item_id: int, quantity: int) -> String:
	if progress.is_empty() or not boundary.is_empty():
		return "存档尚未载入或流程被拦住"
	var catalog: GameplayData = _gameplay()
	if catalog == null:
		return "原道具目录未载入"
	var total := shop_sell_price(catalog.item(item_id), quantity)
	if total <= 0:
		return "原物品目录缺少 %d 的出手价" % item_id
	if not consume_item(item_id, quantity):
		return "背包里没有这么多"
	progress["parameter"]["moneyBalance"] = mini(MONEY_MAX,
		int(progress["parameter"].get("moneyBalance", 0)) + total)
	return ""


## 原生 `Field_Inn_mKeyPressed`：钱 **> 49** 时扣 50 并把三名出战队员的 HP／SP 回满
## （`Ball_stdHP／Ball_stdSP(ball, 0, 100)`），钱不够就什么都不做。
func inn_rest() -> String:
	if progress.is_empty() or not boundary.is_empty():
		return "存档尚未载入或流程被拦住"
	var money := int(progress["parameter"].get("moneyBalance", 0))
	if money < INN_COST:
		return "金币不足，无法住宿"
	if not _heal_party(100, 100):
		return "无法恢复队伍"
	progress["parameter"]["moneyBalance"] = money - INN_COST
	return ""


## 任务奖励入账（`Field_Quest_Complete_SetResult` 的副作用）。`model` 是
## `scripts/field/quest_reward.gd` 的 `QuestReward`：金钱、主角与队员的等级／经验、属性进度由模型的
## `apply()` 按战斗结算同一套阈值写回；道具走本文件唯一的背包规则（`_add_inventory_item`）。
## 返回 `{"items": 已入包道具号, "full": 背包满未入包的道具号}`。
func grant_quest_reward(model: RefCounted) -> Dictionary:
	if progress.is_empty():
		return {"items": [], "full": []}
	var report: Dictionary = model.apply(progress, _gameplay())
	for item: Dictionary in model.items:
		var id := int(item.get("id", 0))
		var count := int(item.get("count", 0))
		if id > 0 and count > 0 and _add_inventory_item(id, count, false):
			report.items.append(id)
		else:
			report.full.append(id)
	return report


## 战斗内消耗道具（原生 `Battle_Capture_Action_IsCapture` 里的 `Item_stdDel(item, 1, 1)`）。
## 与 `_delete_inventory_item` 的区别：战斗中的扣除失败不进事件边界，只返回 false。
func consume_item(item_id: int, quantity: int) -> bool:
	if item_id < 0 or quantity <= 0 or progress.is_empty():
		return false
	var inventory: Variant = progress.get("inventory", {})
	if not inventory is Dictionary:
		return false
	var existing_key := ""
	for key: Variant in inventory:
		if _canonical_numeric_key(str(key)) == str(item_id):
			existing_key = str(key)
			break
	if existing_key.is_empty() or not inventory[existing_key] is int or \
			int(inventory[existing_key]) < quantity:
		return false
	if int(inventory[existing_key]) == quantity:
		inventory.erase(existing_key)
	else:
		inventory[existing_key] = int(inventory[existing_key]) - quantity
	return true


## 原生 `Battle_Drop_BOX`：`rand() % 表长` 抽一条 `(道具号, 数量)`。
## 选表看该地图在世界地图记录里的列号（`Map_worldGET` 的 +38）：> 99（室内层）用 27 条表，
## 其余用 22 条表。表里的 26000 是组 26 伪道具（`Item_stdAdd` 的 `Param_moneySET`），
## 抽到它等于发这笔钱；入包失败（包满等）时按原生的「什么都没有」（msg.fxt:94）处理。
static func box_drop(interior: bool, roll: int) -> Dictionary:
	var table: Array = BOX_DROPS_INTERIOR if interior else BOX_DROPS_OUTDOOR
	var row: Array = table[clampi(roll, 0, table.size() - 1)]
	return {"id": int(row[0]), "count": int(row[1])}


## 原生 `Map_boxIsExist(map_id)`：该地图的宝箱是否还没开过（存档位为 0 才存在）。
func box_opened(map_id: int) -> bool:
	return progress.get("openedBoxes", []).has(map_id)


## 原生 `Field_Box_mRun`（相位 4→6）：先把该地图的宝箱记为已开
## （`Map_boxSetExist(map_id, 0)` 置位），再 `Battle_Drop_BOX` 抽一件道具入包。
## 包满或目录里没有该道具时原生只显示 msg.fxt:94，宝箱同样算开过。
func open_box(map_id: int, interior: bool) -> Dictionary:
	if _disposed or progress.is_empty():
		return {"ok": false, "error": "存档尚未载入"}
	if box_opened(map_id):
		return {"ok": false, "error": "该地图的宝箱已经开过"}
	var table_size := BOX_DROPS_INTERIOR.size() if interior else BOX_DROPS_OUTDOOR.size()
	var drop := box_drop(interior, _roll(table_size))
	var boxes: Array = progress.get("openedBoxes", [])
	boxes.append(map_id)
	boxes.sort()
	progress["openedBoxes"] = boxes
	return {"ok": true, "item": drop,
		"added": _add_inventory_item(int(drop.id), int(drop.count), false)}


## 原生 `Ball_stdAdd`：捕获到的个体进怪物背包，`Param_bookSetMonster(定义号 % 1000, 1)`
## 登记图鉴。背包满时原生 `Ball_stdAdd` 返回空指针、什么也不加，这里同样只报错不入包。
func capture_monster(record: Dictionary) -> String:
	if _disposed or progress.is_empty():
		return "存档尚未载入"
	var monsters: Array = progress["monsters"]
	if monsters.size() >= int(progress["monsterCapacity"]):
		return "怪物背包已满，捕获到的精灵没有入包"
	monsters.append(record)
	Book.discover_monster(progress, int(record["species"]))
	# 原生捕获走 `Ball_stdAddEx@0x85310:35`，入包后清点一次精灵袋。
	_check_monster_quest(int(record["species"]))
	return ""


## 出场的 10 个构造参数：物种、等级、成长、`brain_current`、觉醒值、觉醒档、被动号、被动等级、装备索引、占位。
## 原生建球只走 `Ball_stdSet` → `Item_stdSet` → `Item_datBasic`，
## 那里按 `物种号 % 1000` 查 `item_mon` 组（`0x843D8` 的 `v6 = … % 1000`，所以 `物种 + 1000` 的觉醒形态
## 落回同一组），唯一的失败是查不到记录；`Ball_stdAdd` 入包也只按 `% 1000` 记图鉴、不看物种种类
## （`MonsterDefinition.kind` 只参与被动 0／1、31／32、37／38 的选取，见 `battle.gd` 顶部）。
## 所以这里**不按 `kind` 挡人**：出货的 24 场脚本战斗里 13 场拿 `kind = 1` 的物种当敌人。
func _constructor_valid(catalog: GameplayData, args: Array) -> bool:
	if not _integer_array(args, 10):
		return false
	var species: MonsterDefinition = catalog.monster(int(args[0]))
	if species == null or not _integer_array(species.ability_inputs, 6) or \
			not _integer_array(species.attribute_inputs, 6):
		return false
	if args[7] > 0:
		var passive: PassiveDefinition = catalog.passive(int(args[6]))
		if passive == null or passive.effect < 0 or passive.effect >= 66:
			return false
	if args[8] >= 0:
		var item: ItemDefinition = catalog.item(2000 + int(args[8]))
		if item == null or item.detail_slots.size() < 14:
			return false
	return true


func _start_battle(id: int) -> bool:
	var catalog: GameplayData = _gameplay()
	if catalog == null:
		return false
	var config: ScriptBattleDefinition = catalog.script_battle(id)
	if config == null or config.constructors.size() != 3:
		_block("缺少原脚本战斗配置 %d" % id)
		return false
	_battle_order = progress.get("partyOrder", range(mini(3, progress["monsters"].size()))).duplicate()
	if _battle_order.size() != 3:
		_block("原脚本战斗 %d 需要三名出战队员；当前队伍不足" % id)
		return false
	var args_list: Array = []
	for row: PackedInt32Array in config.constructors:
		args_list.append(Array(row))
	for index: int in _battle_order:
		var member: Dictionary = progress["monsters"][index]
		var args: Array = member["nativeArguments"]
		args_list.append([args[0], args[1], -1, 0, 0, args[2], 0, 0, args[3], -1])
	for args: Variant in args_list:
		if not args is Array or not _constructor_valid(catalog, args):
			_block("原脚本战斗 %d 构造输入损坏" % id)
			return false
	var balls: Array = []
	for index in range(6):
		# 对手侧没有记录，按 `Ball_stdSet` 掷一个；我方侧照抄记录里的性格，缺记录时同样掷一次。
		var nickname := Battle.NICKNAME_UNSPECIFIED if index < 3 else int(
			progress["monsters"][_battle_order[index - 3]].get("nickname", Battle.NICKNAME_UNSPECIFIED))
		nickname = Battle.nickname_or_roll(nickname, _roll)
		var member_slots: Array = []
		if index >= 3:
			member_slots = progress["monsters"][_battle_order[index - 3]].get("passiveSlots", [])
		var ball := Battle.make_ball(catalog, args_list[index], nickname, member_slots)
		if not BattleSpeciesTable.has(Battle.combat_species(int(ball["species"]))) or not \
				ball["passives"].all(func(_n: Variant) -> bool: return _n is int):
			_block("原脚本战斗 %d 的物种 %d 缺少动作分段" % [id, int(ball["species"])])
			return false
		if index >= 3:
			var member: Dictionary = progress["monsters"][_battle_order[index - 3]]
			for stat: String in ["hp", "sp"]:
				if member.has(stat):
					ball[stat] = mini(int(member[stat]), int(ball["max_" + stat]))
			ball["feel"] = int(member.get("feel", 0))
			ball["food"] = int(member.get("food", ItemEffect.FOOD_MAX))
		for effect in range(ball["passives"].size()):
			if ball["passives"][effect] != 0 and not Battle.SUPPORTED_PASSIVE_EFFECTS.has(effect):
				_block("原脚本战斗 %d 的被动效果 %d 尚未还原" % [id, effect])
				return false
		balls.append(ball)
	for index in range(3):
		progress["monsters"][_battle_order[index]]["nickname"] = balls[index + 3]["nickname"]
	combat = Battle.new(balls.slice(0, 3), balls.slice(3, 6), _random)
	combat.catalog = catalog
	_gate("battle")
	progress["cursor"] += 1
	var records := _records(progress["eventId"])
	if not boundary.is_empty():
		return false
	if progress["cursor"] >= records.size() and not _next_event():
		return false
	trace.append("Game6:Game_Guild_Battle_init(%d)→Game3(type4)" % id)
	_battle_returned = false
	_battle_effect = _emit("battle", {"scriptId": id})
	_pending["id"] = _battle_effect
	return true


## 任务槽视图：返回的是包在 `progress["quests"]` 同一份字典上的句柄，
## 改槽（接取／推进／完成）即写进存档状态，`save_store` 落盘自然带走。
func quest_log() -> QuestLog:
	if not progress.has("quests") or not QuestLogModel.validate(progress["quests"]):
		progress["quests"] = QuestLogModel.empty_dict()
	return QuestLogModel.new(progress["quests"])


## The scene runs the emitted combat model; outcomes are never supplied/invented
## by the caller. Only BattleModel's terminal result can release this gate.
## `settlement` 是胜利时战斗视图算好的 `BattleSettlement`（原生状态 26 `Battle_Win_SetResult`）：
## 由它发经验、金币与掉落，故事层只负责写回进度并继续事件。
## 败北按战后触发器的 opcode（原生 `EvtData.step_kind`，见 `pump` 的说明）分两支：
## 8 → 队伍回满并继续剧情，其余 → `game-over`（`Game_out()` 回标题）。
func complete_battle(id: int, settlement: RefCounted = null) -> bool:
	if _disposed or not boundary.is_empty() or _pending.get("kind") != "battle" or \
			id != _battle_effect or combat == null or combat.result == null:
		return false
	var party: Array = combat.balls.slice(3, 6)
	for index in range(3):
		var member: Dictionary = progress["monsters"][_battle_order[index]]
		member["hp"] = party[index]["hp"]
		member["sp"] = party[index]["sp"]
		# 战斗里吃食物改的是球记录上的 `feel_value`／`food_value`（原生 `Ball_stdFeel`／`Ball_stdFood`）。
		member["feel"] = party[index].get("feel", 0)
		member["food"] = party[index].get("food", ItemEffect.FOOD_MAX)
		# 心情到顶时 `Ball_stdFeel` 直接改记录本身：物种号 +1000（记录的 `species`
		# 仍存基础号）与标准被动槽 2–5。本工程用 `nativeArguments[2]` 的觉醒档表达，
		# 战斗球把它放在 `native_arguments[5]`。
		var party_args: Variant = party[index].get("native_arguments")
		if party_args is Array and party_args.size() > 5 and member.get("nativeArguments") is Array:
			member["nativeArguments"][2] = int(party_args[5])
	var records := _records(progress["eventId"])
	if not boundary.is_empty():
		return false
	var trigger: int = records[0]["opcode"]
	if combat.result == "won":
		var grant: RefCounted = settlement
		if grant == null:
			# 没有战斗视图（例如直接驱动模型）时按同一套原生规则结算，不另造奖励。
			grant = BattleSettlementModel.new(combat, progress, _gameplay(), _random)
		apply_battle_settlement(grant)
		# 原生 `Battle_Win_mKeyPressed` 的子状态 2：只有 `EvtData.step_kind ∈ {7, 8}`（战斗之后那个
		# 事件的触发器是 7／8）才把「已打回来」标志置 1，其余触发器直接
		# `EFC_mainSetNEXT(GAME_STATE_FIELD, 1)` 回地图、不置标志。
		_battle_returned = trigger in [Trigger.BATTLE_RETURNED, Trigger.BATTLE_RETURNED_ALT]
		trace.append("Battle_Win:结算经验/金币/掉落→Evt_stdNEXT")
		_finish_pending()
		return true
	if combat.result == "lost" and trigger == Trigger.BATTLE_RETURNED_ALT:
		# 原生 `Battle_Position_mRun` 末尾：只有 `EvtData.step_kind == 8` 才
		# `Param_ballFULL(0)` ＋ 置标志，也就是这一场允许打输（队伍回满后剧情继续）。
		for index in range(3):
			progress["monsters"][_battle_order[index]]["hp"] = party[index]["max_hp"]
			progress["monsters"][_battle_order[index]]["sp"] = party[index]["max_sp"]
		trace.append("Battle_Position:全队HP=0→Param_ballFULL(0)→evt trigger8 flag")
		_battle_returned = true
		_finish_pending()
		return true
	# 其余触发器（含 7「必须打赢」与 0–6、9）走状态 28 DIE，确认后 `Game_out()` 回标题：
	# 不返回地图、不结算、不置标志。存档文件没有被写过，读档即可回到战前。
	_pending = {}
	_battle_returned = false
	trace.append("Battle_Die:Game_out→标题")
	_emit("game-over", {"detail": "原事件战败北（战后触发器 %d）" % trigger})
	return true


func after_move(destination_map: Dictionary, position: Dictionary, through_warp: bool = false) -> void:
	if _disposed or not boundary.is_empty() or not _point_valid(position) or not destination_map.has("id"):
		return
	var changed: bool = progress["mapId"] != destination_map["id"]
	map = destination_map
	progress["mapId"] = map["id"]
	progress["player"] = position.duplicate()
	var hero := _actor(0)
	if not hero.is_empty():
		hero["x"] = position["x"]
		hero["y"] = position["y"]
	if changed and not _populate():
		return
	if changed:
		_emit("map", {"mapId": progress["mapId"], "map": map})
	if through_warp:
		_emit("map-name", {"text": map.info.name_text})
	_emit("focus", {"position": position})
	_actors()
	pump()


func stable_state() -> Dictionary:
	# This is a native in-memory snapshot, not a persistence implementation.
	if running or not _pending.is_empty() or not _motions.is_empty() or progress["cursor"] != 0:
		return {}
	var state := progress.duplicate(true)
	for actor: Dictionary in state.actors:
		actor.erase("wild")
	return state
