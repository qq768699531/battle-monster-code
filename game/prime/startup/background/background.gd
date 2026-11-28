extends Node2D
## 标题背景：只更新投影与颜色，不改 Scene 几何。
const Runtime = preload("res://game/prime/title/prime_title_runtime/prime_title_runtime.gd")
const UI = preload("res://game/prime/ui/layout/layout.gd")
var scene := -1
var captured: Texture2D
@onready var box: Control = $Box

func present(next_scene: int, texture: Texture2D, state: int) -> void:
	scene = next_scene
	captured = texture
	$Fill.color = Color.WHITE if scene == Runtime.LOGO else Color.BLACK
	$Capture.texture = captured
	# 原生 `Prime_Title_Capture` 只把标题画面叠一层 50% 黑，不再做边缘渐隐；
	# 抓取图本身就是整屏的标题画面，没有需要遮的矩形边。
	$Capture.visible = scene >= Runtime.SAVE_SELECT and captured != null
	box.visible = scene == Runtime.SAVE_SELECT and state not in [0, -4]
	if box.visible:
		if box.phase != state:
			box.phase = state
		box.modulate.a = UI.phase_alpha(state)
