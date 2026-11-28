extends Node2D

## Scene animation view for actors and MIF objects, sharing native foot ordering.
## Actor dictionaries are retained by reference (including finite emotion state).
## ANI layers support native multiply/screen/lighten; other modes remain reported.
## Optionally set_visible_world_rect(camera_bounds) to freeze offscreen emotions.

const HERO := "hero/h_f_01"
const TILE := 16.0
const ACTOR_SCENE = preload("res://game/field/actors/actor/actor.tscn")
# 地图物件只需要绘制体，不需要 actor 场景里的 Emotion（它内部还会再实例化一套 ANI）。
## 地图物件外壳：`Shake` 层承载 Scene 抖动动画，`Shake/Body` 仍是 `actor_layers` 绘制体。
const MAP_OBJECT_SCENE = preload("res://game/field/runtime/map_object/map_object.tscn")
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
## 原生 `Object_procDRAW:165-215` 的遮挡淡出：0 序物件中 `resource_id == 1`（第 0 组，
## 即 `obj/obj_f_01`）且当前动画码 ≤ 14 的树木，在被主角绘制之后又与主角的绘制矩形相交时
## 每帧 +1 档（上限 7），离开后每帧 −1 档；alpha = (256 − 12×档位) / 256。
## 档位存在物件自己的字节里，不写档。
const OCCLUSION_FADE_MAX_STEPS := 7
const OCCLUSION_FADE_ALPHA_STEP := 12
const OCCLUSION_FADE_ACTION_MAX := 14
const TREE_OBJECT_PATH := "obj/obj_f_01"
## 英雄 `action` → 待机／走跑基帧（原生 `Field_Hero_procAction`）：基帧后两帧是「朝上」「朝侧」
## 变体，朝下直接用基帧本身。action 1／6 都是走路，10／11 是剧情用动作。
const HERO_ACTION_BASES := {0: 0, 1: 3, 6: 3, 2: 6, 3: 9, 4: 12, 10: 25, 11: 24}
## 原生 ANI 每游戏帧（50ms）推一帧，转换时按 0.06 秒写场景；采集动作（hero ANI 9–14）
## 与物件受击反应用 0.06/0.05 = 1.2 倍播放，对齐原版速度。
const NATIVE_ANI_SPEED := 1.2
const GATHER_ANI_ACTIONS := [9, 10, 11, 12, 13, 14]

var _catalog: Object
var _actors: Dictionary = {}
var _map_objects: Array[Dictionary] = []
var _limits: Array[String] = []
var _visible_world_rect: Variant = null
var _dialogue_speaker := -1
## 原生 `Field_Basic_mRun:24` 的「当前面向对象」：`Object_objNEAR(3, -1, -1, hero.x, hero.y,
## direction_code, 900)` 选出的最近 NPC（30 px 内的朝向上半平面）；名字条与对话目标都读它。
var _facing_id := -1


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
	var group: Node2D = MAP_OBJECT_SCENE.instantiate()
	group.name = "MapObject_%d" % index
	# 与 actor.tscn 根节点保持一致的原生绘制层级。
	group.z_index = 30
	var body: Node2D = group.get_node("Shake/Body")
	add_child(group)
	body.animation_finished.connect(_on_map_object_animation_finished.bind(index))
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
		"action": action, "path": path, "resting_action": action, "reacting": false,
		"harvests": 0, "hidden": false, "hide_when_idle": false,
		"occlusion_steps": 0}


## 该格上的地图物件当前的动作号（`Object_objHIT` 命中后看 `animation_id`），没有就返回 −1。
func object_action_at(tile: Vector2i) -> int:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) == tile.x and int(record.tile_y) == tile.y and \
				not bool(view.get("hidden", false)):
			return int(view.action)
	return -1


