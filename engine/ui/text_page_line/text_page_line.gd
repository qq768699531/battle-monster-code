extends VBoxContainer
## 分页正文的单行。


func present(text: String, rich: Dictionary, color: Color = Color.WHITE,
		indented: bool = false, gap: bool = false) -> void:
	$Gap.visible = gap
	$Line/Normal.visible = not indented
	$Line/Indented.visible = indented
	var group := $Line/Indented if indented else $Line/Normal
	group.get_node("Plain").visible = rich.is_empty()
	group.get_node("Rich").visible = not rich.is_empty()
	if rich.is_empty():
		group.get_node("Plain").text = text
		group.get_node("Plain").color = color
	else:
		group.get_node("Rich").set_line(rich)
	notification(Container.NOTIFICATION_SORT_CHILDREN)
