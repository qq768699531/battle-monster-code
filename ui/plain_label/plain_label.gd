@tool
extends Control
## 单行文字（不逐字形排版的简化版）。

const Layout = preload("res://prime/layout/layout.gd")
@export var text := "":
	set(value):
		text = value
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()
@export var anchor := 0:
	set(value):
		anchor = value
		queue_redraw()
@export var outlined := false:
	set(value):
		outlined = value
		queue_redraw()


func _draw() -> void:
	var font: Font = Layout.UI_FONT
	var at := Layout.text_position(font, text, Vector2.ZERO, anchor)
	if outlined:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Layout.FONT_SIZE, 1, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Layout.FONT_SIZE, color)
