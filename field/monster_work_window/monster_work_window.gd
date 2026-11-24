extends "res://field/field_window/field_window.gd"

## 精灵管理所两页共用的部分：合成（`GAME_STATE_MONSTER_MIX`，22）与强化
## （`GAME_STATE_MONSTER_ENCHANT`，23）。
##
## 两页的原生 init 都是「`Game_Monster_SetList` 建 6 格精灵表 → `_SetJewel`／`GetJewel` 建 6 格
## 道具表」，绘制都是 `Game_Monster_DrawList` + `Game_Monster_DrawInfo1`，读数都取包裹与
## `ParamData.money_balance`。所以列表格、道具格、包裹与金额读数放这里；子状态机、成功率与
## 结算仍留在各自页面（原生 `Game_Monster_Mix_Proc` 与 `Game_Monster_Enchant_Proc` 完全不同）。

const MessageStack = preload("res://core/message_stack/message_stack.gd")
const Menu = preload("res://menu/menu_model/menu_model.gd")
const SlotFrame = preload("res://data/slot_frame/slot_frame.gd")

## `Game_Monster_DrawList` 的 6 列 × 1 行；子状态 2 的换页也是这个宽度
## （`_mKeyPressed` 的 `% v7`、`v7 = 6 * ((数量 + 5) / 6)`）。
const MONSTER_COLUMNS := 6
## 道具表的 6 格（`Game_Monster_Enchant_DrawItem`／合成页的合成石表）。
const VISIBLE_ITEMS := 6
## 确认框的两个选项（原生 `transition_parameter_bits + 6` 的游标取值）。
const CHOICE_COUNT := 2

## 列表格子的背景帧（`Menu_winDrawIcon16` 的 30×30 四帧，与其它页面共用 `assets/ui/slot/`，顺序见 `SlotFrame.Frame`）。
@export var cell_frames: Array[Texture2D] = []

var cursor := 0
var item_cursor := 0

var _story: Object
var _assets: Node
## `Game_Monster_SetList` 的精灵表；两页的条目形状不同（强化页存记录本身，合成页存
## `index`／`record`／`species`），共同点是都有 `species`。
var _monsters: Array = []
## 子状态 2 的道具表（强化剂或合成石），袋内顺序即道具号升序（原生 `Item_bagList`）。
var _items: Array[int] = []


func _catalog() -> GameplayData:
	return _assets.load_gameplay_catalog()


func _text(message_id: int) -> String:
	return _assets.text_message(Msg.SOURCE, message_id)


func _ball(slot: int) -> ItemCell:
	return get_node("Content/Ball%d" % slot) as ItemCell


func _item_cell(slot: int) -> ItemCell:
	return get_node("Content/Items/Cell%d" % slot) as ItemCell


func _ball_texture(species: MonsterDefinition) -> Texture2D:
	if species == null:
		return null
	var icon_id: Variant = Menu.menu_ball_icon(int(species.attribute_group))
	if icon_id == null:
		return null
	return _assets.load_sprite("common/ui_item/frame-%03d" % int(icon_id))


func _monster_name(species: MonsterDefinition, nickname: int) -> String:
	var prefix := ""
	if nickname > 0:
		prefix = _text(Msg.Id.NICKNAME_PREFIX + nickname) + " "
	return prefix + _assets.text_messages("common/item_mon.dat").get(
		"item_mon.group.%d.name" % int(species.id), "")


func _item_name(record: ItemDefinition) -> String:
	return _assets.text_message("common/item_basic.dat", record.name_record) \
		if record != null and not record.name_record.is_empty() else ""


func _inventory() -> Dictionary:
	var inventory: Variant = _story.progress.get("inventory", {})
	var counts := {}
	if inventory is Dictionary:
		for key: Variant in inventory:
			var text := str(key)
			if text.is_valid_int() and int(inventory[key]) is int:
				counts[int(text)] = int(inventory[key])
	return counts


## 背包里某个道具号的持有数。
func _owned(item_id: int) -> int:
	return int(_inventory().get(item_id, 0))


func _money() -> int:
	var parameter: Variant = _story.progress.get("parameter", {})
	return int(parameter.get("moneyBalance", 0)) if parameter is Dictionary else 0


