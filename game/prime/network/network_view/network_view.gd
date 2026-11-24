extends Node2D
## 网络页装配与槽位命中。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const BattleZoneView = preload("res://game/prime/title/battle_zone_scene/battle_zone_scene.gd")
const MarketView = preload("res://game/prime/pages/market_view/market_view.gd")
const IslandView = preload("res://game/prime/pages/island_view/island_view.gd")
const MailView = preload("res://game/prime/pages/mail_view/mail_view.gd")
static var _scene_geometry: Dictionary = {}


static func geometry() -> Dictionary:
	if _scene_geometry.is_empty():
		var scene = load("res://game/prime/network/notice_view/notice_view.tscn").instantiate()
		var buttons: Array[Rect2i] = []
		for button: Control in scene.get_node("Network/Buttons").get_children():
			buttons.append(UI.control_rect(button))
		_scene_geometry = {"panel": UI.box4_window_frame(scene.get_node("Frame").window_size),
			"menu": UI.control_rect(scene.get_node("MenuGeometry")), "buttons": buttons,
			"footers": [UI.control_rect(scene.get_node("Accept")), UI.control_rect(scene.get_node("Back"))]}
		scene.free()
	return _scene_geometry


static func footer_regions(panel: Rect2i) -> Array[Dictionary]:
	var data := geometry()
	var result: Array[Dictionary] = []
	for index in range(2):
		var rect: Rect2i = data.footers[index]
		rect.position += Vector2i(panel.position.x - data.panel.position.x, panel.end.y - data.panel.end.y)
		var region := UI._region(TouchCode.Key.OK if index == 0 else TouchCode.Key.BACK, rect)
		region.footer = true
		result.append(region)
	return result


static func network_panel(paint: Dictionary) -> Rect2i:
	var data := geometry()
	return data.panel if paint.get("network_battle_zone", false) or \
		not paint.get("network_menu_open", false) else data.menu


static func network_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.get("network_request_pending", false):
		return result
	if paint.get("network_result", {}).get("entry_error", false):
		if paint.get("window_state", 0) in UI.BODY_PHASES:
			var layout := network_message_layout(paint)
			var component = load("res://game/prime/network/network_message/network_message.tscn").instantiate()
			result.append(UI._region(TouchCode.Key.OK, component.okay_rect(layout)))
			component.free()
		return result
	if not paint.get("network_slot_page", false) and \
			not paint.get("network_menu_open", false) and \
			not paint.get("network_detail", false):
		if paint.get("window_state", 0) == 4:
			result.append_array(footer_regions(network_panel(paint)))
		return result
	if paint.get("network_slot_page", false) and not paint.get("network_menu_open", false) and \
			not paint.get("network_detail", false):
		if paint.get("window_state", 0) in [3, 4]:
			var selected := int(paint.get("save_slot_selected", 0))
			var slots: Dictionary = load("res://game/prime/slots/slot_view/slot_view.gd").geometry()
			var slot_positions: Array = paint.get("slot_positions", [slots.cards[0].position, slots.cards[1].position])
			for index in range(2):
				result.append(UI._region(TouchCode.Key.OK if index == selected else (TouchCode.Pad.UP if index < selected else TouchCode.Pad.DOWN),
					Rect2i(slot_positions[index], slots.cards[index].size)))
			if paint.get("window_state", 0) == 4:
				result.append_array(footer_regions(network_panel(paint)))
		return result
	if paint.get("network_detail", false):
		if paint.get("window_state", 0) != 4:
			return result
		var detail_action: Dictionary = paint.get("network_detail_action", {})
		var panel := network_panel(paint)
		if not detail_action.is_empty():
			result.append(footer_regions(panel)[0])
		result.append(footer_regions(panel)[1])
		return result
	if paint.get("network_market_open", false):
		return MarketView.regions(paint)
	if paint.get("network_island_open", false):
		return IslandView.regions(paint)
	if paint.get("network_mail_open", false):
		return MailView.regions(paint)
	if paint.get("network_battle_zone", false):
		if paint.get("window_state", 0) not in UI.BODY_PHASES:
			return result
		var selected := int(paint.get("network_battle_selected", 0))
		for index in range(BattleZoneView.BUTTON_COUNT):
			var rects: Array = paint.get("network_battle_button_rects", [])
			var rect: Rect2i = rects[index] if not rects.is_empty() else \
				BattleZoneView.battle_zone_button_rect(index)
			var region := UI._region(TouchCode.Key.OK if index == selected else (TouchCode.Pad.UP if index < selected else TouchCode.Pad.DOWN), rect)
			region.repeats = maxi(1, absi(index - selected))
			result.append(region)
		if paint.get("window_state", 0) == 4:
			result.append_array(footer_regions(network_panel(paint)))
		return result
	if paint.get("window_state", 0) not in UI.BODY_PHASES:
		return result
	if not paint.get("network_menu_open", false):
		return result
	var button_rects: Array = paint.get("network_button_rects", geometry().buttons)
	for index in range(button_rects.size()):
		var selected := int(paint.get("network_selected", 0))
		var region := UI._region(TouchCode.Key.OK if index == selected else (TouchCode.Pad.UP if index < selected else TouchCode.Pad.DOWN),
			button_rects[index])
		region.repeats = maxi(1, absi(index - selected))
		result.append(region)
	if paint.get("window_state", 0) == 4:
		result.append_array(footer_regions(network_panel(paint)))
	return result


func present(paint: Dictionary, messages: Dictionary) -> void:
	var detail: bool = paint.get("network_detail", false)
	var battle: bool = paint.get("network_battle_zone", false)
	$Detail.visible = detail
	if detail:
		$Detail.present(paint)
	$Buttons.visible = not detail and not battle and not paint.get("network_market_open", false) and \
		not paint.get("network_island_open", false) and not paint.get("network_mail_open", false)
	if $Buttons.visible:
		var buttons := $Buttons.get_children()
		for index in range(buttons.size()):
			buttons[index].caption = messages[244 + index]
			buttons[index].selected = index == int(paint.network_selected)
	$Message.visible = $Buttons.visible and paint.get("network_request_pending", false)
	if $Message.visible:
		$Message.present(paint, network_message_layout(paint), messages[138])


static func network_message_layout(paint: Dictionary) -> Dictionary:
	var waiting: bool = paint.get("network_request_pending", false)
	var text: String = str(paint.get("notice", {}).get("wait_text", "连接中...")) if waiting else str(
		paint.get("network_result", {}).get("payload", {}).get("message", ""))
	if text.is_empty():
		text = "网络连接失败。"
	var component = load("res://game/prime/network/network_message/network_message.tscn").instantiate()
	var layout := UI.TextLayout.layout(text, UI.UI_FONT, UI.FONT_SIZE, component.text_width(), true)
	var measured: Dictionary = component.measure(layout.lines, waiting)
	component.free()
	return measured
