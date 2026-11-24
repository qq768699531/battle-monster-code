extends Panel
## 物品说明框：名称、正文、图标与箭头。

const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")

@onready var _title_color: Color = $HeaderClip/SelectedItem.color


func present(host: Control, selected: Dictionary, category: int) -> void:
	present_item(selected, category, host._native_item_name(selected),
		host._native_item_explanation(selected),
		host._native_grade_color(int(selected.get("grade_index", -1)), false), host._menu_text)


func present_item(selected: Dictionary, category: int, item_name: String, explanation: String,
		grade_color: Variant, message: Callable) -> void:
	$HeaderClip.visible = not selected.is_empty()
	$ExplanationArrow.visible = not selected.is_empty() and category != 1
	$Lines.hide()
	$EquipmentStats.hide()
	tooltip_text = ""
	for line: Control in $Lines.get_children():
		line.text = ""
	if selected.is_empty():
		return
	var title: Control = $HeaderClip/SelectedItem
	title.color = _title_color
	title.text = "[ %s ]" % item_name if category == 1 else \
		"[ %s X %d ]" % [item_name, selected.quantity]
	if category == 1:
		var grade: Variant = selected.get("grade_index")
		if grade is int:
			var color: Variant = grade_color
			if color is Color:
				title.color = color
		$EquipmentStats.show()
		var slots: Array = selected.get("detail_slots", [])
		tooltip_text = "装备属性未记录" if slots.is_empty() else ""
		if slots.is_empty():
			_present_lines("--")
		for index in range(14):
			var metric: Control = $EquipmentStats.get_child(index)
			metric.visible = index < slots.size() and slots[index] != 0
			if metric.visible:
				metric.get_node("Number").present("%d%%" % slots[index])
	else:
		var descriptions := PackedStringArray()
		var slots: Array = selected.get("detail_slots", [])
		for index in [6, 8, 7, 9]:
			if index < slots.size() and slots[index] != 0:
				var message_id: int = {6: 179, 8: 180, 7: 181, 9: 182}[index]
				descriptions.append(str(message.call(message_id)).replace("%d",
					str(slots[index])).replace("%%", "%"))
		if not explanation.is_empty():
			descriptions.append(explanation)
		_present_lines("\n".join(descriptions))


func _present_lines(text: String) -> void:
	$Lines.show()
	var label: Control = $Lines/Line0
	var layout := TextLayout.layout(text, label.theme.default_font, label.theme.default_font_size,
		$Lines.size.x)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	for index in range(3):
		var line: Control = $Lines.get_child(index)
		line.visible = index < layout.lines.size()
		if line.visible:
			line.text = layout.lines[index].text
			line.set_line(layout.lines[index])
