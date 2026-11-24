extends Control
## 战斗姿态与动作播放的封装。

const MonsterAnimation = preload("res://scripts/components/monster_animation.gd")

@export var actor_scale := 1.0


func present(ball: Dictionary, action: int, alpha: float, looped: bool = false,
		restart: bool = false) -> void:
	var monster: Node2D = $Monster
	monster.scale = Vector2.ONE * actor_scale
	monster.modulate.a = alpha
	var path := MonsterAnimation.battle_identity(int(ball.species))
	if monster.present(path, action, int(ball.direction), looped) and restart:
		monster.restore_playback({"identity": path, "direction": int(ball.direction),
			"action": action, "looped": looped, "time": 0.0})
