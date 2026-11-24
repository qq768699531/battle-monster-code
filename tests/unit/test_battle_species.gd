extends "res://tests/unit/gut_case.gd"


func test_legacy_suite() -> void:
	# 132 支 `Battle_Monster_00NN_procCurr` 全部导出；1–131 是 `item_mon.dat` 里存在的物种。
	var missing: Array = []
	for species in range(1, 132):
		if not BattleSpeciesTable.has(species):
			missing.append(species)
	assert_eq(missing, [], "每个物种都有动作分段")
	# 样本：物种 86 的技能是 8 段连击（`Battle_Monster_0086_procCurr` 的 `switch (n13 - 7)`），
	# 帧号与百分比照搬 switch 的 case。
	var hits: Array = BattleSpeciesTable.segments(86, true)[0]["hits"]
	assert_eq(hits.map(func(hit: Dictionary) -> Array:
		return [int(hit["frame"]), int(hit["percent"])]),
		[[7, 12], [9, 14], [11, 16], [13, 20], [20, 25], [22, 30], [24, 50], [26, 100]],
		"物种 86 的连击帧与比率")
	# 觉醒变体在物种号上加 1000，共用基础物种的动作回调。
	assert_true(BattleSpeciesTable.has(1099) and
		BattleSpeciesTable.segments(1099, false) == BattleSpeciesTable.segments(99, false),
		"1099 与 99 共用分段")
