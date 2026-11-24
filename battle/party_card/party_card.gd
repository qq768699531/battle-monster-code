extends Control
## 出战队伍卡片。

const MonsterAnimation = preload("res://core/monster_animation/monster_animation.gd")


func present(ball: Dictionary, species: MonsterDefinition) -> void:
	$Vitals.present(ball)
	$Clip/Monster.present(MonsterAnimation.battle_identity(int(ball.species)), 0, 1)
	var origin := species.prime_portrait_position
	$Clip/Monster.position = Vector2(31 - origin / 100, absi(origin) % 100)
	$Clip/Monster.set_grayscale(ball.hp != null and int(ball.hp) == 0)
