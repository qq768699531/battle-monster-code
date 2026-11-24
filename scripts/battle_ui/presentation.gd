extends RefCounted
## 战斗表现步骤的编排（纯计算，不直接绘制）。

const Menu = preload("res://scripts/menu_model.gd")
const SlotGrade = preload("res://scripts/data/slot_grade.gd")

var assets: Node
var catalog: GameplayData


func _init(source: Node) -> void:
	assets = source
	catalog = assets.load_gameplay_catalog()


func message(id: int) -> String:
	return assets.text_message(Msg.SOURCE, id)


func item_name(item: Dictionary) -> String:
	var record_key := str(item.get("name_record", ""))
	if not record_key.is_empty():
		# 名称记录键决定文本源：书类是 `common/item_skill.dat`、普通道具是
		# `common/item_basic.dat`（`ItemDefinition.name_source`；原生 `Item_stdAddEx:73-76`
		# 与结算窗口都按道具记录自己的名字取，不能只查一份表）。
		var messages: Dictionary = assets.text_messages(ItemDefinition.name_source(record_key))
		var text := str(messages.get(record_key, ""))
		if not text.is_empty():
			return text
	return str(item.get("name", "--"))


func item_color(item: Dictionary) -> Variant:
	var grade: int = int(item.get("grade_index", -1))
	return SlotGrade.ITEM_GRADE_RGB[grade] if grade in range(SlotGrade.ITEM_GRADE_RGB.size()) else null


func item_texture(item: Dictionary) -> Texture2D:
	var icon: int = int(item.get("icon", -1))
	return assets.item_icon(icon)

## 立绘偏移随怪物记录登记，缺省为 `Vector2.ZERO`；`variant` 为 0 普通形态、1 变异形态。
func portrait_offset(species_id: int, variant: int) -> Vector2:
	var record: MonsterDefinition = catalog.monster(species_id)
	if record == null or variant < 0 or variant >= record.portrait_offset.size():
		return Vector2.ZERO
	return record.portrait_offset[variant]


func item_explanation(item: Dictionary) -> String:
	return Menu.native_item_explanation(item, message)
