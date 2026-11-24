@tool
extends Control
## 原生圆角面板：多层描边由 border_colors 表达，内层填充 background_color。

@export var border_color := Color("#196485"):
	set(value):
		border_color = value
		queue_redraw()
# 非空时逐层替代 border_color，层数即数组长度（如对话框的黑·黑·灰三层描边）。
@export var border_colors: PackedColorArray = []:
	set(value):
		border_colors = value
		queue_redraw()
@export var background_color := Color("#0E1B2F"):
	set(value):
		background_color = value
		queue_redraw()
@export_range(0, 8, 1) var border_width := 1:
	set(value):
		border_width = value
		queue_redraw()


func _draw() -> void:
	var rect := Rect2i(Vector2i.ZERO, Vector2i(size))
	var rings := border_colors.size() if not border_colors.is_empty() else border_width
	for inset in range(rings):
		_round_rectangle(Rect2i(Vector2i(inset, inset),
			rect.size - Vector2i(2 * inset, 2 * inset)),
			border_colors[inset] if not border_colors.is_empty() else border_color, false)
	var margin := Vector2i(rings, rings)
	_round_rectangle(Rect2i(margin, rect.size - 2 * margin), background_color, true)


func _round_rectangle(rect: Rect2i, color: Color, filled: bool) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	if rect.size.x < 3 or rect.size.y < 3:
		draw_rect(rect, color, filled)
		return
	draw_rect(Rect2i(rect.position + Vector2i(1, 0), Vector2i(rect.size.x - 2, 1)), color)
	draw_rect(Rect2i(rect.position.x + 1, rect.end.y - 1, rect.size.x - 2, 1), color)
	if filled:
		draw_rect(Rect2i(rect.position + Vector2i(0, 1), Vector2i(rect.size.x, rect.size.y - 2)), color)
	else:
		draw_rect(Rect2i(rect.position + Vector2i(0, 1), Vector2i(1, rect.size.y - 2)), color)
		draw_rect(Rect2i(rect.end.x - 1, rect.position.y + 1, 1, rect.size.y - 2), color)
		for y in [1, rect.size.y - 2]:
			for x in [1, rect.size.x - 2]:
				draw_rect(Rect2i(rect.position + Vector2i(x, y), Vector2i.ONE), color)
