extends RefCounted
## 出战怪物的地图跟随队列（位置与朝向的纯计算）。

const MenuModel = preload("res://menu/menu_model/menu_model.gd")
const TILE := 16.0
## 跟随者的临时对象 id：`FOLLOWER_ID_BASE + 槽位 * FOLLOWER_ID_STRIDE + 物种`。
const FOLLOWER_ID_BASE := 1000000
const FOLLOWER_ID_STRIDE := 1000
## 每个对象只记 5 个位置变化点（`Object_procCURR:51-57` 的 `recent_positions[5]`）。
const TRAIL_LENGTH := 5
## 原生 `EvtData.step_index`（原生事件记录的步号）为 0 表示没有事件在跑：`Evt_stdINIT:35`
## 写 −1、`Evt_stdPROC:92` 见到就返回 0。本工程用 `progress["cursor"]` 表达同一状态
## （口径同 `story.gd` 的 `objects_paused()`），它只存非负步号。
const STEP_INDEX_IDLE := 0


static func sync(state: Dictionary, progress: Dictionary, hero: Dictionary,
		reset := false) -> Array:
	if hero.is_empty():
		state.clear()
		return []
	var members := _members(progress)
	# `Field_procCurr:143`：`EvtData.step_index > 0`（事件正在执行记录）时跟随对象直接
	# 返回，既不重新定位也不跟随；`Field_procNext:10` 同样只按既有轨迹，不换目标。这条冻结
	# **先于成员判断**：剧情给怪／收怪（`Evt_stdPROC:1061-1084` 的 opcode 0x1F 只改
	# `ItemData.party_monsters`）不重建跟随对象，重建只在 opcode 0xB（`Evt_stdPROC:275-288`
	# 的 `Map_summonREMOVE/LOAD/CREATE`）与地图加载（`FieldCanvas_load`）两处，所以事件期间
	# 队伍变了也不聚拢，跟随者停在原格。
	if not reset and not state.is_empty() and event_step_running(progress):
		return state.actors
	if reset or state.is_empty() or state.members != members or _leader_teleported(state, hero):
		_anchor(state, members, hero)
	return state.actors


static func _members(progress: Dictionary) -> Array:
	var members := []
	for index: int in MenuModel.native_party_order(progress):
		members.append([index, int(progress.monsters[index].species)])
	return members


## 事件正在执行记录（原生 `EvtData.step_index > 0`，见 `Field_procCurr` case 4 的首句）。
## 跟随与街上的其它对象共用这一个判据：`sync()` 冻结、`advance()` 不跟随都读它。
static func event_step_running(progress: Dictionary) -> bool:
	return int(progress.get("cursor", STEP_INDEX_IDLE)) > STEP_INDEX_IDLE


## 跟随精灵此刻该不该画。原生在事件执行期间照常绘制这些对象：`Field_Basic_mPaint:11` 每次
## 绘制都走 `Object_procDRAW`，而它只按 `active_state > 0` 收集，不看 `EvtData.step_index`
## （`Field_procCurr:144` 返回的只是「跳过演算」，动画帧不前进、位置不跟随）。真正让跟随精灵
## 消失的是黑屏之后的事件记录：`Op.LOAD_MAP`（`Evt_stdPROC:300-302` → `Map_warpProc:21-22`
## → `FieldCanvas_load:146-147` 的 `Map_summonCREATE`，三个槽位直接摆到主角坐标）与
## `Op.CLEAR_ACTORS`（`Evt_stdPROC:292-293` 的 `Map_summonREMOVE/FREE`）。
## 所以 `removed` 表示「已被清场、还没重建」，`event_covered` 表示「事件里已经整屏黑过」
## （由 `field_runtime` 判定并锁存到事件结束）。
static func visible(removed: bool, event_covered: bool) -> bool:
	return not removed and not event_covered


## 主角在没有位移记录的情况下被摆到别处：事件 `Op.PLACE_ACTOR`（`Evt_stdPROC` case 7 的
## `Object_objPOS`）与换图都直接写坐标，不经过 `advance()` 的逐帧记账。原生摆位前把
## `recent_positions[0..4]` 清零（`Map_warpProc:26-30`），再由 `:32-52` 取主角坐标重建三个
## 跟随槽位——轨迹作废时不做插值、直接重新落位。主角自己走开的位移由 `advance()` 记账，
## 不会走到这里，所以正常走跑不会聚拢。
static func _leader_teleported(state: Dictionary, hero: Dictionary) -> bool:
	var recorded: Vector2 = state.get("hero", Vector2.INF)
	return not recorded.is_equal_approx(Vector2(hero.x, hero.y) * TILE)


static func _anchor(state: Dictionary, members: Array, hero: Dictionary) -> void:
	state.clear()
	state.merge({"members": members, "actors": [], "histories": [[]],
		"hero": Vector2(hero.x, hero.y) * TILE, "distance": 0.0, "step": 6.0})
	for slot in members.size():
		var follower_id: int = FOLLOWER_ID_BASE + slot * FOLLOWER_ID_STRIDE + \
			members[slot][1] % FOLLOWER_ID_STRIDE
		state.actors.append({"id": follower_id,
			"x": float(hero.x), "y": float(hero.y), "action": FieldAction.Hero.IDLE,
			"direction": FieldAction.Facing.DOWN, "lastDirection": FieldAction.Facing.DOWN,
			"party_follower": true})
		state.histories.append([])


static func _remember(history: Array, point: Vector2) -> void:
	if history.is_empty() or history[0] != point:
		history.push_front(point)
		if history.size() > TRAIL_LENGTH:
			history.pop_back()


static func _direction(delta: Vector2) -> int:
	if delta == Vector2.ZERO:
		return FieldAction.Facing.DOWN
	if absf(delta.x) >= absf(delta.y):
		return FieldAction.Facing.RIGHT if delta.x > 0 else FieldAction.Facing.LEFT
	return FieldAction.Facing.DOWN if delta.y > 0 else FieldAction.Facing.UP


static func advance(state: Dictionary, from: Vector2, to: Vector2,
		running: bool, following: bool) -> void:
	if state.is_empty():
		return
	var cursor := from * TILE
	var end := to * TILE
	var remaining := cursor.distance_to(end)
	var direction := cursor.direction_to(end)
	if is_zero_approx(float(state.distance)):
		state.step = 8.0 if running else 6.0
	# Native movement writes one history entry per 6px walk / 8px run step.
	while remaining + 0.000001 >= float(state.step) - float(state.distance):
		var distance := float(state.step) - float(state.distance)
		cursor += direction * distance
		remaining = maxf(0.0, remaining - distance)
		state.distance = 0.0
		_remember(state.histories[0], cursor)
		if following:
			for index in state.actors.size():
				var history: Array = state.histories[index]
				if not history.is_empty():
					_remember(state.histories[index + 1], history.back())
		state.step = 8.0 if running else 6.0
	state.distance += remaining
	state.hero = end
	if not following:
		return
	for index in state.actors.size():
		var history: Array = state.histories[index]
		if history.is_empty():
			continue
		var oldest: Vector2 = history.back()
		var next: Vector2 = history[-2] if history.size() > 1 else oldest
		var point := oldest.lerp(next, float(state.distance) / float(state.step)) \
			if history.size() == TRAIL_LENGTH else oldest
		var actor: Dictionary = state.actors[index]
		actor.x = point.x / TILE
		actor.y = point.y / TILE
		actor.lastDirection = _direction(next - oldest)
		actor.direction = actor.lastDirection