## 原生 `Object_objHIT(hero.x, hero.y, direction_code, 1200)`：主角脚下是**像素**坐标，
## 不是格子。命中集合与朝向窗口都在像素上判，最后取距离² < `range_sq` 的最近一个。
## 返回物件 view（`record` 里仍有格坐标，给打开／反应帧用）。
func object_at(pixel: Vector2, direction_code: int, range_sq: int = 1200) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := range_sq
	for view: Dictionary in _map_objects:
		if bool(view.get("hidden", false)) or not _interactive_action(int(view.action)):
			continue
		var target: Vector2 = view.group.position
		if not _facing_window(pixel, target, direction_code):
			continue
		var distance := int(pixel.distance_squared_to(target))
		if distance >= best_distance:
			continue
		best = view
		best_distance = distance
	return best


## `Object_objHIT` 的命中集合：只有这四类帧会被按确认键命中。
static func _interactive_action(action: int) -> bool:
	return action in MapItemInteraction.TREE_FRAMES or action in [MapItemInteraction.ORE_FRAME,
		MapItemInteraction.GLOW_FRAME_FROM, MapItemInteraction.CHEST_FRAME_CLOSED]


## `Object_objHIT` 的朝向窗口：左右看 |dy| ≤ 8px、向上／下的 0..32px；上下看 |dx| ≤ 8px。
static func _facing_window(hero: Vector2, target: Vector2, direction_code: int) -> bool:
	var delta := target - hero
	match direction_code:
		FieldAction.Facing.LEFT:
			return absf(delta.y) <= 8.0 and delta.x <= 0.0 and -delta.x <= 32.0
		FieldAction.Facing.RIGHT:
			return absf(delta.y) <= 8.0 and delta.x >= 0.0 and delta.x <= 32.0
		FieldAction.Facing.UP:
			return absf(delta.x) <= 8.0 and delta.y <= 0.0 and -delta.y <= 32.0
		FieldAction.Facing.DOWN:
			return absf(delta.x) <= 8.0 and delta.y >= 0.0 and delta.y <= 32.0
	return false


## 该格采集点是否还能给道具：矿石／树都有本次访问的收获上限，矿石耗尽后隐藏。
## 计数不写档；换图重建物件即归零，对应原版“暂时消失／下次再来”的阅读。
func can_harvest_at(tile: Vector2i, kind: int) -> bool:
	var view := _map_object_at(tile)
	if view.is_empty():
		return false
	var limit := MapItemInteraction.harvest_limit(kind)
	return limit > 0 and int(view.get("harvests", 0)) < limit


## 记一次成功采集；矿石到上限后隐藏，等重生计时走完再显现。
func consume_harvest_at(tile: Vector2i, kind: int) -> void:
	var view := _map_object_at(tile)
	if view.is_empty():
		return
	var limit := MapItemInteraction.harvest_limit(kind)
	if limit <= 0:
		return
	var count := mini(int(view.get("harvests", 0)) + 1, limit)
	view["harvests"] = count
	if kind == MapItemInteraction.Kind.ORE and count >= limit:
		view["hide_when_idle"] = true
		if not bool(view.get("reacting", false)):
			_hide_map_object(view)


func _map_object_at(tile: Vector2i) -> Dictionary:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) == tile.x and int(record.tile_y) == tile.y:
			return view
	return {}


func _hide_map_object(view: Dictionary) -> void:
	view["hidden"] = true
	view["hide_when_idle"] = false
	view.group.visible = false


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


