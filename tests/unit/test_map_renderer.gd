extends "res://tests/unit/gut_case.gd"

const MAP_SCENE = preload("res://game/field/map/map/map_renderer.tscn")


func test_legacy_suite() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var renderer: Node2D = MAP_SCENE.instantiate()
	get_tree().root.add_child(renderer)
	var map_zero: Dictionary = catalog.load_map(0)
	assert_true(renderer.render_map(map_zero) and renderer.map_size_tiles == Vector2i(40, 30) and
		renderer.tile_count > 0 and renderer.find_children("*", "Sprite2D", true, false).is_empty(),
		"runtime renders the native m0 terrain from shared tile layers")
	var tile_layer: TileMapLayer = renderer.get_node("Layers/Map_0/Terrain/Layer_0")
	assert_true(tile_layer.get_cell_source_id(Vector2i.ZERO) >= 0 and
		tile_layer.get_cell_atlas_coords(Vector2i.ZERO) == Vector2i(1, 0),
		"every drawn cell is owned by the native atlas tile, not a per-tile sprite")
	renderer.clear()
	assert_true(renderer.tile_count == 0 and renderer.get_node("Layers").get_child_count() == 0,
		"clearing releases the previous native scene")
	renderer.free()
