extends Node
## 资源目录（autoload AssetCatalog）：图片、音频、玩法数据与统一文本的唯一入口。
## 启动时注册 zh_CN 翻译资源，退出时移除。

const GameplayData = preload("res://core/gameplay_data/gameplay_data.gd")
const WorldMapData = preload("res://menu/world_map_data/world_map_data.gd")
const SpriteOrigins = preload("res://core/sprite_origins/sprite_origins.gd")
const TextTables = preload("res://core/text_tables/text_tables.gd")
## 文本表按来源前缀拆到各功能目录：只有第一次查某个来源时才加载对应文件。
const TEXT_TABLE_FILES := {
	"evt": "res://field/quest_detail/event_text.tres",
	"npc": "res://field/dialogue_window/npc.tres",
	"qst": "res://field/quest_detail/qst.tres",
	"common": "res://core/message_stack/common.tres",
}
const TEXT_TABLE_FALLBACK := "res://core/monster_animation/creature_names.tres"
const TextSources = preload("res://core/resource_catalog/text_sources.gd")
const TEXT_SOURCES: Dictionary = TextSources.IDS
const SPRITE_ORIGINS: SpriteOrigins = preload("res://core/monster_animation/sprite-origins.tres")
## 玩法数值按功能拆成六份，各自放在使用它的功能目录；这里只在首次访问时拼回一个门面对象。
## 逐对象存放的表：每个对象一个 `<对象名>.tres`，放在它自己的场景目录里。
const GAMEPLAY_OBJECT_DIRS := {
	"monsters": "res://monsters",
	"npcs": "res://actors",
}

const GAMEPLAY_PARTS := {
	"passives": "res://battle/passives/passives.tres",
	"items": "res://menu/items/items.tres",
	"encounters": "res://field/field_runtime/encounters.tres",
	"script_battles": "res://battle/combat/script_battles.tres",
}
const WORLD_MAP_DATA: WorldMapData = preload("res://menu/world_map/world-map.tres")
const ASSET_ROOT := "res://assets/"
const SPRITE_ROOT := ASSET_ROOT + "sprite/"
## 精灵帧索引：图集合并后，`对象/frame-NNN` → [图集路径, 帧矩形]。
const SpriteIndex = preload("res://core/sprite_index/sprite_index.gd")
const SPRITE_FRAMES: Dictionary = SpriteIndex.FRAMES
const AUDIO_ROOT := "res://audio/"
const AUDIO_OGG_ROOT := "ogg/"
## 记录号是整数的文本源：翻译键的后半段必须是规范整数。
const INTEGER_ID_SUFFIXES := [".fxt", ".nm"]
## 只存在于翻译资源、没有结构文件的正文源（NPC 名字由 `gameplay.tres` 的 NpcDefinition 索引）。
const EXTERNAL_TEXT_SOURCES := ["npc"]
const TEXT_TRANSLATION: Translation = preload("res://core/message_stack/zh_CN.tres")
## 地图实体节点放在格子中心，position / 16 还原成格子坐标。
const CELL := 16.0
## 地图 Scene 目录：`m<地图id>.tscn`，地形在 `terrain/t<组>_<号>.tscn`。
const MAP_SCENE_DIR := "res://maps"

var _origins: Dictionary = {}
var _text_tables: Dictionary = {}
var _audio_ids: Dictionary = {}
var _gameplay_data: GameplayData
var _data_cache: Dictionary = {}
var _sprite_cache: Dictionary = {}
var _stream_cache: Dictionary = {}
var _startup_errors: Array[String] = []
var _text_messages: Dictionary = {}
var _text_ids: Dictionary = {}


