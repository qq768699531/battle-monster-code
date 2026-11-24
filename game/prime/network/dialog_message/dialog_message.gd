extends Node2D
## 通用消息框：标题、分页正文与确认按钮，尺寸随内容变化。

const UI = preload("res://game/prime/ui/layout/layout.gd")
@export var center := Vector2.ZERO
@export var vertical_padding := 0


func text_width(width: int) -> int:
	return UI.content_text_width(width, $Content/Lines)


func measure(lines: Array, width: int) -> Dictionary:
	var height: int = $Content/Lines.line_step() * lines.size() + vertical_padding
	var rect := Rect2i(Vector2i(center - Vector2(width, height) / 2), Vector2i(width, height))
	return {"rect": rect, "lines": lines, "divider": rect.end.y + int($Content/Divider.offset_top)}


func button_rects(layout: Dictionary, single: bool) -> Array[Rect2i]:
	var actions := UI.control_rect($Content/Actions, layout.rect)
	var result: Array[Rect2i] = []
	var buttons := [$Content/Actions/Single/Confirm] if single else [
		$Content/Actions/Pair/Left, $Content/Actions/Pair/Right]
	for button: Control in buttons:
		result.append(UI.control_rect(button, actions))
	return result


func present(layout: Dictionary, state: int, labels: Array, selected: int) -> void:
	var rect: Rect2i = layout.rect
	$Content.position = rect.position
	$Content.size = rect.size
	var animated := UI.window_rect(rect, state, int($Content.get_meta("title_height")))
	$Panel.position = animated.position
	$Panel.size = animated.size
	modulate.a = UI.phase_alpha(state)
	$Content.visible = state in [-1, 2, 3, 4]
	$Content/Lines.present(layout.lines)
	var single := labels.size() == 1
	$Content/Actions/Single.visible = single
	$Content/Actions/Pair.visible = not single
	if single:
		$Content/Actions/Single/Confirm.present(labels[0], selected == 0)
	else:
		$Content/Actions/Pair/Left.present(labels[0], selected == 0)
		$Content/Actions/Pair/Right.present(labels[1], selected == 1)
