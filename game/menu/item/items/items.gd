extends Control

const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")

var host: Control
var _first_index := 0


func _ready() -> void:
	host = get_parent()
	for category in range(ItemKind.BAG_COUNT):
		var button: Button = $Categories.get_child(category)
		button.pressed.connect(func(): host.select_bag_category(category))
	for slot in range(12):
		var button: Button = $Grid.get_child(slot)
		button.pressed.connect(func(): host._select_inventory_item(_first_index + slot))


func _scroll(direction: int) -> void:
	if host.item_actions_open or host.item_discard_open:
		return
	host.item_navigation_open = true
	host.item_focus = 1
	host.selected_item_index = posmod(host.selected_item_index + direction,
		host.item_capacity())
	host._render_content()


func handle_key(key: String) -> bool:
	if host.item_discard_open:
		return host._pages.item_discard.handle_key(key)
	if host.item_actions_open:
		return $ActionAnchor/Actions.handle_key(key)
	if host.item_target_open:
		return host._pages.item_target.handle_key(key)
	if not host.item_navigation_open:
		if key in ["ArrowDown", "Enter", "Space"]:
			host.item_navigation_open = true
			host.item_focus = 0
			host.notice = ""
			host._render_content()
			return true
		return key == "ArrowUp"
	if key in ["Escape", "Backspace"]:
		if host.item_focus == 1:
			host.item_focus = 0
		else:
			host.item_navigation_open = false
		host.notice = ""
		host._render_content()
		return true
	if key == "ArrowUp" and host.item_focus == 0:
		host.item_navigation_open = false
		host.notice = ""
		host._render_content()
		return true
	if key == "ArrowDown" and host.item_focus == 0:
		host.item_focus = 1
		host.notice = ""
		host._render_content()
		return true
	if key in ["Enter", "Space"]:
		if host.item_focus == 0:
			host.item_focus = 1
			host.notice = ""
			host._render_content()
		else:
			host.open_selected_item_actions()
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		var direction := -1 if key == "ArrowLeft" else 1
		if host.item_focus == 0:
			host.select_bag_category(posmod(host.selected_bag_category + direction, ItemKind.BAG_COUNT))
		else:
			host.selected_item_index = posmod(host.selected_item_index + direction,
				host.item_capacity())
			host._render_content()
		return true
	if key in ["ArrowUp", "ArrowDown"] and host.item_focus == 1:
		host.selected_item_index = posmod(host.selected_item_index +
			(-6 if key == "ArrowUp" else 6), host.item_capacity())
		host._render_content()
		return true
	return false


func _render_items() -> void:
	var rows: Array = host.Menu.native_inventory_rows(host.story_progress,
		host.gameplay_catalog, host.selected_bag_category)
	var capacity: int = host.item_capacity()
	host.selected_item_index = clampi(host.selected_item_index, 0, capacity - 1)
	var visible_rows: int = host._item_visible_rows()
	var selected_row := floori(float(host.selected_item_index) / 6.0)
	var first_row := clampi(floori(float(host.item_scroll_start) / 6.0),
		0, capacity / 6 - visible_rows)
	if selected_row < first_row:
		first_row = selected_row
	elif selected_row >= first_row + visible_rows:
		first_row = selected_row - visible_rows + 1
	_first_index = first_row * 6
	host.item_scroll_start = _first_index
	$GridFrameOne.visible = visible_rows == 1
	$GridMaskOne.visible = visible_rows == 1
	$GridFrameTwo.visible = visible_rows == 2
	$GridMaskTwo.visible = visible_rows == 2
	$CountOne.visible = visible_rows == 1
	$CountTwo.visible = visible_rows == 2
	$MoneyOne.visible = visible_rows == 1
	$MoneyTwo.visible = visible_rows == 2
	var money: Control = $MoneyOne if visible_rows == 1 else $MoneyTwo
	var balance: Variant = host.story_progress.get("parameter", {}).get("moneyBalance")
	money.get_node("Number").visible = balance != null
	money.get_node("Unknown").visible = balance == null
	money.tooltip_text = "当前进度未记录金币余额" if balance == null else ""
	if balance == null:
		money.get_node("Unknown").present("--")
	else:
		money.get_node("Number").present(_format_money(balance))
	$ScrollOne.hide()
	$ScrollTwo.hide()
	var scrollbar: Control = $ScrollOne if visible_rows == 1 else $ScrollTwo
	_update_scrollbar(scrollbar, selected_row, capacity / 6)
	var count: Control = $CountOne if visible_rows == 1 else $CountTwo
	if count.configure(host._assets):
		count.present("%d/%d" % [rows.size(), capacity])
	else:
		push_error("Native item count texture is unavailable.")
		count.hide()
	for category in range(ItemKind.BAG_COUNT):
		var button: Button = $Categories.get_child(category)
		button.disabled = host.item_actions_open or host.item_discard_open
		var icon: TextureRect = button.get_node("Icon")
		var selected: bool = host.item_navigation_open and category == host.selected_bag_category
		icon.texture = host._item_frames[category][0 if selected else 1]
		icon.material.set_shader_parameter("focused", selected and host.item_focus == 0)
	for slot in range(12):
		var cell := $Grid.get_child(slot) as ItemCell
		var item_index := _first_index + slot
		var has_item := item_index < rows.size()
		var focused: bool = host.item_navigation_open and host.item_focus == 1 \
			and item_index == host.selected_item_index
		cell.visible = slot < 6 * visible_rows
		cell.disabled = host.item_actions_open or host.item_discard_open
		# 原生 `a6` 是「格号 < 上限」（`Menu_Item_DrawList@0x55360:139-155`），容量内的空格子照样用普通帧。
		var frame: Texture2D = SlotFrame.frame_of(host._party_frames, item_index < capacity, focused)
		var icon: Texture2D = null
		var grade: Variant = null
		var quantity := 0
		if has_item:
			var entry: Dictionary = rows[item_index]
			quantity = int(entry.quantity)
			var grade_index: Variant = entry.get("grade_index")
			if grade_index is int:
				grade = host._native_grade_color(grade_index, false)
			var icon_id: int = host._item_icon_id(int(entry["id"]))
			if icon_id >= 0:
				icon = host._assets.item_icon(icon_id)
		cell.present_cell(icon, frame, focused, grade, quantity)
	_present_details(rows, visible_rows == 1)
	$ActionAnchor/Actions.present()
	if host.item_actions_open:
		var cell: Control = $Grid.get_child(host.selected_item_index - _first_index)
		var actions: Control = $ActionAnchor/Actions
		$ActionAnchor.global_position = Vector2(
			minf(cell.get_global_rect().end.x,
				get_viewport_rect().end.x - actions.position.x - actions.size.x),
			cell.global_position.y)


