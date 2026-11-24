extends "res://tests/unit/gut_case.gd"

func test_legacy_suite() -> void:
	_test()


func _test() -> void:
	var catalog: GameplayData = get_tree().root.get_node("AssetCatalog").load_gameplay_catalog()
	assert_true(catalog != null and catalog.items.size() == 367 and catalog.monsters.size() == 131
		and catalog.passives.size() == 168 and catalog.encounters.size() == 149
		and catalog.script_battles.size() == 98,
		"Gameplay data loads as a typed resource with the full native tables.")
	var item: ItemDefinition = catalog.item(1000)
	assert_true(item != null and item.type == 1 and item.index == 0 and item.icon == 0
		and item.purchase_price is int and not item.detail_slots.is_empty(),
		"Typed item records expose integer identifiers, icon frames and slots.")
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	assert_true(assets.get_startup_errors().is_empty(), "The shipped resources load without startup errors.")
