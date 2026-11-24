class_name BattleMap
extends Node2D
## 地图交互规则的唯一实现：通行判定、传送点、实体占位、地图组归属。
##
## 具体地图不再各写一套判定：场景根节点挂本脚本，由 `setup()` 接收
## WorldResources 的地图载荷（id/info/terrain），之后所有格子查询都走这里。
## 规则依据：原生 `Map_tileSetMove`、`Map_tileIsMoveRect`、`Map_warpProc`。
##
## 约定：
## - `cell_flags` 是 `cell_flags[y][x]`，低 3 位非 0 即阻挡。
## - 事件矩形在矩形内无条件放行，优先于地形标志。
## - 实体（玩家以外的 actor）占格另行判定，不写进地形。
## - 越界一律视为阻挡，不做回绕。

signal warp_entered(warp: Dictionary)

const TILE_SIZE := 16.0
const BLOCK_MASK := 7
const DIRECTION_STEP := {
	Vector2i.LEFT: Vector2i(-1, 0),
	Vector2i.RIGHT: Vector2i(1, 0),
	Vector2i.UP: Vector2i(0, -1),
	Vector2i.DOWN: Vector2i(0, 1),
}

var map_id := -1
var size_tiles := Vector2i.ZERO
var palette_indices: Array = []
var map_group := -1
var map_index := -1
var warps: Array = []
var npcs: Array = []
var move_rects: Array = []
var configured := false

var _cell_flags: Array = []


func _ready() -> void:
	if not configured:
		_adopt_scene_metadata()


## 用 WorldResources 的地图载荷装配规则；返回是否装配成功。
## 载荷结构：{"id", "info": {map_group, map_index, palette_indices, warps, npcs}, "terrain": {...}}
func setup(payload: Dictionary) -> bool:
	if not payload.get("terrain") is Dictionary or not payload.get("info") is Dictionary:
		return false
	map_id = int(payload.get("id", -1))
	if not _adopt_terrain(payload.terrain):
		return false
	_adopt_info(payload.info)
	configured = true
	return true


## 只装配地形（单元测试与不依赖 info 的渲染路径）。
func setup_terrain(terrain: Dictionary) -> bool:
	if not _adopt_terrain(terrain):
		return false
	configured = true
	return true


func _adopt_terrain(terrain: Dictionary) -> bool:
	var width := int(terrain.get("width_tiles", 0))
	var height := int(terrain.get("height_tiles", 0))
	var rows: Variant = terrain.get("cell_flags")
	if width <= 0 or height <= 0 or not rows is Array or rows.size() < height:
		return false
	for y in range(height):
		if not rows[y] is Array or (rows[y] as Array).size() < width:
			return false
	_cell_flags = rows
	size_tiles = Vector2i(width, height)
	return true


func _adopt_info(info: Dictionary) -> void:
	map_group = int(info.get("map_group", -1))
	map_index = int(info.get("map_index", -1))
	palette_indices = (info.get("palette_indices", []) as Array).duplicate()
	warps = (info.get("warps", []) as Array).duplicate(true)
	npcs = (info.get("npcs", []) as Array).duplicate(true)


## 场景自带的元数据（地图场景是编辑器产出的数据，运行时的通行表由 setup 注入）。
func _adopt_scene_metadata() -> void:
	map_id = int(get_meta("map_id", -1))
	map_group = int(get_meta("map_group", -1))
	map_index = int(get_meta("map_index", -1))
	size_tiles = get_meta("map_size_tiles", Vector2i.ZERO)
	palette_indices = (get_meta("map_palette_indices", PackedInt32Array()) as PackedInt32Array).duplicate()


## 静态入口：不持有场景时也能用同一套规则（Story 只有地图载荷，没有地图视图）。
static func blocked(terrain: Dictionary, rects: Array, map_id: int, cell: Vector2i) -> bool:
	if in_rects(rects, map_id, cell):
		return false
	var width := int(terrain.get("width_tiles", 0))
	var height := int(terrain.get("height_tiles", 0))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return true
	var rows: Variant = terrain.get("cell_flags")
	if not rows is Array or cell.y >= rows.size() or not rows[cell.y] is Array:
		return true
	var row: Array = rows[cell.y]
	if cell.x >= row.size():
		return true
	return (int(row[cell.x]) & BLOCK_MASK) != 0


static func in_rects(rects: Array, map_id: int, cell: Vector2i) -> bool:
	for rect: Array in rects:
		if int(rect[0]) != map_id:
			continue
		var x := int(rect[1])
		var y := int(rect[2])
		if cell.x >= x and cell.y >= y and cell.x < x + int(rect[3]) and cell.y < y + int(rect[4]):
			return true
	return false


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size_tiles.x and cell.y < size_tiles.y


## 事件矩形放行：原生 `Map_tileIsMoveRect` 只认当前地图的矩形。
func in_move_rect(cell: Vector2i) -> bool:
	for rect: Array in move_rects:
		if int(rect[0]) != map_id:
			continue
		var x := int(rect[1])
		var y := int(rect[2])
		if cell.x >= x and cell.y >= y and cell.x < x + int(rect[3]) and cell.y < y + int(rect[4]):
			return true
	return false


## 地形阻挡：越界、标志位、缺少数据都算阻挡；事件矩形优先放行。
func terrain_blocked(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return true
	if in_move_rect(cell):
		return false
	var row: Variant = _cell_flags[cell.y]
	return (int(row[cell.x]) & BLOCK_MASK) != 0


## 只看地形是否可走（不含实体占位）。
func is_walkable(cell: Vector2i) -> bool:
	return not terrain_blocked(cell)


## 本格上的实体（id 0 是玩家，默认不算阻挡）；没有则返回空字典。
func actor_at(cell: Vector2i, actors: Array, exclude_id := 0) -> Dictionary:
	for actor: Dictionary in actors:
		if int(actor.get("id", 0)) == int(exclude_id):
			continue
		if Vector2i(roundi(actor.get("x", -1.0)), roundi(actor.get("y", -1.0))) == cell:
			return actor
	return {}


## 走位判定：地形 + 实体占位。`actors` 为空时只看地形。
func can_enter(cell: Vector2i, actors: Array = []) -> bool:
	if terrain_blocked(cell):
		return false
	return actor_at(cell, actors).is_empty()


## 目标格上的传送点；没有返回空字典。目标非法不在这里判断（由换图流程报错）。
func warp_at(cell: Vector2i) -> Dictionary:
	for warp: Dictionary in warps:
		if Vector2i(int(warp.get("tile_x", -1)), int(warp.get("tile_y", -1))) == cell:
			return warp
	return {}


func npc_at(cell: Vector2i) -> Dictionary:
	for npc: Dictionary in npcs:
		if Vector2i(int(npc.get("tile_x", -1)), int(npc.get("tile_y", -1))) == cell:
			return npc
	return {}


## 事件矩形集合由 Story 在事件开始时下发；矩形格式 [map_id, x, y, w, h]。
func set_move_rects(rects: Array) -> void:
	move_rects = rects


func to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE_SIZE


func to_cell(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / TILE_SIZE), floori(world.y / TILE_SIZE))


## 请求朝某方向走一格，返回是否放行（同时发信号，不直接改地图状态）。
func request_warp(cell: Vector2i) -> bool:
	var warp := warp_at(cell)
	if warp.is_empty():
		return false
	warp_entered.emit(warp)
	return true
