extends "res://tests/unit/gut_case.gd"

const Story = preload("res://engine/data/story/story.gd")
const Battle = preload("res://game/battle/combat/battle.gd")
const Book = preload("res://game/menu/book/book_model/book_model.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const MapEffectCatalog = preload("res://game/field/map/map_effect.gd")
const QuestMarkModel = preload("res://game/field/quests/quest_mark/quest_mark.gd")
const ItemKind = preload("res://game/menu/item/item_kind/item_kind.gd")
const MonsterAttribute = preload("res://game/growth/monster_attribute/monster_attribute.gd")
## `item_basic.dat` 第 1 组第 3 号在原生表里的 `ui_item` 帧号（记录第 133 字节，`gameplay.tres` 同值）。
const CONSUMABLE_ICON_FRAME := 3

class FixtureProvider extends RefCounted:
	var events: Dictionary = {}
	var maps: Dictionary = {
		0: {"id": 0, "info": {"name_text": "起点地图", "npcs": [], "monster_spawns": []}},
	}
	var gameplay: GameplayData = Fixtures.battle_catalog()
	var dialogue: Dictionary = {"groups": [{"records": [{"text": "原对话 fixture"}]}]}

	func _resource(payload: Dictionary) -> Resource:
		var resource := Resource.new()
		resource.set_meta("payload", payload)
		return resource

	func load_map(id: int) -> Resource:
		return _resource(maps.get(id, {}))

	func load_event(id: int) -> Resource:
		return _resource(events.get(id, {}))

	func has_event(id: int) -> bool:
		return events.has(id)

	func load_dialogue(_id: String) -> Resource:
		return _resource(dialogue)

	func load_gameplay() -> GameplayData:
		return gameplay


class FakeSettlement extends RefCounted:
	var applied := false
	var rows: Array = [{"experience_gain": 120}]
	var money := 300
	var items: Array = []

	func apply(_progress: Dictionary, _add_item: Callable) -> Dictionary:
		applied = true
		return {"items": [], "full": []}


func _record(opcode: int, params: Array = [0, 0, 0, 0, 0]) -> Dictionary:
	return {"opcode": opcode, "params": params}


func _provider(instructions: Array) -> FixtureProvider:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(0)] + instructions}
	provider.events[1] = {"records": [_record(1, [99, 0, 0, 0, 0]), _record(21, [777, 0, 0, 0, 0])]}
	return provider


func _story(provider: FixtureProvider, state: Dictionary = {}) -> RefCounted:
	var story = Story.new(provider, state if not state.is_empty() else Story.initial_progress(0, 2),
		func(_limit: int) -> int: return 0)
	story.initialize()
	return story


func test_legacy_suite() -> void:
	var initial := Story.initial_progress(0)
	assert_true(Story.validate_progress(initial, 0) and not Story.validate_progress(initial, 1),
		"initial progress validates only for its own slot")
	# 公会码：初值是原生 `Param_stdInit(0, 1, 0x63)` 的 99（最差名次），落在 Story 的 1..99 里。
	var guild_code = initial.get("guildCode", null)
	assert_true(guild_code is int and guild_code >= 1 and guild_code <= 99 and
		Story.validate_progress(initial, 0), "初始进度带合法公会码 99")
	var bad_guild := initial.duplicate(true)
	bad_guild["guildCode"] = 100
	assert_true(not Story.validate_progress(bad_guild, 0), "越界的公会码被拒绝")
	# 老存档只在 `parameter.rank` 里记过公会码：initialize() 迁到唯一键 `guildCode` 并删旧键。
	var legacy_guild := initial.duplicate(true)
	legacy_guild.erase("guildCode")
	legacy_guild["parameter"]["rank"] = 42
	var migrated = _story(_provider([]), legacy_guild)
	assert_true(migrated.progress["guildCode"] == 42 and
		not migrated.progress["parameter"].has("rank"),
		"老存档的 parameter.rank 迁到 guildCode 后只剩一处")
	# 上船位置：新档只剩 `Param_saveINIT` 的 memset 0（`Param_stdInit` 不碰三项），
	# 唯一写入点是 `Field_Warp1_mKeyPressed` 的 −5 分支。
	var parameter: Dictionary = initial["parameter"]
	assert_eq([int(parameter["warp_saved_map_id"]), int(parameter["warp_saved_tile_x"]),
		int(parameter["warp_saved_tile_y"])], [0, 0, 0], "新档上船位置与原生 memset 0 同源")
	var story = _story(_provider([_record(21, [12, 0, 0, 0, 0]), _record(21, [13, 0, 0, 0, 0])]))
	assert_true(story.progress["quest"] == 13 and story.progress["eventId"] == 1 and
		story.progress["cursor"] == 0,
		"sequential instructions run to the event end before the next trigger")
	var invalid := initial.duplicate(true)
	invalid["monsterCapacity"] = 21
	assert_true(not Story.validate_progress(invalid, 0), "malformed native state is rejected")
	# 经验加成窗口（`ParamData.standard_progress + 7`）随存档保存：过一遍 JSON 序列化
	# （存档文件的写法）后仍是同一个毫秒数，`validate_progress` 也放行。
	var saved := initial.duplicate(true)
	saved["parameter"][Story.EXP_BONUS_KEY] = Story.EXP_BONUS_MILLISECONDS
	var restored: Dictionary = Story.normalize_integer_types(
		JSON.parse_string(JSON.stringify(saved)))
	assert_eq([Story.validate_progress(restored, 0),
		int(restored["parameter"][Story.EXP_BONUS_KEY])],
		[true, Story.EXP_BONUS_MILLISECONDS], "经验加成窗口随存档往返并保留剩余毫秒")


