extends Node2D
## 提示窗展示层。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const NetworkView = preload("res://game/prime/network/network_view/network_view.gd")
var messages: Dictionary = {}
@onready var _frame_rect := UI.box4_window_frame($Frame.window_size)
@onready var _title_origin: Vector2 = $Title.position
@onready var _accept_origin: Vector2 = $Accept.position
@onready var _back_origin: Vector2 = $Back.position


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	return $Accept.configure(catalog, 0) and $Back.configure(catalog, 1)


static func notice_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.modal_state == 0 and paint.window_state == 4:
		result.append_array(NetworkView.footer_regions(NetworkView.geometry().panel))
	return result


func live_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.modal_state == 0 and paint.window_state == 4:
		result.append(UI._region(TouchCode.Key.OK, Rect2i($Accept.get_global_rect())))
		result.append(UI._region(TouchCode.Key.BACK, Rect2i($Back.get_global_rect())))
	return result


func notice_resource(target: int) -> Dictionary:
	if target not in [15, 16, 17]:
		push_error("Unknown Prime notice scene: %d" % target)
		return {}
	var heading: String = messages[222 if target == 15 else (223 if target == 16 else 224)]
	var body: String = heading + (messages[225] % messages[216])
	var layout := UI.TextLayout.layout(body, UI.UI_FONT, UI.FONT_SIZE, 196, true)
	if not layout.error.is_empty():
		push_error(layout.error)
		return {}
	var lines: Array[String] = []
	for line: Dictionary in layout.lines:
		lines.append(line.text)
	return {"title": messages[219 if target == 15 else (220 if target == 16 else 221)],
		"heading": heading, "lines": lines, "rich_lines": layout.lines,
		"wait_text": messages[249]}


func present(paint: Dictionary) -> void:
	var state: int = paint.get("window_state", 0)
	var network: bool = paint.scene == 15
	var message: bool = paint.get("network_entry_request", false) or \
		paint.get("network_result", {}).get("entry_error", false)
	var slots: bool = paint.get("network_slot_page", false) and \
		not paint.get("network_menu_open", false) and not paint.get("network_detail", false)
	visible = paint.scene in [15, 16, 17] and state != -4 and not (network and (message or slots or
		((paint.get("network_market_open", false) or paint.get("network_island_open", false) or \
		paint.get("network_mail_open", false)) and \
		not paint.get("network_detail", false))))
	if not visible:
		return
	var panel := UI.control_rect($MenuGeometry) if network and paint.get("network_menu_open", false) and \
		not paint.get("network_battle_zone", false) else _frame_rect
	var rect := UI.box4_window_rect(panel, state)
	modulate.a = UI.phase_alpha(state)
	$Frame.window_size = Vector2i(panel.size)
	$Frame.phase = state
	$Title.position = _title_origin + Vector2(0, rect.position.y - _frame_rect.position.y)
	$Title.text = messages[244] if paint.get("network_battle_zone", false) else paint.notice.title
	var content_visible := state in UI.BODY_PHASES
	var show_network: bool = network and (paint.get("network_menu_open", false) or
		paint.get("network_detail", false))
	$Network.visible = content_visible and show_network
	$Body.visible = content_visible and not show_network
	if $Network.visible:
		$Network.present(paint, messages)
	if $Body.visible:
		$Body.present(paint, rect)
	$Accept.visible = state == 4
	$Back.visible = state == 4
	$Accept.position = _accept_origin + Vector2(0, rect.end.y - _frame_rect.end.y)
	$Back.position = _back_origin + Vector2(0, rect.end.y - _frame_rect.end.y)
