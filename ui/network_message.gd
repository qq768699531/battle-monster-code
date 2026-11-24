extends Node2D
## 网络页的提示消息框。

const UI = preload("res://prime/layout.gd")
@export var center := Vector2.ZERO
@export var waiting_padding := 0
@export var complete_padding := 0


func measure(lines: Array, waiting: bool) -> Dictionary:
	var width := int($Content.size.x)
	var height: int = $Content/Lines.line_step() * lines.size() + (waiting_padding if waiting else complete_padding)
	return {"rect": Rect2i(Vector2i(center - Vector2(width, height) / 2), Vector2i(width, height)), "lines": lines}


func text_width() -> int:
	return UI.content_text_width($Content.size.x, $Content/Lines)


func okay_rect(layout: Dictionary) -> Rect2i:
	return UI.control_rect($Content/Okay, layout.rect)


func present(paint: Dictionary, layout: Dictionary, ok_text: String) -> void:
	var state: int = paint.window_state
	var waiting: bool = paint.get("network_request_pending", false)
	modulate.a = UI.phase_alpha(state)
	var animated := UI.window_rect(layout.rect, state, int($Content.get_meta("title_height")))
	$Panel.position = animated.position
	$Panel.size = animated.size
	$Content.position = layout.rect.position
	$Content.size = layout.rect.size
	$Content.visible = state in UI.BODY_PHASES
	var rich: Array = layout.lines
	var lines: Array = []
	for line: Dictionary in rich:
		lines.append(line.text)
	$Content/Lines.present(lines, rich)
	$Content/Divider.visible = not waiting
	$Content/Okay.visible = not waiting
	$Content/Okay.present(ok_text, true)
