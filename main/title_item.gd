extends Node2D
## 标题菜单单项（图 + 文字）。

var _motion := Vector2.ZERO


func present(item: Dictionary, text: String, texture: Texture2D) -> void:
	# Native opening spread and selection bounce are offsets from the authored layout.
	var next_motion := Vector2(float(item.x) - 200, float(item.y) - (52 + 28 * int(item.index)))
	position += next_motion - _motion
	_motion = next_motion
	modulate.a = float(item.opacity)
	$Image.texture = texture
	$Image.show()
	$Label.text = text
	$Label.show()
	$Label.add_theme_color_override("font_color", Color.WHITE if int(item.image) == 0 else Color("#7b7b7b"))
	show()


func hit_rect() -> Rect2:
	var area: Control = $HitArea
	return Rect2(to_global(area.position), area.size)
