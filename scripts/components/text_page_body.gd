extends Node2D
## 分页正文区：行内容与滚动绑定。


func present(paint: Dictionary) -> void:
	var page: Dictionary = paint.page
	$Heading.present(page.title, page.get("title_line", {}), Color("#FFB655"))
	var classification: bool = paint.scene == 14 and paint.page_index == 2
	$Classification.visible = classification
	$Lines.visible = not classification
	if classification:
		var rows := $Classification/Labels.get_children()
		for index in range(rows.size()):
			rows[index].visible = index < page.lines.size()
			if rows[index].visible:
				_present_line(rows[index], page, index)
		return
	var copyright_page: bool = paint.scene == 14 and paint.page_index == 1
	var rows := $Lines.get_children()
	for line in range(rows.size()):
		var index: int = paint.page_scroll + line
		rows[line].visible = index < page.lines.size()
		if rows[line].visible:
			_present_line(rows[line], page, index,
				copyright_page and index in [2, 3, 4, 5, 8, 9],
				copyright_page and index in [1, 6, 7])
	$Lines.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _present_line(row: Node, page: Dictionary, index: int,
		indented: bool = false, gap: bool = false) -> void:
	var rich: Array = page.get("rich_lines", [])
	row.present(page.lines[index], rich[index] if index < rich.size() else {},
		Color.WHITE, indented, gap)
