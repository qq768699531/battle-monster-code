@tool
extends TextureRect
## 原生渐变条：把导出的起止色写入本实例私有的 GradientTexture2D。

@export var start_color := Color("#012534"):
	set(value):
		start_color = value
		_apply_colors()
@export var end_color := Color("#025071"):
	set(value):
		end_color = value
		_apply_colors()

var _localized := false


func _ready() -> void:
	# Scene 里的 Gradient 是共享子资源，先深复制成本实例私有再写入颜色，避免互相覆盖。
	texture = texture.duplicate(true)
	_localized = true
	_apply_colors()


func _apply_colors() -> void:
	if not _localized:
		return
	var gradient := (texture as GradientTexture2D).gradient
	gradient.set_color(0, start_color)
	gradient.set_color(1, end_color)