## 资源路径全部由标识按约定推出，不再维护生成式清单：
## 精灵 `assets/sprite/<id>.webp`、精灵原点 `assets/sprite-origins.tres`、
## 动画全部是 `scenes/monsters`、`scenes/actors`、`scenes/ani` 下的动画 Scene、
## 文本按来源前缀拆在 `field/text`、`ui/text`、`monsters/text`（颜色与换行随正文保存在翻译资源里）、
## 玩法 `core/gameplay.tres`（typed `GameplayData`）、平台图标 `main/platform-images/<path>`、
## 音频按编号扫 `audio/ogg`。
func _ready() -> void:
	_load_origins()
	for key: String in TEXT_TRANSLATION.get_message_list():
		var parts := key.split(":", true, 1)
		if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
			_report_error("Translation key must be source:record_id: %s" % key)
			return
		# 这里不能用 has_text()：_text_ids 正在本循环里逐条构建。
		var kind_ok := _has_text_payload(parts[0]) or \
			EXTERNAL_TEXT_SOURCES.has(parts[0]) or parts[0].begins_with("map/")
		if not kind_ok:
			_report_error("Translation key references an unregistered text source: %s" % key)
			return
		var numeric := EXTERNAL_TEXT_SOURCES.has(parts[0])
		for suffix: String in INTEGER_ID_SUFFIXES:
			numeric = numeric or parts[0].ends_with(suffix)
		if numeric and (not parts[1].is_valid_int() or parts[1] != str(int(parts[1]))):
			_report_error("Translation record requires an integer ID: %s" % key)
			return
		var record_id: Variant = int(parts[1]) if numeric else parts[1]
		if not _text_ids.has(parts[0]):
			_text_ids[parts[0]] = []
		if _text_ids[parts[0]].has(record_id):
			_report_error("Translation record ID is duplicated: %s" % key)
			return
		_text_ids[parts[0]].append(record_id)
	TranslationServer.add_translation(TEXT_TRANSLATION)


func _exit_tree() -> void:
	TranslationServer.remove_translation(TEXT_TRANSLATION)


func text_messages(source_id: String) -> Dictionary:
	if _text_messages.has(source_id):
		return _text_messages[source_id]
	if not _text_ids.has(source_id):
		_report_error("Native text table is unavailable: %s" % source_id)
		return {}
	var messages := {}
	for record_id: Variant in _text_ids[source_id]:
		messages[record_id] = String(TEXT_TRANSLATION.get_message("%s:%s" % [source_id, record_id]))
	messages.make_read_only()
	_text_messages[source_id] = messages
	return messages


func text_message(source_id: String, record_id: Variant) -> String:
	var messages := text_messages(source_id)
	if not messages.has(record_id):
		_report_error("Native text record is unavailable: %s:%s" % [source_id, record_id])
		return "【文本 %s:%s 不可用】" % [source_id, record_id]
	if messages[record_id].is_empty():
		return ""
	return TranslationServer.translate("%s:%s" % [source_id, record_id])


## 精灵是否存在：标识就是 `assets/sprite` 下的相对路径去掉 `.webp`。
func sprite_exists(sprite_id: String) -> bool:
	if not _is_safe_relative_path(sprite_id):
		return false
	if SPRITE_FRAMES.has(sprite_id):
		return true
	return ResourceLoader.exists(SPRITE_ROOT + sprite_id + ".webp")


## 文本源是否存在：有结构 payload，或者翻译资源里有它的记录。
func has_text(source_id: String) -> bool:
	return _is_safe_source_id(source_id) and \
		(_has_text_payload(source_id) or _text_ids.has(source_id))


## 已登记的全部正文源标识（来自翻译资源）。
func text_sources() -> Array[String]:
	var result: Array[String] = []
	for source: Variant in _text_ids.keys():
		result.append(str(source))
	result.sort()
	return result


## 精灵原点（原 sprite manifest 的 xOffset／yOffset）；未登记表示 (0, 0)。
func sprite_origin(sprite_id: String) -> Vector2i:
	var origin: Variant = _origins.get(sprite_id)
	return origin if origin is Vector2i else Vector2i.ZERO


func _load_origins() -> void:
	_origins = SPRITE_ORIGINS.origins


func load_sprite(sprite_id: String) -> Texture2D:
	if _sprite_cache.has(sprite_id):
		return _sprite_cache[sprite_id]
	if not _is_safe_relative_path(sprite_id):
		_report_error("Unsafe sprite identity: %s" % sprite_id)
		return null
	var path: String = SPRITE_ROOT + sprite_id + ".webp"
	var texture: Variant
	if SPRITE_FRAMES.has(sprite_id):
		# 图集合并后，一帧就是图集上的一个矩形：按索引取图集再切区域。
		var entry: Array = SPRITE_FRAMES[sprite_id]
		var sheet: Variant = load(entry[0])
		if not sheet is Texture2D:
			_report_error("Sprite sheet could not be loaded: %s" % entry[0])
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = entry[1]
		texture = atlas
	else:
		if not ResourceLoader.exists(path):
			_report_error("Sprite frame missing: %s" % sprite_id)
			return null
		texture = load(path)
	if not texture is Texture2D:
		_report_error("Sprite source texture could not be loaded: %s" % path)
		return null
	_sprite_cache[sprite_id] = texture
	return texture


