extends Control
## 战斗指令窗口的展示与选择状态。

signal command_finished
## 五向轮盘的入场动画（`obj/b_icon2` 的动作 0，7 帧 / 0.35 秒）播完。原生
## `Battle_Menu_mPaint` 的子状态 0 在这一刻调 `Battle_Menu_Auto`，AUTO／敌方 AI 因此
## 和玩家走同一套「轮盘入场 → 接受 → 退出 → 淡出」流程。
signal intro_finished

## 退出动画（动作 6–10，3 帧）播完后整块轮盘淡出的帧数与时长（0.05 秒/帧）。
const EXIT_FADE_FRAMES := 4
const EXIT_FADE_SECONDS := EXIT_FADE_FRAMES * 0.05

var buttons: Array[Button] = []
var _callbacks: Dictionary = {}
var _feedback := 0
var _fade_tween: Tween
var _fading := false


func _ready() -> void:
	$Commands/Art/AnimationPlayer.animation_finished.connect(_command_animation_finished)


func clear() -> void:
	_cancel_fade()
	_feedback = 0
	for button in buttons:
		var callback: Callable = _callbacks.get(button, Callable())
		if callback.is_valid() and button.pressed.is_connected(callback):
			button.pressed.disconnect(callback)
		button.hide()
	buttons.clear()
	_callbacks.clear()
	$Commands.hide()
	var animation: AnimationPlayer = $Commands/Art/AnimationPlayer
	animation.stop()
	animation.play(AniAction.clip_name(animation, AniAction.Icon.IDLE))
	animation.seek(0.0, true)
	animation.pause()


func add_button(_x: float, text: String, callback: Callable, enabled := true) -> void:
	var names := {"攻击": "Commands/Attack", "技能": "Commands/Skill",
		"防御 ↑": "Commands/Guard", "逃跑": "Commands/Flee", "道具": "Commands/Item",
		"确认结果": "ConfirmResult", "返回标题": "ReturnTitle", "返回地图": "ReturnTitle"}
	var button: Button = get_node(names[text])
	if button == $ReturnTitle:
		button.text = text
	if button.get_parent() == $Commands and not $Commands.visible:
		$Commands.show()
		var animation: AnimationPlayer = $Commands/Art/AnimationPlayer
		animation.stop()
		animation.play(AniAction.clip_name(animation, AniAction.Icon.IDLE))
		animation.advance(0.0)
	button.disabled = not enabled
	button.show()
	if callback.is_valid():
		button.pressed.connect(callback)
		_callbacks[button] = callback
	buttons.append(button)


func place_commands(at: Vector2) -> void:
	$Commands.position = Vector2(at.x, minf(at.y - 20, 150))


func select_command(action: String) -> void:
	_feedback = AniAction.COMMAND_ORDER.find(action) + 1
	for button: Button in buttons:
		button.disabled = true
	_play_feedback(_feedback)


## 指令序号 → 该指令的原生图标动作号；松开是按下 + `AniAction.COMMAND_PRESS_OFFSET`。
func _feedback_action(command: int, released: bool) -> int:
	return command + (AniAction.COMMAND_PRESS_OFFSET if released else 0)


func _play_feedback(command: int, released := false) -> void:
	var animation: AnimationPlayer = $Commands/Art/AnimationPlayer
	var action := _feedback_action(command, released)
	animation.play(AniAction.clip_name(animation, action))
	animation.advance(0.0)


func _command_animation_finished(name: StringName) -> void:
	if _feedback > 0:
		var played := AniAction.action_of_clip(name)
		if played == _feedback:
			_play_feedback(_feedback, true)
		elif played == _feedback_action(_feedback, true):
			_feedback = 0
			_fade_out()
	elif AniAction.action_of_clip(name) == AniAction.Icon.IDLE and $Commands.visible:
		var animation: AnimationPlayer = $Commands/Art/AnimationPlayer
		animation.seek(0.3, true)
		animation.pause()
		intro_finished.emit()


## 原生退出动画（6–10）把轮盘逐帧压黑；这里在它之后再补一段整块 `modulate.a` 淡出，
## 淡出结束才回报 `command_finished`，所以确认后不会直接跳走。
func _fade_out() -> void:
	if _fading:
		return
	_fading = true
	_fade_tween = create_tween()
	_fade_tween.tween_property($Commands, "modulate:a", 0.0, EXIT_FADE_SECONDS)
	_fade_tween.finished.connect(_fade_finished)


func _fade_finished() -> void:
	_fading = false
	_fade_tween = null
	$Commands.hide()
	$Commands.modulate.a = 1.0
	command_finished.emit()


## 中途清掉指令窗（换目标、逃跑、结束战斗）时终止淡出并复位透明度。
func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_fading = false
	$Commands.modulate.a = 1.0

