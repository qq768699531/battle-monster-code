extends RefCounted
class_name MonsterGrowth
## 精灵强化（`GAME_STATE_MONSTER_ENCHANT` = 23）的业务规则。
##
## 全部来自 `Game_Monster_Enchant_*` 的反编译结果（取证见 `wiki\growth\game-monster-list.md` §7）：
## - `Game_Monster_Enchant_SetJewel`：可选强化剂 = 袋 0 里 `kind 7` 且定义号 ∈ {0,1,2,19}；
## - `Game_Monster_Enchant_GetJewel`：槽 0 是「超级强化剂」（一次 1 个）或按属性组的默认强化剂
##   （要 `brain_current + 1` 个）；槽 1 是任何其它强化剂，加成 `10 × (定义号 + 1)`；
## - `Game_Monster_Enchant_Percent`：成功率 = `100 − brain_current + 槽 1 加成`，上限 100；
## - `Game_Monster_Enchant_Proc`：一次性掷骰加成 + 消耗 + `Param_moneySET(-100)` +
##   `Ball_stdBrain` 判定；失败会把 `brain_limit` 压到当前 `brain_current`（`Ball_stdBrain`）。
##
## 这里只放纯数据与算式：背包扣减、提示栈、存档由页面脚本调用存档层完成。

## `Game_Monster_Enchant_Percent` 的基数与上限（`n100 = 100 - brain_current`，
## 结果 `> 100` 时返回 100）。
const PERCENT_BASE := 100
const PERCENT_MAX := 100
## 同一函数的槽 1 加成：`n100 += 10 * (*(__int16 *)v3 + 3) + 1)`，即 `10 × (定义号 + 1)`。
const ORB_PERCENT_STEP := 10
## `Game_Monster_Enchant_Proc`／`_Percent` 的掷骰都是 `EFC_mainGetRAND() % 100`。
const ROLL_MODULUS := 100
## `Game_Monster_Enchant_Proc` 的 `Param_moneySET(-100)`。
const FEE := 100
## 同函数的 `v6 = (ParamData.ability_values[1] - 1) / 30 + 1`、`n10 = 10 * v6`：
## 能力每 30 点一层，每层 10% 机会触发额外加成。
const ABILITY_TIER_STEP := 30
const ABILITY_ROLL_PER_TIER := 10
## `Game_Monster_Enchant_Proc` 的 48 字节栈表 `v11[12]`，按 `6 * (层 - 1) + 品级` 取 byte：
## 层 1..8、品级 0..5。数值与 `Battle.CAPTURE_BONUS`（`Battle_Capture_Action_IsCapture`）
## 相同，但这里是另一处独立表，别混用。
const ABILITY_BONUS := [[5, 4, 3, 2, 1, 1], [6, 5, 4, 3, 1, 1], [7, 6, 5, 4, 2, 2],
	[8, 7, 6, 5, 2, 2], [9, 8, 7, 6, 3, 3], [10, 9, 8, 7, 3, 3],
	[11, 10, 9, 8, 4, 4], [12, 11, 10, 9, 4, 4]]
## `Game_Monster_Get`／`SetJewel` 的 `1245191` 拆开就是 `(19 << 16) | 7`：`kind 7` 的 19 号。
const SUPER_ENHANCER_INDEX := 19
## `Game_Monster_Enchant_SetJewel` 的筛选位掩码 `0x80007`：定义号 0／1／2／19。
const ENHANCER_INDEXES := [0, 1, 2, SUPER_ENHANCER_INDEX]
## `Game_Monster_Enchant_GetJewel` 的默认强化剂表（栈上 6 字节 `1E1B1A19` + `1D1C`）：
## 按 `byte_134`（属性组 − 1）取 `kind 1` 的定义号，依次是水／火／木／风／光／暗之强化剂。
const ENHANCER_BY_ATTRIBUTE_GROUP := [25, 26, 27, 30, 28, 29]
const ENHANCER_KIND := ItemKind.Kind.CONSUMABLE


## `Ball_datBasic` 的 `kind_specific_84_bits`：`Ball_stdBasic` 用 `byte_132`（属性条目）取
## 六项数值的品级，工程里对应 `MonsterDefinition.attribute_entry`。
static func grade_of(species: MonsterDefinition) -> int:
	return int(species.attribute_entry) if species != null else 0


