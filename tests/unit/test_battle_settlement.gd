extends "res://tests/unit/gut_case.gd"

## 原生胜利结算（`Battle_Win_SetResult`／`Battle_Win_mRun`／
## `Battle_Drop_*`／`Param_expSET`／`Ball_stdEXP`）的数值与写回。

const Battle = preload("res://game/battle/combat/combat/battle.gd")
const Settlement = preload("res://game/battle/combat/battle_settlement/battle_settlement.gd")
const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")


## 固定随机序列：序列用完后一直返回最后一项，再按 `limit` 取整。
## 原生每个 `rand() % 100` 抽取值都由序列逐位给出，便于逐条核对掉落分支。
func _sequence(values: Array) -> Callable:
	var state := {"index": 0}
	return func(limit: int) -> int:
		var index: int = mini(int(state.index), values.size() - 1)
		state.index = index + 1
		return int(values[index]) % limit


## 永远返回 `limit - 1`：`rand()%100 == 99` 时不掉金币、不掉道具。
func _quiet(limit: int) -> int:
	return limit - 1


func _progress() -> Dictionary:
	var monsters: Array = []
	for species: int in [49, 62, 86]:
		monsters.append({"species": species, "level": 10,
			"nativeArguments": [species, 10, 0, -1, 0], "nickname": 0, "experience": 0,
			"hp": 40, "sp": 8})
	return {
		"parameter": {"identity": 0, "level": 1, "moneyBalance": 0,
			"standardProgressPoints": 0, "trait": 0,
			"development": {"experience": 0, "growth": [1, 1, 1, 1, 1, 1],
				"points": 0, "allocated": [0, 0, 0],
				"masteryExperience": [0, 0, 0, 0, 0, 0]}},
		"monsters": monsters, "partyOrder": [0, 1, 2], "inventory": {},
		"itemCapacity": [72, 72, 72, 72, 72, 72], "monsterCapacity": 20,
	}


## 三只 10 级敌人（属性组 3 → 属性索引 2、品级 0）＋三名存活队员，已判胜。
func _won_battle(catalog: GameplayData, enemy_level := 10) -> RefCounted:
	var enemies: Array = []
	for index in 3:
		enemies.append(Battle.make_ball(catalog, [49, enemy_level, -1, 0, 0, 0, 0, 0, -1, -1], 0))
	var party: Array = []
	for species: int in [49, 62, 86]:
		party.append(Battle.make_ball(catalog, [species, 10, -1, 0, 0, 0, 0, 0, -1, -1], 0))
	var battle := Battle.new(enemies, party)
	for ball: Dictionary in battle.balls.slice(0, 3):
		ball.hp = 0
	battle.select_actor()
	return battle


