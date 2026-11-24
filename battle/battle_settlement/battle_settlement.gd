extends RefCounted
class_name BattleSettlement

## 原生「战斗结果」结算模型：只算数据，不画界面、不写存档。
##
## 依据（`libjconvertor.so`）：
## * `Battle_Win_init` → `Battle_Win_SetResult`：进状态 26 时一次算好
##   经验（`+16` 主角、`+17..19` 三名队员）、金币（`+49`）与掉落（`+24` 槽位、`+48` 数量）。
## * `Battle_Win_mRun`：子状态 1 每次推进分别给主角／队员发经验、给金币入账，
##   升级时把 `+20..+23` 置 5（Draw 里逐帧减一，即升级高亮）；子状态 2 入包 `Item_stdAddEx`。
## * `Battle_Win_mKeyPressed`：子状态 1 确认 = 快进（一次性发完剩余量），
##   子状态 2 确认 = 回地图／联网状态。
## * 经验阈值 `Param_expINIT`／`Ball_stdEXPS` 都是 `65 × 等级²`；
##   升级上限两者都是 99，满级后经验归零。
## 掉落表全部是 .rodata 固定表（0x97940–0x97BB8），没有可导出数据源，这里逐字节照抄。

const Battle = preload("res://battle/battle/battle.gd")
const Book = preload("res://menu/book_model/book_model.gd")
const MenuModel = preload("res://menu/menu_model/menu_model.gd")
const MonsterAttribute = preload("res://core/monster_animation/monster_attribute/monster_attribute.gd")

## `Param_expINIT`：主角 `65 × 等级²`；`Ball_stdEXPS`：队员同一条公式。
const EXPERIENCE_PER_LEVEL := 65
## `Param_expSET` 每升一级给 3 点能力点（只对主角）。
const ABILITY_POINTS_PER_LEVEL := 3
## `Battle_Win_SetResult` 的升级高亮帧数（`+20..+23` 写 5，`Battle_Win_Draw` 逐帧减）。
const FLASH_FRAMES := 5
## 原生每帧发 `阈值/100`、金币发 `总额/100`（都最少 1）：总额只有一两百时每帧 1 点要拖
## 上几秒，总额大时又几帧就跳完。`Battle_Win_mRun` 返回的 500 单位一直没有旁证，所以窗口
## 把剩余量均摊到这 20 帧（20 × 0.05 秒 = 1 秒）发完，升级高亮仍是原生的 5 帧。
const GAIN_FRAMES := 20
## 每只敌人 30% 掉一笔 `50 + 等级` 的金币（`rand() % 100 <= 29`）。
const MONEY_CHANCE := 30
## 原生自动战斗 `Battle_Menu_Auto` 把 `run_counter+25` 置 1，`Battle_Win_SetResult` 因此
## `n20 -= 40`（msg.fxt:0「自动战斗时,获得60%的经验」）。
const AUTO_EXPERIENCE_PENALTY := -40
## `Battle_Win_SetResult:180-181`：`standard_progress + 7 > 0` 时 `n20 = 20`——经验加成的
## 百分比与自动战斗的 −40、被动 24 直接代数相加，再走同一条 `v4 * n20 / 100 + v4`。
const EXP_BONUS_PERCENT := 20
## `Battle_Win_SetResult` 的战後心情／饱食度：`n4 = 敌方平均等级 − 我方存活队员平均等级`，
## 队员按 n4 加心情、减饱食度（`Ball_stdFeel`／`Ball_stdFood`）。
const FEEL_GAIN_SLIGHT := 3
const FEEL_GAIN_NORMAL := 2
const FEEL_GAIN_HARD := 1
const FOOD_LOSS_SLIGHT := 5
const FOOD_LOSS_HARD := 2
## `Field_Quest_Complete_SetResult`：`v5 = v2 / 10`，`v2` 是结果页的总经验，
## `v5` 写进六格属性经验（`BattleData + 10 + 属性`）。整数截断。
const ATTRIBUTE_EXPERIENCE_DIVISOR := 10

