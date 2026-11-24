extends "res://prime/runtime_state/runtime_state.gd"
## 标题选单的状态机：场景切换、动画相位、请求与提示。
## 不含绘制；视图由 PrimeView 与各 *_view 消费。

const TouchControls = preload("res://ui/touch_controls/touch_controls.gd")

## 环境设定页底部的形态由原生 `EFC_mainTouchSTYLE` 决定：Prime 画布的 4131 让
## `Menu_win_Box_DrawKeyInfo` 画窗口内 OK／BACK，游戏内 OPTION 层 4 的 35 只留摇杆与 OK／CLR。
## 两条入口各自赋值：`main._open_field_page` 打开 SETTINGS 时写 35，其余走这里的默认值。
var settings_touch_style := TouchControls.Style.PRIME_WINDOW


func key_down(key: int) -> void:
	key = normalize_key(key)
	if _held_key == key:
		return
	_held_key = key
	if key != -13 and key != -14:
		_push_key(key)


func key_up() -> void:
	_held_key = 0
	_push_key(0)


func touch(kind: String, x: int = 0, y: int = 0) -> void:
	if kind not in ["down", "move", "up"]:
		push_error("Unknown touch event: %s" % kind)
		return
	if kind == "up":
		_last_touch = Vector2i(-1000, -1000)
	else:
		var point := Vector2i(x, y)
		if kind == "move" and absi(x - _last_touch.x) <= 7 and absi(y - _last_touch.y) <= 7:
			return
		_last_touch = point
	_push_touch(_last_touch)


func pause() -> void:
	paused = true
	_clear_input()


func resume() -> void:
	_accumulated_ms = 0.0
	paused = false


func dismiss_boundary() -> void:
	if boundary_target < 0:
		push_error("There is no unavailable Prime target to dismiss.")
		return
	boundary_target = -1
	_clear_input()


func set_settings(values: Dictionary) -> void:
	settings_runtime.set_settings(values)


func speed_scale() -> float:
	return settings_runtime.speed_scale()


func select_setting(index: int) -> void:
	settings_runtime.select_setting(index)


func set_pages(target: int, pages: Array) -> void:
	text_page_runtime.set_pages(target, pages)


func set_notice(target: int, notice: Dictionary) -> void:
	notice_runtime.set_notice(target, notice)


func complete_network_request(operation: String, status: int, payload: Variant) -> void:
	network_runtime.complete_network_request(self, operation, status, payload)


func start() -> void:
	startup_runtime.start(self)


## 调试入口（仅验收用）：从任意页回到启动欢迎页（原生 `Menu_win_Box2_DrawPROGRESS@0x4AEF8`）。
## 见 `startup_runtime.debug_return_to_notice`：正常启动本来就会经过这一页，这里只为反复验收。
func debug_open_startup_page() -> void:
	startup_runtime.debug_return_to_notice(self)


func complete_storage_check(error: int) -> void:
	startup_runtime.complete_storage_check(self, error)


func complete_slot_delete(error: int) -> void:
	slot_runtime.complete_slot_delete(self, error)


