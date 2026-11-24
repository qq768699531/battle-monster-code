extends Resource
class_name ItemDefinition

## 原生道具记录（`common/item_basic.dat`，书类来自 `item_skill.dat`）。
##
## `id` 是 `type * 1000 + index`；`icon` 是原生记录第 133 字节，直接作为
## `common/ui_item/frame-%03d` 的帧号，不再单独维护图标表。

@export var id: int
@export var type: int
@export var index: int
@export var grade_index: int
@export var icon: int
## 原生购买价；59 条书记录该字段为空，用 -1 表示未记录。
@export var purchase_price: int = -1
@export var name_record: String
@export var detail_slots: Array[int] = []

## 书类特有的结果条目；普通道具为空字符串。
@export var result_name_record: String = ""
@export var result_description_record: String = ""


## 名称所在的原生文本源：书类（`item_skill.dat`）的记录键是 `item_skill.…`，其余在
## `item_basic.dat`。`text_message()` 按源查，用错源会整条取不到正文。
static func name_source(record_key: String) -> String:
	return "common/item_skill.dat" if record_key.begins_with("item_skill.") \
		else "common/item_basic.dat"