## 道具图标：原生记录里的 `icon` 字段就是 `common/ui_item` 的帧号，没有单独的图标表。
## `icon_id < 0` 表示该道具没有图标，返回 null。
func item_icon(icon_id: int) -> Texture2D:
	return load_sprite("common/ui_item/frame-%03d" % icon_id) if icon_id >= 0 else null


func load_map(map_id: int) -> Variant:
	var path := "res://maps/m%d/m%d.tscn" % [map_id, map_id]
	if not ResourceLoader.exists(path):
		_report_error("Map scene is not registered: %d" % map_id)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_report_error("Map scene could not be loaded: %s" % path)
		return null
	var state := packed.get_state()
	if state.get_node_count() == 0:
		_report_error("Map scene has no root node: %s" % path)
		return null
	var root := _state_metadata(state, 0)
	if not root.get("map_id") is int or int(root.map_id) != map_id or \
			not root.get("map_group") is int or not root.get("map_index") is int:
		_report_error("Map scene identity metadata is missing: %s" % path)
		return null
	var info := {
		"schema": "battlemonster.mif.runtime",
		"schema_version": 1,
		"map_group": int(root.map_group),
		"map_index": int(root.map_index),
		"name_text": null,
		"name_text_status": "unmapped",
		"palette_indices": _ints_from(root.get("map_palette_indices", PackedInt32Array())),
		"map_objects": _objects_from(root.get("map_objects", PackedInt32Array())),
		"npcs": [],
		"warps": [],
		"monster_spawns": [],
	}
	for node in range(state.get_node_count()):
		var meta := _state_metadata(state, node)
		if meta.has("map_warp"):
			info.warps.append(_warp_from(meta, _state_tile(state, node)))
		elif meta.has("map_npc"):
			info.npcs.append(_npc_from(meta, _state_tile(state, node)))
		elif meta.has("map_spawn"):
			info.monster_spawns.append(_tile_dict(_state_tile(state, node)))
	var terrain_packed: Variant = _terrain_packed(map_id)
	if terrain_packed == null:
		return null
	var terrain_state := (terrain_packed as PackedScene).get_state()
	var sheets: Array = _sheets_from_state(terrain_state)
	if sheets.is_empty():
		_report_error("Map terrain has no bound tile set sources: %s" % path)
		return null
	var terrain: Variant = _grid_from_state(terrain_state)
	if terrain == null:
		_report_error("Map passage grid is inconsistent: %s" % path)
		return null
	return {
		"id": map_id,
		"info": info,
		"layout": terrain,
		"images": sheets,
	}