## 本轮补齐的事件执行器分支：触发器 4 锁存、opcode 28 删除、opcode 29 回复、opcode 4 字幕门。
func test_event_instruction_gaps() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(4, [7, 0, 0, 0, 0]),
		_record(28, [42, 1212, 2, 1, 0]), _record(28, [42, 1212, 2, 1, 1]),
		_record(21, [5, 0, 0, 0, 0])]}
	var story = _story(provider)
	assert_true(story.progress["quest"] == 0 and story.trigger_interaction(6) == false,
		"trigger 4 only latches on the recorded interaction id")
	assert_true(story.trigger_interaction(7) and story.progress["quest"] == 5 and
		story.progress["extraNpcs"].is_empty(),
		"matching interaction starts the event and opcode 28 deletes the NPC record")

	var healed: Dictionary = Story.initial_progress(0, 2)
	healed["monsters"] = [{"species": 49, "level": 10, "nativeArguments": [49, 10, 0, -1, 0],
		"nickname": 0, "experience": 0, "hp": 1, "sp": 0}]
	healed["partyOrder"] = [0]
	var heal_story = _story(_provider([_record(29, [100, 100, 0, 0, 0])]), healed)
	var ball := Battle.make_ball(heal_story._gameplay(),
		[49, 10, -1, 0, 0, 0, 0, 0, -1, -1], 0)
	assert_eq([heal_story.progress["monsters"][0].get("hp"),
		heal_story.progress["monsters"][0].get("sp")], [int(ball.max_hp), int(ball.max_sp)],
		"opcode 29 restores party HP/SP by percentage of the maximum")

	# 触发器 3 的事件掉落：击杀对应物种时把条件物品当战利品。
	var drop_provider := FixtureProvider.new()
	drop_provider.events[0] = {"records": [_record(3, [6004, 5, 112, 100, 0]),
		_record(21, [9, 0, 0, 0, 0])]}
	var drop_story = _story(drop_provider)
	assert_eq([drop_story.event_drop_for(112), drop_story.event_drop_for(7)], [6004, -1],
		"trigger 3 drops its required item only for the recorded species")


## 任务图标码 5（`Qst_icoGET:15-17`）：判的是事件步的两个字段，不是事件号。
func test_event_step_state() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(Story.Trigger.INTERACT_LATCH, [7, 0, 0, 0, 0])]}
	var story = _story(provider)
	var step: Dictionary = story.event_step()
	assert_eq([step["index"], step["kind"], step["parameter"]],
		[Story.STEP_INDEX_TRIGGER, Story.Trigger.INTERACT_LATCH, 7],
		"event_step 读首记录的 step_kind 与交互号")
	assert_eq([QuestMarkModel.event_step_code(step, 7), QuestMarkModel.event_step_code(step, 8)],
		[QuestMarkModel.Code.EVENT, QuestMarkModel.Code.NONE],
		"只有被等的那一个对象拿事件任务码 5")
	var running = _story(_provider([_record(Story.Op.DIALOGUE, [0, 0, 0, 0, 0])]))
	var busy: Dictionary = running.event_step()
	assert_true(busy["index"] > Story.STEP_INDEX_TRIGGER and QuestMarkModel.suppresses_marks(busy) and
		QuestMarkModel.event_step_code(busy, 0) == QuestMarkModel.Code.NONE,
		"执行记录中不产任何任务图标")
	var ended := FixtureProvider.new()
	ended.events[0] = {"records": [_record(Story.Trigger.ALWAYS)]}
	var done = _story(ended)
	assert_eq(done.event_step()["index"], Story.STEP_INDEX_ENDED, "事件链结束按原生 step_index = -1")


## 触发 6（区域调查）：主角在矩形里做出动作 3／4 后锁存，动作回到 0 才让事件开跑。
## 采矿（帧 152）与摇树（第 0 组帧 0／5／10）的原版奖励就走这条。
func test_area_action_trigger() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(Story.Trigger.AREA_ACTION, [0, 808, 101, 0, 0]),
		_record(21, [9, 0, 0, 0, 0])]}
	var story = _story(provider)
	assert_true(story.pending_area_action(), "主角在区域里且事件停在触发 6 时优先走原版事件")
	var hero: Dictionary = story.progress["actors"][0]
	hero["action"] = 3
	story.pump()
	assert_eq(story.progress["quest"], 0, "调查动作播放期间只锁存，不提前开事件")
	hero["action"] = 0
	story.pump()
	assert_eq(story.progress["quest"], 9, "动作结束后的下一帧才跑 opcode 21")
	var outside = _story(provider)
	outside.progress["player"]["x"] = 20
	outside.progress["actors"][0]["x"] = 20
	assert_true(not outside.pending_area_action(), "区域外不算等待中的调查事件")


## 战斗结算 / 任务奖励：经验与金币用组 23／24 伪道具各推一条 fxt415（无图标）。
func test_settlement_gain_messages() -> void:
	var story = _story(_provider([]))
	story.take_effects()
	story.apply_battle_settlement(FakeSettlement.new())
	var obtained: Array = story.take_effects().filter(func(effect: Dictionary) -> bool:
		return effect.kind == "item-obtained")
	assert_eq(obtained.map(func(effect: Dictionary) -> Array:
		return [int(effect.itemId), int(effect.count), int(effect.iconFrame)]),
		[[23000, 120, -1], [24000, 300, -1]],
		"经验与金币按原版各推一条「获得经验值／金币」提示")


## 通用采集入口：兜底材料走与开宝箱同一条非阻塞入包口径。
func test_gather_item() -> void:
	var story = _story(_provider([]))
	var result: Dictionary = story.gather_item(1000, 2)
	assert_true(result.get("ok", false), "采集材料入包成功")
	assert_eq(int(story.progress["inventory"].get("1000", 0)), 2, "材料数量写进背包")
	assert_true(not story.gather_item(0, 1).get("ok", false), "非法道具号被拒绝")


## P1-3 的商店与旅店数值：`Field_Item_Buy_Price`（购买价 × 数量）、
## `Field_Item_Sell_Price`（第 2／4 组每件 100，其余购买价 / 2）、
## `Field_Inn_mKeyPressed`（钱 > 49 时扣 50 并把出战三人 HP／SP 回满）。
func test_shop_and_inn() -> void:
	var catalog := Fixtures.battle_catalog()
	catalog.items.append(Fixtures.item({"id": 1001, "type": 1, "index": 1,
		"purchase_price": 120}))
	var provider := _provider([])
	provider.gameplay = catalog
	var state := Story.initial_progress(0, 2)
	state["monsters"] = [{"species": 49, "level": 10, "nativeArguments": [49, 10, 0, -1, 0],
		"nickname": 0, "experience": 0, "hp": 1, "sp": 0}]
	state["partyOrder"] = [0]
	state["parameter"]["moneyBalance"] = 1000
	var story = _story(provider, state)
	var bought: String = story.buy_item(1001, 2)
	var after_buy := int(story.progress["parameter"]["moneyBalance"])
	var sold: String = story.sell_item(1001, 1)
	assert_eq([bought, after_buy, sold, int(story.progress["parameter"]["moneyBalance"]),
		int(story.progress["inventory"].get("1001", 0))], ["", 760, "", 820, 1],
		"buying charges the record price per unit and selling refunds half")
	var rested: String = story.inn_rest()
	var ball := Battle.make_ball(story._gameplay(), [49, 10, -1, 0, 0, 0, 0, 0, -1, -1], 0)
	assert_eq([rested, int(story.progress["parameter"]["moneyBalance"]),
		int(story.progress["monsters"][0].get("hp"))], ["", 770, int(ball.max_hp)],
		"an inn stay costs 50 and refills the party")


