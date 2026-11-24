extends Node2D

## Scene animation view for actors and MIF objects, sharing native foot ordering.
## Actor dictionaries are retained by reference (including finite emotion state).
## ANI layers support native multiply/screen/lighten; other modes remain reported.
## Optionally set_visible_world_rect(camera_bounds) to freeze offscreen emotions.

const HERO := "hero/h_f_01"
const ACTOR_SCENE = preload("res://game/field/actors/actor/actor.tscn")
# 地图物件只需要绘制体，不需要 actor 场景里的 Emotion（它内部还会再实例化一套 ANI）。
const LAYERS_SCENE = preload("res://game/field/actors/actor_layers/actor_layers.tscn")
## MIF 物件 `frame_id` 里不走 `% 100` 取图的那几个码：传送门由 `Map_portalCREATE` 单独处理。
const PORTAL_FRAME_IDS := [164, 165]
## 物件绘制锚点按尺寸分档（原生 `Map_objCREATE`）：16×8 与 12×5 两组，其余 8×8。
const WIDE_FRAME_IDS := [152, 153, 154, 155]
## 宝箱物件的两帧：`Map_objCREATE` 按 `Map_boxIsExist(map_id)` 选 176（未开）／177（已开），
## `Field_Basic_mKeyPressed` 的 `Object_objHIT` 命中 176 后调 `Object_objANI(obj, 177)`。
const CHEST_FRAME_CLOSED := 176
const CHEST_FRAME_OPEN := 177
const CHEST_FRAME_IDS := [CHEST_FRAME_CLOSED, CHEST_FRAME_OPEN]
## 公共物件图组的选择器（`obj_f_99`）：动作码 <=99 用本图组对应的 `obj_f_01..07`，其余统一走它。
const COMMON_OBJECT_SELECTOR := 99
## 本图组映射到 `obj_f_01..07` 的有效选择器（其余回落到 `obj_f_00`）。
const GROUP_OBJECT_SELECTORS := [1, 2, 3, 4, 7, COMMON_OBJECT_SELECTOR]
## 公共帧 156–163（`obj_f_99`）的原生绘制序为 -1，其余物件为 0。
const COMMON_BACK_FRAME_FIRST := 156
const COMMON_BACK_FRAME_LAST := 163
## 英雄 `action` → 待机／走跑基帧（原生 `Field_Hero_procAction`）：基帧后两帧是「朝上」「朝侧」
## 变体，朝下直接用基帧本身。action 1／6 都是走路，10／11 是剧情用动作。
const HERO_ACTION_BASES := {0: 0, 1: 3, 6: 3, 2: 6, 3: 9, 4: 12, 10: 25, 11: 24}

var _catalog: Object
var _actors: Dictionary = {}
var _map_objects: Array[Dictionary] = []
var _limits: Array[String] = []
var _visible_world_rect: Variant = null
var _dialogue_speaker := -1


func configure(catalog: Object) -> void:
	clear()
	_catalog = catalog


## 按 MIF 的 map_objects 建立动态绘制体（树冠、石柱、建筑、公共装饰等）。
## `extras` 是 opcode 26 增删的事件物件（原生 event_map_object 表），按同一套规则绘制。
## `map_state` 给两处需要存档状态的帧：`warps` 是原生 `warpEnabled`（目标地图号 → 是否开放，
## `Map_warpIsEnableTile` 查的就是它），`boxes` 是已开宝箱的地图号。
## 只建绘制体本身：地图物件不会说话，因此不实例化 actor 场景里的 Emotion。
func set_map_objects(info: Dictionary, extras: Array = [], map_state: Dictionary = {}) -> bool:
	_clear_map_objects()
	var records: Array = info.map_objects.duplicate()
	records.append_array(extras)
	for index in records.size():
		var record: Dictionary = records[index]
		var body := _create_map_object(index, record, info, map_state)
		if body.is_empty():
			return false
		_map_objects.append(body)
	_sort_feet()
	return true