## `Game_Monster_Enchant_GetJewel` 的默认强化剂：属性组（1–6）→ `byte_134`（0–5）。
static func attribute_enhancer_id(species: MonsterDefinition) -> int:
	var group_index := 0
	if species != null:
		group_index = clampi(int(species.attribute_group) - 1, 0,
			ENHANCER_BY_ATTRIBUTE_GROUP.size() - 1)
	return ItemKind.id_of(ENHANCER_KIND, ENHANCER_BY_ATTRIBUTE_GROUP[group_index])


## `Game_Monster_Enchant_SetJewel` 的过滤：`kind 7` 且定义号在 `0x80007` 的位里。
static func is_enhancer(item_id: int) -> bool:
	return ItemKind.kind_of(item_id) == ItemKind.Kind.GROUP_7 and \
		ENHANCER_INDEXES.has(ItemKind.index_of(item_id))


static func is_super_enhancer(item_id: int) -> bool:
	return is_enhancer(item_id) and ItemKind.index_of(item_id) == SUPER_ENHANCER_INDEX


## `Game_Monster_Enchant_Percent`：`100 − brain_current`，槽 1 的强化剂再 +10 × (定义号 + 1)，
## 上限 100。`orb_index` 是槽 1 强化剂的定义号，−1 表示没选。
static func percent(brain_current: int, orb_index: int) -> int:
	var value := PERCENT_BASE - brain_current
	if orb_index >= 0:
		value += ORB_PERCENT_STEP * (orb_index + 1)
	return mini(value, PERCENT_MAX)


## `Game_Monster_Enchant_Proc` 的 `(ability_values[1] - 1) / 30 + 1`，能力为 0 时按 1 层算。
static func ability_tier(ability: int) -> int:
	return clampi((ability - 1) / ABILITY_TIER_STEP + 1, 1, ABILITY_BONUS.size()) if ability > 0 \
		else 1


## 同上函数的 `n10 = 10 * v6`：一次 `rand() % 100` 要多小才算触发加成。
static func ability_chance(ability: int) -> int:
	return ABILITY_ROLL_PER_TIER * ability_tier(ability)


## 触发后按 `ABILITY_BONUS[层 - 1][品级]` 加的成功率；没触发返回 0（原生此时也不弹 `msg 558`）。
static func ability_bonus(ability: int, grade: int, roll: int) -> int:
	if roll >= ability_chance(ability):
		return 0
	var tier := ability_tier(ability)
	var row: Array = ABILITY_BONUS[tier - 1]
	return int(row[clampi(grade, 0, row.size() - 1)])


## `Game_Monster_Enchant_GetJewel` 的一次强化消耗：`{id, count}`。
## 槽 0 选了超级强化剂就是它 1 个，否则是属性组对应的默认强化剂 `brain_current + 1` 个。
static func enhancer_requirement(species: MonsterDefinition, brain_current: int,
		super_selected: bool) -> Dictionary:
	if super_selected:
		return {"id": ItemKind.id_of(ItemKind.Kind.GROUP_7, SUPER_ENHANCER_INDEX), "count": 1}
	return {"id": attribute_enhancer_id(species), "count": brain_current + 1}


## `Game_Monster_Enchant_IsProc`：持有量够不够这次消耗。
static func is_ready(owned: Dictionary, species: MonsterDefinition, brain_current: int,
		super_selected: bool) -> bool:
	var need := enhancer_requirement(species, brain_current, super_selected)
	return int(owned.get(int(need["id"]), 0)) >= int(need["count"])


## `Game_Monster_Enchant_Proc` 的收尾：`Ball_stdBrain` 的
## 成功 `brain_current = min(brain_current + 1, brain_limit)`、
## 失败 `brain_limit = brain_current`（失败会锁住这只精灵，不能再强化）。
static func apply_brain(monster: Dictionary, success: bool) -> void:
	if success:
		monster["brainCurrent"] = mini(int(monster["brainCurrent"]) + 1, int(monster["brainLimit"]))
	else:
		monster["brainLimit"] = int(monster["brainCurrent"])


## `Game_Monster_Enchant_Proc` 的判定 `if (v1 > (int)EFC_mainGetRAND() % 100)`。
static func is_success(percent_value: int, roll: int) -> bool:
	return percent_value > roll
