extends Control
## 遇敌转场动画。
##
## 原生分两段：`Game_Ready_Battle_mPaint`（接触后的「战斗准备」动画 15 帧）
## 之后 `BattleCanvas_init` 进 `BATTLE_STATE_READY`，由
## `Battle_Ready_mPaint` 用 5 帧把黑幕 alpha 从 256 收到 0（就是「淡出战斗准备动画」），
## 同时 BATTLE／MONSTER 两个图案每帧右移 10px；`Battle_Ready_mRun` 在
## `run_counter > 5` 才切 `BATTLE_STATE_BASIC` 正式开打。

signal battle_ready
signal completed
signal effect_requested(resource_id: int)

var effect_played := false
var finished := false


func _ready() -> void:
	$Timeline.animation_finished.connect(_finished)


func present(image: Image, hero: Vector2) -> void:
	effect_played = false
	$Snapshot.texture = ImageTexture.create_from_image(image)
	$Snapshot.material.set_shader_parameter("hero_uv", hero / Vector2(399, 239))
	$Timeline.play("encounter")


func _play_effect() -> void:
	if not effect_played:
		effect_played = true
		effect_requested.emit(124)


## 「战斗准备」播完：先让战斗界面在下面开起来，再播淡出（黑幕 256 → 0 + 图案右移）。
func _finished(animation: StringName) -> void:
	if animation == &"encounter":
		battle_ready.emit()
		$Timeline.play("ready")
		return
	if not finished:
		finished = true
		completed.emit()
