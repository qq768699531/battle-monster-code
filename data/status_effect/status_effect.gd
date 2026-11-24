extends RefCounted
class_name StatusEffect
## 战斗状态码（`ball.statuses` 的键）与它们在 `obj/b_effect` 上的图标动作。
##
## 状态码是原生 `Param_*`／`Battle_Monster_procCurr` 里直接比较的数值；
## 图标是相邻两个动作——第一个播完接着播后一个（循环）。
##
## 状态码同时是**主动效果槽**的下标：槽地址 = 球记录 + 60 + 12 × 状态码，12 字节一槽
## （`Param_activeSet` 写、`Param_activeInit` 清）：
##   +0 id（`int16`）：强度档，`6 × 相性档 − 3`，即相性有利 3、不利 −3；中毒槽用它当
##      「剩余档位」逐回合递减；
##   +2 层数（`int16`）：每次施加 +1；
##   +4 持续值（`int16`）：`Param_activeSet` 的第三个参数 + 1；
##   +6 保留；
##   +8 强度值（`int32`）：`max(旧值, 本次参数)`，只有中毒槽会用（施加瞬间的 HP）。
## `ball.statuses[码]` 就是这一槽的 `{stacks, remaining, value}` 表示。

enum Code {
	SEAL = 7,        ## 封印：技能不可用（`battle.gd` 的 `skill_available`）
	WEAKNESS = 21,   ## 弱点：受击伤害按状态层数加成
	POISON_HIGH = 27, ## 中毒一段（`Param_dmgPOISON` 的第 1 槽）
	POISON_MID = 28,  ## 中毒二段
	POISON_LOW = 29,  ## 中毒三段
	DEFENCE = 33,     ## 防御：`Battle_Defence_init` 写的那一槽，防御力 +100% 每层
}

## 中毒的三段槽，下标与 `battle.gd` 的 `POISON_PERCENT` 对应。
const POISON_CODES := [Code.POISON_HIGH, Code.POISON_MID, Code.POISON_LOW]

## 槽的语义（按 `Param_atk1/2ACTIVE`／`0x76FE0`、`Param_def1/2ACTIVE`／`0x770FC`
## 的读取点归纳），只用于本工程的说明文字；原生没有这些名字。
## 1 与 6 是技能码（槽号）本身没有读取点、但 `Param_dmg2SKILL` 的 `case 1`／`case 6`
## 会给那一槽附上 active 12（攻击↑）／active 7（封印），所以按它们带的状态命名。
const LABELS := {
	1: "攻击↑", 6: "封印",
	7: "封印",
	9: "防御↓", 10: "防御↓", 11: "防御↓",
	12: "攻击↑", 13: "攻击↑",
	14: "技能攻击↑", 15: "技能攻击↑", 16: "技能攻击↑", 17: "技能攻击↑",
	18: "受伤↑", 19: "受伤↑", 20: "受伤↑",
	21: "弱点",
	22: "攻击↓", 23: "攻击↓",
	24: "受伤↓", 25: "受伤↓", 26: "受伤↓",
	27: "中毒", 28: "中毒", 29: "中毒",
	30: "狂暴", 31: "狂暴", 32: "狂暴",
	33: "防御",
	38: "减速", 39: "减速", 40: "减速",
}

enum Icon {
	WEAKNESS = 23,
	SEAL = 32,
}
