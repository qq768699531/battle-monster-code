extends VBoxContainer
## 分页正文的行列表。


func present(lines: Array, rich: Array = [], color: Color = Color.WHITE) -> void:
	while get_child_count() - 1 < lines.size():
		var row := $Prototype.duplicate()
		row.name = "Line%d" % (get_child_count() - 1)
		add_child(row)
	for index in range(1, get_child_count()):
		var row := get_child(index)
		row.visible = index - 1 < lines.size()
		if row.visible:
			row.present(str(lines[index - 1]), rich[index - 1] if index - 1 < rich.size() else {}, color)
	notification(Container.NOTIFICATION_SORT_CHILDREN)


func line_step() -> int:
	return int($Prototype.custom_minimum_size.y) + get_theme_constant("separation")