## 捕获入包（原生 `Ball_stdAdd`：进怪物背包 + `Param_bookSetMonster` 登记图鉴），
## 以及捕获球的扣除（`Item_stdDel`）。
func test_capture_party_add() -> void:
	var story = _story(_provider([]))
	story.progress["inventory"] = {"5001": 1}
	var record := {"species": 49, "level": 10, "nativeArguments": [49, 10, 0, -1, 0],
		"nickname": 0, "experience": 0}
	assert_true(story.capture_monster(record).is_empty() and
		story.progress["monsters"].size() == 1 and
		story.progress["book"][Book.BOOK_MONSTERS].has(49) and
		story.consume_item(5001, 1) and story.progress["inventory"].is_empty(),
		"a captured individual joins the box, is recorded in the book and consumes its ball")


## 原生 `FieldCanvas_load`：进入野外画布时 HP 归 0 的个体恢复 1 HP（只改 HP，不动 SP；
## 记录里没有 `hp` 键的个体按「未记录当前值＝满血」处理，不碰）。
func test_downed_monsters_restore_to_one_hp() -> void:
	var story = _story(_provider([]))
	story.progress["monsters"] = [
		{"species": 49, "hp": 0, "sp": 7, "nativeArguments": [49, 10, 0, -1, 0]},
		{"species": 62, "hp": 3, "sp": 2, "nativeArguments": [62, 10, 0, -1, 0]},
		{"species": 86, "nativeArguments": [86, 10, 0, -1, 0]},
	]
	var restored: int = story.restore_downed_monsters()
	assert_eq([restored, int(story.progress["monsters"][0]["hp"]),
		int(story.progress["monsters"][0]["sp"]),
		int(story.progress["monsters"][1]["hp"]),
		story.progress["monsters"][2].has("hp")], [1, 1, 7, 3, false],
		"field load restores downed monsters to 1 HP, leaves SP and unknown HP alone")


## 宝箱（原生 `Field_Box_mRun` 的相位 4→6：记已开、抽 `Battle_Drop_BOX`、入包）。
func test_map_box_open() -> void:
	var provider := _provider([])
	provider.gameplay = Fixtures.data({"items": [{"id": 1003, "type": 1, "index": 3}]})
	var story = _story(provider)
	var first: Dictionary = story.open_box(7, false)
	assert_true(first.get("ok", false) and int(first.item.id) == 1003 and
		int(first.item.count) == 5 and first.get("added", false) and story.box_opened(7) and
		int(story.progress["inventory"].get("1003", 0)) == 5,
		"a chest hands out its table drop once and records the map as opened")
	assert_true(not story.open_box(7, false).get("ok", false) and
		Story.validate_progress(story.progress, 0),
		"the same chest cannot be opened twice and the opened list stays valid")


## T-C2 任务槽：`ParamData.quests[11]`（槽 0 公会任务、1..10 普通任务）的接取／推进／完成，
## 判定照 `Qst_stdQuest`（前置／公会档／事件号区间）与 `Qst_stdEmpty` 的区间选择。
func test_quest_slots() -> void:
	var table: QuestTable = QuestSet.load_table()
	var context := {"guild_code": 0, "event_id": 0}
	var log: QuestLog = _story(_provider([])).quest_log()
	# NPC 33 的链上只有 46 号（goal_kind 0、目标物种 6、数量 5），接取后落在普通槽。
	assert_true(log.accept(table, 46) and log.is_active(46) and log.slot_of(46) >= QuestLog.SLOT_FIRST_NORMAL,
		"accept writes the quest into the 1..10 normal slots")
	# NPC 30 的 43 号两段前置都是「必须已完成」（39／40），都未完成时整条链都不给。
	assert_eq(log.available(table, 30, context), [], "unmet prerequisites keep the quest out of available")
	# 推进到 5 再完成：进完成位图、槽位释放，46 不可重复所以链头变空。
	log.advance(QuestTable.GOAL_PROGRESS, 6, 5)
	log.complete(46)
	assert_true(log.is_completed(46) and not log.is_active(46) and
		log.available(table, 33, context).is_empty(),
		"completing records the bit, frees the slot and empties a non-repeatable chain")


## 任务进度提示：原生 `Item_stdAddEx@0x85BE4:73-78` 先推 416 入手提示，再按素材袋清点
## （`Qst_stdCHECK(2, 道具号)`），最后按事件步条件清点（`Evt_stdCHECK(3, 道具号)`）。
## 战斗掉落走同一个背包入口，所以也带这两条提示。
func test_quest_progress_prompt() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(Story.Trigger.ITEM_COUNT, [3000, 2, 0, 0, 0])]}
	provider.gameplay = Fixtures.data({"items": [{"id": 3000, "type": 3, "index": 0}]})
	var story = _story(provider)
	story.take_effects()
	story.progress["quest"] = 7
	story.progress["quests"]["slots"][QuestLog.SLOT_FIRST_NORMAL] = {
		"marker": QuestLog.CONTEXT_NPC, "npc": 1, "quest": 46,
		"goal_kind": QuestTable.GOAL_MATERIAL, "goal_target": 0, "goal_count": 3, "progress": 0}
	story._add_battle_drop(3000, 1)
	var first: Array = story.take_effects()
	assert_eq(first.map(func(effect: Dictionary) -> String: return effect.kind),
		["item-obtained", "quest-progress", "quest-progress"],
		"an item entering the bag pushes the obtain notice, then the quest and event progress")
	assert_eq([int(first[1].questId), int(first[1].count), bool(first[1].fromEvent),
		int(first[2].questId), int(first[2].count), bool(first[2].fromEvent)],
		[46, 1, false, 7, 1, true],
		"the material slot uses the quest text source, the event step uses the event one")
	story._add_battle_drop(3000, 1)
	var second: Array = story.take_effects()
	assert_eq([int(second[2].questId), int(second[2].count)], [7, 2],
		"the event progress follows the live held count on the next pickup")


