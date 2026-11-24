extends RefCounted
## 标题主菜单的状态机。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")

var title_animation_frame := 0
var menu_open := false
var selected := 0
var opening_frame := 0
var highlight_frame := 0


func prepare_paint(context: RefCounted) -> Dictionary:
	if menu_open:
		var animation_frame := title_animation_frame
		title_animation_frame += 1
		var layout := title_layout(selected, opening_frame, highlight_frame)
		if opening_frame >= 7:
			highlight_frame += 1
		opening_frame += 1
		return {"animation_frame": animation_frame, "items": layout.items, "regions": layout.regions}
	title_animation_frame = context.frame
	return {"animation_frame": context.frame, "items": [], "regions": [{
		"x": 0, "y": 0, "width": C.LOGICAL_SIZE.x, "height": C.LOGICAL_SIZE.y,
		"key": -5, "repeats": 1,
	}]}


static func title_layout(selection: int, opening: int, highlight: int) -> Dictionary:
	var items: Array[Dictionary] = []
	var regions: Array[Dictionary] = []
	if opening < 2:
		return {"items": items, "regions": regions}

	var interactive := opening >= 7
	var spread := 100
	match opening:
		3: spread = 40
		4: spread = 120
		5: spread = 90
		6: spread = 110
	var first_index := 0 if opening == 2 else 4
	for index in range(first_index, -1, -1):
		var center_y := 120
		if opening != 2:
			center_y += int(float(spread * (63 + 28 * index - 120)) / 100.0)
		var active := interactive and selection == index

		var offset := 11
		if active:
			match highlight:
				0: offset = 8
				1: offset = 12
				2: offset = 10
				_: offset = 12
		var y := center_y - offset
		items.append({
			"x": 200,
			"y": y,
			"index": index,
			"selected": active,
			"text_id": C.TITLE_TEXT_IDS[index],
			"opacity": 0.5 if opening == 2 else 1.0,
			"image": 0 if active else 1,

		})
		if interactive:
			var key: int = TouchCode.Key.OK if index == selection else (
				TouchCode.Pad.UP if index < selection else TouchCode.Pad.DOWN)
			regions.append({
				"x": 150,
				"y": y - 3,
				"width": 100,
				"height": 29,
				"key": key,
				"repeats": 1 if index == selection else absi(index - selection),
			})
	return {"items": items, "regions": regions}


func dispatch(context: RefCounted, key: int) -> void:
	if not menu_open:
		if key != 0:
			menu_open = true
			selected = 0
			opening_frame = 0
			highlight_frame = 0
	elif key == TouchCode.Key.OK:
		if selected == 1:
			context._reset_page_state()
			context.scene = C.SETTINGS
			context._pending_effects.append({"kind": "audio-stop-all", "release": true})
			context.settings_selected = 0
			context.window_state = 1
			context.modal_state = 0
			context._interval_ms = 80
			context._clear_input()
		elif selected == 0:
			context._reset_page_state()
			context.scene = C.SAVE_SELECT
			context.save_slot_selected = 1 if context.save_slots[1] and not context.save_slots[0] else 0
			context.slot_animation_phase = 0
			context.slot_substate = 0
			context.window_state = 1
			context.modal_state = 0
			context._interval_ms = 80
			context._clear_input()
			context._pending_effects.append({"kind": "scene-change", "from": C.TITLE, "to": C.SAVE_SELECT})
		elif selected in [2, 3]:
			var target: int = C.TITLE_TARGETS[selected]
			if not context._pages.has(target):
				push_error("Prime page resource is unavailable for scene %d." % target)
				return
			context._reset_page_state()
			context.scene = target
			context._pending_effects.append({"kind": "audio-stop-all", "release": true})
			context.page_index = 0
			context.page_scroll = 0
			context.window_state = 1
			context.modal_state = 0
			context._clear_input()
			context._pending_effects.append({"kind": "scene-change", "from": C.TITLE, "to": context.scene})
		elif selected in [4, 6, 7]:
			var target := C.NETWORK if selected == 4 else (C.PRESENT if selected == 6 else C.ZONE)
			if not context._notices.has(target):
				push_error("Prime notice resource is unavailable for scene %d." % target)
				return
			context._reset_page_state()
			context.scene = target
			context._pending_effects.append({"kind": "audio-stop-all", "release": true})
			context.window_state = 1
			context.modal_state = 0
			context.modal_selection = 0
			if target == C.NETWORK:
				context.save_slot_selected = 1 if context.save_slots[1] and not context.save_slots[0] else 0
				context.slot_animation_phase = 0
				context.network_selected = 0
				context.network_slot_page = false
				context.network_menu_open = false
				context.network_battle_zone = false
				context.network_battle_selected = 0
				context.network_battle_stats.clear()
				context.network_detail = false
				context.network_detail_action.clear()
				context.network_action_confirming = false
				context.network_request_pending = false
				context.network_entry_request = false
				context.network_result = {}
				context.network_runtime.network_market_open = false
				context.network_runtime.network_market_selected = 0
				context.network_runtime.network_island_open = false
				context.network_runtime.network_island_selected = 0
				context.network_runtime.network_mail_open = false
				context.network_runtime.network_mail_selected = 0
			context._interval_ms = 80
			context._clear_input()
			context._pending_effects.append({"kind": "scene-change", "from": C.TITLE, "to": context.scene})
	elif key == TouchCode.Key.BACK:
		menu_open = false
		context.frame = 0
	elif key == TouchCode.Pad.UP or key == TouchCode.Pad.DOWN:
		selected = posmod(selected + (4 if key == TouchCode.Pad.UP else 1), C.TITLE_TARGETS.size())
		highlight_frame = 0
