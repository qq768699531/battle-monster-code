extends Control
## 道具页的丢弃窗口（原生 `Field_Item_DrawSelect`：先选数量，再确认）。

const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")

var host: Control
var _was_open := false


func _ready() -> void:
	host = get_parent()
	visible = false
	$Window.transition_finished.connect(_transition_finished)
	$Window.chosen.connect(_on_confirm_choice)


func render() -> void:
	var opening: bool = host.item_discard_open
	visible = opening
	if opening and not _was_open:
		# `$Window` 场景里是 `visible = false`，开窗时显式 show 并播开窗；关闭由 confirm／CLR 走
		# `close_window`，下一次打开再从相位 1 重播。
		$Window.show()
		$Window.open_window()
	_was_open = opening
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
	$Window.present_select(host._menu_text(82), host.selected_item_discard)


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


## 触控：光标先移过去，光标已在的那颗才算确认（`chosen` 只在确认时发）。
func _on_confirm_choice(accepted: bool) -> void:
	if not host.item_discard_open or $Window.is_transitioning():
		return
	host.selected_item_discard = 0 if accepted else 1
	confirm()


func _transition_finished(opened: bool) -> void:
	if opened or not host.item_discard_open:
		return
	host.item_discard_open = false
	host.item_discard_item = {}
	host.item_discard_count = 1
	host.item_discard_step = 0
	host.selected_item_discard = 1
	host._render_content()