## `Battle_Drop_ITEM1` 的 6×6 表（.rodata 0x97B94），索引 = 属性 × 6 + 品级，
## 取值 + 3000 得到道具号；`-1` 表示该组合不掉落。
const ITEM1_GRADE_TABLE := [
	0, 6, 12, 18, -1, -1,
	1, 7, 13, 19, -1, -1,
	2, 8, 14, 20, -1, -1,
	3, 9, 15, 21, -1, -1,
	4, 10, 16, 22, -1, -1,
	5, 11, 17, 23, -1, -1,
]
## `Battle_Drop_ITEM1` 20% 分支里属性 4／5 的 8 项表（0x97B8C）与 3 项表（立即数 16..18）。
const ITEM1_HIGH_TABLE := [8, 9, 10, 11, 12, 13, 14, 15]
const ITEM1_HIGH_RARE_TABLE := [16, 17, 18]
## `Battle_Drop_ITEM2` 的四张按属性索引的表（0x97B6C／0x97B74／0x97B7C／0x97B84）。
const ITEM2_LOW_TABLE := [20, 19, 21, 24, 23, 22]
const ITEM2_MIDDLE_TABLE := [25, 26, 27, 30, 28, 29]
const ITEM2_HIGH_TABLE := [32, 31, 34, 35, 33, 36]
const ITEM2_SPECIAL_TABLE := [2, 1, 3, 6, 5, 4]
## `Battle_Drop_BOOK_*` 的三张表（80%／90-94%／95%+），按品级选表（0x97940–0x97A8C）。
const BOOK_COMMON := [
	[36, 39, 42, 45, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 161],
	[37, 40, 43, 46],
	[43, 46, 38, 41],
]
const BOOK_UNCOMMON := [
	[0, 3, 6, 9, 24, 27, 30, 33, 60, 63, 66, 67, 70, 156, 158],
	[1, 4, 7, 10, 25, 28, 31, 34, 61, 64, 67, 71, 159],
	[2, 5, 8, 11, 26, 29, 32, 35, 62, 65, 68, 72, 160],
]
const BOOK_RARE := [
	[12, 15, 18, 21, 48, 51, 54, 57, 91, 94, 97, 100, 103, 106, 118, 121, 124, 127,
		130, 133, 157],
	[13, 16, 19, 22, 49, 52, 55, 58, 92, 95, 98, 101, 104, 107, 119, 122, 125, 128,
		131, 134],
	[14, 17, 20, 23, 50, 53, 56, 59, 93, 96, 99, 102, 105, 108, 120, 123, 126, 129,
		132, 135],
]
const BOOK_SPECIAL := [
	[73, 76, 79, 82, 85, 88, 109, 112, 115, 146, 149, 152, 155, 158, 165],
	[74, 77, 80, 83, 86, 89, 110, 113, 116, 147, 150, 153, 156, 159],
	[75, 78, 81, 84, 87, 90, 111, 114, 117, 148, 151, 154, 157, 167],
]
const BOOK_TABLES := [BOOK_COMMON, BOOK_UNCOMMON, BOOK_RARE, BOOK_SPECIAL]
## `Battle_Drop_EQUIP` 按品级与 `rand()%100` 选 6 项表（.rodata 0x97A9C–0x97B64）。
const EQUIP_GRADE_0 := [[0, 2, 4, 6, 8, 10]]
const EQUIP_GRADE_1 := [[0, 2, 4, 6, 8, 10], [1, 3, 5, 7, 9, 11]]
const EQUIP_GRADE_2 := [[1, 3, 5, 7, 9, 11], [12, 14, 16, 18, 20, 22], [13, 15, 17, 19, 21, 23]]
const EQUIP_GRADE_3 := [[48, 50, 52, 54, 56, 58], [49, 51, 53, 55, 57, 59],
	[60, 62, 64, 66, 68, 70], [61, 63, 65, 67, 69, 71]]
const EQUIP_GRADE_4 := [[13, 15, 17, 19, 21, 23], [24, 26, 28, 30, 32, 34],
	[25, 27, 29, 31, 33, 35], [36, 38, 40, 42, 44, 46], [37, 39, 41, 43, 45, 47],
	[48, 50, 52, 54, 56, 58], [49, 51, 53, 55, 57, 59], [60, 62, 64, 66, 68, 70]]
const EQUIP_GRADE_5 := [[24, 26, 28, 30, 32, 34], [25, 27, 29, 31, 33, 35],
	[36, 38, 40, 42, 44, 46], [37, 39, 41, 43, 45, 47], [48, 50, 52, 54, 56, 58],
	[49, 51, 53, 55, 57, 59], [60, 62, 64, 66, 68, 70], [61, 63, 65, 67, 69, 71]]
## 四行：0 是主角（`Battle_Win_Draw` 的 `n4_1 == 0` 分支），1..3 是出战队员。
var rows: Array[Dictionary] = []
## 本次入账金币（`+49`）与尚未发完的余额。
var money := 0
var money_left := 0
## 经验／金币动画已经推进的帧数（见 `GAIN_FRAMES`）。
var gain_frames := 0
## 掉落清单（每项一条，原生每个掉落各占一个槽位、数量固定 1）。
var items: Array[Dictionary] = []
var applied := false
## 结果页六格属性经验（原生 `BattleData + 10..15`，一格一个属性，下标见 `MonsterAttribute`）。
## 原生只有任务完成那一路（`Field_Quest_Complete_SetResult`）写值，
## `Battle_Win_SetResult` 只把六格清零，所以纯战斗这里全是 0。
var mastery_experience: Array[int] = MonsterAttribute.zero_points()

var _random: Callable
var _catalog: GameplayData
var _money_before := 0
## `Evt_stdSET(3, 物种)` 的事件掉落（见 `story.event_drop_for`）：返回物品 id 或 -1。
var _event_drop: Callable