## 原生 `Field_Object_procNext`：153..155 播完回 152。矿石受击时按朝向播其中一段，
## 播完由 `_on_map_object_animation_finished` 收回静止帧。
func react_at(tile: Vector2i, from_action: int, reaction_action: int) -> bool:
	for view: Dictionary in _map_objects:
		var record: Dictionary = view.record
		if int(record.tile_x) != tile.x or int(record.tile_y) != tile.y or bool(view.get("reacting", false)):
			continue
		if int(view.action) != from_action:
			continue
		# 上一段反应播完、还没到下一帧收回静止帧时再按一次：先把 152 换回来再起新反应。
		_apply_map_object_revert(view)
		var drawing: Dictionary = view.body_node.present(
			{"path": str(view.get("path", "obj/obj_f_99")), "action": int(reaction_action) % 100,
				"direction": 0}, false, _limit)
		if drawing.is_empty():
			return false
		view["reacting"] = true
		view["action"] = reaction_action
		view["body"] = drawing
		view.body_node.set_speed(NATIVE_ANI_SPEED)
		return true
	return false


## 主角当前显示帧（原生 `Object_procCURR` 的 `frame_index`）：采集命中帧判定用。
func hero_frame() -> int:
	var view: Dictionary = _actors.get(0, {})
	var body: Dictionary = view.get("body", {})
	return int(body.get("frame", -1))


func _on_map_object_animation_finished(index: int) -> void:
	if index < 0 or index >= _map_objects.size():
		return
	var view: Dictionary = _map_objects[index]
	if not bool(view.get("reacting", false)):
		return
	view["reacting"] = false
	# 不在动画回调栈里重建层：只登记要收回的静止帧，下一帧 advance 开头再换。
	view["revert_action"] = int(view.get("resting_action", int(view.action)))


## 矿石反应帧播完的收回点（`Field_Object_procNext` 的 153..155 → 152）。
func _apply_map_object_revert(view: Dictionary) -> void:
	var revert := int(view.get("revert_action", -1))
	if revert < 0:
		return
	view.erase("revert_action")
	# 耗尽矿石不再画一帧静止图：反应一结束就直接隐藏。
	if bool(view.get("hide_when_idle", false)):
		_hide_map_object(view)
		return
	var drawing: Dictionary = view.body_node.present(
		{"path": str(view.get("path", "obj/obj_f_99")), "action": revert % 100,
			"direction": 0}, true, _limit)
	if drawing.is_empty():
		return
	view["action"] = revert
	view["body"] = drawing
	view.body_node.set_speed(1.0)


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
				"body": {}, "emotion": {}, "actor": actor, "name_text": "", "npc_code": 0}
			body.animation_finished.connect(_on_body_animation_finished.bind(id))
		var view: Dictionary = _actors[id]
		view["actor"] = actor
		view["name_text"] = ""
		for binding: Dictionary in bindings:
			if int(binding.get("record_index", -1)) == id:
				var prompt_name: Variant = binding.get("name_text")
				if prompt_name is String and not prompt_name.is_empty():
					view["name_text"] = prompt_name
				view["npc_code"] = int(binding.get("interaction_code", 0))
				break
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
			view.body_node.set_speed(NATIVE_ANI_SPEED \
				if int(art.get("action", 0)) in GATHER_ANI_ACTIONS else 1.0)
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
	view.emotion_node.present(actor, speaking, _limit, actor_id == _facing_id,
		str(view.get("name_text", "")), int(view.get("npc_code", 0)))
	view.emotion = view.emotion_node.drawing()


## 原生 `Field_Basic_mRun` 的每帧面向对象判定：只找 kind 3（NPC，id 不为 0 且 < 1000），
## 按 `direction_code` 的半平面筛候选（上：y ≤ 主角 y；下：≥；左：x ≤；右：≥），
## 距离平方 < 900（30 px）取最近。
func _refresh_facing() -> void:
	var hero_view: Dictionary = _actors.get(0, {})
	if hero_view.is_empty() or hero_view.get("actor", {}).is_empty():
		_facing_id = -1
		return
	var hero: Dictionary = hero_view.actor
	var facing := int(hero.get("lastDirection", int(hero.get("direction", FieldAction.Facing.DOWN))))
	var picked := -1
	var best := 900.0
	for id: int in _actors:
		if id == 0 or id >= 1000:
			continue
		var actor: Dictionary = _actors[id].actor
		var dx := (float(actor.x) - float(hero.x)) * TILE
		var dy := (float(actor.y) - float(hero.y)) * TILE
		if (facing == FieldAction.Facing.UP and dy > 0.0) or \
				(facing == FieldAction.Facing.DOWN and dy < 0.0) or \
				(facing == FieldAction.Facing.LEFT and dx > 0.0) or \
				(facing == FieldAction.Facing.RIGHT and dx < 0.0):
			continue
		var distance := dx * dx + dy * dy
		if distance >= best:
			continue
		picked = id
		best = distance
	_facing_id = picked


