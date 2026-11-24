@tool
extends Control
## 触控按钮：透明度/材质/位移由共用动画驱动，脚本只切换状态。

@export var key := 0
@export var style_mask := 0
@export var register_touch := true
@export var press_offset := Vector2.DOWN
@export_range(0.0, 1.0) var press_amount := 0.0:
	set(value):
		press_amount = value
		if is_node_ready():
			$Anchor/Visuals.position = press_offset * value

@onready var sprites: Array[Sprite2D] = [$Anchor/Visuals/Base, $Anchor/Visuals/Icon]

var _pressed := false
var _bright := false


func set_pressed(pressed: bool) -> void:
	if _pressed == pressed:
		return
	_pressed = pressed
	_apply_animation()


## 常亮状态：原生 `EFC_mainTouchDRAW:138-162` 在自动战斗（`BattleData + 24 == 1`）时先
## `JC_grpSetMODE(GRP_MODE_BRIGHT, v18)` 再画 AUTO 键，其中
## `v18 = ((frames_since_canvas_change / 2) & 3)` 取样成 64／0／64／128
## （`t == 0` 走 `(n − t) << 6`、`t > 0` 走 `(t − 1) << 6`），也就是**亮度在 0 与 128 之间来回**；
## 那四档只是按帧号取样留下的量化痕迹，真实效果是上下限之间的线性呼吸（一轮 8 帧 = 0.4 秒）。
## 亮度呼吸在 `bright` 动画的 `native_brightness` 轨里（0→128→0 线性），按钮本身保持 idle 的
## 0.5 半透明，脚本只切状态。
func set_bright(bright: bool) -> void:
	if _bright == bright:
		return
	_bright = bright
	_apply_animation()


func _apply_animation() -> void:
	# 原生 `EFC_mainTouchBUTTON2:73`：当前像素操作已是 `PIXEL_OPERATION_BRIGHT` 时跳过按下高亮，
	# 所以常亮优先于按下。
	var clip: StringName = &"bright" if _bright else (&"press" if _pressed else &"idle")
	if $AnimationPlayer.current_animation == clip:
		return
	$AnimationPlayer.play(clip)
	$AnimationPlayer.advance(0)
