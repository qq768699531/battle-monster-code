extends "res://engine/ui/item_select/item_select.gd"
## 道具页的丢弃数量框：数量步进／是/否／开合都继承 `engine/ui/item_select/item_select.gd`，
## 这里只把宿主（`MenuView`）的 `item_discard_*` 状态接上，并在确认时执行丢弃。

const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")

var host: Control
var _was_open := false


func _ready() -> void:
	host = get_parent()
	super._ready()
	visible = false


func render() -> void:
	var opening: bool = host.item_discard_open
	if opening and not _was_open:
		var item: Dictionary = host.item_discard_item
		var frames: Array[Texture2D] = host._party_frames
		var frame: Texture2D = SlotFrame.frame_of(frames, true, false) if not frames.is_empty() else null
		var grade: Variant = host._native_grade_color(int(item.get("grade_index", -1)), false)
		var icon: Texture2D = host._assets.item_icon(host._item_icon_id(int(item.get("id", -1))))
		# 原生 `Field_Item_DrawSelect` 的 `n2 = 0`（丢弃）：正文 82、是/否 85/86，没有价格行。
		present_item(host._menu_text(82), host._menu_text(85), host._menu_text(86), icon,
			maxi(1, int(item.get("quantity", 1))), host.item_discard_count,
			host.item_discard_step, ConfirmLayout.ItemSelect.DISCARD, 0, frame, grade)
	elif opening:
		# 宿主已经用 item_discard_step/count 记录状态；以宿主为准同步（例如堆叠 1 直接进确认）。
		var next_step: int = clampi(host.item_discard_step, 0, 1)
		var next_quantity: int = clampi(host.item_discard_count, 1, maximum)
		if step != next_step or quantity != next_quantity:
			step = next_step
			quantity = next_quantity
			_render()
	_was_open = opening
	visible = opening


func _accept(count: int) -> void:
	host.item_discard_count = count
	host.selected_item_discard = selected
	if selected == 0:
		host.discard_selected_item()
	else:
		host.item_discard_open = false
		host.item_discard_step = 0
		host._render_content()


func _cancel() -> void:
	host.item_discard_open = false
	host.item_discard_step = 0
	host.selected_item_discard = 1
	host._render_content()


func _quantity_changed() -> void:
	host.item_discard_count = quantity


func _step_changed() -> void:
	host.item_discard_step = step
	host.selected_item_discard = selected
