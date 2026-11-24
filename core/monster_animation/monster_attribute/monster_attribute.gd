extends RefCounted
# 原生怪物的六属性（`item_mon.dat` 记录的第 134 字节是「属性组 − 1」，取值 0..5；
# `item_attr.dat` 的 1..6 组与之逐一对应，见 `wiki\data-format\dat-item-mon.md`／`wiki\data-format\dat-item-attr.md`）。
#
# 原生没有给这六个属性起名（`wiki\data-format\dat-item-attr.md`：「具体能力名称与单位尚未确证」），
# 所以按组号命名，不要按外观猜。同一个下标是这几处的下标，共用这一份枚举：
#
# - `Ball_datBasic` 输出的 `kind_specific_86_bits`（＝记录第 134 字节）；
# - `ParamData.mastery_progress[6]`：`Ball_stdBasic` 拿它当流派成长值；
# - 结果页六格属性经验 `BattleData + 10 + 属性`（写：`Field_Quest_Complete_SetResult`，
#   收：`Battle_Win_mRun` 末段的 `Param_expSET(0..5, ...)`）。
#
# 没有 `class_name`：只用 `preload` 引用，省掉为一处枚举再跑一次类缓存导入。

const COUNT := 6

## 等级上限：`Param_expSET` 用 `if (level > 0x62) break`（0x62 = 98，所以 98 级还能进 99）。
## 主角等级与六格流派等级共用这个上限；它是全仓唯一定义，菜单／结算／公会战都引用这里。
const LEVEL_MAX := 99
## `Param_stdInit` 把六格等级初始化成 1（`mastery_progress[i].level = 1`）。
const LEVEL_MIN := 1
## `Param_expINIT`：`next_level_threshold = 系数 × 等级²`；系数在
## `ParamData.preferred_mastery_index == i` 时是 **120**，其余是 **130**（主角等级用 65）。
## `Param_expSET` 的判定是 `while 余数 >= 阈值`，所以「达到」即升级：119 不升、120 升。
const THRESHOLD_FACTOR_PREFERRED := 120
const THRESHOLD_FACTOR_OTHER := 130

## 六属性本身；成员名就是原生 `item_attr.dat` 的组号（1..6），值是可作下标的 0..5。
enum Code {
	GROUP_1 = 0,
	GROUP_2 = 1,
	GROUP_3 = 2,
	GROUP_4 = 3,
	GROUP_5 = 4,
	GROUP_6 = 5,
}


## `MonsterDefinition.attribute_group` 是原生的 1..6 组号，落槽下标要减一
## （`Ball_stdBasic` 用 `byte_134 + 1` 回查 `item_attr.dat` 的组）。
static func index_of(attribute_group: int) -> int:
	return attribute_group - 1


## 六格清零数组：`Param_stdInit` 把 `mastery_progress[0..5].point_remainder` 清零，
## 结果页的 `BattleData + 10..15` 在 `Battle_Win_SetResult` 开头也整片清零。
static func zero_points() -> Array[int]:
	var points: Array[int] = []
	points.resize(COUNT)
	points.fill(0)
	return points


## 该格流派的阈值系数：`Param_expINIT` 的 `preferred_mastery_index == i ? 120 : 130`。
## `BattleSettlement.advance_levels` 按系数逐级扣阈值（系数 × 等级²）。
static func threshold_factor(preferred_mastery: int, index: int) -> int:
	return THRESHOLD_FACTOR_PREFERRED if preferred_mastery == index \
		else THRESHOLD_FACTOR_OTHER


## 该格流派的下一级阈值（原生 `Param_expINIT` 写进 `next_level_threshold`）。
## `preferred_mastery` 是 `ParamData.preferred_mastery_index`，未选／老存档用 -1。
static func threshold(preferred_mastery: int, index: int, level: int) -> int:
	return threshold_factor(preferred_mastery, index) * level * level