## 事件战败北（`Battle_Position_mRun` 末尾）：只有战后触发器 8 才 `Param_ballFULL(0)` ＋ 置标志
## 让剧情继续；触发器 7（必须打赢）与其余触发器都走状态 28 DIE → `Game_out()` 回标题。
func test_event_battle_defeat() -> void:
	for trigger: int in [Story.Trigger.BATTLE_RETURNED_ALT, Story.Trigger.BATTLE_RETURNED,
			Story.Trigger.MAP]:
		var story = _lost_story(trigger)
		var completed: bool = story.complete_battle(story._battle_effect)
		var healed: bool = int(story.progress["monsters"][0].get("hp", 0)) > 0
		var quit: bool = story.take_effects().any(func(effect: Dictionary) -> bool:
			return effect.kind == "game-over")
		assert_true(completed and healed == (trigger == Story.Trigger.BATTLE_RETURNED_ALT) and
			quit == (trigger != Story.Trigger.BATTLE_RETURNED_ALT),
			"a lost event battle resumes only for the post-battle trigger %d" % trigger)


## P0-8：事件 2 的初始包带 `Op.ADD_ITEM(26000, 2000)`。原生 `Item_stdAdd` 的组 26 走
## `Param_moneySET`，所以它直接进 `parameter.moneyBalance`，不进任何背包。
func test_pseudo_money_item() -> void:
	var provider := _provider([_record(Story.Op.ADD_ITEM, [26000, 2000, 0, 0, 0]),
		_record(Story.Op.ADD_ITEM, [1003, 20, 0, 0, 0])])
	provider.gameplay = Fixtures.data({"items": [
		{"id": 1003, "type": 1, "index": 3, "icon": CONSUMABLE_ICON_FRAME}]})
	var story = _story(provider)
	var inventory: Dictionary = story.progress["inventory"]
	assert_eq(int(story.progress["parameter"]["moneyBalance"]), 2000, "组 26 直接加钱")
	assert_true(inventory.size() == 1 and int(inventory.get("1003", 0)) == 20,
		"钱不进背包，后面的真道具照常入包")
	assert_true(story.boundary.is_empty(), "伪道具不落事件边界")
	# 原生 `Item_stdAddEx@0x85BE4:56-58`：组 23–26 入账后推一条 fxt415 的无图标提示；
	# 普通道具 `:73-76` 的提示把记录第 133 字节（`kind_specific_85_bits`）当图标帧。
	var obtained: Array = story.take_effects().filter(func(effect: Dictionary) -> bool:
		return effect.kind == "item-obtained")
	assert_true(obtained.size() == 2 and int(obtained[0].iconFrame) == -1 and
		int(obtained[0].count) == 2000,
		"组 26 的「获得金币」提示无图标（`Item_stdAddEx@0x85BE4:58` 传 0xFFFFFFFF）")
	assert_true(int(obtained[1].iconFrame) == CONSUMABLE_ICON_FRAME and
		int(obtained[1].count) == 20,
		"道具入手提示带 ui_item 帧号（`Item_stdAddEx@0x85BE4:76`）")


## P2-231：组 25 伪道具走 `Param_expSET(6u, 数量)`——数量进主角经验余量
## （`development.experience`），阈值按 `Param_expINIT` 的主角式 `65 × 等级²` 逐级扣、
## 等级写 `parameter.level`，每升一级 `ability_points += 3`（`development.points`）；
## 99 级封顶且余数清零（`point_remainder = level != 99 ? 余数 : 0`）。
func test_pseudo_experience_item() -> void:
	var experience_id := ItemKind.id_of(ItemKind.Pseudo.EXPERIENCE, 0)
	var story = _story(_provider([_record(Story.Op.ADD_ITEM, [experience_id, 200, 0, 0, 0])]))
	var development: Dictionary = story.progress["parameter"]["development"]
	assert_true(int(story.progress["parameter"]["level"]) == 2 and
		int(development["experience"]) == 135 and int(development["points"]) == 3 and
		story.boundary.is_empty() and story.progress["inventory"].is_empty() and
		Story.validate_progress(story.progress, 0),
		"组 25 加英雄经验：65 点升一级并给 3 点能力点，余 135 不到下一级 260；不入包且存档仍合法")
	var capped: Dictionary = Story.initial_progress(0, 2)
	capped["parameter"]["level"] = MonsterAttribute.LEVEL_MAX
	var story_capped = _story(_provider([_record(Story.Op.ADD_ITEM,
		[experience_id, 5000, 0, 0, 0])]), capped)
	var capped_development: Dictionary = story_capped.progress["parameter"]["development"]
	assert_true(int(story_capped.progress["parameter"]["level"]) == MonsterAttribute.LEVEL_MAX and
		int(capped_development["experience"]) == 0 and int(capped_development["points"]) == 0,
		"99 级再吃经验不升级、余数清零")


## P0-8：脚本战斗的敌人可以是 `kind = 1` 的物种。原生建球只走 `Ball_stdSet` →
## `Item_stdSet` → `Item_datBasic` 的 `物种号 % 1000` 查表，没有物种种类闸门，
## 而出货表里 13 场脚本战斗的敌人就是 `kind = 1`（例如 51 的 31、75 的 92）。
## 觉醒档（构造参数第 6 项 = 1）按原生把物种号写成 +1000，被动照常进 `passives[效果号]`。
func test_script_battle_accepts_kind_one_species() -> void:
	var provider := _provider([_record(Story.Op.BATTLE, [9, 0, 0, 0, 0])])
	provider.gameplay = Fixtures.data({
		"monsters": [
			{"id": 31, "kind": 1, "ability_inputs": [26, 26, 25, 24, 22, 22],
				"attribute_inputs": [21, 7, 25, 5, 8, 7]},
			{"id": 49, "kind": 0, "ability_inputs": [14, 13, 12, 11, 17, 16],
				"attribute_inputs": [16, 4, 22, 2, 11, 2]},
		],
		"passives": [{"id": 162, "effect": 64, "base": 33, "increment": 1}],
		"script_battles": {9: {"constructors": [
			[31, 10, 0, 0, 0, 1, 162, 1, -1, -1],
			[31, 10, 0, 0, 0, 0, 0, 0, -1, -1],
			[31, 10, 0, 0, 0, 0, 0, 0, -1, -1]]}},
	})
	var state: Dictionary = Story.initial_progress(0, 2)
	var members: Array = []
	for _index in range(3):
		members.append({"species": 49, "level": 10, "nativeArguments": [49, 10, 0, -1, 0],
			"nickname": 0, "experience": 0, "hp": 0, "sp": 0})
	state["monsters"] = members
	state["partyOrder"] = [0, 1, 2]
	var story = _story(provider, state)
	assert_true(story.boundary.is_empty() and story.combat != null,
		"kind = 1 的敌人不再被判成构造输入损坏")
	assert_eq([int(story.combat.balls[0]["species"]), int(story.combat.balls[0]["passives"][64])],
		[1031, 33], "觉醒档写成物种 + 1000，被动 64 的数值进表")