func _init(combat: RefCounted, progress: Dictionary, catalog: GameplayData,
		random: Callable = Callable(), auto_battle := false,
		event_drop: Callable = Callable(), result_experience := 0) -> void:
	assert(combat != null and progress != null and catalog != null)
	assert(combat.result == "won")
	_catalog = catalog
	_random = random if random.is_valid() else func(limit: int) -> int: return randi_range(0, limit - 1)
	_event_drop = event_drop
	_money_before = int(progress.get("parameter", {}).get("moneyBalance", 0))
	_build_rows(progress)
	_build_mastery_experience(combat, result_experience)
	var gain := _base_experience(combat, auto_battle, progress.get("parameter", {}))
	for row: Dictionary in rows:
		var amount := gain
		if row.kind == "member":
			var bonus := int(_passive(combat.balls[row.member_index], 23))
			if bonus > 0:
				# 原生 `(v15 * v20 + 99) / 100 + v15`：队员经验加成被动。
				amount = (gain * bonus + 99) / 100 + gain
		row.experience_left = amount
	_build_feel_food(combat, progress)
	_build_items(combat)
	_build_money(combat)


## 玩家的流派（原生 `ParamData.preferred_mastery_index`）：本工程存在
## `parameter.preferredMastery`，事件 0x20 选过才有值，未选／老存档按 -1。
static func preferred_mastery(progress: Dictionary) -> int:
	var parameter: Variant = progress.get("parameter")
	if not parameter is Dictionary:
		return -1
	return int(parameter.get("preferredMastery", -1))


## 原生 `Battle_Win_SetResult` 的战後心情／饱食度（`Ball_stdFeel`／`Ball_stdFood`）：
## `n4 = 敌方平均等级 − 我方存活队员平均等级`；`n4 > 4` → 心情 +1、饱食 −2；
## `−3 ≤ n4 ≤ 4` → 心情 +2、饱食 −5（`n4 == 4` 时 −2）；`n4 < −3` → 心情 +3、饱食 −5。
## 玩家的流派（`preferredMastery`）与该队员属性一致时心情再多 +1；`feel_state_code == 3`
## （觉醒，本工程用物种号 +1000 表示）不再加心情。对战类型 ≥ 10 时才跳过饱食度扣减，
## 本工程没有这些类型，一律按上表扣。
func _build_feel_food(combat: RefCounted, progress: Dictionary) -> void:
	var enemy_total := 0
	var enemy_count := 0
	var party_total := 0
	var party_count := 0
	for index in range(3):
		var ball: Dictionary = combat.balls[index]
		if ball.is_empty():
			continue
		enemy_total += int(ball.level)
		enemy_count += 1
	for slot in range(3, combat.balls.size()):
		var ball: Dictionary = combat.balls[slot]
		if ball.is_empty() or int(ball.hp) == 0:
			continue
		party_total += int(ball.level)
		party_count += 1
	if enemy_count == 0 or party_count == 0:
		return
	var gap := int(enemy_total / enemy_count) - int(party_total / party_count)
	var feel_gain := FEEL_GAIN_NORMAL
	var food_loss := FOOD_LOSS_SLIGHT
	if gap > 4:
		feel_gain = FEEL_GAIN_HARD
		food_loss = FOOD_LOSS_HARD
	elif gap < -3:
		feel_gain = FEEL_GAIN_SLIGHT
	elif gap == 4:
		food_loss = FOOD_LOSS_HARD
	var preferred := preferred_mastery(progress)
	for slot in rows.size():
		var row: Dictionary = rows[slot]
		if row.kind != "member":
			continue
		var ball: Dictionary = combat.balls[slot + 2]
		if ball.is_empty():
			continue
		var gain := feel_gain
		if preferred >= 0 and preferred == int(ball.attribute):
			gain += 1
		row["feel_gain"] = 0 if int(ball.species) > 999 else gain
		row["food_loss"] = food_loss
		# `Battle_Win_SetResult` 的同一条循环里还有两支被动：56（`ext + 524`）按值% 回 HP、
		# 62（`ext + 530`）掷中则 SP 回满，两者都 `Param_atkPASSIVE` 弹「被动发动」。
		row["hp_heal"] = int(_passive(ball, 56))
		row["sp_full"] = _roll(100) < int(_passive(ball, 62))


## 原生 `Battle_Win_SetResult` 只给主角与在场队员各发一份经验；不在队伍／已阵亡的成员不显示。
func _build_rows(progress: Dictionary) -> void:
	rows.clear()
	var parameter: Dictionary = progress.get("parameter", {})
	var development: Dictionary = parameter.get("development", {})
	var hero_level := int(parameter.get("level", 1))
	rows.append(make_row("hero", -1, -1, 0, hero_level,
		int(development.get("experience", 0))))
	var order: Array = MenuModel.native_party_order(progress)
	var monsters: Array = progress.get("monsters", [])
	for slot in range(3):
		if slot >= order.size():
			break
		var index := int(order[slot])
		if index < 0 or index >= monsters.size():
			break
		var member: Dictionary = monsters[index]
		var args: Variant = member.get("nativeArguments")
		if not args is Array or args.size() < 2:
			break
		rows.append(make_row("member", index, int(member.get("species", args[0])),
			int(member.get("nickname", 0)), int(args[1]),
			int(member.get("experience", 0))))


