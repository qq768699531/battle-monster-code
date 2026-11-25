extends Node2D
## 标题菜单单项（图 + 文字）。

const TITLE_SHINE = preload("res://game/prime/title/title_item/title_shine.gdshader")
const TITLE_GLEAM = preload("res://game/prime/title/title_item/title_gleam.webp")

var _motion := Vector2.ZERO
var _shine_material: ShaderMaterial


func _ready() -> void:
	# 每个按钮一份材质实例：闪光相位是逐按钮的，共用材质会一起闪。
	_shine_material = ShaderMaterial.new()
	_shine_material.shader = TITLE_SHINE
	_shine_material.set_shader_parameter("gleam_tex", TITLE_GLEAM)
	_shine_material.set_shader_parameter("phase", -1)
	# 闪光层压在文字之上：原生先 `JC_fntDrawChars` 再画白块/贴片，白块会盖住字。
	$Shine.material = _shine_material
	$Shine.hide()

func present(item: Dictionary, text: String, texture: Texture2D) -> void:
	# Native opening spread and selection bounce are offsets from the authored layout.
	var next_motion := Vector2(float(item.x) - 200, float(item.y) - (52 + 28 * int(item.index)))
	position += next_motion - _motion
	_motion = next_motion
	modulate.a = float(item.opacity)
	$Image.texture = texture
	$Shine.texture = texture
	# 源码 `*p_n2` 每帧加一，n2=0..3 画闪光，第 4 帧起停止。
	var phase := int(item.get("flash_phase", -1))
	if _shine_material != null:
		_shine_material.set_shader_parameter("phase", phase)
	$Shine.visible = phase >= 0 and phase <= 3
	$Image.show()
	$Label.text = text
	$Label.show()
	$Label.add_theme_color_override("font_color", Color.WHITE if int(item.image) == 0 else Color("#7b7b7b"))
	show()


func hit_rect() -> Rect2:
	var area: Control = $HitArea
	return Rect2(to_global(area.position), area.size)
