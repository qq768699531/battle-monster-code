extends RefCounted
## Synchronous, validated world data backed exclusively by AssetCatalog's native resources.
## Call initialize(root.get_node("AssetCatalog")) after the autoload is ready.
## Loaders return null on failure; last_error contains the diagnostic (no timing or I/O here).

const GameplayData = preload("res://core/gameplay_data/gameplay_data.gd")
const NpcDefinition = preload("res://field/npc_definition/npc_definition.gd")

var map_ids: Array[int] = []
var event_ids: Array[int] = []
var last_error := ""

var _assets: Node
var _event_scripts: Variant
var _map_scenes: Dictionary = {}
var _events: Dictionary = {}


func initialize(asset_catalog: Node, event_scripts: Variant = null) -> bool:
	_assets = null
	_event_scripts = event_scripts
	_map_scenes.clear()
	_events.clear()
	map_ids.clear()
	event_ids.clear()
	last_error = ""
	if not is_instance_valid(asset_catalog):
		_fail("转换资源清单格式不受支持")
		return false
	# 地图注册直接从 Godot 场景目录推导：一个地图组一个目录 `m<id>/`，里面是 `m<id>.tscn`。
	var directory := DirAccess.open("res://maps")
	if directory == null:
		_fail("地图场景目录缺失：res://maps")
		return false
	for name: String in directory.get_directories():
		if not name.begins_with("m"):
			continue
		var digits := name.substr(1)
		if not digits.is_valid_int():
			continue
		if not ResourceLoader.exists("res://maps/%s/%s.tscn" % [name, name]):
			continue
		var id := digits.to_int()
		_map_scenes[id] = true
		map_ids.append(id)
	map_ids.sort()
	# 事件脚本总表：Scene 传入优先；没传就用共享的 `assets/events.tres`。
	if _event_scripts == null:
		_event_scripts = load("res://main/main/event_scripts.tres")
	if _event_scripts != null and not _event_scripts.scripts.is_empty():
		for id: Variant in _event_scripts.scripts.keys():
			_events[int(id)] = _event_scripts.scripts[id]
	for id: Variant in _events.keys():
		event_ids.append(int(id))
	event_ids.sort()
	_assets = asset_catalog
	return true


func gameplay() -> GameplayData:
	if not _begin_load():
		return null
	var data: GameplayData = _assets.load_gameplay_catalog()
	if data == null or data.items.is_empty() or data.monsters.is_empty() or \
			data.encounters.is_empty():
		return _fail("游戏数值目录缺失或版本不兼容")
	return data


func load_gameplay() -> GameplayData:
	return gameplay()


func load_map(id: int) -> Variant:
	return map(id)


func load_event(id: int) -> Variant:
	return event(id)


func load_dialogue(source_id: String) -> Variant:
	return dialogue(source_id)