func tick(delta: float) -> Dictionary:
	if not is_finite(delta) or delta < 0.0:
		push_error("Prime runtime delta must be finite and nonnegative.")
		return {}
	if paused or boundary_target >= 0:
		return {}
	if scene == NOT_MEM:
		# `PrimeCanvas_mRun@0x6A5F4:10` 每帧累加状态计时（`PrimeCanvas_SetNext@0x6A640:33` 换状态时清零），
		# 欢迎页拿它当进度条与「确定键是否生效」的门槛（`Prime_NotMem_mPaint@0x6A53C:12`）。
		startup_elapsed_ms += delta * 1000.0

	_accumulated_ms += delta * 1000.0
	if _accumulated_ms < _interval_ms:
		return {}
	var elapsed_ms := _accumulated_ms
	_accumulated_ms = fmod(_accumulated_ms, _interval_ms)
	_pending_effects.clear()
	_dispatch_touches()
	while not _keys.is_empty():
		_dispatch_key(_keys.pop_front())

	var effects: Array[Dictionary] = []
	var run_passes := 0
	var changed := true
	while changed:
		changed = startup_runtime.run(self, effects)
		text_page_runtime.run(self)
		settings_runtime.run(self)
		network_runtime.run(self)
		notice_runtime.run(self)
		slot_runtime.run(self)
		if scene in [LOGO, TITLE, SAVE_SELECT, SETTINGS, METHOD, INFO, NETWORK, PRESENT, ZONE]:
			frame += 1
			run_passes += 1

	var paint := _paint()
	if warning_kind != 0:
		paint["warning_kind"] = warning_kind
		paint["warning_state"] = warning_state
		paint["warning_text"] = warning_text
		if warning_state > 0 and warning_state < 4:
			warning_state += 1
		elif warning_state < 0 and warning_state > -4:
			warning_state -= 1
		if warning_state == -4:
			warning_kind = 0
			warning_state = 0
			warning_text = ""
	_regions = paint.regions.duplicate(true)
	effects.append_array(_pending_effects)
	return {
		"elapsed_ms": elapsed_ms,
		"run_passes": run_passes,
		"effects": effects,
		"paint": paint,
	}


static func normalize_key(key: int) -> int:
	match key:
		50: return -1
		52: return -3
		53: return -5
		54: return -4
		56: return -2
		_: return key


static func keycode_to_native(keycode: int) -> int:
	match keycode:
		KEY_UP: return -1
		KEY_DOWN: return -2
		KEY_LEFT: return -3
		KEY_RIGHT: return -4
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: return -5
		KEY_ESCAPE, KEY_BACKSPACE: return -16
		_: return 0


static func title_layout(selection: int, opening: int, highlight: int) -> Dictionary:
	return TitleRuntime.title_layout(selection, opening, highlight)


func _dispatch_touches() -> void:
	while not _touches.is_empty():
		var point: Vector2i = _touches.pop_front()
		if point == Vector2i(-1000, -1000):
			key_down(0)
			continue
		for index in range(_regions.size() - 1, -1, -1):
			var region: Dictionary = _regions[index]
			if point.x < region.x or point.x >= region.x + region.width or \
					point.y < region.y or point.y >= region.y + region.height:
				continue
			for repeat in range(region.repeats):
				key_down(region.key)
				if region.repeats > 1:
					key_down(0)


func _dispatch_key(raw_key: int) -> void:
	if warning_kind > 0:
		if normalize_key(raw_key) in [TouchCode.Key.OK, TouchCode.Key.BACK]:
			warning_state = -1
		return
	if scene == NOT_MEM:
		# `Prime_NotMem_mKeyPressed@0x6ADA0:3-7`：计时过 3000 ms 后确定键才进状态 4（NetDsp）。
		if normalize_key(raw_key) == TouchCode.Key.OK and startup_elapsed_ms > StartupRuntime.PROGRESS_FULL_MS:
			scene = NET_DSP
			_clear_input()
		return
	if scene == NOT_SPACE:
		if normalize_key(raw_key) in [TouchCode.Key.OK, TouchCode.Key.BACK]:
			_pending_effects.append({"kind": "application-exit"})
			_clear_input()
		return
	if boundary_target >= 0:
		if raw_key == TouchCode.Key.BACK or raw_key == TouchCode.Key.OK:
			dismiss_boundary()
		return
	if scene == SETTINGS:
		settings_runtime._dispatch_settings_key(self, normalize_key(raw_key))
		return
	if scene == SAVE_SELECT:
		slot_runtime._dispatch_save_select_key(self, normalize_key(raw_key))
		return
	if scene in [METHOD, INFO]:
		text_page_runtime._dispatch_page_key(self, normalize_key(raw_key))
		return
	if scene in [PRESENT, ZONE]:
		notice_runtime._dispatch_notice_key(self, normalize_key(raw_key))
		return
	if scene == NETWORK:
		network_runtime._dispatch_network_key(self, normalize_key(raw_key))
		return
	if scene != TITLE:
		return
	title_runtime.dispatch(self, normalize_key(raw_key))


