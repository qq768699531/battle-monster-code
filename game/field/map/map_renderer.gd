extends Node2D
## Instantiates editor-authored tilemap scenes; gameplay metadata remains in WorldResources.
## Map interaction rules live in BattleMap (field/map/map.gd): the scene root carries that script.
## A map scene owns its optional background layer (e.g. m148's airship landscape); maps that
## do not need one simply have no Background node.

var last_error := ""
var map_size_tiles := Vector2i.ZERO
var tile_count := 0


func render_map(map_data: Dictionary) -> bool:
	clear()
	var id := int(map_data.get("id", -1))
	var path := "res://game/field/map/map_set/m%d/m%d.tscn" % [id, id]
	var scene: PackedScene = load(path)
	if scene == null:
		last_error = "Map scene could not be loaded: " + path
		return false
	var map_view: Node2D = scene.instantiate()
	if map_view is BattleMap:
		if not (map_view as BattleMap).setup(map_data):
			last_error = "Map rules rejected the payload: " + path
			map_view.free()
			return false
	$Layers.add_child(map_view)
	map_size_tiles = map_view.get_meta("map_size_tiles")
	var terrain := map_view.get_node_or_null("Terrain")
	for layer: TileMapLayer in (terrain.get_children() if terrain != null else map_view.get_children()):
		tile_count += layer.get_used_cells().size()
	return true


func clear() -> void:
	for child in $Layers.get_children():
		$Layers.remove_child(child)
		child.free()
	map_size_tiles = Vector2i.ZERO
	tile_count = 0
	last_error = ""
