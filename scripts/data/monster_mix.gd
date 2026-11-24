extends RefCounted
class_name MonsterMix
## 精灵合成（`GAME_STATE_MONSTER_MIX` = 22）的业务规则。
##
## 三张设计表已经在 `MonsterMixTable`（`game\assets\monster-mix.tres`，取证见 `wiki\growth\monster-mix.md`），
## 这里只放 `Game_Monster_Mix_Proc` 的取值顺序与门槛，不另存任何表：
##
## 1. 品级：成功 `min(品级 + 1, 5)`、失败 `max(品级 − 1, 0)`（第 223–245 行）；
## 2. 后代属性组：两只的 `kind_specific_86_bits`（属性组 − 1）之和查 `unk_990B4 + 6` 的 11 项表
##    （第 246–249 行，`MonsterMixTable.target_group`）；
## 3. 候选物种：按定义号升序扫 `Item_datBasic(kind 29)` 0–199，收「属性组 == 目标组且品级 == 新品级」
##    的记录（第 259–323 行），遇第一条不存在的记录就停（`n200 != 200`）；
## 4. 判定树：`(候选数, 主位同族数, 主位同族序号 + 副位同族序号)` → 候选下标
##    （第 324–662 行，`MonsterMixTable.pick`）；`LABEL_96` 在原生置 `v15 = 0`，即结算成物种 0；
## 5. 结算：删两只、`Param_moneySET(-200)`、按 `Ball_stdSet` 建新记录（第 655–777 行）。

## `Game_Monster_Mix_Proc` 第 660 行的 `Param_moneySET(-200)`。
const FEE := 200
## `Game_Monster_Mix_mKeyPressed` 子状态 1 的门槛：`ParamData.money_balance > 0xC7`，
## 不够时弹 `msg 79`（与商店同一个记录号）。
const FEE_MINIMUM_MONEY := FEE - 1
## 判定树 `LABEL_96` 的落地值：原生把 `v15` 置 0，`Ball_stdSet` 收到的物种号就是 0。
const FALLBACK_SPECIES := 0
## `Item_datBasic` 的扫描上限（第 319 行 `if (n200 != 200) continue;`）。
const DEFINITION_LIMIT := 200
## `ParamData.ability_values[0]`：合成页一次性掷骰加成读槽 0（强化页读槽 1）。
const ABILITY_VALUE_INDEX := 0
## `MonsterDefinition.attribute_group` 是 1–6，记录里的 `kind_specific_86_bits` 是 0–5。
const ATTRIBUTE_INDEX_COUNT := 6


## `Game_Monster_Mix_SetJewel` 的过滤：袋 0 里 `item_kind == 7` 且定义号 4／5。
static func is_stone(item_id: int) -> bool:
	return ItemKind.kind_of(item_id) == ItemKind.Kind.GROUP_7 and \
		MonsterMixTable.STONE_PERCENT_SCALE.has(ItemKind.index_of(item_id))


## `ItemData.selected_enchant_item_0` → 定义号；没选或不是合成石时给
## `MonsterMixTable.NO_STONE`（`Game_Monster_Mix_Percent` 只认 4／5）。
static func stone_definition_id(item_id: int) -> int:
	return ItemKind.index_of(item_id) if is_stone(item_id) else MonsterMixTable.NO_STONE


## `Game_Monster_Mix_Proc` 第 223–245 行：成功升一级、失败降一级，都夹在 0–5。
static func grade_after(grade: int, success: bool) -> int:
	if success:
		return mini(grade + 1, MonsterMixTable.GRADE_MAX)
	return maxi(grade - 1, MonsterMixTable.GRADE_MIN)


## 判定与强化页同式（`if (v5 <= EFC_mainGetRAND() % 100)` 即失败），共用一处实现。
static func is_success(percent_value: int, roll: int) -> bool:
	return MonsterGrowth.is_success(percent_value, roll)


## 一次性掷骰加成：合成的 48 字节栈表 `v57[12]` 与 `MonsterGrowth.ABILITY_BONUS` 逐字节相同
## （按 `6 * (层 - 1) + 品级` 取 byte），触发概率也同式 `10 * 层 > rand() % 100`。
static func ability_bonus(ability: int, grade: int, roll: int) -> int:
	return MonsterGrowth.ability_bonus(ability, grade, roll)


## 记录第 134 字节 `kind_specific_86_bits`：工程字段减 1 才是 0–5 的组索引。
static func attribute_index(species: MonsterDefinition) -> int:
	if species == null:
		return 0
	return clampi(int(species.attribute_group) - 1, 0, ATTRIBUTE_INDEX_COUNT - 1)


## `Game_Monster_Mix_Proc` 第 223–662 行的候选与判定树。
## 返回 `{species, grade, group, position, candidates}`；`position` 是判定树给的下标，
## `MonsterMixTable.PICK_NONE` 时 `species` 落到 `FALLBACK_SPECIES`（原生 `v15 = 0`）。
static func resolve(catalog: GameplayData, primary_species: int, secondary_species: int,
		success: bool) -> Dictionary:
	var primary := catalog.monster(primary_species)
	var secondary := catalog.monster(secondary_species)
	if primary == null or secondary == null:
		return {"species": FALLBACK_SPECIES, "grade": MonsterMixTable.GRADE_MIN, "group": 0,
			"position": MonsterMixTable.PICK_NONE, "candidates": []}
	var grade := grade_after(int(primary.attribute_entry), success)
	var group := MonsterMixTable.target_group(attribute_index(primary), attribute_index(secondary))
	var scan := _scan(catalog, group, grade, primary, secondary)
	var position := MonsterMixTable.pick(scan["candidates"].size(), int(scan["family_count"]),
		int(scan["total"]))
	var species := FALLBACK_SPECIES
	if position >= 0 and position < scan["candidates"].size():
		species = int(scan["candidates"][position])
	return {"species": species, "grade": grade, "group": group, "position": position,
		"candidates": scan["candidates"]}


## 第 259–323 行：一次扫描同时收候选表与两个同族计数。
## - `candidates`：目标属性组 × 新品级的定义号，按定义号升序（原生存 `v66`，最多 6 个）；
## - `family_count`：主位同族（同属性组＋同品级）的物种数（`n2_1`）；
## - `total`：主位在同族里的序号（`n2_8`）＋副位在自己同族里的序号（`v49`）。
static func _scan(catalog: GameplayData, target_group: int, target_grade: int,
		primary: MonsterDefinition, secondary: MonsterDefinition) -> Dictionary:
	var candidates: Array[int] = []
	var family_count := 0
	var secondary_count := 0
	var primary_position := 0
	var secondary_position := 0
	var primary_group := attribute_index(primary)
	var secondary_group := attribute_index(secondary)
	var primary_grade := int(primary.attribute_entry)
	var secondary_grade := int(secondary.attribute_entry)
	var definition_id := 0
	while definition_id < DEFINITION_LIMIT:
		var species := catalog.monster(definition_id)
		if species == null:
			break
		var group := attribute_index(species)
		var grade := int(species.attribute_entry)
		if group == target_group and grade == target_grade and \
				candidates.size() < MonsterMixTable.CANDIDATE_LIMIT:
			candidates.append(definition_id)
		if group == primary_group and grade == primary_grade:
			if definition_id == int(primary.id):
				primary_position = family_count
			family_count += 1
		if group == secondary_group and grade == secondary_grade:
			if definition_id == int(secondary.id):
				secondary_position = secondary_count
			secondary_count += 1
		definition_id += 1
	return {"candidates": candidates, "family_count": family_count,
		"total": primary_position + secondary_position}
