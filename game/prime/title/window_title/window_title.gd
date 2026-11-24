extends Control
## 原生标题文字（带标题配色 shader）。

const Layout = preload("res://game/prime/ui/layout/layout.gd")
var text := "":
	set(value):
		text = value
		queue_redraw()


func _draw() -> void:
	draw_string(Layout.UI_FONT, Layout.text_position(Layout.UI_FONT, text, Vector2.ZERO, 17),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, Layout.FONT_SIZE, Color.WHITE)
