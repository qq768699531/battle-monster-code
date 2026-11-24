extends Control
## 战斗道具窗口。

signal chosen(item: Dictionary)
signal cancelled

const Menu = preload("res://scripts/menu_model.gd")

@export var categories: Array[Texture2D] = []
@export var frames: Array[Texture2D] = []

var rows: Array[Dictionary] = []
var selected := 0
var scroll_start := 0
var mode := "item"
var _accepted := false
var _presentation: RefCounted
var _progress: Dictionary


func _ready() -> void:
	$Window.transition_finished.connect(_transition_finished)
	for slot in 18:
		%Grid.get_child(slot).pressed.connect(func(): select(scroll_start + slot, true))
	%Scrollbar.get_node("UpHit").pressed.connect(func(): select(posmod(selected - 6, slot_count())))
	%Scrollbar.get_node("DownHit").pressed.connect(func(): select(posmod(selected + 6, slot_count())))


## `previous` 只在从目标选择退回道具窗口时传入（原生保留光标位置），其余情况从第一格开始。
func open_items(kind: String, progress: Dictionary, presentation: RefCounted,
		previous: Dictionary = {}) -> bool:
	mode = kind
	_progress = progress
	_presentation = presentation
	rows = Menu.native_inventory_rows(progress, presentation.catalog,
		ItemKind.Bag.CAPTURE_BALLS if mode == "capture" else ItemKind.Bag.ITEMS)
	if mode == "item":
		# 普通道具页只列消耗品（19–30 号是属性提升类，归战斗外使用）加上 7020 这件战斗道具。
		rows = rows.filter(func(item: Dictionary) -> bool:
			var consumable := int(item.type) == ItemKind.Kind.CONSUMABLE and \
				not int(item.index) in range(19, 31)
			return consumable or int(item.id) == ItemKind.id_of(ItemKind.Kind.GROUP_7, 20))
	selected = clampi(int(previous.get("selected", 0)), 0, maxi(0, slot_count() - 1))
	scroll_start = 0
	_accepted = false
	show()
	_render()
	$Window.open_window()
	return true


func slot_count() -> int:
	return maxi(18, ceili(float(rows.size()) / 6.0) * 6)


func handle_key(key: String) -> void:
	if $Window.is_transitioning():
		return
	if key in ["Escape", "Backspace"]:
		_accepted = false
		$Window.close_window()
	elif key in ["Enter", "Space"]:
		_confirm()
	elif key in ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]:
		select(posmod(selected + {"ArrowLeft": -1, "ArrowRight": 1, "ArrowUp": -6, "ArrowDown": 6}[key], slot_count()))


func select(index: int, activate: bool = false) -> void:
	if $Window.is_transitioning():
		return
	if activate and index == selected:
		_confirm()
	else:
		selected = index
		_render()


func _confirm() -> void:
	if selected >= rows.size():
		return
	_accepted = true
	$Window.close_window()


func _transition_finished(opened: bool) -> void:
	if opened or not visible:
		return
	hide()
	if _accepted:
		_accepted = false
		chosen.emit(rows[selected].duplicate(true))
	else:
		cancelled.emit()


func _render() -> void:
	var capacity := slot_count()
	var row := selected / 6
	if selected < scroll_start:
		scroll_start = row * 6
	elif selected >= scroll_start + 18:
		scroll_start = (row - 2) * 6
	$Window/Bounds/Title.text = _presentation.message(
		Msg.Id.CAPTURE_WINDOW_TITLE if mode == "capture" else Msg.Id.ITEM_WINDOW_TITLE)
	$Window/Content/Category.texture = categories[int(mode == "capture")]
	$Window/Content/Notice.text = "当前进度未记录背包" if not _progress.has("inventory") else \
		"没有可用道具" if rows.is_empty() else ""
	%Count.present("%d/%d" % [rows.size(), capacity])
	var balance: Variant = _progress.get("parameter", {}).get("moneyBalance")
	%Money.get_node("Number").visible = balance != null
	%Money.get_node("Unknown").visible = balance == null
	if balance == null:
		%Money.get_node("Unknown").present("--")
	else:
		%Money.get_node("Number").present(_format_money(int(balance)))
	for slot in 18:
		var index := scroll_start + slot
		var cell := %Grid.get_child(slot) as ItemCell
		var focused := index == selected
		cell.present_frame(frames[int(focused)], focused)
		var item: Dictionary = rows[index] if index < rows.size() else {}
		cell.get_node("Icon").texture = _presentation.item_texture(item)
		cell.set_grade(_presentation.item_color(item))
		cell.get_node("Quantity").hide()
		cell.get_node("QuantityNumber").visible = int(item.get("quantity", 0)) > 1
		cell.get_node("QuantityNumber").present(str(item.get("quantity", 0)))
	var item: Dictionary = rows[selected] if selected < rows.size() else {}
	%DetailFrame.present_item(item, 4 if mode == "capture" else 0,
		_presentation.item_name(item), _presentation.item_explanation(item),
		_presentation.item_color(item), _presentation.message)
	var track: Control = %Scrollbar.get_node("Track")
	var thumb: Control = %Scrollbar.get_node("Thumb")
	var row_count := capacity / 6
	var length := maxi(3, int(track.size.y) - 3 * (row_count - 1))
	thumb.position = track.position + Vector2(0, int(row * (track.size.y - length) / (row_count - 1)))
	thumb.size = Vector2(track.size.x, length)


func _format_money(value: int) -> String:
	var text := str(value)
	var parts := PackedStringArray()
	while text.length() > 3:
		parts.insert(0, text.right(3))
		text = text.left(text.length() - 3)
	parts.insert(0, text)
	return ".".join(parts)


func playback_state() -> Dictionary:
	return {"selected": selected, "scroll_start": scroll_start}
