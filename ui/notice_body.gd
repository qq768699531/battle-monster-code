extends Node2D
## 提示正文区。
@onready var _heading_origin: Vector2 = $Heading.position
@onready var _separator_rect := Rect2i($Separator.position, $Separator.size)


func present(paint: Dictionary, rect: Rect2i) -> void:
	$Heading.text = paint.notice.heading
	var base: Rect2i = get_parent()._frame_rect
	$Heading.position = _heading_origin + Vector2(rect.position - base.position)
	$Separator.position = _separator_rect.position + Vector2i(rect.position - base.position)
	$Separator.size.x = _separator_rect.size.x + rect.size.x - base.size.x
	$Lines.present(paint.notice.lines, paint.notice.get("rich_lines", []))