## 地图 Scene 里实例化的地形子场景；不实例化地图本身。
func _terrain_packed(map_id: int) -> Variant:
	var path := "res://maps/m%d/m%d.tscn" % [map_id, map_id]
	if not ResourceLoader.exists(path):
		_report_error("Map scene is missing: %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_report_error("Map scene could not be loaded: %s" % path)
		return null
	var state := packed.get_state()
	for node in range(state.get_node_count()):
		var instance: Variant = state.get_node_instance(node)
		if instance is PackedScene:
			return instance
	_report_error("Map scene has no terrain instance: %s" % path)
	return null


## 图集／调色板绑定从地形场景的 TileSet atlas source 派生：
## 每个 source 携带 `sprite_id` 与 `palette_index` 元数据，渲染用的也是这份 TileSet，
## 因此不再需要单独的资源清单。
func _sheets_from_state(terrain_state: SceneState) -> Array:
	for node in range(terrain_state.get_node_count()):
		for property in range(terrain_state.get_node_property_count(node)):
			if terrain_state.get_node_property_name(node, property) != &"tile_set":
				continue
			var tile_set: Variant = terrain_state.get_node_property_value(node, property)
			if not tile_set is TileSet:
				continue
			return _sheets_of(tile_set)
	return []


func _sheets_of(tile_set: TileSet) -> Array:
	var result: Array = []
	for index in tile_set.get_source_count():
		var slot := tile_set.get_source_id(index)
		var source := tile_set.get_source(slot) as TileSetAtlasSource
		if source == null:
			continue
		result.append({
			"slot": slot,
			"status": "resolved" if source.texture != null else "unbound",
			"sprite_id": String(source.get_meta("sprite_id", "")),
			"palette_index": int(source.get_meta("palette_index", 0)),
		})
	return result


## 地图 Scene 里 `metadata/*` 形式的属性集合；用于按语义标记识别交互实体节点。
func _state_metadata(state: SceneState, node: int) -> Dictionary:
	var result := {}
	for property in range(state.get_node_property_count(node)):
		var name := state.get_node_property_name(node, property)
		if name.begins_with("metadata/"):
			result[String(name).trim_prefix("metadata/")] = state.get_node_property_value(node, property)
	return result


## 实体节点放在格子中心，回到格子坐标用 position / 16 向下取整。
func _state_tile(state: SceneState, node: int) -> Vector2i:
	for property in range(state.get_node_property_count(node)):
		if state.get_node_property_name(node, property) == &"position":
			var position: Variant = state.get_node_property_value(node, property)
			if position is Vector2:
				return Vector2i(floori(position.x / float(CELL)), floori(position.y / float(CELL)))
	return Vector2i.ZERO


func _tile_dict(tile: Vector2i) -> Dictionary:
	return {"tile_x": tile.x, "tile_y": tile.y}


func _warp_from(meta: Dictionary, tile: Vector2i) -> Dictionary:
	var record: Variant = meta.map_warp
	var result := _tile_dict(tile)
	result["destination_map_id"] = int(record.get("target_map_id", 0))
	var target: Variant = record.get("target_tile", Vector2i.ZERO)
	result["destination_tile_x"] = int(target.x)
	result["destination_tile_y"] = int(target.y)
	return result


## 对白源由地图节点自己声明（`metadata/npc_dialogue` = 原生 CHT 源标识，如 `npc/npc0027.cht`）；
## 没有声明时留空，由 `field_runtime.interact_npc()` 显式报错，这里不猜编号。
func _npc_from(meta: Dictionary, tile: Vector2i) -> Dictionary:
	var record: Variant = meta.map_npc
	var result := _tile_dict(tile)
	result["resource_id"] = int(record.get("resource_id", 0))
	result["direction_code"] = int(record.get("direction_code", 0))
	result["npc_dialogue"] = str(meta.get("npc_dialogue", ""))
	return result


func _ints_from(values: Variant) -> Array:
	var result: Array = []
	if values is PackedInt32Array:
		for value in values:
			result.append(int(value))
	return result


func _objects_from(values: Variant) -> Array:
	var result: Array = []
	if values is PackedInt32Array:
		for index in range(0, values.size() - 2, 3):
			result.append({"frame_id": values[index], "tile_x": values[index + 1],
				"tile_y": values[index + 2]})
	return result


## 从地形子场景根节点元数据还原每格通行标志，地形场景是唯一来源。
## `metadata/map_cell_flags` 按行优先保存每格原始字节；低 3 位是原生通行掩码（非 0 不可走），
## bit3-5 是原生可见性标志。不实例化地图，直接读 PackedScene 属性表与子场景引用。
func load_map_terrain(map_id: int) -> Variant:
	var terrain: Variant = _terrain_packed(map_id)
	if terrain == null:
		return null
	return _grid_from_state((terrain as PackedScene).get_state())


func _grid_from_state(terrain_state: SceneState) -> Variant:
	if terrain_state.get_node_count() == 0:
		return null
	var size: Variant = null
	var bytes: Variant = null
	for property in range(terrain_state.get_node_property_count(0)):
		match terrain_state.get_node_property_name(0, property):
			&"metadata/map_size_tiles":
				size = terrain_state.get_node_property_value(0, property)
			&"metadata/map_cell_flags":
				bytes = terrain_state.get_node_property_value(0, property)
	if not size is Vector2i or not bytes is PackedByteArray:
		return null
	var width: int = size.x
	var height: int = size.y
	if width <= 0 or height <= 0 or bytes.size() != width * height:
		return null
	var grid: Array = []
	grid.resize(height)
	for y in height:
		var row: Array = []
		row.resize(width)
		for x in width:
			row[x] = bytes[y * width + x]
		grid[y] = row
	return {"width_tiles": width, "height_tiles": height, "cell_flags": grid}



## 递归扫描目录树，收集同类对象（按 `id` 排序）。用于"一对象一 tres、放在各自场景目录"的表。
func _scan_object_tree(dir_path: String, collector: Array = []) -> Array:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return collector
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var record: Variant = load(dir_path.path_join(file_name))
		if record != null and record.get("id") != null:
			collector.append(record)
	for sub: String in dir.get_directories():
		_scan_object_tree(dir_path.path_join(sub), collector)
	collector.sort_custom(func(a: Object, b: Object) -> bool: return a.get("id") < b.get("id"))
	return collector


func load_gameplay_catalog() -> GameplayData:
	if _gameplay_data == null:
		var data := GameplayData.new()
		for key: String in GAMEPLAY_OBJECT_DIRS:
			var records := _scan_object_tree(GAMEPLAY_OBJECT_DIRS[key])
			if records.is_empty():
				_report_error("Gameplay object tree is empty: %s" % GAMEPLAY_OBJECT_DIRS[key])
				return null
			var target: Array = data.get(key)
			for record: Variant in records:
				target.append(record)
		for key: String in GAMEPLAY_PARTS:
			var path: String = GAMEPLAY_PARTS[key]
			var part: Variant = load(path)
			if part == null:
				_report_error("Gameplay table could not be loaded: %s" % path)
				return null
			data.set(key, (part.get(key) as Array).duplicate(true))
		_gameplay_data = data
	return _gameplay_data


## 世界地图节点表（`map/mini.mmi` 导出）；只读共享，不做拷贝。
func load_world_map() -> WorldMapData:
	if WORLD_MAP_DATA.count() <= 0:
		_report_error("World map table is empty: %s" % WORLD_MAP_DATA.resource_path)
		return null
	return WORLD_MAP_DATA


func load_text(source_id: String) -> Variant:
	if not _is_safe_source_id(source_id):
		_report_error("Unsafe text source: %s" % source_id)
		return null
	var cache_key := "text/%s" % source_id
	if _data_cache.has(cache_key):
		return _data_cache[cache_key]
	var source: Variant = _text_payload(source_id)
	if not source is Dictionary:
		_report_error("Text source is not registered: %s" % source_id)
		return null
	if source.get("format") == "qst":
		return source
	var localized: Dictionary = source.duplicate(true)
	match localized.get("format", localized.get("schema", "")):
		"battlemonster.fxt", "battlemonster.dat.item-text":
			for record: Dictionary in localized.records:
				if record.text is String:
					record.text = text_message(source_id,
						int(record.index) if localized.get("format") == "battlemonster.fxt" else record.id)
		"cht":
			for group_index in range(localized.groups.size()):
				var records: Array = localized.groups[group_index].records
				for index in range(records.size()):
					if records[index].text is String:
						records[index].text = text_message(source_id, "%d/%d" % [group_index, index])
		"battlemonster.mif.runtime":
			localized.name_text = text_message(source_id, "name")
		_:
			_data_cache.erase(cache_key)
			_report_error("Native text format is unsupported: %s" % source_id)
			return null
	_data_cache[cache_key] = localized
	return localized


## 文本资源本体：结构在 `assets/text-tables.tres` 的总表里。
func _text_table(prefix: String) -> Variant:
	if _text_tables.has(prefix):
		return _text_tables[prefix]
	var path: String = TEXT_TABLE_FILES.get(prefix, TEXT_TABLE_FALLBACK)
	var table: Variant = load(path)
	if table == null:
		_report_error("Text table could not be loaded: %s" % path)
	_text_tables[prefix] = table
	return table


func _text_payload(source_id: String) -> Variant:
	var table: Variant = _text_table(source_id.get_slice("/", 0))
	if table == null:
		return null
	return table.payloads.get(source_id)


func _has_text_payload(source_id: String) -> bool:
	# 启动期只查来源清单，不加载正文表；正文在第一次取用时才载入。
	return TEXT_SOURCES.has(source_id)


## 窗框图集拆分后的帧入口：按原生帧号取图，不再经过 `common/ui_window` 图集。
const WindowFrames = preload("res://core/window_frame/window_frames.gd")
var _window_frame_cache: Dictionary = {}


func load_window_frame(index: int) -> Texture2D:
	if _window_frame_cache.has(index):
		return _window_frame_cache[index]
	var path: String = WindowFrames.FRAMES.get(index, "")
	if path.is_empty():
		_report_error("Window frame is not registered: %d" % index)
		return null
	var texture: Variant = load(path)
	if not texture is Texture2D:
		_report_error("Window frame could not be loaded: %s" % path)
		return null
	_window_frame_cache[index] = texture
	return texture


func load_platform_image(relative_path: String) -> Texture2D:
	if not relative_path.ends_with(".webp") or not _is_safe_relative_path(relative_path):
		_report_error("Platform image is not registered: %s" % relative_path)
		return null
	var path: String = "res://prime/platform-images/".path_join(relative_path)
	if not ResourceLoader.exists(path):
		_report_error("Platform image is not registered: %s" % relative_path)
		return null
	var texture: Variant = load(path)
	if not texture is Texture2D:
		_report_error("Platform image could not be loaded: %s" % path)
		return null
	return texture


func load_audio(resource_id: int) -> AudioStream:
	var key := str(resource_id)
	if _stream_cache.has(key):
		return _stream_cache[key]
	var files := _audio_table()
	var relative_path: Variant = files.get(key)
	if not relative_path is String:
		_report_error("Audio resource is not registered: %d" % resource_id)
		return null
	var path: String = AUDIO_ROOT + relative_path
	var stream: Variant = load(path)
	if not stream is AudioStream:
		_report_error("Audio stream could not be loaded: %s" % path)
		return null
	_stream_cache[key] = stream
	return stream


## 音频编号 → 文件：原生编号 101..151 依次对应 `ogg/NN_<名字>.ogg`（NN = 编号 - 100），
## 152 是 `ogg/Logo.ogg`；名字本身只在文件名里，所以按目录扫描建立一次。
func _audio_table() -> Dictionary:
	if not _audio_ids.is_empty():
		return _audio_ids
	var directory := DirAccess.open(AUDIO_ROOT + AUDIO_OGG_ROOT)
	if directory == null:
		_report_error("Audio directory is missing: %s%s" % [AUDIO_ROOT, AUDIO_OGG_ROOT])
		return _audio_ids
	for name: String in directory.get_files():
		if not name.ends_with(".ogg"):
			continue
		if name == "Logo.ogg":
			_audio_ids["152"] = AUDIO_OGG_ROOT + name
			continue
		var prefix := name.substr(0, 2)
		if not prefix.is_valid_int():
			continue
		_audio_ids[str(100 + prefix.to_int())] = AUDIO_OGG_ROOT + name
	return _audio_ids


func release_audio(resource_id: int) -> void:
	_stream_cache.erase(str(resource_id))


func get_resource_summary() -> Dictionary:
	return {
		"sprites": _sprite_file_count(),
		"sprite_origins": _origins.size(),
		"map_scenes": _map_scene_count(),
		"text_tables": _text_ids.size(),
		"text_messages": TEXT_TRANSLATION.get_message_count(),
	}


func get_startup_errors() -> Array[String]:
	return _startup_errors.duplicate()


func _map_scene_count() -> int:
	var directory := DirAccess.open(MAP_SCENE_DIR)
	if directory == null:
		return 0
	var count := 0
	for name: String in directory.get_files():
		if name.begins_with("m") and name.ends_with(".tscn"):
			count += 1
	return count


func _sprite_file_count() -> int:
	var directory := DirAccess.open(SPRITE_ROOT)
	if directory == null:
		return 0
	var count := 0
	for group: String in directory.get_directories():
		count += _count_webp(SPRITE_ROOT.path_join(group))
	return count


func _count_webp(directory: String) -> int:
	var access := DirAccess.open(directory)
	if access == null:
		return 0
	var count := 0
	for child: String in access.get_directories():
		count += _count_webp(directory.path_join(child))
	for name: String in access.get_files():
		if name.ends_with(".webp"):
			count += 1
	return count


func _is_safe_source_id(value: String) -> bool:
	if value.is_empty() or value.begins_with("/") or value.contains("\\") or value.contains(":"):
		return false
	for part: String in value.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


func _is_safe_relative_path(value: String) -> bool:
	return _is_safe_source_id(value)


func _report_error(message: String) -> void:
	_startup_errors.append(message)
	push_error(message)