func map(id: int) -> Variant:
	if not _begin_load():
		return null
	if not _map_scenes.has(id):
		return _fail("地图场景未登记：m%d" % id)
	var data: Variant = _assets.load_map(id)
	if not data is Dictionary or not data.get("info") is Dictionary:
		return _fail("MIF runtime 契约不兼容：m%d" % id)
	var info: Dictionary = data.info.duplicate(true)
	# 地图名只在翻译资源里（`map/m<id>.mif:name`）：地图结构在地图 Scene，没有单独载荷。
	var name_id := "map/m%d.mif" % id
	if _assets.has_text(name_id):
		var names: Variant = _assets.text_messages(name_id)
		if not names is Dictionary or not names.has("name"):
			return _fail("MIF 地图名称契约不兼容：m%d" % id)
		var value: Variant = names["name"]
		info["name_text"] = null if value == null else String(value)
		info["name_text_status"] = "unmapped" if value == null else "verified-mapping"
	if not _valid_map_name(info) or not info.get("npcs") is Array or \
			not info.get("warps") is Array or not info.get("palette_indices") is Array or \
			not _integer(info.get("map_group")) or not _integer(info.get("map_index")):
		return _fail("MIF runtime 契约不兼容：m%d" % id)
	var bindings: Variant = npc_bindings()
	if bindings == null:
		return null
	info["npc_bindings"] = bindings
	var terrain: Variant = data.get("layout")
	var sheets: Variant = data.get("images")
	if not _valid_terrain(terrain) or not sheets is Array or sheets.is_empty():
		return _fail("地图通行格或图像引用缺失：m%d" % id)
	for sheet: Variant in sheets:
		if not sheet is Dictionary or not _integer(sheet.get("slot")):
			return _fail("地图 runtime 或图像引用缺失：m%d" % id)
		var slot := int(sheet.slot)
		var palette: Variant = info.palette_indices[slot] if slot >= 0 and \
			slot < info.palette_indices.size() else 0
		if slot < 0 or sheet.get("status") != "resolved" or \
				not _integer(sheet.get("palette_index")) or palette != sheet.palette_index:
			return _fail("地图图像/调色板尚未绑定：m%d 槽 %d（不会猜测 WEBP）" % [id, slot])
		if not sheet.get("sprite_id") is String or not _assets.sprite_exists(sheet.sprite_id):
			return _fail("地图精灵未登记：m%d 槽 %d" % [id, slot])
	return {"id": id, "info": info, "terrain": terrain.duplicate(true), "sheets": sheets.duplicate(true)}


## NPC 绑定来自玩法数据 `gameplay.tres` 的 `npcs`；名字单独按 `npc:<id>` 存在翻译资源里。
## 每次调用都重新构造记录，调用方改动返回值不会污染缓存。
func npc_bindings() -> Variant:
	var data: GameplayData = _assets.load_gameplay_catalog()
	if data == null:
		return _fail("玩法数据无法加载：NPC 绑定")
	var names: Dictionary = _assets.text_messages("npc")
	var records: Array = []
	for record: NpcDefinition in data.npcs:
		# 记录号必须从 0 连续：贴图与说话人名字都按这个序号索引。
		if record.id != records.size() or record.field_sprite_id < 0 or \
				record.field_sprite_id > 255 or record.interaction_code < 0 or \
				record.interaction_code > 255 or record.idle_movement_gate < 0 or \
				record.idle_movement_gate > 255:
			return _fail("NPC 绑定记录不合法：id %d" % record.id)
		var name: Variant = names.get(record.id)
		records.append({
			"record_index": record.id,
			"name_source": "unmapped" if name == null else "verified-mapping",
			"name_text": name,
			"field_sprite_id": record.field_sprite_id,
			"interaction_code": record.interaction_code,
			"idle_movement_gate": record.idle_movement_gate,
		})
	return records


func text(source_id: String) -> Variant:
	if not _begin_load():
		return null
	if not _assets.has_text(source_id):
		return _fail("文本资源未登记：%s（不是 Unicode 待转换）" % source_id)
	var data: Variant = _assets.load_text(source_id)
	if not data is Dictionary:
		return _fail("文本资源无法加载：%s" % source_id)
	return data.duplicate(true)


func dialogue(source_id: String) -> Variant:
	var doc: Variant = text(source_id)
	if doc == null:
		return null
	if doc.get("schema") != "battlemonster.cht.runtime.v1" or not doc.get("groups") is Array:
		return _fail("CHT runtime 契约不兼容：%s" % source_id)
	for group: Variant in doc.groups:
		if not group is Dictionary or not group.get("records") is Array:
			return _fail("CHT runtime 契约不兼容：%s" % source_id)
		for record: Variant in group.records:
			if not record is Dictionary or not record.has("text") or \
					not (record.text == null or record.text is String) or \
					not record.get("text_status") is String or \
					(record.text == null and record.text_status != "unmapped"):
				return _fail("CHT runtime 契约不兼容：%s" % source_id)
	return doc