## `ParamData.ability_values[slot]`：两页读的槽不同（合成读 0、强化读 1），取不到就是 0。
func _allocated_value(slot: int) -> int:
	var parameter: Variant = _story.progress.get("parameter", {})
	if not parameter is Dictionary:
		return 0
	var development: Variant = parameter.get("development", {})
	if not development is Dictionary:
		return 0
	var allocated: Variant = development.get("allocated", [])
	if not allocated is Array or allocated.size() <= slot or not allocated[slot] is int:
		return 0
	return int(allocated[slot])


## `_mKeyPressed` 子状态 2 的换页跨度：`v7 = 6 * ((数量 + 5) / 6)`。
func _item_span() -> int:
	return MONSTER_COLUMNS * ((_items.size() + MONSTER_COLUMNS - 1) / MONSTER_COLUMNS)


## 子状态 2 的道具表游标移动（−1／−2 换页 ×6、−3／−4 单格）。
func _move_item(step: int, span: int) -> bool:
	if span <= 0:
		return true
	item_cursor = posmod(item_cursor + step, span)
	_refresh()
	return true


## 子类实现：按当前游标重画（两页的格阵与角标不同，基类只留这一个钩子）。
func _refresh() -> void:
	pass


## 袋里还持有、且 `accepts` 认的道具号，按道具号升序（原生 `Item_bagList` 的袋内顺序）。
func _owned_item_ids(accepts: Callable) -> Array[int]:
	var inventory := _inventory()
	var ids: Array[int] = []
	for key: Variant in inventory:
		var text := str(key)
		if not text.is_valid_int():
			continue
		var item_id := int(text)
		if int(inventory[key]) > 0 and bool(accepts.call(item_id)):
			ids.append(item_id)
	ids.sort()
	return ids


## 6 格精灵表：空位也画格底（原生 `Menu_Party_DrawBall(..., 0, 0)` 对超出行数的格照画），
## 只省图标与两个角标。角标状态由子页给（强化页标出战位，合成页标主／副位）。
func _refresh_monster_cells() -> void:
	for slot in range(MONSTER_COLUMNS):
		var ball := _ball(slot)
		var has_monster := slot < _monsters.size()
		var focused := slot == cursor
		ball.visible = true
		ball.present_frame(SlotFrame.frame_of(cell_frames, true, focused), focused)
		if not has_monster:
			ball.get_node("Icon").texture = null
			ball.get_node("Marker").visible = false
			ball.get_node("EquipmentMarker").visible = false
			continue
		var entry: Dictionary = _monsters[slot]
		var species: MonsterDefinition = _catalog().monster(int(entry.get("species", -1)))
		ball.get_node("Icon").texture = _ball_texture(species)
		ball.get_node("Quantity").hide()
		ball.set_grade(null)
		ball.get_node("Marker").visible = _monster_marked(slot, entry)
		ball.get_node("EquipmentMarker").visible = _monster_equipped(slot, entry)


## 6 格道具表：空格同样照画格底（`Game_Monster_Enchant_DrawItem@0x43548:32` 对空格也传 `a6 = 1`）。
func _refresh_item_cells() -> void:
	for slot in range(VISIBLE_ITEMS):
		var cell := _item_cell(slot)
		var has_item := slot < _items.size()
		var focused := slot == item_cursor
		cell.visible = true
		cell.present_frame(SlotFrame.frame_of(cell_frames, true, focused), focused)
		if not has_item:
			cell.get_node("Icon").texture = null
			cell.set_grade(null)
			cell.get_node("QuantityNumber").hide()
			cell.get_node("Marker").visible = false
			continue
		var item_id := _items[slot]
		var record: ItemDefinition = _catalog().item(item_id)
		cell.set_grade(null)
		cell.get_node("QuantityNumber").hide()
		cell.get_node("Icon").texture = _assets.item_icon(record.icon) if record != null and \
			record.icon >= 0 else null
		cell.get_node("Marker").visible = _marked_item(item_id)
	var chosen := _items[item_cursor] if item_cursor < _items.size() else -1
	var record: ItemDefinition = _catalog().item(chosen) if chosen >= 0 else null
	$Content/Items/ItemName.text = "[ %s ]" % _item_name(record) if record != null else ""


## 子页实现：该格精灵是否画选中角标。
func _monster_marked(_slot: int, _entry: Dictionary) -> bool:
	return false


## 子页实现：该格精灵是否画装备角标（原生 `equipment_code > 0`）。
func _monster_equipped(_slot: int, _entry: Dictionary) -> bool:
	return false


## 子页实现：该道具在格上是否画选中角标。
func _marked_item(_item_id: int) -> bool:
	return false
