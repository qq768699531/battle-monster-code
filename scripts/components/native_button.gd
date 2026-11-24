@tool
extends Button
## 原生按钮组合件（底框 + 文本）。

@export var caption := "":
	set(value):
		caption = value
		_refresh()
@export var selected := false:
	set(value):
		selected = value
		_refresh()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	var label := get_node_or_null("Caption")
	if label != null:
		label.text = caption
		label.color = Color.WHITE if selected else Color("#196485")
	var panel := get_node_or_null("Background")
	if panel != null:
		panel.border_color = Color("#7AD0FA") if selected else Color("#196485")
