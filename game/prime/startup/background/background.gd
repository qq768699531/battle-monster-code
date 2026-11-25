extends Node2D
## 标题背景：只更新投影与颜色，不改 Scene 几何。
const Runtime = preload("res://game/prime/title/prime_title_runtime/prime_title_runtime.gd")
const PrimeView = preload("res://game/prime/startup/prime_view/prime_view.gd")
const UI = preload("res://game/prime/ui/layout/layout.gd")
var scene := -1
var captured: Texture2D
@onready var box: Control = $Box
@onready var edge_shade: ColorRect = $EdgeShade

func present(next_scene: int, texture: Texture2D, state: int) -> void:
	scene = next_scene
	captured = texture
	$Fill.color = Color.WHITE if scene == Runtime.LOGO else Color.BLACK
	$Capture.texture = captured
	$Capture.visible = scene >= Runtime.SAVE_SELECT and captured != null
	# 压黑边只跟着抓取背景出现：LOGO 的白底和其它页不压。
	edge_shade.visible = $Capture.visible
	box.visible = scene == Runtime.SAVE_SELECT and state not in [0, -4]
	if box.visible:
		if box.phase != state:
			box.phase = state
		box.modulate.a = UI.phase_alpha(state)
