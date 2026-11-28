extends Control

var host: Control
var _first_index := 0


func _ready() -> void:
	host = get_parent()
	$Window.transition_finished.connect(func(opened: bool):
		if not opened:
			host.party_equip_open = false
			host._render_content())
	for slot in range(18):
		var button: Button = %Grid.get_child(slot)
		button.pressed.connect(func():
			host._select_party_equipment(_first_index + slot))


func slot_count() -> int:
	var rows: Array = host.Menu.native_inventory_rows(host.story_progress,
		host.gameplay_catalog, 1)
	return maxi(18, ceili(float(rows.size()) / 6.0) * 6)


func _move_selection(direction: int) -> void:
	host._select_party_equipment(posmod(host.selected_equipment_index + direction,
		slot_count()))


func handle_key(key: String) -> bool:
	if $Window.is_transitioning():
		return true
	if key in ["Escape", "Backspace"]:
		host.notice = ""
		$Window.close_window()
	elif key in ["Enter", "Space"]:
		host.equip_selected_party_member()
	elif key in ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]:
		var direction: int = {"ArrowLeft": -1, "ArrowRight": 1,
			"ArrowUp": -6, "ArrowDown": 6}[key]
		_move_selection(direction)
	return true


func _render_party_equipment() -> void:
	var rows: Array = host.Menu.native_inventory_rows(host.story_progress,
		host.gameplay_catalog, 1)
	var capacity := slot_count()
	host.selected_equipment_index = clampi(host.selected_equipment_index, 0, capacity - 1)
	var selected_row: int = host.selected_equipment_index / 6
	var first_row := clampi(int(host.equipment_scroll_start / 6), 0, capacity / 6 - 3)
	if selected_row < first_row:
		first_row = selected_row
	elif selected_row >= first_row + 3:
		first_row = selected_row - 2
	_first_index = first_row * 6
	host.equipment_scroll_start = _first_index
	$Window/Bounds/Title.text = host._menu_text(76)
	%Count.present("%d/%d" % [rows.size(), capacity])
	var balance: Variant = host.story_progress.get("parameter", {}).get("moneyBalance")
	%Money.get_node("Number").visible = balance != null
	%Money.get_node("Unknown").visible = balance == null
	%Money.tooltip_text = "当前进度未记录金币余额" if balance == null else ""
	if balance == null:
		%Money.get_node("Unknown").present("--")
	else:
		%Money.present(host._pages.items._format_money(balance))
	for slot in range(18):
		var index := _first_index + slot
		var cell := %Grid.get_child(slot) as ItemCell
		var selected: bool = index == host.selected_equipment_index
		var frame: Texture2D = host._party_frames[1 if selected else 0]
		var icon: Texture2D = null
		var grade: Variant = null
		var quantity := 0
		if index < rows.size():
			var item: Dictionary = rows[index]
			var icon_id: int = host._item_icon_id(int(item["id"]))
			if icon_id >= 0:
				icon = host._assets.item_icon(icon_id)
			var grade_index: Variant = item.get("grade_index")
			if grade_index is int:
				grade = host._native_grade_color(grade_index, false)
			quantity = int(item.quantity)
		cell.present_cell(icon, frame, selected, grade, quantity)
	%DetailFrame.present(host, rows[host.selected_equipment_index]
		if host.selected_equipment_index < rows.size() else {}, 1)
	host._pages.items._update_scrollbar(%Scrollbar, selected_row, capacity / 6)
