extends RefCounted
## 网络各页的请求与状态机。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const View = preload("res://game/prime/network/network_view/network_view.gd")

var network_selected := 0
var network_slot_page := false
var network_menu_open := false
var network_detail := false
var network_request_pending := false
var network_entry_request := false
var network_server_time_delta_seconds := 0
var network_result := {}
var network_detail_action := {}
var network_action_confirming := false
var network_market_open := false
var network_market_selected := 0
var network_island_open := false
var network_island_selected := 0
var network_mail_open := false
var network_mail_selected := 0


func complete_network_request(context: RefCounted, operation: String, status: int, payload: Variant) -> void:
	if context.scene != C.NETWORK or not network_request_pending:
		push_error("Local service response arrived outside a pending network action.")
		return
	network_request_pending = false
	if network_entry_request:
		network_entry_request = false
		var timestamp: Variant = payload.get("server_time") if payload is Dictionary else null
		if status == 200 and (timestamp is int or timestamp is float) and \
				timestamp == int(timestamp) and timestamp > 0 and timestamp <= 2147483647:
			network_server_time_delta_seconds = int(timestamp) - int(Time.get_unix_time_from_system())
			network_menu_open = true
			network_slot_page = false
			network_detail = false
			network_selected = 0
			network_result.clear()
		else:
			network_detail = true
			network_result = {"entry_error": true, "operation": operation, "status": status,
				"payload": {"message": str(payload.get("message", "网络连接失败。")) \
					if payload is Dictionary and status != 200 else "服务器时间响应无效。"}}
		context.window_state = 1
		context._clear_input()
		return
	network_detail = true
	network_result = {
		"operation": operation,
		"status": status,
		"payload": payload if payload is Dictionary else {},
	}
	if operation == "island-entry":
		if status == 200 and payload is Dictionary and payload.has("snapshot") and \
				(payload.snapshot == null or payload.snapshot is Dictionary):
			network_island_open = true
			network_island_selected = 0
			network_detail = false
			network_result.clear()
		elif status == 200:
			network_result.payload = {"message": "未知岛资料响应无效。"}
			push_error("Local unknown-island entry response does not contain a valid snapshot.")
		context.window_state = 1
	if operation == "battle-records" and status == 200:
		context.battle_zone_runtime.open(context, network_result.payload)
		network_detail = false
		network_result.clear()
	network_detail_action = _network_action_for_result(operation, network_result.get("payload", {}))
	network_action_confirming = false
	context._clear_input()


func _network_action_for_result(operation: String, payload: Dictionary) -> Dictionary:
	if operation == "mail":
		var messages: Variant = payload.get("messages", [])
		if messages is Array:
			for message in messages:
				if message is Dictionary and not message.get("claimed", false) and \
						message.get("id") is String:
					return {"kind": "claim-mail", "id": message.id}
	elif operation == "market":
		var listings: Variant = payload.get("listings", [])
		if listings is Array:
			for listing in listings:
				if not listing is Dictionary or listing.get("status") != "active" or \
						not listing.get("id") is String:
					continue
				var raw_price: Variant = listing.get("price")
				var price := -1
				if raw_price is int:
					price = raw_price
				elif raw_price is float and is_finite(raw_price) and floor(raw_price) == raw_price \
						and raw_price <= 1_000_000:
					price = int(raw_price)
				if price > 0:
					return {"kind": "buy-market", "id": listing.id,
						"seller": str(listing.get("seller", "")), "price": price}
	elif operation == "island":
		var islands: Variant = payload.get("islands", [])
		if islands is Array:
			for island in islands:
				if island is Dictionary and island.get("username") is String:
					return {"kind": "visit-island", "username": island.username}
	elif operation == "visit-island":
		var island: Variant = payload.get("island", {})
		if island is Dictionary and island.get("username") is String:
			return {"kind": "like-island", "username": island.username}
	return {}


