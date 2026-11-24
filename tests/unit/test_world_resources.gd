extends "res://tests/unit/gut_case.gd"

const WorldResources = preload("res://core/world_resources/world_resources.gd")


func test_legacy_suite() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var resources = WorldResources.new()
	assert_true(resources.initialize(catalog), "native catalog initialization")
	var world: Variant = resources.map(0)
	assert_true(world is Dictionary and world.terrain.width_tiles == 40 and
		world.terrain.height_tiles == 30, "map 0 loads its native terrain")
	var dialogue: Variant = resources.dialogue("evt/evt0000.cht")
	assert_true(dialogue is Dictionary and dialogue.groups.size() == 3 and
		dialogue.groups[0].records[0].text == "雷亚……再稍微等一会儿……", "original dialogue contract")