## `Field_Quest_Complete_SetResult` 的六格写法：`v5 = 总经验 / 10`；逐只「在场
## （`presence_value > 0`）且 `hp_current != 0`」的出战怪先 `Ball_datBasic` 取记录第 134 字节
## （属性组 − 1），再 `BattleData + 10 + 属性 = v5`。原生是**赋值**而不是累加，而 `v5` 对每只
## 怪都相同，所以同属性两只怪共享一格、不会翻倍。
## `result_experience` 是结果页的总经验（`BattleData+16`）：任务完成那一路取 `record+23`；
## 战斗那一路 `Battle_Win_SetResult` 只把六格清零，传 0 即「普通战斗不涨属性经验」。
func _build_mastery_experience(combat: RefCounted, result_experience: int) -> void:
	mastery_experience = MonsterAttribute.zero_points()
	if result_experience <= 0:
		return
	var gain := mastery_gain(result_experience)
	for index in range(3, combat.balls.size()):
		var ball: Dictionary = combat.balls[index]
		if ball.is_empty() or int(ball.hp) == 0:
			continue
		var attribute := int(ball.attribute)
		if attribute < 0 or attribute >= MonsterAttribute.COUNT:
			continue
		mastery_experience[attribute] = gain


## 原生 `v58 = Σ 80 × 等级`（强化=`feel_state_code == 3` 时翻倍），`v4 = v58 / 3`；
## 再乘 `(100 + n20) / 100`，`n20` 来自自动战斗 -40、在场队员的被动 24（经验增加）
## 与经验加成窗口的 +20（`Battle_Win_SetResult:180-181`）。
static func _base_experience(combat: RefCounted, auto_battle: bool,
		parameter: Variant = {}) -> int:
	var total := 0
	var count := 0
	var level_sum := 0
	for index in range(3):
		var ball: Dictionary = combat.balls[index]
		if ball.is_empty():
			continue
		var level := int(ball.level)
		# 原生 `feel_state_code == 3`（强化怪）经验翻倍；本工程用「觉醒/强化」物种号 +1000 表示。
		total += (160 if int(ball.species) > 999 else 80) * level
		level_sum += level
		count += 1
	# 三只都被捕获（不是击倒）时也会进 WIN，但没有任何敌人留下经验来源，按 0 处理。
	var base := int(total / 3)
	var bonus := AUTO_EXPERIENCE_PENALTY if auto_battle else 0
	if StoryRuntime.exp_bonus_remaining(parameter) > 0:
		bonus += EXP_BONUS_PERCENT
	for slot in range(3, combat.balls.size()):
		var ball: Dictionary = combat.balls[slot]
		if ball.is_empty() or int(ball.hp) == 0:
			continue
		bonus += int(_passive(ball, 24))
	return int(base * bonus / 100) + base


static func _passive(ball: Dictionary, effect: int) -> int:
	var passives: Variant = ball.get("passives")
	if not passives is Array or effect < 0 or effect >= passives.size():
		return 0
	return int(passives[effect])


## 六格每格进多少：`Field_Quest_Complete_SetResult` 的 `v5 = v2 / 10`。
static func mastery_gain(result_experience: int) -> int:
	return result_experience / ATTRIBUTE_EXPERIENCE_DIVISOR


## 把六格累加进存档并逐格判升级（原生 `Battle_Win_mRun` → `Param_expSET`）。
## 原生只把 `> 0` 的格子交过去，随后 `point_remainder += 值`，再
## `while 余数 >= 阈值: 余数 -= 阈值; level++`；阈值随等级重算（`Param_expINIT` 的
## `120／130 × 等级²`，见 `MonsterAttribute.threshold`）。
## `ability_points += 3` 只写在 `n5 > 5` 的主角等级分支，所以**属性升级不加能力点**；
## 余数留在 `masteryExperience`（＝ `point_remainder`），99 级封顶并把余数清零
## （`point_remainder = level != 99 ? 余数 : 0`）。返回本次升过级的槽位。
static func add_mastery_experience(development: Dictionary, gains: Array[int],
		preferred_mastery := -1) -> Array[int]:
	var leveled: Array[int] = []
	if gains.size() != MonsterAttribute.COUNT:
		return leveled
	var stored: Variant = development.get("masteryExperience")
	var points: Array = stored if stored is Array and \
		stored.size() == MonsterAttribute.COUNT else MonsterAttribute.zero_points()
	var stored_levels: Variant = development.get("growth")
	# `growth` 是 `mastery_progress[i].level`；没有它只累加，不改等级。
	var levels: Array = stored_levels if stored_levels is Array and \
		stored_levels.size() == MonsterAttribute.COUNT else []
	for index in MonsterAttribute.COUNT:
		var remainder := int(points[index]) + maxi(0, int(gains[index]))
		if index < levels.size():
			var outcome: Dictionary = advance_levels(
				maxi(MonsterAttribute.LEVEL_MIN, int(levels[index])), remainder,
				MonsterAttribute.threshold_factor(preferred_mastery, index))
			remainder = int(outcome["remainder"])
			levels[index] = int(outcome["level"])
			if int(outcome["levels"]) > 0:
				leveled.append(index)
		points[index] = remainder
	development["masteryExperience"] = points
	return leveled


