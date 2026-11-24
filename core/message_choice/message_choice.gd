extends Control
## 消息确认按钮（44×16，水平居中于分隔线下方）。


func present(text: String, selected: bool) -> void:
	$Highlight.visible = selected
	$Caption.text = text
	$Caption.color = Color.BLACK if selected else Color("#808080")
