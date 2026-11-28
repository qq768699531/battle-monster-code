extends Node2D
## 存档槽选择展示层。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const WorldResources = preload("res://engine/data/world_resources/world_resources.gd")

var _npc_records: Array = []
var slot_progress: Array[Dictionary] = []
var _slot_details: Array[Node2D] = []
var _slot_window: Control
var _portraits_released := true
var messages: Dictionary = {}
var last_error := ""
@onready var _frame_rect := UI.box4_window_frame($Window.window_size)
@onready var _title_origin: Vector2 = $Title.position
@onready var _footer_origins: Array[Vector2] = [$Accept.position, $Back.position]
static var _scene_geometry: Dictionary = {}


static func geometry() -> Dictionary:
	if _scene_geometry.is_empty():
		var scene = load("res://game/prime/slots/slot_view/slot_view.tscn").instantiate()
		var cards: Array[Rect2i] = []
		for card: Node2D in [scene.get_node("Card0"), scene.get_node("Card1")]:
			cards.append(UI.control_rect(card.get_node("Hit"), Rect2i(Vector2i(card.position), Vector2i.ZERO)))
		_scene_geometry = {"window": UI.box4_window_frame(scene.get_node("Window").window_size),
		"cards": cards,
			"footers": [UI.control_rect(scene.get_node("Accept")), UI.control_rect(scene.get_node("Back"))],
			"extra": UI.control_rect(scene.get_node("Extra"))}
		scene.free()
	return _scene_geometry


func live_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.get("slot_substate", 0) != 0 or paint.window_state not in [-1, 2, 3, 4]:
		return result
	for index in range(2):
		var card := get_node("Card%d/Hit" % index) as Control
		result.append(UI._region(TouchCode.Key.OK if index == paint.save_slot_selected else (TouchCode.Pad.UP if index == 0 else TouchCode.Pad.DOWN),
			Rect2i(card.get_global_rect())))
	if paint.window_state == 4:
		result.append(UI._region(TouchCode.Key.OK, Rect2i($Accept.get_global_rect())))
		result.append(UI._region(TouchCode.Key.BACK, Rect2i($Back.get_global_rect())))
		if paint.save_slots[paint.save_slot_selected]:
			result.append(UI._region(UI.PanelKey.DELETE, Rect2i($Extra.get_global_rect())))
	return result


## 存档槽页自己的命中区（两张卡、OK／BACK、删除）。网络页的存档槽子页由网络页汇总。
func regions(paint: Dictionary) -> Array[Dictionary]:
	if int(paint.get("scene", -1)) != C.SAVE_SELECT:
		return []
	return live_regions(paint)


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	_slot_window = $Window
	_slot_details.assign([$Card0, $Card1])
	if not $Names.configure(catalog) or \
			not $Card0.configure(catalog) or not $Card1.configure(catalog) or \
			not $Accept.configure(catalog, 0) or not $Back.configure(catalog, 1) or \
			not $Extra.configure(catalog, 2):
		last_error = "Prime slot sprites are unavailable."
		push_error(last_error)
		return false
	var world := WorldResources.new()
	if not world.initialize(catalog):
		last_error = world.last_error
		return false
	var bindings: Variant = world.npc_bindings()
	if bindings == null:
		last_error = world.last_error
		return false
	_npc_records = bindings
	return true


func slot_card_data(progress: Dictionary) -> Dictionary:
	var parameter: Dictionary = progress.parameter
	var identity := int(parameter.identity)
	if identity >= _npc_records.size() or not _npc_records[identity].name_text is String:
		push_error("Prime slot identity has no exported NPC name: %d" % identity)
		return {}
	var title_id := MenuModel.guild_title_record(progress)
	return {"heading": "%s %s" % [messages[title_id], _npc_records[identity].name_text],
		"level": int(parameter.level), "trait": int(parameter.trait)}


func present(paint: Dictionary) -> void:
	var network: bool = paint.scene == C.NETWORK and paint.get("network_slot_page", false) and \
		not paint.get("network_menu_open", false) and not paint.get("network_detail", false)
	var saving: bool = paint.scene == C.SAVE_SELECT
	visible = saving or network
	if not visible:
		_release_portraits()
		return
	_portraits_released = false
	var state: int = paint.get("window_state", 4)
	var rect := UI.box4_window_rect(_frame_rect, state)
	$Window.visible = network and state != -4
	if $Window.visible:
		$Window.phase = state
		$Window.modulate.a = UI.phase_alpha(state)
	$Title.visible = state != -4
	$Title.text = messages[387 if network else 383]
	$Title.position = _title_origin + Vector2(0, rect.position.y - _frame_rect.position.y)
	$Title.modulate.a = UI.phase_alpha(state)
	var details_visible := (saving and state in UI.BODY_PHASES) or (network and state in [3, 4])
	$Names.visible = details_visible
	if details_visible:
		$Names.present(paint)
	for index in range(2):
		var details = _slot_details[index]
		details.visible = details_visible
		if details_visible:
			details.position = paint.slot_positions[index]
			var progress: Dictionary = slot_progress[index] if index < slot_progress.size() else {}
			var card := slot_card_data(progress) if not progress.is_empty() else {}
			details.present(bool(paint.save_slots[index]), index == paint.save_slot_selected, card, progress)
	$Accept.visible = state == 4
	$Back.visible = state == 4
	$Extra.visible = saving and state == 4 and paint.save_slots[paint.save_slot_selected]
	for index in range(2):
		var footer := $Accept if index == 0 else $Back
		footer.position = _footer_origins[index] + Vector2(0, rect.end.y - _frame_rect.end.y)


func _release_portraits() -> void:
	if _portraits_released:
		return
	for card: Node2D in _slot_details:
		card.release_portraits()
	_portraits_released = true