## `Battle_Win_SetResult` 的掉落顺序：逐只敌人的 ITEM1 → ITEM2 → ITEM3。
## `Evt_stdSET(3, 物种)` 的事件掉落与 `Battle_Drop_RANKING`（5/6/8/9 号对战类型）在
## 本工程没有对应数据源，这里不生成，也不拿别的表顶替。
func _build_items(combat: RefCounted) -> void:
	items.clear()
	for index in range(3):
		var ball: Dictionary = combat.balls[index]
		if ball.is_empty():
			continue
		var species: MonsterDefinition = _catalog.monster(Battle.combat_species(int(ball.species)))
		if species == null:
			continue
		var attribute := int(species.attribute_group) - 1
		var grade := int(species.attribute_entry)
		# 原生每个敌人先判 `Evt_stdSET(3, 定义号)` 的事件掉落，再判三条掉落表。
		if _event_drop.is_valid():
			_add_drop(int(_event_drop.call(int(ball.species))))
		_add_drop(_drop_item1(attribute, grade))
		_add_drop(_drop_item2(attribute))
		_add_drop(_drop_item3(grade))


func _add_drop(id: int) -> void:
	if id < 0:
		return
	var record: ItemDefinition = _catalog.item(id)
	if record == null or record.type != ItemKind.kind_of(id) or \
			record.index != ItemKind.index_of(id):
		return
	items.append({"id": id, "type": record.type, "index": record.index, "count": 1})


## `Battle_Drop_ITEM1(属性, 品级)`：15% 起步；80% 走 6×6 表，20% 再抽一次 `rand()%100` 分类。
func _drop_item1(attribute: int, grade: int) -> int:
	if _roll(100) > 84:
		return -1
	if _roll(100) > 19:
		if attribute < 0 or attribute > 5 or grade < 0 or grade > 5:
			return -1
		var value: int = ITEM1_GRADE_TABLE[attribute * 6 + grade]
		return ItemKind.id_of(ItemKind.Kind.MATERIAL, value)
	# 原生在 20% 分支里再抽一次（`Battle_Drop_ITEM1`）才决定分类。
	var roll := _roll(100)
	if attribute > 5:
		return -1
	var consumable := ItemKind.Kind.CONSUMABLE
	if attribute in [4, 5]:
		var index: int = ITEM1_HIGH_RARE_TABLE[_roll(ITEM1_HIGH_RARE_TABLE.size())] \
			if roll > 79 else ITEM1_HIGH_TABLE[_roll(ITEM1_HIGH_TABLE.size())]
		return ItemKind.id_of(consumable, index)
	if attribute in [2, 3]:
		# 原生 `1007 - ((n79 <= 89) ? 1 : 0)`：70–89 掉 1006，90–99 掉 1007。
		return ItemKind.id_of(consumable, 5 if roll <= 69 else 6 if roll <= 89 else 7)
	if roll <= 69:
		return ItemKind.id_of(consumable, 0)
	if roll <= 89:
		return ItemKind.id_of(consumable, 1)
	return ItemKind.id_of(consumable, 4)


## `Battle_Drop_ITEM2(属性)`：50% 起步，四档 `rand()%100` 选表。
func _drop_item2(attribute: int) -> int:
	if _roll(100) > 49:
		return -1
	if attribute < 0 or attribute >= ITEM2_LOW_TABLE.size():
		return -1
	var roll := _roll(100)
	if roll <= 9:
		return ItemKind.id_of(ItemKind.Kind.CONSUMABLE, ITEM2_LOW_TABLE[attribute])
	if roll <= 59:
		return ItemKind.id_of(ItemKind.Kind.CONSUMABLE, ITEM2_MIDDLE_TABLE[attribute])
	if roll <= 89:
		return ItemKind.id_of(ItemKind.Kind.CONSUMABLE, ITEM2_HIGH_TABLE[attribute])
	return ItemKind.id_of(ItemKind.Kind.ATTRIBUTE_BALL, ITEM2_SPECIAL_TABLE[attribute])


## `Battle_Drop_ITEM3(品级)`：10% 起步，10% 走装备、其余按品级掉书。
func _drop_item3(grade: int) -> int:
	if _roll(100) > 9:
		return -1
	if _roll(100) <= 9:
		return _drop_equip(grade)
	if grade < 0 or grade >= BOOK_TABLES.size():
		return -1
	var tables: Array = BOOK_TABLES[grade]
	var roll := _roll(100)
	var table: Array = tables[0] if roll <= 79 else tables[1] if roll <= 94 else tables[2]
	return ItemKind.id_of(ItemKind.Kind.SKILL_BOOK, int(table[_roll(table.size())]))


