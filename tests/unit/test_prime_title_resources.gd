extends "res://tests/unit/gut_case.gd"

const MonsterAnimation = preload("res://core/monster_animation/monster_animation.gd")


func _run() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	for identity: String in ["obj/title", "ktf/elogo", "obj/ensony", "obj/ui_select", "touch/ui_touch"]:
		assert_true(ResourceLoader.exists(MonsterAnimation.scene_path(identity)),
			"Missing converted animation scene: %s" % identity)
	assert_true(catalog.get_startup_errors().is_empty())
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	assert_true(main._startup_error.is_empty())
	main.queue_free()
	await get_tree().process_frame


func test_legacy_suite() -> void:
	await _run()
