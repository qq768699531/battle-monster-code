extends Node2D
## 标题菜单单项（图 + 文字）。

const TITLE_SHINE = preload("res://game/prime/title/title_item/title_shine.gdshader")

var _motion := Vector2.ZERO
var _shine_material: ShaderMaterial


func _ready() -> void:
	# 每个按钮一份材质实例：闪光相位是逐按钮的，共用材质会一起闪。
	_shine_material = ShaderMaterial.new()
	_shine_material.shader = TITLE_SHINE
	_shine_material.set_shader_parameter("progress", -1.0)
	$Image.material = _shine_material


func present(item: Dictionary, text: String, texture: Texture2D) -> void:
	# Native opening spread and selection bounce are offsets from the authored layout.
	var next_motion := Vector2(float(item.x) - 200, float(item.y) - (52 + 28 * int(item.index)))
	position += next_motion - _motion
	_motion = next_motion
	modulate.a = float(item.opacity)
	$Image.texture = texture
	if _shine_material != null:
		# 原版 0..3 帧：白块右边界逐帧推进，第 4 帧起关闭。
		var phase := int(item.get("flash_phase", -1))
		var steps: Array[float] = [0.25, 0.5, 0.82, 1.0]
		_shine_material.set_shader_parameter("progress", steps[phase] if phase >= 0 and phase < 4 else -1.0)
	$Image.show()
	$Label.text = text
	$Label.show()
	$Label.add_theme_color_override("font_color", Color.WHITE if int(item.image) == 0 else Color("#7b7b7b"))
	show()


func hit_rect() -> Rect2:
	var area: Control = $HitArea
	return Rect2(to_global(area.position), area.size)
