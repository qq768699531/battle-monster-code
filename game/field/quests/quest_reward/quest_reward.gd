extends RefCounted
## 原生 `Field_Quest_Complete_SetResult` 的奖励模型。
##
## 任务完成页（状态 11）整页复用战斗结算窗（`Battle_Win_mPaint`／`mRun`／`mKeyPressed`），
## 所以这里的字段形状与 `BattleSettlement` 一致，`battle_ui/result.gd` 不做区分地渲染它。
## 奖励来源是任务记录而不是战斗：
##
## - 道具：`record+13` 的 16 位道具号 + `record+15` 数量（`Item_stdSet(...) == 1` 时 +48 计数）；
## - 经验：`record+23` 的 dword，**每名在场且 HP 不为 0 的队员都拿满额**（`BattleData+16..19` 同值），
##   另把 `v2 / 10` 记到属性进度条（`BattleData + 10 + 属性`）；
## - 金钱：`record+19` 的 dword → `BattleData+49`。
##
## 未建模：无。`*((int *)&ParamData.standard_progress + 7) > 0` 时经验 +20%（`v2 += v2 / 5`）
## 走 `StoryRuntime.experience_with_bonus`（经验加成窗口由第 7 组第 18 号道具开启）。

const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const BattleSettlement = preload("res://game/battle/combat/battle_settlement/battle_settlement.gd")
const MonsterAttribute = preload("res://game/growth/monster_attribute/monster_attribute.gd")

## 阈值、节奏与逐级升级都取 `BattleSettlement` 的同一份（`Battle_Win_mRun` 的两条路径共用）；
## 属性进度条的除数 `v2 / 10` 属于本页。
const ATTRIBUTE_DIVISOR := 10

var rows: Array[Dictionary] = []
var money := 0
var money_left := 0
var items: Array[Dictionary] = []
## 每名在场队员拿到的经验（原生四行都写同一个值）。
var experience := 0
## 属性进度条拿到的经验（`v2 / 10`）。
var attribute_experience := 0
var gain_frames := 0
var applied := false

var _money_before := 0


func _init(record: Dictionary, progress: Dictionary) -> void:
	var parameter: Variant = progress.get("parameter")
	# `Field_Quest_Complete_SetResult:39-41`：`v2 = record+23`，经验加成窗口内在
	# `BattleData+16` 落库前先 `v2 += v2 / 5`，六格进度也用加成后的 `v2 / 10`。
	experience = StoryRuntime.experience_with_bonus(parameter,
		int(record.get("reward_experience", 0)))
	attribute_experience = experience / ATTRIBUTE_DIVISOR
	money = int(record.get("reward_money", 0))
	money_left = money
	_money_before = int(parameter.get("moneyBalance", 0)) if parameter is Dictionary else 0
	_build_rows(progress)
	var item := int(record.get("reward_item", 0))
	var count := int(record.get("reward_item_count", 0))
	if item != 0 and count > 0:
		items.append({"id": item, "count": count})


## 主角行 + 在场且未阵亡的队员行（原生只给这三只发经验，空位不显示）。
func _build_rows(progress: Dictionary) -> void:
	var parameter: Dictionary = progress.get("parameter", {})
	var development: Dictionary = parameter.get("development", {})
	var hero_level := int(parameter.get("level", 1))
	rows.append(BattleSettlement.make_row("hero", -1, -1, 0, hero_level,
		int(development.get("experience", 0))))
	var monsters: Array = progress.get("monsters", [])
	var order: Array = MenuModel.native_party_order(progress)
	for slot in range(mini(3, order.size())):
		var index := int(order[slot])
		if index < 0 or index >= monsters.size():
			break
		var member: Dictionary = monsters[index]
		var arguments: Variant = member.get("nativeArguments")
		if not arguments is Array or arguments.size() < 2:
			break
		if int(member.get("hp", 0)) == 0:
			continue
		rows.append(BattleSettlement.make_row("member", index, int(member.get("species", arguments[0])),
			int(member.get("nickname", 0)), int(arguments[1]), int(member.get("experience", 0))))
	for row: Dictionary in rows:
		row.experience_left = experience


func shown_money() -> int:
	return _money_before + money - money_left