## 地图全屏特效（`wiki\field\map-effects.md`）与地图滤镜：opcode 3 子模式 5 的「开／关」两档，
## 以及 opcode 5 的未知值按原生静默忽略（不再报 boundary）。
func test_map_effect_tiers() -> void:
	var story = _story(_provider([
		_record(Story.Op.SCREEN_EFFECT,
			[Story.ScreenEffect.MAP_EFFECT, 0, MapEffectCatalog.BLACKOUT_PARAMETER, 0, 0]),
		_record(Story.Op.SCREEN_EFFECT, [Story.ScreenEffect.MAP_EFFECT, 0, 0, 0, 0])]))
	var tiers: Array = []
	for effect: Dictionary in story.take_effects():
		if effect.kind == "map-effect":
			tiers.append(int(effect.tier))
	assert_eq(tiers, [MapEffectCatalog.Kind.BLACK, MapEffectCatalog.Kind.BLANK],
		"子模式 5：match_parameter 4 → 整屏黑，其余值 → 复位")
	# 3 = `MapFilter.DARK` 之后的下一个值，原生两个绘制函数都当它不存在。
	var inert = _story(_provider([
		_record(Story.Op.MAP_FILTER, [Story.MapFilter.DARK + 1, 0, 0, 0, 0])]))
	var modes: Array = []
	for effect: Dictionary in inert.take_effects():
		if effect.kind == "map-filter":
			modes.append(int(effect.mode))
	assert_true(inert.boundary.is_empty() and not modes.is_empty() and
		not modes.has(Story.MapFilter.GRAY) and not modes.has(Story.MapFilter.DARK),
		"未确认的地图滤镜值按原生静默：不再 _block，也不切任何滤镜")


## 事件镜头（`Evt_camSET`／`wiki\event\event-camera.md`）：`p[1]` 是 `Map_posFOCUS`
## 的模式号而不是帧数——0／1 立即放行，2 起停在等待里，直到 field 侧收敛后 `complete_camera`。
func test_event_camera_modes() -> void:
	var instant = _story(_provider([
		_record(Story.Op.CAMERA, [1807, Story.CameraMode.INSTANT, 0, 0, 0]),
		_record(21, [7, 0, 0, 0, 0])]))
	var instant_target_focused := false
	for effect: Dictionary in instant.take_effects():
		if effect.kind == "focus" and effect.position == {"x": 18, "y": 7}:
			instant_target_focused = true
	assert_true(instant_target_focused and instant.progress["quest"] == 7,
		"模式 1：一步定位到瓦片 (18, 7) 并继续执行下一条指令")
	var follow = _story(_provider([
		_record(Story.Op.CAMERA, [1807, Story.CameraMode.FOLLOW, 0, 0, 0]),
		_record(21, [8, 0, 0, 0, 0])]))
	var follow_targeted := false
	for effect: Dictionary in follow.take_effects():
		if effect.kind == "focus" and effect.position == {"x": 18, "y": 7}:
			follow_targeted = true
	assert_true(follow.progress["quest"] == 8 and not follow_targeted,
		"模式 0：镜头交回英雄，同样不等待")

	var pan = _story(_provider([
		_record(Story.Op.CAMERA, [1807, Story.CameraMode.PAN_FAST, 0, 0, 0]),
		_record(21, [9, 0, 0, 0, 0])]))
	var pan_id := -1
	for effect: Dictionary in pan.take_effects():
		if effect.kind == "camera-pan":
			pan_id = int(effect.id)
	pan.advance(1.0)
	assert_eq([pan_id > 0, pan._pending.get("kind"), pan.progress["quest"]], [true, "camera", 0],
		"模式 2：停在镜头等待，时间推进也不放行，后续指令仍未执行")
	assert_true(pan.complete_camera(pan_id) and pan.progress["quest"] == 9,
		"收敛到位后 complete_camera 放行并继续执行后续指令")


## 造一场「已打完并输掉」的事件战：战后事件（eventId）的触发器是 `trigger`，
## 队伍三只写在 progress 里，`combat.result` 直接置 `lost`。
func _lost_story(trigger: int) -> RefCounted:
	var provider := FixtureProvider.new()
	# 触发器 1（MAP）用不存在的地图号，保证 initialize() 时事件停在门口不进记录。
	var params: Array = [99 if trigger == Story.Trigger.MAP else 0, 0, 0, 0, 0]
	provider.events[0] = {"records": [_record(trigger, params), _record(21, [9, 0, 0, 0, 0])]}
	var story = _story(provider)
	var members: Array = []
	for _index in range(3):
		members.append({"species": 49, "level": 10, "nativeArguments": [49, 10, 0, -1, 0],
			"nickname": 0, "experience": 0, "hp": 0, "sp": 0})
	story.progress["monsters"] = members
	story.progress["partyOrder"] = [0, 1, 2]
	story._battle_order = [0, 1, 2]
	var balls: Array = []
	for _index in range(6):
		balls.append(Battle.make_ball(story._gameplay(), [49, 10, -1, 0, 0, 0, 0, 0, -1, -1], 0))
	story.combat = Battle.new(balls.slice(0, 3), balls.slice(3, 6),
		func(_limit: int) -> int: return 0)
	for ball: Dictionary in story.combat.balls:
		ball.hp = 0
	story.combat.result = "lost"
	story._battle_returned = false
	story._battle_effect = story._emit("battle", {"scriptId": 1})
	story._pending = {"kind": "battle", "id": story._battle_effect, "eventId": 0,
		"cursor": 1, "opcode": 33}
	story.take_effects()
	return story