func _create_map_object(index: int, record: Dictionary, info: Dictionary,
		map_state: Dictionary) -> Dictionary:
	var action := _frame_for(record, info, map_state)
	var selector := int(info.map_group) + 1 if action <= COMMON_OBJECT_SELECTOR \
		else COMMON_OBJECT_SELECTOR
	var path := "obj/obj_f_%02d" % (selector if selector in GROUP_OBJECT_SELECTORS else 0)
	var group := Node2D.new()
	group.name = "MapObject_%d" % index
	# 与 actor.tscn 根节点保持一致的原生绘制层级。
	group.z_index = 30
	var body: Node2D = LAYERS_SCENE.instantiate()
	body.name = "Body"
	group.add_child(body)
	add_child(group)
	var anchor := Vector2(8, 8)
	if int(record.frame_id) in WIDE_FRAME_IDS:
		anchor = Vector2(16, 8)
	elif int(record.frame_id) in CHEST_FRAME_IDS:
		anchor = Vector2(12, 5)
	group.position = Vector2(record.tile_x, record.tile_y) * 16 + anchor
	# 公共帧 156–163 的原生 order 为 -1，其余物件为 0。
	var order := -1 if selector == COMMON_OBJECT_SELECTOR and \
		action >= COMMON_BACK_FRAME_FIRST and action <= COMMON_BACK_FRAME_LAST else 0
	group.set_meta("draw_order_key", order)
	group.set_meta("map_object_index", index)
	# Object_objPOS keeps the drawing offset separate from the sorting foot.
	body.position = -anchor
	var drawing: Dictionary = body.present(
		{"path": path, "action": action % 100, "direction": 0}, true, _limit)
	if drawing.is_empty():
		push_error("Cannot draw map object %d: %s action %d." % [index, path, action % 100])
		remove_child(group)
		group.free()
		_clear_map_objects()
		return {}
	return {"group": group, "body_node": body, "body": drawing, "record": record,
		"action": action, "path": path}


## 该格上的地图物件当前的动作号（`Object_objHIT` 命中后看 `animation_id`），没有就返回 −1。
func object_action_at(tile: Vector2i) -> int:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) == tile.x and int(record.tile_y) == tile.y:
			return int(view.action)
	return -1


## 原生 `Field_Basic_mKeyPressed` 的 `case 166: Object_objANI(obj, 167)`：只把这一格的物件
## 换成另一帧，没有存档、没有掉落。绘制沿用建对象时算好的 `obj/obj_f_XX` 资源。
func switch_object_at(tile: Vector2i, from_action: int, to_action: int) -> bool:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) != tile.x or int(record.tile_y) != tile.y or \
				int(view.action) != from_action:
			continue
		var drawing: Dictionary = view.body_node.present(
			{"path": str(view.get("path", "obj/obj_f_00")), "action": int(to_action) % 100,
				"direction": 0}, true, _limit)
		if drawing.is_empty():
			return false
		view["action"] = to_action
		view["body"] = drawing
		return true
	return false


## 物件真正播放的帧号：
## - 164／165 传送门：`Map_portalCREATE` 按 `Map_warpIsEnableTile(格)` 选 164（开放）／165。
##   本工程的地图 Scene 只有 warp 的目标地图号，而原生那一位也是按目标地图号索引的
##   （`Map_warpIsEnable` 的 id 就是 warp 记录的 +2 uint16），所以用 `warps` 的开关。
## - 176／177 宝箱：`Map_objCREATE` 按 `Map_boxIsExist(MapData.map_id)` 选 176（未开）／177。
func _frame_for(record: Dictionary, info: Dictionary, map_state: Dictionary) -> int:
	var frame := int(record.frame_id)
	if frame in PORTAL_FRAME_IDS:
		return 164 if _portal_enabled(record, info, map_state) else 165
	if frame in CHEST_FRAME_IDS:
		var boxes: Variant = map_state.get("boxes", [])
		var opened: bool = boxes is Array and boxes.has(int(map_state.get("map_id", -1)))
		return CHEST_FRAME_OPEN if opened else CHEST_FRAME_CLOSED
	return frame


func _portal_enabled(record: Dictionary, info: Dictionary, map_state: Dictionary) -> bool:
	var warps: Dictionary = map_state.get("warps", {})
	for warp: Dictionary in info.get("warps", []):
		if int(warp.tile_x) != int(record.tile_x) or int(warp.tile_y) != int(record.tile_y):
			continue
		return bool(warps.get(str(int(warp.destination_map_id)), false))
	return false