func _reset_page_state() -> void:
	settings_selected = 0
	settings_touch_style = TouchControls.Style.PRIME_WINDOW
	page_index = 0
	page_scroll = 0
	window_state = 0
	modal_state = 0
	modal_selection = 0
	slot_substate = 0
	slot_animation_phase = 0
	deletion_pending = false
	_clear_input()


func set_warning(kind: int, text: String = "") -> void:
	if kind not in range(1, 8) or (kind == 1 and text.is_empty()):
		push_error("Invalid original Game warning.")
		return
	warning_kind = kind
	warning_text = text
	warning_state = 1
	_clear_input()


func _return_to_title(selection: int) -> void:
	var previous := scene
	scene = TITLE
	selected = mini(selection, 4)
	menu_open = true
	opening_frame = 99
	highlight_frame = 0
	window_state = 0
	modal_state = 0
	_clear_input()
	_pending_effects.append({"kind": "scene-change", "from": previous, "to": TITLE})


func _paint() -> Dictionary:
	var items: Array[Dictionary] = []
	var regions: Array[Dictionary] = []
	var animation_frame := 0
	var slot_positions := slot_runtime.positions(self)
	if scene == TITLE:
		var title_paint := title_runtime.prepare_paint(self)
		animation_frame = title_paint.animation_frame
		items.assign(title_paint.items)
		regions.assign(title_paint.regions)
	elif scene == SETTINGS:
		animation_frame = frame
	elif scene == SAVE_SELECT:
		animation_frame = frame
	var paint := {
		"scene": scene,
		"frame": frame,
		"title_animation_frame": animation_frame,
		"menu_open": menu_open,
		"selected": selected,
		"save_slot_selected": save_slot_selected,
		"save_slots": save_slots.duplicate(),
		"slot_positions": slot_positions,
		"opening_frame": opening_frame,
		"items": items,
		"regions": regions,
		"settings": {},
		"settings_selected": -1,
		"settings_touch_style": settings_touch_style,
	}
	if scene in [NOT_MEM, NOT_SPACE]:
		paint["startup_elapsed_ms"] = startup_elapsed_ms
		paint["startup_load_ratio"] = startup_load_ratio
	if scene == SETTINGS:
		settings_runtime.paint_page(self, paint)
	if scene in [METHOD, INFO]:
		text_page_runtime.paint_page(self, paint)
	if scene in [PRESENT, ZONE]:
		notice_runtime.paint_page(self, paint)
	if scene == NETWORK:
		network_runtime.paint_page(self, paint)
	if scene in [SETTINGS, METHOD, INFO, NETWORK, PRESENT, ZONE]:
		if window_state > 0 and window_state < 4:
			window_state += 1
		elif window_state < 0 and window_state > -4:
			window_state -= 1
	if scene == SAVE_SELECT:
		slot_runtime.paint_page(self, paint)
	if modal_state > 0 and modal_state < 4:
		modal_state += 1
	elif modal_state < 0 and modal_state > -4:
		modal_state -= 1
	return paint


func set_modal_regions(regions: Array[Dictionary]) -> void:
	_regions = regions.duplicate(true)


func _push_key(key: int) -> void:
	if _keys.size() == 20:
		_keys.pop_front()
	_keys.push_back(key)


func _push_touch(point: Vector2i) -> void:
	if _touches.size() == 20:
		_touches.pop_front()
	_touches.push_back(point)


func _clear_input() -> void:
	_keys.clear()
	_touches.clear()
	_held_key = 0
	_last_touch = Vector2i(-1000, -1000)
