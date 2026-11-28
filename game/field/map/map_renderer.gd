extends Node2D
## Instantiates editor-authored tilemap scenes; gameplay metadata remains in WorldResources.
## Map interaction rules live in BattleMap (field/map/map.gd): the scene root carries that script.

var last_error := ""
var map_size_tiles := Vector2i.ZERO
var tile_count := 0
var _airship_background: CanvasLayer
## 原生 `FieldCanvas_load:30-31`：地图组 6（飞艇）额外加载 `Object_resLOAD(15, 91)`；
## `Map_Proc:22-25` 在画瓦片前把它画在 (104,0)／(312,0)，作为飞艇地图下方的独立风景背景。
## 对应 `map9_a_1`（104×320，天空/山野），不是水晶等地图物件。
const AIRSHIP_MAP_GROUP := 6
const AIRSHIP_BACKGROUND_SPRITE := "obj/map9_a_1/frame-000"
const AIRSHIP_BACKGROUND_POSITIONS := [Vector2(104, 0), Vector2(312, 0)]


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
	if map_view is BattleMap and (map_view as BattleMap).map_group == AIRSHIP_MAP_GROUP:
		_add_airship_background()
	map_size_tiles = map_view.get_meta("map_size_tiles")
	var terrain := map_view.get_node_or_null("Terrain")
	for layer: TileMapLayer in (terrain.get_children() if terrain != null else map_view.get_children()):
		tile_count += layer.get_used_cells().size()
	return true


func _add_airship_background() -> void:
	if _airship_background == null:
		_airship_background = CanvasLayer.new()
		_airship_background.layer = -1
		add_child(_airship_background)
	for child: Node in _airship_background.get_children():
		child.queue_free()
	var catalog := get_node_or_null("/root/AssetCatalog")
	if catalog == null:
		return
	var texture: Texture2D = catalog.call("load_sprite", AIRSHIP_BACKGROUND_SPRITE)
	if texture == null:
		return
	for position: Vector2 in AIRSHIP_BACKGROUND_POSITIONS:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = position
		sprite.z_index = -1
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_airship_background.add_child(sprite)


func _clear_airship_background() -> void:
	if _airship_background != null:
		_airship_background.visible = false


func clear() -> void:
	_clear_airship_background()
	for child in $Layers.get_children():
		$Layers.remove_child(child)
		child.free()
	map_size_tiles = Vector2i.ZERO
	tile_count = 0
	last_error = ""