## 事件链末端（`wiki\event\event-end.md`）：后继号在事件表里不存在时，原生 `Evt_stdNEXT:14`
## 照样 `Evt_stdINIT(102)`，`Evt_stdSTYLE` 取不到资源就把 `EvtData.step_index` 置 −1，
## `Evt_stdPROC:92` 随即返回 0 → 安静结束、野外拿回控制权，不是数据缺损。
func test_chain_end_without_successor() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [_record(Story.Trigger.ALWAYS), _record(21, [3, 0, 0, 0, 0])]}
	var story = _story(provider)
	assert_true(story.boundary.is_empty() and not story.running and story._pending.is_empty() and
		story.progress["eventId"] == 1 and story._step_index_idle,
		"后继事件不存在时安静结束：不落边界、无待办效果、事件号前进到不存在的 1")
	assert_true(not story.trigger_interaction(0), "安静结束后不再轮询触发器（原生 step_index = -1）")
	story.pump()
	assert_true(story.boundary.is_empty() and story.progress["eventId"] == 1,
		"pump 不再重试加载缺失事件")

	var jumping := FixtureProvider.new()
	jumping.events[0] = {"records": [_record(Story.Trigger.ALWAYS),
		_record(Story.Op.JUMP, [99, 0, 0, 0, 0])]}
	var jump_story = _story(jumping)
	assert_true(jump_story.boundary.is_empty() and jump_story._step_index_idle and
		jump_story.progress["eventId"] == 99,
		"跳转目标不存在时同样安静结束（跳转分支也是 Evt_stdINIT）")

	var continued = _story(_provider([_record(21, [3, 0, 0, 0, 0])]))
	assert_true(continued.boundary.is_empty() and not continued._step_index_idle and
		continued.progress["eventId"] == 1 and continued.progress["cursor"] == 0,
		"存在的后继事件照原样继续（event 1 的触发器 1 在等地图号 99）")


## opcode 16 的放行条件照 `Evt_stdPROC` case 0x10：所有活动对象的 `animation_id` 都为 0
## 才继续；表情画在对象自身的 +272／+274（`Field_Emoticon_procDraw`），不在判定里。
## 见 wiki\field\field-animation-wait.md。
func test_wait_animations_gate() -> void:
	var story = _story(_provider([_record(Story.Op.MOVE_ACTOR, [0, 305, 0, 0, 0]),
		_record(Story.Op.WAIT_ANIMATIONS), _record(21, [9, 0, 0, 0, 0])]))
	var move_id := -1
	for effect: Dictionary in story.take_effects():
		if effect.kind == "move":
			move_id = int(effect.id)
	assert_true(move_id >= 0 and int(story.progress["quest"]) == 0,
		"角色还有移动动作时 opcode 16 不放行")
	assert_true(story.complete_effect(move_id), "移动到位后动作清成待机")
	story.advance(0.0)
	assert_eq(int(story.progress["quest"]), 9, "对象动作清零后放行到下一条记录")

	var emotive = _story(_provider([_record(Story.Op.EMOTION, [0, 7, 1, 0, 0]),
		_record(Story.Op.WAIT_ANIMATIONS), _record(21, [11, 0, 0, 0, 0])]))
	emotive.advance(0.0)
	assert_eq([int(emotive.progress["quest"]), emotive.progress["actors"][0].emotion], [11, 7],
		"挂着表情不算「在播」：opcode 16 照常放行")

