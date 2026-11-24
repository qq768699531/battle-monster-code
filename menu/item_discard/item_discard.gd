extends Control
## 道具页的丢弃窗口（原生 `Field_Item_DrawSelect`：先选数量，再确认）。

const SlotFrame = preload("res://menu/slot_frame/slot_frame.gd")

var host: Control


func _ready() -> void:
	host = get_parent()
	visible = false
	$Window.transition_finished.connect(_transition_finished)
	$Window/Content/Yes.pressed.connect(_choose.bind(0))
	$Window/Content/No.pressed.connect(_choose.bind(1))


func render() -> void:
	visible = host.item_discard_open
	if not visible:
		return
	var item: Dictionary = host.item_discard_item
	var cell := $Window/Content/Item
	# 丢弃框里的这一格一定有道具，所以只可能是帧 0（`Menu_winDrawIcon16` 的有内容·常态）。
	cell.set_frame_texture(SlotFrame.frame_of(host._party_frames, true, false) \
		if not host._party_frames.is_empty() else null)
	var icon_id: int = host._item_icon_id(int(item.get("id", -1)))
	cell.get_node("Icon").texture = host._assets.item_icon(icon_id)
	cell.set_grade(host._native_grade_color(int(item.get("grade_index", -1)), false))
	var quantity: Control = cell.get_node("QuantityNumber")
	cell.get_node("Quantity").hide()
	quantity.visible = int(item.get("quantity", 1)) > 1
	if quantity.visible:
		quantity.present(str(item.quantity))
	$Window.tooltip_text = "%s\n丢弃数量：%d" % [host._native_item_name(item), host.item_discard_count]
	# 选数量时数字嵌在原生的橙色底上；进入确认后改成黑底白字。
	var choosing: bool = host.item_discard_step == 0
	$Window/Content/QuantityBackground.color = Color("#ff9600") if choosing else Color.BLACK
	$Window/Content/Quantity.modulate = Color.BLACK if choosing else Color.WHITE
	$Window/Content/Quantity.present(str(host.item_discard_count))
	$Window/Content/Prompt.text = host._menu_text(82)
	$Window/Content/Yes/Choice.present(host._menu_text(85), host.selected_item_discard == 0)
	$Window/Content/No/Choice.present(host._menu_text(86), host.selected_item_discard == 1)


func handle_key(key: String) -> bool:
	if $Window.is_transitioning():
		return true
	if host.item_discard_step == 0:
		if key == "ArrowLeft":
			_adjust(-1)
		elif key == "ArrowRight":
			_adjust(1)
		elif key in ["Enter", "Space"]:
			host.item_discard_step = 1
			host.notice = ""
			render()
		elif key in ["Escape", "Backspace"]:
			$Window.close_window()
	else:
		if key in ["ArrowLeft", "ArrowRight"]:
			host.selected_item_discard = 1 - host.selected_item_discard
			render()
		elif key in ["Enter", "Space"]:
			confirm()
		elif key in ["Escape", "Backspace"]:
			host.item_discard_step = 0
			host.notice = ""
			render()
	return true


func confirm() -> void:
	if not host.item_discard_open or $Window.is_transitioning():
		return
	if host.selected_item_discard != 0:
		$Window.close_window()
		return
	host.discard_selected_item()
	$Window.close_window()


func _adjust(direction: int) -> void:
	var total: int = maxi(1, int(host.item_discard_item.get("quantity", 1)))
	host.item_discard_count += direction
	if host.item_discard_count > total:
		host.item_discard_count = 1
	elif host.item_discard_count < 1:
		host.item_discard_count = total
	render()


func _choose(index: int) -> void:
	if not host.item_discard_open or $Window.is_transitioning():
		return
	if host.selected_item_discard == index:
		confirm()
	else:
		host.selected_item_discard = index
		render()


func _transition_finished(opened: bool) -> void:
	if opened or not host.item_discard_open:
		return
	host.item_discard_open = false
	host.item_discard_item = {}
	host.item_discard_count = 1
	host.item_discard_step = 0
	host.selected_item_discard = 1
	host._render_content()
