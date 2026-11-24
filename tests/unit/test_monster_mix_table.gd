extends "res://tests/unit/gut_case.gd"

## 合成页（`GAME_STATE_MONSTER_MIX` = 22）的数据表：`Game_Monster_Mix_Proc` 的候选判定树、
## `.rodata` 0x990CC 的属性组表和 `Game_Monster_Mix_Percent` 的品级成功率表。
## 数据由 `script\export_monster_mix.py` 生成（纯离线），取证见 `wiki\growth\monster-mix.md`。


func test_legacy_suite() -> void:
	var table := MonsterMixTable.data()
	assert_eq([table.percent_by_grade.size(), table.target_group_by_pair.size(),
		table.candidate_pick.size()], [6, 11, 4], "成功率 6 项、组表 11 项、判定树 4 个候选数")
	# 判定树的维度：候选数 2–5 × 主位同族数 2–5 × 序号和 0–8，共 144 格。
	var cells := 0
	for candidate_count: int in table.candidate_pick:
		for family_count: int in table.candidate_pick[candidate_count]:
			assert_eq(table.candidate_pick[candidate_count][family_count].size(), 9,
				"判定树 (%d, %d) 应覆盖和 0–8" % [candidate_count, family_count])
			cells += 1
	assert_eq(cells, 16, "判定树 4×4 个分支")
	# 关键格：候选数 2、主位同族数 4 时和 0 取候选 1（不是 0）；和 3 落进 `& 0xE` 取候选 0。
	assert_eq([MonsterMixTable.pick(2, 4, 0), MonsterMixTable.pick(2, 4, 3),
		MonsterMixTable.pick(5, 5, 8), MonsterMixTable.pick(2, 2, 3),
		MonsterMixTable.pick(6, 3, 0)],
		[1, 0, 3, MonsterMixTable.PICK_NONE, MonsterMixTable.PICK_NONE],
		"判定树关键格与超出范围的候选数")
	# 成功率：品级 0 → 90、品级 5 → 0；合成石 5 是 ×2.2（60 × 220 / 100 = 132 截到 100），
	# 合成石 4 是 ×1.7（5 × 170 / 100 = 8，整数截断）。
	assert_eq([MonsterMixTable.percent(0), MonsterMixTable.percent(5),
		MonsterMixTable.percent(1, MonsterMixTable.MixStone.SCALE_220),
		MonsterMixTable.percent(3, MonsterMixTable.MixStone.SCALE_170)],
		[90, 0, 100, 8], "品级成功率与合成石倍率")
	# 组表：0–10 各一项，越界按原生初始化值 0。
	assert_eq([MonsterMixTable.target_group(0, 0), MonsterMixTable.target_group(1, 2),
		MonsterMixTable.target_group(5, 5), MonsterMixTable.target_group(5, 6)],
		[3, 1, 1, 0], "属性组之和 → 后代属性组")