## `quest_status` 这类由外部写进 actor 的字段变化后重画表情层（`present` 会跳过没变的请求）。
func refresh_emotions() -> void:
	_refresh_facing()
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


## 让主角当前动作从第一帧重播一次（采集两遍用）。同一条 `present()` 请求会被去重，
## 所以第二遍只能走 `actor_layers.replay()`。
func restart_hero_action() -> bool:
	var view: Dictionary = _actors.get(0, {})
	if view.is_empty() or view.get("body", {}).is_empty():
		return false
	return bool(view.body_node.replay())


func advance(delta: float, animate_bodies: bool = true, animate_hero: bool = true) -> void:
	if not is_finite(delta) or delta < 0:
		return
	_refresh_facing()
	for view: Dictionary in _map_objects:
		_apply_map_object_revert(view)
		if animate_bodies:
			view.body_node.advance(delta)
			view.body.frame = view.body_node.frame_index()
	for view: Dictionary in _actors.values():
		var actor: Dictionary = view["actor"]
		var body: Dictionary = view["body"]
		if animate_bodies and (animate_hero or int(actor.id) != 0) and not body.is_empty():
			view.body_node.advance(delta)
			body.frame = view.body_node.frame_index()
		if _visible_world_rect != null and not body.is_empty():
			var body_bounds: Rect2 = view["group"].get_global_transform() * body["bounds"]
			if not body_bounds.intersects(_visible_world_rect, true):
				continue
		# 名字条的相位与朝向每帧都要重算，所以即使当前没有气泡／任务图标也推进并同步。
		view.emotion_node.advance(delta)
		_sync_emotion(view)
	_apply_occlusion_fade()


## 原生 `Object_procDRAW` 的遮挡淡出：只处理第 0 组（`obj/obj_f_01`）且动画码 ≤14 的
## 0 序树木，且必须绘制在主角之后（脚点更靠下）。档位每帧 ±1，alpha = (256−12×档位)/256。
func _apply_occlusion_fade() -> void:
	var hero_view: Dictionary = _actors.get(0, {})
	if hero_view.is_empty() or hero_view.get("body", {}).is_empty():
		return
	var hero_rect: Rect2 = hero_view.group.get_global_transform() * hero_view.body["bounds"]
	var hero_index: int = int(hero_view.group.get_index())
	for view: Dictionary in _map_objects:
		var body: Dictionary = view.get("body", {})
		if bool(view.get("hidden", false)) or \
				int(view.group.get_meta("draw_order_key", 0)) != 0 or \
				str(view.get("path", "")) != TREE_OBJECT_PATH or \
				int(view.get("resting_action", 0)) % 100 > OCCLUSION_FADE_ACTION_MAX or \
				body.is_empty():
			continue
		var steps := int(view.get("occlusion_steps", 0))
		var overlapping: bool = view.group.get_index() > hero_index and \
			(view.group.get_global_transform() * body["bounds"]).intersects(hero_rect, true)
		if overlapping:
			steps = mini(steps + 1, OCCLUSION_FADE_MAX_STEPS)
		else:
			steps = maxi(steps - 1, 0)
		view["occlusion_steps"] = steps
		view.group.modulate.a = float(256 - OCCLUSION_FADE_ALPHA_STEP * steps) / 256.0


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
