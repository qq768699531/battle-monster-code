extends Control

const SlotFrame = preload("res://scripts/data/slot_frame.gd")

var host: Control
var _offers: Array[Dictionary]
var _first_index := 0


func _ready() -> void:
	hide()
	host = get_parent()
	_offers = host.Menu.native_network_offers()
	for slot in range($Grid.get_child_count()):
		$Grid.get_child(slot).pressed.connect(_select_offer.bind(slot))
	$Scroll/UpHit.pressed.connect(_move.bind(-6))
	$Scroll/DownHit.pressed.connect(_move.bind(6))


func handle_key(key: String) -> bool:
	if not host.network_navigation_open:
		if key in ["ArrowDown", "Enter", "Space"]:
			host.network_navigation_open = true
			host.notice = ""
			host._render_content()
			return true
		return key == "ArrowUp"
	if key in ["Escape", "Backspace"]:
		host.network_navigation_open = false
		host.notice = ""
		host._render_content()
	elif key in ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]:
		_move({"ArrowUp": -6, "ArrowDown": 6, "ArrowLeft": -1, "ArrowRight": 1}[key])
	elif key in ["Enter", "Space"]:
		_confirm()
	return true


func _move(step: int) -> void:
	host.network_navigation_open = true
	host.selected_network_index = posmod(host.selected_network_index + step, _capacity())
	host.notice = ""
	host._render_content()


func _select_offer(slot: int) -> void:
	var index := _first_index + slot
	var selected: bool = host.network_navigation_open and host.selected_network_index == index
	host.network_navigation_open = true
	host.selected_network_index = index
	host.notice = ""
	if selected:
		_confirm()
	else:
		host._render_content()


func _confirm() -> void:
	if host.selected_network_index < _offers.size():
		host.notice = "NET购买尚未接通；未扣费或添加道具。"
	host._render_content()


func _capacity() -> int:
	return ceili(_offers.size() / 6.0) * 6


func _render_network() -> void:
	var selected_row := floori(host.selected_network_index / 6.0)
	var first_row := floori(host.network_scroll_start / 6.0)
	if selected_row < first_row:
		first_row = selected_row
	elif selected_row >= first_row + 3:
		first_row = selected_row - 2
	_first_index = first_row * 6
	host.network_scroll_start = _first_index
	for slot in range($Grid.get_child_count()):
		var cell := $Grid.get_child(slot) as ItemCell
		var index := _first_index + slot
		var focused: bool = host.network_navigation_open and index == host.selected_network_index
		# 同物品栏：面板内的格子都在条目范围内，空格也用普通帧。
		cell.present_frame(SlotFrame.frame_of(host._party_frames, true, focused), focused)
		cell.set_grade(null)
		cell.get_node("Quantity").hide()
		cell.get_node("QuantityNumber").hide()
		cell.get_node("Icon").texture = null
		if index < _offers.size():
			var offer := _offers[index]
			var icon_id: int = host._item_icon_id(int(offer["id"]))
			if icon_id >= 0:
				cell.get_node("Icon").texture = host._assets.item_icon(icon_id)
			var quantity: Control = cell.get_node("QuantityNumber")
			quantity.visible = offer.quantity > 1
			quantity.present(str(offer.quantity))
	$Count.present("%d/%d" % [_offers.size(), _offers.size()])
	var offer: Dictionary = _offers[host.selected_network_index] \
		if host.selected_network_index < _offers.size() else {}
	$Price/Number.present(str(offer.cash_price if not offer.is_empty() else 0))
	$Description.present(host, offer if host.network_navigation_open else {}, 5)
	var track: Control = $Scroll/Track
	var thumb: Control = $Scroll/Thumb
	var row_count := _capacity() / 6
	var length := maxi(3, int(track.size.y) - 3 * (row_count - 1))
	thumb.position.y = track.position.y + selected_row * (track.size.y - length) / (row_count - 1)
	thumb.size.y = length
