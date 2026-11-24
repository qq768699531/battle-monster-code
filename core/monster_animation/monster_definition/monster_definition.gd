extends Resource
class_name MonsterDefinition

## 原生怪物物种记录（`common/item_mon.dat` 与 `item_stts.dat` 的组合）。
##
## `kind` 是战斗类别，`attribute_group`／`attribute_entry` 是属性分组与条目；
## `portrait_offset` 是菜单立绘按物种登记的对位偏移（普通、变异两档，缺省为零）。

@export var id: int
@export var kind: int
@export var attribute_group: int
@export var attribute_entry: int
@export var ability_inputs: Array[int] = []
@export var attribute_inputs: Array[int] = []
@export var name_record: String
@export var prime_portrait_position: int
@export var portrait_offset: Array[Vector2] = []
## 野外站立动画（动作 0）的帧数，原生每帧 0.05 秒。
@export var idle_frames: int


## 图标锚点：原生把物种记录的 `kind_specific_value_bits` 当成 `x * 100 + y` 用，
## x 取 C 的截断整除、y 取绝对值取余（`Menu_mon_DrawBookList:164-167` 的 `v40`／`v31`；
## 战斗结算 `Battle_Win_Draw` 与图鉴格用同一套）。未登记的物种（0）沿用导出表里最常见的
## `1231`，等导出工具补齐后自动生效。
const DEFAULT_ICON_ANCHOR := Vector2(12, 31)


static func icon_anchor(definition: MonsterDefinition) -> Vector2:
	var value := int(definition.prime_portrait_position) if definition != null else 0
	return Vector2(value / 100, absi(value) % 100) if value != 0 else DEFAULT_ICON_ANCHOR
