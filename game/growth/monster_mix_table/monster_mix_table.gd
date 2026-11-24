extends Resource
class_name MonsterMixTable
## 合成页（`GAME_STATE_MONSTER_MIX` = 22）的三张设计表：候选物种判定树、两只属性组之和 → 后代属性组、
## 品级 → 成功率基数。数据源是反编译代码与 `.rodata` 常量池，由
## `script\export_monster_mix.py` 生成（纯离线），不要手改本文件；取证全文见 `wiki\growth\monster-mix.md`。
##
## `Game_Monster_Mix_Proc` 的结算顺序：品级 `n5`（成功 +1／失败 −1）→ 属性组之和查组表 →
## 在「目标属性组 × 品级 `n5`」的物种里收集候选（按定义号升序，最多 6 个）→ 由判定树按
## `(候选数, 主位同族数, 主位同族序号 + 副位同族序号)` 选一个候选。
##
##     candidate_pick = {候选数: {主位同族数: [和 0..8 各一格 → 候选序号或 PICK_NONE]}}
##
## 判定树是**设计表**，不是公式：同一行里 0/1 的两格取值可以不同（`(2, 4)` 的和 0 取候选 1）。

## 数据文件；与 `battle-poses.tres` 一样是生成物。
const TABLE_PATH := "res://engine/anim/monster_animation/monster-mix.tres"

## `kind_specific_84_bits`（记录第 132 字节，`Ball_stdBasic` 用它取属性组内记录）的取值范围，
## 即品级：`Game_Monster_Mix_mKeyPressed` 对 `== 5` 的精灵直接弹 `msg 117`「不能合成」，
## `Game_Monster_Mix_Proc` 的成功分支是 `min(品级 + 1, 5)`、失败分支是 `max(品级 − 1, 0)`。
const GRADE_MIN := 0
const GRADE_MAX := 5
## 判定树 `LABEL_96`（组合非法）对应的值：原生在那里置 `v15 = 0`，即结算成物种 0。
## 这是「没有候选」的标记，不是「第 0 个候选」。
const PICK_NONE := -1
## 候选表 `v66`＋紧邻的 `v67` 最多存 6 个 byte，判定树最多返回下标 5。
const CANDIDATE_LIMIT := 6
## `Game_Monster_Mix_Percent` 末段 `if (n100 > 100) return 100`。
const PERCENT_CAP := 100
## `ItemData.selected_enchant_item_0` 为空时的定义号（原生判的是指针非空，移植侧用负值表示没选）。
const NO_STONE := -1

## `Game_Monster_Mix_SetJewel` 只收 `kind 7` 且 `(definition_id - 4) <= 1` 的道具，
## 也就是定义号 4／5 两种合成石；`Game_Monster_Mix_Percent` 对它们分别
## `n100 = 170 * n100 / 100` 与 `220 * n100 / 100`。两种石头的道具本名未确认，按倍率命名。
enum MixStone {
	SCALE_170 = 4,
	SCALE_220 = 5,
}
## 合成石定义号 → 百分比倍率（百分数，170 即 ×1.7）。
const STONE_PERCENT_SCALE := {
	MixStone.SCALE_170: 170,
	MixStone.SCALE_220: 220,
}

@export var percent_by_grade: Array[int] = []
## 两只 `kind_specific_86_bits`（记录第 134 字节＝属性组 − 1，工程里是 `attribute_group - 1`）
## 之和 0–10 → 后代的属性组索引。原生初始化成 0，只在 `和 <= 10` 时查表。
@export var target_group_by_pair: Array[int] = []
@export var candidate_pick: Dictionary = {}


static func data() -> MonsterMixTable:
	return load(TABLE_PATH) as MonsterMixTable


## `Game_Monster_Mix_Percent`：`percent_by_grade[品级]`，槽 0 选了合成石再乘倍率，
## 最后 `> 100` 取 100。`stone_definition_id` 是 `ItemData.selected_enchant_item_0` 的定义号，
## 没选时传 `NO_STONE`。
static func percent(grade: int, stone_definition_id: int = NO_STONE) -> int:
	var table := data()
	var value: int = table.percent_by_grade[clampi(grade, GRADE_MIN,
		table.percent_by_grade.size() - 1)]
	if STONE_PERCENT_SCALE.has(stone_definition_id):
		value = int(STONE_PERCENT_SCALE[stone_definition_id]) * value / 100
	return mini(value, PERCENT_CAP)


## `Game_Monster_Mix_Proc` 第 246–249 行：`和 = 两只的 kind_specific_86_bits`，
## `和 <= 10` 才查组表，否则 0。参数是属性组索引（`MonsterAttribute.index_of(attribute_group)`）。
static func target_group(primary_group_index: int, secondary_group_index: int) -> int:
	var table := data()
	var total := primary_group_index + secondary_group_index
	if total < 0 or total >= table.target_group_by_pair.size():
		return 0
	return table.target_group_by_pair[total]


## 判定树取候选序号；`candidate_count` 是目标属性组在品级 `n5` 上的物种数，`family_count` 是
## 主位同族（属性组＋品级都相同）的物种数，`total` 是主位与副位各自同族序号之和。
## 树里没有这一格时返回 `PICK_NONE`。
static func pick(candidate_count: int, family_count: int, total: int) -> int:
	var rows: Dictionary = data().candidate_pick.get(candidate_count, {})
	var row: Array = rows.get(family_count, [])
	if total < 0 or total >= row.size():
		return PICK_NONE
	return int(row[total])
