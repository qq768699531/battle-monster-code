extends "res://tests/unit/gut_case.gd"


func test_legacy_suite() -> void:
	var scene := load("res://core/monster_animation/monster_animation.tscn") as PackedScene
	var view = scene.instantiate()
	get_tree().root.add_child(view)
	view.position = Vector2(120, 180)
	assert_true(view.present("mon2/m_b_086_1"), "Godot monster scene loads")
	view._player.advance(0.15)
	var state: Dictionary = view.playback_state()
	var copy = scene.instantiate()
	get_tree().root.add_child(copy)
	copy.position = Vector2(280, 180)
	assert_true(copy.restore_playback(state) and copy.playback_state() == state,
		"Animation position restores without replay")
	var player: AnimationPlayer = view._player
	view.present("mon2/m_b_086_1", 0, 1)
	assert_true(view._player == player and player.current_animation_position == state.time and
		view.get_node("Content").scale == Vector2(-1, 1),
		"Turning mirrors the existing container without reloading or restarting playback")
	view.free()
	copy.free()
	# 步态只属于声明了 cycle_distance 的走跑片段；待机／剧情动作收到位移推进时跳过摆臂，
	# 不能把缺失的元数据喂给 float()（原生 Field_Hero_procMOVE 也只是按位移推进走跑）。
	var hero = scene.instantiate()
	get_tree().root.add_child(hero)
	assert_true(hero.present("hero/h_f_01", AniAction.FieldHero.IDLE_DOWN), "hero idle action plays")
	hero.advance_motion(1.5)
	assert_eq(hero._player.current_animation_position, 0.0,
		"idle action ignores motion advance instead of reading a missing cycle distance")
	var walk: Animation = hero._player.get_animation(
		AniAction.clip_name(hero._player, AniAction.FieldHero.WALK_DOWN))
	assert_true(walk.has_meta("cycle_distance") and float(walk.get_meta("cycle_distance")) > 0.0,
		"walk clip declares its gait cycle")
	assert_true(hero.present("hero/h_f_01", AniAction.FieldHero.WALK_DOWN), "hero walk action plays")
	hero.advance_motion(float(walk.get_meta("cycle_distance")) / 2.0)
	assert_almost_eq(hero._player.current_animation_position, walk.length / 2.0, 0.001)
	hero.free()
	# 野外物件图层 mode 235 的低 4 位是原生 op 11（Object_drawBUFFER0 的
	# case GRP_MODE_GRAYCOLOR），已落成灰度材质，不再进「未实现的混合模式」列表。
	var gray_object: Node2D = (load("res://field/map_actor/obj_f_99/obj_f_99.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(gray_object)
	assert_false(gray_object.has_meta("unapplied_blend_modes"),
		"gray-color layers render instead of being reported as unapplied")
	gray_object.free()
