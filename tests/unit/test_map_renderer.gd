extends "res://tests/unit/gut_case.gd"

const MAP_SCENE = preload("res://game/field/map/map/map_renderer.tscn")
const WorldResources = preload("res://engine/data/world_resources/world_resources.gd")


func test_legacy_suite() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var resources = WorldResources.new()
	var initialized: bool = resources.initialize(catalog)
	var map_zero: Variant = resources.map(0)
		resources.last_error])
	assert_true(initialized and map_zero is Dictionary,
		"map 0 loads through WorldResources: %s" % resources.last_error)
	if not map_zero is Dictionary:
		return
	var renderer: Node2D = MAP_SCENE.instantiate()
	get_tree().root.add_child(renderer)
	var rendered: bool = renderer.render_map(map_zero)
		renderer.map_size_tiles, renderer.tile_count])
	assert_true(rendered, "render_map accepts the WorldResources payload: %s" % renderer.last_error)
	var tile_layer: TileMapLayer = renderer.get_node_or_null("Layers/Map_0/Terrain/Layer_0")
	if rendered and tile_layer != null:
		assert_true(tile_layer.get_cell_source_id(Vector2i.ZERO) >= 0 and
			tile_layer.get_cell_atlas_coords(Vector2i.ZERO) == Vector2i(1, 0),
			"every drawn cell is owned by the native atlas tile, not a per-tile sprite")
	renderer.clear()
	assert_true(renderer.tile_count == 0 and renderer.get_node("Layers").get_child_count() == 0,
		"clearing releases the previous native scene")
	renderer.free()