## `Battle_Drop_EQUIP(品级)`：先抽 `rand()%100`（分档）再抽 `rand()%6` 取表内一项。
func _drop_equip(grade: int) -> int:
	var roll := _roll(100)
	var index := _roll(6)
	var tables: Array = [EQUIP_GRADE_0, EQUIP_GRADE_1, EQUIP_GRADE_2,
		EQUIP_GRADE_3, EQUIP_GRADE_4, EQUIP_GRADE_5][grade] if grade in range(6) else []
	if tables.is_empty():
		return -1
	var slot := -1
	match grade:
		0:
			slot = 0
		1:
			slot = 1 if roll > 79 else 0
		2:
			slot = 0 if roll <= 59 else 2 if roll > 89 else 1
		3:
			slot = 0 if roll <= 49 else 1 if roll <= 74 else 2 if roll <= 89 else 3
		4:
			slot = 0 if roll <= 39 else 1 if roll <= 64 else 2 if roll <= 74 else \
				3 if roll <= 83 else 4 if roll <= 90 else 5 if roll <= 95 else \
				6 if roll <= 98 else 7
		_:
			slot = 0 if roll <= 39 else 1 if roll <= 64 else 2 if roll <= 74 else \
				3 if roll <= 83 else 4 if roll <= 90 else 5 if roll <= 95 else \
				6 if roll <= 98 else 7
	return ItemKind.id_of(ItemKind.Kind.EQUIPMENT, int(tables[slot][index]))


## 金币：每只在场敌人 30% 掉 `50 + 等级`，最后叠加在场队员的被动 61（金币增加）。
func _build_money(combat: RefCounted) -> void:
	var total := 0
	for index in range(3):
		var ball: Dictionary = combat.balls[index]
		if ball.is_empty():
			continue
		if _roll(100) <= MONEY_CHANCE - 1:
			total += 50 + int(ball.level)
	var bonus := 0
	for slot in range(3, combat.balls.size()):
		var ball: Dictionary = combat.balls[slot]
		if ball.is_empty() or int(ball.hp) == 0:
			continue
		bonus += _passive(ball, 61)
	money = total + (total * bonus + 99) / 100
	money_left = money


func _roll(limit: int) -> int:
	var value := int(_random.call(limit))
	assert(value >= 0 and value < limit)
	return value


## 当前展示的金币（原生 Draw 画的是已经入账的 `ParamData.money_balance`）。
func shown_money() -> int:
	return _money_before + money - money_left


func is_finished() -> bool:
	return rows_finished(rows, money_left)


## 一次 `Battle_Win_mRun` 子状态 1 的推进：把剩余量均摊到剩下的 `GAIN_FRAMES` 帧
## （取整向上，最后一帧一定发完），快进（子状态 1 按确认键）时一次发完；
## 升级的行记 `FLASH_FRAMES` 帧高亮。
func step(fast: bool) -> Dictionary:
	gain_frames += 1
	var outcome := advance_frame(rows, gain_frames, money_left, fast)
	money_left = int(outcome["money_left"])
	return {"level_ups": outcome["level_ups"], "done": is_finished()}


## 结算窗与任务完成页（`field/quest_reward`）共用的结果页推进，返回
## `{"level_ups": Array[int], "money_left": int}`。`gain_frames` 是已经推进的帧数（调用方先自增）。
static func advance_frame(rows: Array[Dictionary], gain_frames: int, money_left: int,
		fast: bool) -> Dictionary:
	var level_ups: Array[int] = []
	var left_frames := maxi(1, GAIN_FRAMES - gain_frames + 1)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var left := int(row.experience_left)
		if left <= 0:
			continue
		var amount := left if fast else mini(ceili(float(left) / left_frames), left)
		row.experience_left = left - amount
		if grant(row, amount):
			row.flash = FLASH_FRAMES
			level_ups.append(index)
	if money_left > 0:
		var amount := money_left if fast else mini(ceili(float(money_left) / left_frames), money_left)
		money_left -= amount
	return {"level_ups": level_ups, "money_left": money_left}


## 结果页一行（`Battle_Win_SetResult` 的 `BattleData+16..23` 逐行字段）：
## 阈值按 `hero_threshold`、余额从 0 起、`flash` 是升级高亮的剩余帧数。
static func make_row(kind: String, member_index: int, species: int, nickname: int, level: int,
		experience: int) -> Dictionary:
	var safe_level := maxi(1, level)
	return {
		"kind": kind, "member_index": member_index, "species": species,
		"nickname": nickname, "level": safe_level, "experience": maxi(0, experience),
		"threshold": hero_threshold(safe_level),
		"start_level": safe_level, "experience_left": 0, "points": 0, "flash": 0,
	}