## 初始精灵选择（`Evt_stdPROC` case 0x20）：`Game_Character_Select_init` 的六个
## 流派候选 → `Game_Book_Monster_init:18-26` 的五只候选 → `:38-94` 入队。
## 见 wiki\growth\starter-select.md。
func test_starter_select() -> void:
	var provider := FixtureProvider.new()
	provider.gameplay = Fixtures.data({"monsters": [
		{"id": 4, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		{"id": 5, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		# 同伴两只（`Game_Book_Monster_mKeyPressed:85-94`）：流派 0 → 组 (0+4)%6=4、(0+2)%6=2，
		# 夹具的随机数恒取组内第一只，所以是 88／44。
		{"id": 44, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		{"id": 88, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
	]})
	provider.events[0] = {"records": [_record(Story.Op.NONE),
		_record(Story.Op.MASTERY_SELECT), _record(Story.Op.SET_QUEST, [17, 0, 0, 0, 0])]}
	var story = _story(provider)
	var first := _mastery_effect(story)
	assert_eq([first.get("species"), int(first.get("stage"))],
		[Story.MASTERY_SPECIES, Story.MasteryStage.MASTERY],
		"一级给出六个流派候选（Game_Character_Select_init）")
	assert_true(story.complete_mastery(int(first.get("id", -1)), 0),
		"一级确认写 preferredMastery 并换到二级候选")
	var second := _mastery_effect(story)
	assert_eq([int(story.progress["parameter"]["preferredMastery"]), second.get("species")],
		[0, [4, 5, 6, 7, 8]],
		"二级候选是 22 * 流派 + 4 .. + 8（Game_Book_Monster_init）")
	var starter_id := int(second.get("id", -1))
	assert_true(story.return_mastery() and story.complete_mastery(starter_id, 0),
		"二级 BACK 退回一级后仍能重新确认流派")
	var again := _mastery_effect(story)
	assert_true(story.complete_mastery(int(again.get("id", -1)), 1),
		"二级确认把选中的那只入包并放行事件")
	assert_eq([story.progress["monsters"].size(), int(story.progress["monsters"][0]["species"]),
		int(story.progress["monsters"][0]["level"]), story.progress["partyOrder"],
		story.progress["book"][Book.BOOK_MONSTERS], int(story.progress["quest"])],
		[3, 5, 1, [0, 1, 2], [5, 44, 88], 17],
		"选中的那只等级 1 入包并进队伍，另赠两只同伴一起进队，事件继续跑到后面的记录")
	assert_eq([int(story.progress["monsters"][1]["species"]) / Book.MONSTER_SLOTS,
		int(story.progress["monsters"][2]["species"]) / Book.MONSTER_SLOTS],
		[(0 + 4) % Story.MASTERY_SPECIES.size(), (0 + 2) % Story.MASTERY_SPECIES.size()],
		"两只同伴分别落在「流派 + 4」「流派 + 2」那一组（Game_Book_Monster_mKeyPressed:85-94）")
	assert_true(Story.validate_progress(story.progress, 0), "入队后的进度仍能通过存档校验")


## 取最近一次流派选择效果（`initialize` 会先发地图／角色这类无关键）。
func _mastery_effect(story: RefCounted) -> Dictionary:
	var found: Dictionary = {}
	for effect: Dictionary in story.take_effects():
		if effect.get("kind") == "mastery-select":
			found = effect
	return found


## 新手剧情的临时精灵回收。事件 0 用 `Op.ADD_MONSTER`（`Evt_stdPROC` case 0x1F）给三只
## 等级 66 的临时精灵（`events.tres` 事件 0 的 49／62／86），事件 2 末尾先
## `Op.INIT_PARAMETERS`（`Param_stdInit` → `Ball_bagInit`／`Item_bagInit`：清背包与角色状态，
## 但**不动**图鉴位图），再由初始精灵确认的 `Game_Book_Monster_mKeyPressed:42-69`
## 把 132 位怪物图鉴清零并登记新的三只。所以过完剧情后背包／图鉴／队伍都只剩确认的那三只。
func test_starter_select_recycles_prologue_monsters() -> void:
	var provider := FixtureProvider.new()
	provider.gameplay = Fixtures.data({"monsters": [
		{"id": 5, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		{"id": 44, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		{"id": 88, "kind": 0, "attribute_group": 1,
			"ability_inputs": [32, 37, 35, 35, 34, 33], "attribute_inputs": [21, 9, 27, 7, 10, 7]},
		{"id": 49, "kind": 0, "attribute_group": 3,
			"ability_inputs": [14, 13, 12, 11, 17, 16], "attribute_inputs": [16, 4, 22, 2, 11, 2]},
		{"id": 62, "kind": 0, "attribute_group": 3,
			"ability_inputs": [45, 43, 42, 41, 47, 45], "attribute_inputs": [19, 7, 25, 5, 14, 5]},
		{"id": 86, "kind": 0, "attribute_group": 4,
			"ability_inputs": [55, 54, 53, 53, 52, 57], "attribute_inputs": [21, 9, 25, 7, 10, 11]},
	]})
	provider.events[0] = {"records": [_record(Story.Op.NONE),
		_record(Story.Op.ADD_MONSTER, [49, 66, 0, 64, 0]),
		_record(Story.Op.ADD_MONSTER, [62, 66, 0, 60, 0]),
		_record(Story.Op.ADD_MONSTER, [86, 66, 0, 62, 0]),
		_record(Story.Op.INIT_PARAMETERS, [0, 1, 99, 0, 0]),
		_record(Story.Op.MASTERY_SELECT),
		_record(Story.Op.SET_QUEST, [1, 0, 0, 0, 0])]}
	var story = _story(provider)
	var first := _mastery_effect(story)
	assert_true(story.complete_mastery(int(first.get("id", -1)), 0),
		"一级确认写 preferredMastery 并换到二级候选")
	var second := _mastery_effect(story)
	assert_true(story.complete_mastery(int(second.get("id", -1)), 1),
		"二级确认把选中的那只入包并放行事件")
	assert_eq([story.progress["monsters"].size(), story.progress["book"][Book.BOOK_MONSTERS],
		story.progress["partyOrder"]], [3, [5, 44, 88], [0, 1, 2]],
		"过完新手剧情后背包／图鉴／队伍只剩确认的那三只（临时精灵的图鉴位被 Game_Book_Monster_mKeyPressed:42-69 清零）")
	assert_eq([story.progress["parameter"]["identity"], story.progress["parameter"]["level"],
		story.progress["guildCode"]], [0, 1, 99],
		"同一条剧情里的 Op.INIT_PARAMETERS（Param_stdInit(0, 1, 99)）把角色状态与公会码回到初始")


## `Evt_stdPROC` case 0xA（`:264-274`）与 `Object_procNEXT`：`p[2]` 原样写进
## `animation_end_mode`，2 = 停末帧（播一次就停在末帧，不重播）；下一条 opcode 10 把
## `p[1] + 100` 换回 100（= 待机动作）才离开那一帧。记录本身只推进一次步号。
## 依据见 `wiki\field\field-animation-wait.md` 第 2、3 节。
func test_actor_animation_plays_once() -> void:
	var provider := FixtureProvider.new()
	provider.events[0] = {"records": [
		_record(0),
		_record(Story.Op.PLACE_ACTOR, [6, 1212, 0, 0, 0]),
		_record(Story.Op.ACTOR_ANIMATION,
			[6, 14, Story.AnimationEndMode.HOLD_LAST_FRAME, 0, 0]),
		_record(Story.Op.WAIT, [6, 0, 0, 0, 0]),
		_record(Story.Op.ACTOR_ANIMATION, [6, 0, Story.AnimationEndMode.RESTART, 0, 0]),
		_record(21, [4, 0, 0, 0, 0])]}
	var story = _story(provider)
	var clown: Dictionary = story._actor(6)
	assert_eq([int(clown.get("action", -1)), int(clown.get("animationEndMode", -1)),
		int(story.progress["cursor"])],
		[Story.SCRIPTED_ANIMATION_FIRST + 14, Story.AnimationEndMode.HOLD_LAST_FRAME, 3],
		"一次性偷袭动作只设一次、按停末帧档写进对象，步号只推进到等待记录")
	story.advance(1.0)
	clown = story._actor(6)
	assert_eq([int(clown["action"]), int(clown["animationEndMode"]), int(story.progress["quest"])],
		[Story.SCRIPTED_ANIMATION_FIRST, Story.AnimationEndMode.RESTART, 4],
		"等待结束后回到待机动作，后续记录只推进到任务号 4")
	assert_eq(story.trace.count("evt0#2:10"), 1,
		"同一条动作记录只执行一次（不会反复播放）")


## `events.tres` 事件 33 的小丑偷袭（33#35 `10 [6, 14, 0]`）：mode 0 在原生是重播档，
## 只被 33#37 的放置记录 `7 [6, 0, 1]` 写回待机截断（中间 33#36 只等 3 帧），所以这一段
## 只播一次。用户口径：事件 33 的小丑只应该播放一次。
func test_event33_clown_ambush_plays_once() -> void:
	var provider := FixtureProvider.new()
	# 原样抄 `game\assets\events.tres` 事件 33 的第 34–38 条记录（0 基）。
	provider.events[0] = {"records": [
		_record(0),
		_record(Story.Op.PLACE_ACTOR, [6, 1608, 1, 0, 0]),
		_record(Story.Op.ACTOR_ANIMATION,
			[6, 14, Story.AnimationEndMode.CALLBACK_OR_RESTART, 0, 0]),
		_record(Story.Op.WAIT, [3, 0, 0, 0, 0]),
		_record(Story.Op.PLACE_ACTOR, [6, 0, 1, 0, 0]),
		_record(21, [4, 0, 0, 0, 0])]}
	var story = _story(provider)
	var clown: Dictionary = story._actor(6)
	assert_eq([int(clown.get("action", -1)), int(clown.get("animationEndMode", -1)),
		int(story.progress["cursor"])],
		[Story.SCRIPTED_ANIMATION_FIRST + 14, Story.AnimationEndMode.CALLBACK_OR_RESTART, 3],
		"33#35 的偷袭按重播档写入对象，随后停在 3 帧的等待记录")
	for _frame in 3:
		story.advance(FramePacing.NATIVE_FRAME_SECONDS)
	clown = story._actor(6)
	assert_eq([int(clown.get("action", -1)), clown.has("animationEndMode"),
		int(story.progress["quest"])],
		[FieldAction.Hero.IDLE, false, 4],
		"33#37 的放置记录在 3 帧后把动作写回待机")
	assert_eq(story.trace.count("evt0#2:10"), 1, "偷袭动作记录只执行一次")
	story.advance(1.0)
	assert_eq([int(story._actor(6).get("action", -1)), story.trace.count("evt0#2:10")],
		[FieldAction.Hero.IDLE, 1], "后续推进不会再回到偷袭动作（小丑只播一次）")


## opcode 3 的两条子模式按原生绘制语义落地（见 `wiki\event\event-chain-audit.md`
## 「动作／特效播放语义」）：
## * 子模式 3 的闪光是 `Evt_stdPAINT2:70-81` 的加色递减（`300 - 60 * 帧号`，6 帧），
##   末帧加色 0 等于不画，所以任何一帧都不该把画面压成黑色；
## * 子模式 6 只写 `EvtData+0x11`（`Evt_stdPROC:120-124`；`Evt_stdPAINT2:88-92` 读到 1 才
##   `Evt_chtDESTROY()`），是销毁原版对话窗的旗标，不是全屏黑遮罩。
func test_screen_effect_playback() -> void:
	var story = _story(_provider([
		_record(Story.Op.SCREEN_EFFECT, [Story.ScreenEffect.FLASH, 0, 0, 0, 0]),
		_record(Story.Op.SCREEN_EFFECT, [Story.ScreenEffect.CHT_DESTROY, 0, 1, 0, 0]),
		_record(Story.Op.SCREEN_EFFECT, [Story.ScreenEffect.CHT_DESTROY, 0, 0, 0, 0]),
		_record(21, [5, 0, 0, 0, 0])]))
	story.advance(1.0)
	var alphas: Array = []
	var covers := 0
	for effect: Dictionary in story.take_effects():
		if effect.kind == "fade":
			alphas.append(float(effect.alpha))
			assert_eq(int(effect.color), 0xffffff, "闪光按加色白光画，不混黑")
		elif effect.kind == "cover" and bool(effect.get("enabled", false)):
			covers += 1
	assert_eq(alphas.size(), Story.FLASH_FRAMES, "闪光正好 6 帧（`step_count > 5`）")
	assert_true(float(alphas[0]) == 1.0 and float(alphas[-1]) == 0.0 and
		float(alphas[1]) > float(alphas[-2]), "闪光从最亮单调收到全透明")
	assert_eq(covers, 0, "子模式 6 不产出全屏遮罩")
	assert_eq(int(story.progress["quest"]), 5, "两条子模式 6 记录都立即推进到下一条")


## `Evt_stdPROC:306-325`：`WAIT` 的 `p[0]` 是帧数，一帧 = 原生默认 50 ms
## （`EFC_thrInitialize:14` → `EFC_thrSPEED(4)` → `EFC_thrSLEEP(50)`，见 `wiki\ui\frame-pacing.md`）。
func test_wait_counts_native_frames() -> void:
	var story = _story(_provider([
		_record(Story.Op.WAIT, [4, 0, 0, 0, 0]),
		_record(Story.Op.SET_QUEST, [7, 0, 0, 0, 0])]))
	story.advance(0.19)
	assert_eq(int(story.progress["quest"]), 0, "4 帧的等待在 0.19 s 时还没走完（一帧 0.05 s）")
	story.advance(0.02)
	assert_eq(int(story.progress["quest"]), 7, "超过 0.2 s 后等待结束并推进到下一条")


## opcode 22（`Evt_stdPROC:465`）把参数整字节写进 `EvtData+0x28` 后立即推进下一条；
## 消费点是 `Object_procRUN:13`：`step_index > 0`（正在执行记录）且该字节 `== 1`
## 时整轮跳过对象池的逐帧推进，所以暂停只在事件执行期间成立，链尾与等触发器时对象照常推进。
func test_pause_objects() -> void:
	var story = _story(_provider([_record(Story.Op.PAUSE_OBJECTS, [1, 0, 0, 0, 0]),
		_record(Story.Op.WAIT, [16, 0, 0, 0, 0]),
		_record(Story.Op.SET_QUEST, [7, 0, 0, 0, 0])]))
	var paused_flags: Array = []
	for effect: Dictionary in story.take_effects():
		if effect.get("kind") == "objects-paused":
			paused_flags.append(bool(effect.paused))
	assert_eq([paused_flags, story.objects_paused(), int(story.progress["quest"])],
		[[true], true, 0],
		"参数 1 写暂停位：事件还在执行记录（等 16 帧），对象池整轮不推进")
	story.advance(2.0)
	assert_eq([story.objects_paused(), int(story.progress["quest"])], [false, 7],
		"链尾等到后继触发器（cursor 回到 0）后不再冻结对象")

	var other = _story(_provider([_record(Story.Op.PAUSE_OBJECTS, [0, 0, 0, 0, 0]),
		_record(Story.Op.PAUSE_OBJECTS, [2, 0, 0, 0, 0]),
		_record(Story.Op.WAIT, [16, 0, 0, 0, 0])]))
	assert_true(not other.objects_paused(),
		"只有恰好 1 冻结（Object_procRUN:13 的比较是 `!= 1`），0 与其它取值都是恢复")