func test_legacy_suite() -> void:
	var catalog := Fixtures.battle_catalog()
	var battle := _won_battle(catalog)
	var progress := _progress()
	var quiet := Settlement.new(battle, progress, catalog, _quiet)
	assert_true(quiet.rows.size() == 4 and
		quiet.rows.all(func(row: Dictionary) -> bool: return int(row.experience_left) == 800) and
		int(quiet.money) == 0 and quiet.items.is_empty(),
		"base experience is (80 x 10 x 3) / 3 per row and a quiet roll drops nothing")
	quiet.step(true)
	quiet.apply(progress)
	assert_true(int(progress.parameter.level) == 3 and
		int(progress.parameter.development.experience) == 475 and
		int(progress.parameter.development.points) == 6,
		"level ups spend 65 x level^2 and keep the remaining experience")
	var money := Settlement.new(battle, progress, catalog, _quiet)
	money._random = _sequence([0, 0, 0])
	money._build_money(battle)
	assert_true(int(money.money) == 180, "three level-10 enemies drop 60 gold each")
	# 经验／金币按 GAIN_FRAMES 帧均摊：到第 n 帧就发完，不会像原生 1%／帧那样拖几百帧。
	var paced := Settlement.new(battle, _progress(), catalog, _quiet)
	paced.step(false)
	var moved: int = int(paced.rows[0].experience_left)
	assert_true(moved < 800 and not paced.is_finished(),
		"one tick spends part of the remainder instead of the whole gain")
	for frame in Settlement.GAIN_FRAMES:
		paced.step(false)
	assert_true(paced.is_finished(), "the gain animation finishes within GAIN_FRAMES ticks")
	# 六格属性经验（`BattleData + 10..15`）：普通胜利 `Battle_Win_SetResult` 只清零，
	# 唯一写值是任务完成那一路 `Field_Quest_Complete_SetResult` 的 `总经验 / 10`，
	# 且是 `=` 赋值——同属性两只怪写同一格、值相同所以不叠加。
	# 49／62 属属性组 3（下标 2），86 属属性组 4（下标 3）。
	var quest := Settlement.new(battle, _progress(), catalog, _quiet, false, Callable(), 800)
	assert_true(quest.mastery_experience == [0, 0, 80, 80, 0, 0],
		"each surviving member credits total/10 to its attribute slot once, never doubled")
	var saved := _progress()
	saved.parameter.development.masteryExperience = [5, 0, 5, 0, 0, 0]
	Settlement.new(battle, saved, catalog, _quiet, false, Callable(), 800).apply(saved)
	assert_true(saved.parameter.development.masteryExperience == [5, 0, 85, 80, 0, 0],
		"apply() adds the six slots onto development.masteryExperience")
	battle.balls[4] = {}
	battle.balls[5].hp = 0
	var absent := Settlement.new(battle, _progress(), catalog, _quiet, false, Callable(), 800)
	assert_true(absent.mastery_experience == [0, 0, 80, 0, 0, 0],
		"absent or knocked-out members credit no attribute experience")
	# 流派阈值（`Param_expINIT`／`Param_expSET`）：偏好流派 `120 × 等级²`、
	# 其余 `130 × 等级²`，「达到」才升级；升级不加能力点，余数留在 `masteryExperience`。
	var mastery := {"growth": [1, 1, 1, 1, 1, 1], "points": 0,
		"masteryExperience": [0, 0, 0, 0, 0, 0]}
	Settlement.add_mastery_experience(mastery, [119, 129, 0, 0, 0, 0], 0)
	assert_true(mastery.growth == [1, 1, 1, 1, 1, 1] and
		mastery.masteryExperience == [119, 129, 0, 0, 0, 0],
		"119 points stay below the 120 x level^2 preferred threshold, 129 below the 130 x level^2 other one")
	Settlement.add_mastery_experience(mastery, [1, 1, 0, 0, 0, 0], 0)
	assert_true(mastery.growth == [2, 2, 1, 1, 1, 1] and
		mastery.masteryExperience == [0, 0, 0, 0, 0, 0] and int(mastery.points) == 0,
		"the 120th and 130th points each level once, keep no remainder and grant no ability points")
	# 掉落入口由调用方给出时（故事层的 `_add_inventory_item`），`apply` 逐件回调并把结果记进报告。
	var dropped := Settlement.new(battle, _progress(), catalog, _quiet)
	dropped.items = [{"id": 3001, "type": 3, "index": 1, "count": 1}]
	var added: Array = []
	var hooked := dropped.apply(_progress(), func(item_id: int, count: int) -> bool:
		added.append([item_id, count])
		return true)
	assert_eq([added, hooked.items], [[[3001, 1]], [3001]],
		"apply() hands every drop to the supplied inventory entry instead of its own rule")
	# 战後心情到 999 的觉醒（`Battle_Win_SetResult` 的 `Ball_stdFeel` → `Ball_stdFeel`
	# 的 LABEL_5）：觉醒档置 1、心情归 0、HP／SP 按 `Ball_stdBasic` 重算后的上限回满。
	var awakening := _progress()
	awakening.monsters[0]["feel"] = ItemEffect.FEEL_MAX - 1
	Settlement.new(_won_battle(catalog), awakening, catalog, _quiet).apply(awakening)
	var evolved: Dictionary = awakening.monsters[0]
	var evolved_ball: Variant = Menu.native_member_details(awakening, catalog, 0).ball
	assert_eq([int(evolved.nativeArguments[2]), int(evolved.feel), int(evolved.hp),
		int(evolved.sp), int(evolved_ball.max_hp)],
		[1, 0, int(evolved_ball.max_hp), int(evolved_ball.max_sp), int(evolved_ball.max_hp)],
		"feel 999 awakens the record: awakened flag, feel reset and HP/SP refilled")
