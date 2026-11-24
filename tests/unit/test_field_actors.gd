extends "res://tests/unit/gut_case.gd"

const FieldActors = preload("res://game/field/runtime/field_actors/field_actors.gd")
const ACTORS_SCENE = preload("res://game/field/runtime/field_actors/field_actors.tscn")
const Minimap = preload("res://game/field/map/minimap/minimap.gd")
const Followers = preload("res://game/field/actors/party_followers/party_followers.gd")


func _actor(id: int = 0, y: float = 5.0) -> Dictionary:
	return {"id": id, "x": 8.0, "y": y, "direction": 32,
		"lastDirection": 32, "action": 0, "emotion": null}


func _state(view: Node2D, id: int = 0) -> Dictionary:
	for state: Dictionary in view.snapshot():
		if state["actor"] == id:
			return state
	return {}


func _object_actions(view: FieldActors) -> Array:
	var actions: Array = []
	for view_state: Dictionary in view._map_objects:
		actions.append(int(view_state.action))
	return actions


func test_legacy_suite() -> void:
	var monster := _actor(1049)
	monster["action"] = 102
	monster["lastDirection"] = 2
	assert_true(FieldActors.field_artwork(monster) ==
		{"path": "mon1/m_f_049", "action": 2, "direction": 1},
		"monster artwork binds the modulo identity and action")
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var view := ACTORS_SCENE.instantiate() as FieldActors
	get_tree().root.add_child(view)
	view.configure(catalog)
	view.sync([_actor()])
	assert_true(view.get_child_count() == 1 and _state(view)["position"] == Vector2(136, 88),
		"sync creates one actor node on its tile foot position")
	var missing := _actor(7)
	view.sync([missing])
	assert_true(_state(view, 7)["body"].is_empty() and
		view.get_limits().has("NPC 7 has no confirmed artwork binding."),
		"an unbound actor hides its body and reports the artwork limit")
	# 传送门帧看 warp 开关（`Map_portalCREATE`），宝箱帧看已开记录
	# （`Map_objCREATE` 的 `Map_boxIsExist(map_id)`）。
	var info := {"map_group": 0,
		"map_objects": [{"tile_x": 1, "tile_y": 1, "frame_id": 164},
			{"tile_x": 2, "tile_y": 2, "frame_id": 176}],
		"warps": [{"tile_x": 1, "tile_y": 1, "destination_map_id": 2}]}
	assert_true(view.set_map_objects(info, [],
			{"map_id": 1, "warps": {"2": true}, "boxes": []}) and
		_object_actions(view) == [164, 176],
		"an enabled portal and a fresh chest draw their closed frames")
	assert_true(view.set_map_objects(info, [], {"map_id": 1, "warps": {}, "boxes": [1]}) and
		_object_actions(view) == [165, 177],
		"a disabled portal and an opened chest draw the other frame")
	# 头顶任务图标：`Qst_icoGET` 的码 2 → `obj/f_emoticon` 动作 11
	# （`Field_Emoticon_procDraw` 的 animation_id 1011）。
	var npc := _actor(3)
	npc["quest_status"] = QuestMark.Code.ACCEPTABLE
	view.sync([npc])
	var quest: Node = view._actors[3]["emotion_node"].get_node("Quest")
	assert_true(quest.visible and int(quest.playback_state().get("action", -1)) ==
		AniAction.Emoticon.QUEST_AVAILABLE, "the quest icon layer plays the available action")
	# 码 0／1 原生不画。
	npc["quest_status"] = QuestMark.Code.NONE
	view.sync([npc])
	assert_false(quest.visible, "a cleared quest status hides the quest icon layer")
	view.free()