func is_finished() -> bool:
	return BattleSettlement.rows_finished(rows, money_left)


## 一次 `Battle_Win_mRun` 子状态 1 的推进：剩余量按 `BattleSettlement.GAIN_FRAMES` 帧均摊，
## 快进时一次发完；升级的行记 `BattleSettlement.FLASH_FRAMES` 帧高亮。
func step(fast: bool) -> Dictionary:
	gain_frames += 1
	var outcome := BattleSettlement.advance_frame(rows, gain_frames, money_left, fast)
	money_left = int(outcome["money_left"])
	return {"level_ups": outcome["level_ups"], "done": is_finished()}


## 交给宿主的发奖载荷。本工程没有「任务发钱／发道具」的既有通道（`story.gd` 只在
## `buy_item`／`sell_item`／`inn_rest` 里改 `moneyBalance`，`BattleSettlement.apply` 又只能由战斗构造），
## 所以入账由调用方接，这里只把原生算出来的量原样带出。
func payload() -> Dictionary:
	var item: Dictionary = items[0] if not items.is_empty() else {}
	return {
		"money": money,
		"experience": experience,
		"attribute_experience": attribute_experience,
		"item": int(item.get("id", 0)),
		"item_count": int(item.get("count", 0)),
	}


## 把金钱、主角与队员的等级／经验、属性进度写回存档（`Field_Quest_Complete_SetResult` 的副作用）。
## 与 `BattleSettlement.apply` 同一条规则：先把剩余量快进发完，再落盘；升级的队员按
## `Ball_stdBasic` 重算数值并回满 HP／SP。**道具不在这里入包**——背包规则只在 `story.gd` 里有一份，
## 由 `Story.grant_quest_reward()` 用 `items` 逐条走 `_add_inventory_item`。
func apply(progress: Dictionary, catalog: GameplayData) -> Dictionary:
	var report := {"items": [], "full": []}
	if applied or rows.is_empty():
		return report
	applied = true
	if not is_finished():
		step(true)
	var parameter: Dictionary = progress.get("parameter", {})
	if parameter.is_empty():
		return report
	var hero: Dictionary = rows[0]
	parameter["level"] = int(hero.level)
	parameter["moneyBalance"] = mini(999999999, int(parameter.get("moneyBalance", 0)) + money)
	var development: Variant = parameter.get("development")
	if development is Dictionary:
		development["experience"] = int(hero.experience)
		development["points"] = int(development.get("points", 0)) + int(hero.points)
		# `Field_Quest_Complete_SetResult` 的六格：每只在场且未阵亡的队员把自己那份
		# `总经验 / 10` 写进 `BattleData + 10 + 属性`（**赋值**，同属性的两只共享一格、不叠加），
		# 再由 `Battle_Win_mRun` 经 `Param_expSET` 入账；容器与阈值都在 `BattleSettlement`。
		if attribute_experience > 0:
			var gains: Array[int] = MonsterAttribute.zero_points()
			for index in range(1, rows.size()):
				var row: Dictionary = rows[index]
				var species: MonsterDefinition = catalog.monster(int(row.species)) \
					if catalog != null else null
				if species == null:
					continue
				var slot := MonsterAttribute.index_of(int(species.attribute_group))
				if slot < 0 or slot >= MonsterAttribute.COUNT:
					continue
				gains[slot] = attribute_experience
			BattleSettlement.add_mastery_experience(development, gains,
				BattleSettlement.preferred_mastery(progress))
	var monsters: Array = progress.get("monsters", [])
	for index in range(1, rows.size()):
		var row: Dictionary = rows[index]
		var member_index := int(row.member_index)
		if member_index < 0 or member_index >= monsters.size():
			continue
		var member: Dictionary = monsters[member_index]
		member["level"] = int(row.level)
		member["experience"] = int(row.experience)
		var arguments: Variant = member.get("nativeArguments")
		if arguments is Array and arguments.size() > 1:
			arguments[1] = int(row.level)
		var details := MenuModel.native_member_details(progress, catalog, member_index)
		var ball: Variant = details.get("ball")
		if bool(details.get("ok", false)) and ball != null and int(row.level) != int(row.start_level):
			member["hp"] = int(ball.max_hp)
			member["sp"] = int(ball.max_sp)
	return report
