extends Control
## 战斗场上单个出战单位的绘制与姿态。目标光标不在这里：它在 `field.tscn` 的 `$Cursor` 这一独立层，
## 见 `field.gd::_place_target_cursor()`。

var _hit_revision := 0
var _status_stacks: Dictionary = {}


func present(ball: Dictionary, pose: Dictionary) -> void:
	visible = true
	$Pose.visible = not pose.is_empty()
	if not pose.is_empty():
		var revision := int(pose.get("revision", 0))
		# 原生 `Object_procCURR` 只把 `frame_index` 往前推，`Battle_Monster_procNext` 按
		# `same_animation_request_count * frame_count + frame_index` 跨循环判断命中帧——
		# 所以攻击／技能／分身动作在行动结束前一直循环，不是播一遍停在末帧。
		$Pose.present(ball, int(pose.action), 1.0,
			ball.hp == null or ball.hp > 0,
			revision != _hit_revision)
		_hit_revision = revision
	$Statuses.scale.x = -1.0 if int(ball.direction) == 1 else 1.0
	_present_status($Statuses/Weakness, ball, StatusEffect.Code.WEAKNESS, StatusEffect.Icon.WEAKNESS)
	_present_status($Statuses/Seal, ball, StatusEffect.Code.SEAL, StatusEffect.Icon.SEAL)


func _present_status(effect: Node2D, ball: Dictionary, code: int, action: int) -> void:
	var active: bool = ball.get("statuses", {}).has(code) and ball.hp != null and ball.hp > 0
	if active and (not effect.visible or _status_stacks.get(code, 0) != ball.statuses[code].stacks):
		effect.restore_playback({"identity": "obj/b_effect", "action": action,
			"direction": 0, "looped": false, "time": 0.0})
		var player: AnimationPlayer = effect.get_node("Content").get_child(0).get_node("AnimationPlayer")
		if not player.animation_finished.is_connected(_status_started.bind(effect, action)):
			player.animation_finished.connect(_status_started.bind(effect, action))
	if active:
		_status_stacks[code] = ball.statuses[code].stacks
	effect.visible = active


func _status_started(_animation: StringName, effect: Node2D, action: int) -> void:
	if effect.visible:
		effect.present("obj/b_effect", action + 1, int(effect.playback_state().direction), true)