func _dispatch_network_key(context: RefCounted, key: int) -> void:
	if network_request_pending:
		return
	if network_detail:
		if network_result.get("entry_error", false):
			if key in [TouchCode.Key.OK, TouchCode.Key.BACK]:
				network_detail = false
				network_slot_page = false
				network_result.clear()
				context.window_state = 1
				context._clear_input()
			return
		if key == TouchCode.Key.BACK:
			network_detail = false
			network_detail_action.clear()
			network_action_confirming = false
			context._clear_input()
		elif key == TouchCode.Key.OK:
			if network_detail_action.is_empty():
				network_detail = false
				network_result = {}
			elif network_detail_action.kind == "buy-market" and not network_action_confirming:
				network_action_confirming = true
			else:
				network_request_pending = true
				context._pending_effects.append({"kind": "local-service-detail-action",
					"action": network_detail_action.duplicate(true)})
			context._clear_input()
		return
	if context.network_battle_zone:
		context.battle_zone_runtime.dispatch(context, key)
		return
	if network_market_open:
		if key == TouchCode.Key.BACK:
			network_market_open = false
			context.window_state = 1
			context._clear_input()
		elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
			network_market_selected = posmod(network_market_selected + (-1 if key == TouchCode.Pad.UP else 1), 3)
		elif key == TouchCode.Key.OK:
			context.set_warning(1, [
				"出售精灵的选择与定价界面尚未还原。",
				"购买精灵的属性与种类筛选界面尚未还原。",
				"在售精灵列表与撤销界面尚未还原。",
			][network_market_selected])
		return
	if network_island_open:
		if key == TouchCode.Key.BACK:
			network_island_open = false
			network_selected = 2
			context.window_state = 1
			context._clear_input()
		elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
			network_island_selected = posmod(network_island_selected + (-1 if key == TouchCode.Pad.UP else 1), 4)
		elif key == TouchCode.Key.OK:
			context.set_warning(1, [
				"My未知岛的资料详情与进入确认界面尚未还原。",
				"随机访问的目标资料与进入确认界面尚未还原。",
				"喜欢列表界面尚未还原。",
				"访问记录列表界面尚未还原。",
			][network_island_selected])
		return
	if network_mail_open:
		if key == TouchCode.Key.BACK:
			network_mail_open = false
			network_selected = 3
			context.window_state = 1
			context._clear_input()
		elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
			network_mail_selected = posmod(network_mail_selected + (-1 if key == TouchCode.Pad.UP else 1), 4)
		elif key == TouchCode.Key.OK:
			context.set_warning(1, [
				"赠送精灵球的收取人、选择与确认界面尚未还原。",
				"赠送金币的收取人、金额与确认界面尚未还原。",
				"赠送礼物的每日限制与确认界面尚未还原。",
				"道具收件列表与收取、删除确认界面尚未还原。",
			][network_mail_selected])
		return
	if not network_menu_open:
		if network_slot_page:
			if key == TouchCode.Key.BACK:
				network_slot_page = false
				context.window_state = 1
				network_selected = 0
				context._clear_input()
			elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
				context.save_slot_selected = 1 - context.save_slot_selected
				context.slot_animation_phase = 0
			elif key == TouchCode.Key.OK and context.save_slots[context.save_slot_selected]:
				network_request_pending = true
				network_entry_request = true
				network_slot_page = false
				context.window_state = 1
				context._pending_effects.append({"kind": "local-service-request",
					"action": "network-time", "slot": context.save_slot_selected})
				context._clear_input()
			return
		if key == TouchCode.Key.BACK:
			if context.window_state > 0:
				context.window_state = -1
		elif key == TouchCode.Key.OK:
			network_slot_page = true
			context.window_state = 1
			network_selected = 0
			context._clear_input()
		return
	if key == TouchCode.Key.BACK:
		if context.window_state > 0:
			network_menu_open = false
			network_slot_page = false
			network_selected = 0
			context.window_state = 1
			context._clear_input()
	elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
		network_selected = posmod(network_selected + (3 if key == TouchCode.Pad.UP else 1), 4)
	elif key == TouchCode.Key.OK:
		if network_selected == 1:
			network_market_open = true
			network_market_selected = 0
			context.window_state = 1
			context._clear_input()
			return
		if network_selected == 3:
			network_mail_open = true
			network_mail_selected = 0
			context.window_state = 1
			context._clear_input()
			return
		network_request_pending = true
		context._pending_effects.append({"kind": "local-service-request",
			"action": ["battle-records", "market", "island-entry", "mail"][network_selected],
			"slot": context.save_slot_selected})
		context._clear_input()


func paint_page(context: RefCounted, paint: Dictionary) -> void:
	paint.merge({"notice": context._notices[context.scene], "window_state": context.window_state,
		"modal_state": context.modal_state, "modal_selection": context.modal_selection,
		"network_selected": network_selected, "save_slot_selected": context.save_slot_selected,
		"network_market_open": network_market_open,
		"network_market_selected": network_market_selected,
		"network_island_open": network_island_open,
		"network_island_selected": network_island_selected,
		"network_mail_open": network_mail_open,
		"network_mail_selected": network_mail_selected,
		"network_detail": network_detail,
		"network_slot_page": network_slot_page,
		"network_menu_open": network_menu_open,
		"network_request_pending": network_request_pending,
		"network_entry_request": network_entry_request,
		"network_result": network_result.duplicate(true),
		"network_detail_action": network_detail_action.duplicate(true),
		"network_action_confirming": network_action_confirming})
	context.battle_zone_runtime.paint_page(paint)
	paint.regions = View.network_regions(paint)


func run(context: RefCounted) -> void:
	if context.scene == C.NETWORK and context.window_state == -4:
		context._return_to_title(4)
