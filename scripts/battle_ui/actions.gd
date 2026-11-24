extends Control
## 战斗指令窗口的展示与选择状态。

signal command_finished

var buttons: Array[Button] = []
var _callbacks: Dictionary = {}
var _feedback := 0


func _ready() -> void:
	$Commands/Art/AnimationPlayer.animation_finished.connect(_command_animation_finished)


func clear() -> void:
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
			command_finished.emit()
	elif AniAction.action_of_clip(name) == AniAction.Icon.IDLE and $Commands.visible:
		var animation: AnimationPlayer = $Commands/Art/AnimationPlayer
		animation.seek(0.3, true)
		animation.pause()

