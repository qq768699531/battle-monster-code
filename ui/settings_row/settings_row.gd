extends Node2D
## 设置页单行。
@onready var panel: Control = $Panel
@onready var content = $Content
func present(index: int, values: Dictionary, selected: int, text: Dictionary, arrows: Array[Texture2D], inactive: Array[Texture2D]) -> void:
	var active := index == selected
	panel.border_color = Color("#7AD0FA") if active else Color("#195573")
	var narrow := index in [0, 2, 3]
	$NarrowTrack.visible = narrow
	$WideTrack.visible = not narrow
	content.present(index, values, active, text, arrows, inactive)
