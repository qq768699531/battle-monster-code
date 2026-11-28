extends Node2D
## 提示窗展示层，同时是「网络连接」页的窗口框：网络页的页面命中区也在这里汇总。
##
## 网络页里按钮、市场／未知岛／邮箱／战场区域／存档槽都是各自的子页，只有本节点知道自己那一帧
## 的页脚（Accept／Back）落在哪里，所以 `regions()` 把子页的实时矩形塞进 paint 后交给
## `NetworkView.network_regions()`，再把 footer 命中区换成当前真正可见的页脚。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const NetworkView = preload("res://game/prime/network/network_view/network_view.gd")
var messages: Dictionary = {}
var last_error := ""
## 网络页的同伴页：市场／未知岛／邮箱／战场区域／存档槽，由宿主 `configure()` 一次性绑定。
var _slots: Node
var _battle_zone: Node
var _market: Node
var _island: Node
var _mail: Node
@onready var _frame_rect := UI.box4_window_frame($Frame.window_size)
@onready var _title_origin: Vector2 = $Title.position
@onready var _accept_origin: Vector2 = $Accept.position
@onready var _back_origin: Vector2 = $Back.position


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	if not ($Accept.configure(catalog, 0) and $Back.configure(catalog, 1)):
		last_error = "Prime notice footer sprites are unavailable."
		return false
	return true


## 网络页的同伴页。只做绑定，不做绘制：每个子页自己的窗口实现仍在它自己的目录里。
func bind_network_pages(slots: Node, battle_zone: Node, market: Node, island: Node, mail: Node) -> void:
	_slots = slots
	_battle_zone = battle_zone
	_market = market
	_island = island
	_mail = mail


## 本页负责的场景：网络连接（15）与两张提示页（16／17）。
func regions(paint: Dictionary) -> Array[Dictionary]:
	var scene := int(paint.get("scene", -1))
	if scene in [C.PRESENT, C.ZONE]:
		return live_regions(paint)
	if scene == C.NETWORK:
		return _network_regions(paint)
	return []


## 网络页命中区：按钮／子页矩形喂给 `NetworkView.network_regions`，footer 用当前可见页的页脚。
func _network_regions(paint: Dictionary) -> Array[Dictionary]:
	var layout_paint := paint.duplicate()
	var button_rects: Array[Rect2i] = []
	for button: Control in $Network/Buttons.get_children():
		button_rects.append(Rect2i(button.get_global_rect()))
	layout_paint.network_button_rects = button_rects
	if paint.get("network_market_open", false) and not paint.get("network_detail", false):
		layout_paint.network_market_geometry = _market.layout_geometry()
	if paint.get("network_island_open", false) and not paint.get("network_detail", false):
		layout_paint.network_island_geometry = _island.layout_geometry()
	if paint.get("network_mail_open", false) and not paint.get("network_detail", false):
		layout_paint.network_mail_geometry = _mail.layout_geometry()
	if paint.get("network_battle_zone", false) and not paint.get("network_detail", false):
		layout_paint.network_battle_button_rects = _battle_zone.button_rects()
	var result := NetworkView.network_regions(layout_paint)
	for region: Dictionary in result:
		if region.get("footer", false):
			var footer: Control = get_node("Accept" if region.key == TouchCode.Key.OK else "Back")
			if _slots != null and _slots.visible:
				footer = _slots.get_node("Accept" if region.key == TouchCode.Key.OK else "Back")
			region.merge(UI._region(region.key, Rect2i(footer.get_global_rect())), true)
	return result


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
	if target not in [C.NETWORK, C.PRESENT, C.ZONE]:
		push_error("Unknown Prime notice scene: %d" % target)
		return {}
	var heading: String = messages[222 if target == C.NETWORK else (223 if target == C.PRESENT else 224)]
	var body: String = heading + (messages[225] % messages[216])
	var layout := UI.TextLayout.layout(body, UI.UI_FONT, UI.FONT_SIZE, 196, true)
	if not layout.error.is_empty():
		push_error(layout.error)
		return {}
	var lines: Array[String] = []
	for line: Dictionary in layout.lines:
		lines.append(line.text)
	return {"title": messages[219 if target == C.NETWORK else (220 if target == C.PRESENT else 221)],
		"heading": heading, "lines": lines, "rich_lines": layout.lines,
		"wait_text": messages[249]}


func present(paint: Dictionary) -> void:
	var state: int = paint.get("window_state", 0)
	var network: bool = paint.scene == C.NETWORK
	var message: bool = paint.get("network_entry_request", false) or \
		paint.get("network_result", {}).get("entry_error", false)
	var slots: bool = paint.get("network_slot_page", false) and \
		not paint.get("network_menu_open", false) and not paint.get("network_detail", false)
	visible = paint.scene in [C.NETWORK, C.PRESENT, C.ZONE] and state != -4 and not (network and (message or slots or
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