func _clear_map_objects() -> void:
	for view: Dictionary in _map_objects:
		remove_child(view.group)
		view.group.free()
	_map_objects.clear()


## 宝箱交互（原生 `Field_Basic_mKeyPressed` 的 `Object_objHIT` 命中 `animation_id == 176`）：
## 该格上是否还有未开的宝箱。
func has_unopened_box(tile: Vector2i) -> bool:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) == tile.x and int(record.tile_y) == tile.y and \
				int(view.action) == CHEST_FRAME_CLOSED:
			return true
	return false


## 原生 `Object_objANI(obj, 177)`：宝箱换成打开的那一帧（`obj_f_99` 动作 77）。
func open_box_at(tile: Vector2i) -> bool:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) != tile.x or int(record.tile_y) != tile.y or \
				int(view.action) != CHEST_FRAME_CLOSED:
			continue
		var drawing: Dictionary = view.body_node.present(
			{"path": "obj/obj_f_99", "action": CHEST_FRAME_OPEN % 100, "direction": 0}, true, _limit)
		if drawing.is_empty():
			return false
		view["action"] = CHEST_FRAME_OPEN
		view["body"] = drawing
		return true
	return false


func get_limits() -> Array[String]:
	return _limits.duplicate()


func set_visible_world_rect(rect: Rect2) -> void:
	_visible_world_rect = rect


func clear_visible_world_rect() -> void:
	_visible_world_rect = null


func set_dialogue_speaker(portrait: int) -> void:
	if _dialogue_speaker == portrait:
		return
	_dialogue_speaker = portrait
	for view: Dictionary in _actors.values():
		_sync_emotion(view)


func _limit(message: String) -> void:
	if not _limits.has(message):
		_limits.append(message)


static func field_artwork(actor: Dictionary, bindings: Array = []) -> Dictionary:
	var id := int(actor.get("id", -1))
	var action := int(actor.get("action", 0))
	var direction := int(actor.get("direction", 32))
	var last_direction := int(actor.get("lastDirection", (direction & FieldAction.VERTICAL_MASK) if direction & FieldAction.VERTICAL_MASK else FieldAction.Facing.DOWN))
	if id == 0:
		var variant := 0 if last_direction == FieldAction.Facing.DOWN else 1 if last_direction == FieldAction.Facing.UP else 2
		var selected := action % 100
		if HERO_ACTION_BASES.has(action):
			selected = int(HERO_ACTION_BASES[action]) + (0 if action in [10, 11] else variant)
		return {"path": HERO, "action": selected, "direction": 1 if last_direction == 2 else 0}
	if id >= 1000:
		if actor.get("party_follower", false) or actor.has("wild"):
			action = 0 if last_direction == FieldAction.Facing.DOWN else 1 if last_direction == FieldAction.Facing.UP else 2
		return {"path": "mon1/m_f_%03d" % int(actor.get("species", id % 1000)),
			"action": action % 100, "direction": 1 if last_direction == 2 else 0}
	for binding: Dictionary in bindings:
		if int(binding.get("record_index", -1)) != id:
			continue
		var vertical := direction & FieldAction.VERTICAL_MASK
		var selected := action % 100
		if action == 0:
			selected = 1 if vertical == FieldAction.Facing.UP else 0
		elif action in [5, 6]:
			selected = 3 if vertical == FieldAction.Facing.UP else 2 if vertical == FieldAction.Facing.DOWN else selected
		return {"path": "npc/n_f_%02d" % int(binding["field_sprite_id"]),
			"action": selected, "fallback": 1 if vertical == FieldAction.Facing.UP else 0,
			"direction": (direction >> 1) & 1}
	return {}


