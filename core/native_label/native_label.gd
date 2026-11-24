@tool
extends Control
## 原生点阵文字：按原文字单元逐字形绘制，支持对齐与描边。

const UI_THEME = preload("res://core/native_label/ui_theme.tres")
const TextLayout = preload("res://core/native_text_layout/native_text_layout.gd")
const TEXT_CELL_HEIGHT := 10

@export var text := "":
	set(value):
		text = value
		_line = {}
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		_line = {}
		queue_redraw()
@export var outline := Color.TRANSPARENT:
	set(value):
		outline = value
		queue_redraw()
@export_enum("Left", "Center", "Right") var horizontal_alignment := 0:
	set(value):
		horizontal_alignment = value
		queue_redraw()
@export_enum("Top", "Center", "Bottom") var vertical_alignment := 0:
	set(value):
		vertical_alignment = value
		queue_redraw()

var _line: Dictionary = {}


func set_line(line: Dictionary) -> void:
	_line = line
	queue_redraw()


func _draw() -> void:
	var font: Font = UI_THEME.default_font
	var font_size: int = UI_THEME.default_font_size
	var line := _line
	if line.is_empty():
		var layout := TextLayout.layout(text, font, font_size, 0, false, color)
		if not layout.error.is_empty():
			push_error(layout.error)
			return
		line = layout.lines[0]
	var at := Vector2.ZERO
	if horizontal_alignment == 1:
		at.x = floorf((size.x - line.width) / 2.0)
	elif horizontal_alignment == 2:
		at.x = size.x - line.width
	if vertical_alignment == 1:
		at.y = (size.y - TEXT_CELL_HEIGHT) / 2.0
	elif vertical_alignment == 2:
		at.y = size.y - TEXT_CELL_HEIGHT
	var text_line := TextLine.new()
	text_line.add_string(line.text, font, font_size)
	at.y += ceilf((TEXT_CELL_HEIGHT - text_line.get_size().y) / 2.0) + text_line.get_line_ascent()
	for glyph: Dictionary in line.glyphs:
		if glyph.character == " ":
			continue
		var glyph_width := font.get_char_size(glyph.character.unicode_at(0), font_size).x
		var scale_x: float = minf(1.0, glyph.advance / maxf(1.0, glyph_width))
		var inset: float = ceilf((glyph.advance - glyph_width * scale_x) / 2.0)
		draw_set_transform(at + Vector2(glyph.x + inset, 0), 0, Vector2(scale_x, 1))
		if outline.a > 0.0:
			draw_char_outline(font, Vector2.ZERO, glyph.character, font_size, 2, outline)
		draw_char(font, Vector2.ZERO, glyph.character, font_size, glyph.color)
	draw_set_transform(Vector2.ZERO)