## 事件表里有没有这一号：原生 `Evt_stdSTYLE:20` 用 `JC_memGET(evt/evtNNNN.qst) == nullptr`
## 判「没有这个事件资源」，`Evt_stdINIT:33` 据此把 `EvtData.step_index` 置 −1 安静收尾。
## 只查 `initialize()` 已经收进来的那张总表，不做加载/转换，也不改 `last_error`。
func has_event(id: int) -> bool:
	return _events.has(id)


func event(id: int) -> Variant:
	if not _begin_load():
		return null
	var key := "evt/evt%04d.qst" % id
	if not _events.has(id):
		return _fail("文本资源未登记：%s（不是 Unicode 待转换）" % key)
	var doc: Variant = _events[id]
	if doc is String:
		doc = text(doc)
	if doc == null:
		return null
	if doc.get("schema") != "battlemonster.qst.v1" or \
			not doc.get("records") is Array or doc.records.is_empty():
		return _fail("QST runtime 契约不兼容：%s" % key)
	for record: Variant in doc.records:
		if not record is Dictionary or not _integer(record.get("opcode")) or \
				not record.get("params") is Array or record.params.size() != 5:
			return _fail("QST runtime 契约不兼容：%s" % key)
		for value: Variant in record.params:
			if not _integer(value) or value < -32768 or value > 32767:
				return _fail("QST runtime 契约不兼容：%s" % key)
	return doc


func quest_label(id: Variant) -> Variant:
	last_error = ""
	if id == null:
		return "未设置事件提示（不是任务完成状态）"
	if not _integer(id):
		return _fail("事件提示编号必须是整数")
	var doc: Variant = text("evt/evtlist.fxt")
	if doc == null:
		return null
	if not doc.get("records") is Array:
		return _fail("事件提示契约不兼容：evt/evtlist.fxt")
	for record: Variant in doc.records:
		if record is Dictionary and record.get("index") == id:
			if not record.has("text") or not (record.text == null or record.text is String):
				return _fail("事件提示契约不兼容：evt/evtlist.fxt")
			return record.text if record.text != null else \
				"【原文待 Unicode 转换：evt/evtlist.fxt #%d】" % int(id)
	return _fail("事件提示记录不存在：evt/evtlist.fxt #%d" % int(id))


func _valid_map_name(info: Dictionary) -> bool:
	return info.get("schema") == "battlemonster.mif.runtime" and info.get("schema_version") == 1 and \
		info.has("name_text") and (info.name_text == null or info.name_text is String) and \
		info.get("name_text_status") is String


## 通行格由地图 Scene 的根节点元数据提供（`resource_catalog.load_map_terrain`），
## 每格保留原生原始字节，低 3 位是通行掩码。
func _valid_terrain(terrain: Variant) -> bool:
	if not terrain is Dictionary or not _integer(terrain.get("width_tiles")) or \
			not _integer(terrain.get("height_tiles")) or terrain.width_tiles <= 0 or \
			terrain.height_tiles <= 0:
		return false
	return _valid_grid(terrain.get("cell_flags"), int(terrain.width_tiles),
		int(terrain.height_tiles))


func _valid_grid(grid: Variant, width: int, height: int) -> bool:
	if not grid is Array or grid.size() != height:
		return false
	for row: Variant in grid:
		if not row is Array or row.size() != width:
			return false
		for value: Variant in row:
			if not _integer(value):
				return false
	return true


func _integer(value: Variant) -> bool:
	# Converted numeric payloads may be integral floats in the native .tres.
	return value is int or (value is float and is_finite(value) and value == floor(value))


func _begin_load() -> bool:
	last_error = ""
	if not is_instance_valid(_assets):
		_fail("世界资源尚未初始化")
		return false
	return true


func _fail(message: String) -> Variant:
	last_error = message
	return null