## Object_drawBUFFER0/1 -> JC_fbmMirrorRotateINFO; pixel edges are integer/floored.
static func layer_rect(version: int, layer: Dictionary, image: Dictionary, direction: int) -> Dictionary:
	var mirror := int(layer.get("slot_flags", 0)) >> 6
	var flip := (int(image.get("sprite_flag", image.get("flag", 0))) ^ direction ^ mirror) & 3
	var x := int(layer.get("x", 0))
	var y := int(layer.get("y", 0))
	var origin_mirror: int
	var percent := 100
	var quarter_turn := 0
	if version == 0:
		if mirror & 1:
			x = ~x
		if mirror & 2:
			y = ~y
		origin_mirror = flip
	elif version == 1:
		var code := int(layer.get("transform", 1))
		quarter_turn = code >> 4
		if quarter_turn > 3 or (quarter_turn != 0 and (code & 15) > 1):
			return {}
		if quarter_turn != 0 and direction == 1:
			quarter_turn = 4 - quarter_turn
		if (code & 15) > 1:
			percent += 10 * ((code & 15) - 1)
		origin_mirror = direction
	else:
		return {}
	var iw := int(image["width"])
	var ih := int(image["height"])
	var offset_x := int(image.get("x_offset", image.get("xOffset", 0)))
	var offset_y := int(image.get("y_offset", image.get("yOffset", 0)))
	var ox := iw - offset_x if origin_mirror & 1 else offset_x
	var oy := ih - offset_y if origin_mirror & 2 else offset_y
	var width := floori(float(ih if quarter_turn & 1 else iw) * percent / 100.0)
	var height := floori(float(iw if quarter_turn & 1 else ih) * percent / 100.0)
	var ax := -x if direction == 0 else x
	return {"x": ax + ox - width if (percent > 100 or quarter_turn != 0) and direction == 1 else ax - ox,
		"y": -y - oy, "width": width, "height": height,
		"flipX": bool(flip & 1), "flipY": bool(flip & 2), "rotation": quarter_turn}


func sync(actors: Array, bindings: Array = []) -> void:
	if _catalog == null:
		_catalog = get_node_or_null("/root/AssetCatalog")
	if _catalog == null:
		_limit("AssetCatalog is unavailable.")
		return
	var retained: Dictionary = {}
	for actor: Dictionary in actors:
		var id := int(actor["id"])
		if retained.has(id):
			_limit("Duplicate field actor id: %d" % id)
			continue
		retained[id] = true
		if not _actors.has(id):
			var group := ACTOR_SCENE.instantiate() as Node2D
			group.name = "Actor_%d" % id
			add_child(group)
			var body: Node2D = group.get_node("Body")
			var emotion: Node2D = group.get_node("Emotion")
			if id >= 1000:
				emotion.use_monster_anchor()
			_actors[id] = {"group": group, "body_node": body, "emotion_node": emotion,
				"body": {}, "emotion": {}, "actor": actor}
			body.animation_finished.connect(_on_body_animation_finished.bind(id))
		var view: Dictionary = _actors[id]
		view["actor"] = actor
		var art := field_artwork(actor, bindings)
		var request := [art, actor.get("action", 0), actor.get("animationEndMode", 0)]
		if view.get("body_request") != request:
			var preserve_phase: bool = id == 0 and int(actor.get("action", 0)) in [1, 2] \
				and not view.body.is_empty() and int(view.body_request[1]) in [1, 2]
			view["body_request"] = request
			# 原生 `Object_procNEXT`：只有 `HOLD_LAST_FRAME` 停在末帧，
			# `CALLBACK_OR_RESTART`／`RESTART` 都重播（100..199 的剧情动作在 next 回调里同样重播）。
			view["body"] = view.body_node.present(art,
				int(actor.get("animationEndMode", 0)) != StoryRuntime.AnimationEndMode.HOLD_LAST_FRAME,
				_limit, preserve_phase)
			if art.is_empty():
				_limit("NPC %d has no confirmed artwork binding." % id)
		_sync_emotion(view)
		_update_position(actor)
	for id: int in _actors.keys():
		if not retained.has(id):
			remove(id)
	_sort_feet()


## 任一角色的动作播完（转发 `actor_layers.animation_finished`，附带角色号）。
signal animation_finished(actor_id: int)


func _on_body_animation_finished(actor_id: int) -> void:
	animation_finished.emit(actor_id)


