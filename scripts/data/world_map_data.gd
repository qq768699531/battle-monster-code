extends Resource
## 原生世界地图节点表（`assets/assets/map/mini.mmi`）。
##
## `Map_worldCOUNT` 先读 int32 条数，`Map_worldGET` 再按 60 字节定长记录
## 读单条：+0 图标号（`obj/ui_world.fbm` 帧号）、+1 等级、+2 地图号、
## +4 起 32 字节原生字形名、+36 行、+38 列、+40 起四个邻接地图号（-1 为空）。
## 列 > 99 的记录是「室内层」，只在当前地图本身是室内层时绘制
## （`Map_worldINIT` 写 `+80` 标志，`Map_worldDRAW` 按它过滤）。
## 名称不复用字形字节：与地图 Scene 一致，走 `map/m<id>.mif:name` 翻译。
##
## 由 `script/export_world_map.py` 生成。
@export var nodes: Dictionary = {}

## 行号 ≥ 99 的记录没有排进世界地图网格（`mini.mmi` 里 148 号是 (99, 99)），只留数据。
const PLACEMENT_MISSING := 99


func count() -> int:
	return nodes.size()


func node(map_id: int) -> Dictionary:
	var record: Variant = nodes.get(map_id)
	return record if record is Dictionary else {}


## 当前地图所属的层：列 > 99 为室内层。
func interior(map_id: int) -> bool:
	return column(map_id) > 99


func column(map_id: int) -> int:
	return int(node(map_id).get("column", -1))


func row(map_id: int) -> int:
	return int(node(map_id).get("row", -1))


func icon(map_id: int) -> int:
	return int(node(map_id).get("icon", 0))


func level(map_id: int) -> int:
	return int(node(map_id).get("level", 1))


## 与该地图相邻的地图号（已去掉 -1）。
func links(map_id: int) -> Array:
	var result: Array = []
	for target: Variant in node(map_id).get("links", []):
		if int(target) >= 0:
			result.append(int(target))
	return result


## 同一格可能有多条记录（如基连神殿1/2、沿别轮神殿1/2 都在 (0,7)），其中只有带连线的
## 那条是世界地图上的入口，其余 66 条是无连线的次级记录且从没被别的记录连到。
## 截图里每格只出现一个名称与图标，所以按「同格优先取带连线的记录」去重。
func layer_ids(interior_layer: bool) -> Array:
	var cells := {}
	for map_id: Variant in nodes.keys():
		var id := int(map_id)
		if interior(id) != interior_layer or row(id) >= PLACEMENT_MISSING:
			continue
		var cell := Vector2i(column(id) % 100, row(id))
		if not cells.has(cell):
			cells[cell] = id
			continue
		var previous: int = cells[cell]
		if links(previous).is_empty() and not links(id).is_empty():
			cells[cell] = id
	var result: Array = []
	for cell: Variant in cells.keys():
		result.append(int(cells[cell]))
	result.sort()
	return result


## 该层的格数（列数、行数），用于镜头夹取与总览。
## 记录里 (99, 99) 是「没有排进网格」的占位（148 号），不参与格数。
func extents(interior_layer: bool) -> Vector2i:
	var columns := 1
	var rows := 1
	for map_id: Variant in layer_ids(interior_layer):
		if row(int(map_id)) >= PLACEMENT_MISSING:
			continue
		columns = maxi(columns, column(int(map_id)) % 100 + 1)
		rows = maxi(rows, row(int(map_id)) + 1)
	return Vector2i(columns, rows)