func _present_details(rows: Array, book: bool) -> void:
	$DetailFrame.visible = not book
	$BookDetailFrame.visible = book
	$DetailFrame.present(host, {}, host.selected_bag_category)
	$BookDetailFrame/HeaderClip.hide()
	$BookDetailFrame/Recipe0.hide()
	$BookDetailFrame/Recipe1.hide()
	$BookDetailFrame/Cost.visible = book
	$BookDetailFrame/Cost.present(0)
	$BookDetailFrame/Unknown.hide()
	if not host.item_navigation_open or host.item_focus == 0 or \
			host.selected_item_index >= rows.size() or host.item_target_open:
		return
	var selected: Dictionary = rows[host.selected_item_index]
	if book:
		$BookDetailFrame/HeaderClip.show()
		_present_book(selected)
	else:
		$DetailFrame.present(host, selected, host.selected_bag_category)


func _present_book(selected: Dictionary) -> void:
	var title: Control = $BookDetailFrame/HeaderClip/Content/SelectedItem
	title.text = "[ %s ]" % host._item_names.get(selected.get("result_name_record"), "--")
	var layout := TextLayout.layout(title.text, title.theme.default_font, title.theme.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	var content: HBoxContainer = $BookDetailFrame/HeaderClip/Content
	title.custom_minimum_size.x = minf(layout.lines[0].width, content.size.x - 20)
	content.queue_sort()
	_present_book_result.call_deferred(host._item_names.get(
		selected.get("result_description_record"), "--"))
	var slots: Array = selected.get("detail_slots", [])
	$BookDetailFrame.tooltip_text = host._native_item_mix_status(selected)
	$BookDetailFrame/Unknown.visible = slots.is_empty()
	for index in range(2):
		var row: Control = $BookDetailFrame.get_node("Recipe%d" % index)
		row.visible = index + 1 < slots.size() and slots[index + 1] != 0
		if not row.visible:
			continue
		var encoded: int = slots[index + 1]
		var material_index := encoded & 0xff
		var required := (encoded >> 8) & 0xff
		var owned: int = host.story_progress.get("inventory", {}).get(str(ItemKind.id_of(ItemKind.Kind.MATERIAL, material_index)), 0)
		row.get_node("Name").text = host._native_catalog_item_name(3, material_index)
		var icon_id: int = host._item_icon_id(ItemKind.id_of(ItemKind.Kind.MATERIAL, material_index))
		row.get_node("Icon").visible = icon_id >= 0
		if icon_id >= 0:
			row.get_node("Icon").texture = host._assets.item_icon(icon_id)
		row.get_node("Count").source_y = 0 if owned >= required else 21
		row.get_node("Count").present("%d/%d" % [owned, required])
	$BookDetailFrame/Cost.present(host.Menu.MIX_FEE)


func _present_book_result(text: String) -> void:
	var lines: VBoxContainer = $BookDetailFrame/HeaderClip/Content/Result/Lines
	var label: Control = lines.get_child(0)
	var layout := TextLayout.layout(text, label.theme.default_font, label.theme.default_font_size,
		lines.size.x)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	for index in range(lines.get_child_count()):
		var line: Control = lines.get_child(index)
		line.visible = index < layout.lines.size()
		if line.visible:
			line.text = layout.lines[index].text
			line.set_line(layout.lines[index])


func _format_money(balance: int) -> String:
	var digits := str(balance)
	var groups := PackedStringArray()
	while digits.length() > 3:
		groups.insert(0, digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.insert(0, digits)
	return ".".join(groups)


func _update_scrollbar(scrollbar: Control, page: int, page_count: int) -> void:
	scrollbar.call("set_page", page, page_count)