func _sync_emotion(view: Dictionary) -> void:
	var actor: Dictionary = view["actor"]
	var actor_id := int(actor.id)
	var speaking := _dialogue_speaker >= 0 and actor_id < 1000 and \
		(1 if actor_id == 0 else actor_id) == maxi(1, _dialogue_speaker)
	view.emotion_node.present(actor, speaking, _limit)
	view.emotion = view.emotion_node.drawing()


## `quest_status` 这类由外部写进 actor 的字段变化后重画表情层（`present` 会跳过没变的请求）。
func refresh_emotions() -> void:
	for view: Dictionary in _actors.values():
		_sync_emotion(view)


func update_position(actor: Dictionary) -> void:
	_update_position(actor)
	_sort_feet()


func _update_position(actor: Dictionary) -> void:
	var view: Dictionary = _actors.get(int(actor["id"]), {})
	if view.is_empty():
		return
	view["group"].position = Vector2(float(actor["x"]) * 16 + 8, float(actor["y"]) * 16 + 8)


func _sort_feet() -> void:
	var views: Array = _actors.values()
	views.append_array(_map_objects)
	views.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_order := int(a.group.get_meta("draw_order_key", 0))
		var b_order := int(b.group.get_meta("draw_order_key", 0))
		if a_order != b_order:
			return a_order < b_order
		if a.group.position.y != b.group.position.y:
			return a.group.position.y < b.group.position.y
		if a.has("actor") != b.has("actor"):
			return not a.has("actor")
		if a.has("actor"):
			return int(a.actor.id) != 0 and int(b.actor.id) == 0
		return int(a.group.get_meta("map_object_index")) > int(b.group.get_meta("map_object_index")))
	for index in range(views.size()):
		move_child(views[index]["group"], index)


func set_monster_running(value: bool) -> void:
	for view: Dictionary in _actors.values():
		view.body_node.set_monster_running(value)


func advance_hero_motion(distance: float) -> void:
	var view: Dictionary = _actors[0]
	view.body_node.advance_motion(distance)
	view.body.frame = view.body_node.frame_index()


func advance(delta: float, animate_bodies: bool = true, animate_hero: bool = true) -> void:
	if not is_finite(delta) or delta < 0:
		return
	for view: Dictionary in _map_objects:
		if animate_bodies:
			view.body_node.advance(delta)
			view.body.frame = view.body_node.frame_index()
	for view: Dictionary in _actors.values():
		var actor: Dictionary = view["actor"]
		var body: Dictionary = view["body"]
		if animate_bodies and (animate_hero or int(actor.id) != 0) and not body.is_empty():
			view.body_node.advance(delta)
			body.frame = view.body_node.frame_index()
		var emotion: Dictionary = view["emotion"]
		if emotion.is_empty():
			continue
		if _visible_world_rect != null and not body.is_empty():
			var body_bounds: Rect2 = view["group"].get_global_transform() * body["bounds"]
			if not body_bounds.intersects(_visible_world_rect, true):
				continue
		view.emotion_node.advance(delta)
		_sync_emotion(view)


func clear_emotions() -> void:
	for view: Dictionary in _actors.values():
		var actor: Dictionary = view["actor"]
		if actor.get("emotion") != null:
			actor["emotion"] = null
			actor["emotionFrame"] = 0
			actor["emotionRepeats"] = 0
			actor["emotionRevision"] = int(actor.get("emotionRevision", 0)) + 1
		view["emotion"] = {}
		view.emotion_node.clear_layers()
		_sync_emotion(view)


func remove(actor_id: int) -> void:
	if not _actors.has(actor_id):
		return
	var group: Node2D = _actors[actor_id]["group"]
	_actors.erase(actor_id)
	remove_child(group)
	group.free()


func clear() -> void:
	_dialogue_speaker = -1
	_clear_map_objects()
	for id: int in _actors.keys():
		remove(id)


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in _actors:
		var view: Dictionary = _actors[id]
		result.append({"actor": id, "position": view["group"].position,
			"body": view["body"].duplicate(), "emotion": view["emotion"].duplicate(),
			"emotion_position": view["group"].position + view["emotion_node"].position,
			"order": view["group"].get_index()})
	return result

