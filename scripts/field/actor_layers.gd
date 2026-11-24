extends Node2D
## 地图/战斗单位的绘制体：持有一个 monster_animation 实例。

const ANIMATION_SCENE = preload("res://scenes/components/monster_animation.tscn")

## 非循环动作播完（转发 `monster_animation.animation_finished`）；循环动作每圈也会触发，
## 调用方要按当前 action 判定。
signal animation_finished

var _monster: Node2D


func clear_layers() -> void:
	if _monster != null:
		remove_child(_monster)
		_monster.free()
		_monster = null


func present(art: Dictionary, looped: bool, report: Callable,
		preserve_phase: bool = false) -> Dictionary:
	if art.is_empty():
		clear_layers()
		return {}
	if _monster == null:
		_monster = ANIMATION_SCENE.instantiate()
		_monster.name = "Monster"
		add_child(_monster)
		_monster.set_manual(true)
		_monster.animation_finished.connect(func() -> void: animation_finished.emit())
	if not _monster.present(art.path, int(art.action), int(art.direction), looped,
			preserve_phase, int(art.get("fallback", -1))):
		report.call(_monster.last_error)
		return {}
	return {"path": art.path, "action": _monster.playback_state().action,
		"direction": art.direction, "bounds": _monster.bounds(), "frame": _monster.frame_index(),
		"frames": _monster.frame_count(_monster.playback_state().action)}


func set_monster_running(value: bool) -> void:
	if _monster != null:
		_monster.set_running(value)


func advance(delta: float) -> void:
	if _monster != null:
		_monster.advance(delta)


func advance_motion(distance: float) -> void:
	_monster.advance_motion(distance)


func frame_index() -> int:
	return _monster.frame_index() if _monster != null else 0