## 下一级阈值：原生 `Param_expINIT` 的主角／队员同一条公式 `65 × 等级²`。
static func hero_threshold(level: int) -> int:
	return EXPERIENCE_PER_LEVEL * level * level


## 原生 `Param_expSET` 的升级循环（`point_remainder` 已经加进 `remainder`）：
## `while 余数 >= 阈值 { 余数 -= 阈值; 等级 += 1; 阈值 = Param_expINIT(等级) }`。
## `Param_expINIT` 两种阈值都是「系数 × 等级²」，所以按系数传入——主角 65（`hero_threshold`）、
## 六格流派 120／130（`MonsterAttribute.threshold_factor`）。`level > 0x62` 才 break，所以
## 99 级封顶；末行 `point_remainder = level != 99 ? 余数 : 0` 让满级余数清零。
## 主角（结果页 `grant`、存档 `add_hero_experience`）与六格流派共用这一段。
## 返回 `{"level", "threshold", "remainder", "levels"}`，`levels` 是本次升了几级。
static func advance_levels(level: int, remainder: int, factor: int) -> Dictionary:
	var threshold := factor * level * level
	var levels := 0
	while level < MonsterAttribute.LEVEL_MAX and remainder >= threshold:
		remainder -= threshold
		level += 1
		threshold = factor * level * level
		levels += 1
	if level >= MonsterAttribute.LEVEL_MAX:
		remainder = 0
	return {"level": level, "threshold": threshold, "remainder": remainder, "levels": levels}


## 原生 `Param_expSET`（主角）／`Ball_stdEXP`（队员）：逐级扣阈值升级，满级后余额归零。
## `row.threshold` 恒等于 `hero_threshold(等级)`（`make_row` 与这里都按它写）。
## 返回是否发生了升级。
static func grant(row: Dictionary, amount: int) -> bool:
	var remainder := amount + int(row.experience)
	var outcome: Dictionary = advance_levels(int(row.level), remainder, EXPERIENCE_PER_LEVEL)
	row.level = int(outcome["level"])
	row.threshold = int(outcome["threshold"])
	row.experience = int(outcome["remainder"])
	if remainder < 0:
		row.experience = 0
	var levels := int(outcome["levels"])
	if levels > 0 and row.kind == "hero":
		row.points = int(row.points) + levels * ABILITY_POINTS_PER_LEVEL
	return levels > 0


## `Item_stdAdd:93` 的组 25 伪道具 → `Param_expSET(6u, 数量)`：把数量直接写进存档里的主角进度
## （`ParamData.player_progress`）——余数落 `parameter.development.experience`
## （＝ `point_remainder`）、等级落 `parameter.level`；每升一级
## `ParamData.ability_points += 3`（`Param_expSET:26-27` 的 `n5 > 5` 分支），
## 本工程的能力点就是 `parameter.development.points`（`Param_abilPlus`／`Param_abilApply`
## 扣的是同一份余额）。升级循环与六格流派共用 `advance_levels`，只是系数取主角的 65。
## 返回是否升了级。
static func add_hero_experience(parameter: Dictionary, amount: int) -> bool:
	var development: Variant = parameter.get("development")
	if amount <= 0 or not development is Dictionary:
		return false
	var level := maxi(MonsterAttribute.LEVEL_MIN,
		int(parameter.get("level", MonsterAttribute.LEVEL_MIN)))
	var remainder := int(development.get("experience", 0)) + amount
	var outcome: Dictionary = advance_levels(level, remainder, EXPERIENCE_PER_LEVEL)
	parameter.level = int(outcome["level"])
	development.experience = int(outcome["remainder"])
	var levels := int(outcome["levels"])
	if levels > 0:
		development.points = int(development.get("points", 0)) + \
			levels * ABILITY_POINTS_PER_LEVEL
	return levels > 0


## 结果页是否还有没发完的经验／金币（`Battle_Win_mRun` 子状态 1 的退出条件）。
static func rows_finished(rows: Array[Dictionary], money_left: int) -> bool:
	if money_left > 0:
		return false
	for row: Dictionary in rows:
		if int(row.experience_left) > 0:
			return false
	return true