## 出战怪物跟随（`Map_summonCREATE`、`Object_procCURR`、
## `Field_procCurr` case 4，见 wiki\field\field-movement.md「地图出战怪物跟随」）：
## 第二、三只怪物与主角一起进渲染树，并按主角轨迹后退跟随。
func test_party_followers() -> void:
	var progress := {"partyOrder": [0, 1, 2],
		"monsters": [{"species": 49}, {"species": 62}, {"species": 86}]}
	var hero := _actor()
	var state := {}
	var followers := Followers.sync(state, progress, hero)
	assert_eq(followers.size(), 3, "队伍三只出战怪物各建一个跟随者")
	var view := ACTORS_SCENE.instantiate() as FieldActors
	get_tree().root.add_child(view)
	view.configure(get_tree().root.get_node("AssetCatalog"))
	var actors: Array = [hero]
	actors.append_array(followers)
	view.sync(actors)
	for follower: Dictionary in followers:
		assert_false(_state(view, int(follower.id))["body"].is_empty(),
			"跟随怪物 %d 进渲染树并取到 mon1 画面" % int(follower.id))
	var from := Vector2(hero.x, hero.y)
	for _step in 4:
		var to := from + Vector2(0, 1)
		Followers.advance(state, from, to, false, true)
		from = to
	hero["x"] = from.x
	hero["y"] = from.y
	view.sync(actors)
	var feet: Array[float] = []
	for index in followers.size():
		feet.append(float(followers[index].y))
	assert_true(feet[0] < from.y and feet[1] < feet[0] and feet[2] < feet[1],
		"跟随者按出战顺序排在主角身后：%s" % [feet])
	# 事件执行记录期间（原生 `EvtData.step_index > 0`，本工程 `progress["cursor"] > 0`）
	# `Field_procCurr:143` 直接返回：主角被剧情摆走后跟随对象留在原地，不聚拢、不跟随。
	var before: Array[Vector2] = []
	for follower: Dictionary in followers:
		before.append(Vector2(follower.x, follower.y))
	var running_progress: Dictionary = progress.duplicate(true)
	running_progress["cursor"] = 3
	var frozen := Followers.sync(state, running_progress, {"id": 0, "x": 8.0, "y": 24.0})
	for index in frozen.size():
		assert_true(Vector2(frozen[index].x, frozen[index].y) == before[index],
			"剧情执行记录期间跟随怪物留在原地（%s → %s）" % [before[index],
				Vector2(frozen[index].x, frozen[index].y)])
	# 事件里换队伍成员（剧情给怪／收怪：原生 `Evt_stdPROC:1061-1084` 的 opcode 0x1F 只改
	# `ItemData.party_monsters`，不重建跟随对象）：冻结判据先于成员判断，所以同样不聚拢。
	var changed_party: Dictionary = running_progress.duplicate(true)
	changed_party["monsters"] = [{"species": 49}, {"species": 62}, {"species": 87}]
	var after_change := Followers.sync(state, changed_party, {"id": 0, "x": 8.0, "y": 24.0})
	for index in after_change.size():
		assert_true(Vector2(after_change[index].x, after_change[index].y) == before[index],
			"事件期间换队伍成员也不聚拢（%s → %s）" % [before[index],
				Vector2(after_change[index].x, after_change[index].y)])
	# 事件里跟随精灵照常画：原生每次绘制都走 `Object_procDRAW`，它只按 `active_state > 0`
	# 收集，不看 `EvtData.step_index`（`Field_procCurr:144` 只跳过演算）。真正让它们消失的是
	# 黑屏之后的 `Op.LOAD_MAP` 重建与 `Op.CLEAR_ACTORS` 清场（bm-P2-103）。
	assert_true(Followers.visible(false, false),
		"剧情期间、第一次黑屏之前跟随精灵照常显示")
	assert_true(not Followers.visible(false, true),
		"事件里第一次黑屏之后不再显示跟随精灵")
	assert_true(not Followers.visible(true, false),
		"清场之后到重建之前不显示跟随精灵")
	# 剧情把主角摆到别处（`Op.PLACE_ACTOR`／传送，原生 `Map_warpProc:32-52`
	# 换图后把跟随对象摆回主角坐标）：队列接不上时聚拢到主角脚下，不再留在原地看不见。
	var placed := {"id": 0, "x": 8.0, "y": 24.0, "direction": 32,
		"lastDirection": 32, "action": 0, "emotion": null}
	followers = Followers.sync(state, progress, placed)
	view.sync([placed] + followers)
	for follower: Dictionary in followers:
		var position: Vector2 = _state(view, int(follower.id))["position"]
		assert_eq(position, Vector2(placed.x, placed.y) * 16 + Vector2(8, 8),
			"主角被剧情摆走后跟随怪物聚拢到主角脚下")
	view.free()


## 剧情动作的结束模式（`Object_procNEXT`，见 wiki\field\field-animation-wait.md）：
## 0 交给该 resource 的 next 回调、100..199 在回调里重播，只有 2 停在末帧。
func test_script_animation_end_mode() -> void:
	var view := ACTORS_SCENE.instantiate() as FieldActors
	get_tree().root.add_child(view)
	view.configure(get_tree().root.get_node("AssetCatalog"))
	var actor := _actor()
	actor["action"] = StoryRuntime.SCRIPTED_ANIMATION_FIRST + FieldAction.Hero.WALK
	actor["animationEndMode"] = StoryRuntime.AnimationEndMode.CALLBACK_OR_RESTART
	view.sync([actor])
	assert_true(bool(view._actors[0]["body_node"].get("_monster").playback_state().looped),
		"结束模式 0 的剧情动作一直重播")
	actor["animationEndMode"] = StoryRuntime.AnimationEndMode.HOLD_LAST_FRAME
	view.sync([actor])
	assert_false(bool(view._actors[0]["body_node"].get("_monster").playback_state().looped),
		"结束模式 2 的剧情动作播一遍停在末帧")
	# 原生 `Object_procNEXT` 的 mode 2 把 `frame_index` 钉在 `frame_count - 1`：播过一遍再推时间，
	# 帧号不回到 0。这是「动作自己停住」的一档；mode 0 的偷袭靠后续 `Op.PLACE_ACTOR` 截断
	# （事件 33#35→#37，见 `test_story::test_event33_clown_ambush_plays_once`）。
	var frames := int(view._actors[0]["body"].get("frames", 0))
	for _tick in 30:
		view.advance(0.1)
	assert_eq([int(view._actors[0]["body"].get("frame", -1)), frames],
		[frames - 1, frames], "结束模式 2 的动作播完后停在末帧、不重播")
	view.free()