## 把结算结果写回进度：主角等级／经验／能力点、金币、队员等级／经验（升级后重算数值并回满）、
## 掉落入包、六格属性经验与流派升级（`development.masteryExperience`／`development.growth`）。
## `add_item` 是入包入口：传故事层的背包规则时，掉落在结算内就走同一条 `Item_stdAddEx` 等价路径
## （因此会推 fxt416 入手提示）；直接驱动模型（没有故事／视图）时留空，用本文件同规则的 `_add_item`。
## 返回 `{"items": 已入包道具号, "full": 背包满未入包的道具号}`。
func apply(progress: Dictionary, add_item := Callable()) -> Dictionary:
	var report := {"items": [], "full": []}
	if applied or rows.is_empty():
		return report
	applied = true
	# 原生只有子状态 2（经验与金币都发完）才允许离开；直接写回时先把剩余量快进发完。
	if not is_finished():
		step(true)
	var parameter: Dictionary = progress.get("parameter", {})
	var hero: Dictionary = rows[0]
	parameter.level = int(hero.level)
	parameter.moneyBalance = mini(999999999, int(parameter.get("moneyBalance", 0)) + money)
	var development: Variant = parameter.get("development")
	if development is Dictionary:
		development.experience = int(hero.experience)
		development.points = int(development.get("points", 0)) + int(hero.points)
		add_mastery_experience(development, mastery_experience,
			preferred_mastery(progress))
	var monsters: Array = progress.get("monsters", [])
	for index in range(1, rows.size()):
		var row: Dictionary = rows[index]
		var member_index := int(row.member_index)
		if member_index < 0 or member_index >= monsters.size():
			continue
		var member: Dictionary = monsters[member_index]
		member.level = int(row.level)
		member.experience = int(row.experience)
		# `Ball_stdFood`：饱食度夹到 0–100。`Ball_stdFeel`：心情到 999 且尚未觉醒时走觉醒
		# （`Ball_stdFeel` 的 LABEL_5），已觉醒的只把 `feel_value` 夹在 0–999。
		member.food = clampi(int(member.get("food", ItemEffect.FOOD_MAX)) - int(row.get("food_loss", 0)),
			0, ItemEffect.FOOD_MAX)
		var feel := int(member.get("feel", 0)) + int(row.get("feel_gain", 0))
		var evolved := feel >= ItemEffect.FEEL_MAX and not Battle.record_awakened(member)
		if evolved:
			Battle.awaken_record(member)
		else:
			member.feel = mini(ItemEffect.FEEL_MAX, feel)
		var arguments: Array = member.nativeArguments
		arguments[1] = int(row.level)
		# 原生 `Ball_stdEXP` 升级时 `Ball_stdBasic` 重算数值并把 HP／SP 回满；
		# 战後被动 56／62 也要用到重算后的上限，所以这里一次算好。
		var details := MenuModel.native_member_details(progress, _catalog, member_index)
		var ball: Variant = details.get("ball")
		var known: bool = details.get("ok", false) and ball != null
		# 觉醒同 `Ball_stdBasic` 之后的两句 `Ball_stdHP(ball, 0, 100)`／`Ball_stdSP(ball, 0, 100)`：
		# HP／SP 按新物种的上限回满（`member.get("hp") != null` 才表示记录里存过当前值）。
		if evolved and known and member.get("hp") != null:
			member.hp = int(ball.max_hp)
			member.sp = int(ball.max_sp)
		elif int(row.level) != int(row.start_level) and known:
			member.hp = int(ball.max_hp)
			member.sp = int(ball.max_sp)
		if known:
			var heal := int(row.get("hp_heal", 0))
			if heal > 0:
				member.hp = mini(int(ball.max_hp),
					int(member.get("hp", ball.max_hp)) + int(int(ball.max_hp) * heal / 100))
			if bool(row.get("sp_full", false)):
				member.sp = int(ball.max_sp)
	for item: Dictionary in items:
		var item_id := int(item.id)
		var count := int(item.count)
		var added: bool = bool(add_item.call(item_id, count)) if add_item.is_valid() \
			else _add_item(progress, item_id, count)
		if added:
			report.items.append(item_id)
		else:
			report.full.append(item_id)
	return report


## 背包规则与 `story.gd::_add_inventory_item` 相同（分类包、堆叠上限），区别是背包满
## 时不中断原流程：原生在这一步只弹一条「背包已满」（`Param_ballFULL`）。返回是否入包。
func _add_item(progress: Dictionary, item_id: int, count: int) -> bool:
	var inventory: Variant = progress.get("inventory")
	if not inventory is Dictionary:
		return false
	var type := ItemKind.kind_of(item_id)
	var index := ItemKind.index_of(item_id)
	var bag := ItemKind.bag_of(type, index)
	if bag < 0:
		return false
	var key := str(item_id)
	var previous := int(inventory.get(key, 0))
	var capacity: Variant = progress.get("itemCapacity")
	if not capacity is Array or bag >= capacity.size():
		return false
	var occupied := 0
	for entry: Variant in inventory:
		if str(entry) == key:
			continue
		var other := int(str(entry))
		if ItemKind.bag_of(ItemKind.kind_of(other), ItemKind.index_of(other)) != bag:
			continue
		occupied += _stack_slots(int(inventory[entry]),
			ItemKind.max_stack(ItemKind.kind_of(other), ItemKind.index_of(other)))
	var slots := occupied + _stack_slots(previous + count, ItemKind.max_stack(type, index))
	if slots > int(capacity[bag]):
		return false
	inventory[key] = previous + count
	Book.discover_item(progress, item_id)
	return true


static func _stack_slots(quantity: int, maximum: int) -> int:
	return int((quantity + maximum - 1) / maximum)
