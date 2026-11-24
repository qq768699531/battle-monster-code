@tool
extends Control
## 战斗区域页面的展示层。

const UI_THEME = preload("res://core/theme/ui_theme.tres")
const TextLayout = preload("res://core/native_text_layout/native_text_layout.gd")
const UI = preload("res://prime/layout/layout.gd")
const BUTTON_COUNT := 6
const SCENE_PATH := "res://prime/battle_zone/battle_zone.tscn"

var last_error := ""
var _battle_headings: Dictionary = {}
var _messages: Dictionary = {}
static var _default_button_rects: Array[Rect2i] = []


func _ready() -> void:
	var preview := Engine.is_editor_hint() or get_tree().current_scene == self
	get_node("FramePreview").visible = preview
	get_node("TitlePreview").visible = preview


func configure(messages: Dictionary) -> bool:
	_messages = messages
	for id in [250, 251, 253, 256, 257]:
		if not messages.get(id) is String:
			last_error = "Battle-zone text is unavailable: %d" % id
			push_error(last_error)
			return false
		var layout := TextLayout.layout(messages[id], UI_THEME.default_font,
			UI_THEME.default_font_size, 0, false, Color("#FFFFAD"))
		if not layout.error.is_empty():
			last_error = layout.error
			push_error(last_error)
			return false
		_battle_headings[id] = layout.lines[0]
	return true


func present(paint: Dictionary) -> void:
	visible = paint.scene == 15 and paint.get("network_battle_zone", false) and \
		not paint.get("network_detail", false) and paint.get("window_state", 0) in UI.BODY_PHASES
	if not visible:
		return
	get_node("Buttons").notification(Container.NOTIFICATION_SORT_CHILDREN)
	get_node("Statistics/Rows").notification(Container.NOTIFICATION_SORT_CHILDREN)
	get_node("Statistics/Heading").set_line(_battle_headings[250])
	for row in get_node("Statistics/Rows").get_children():
		row.present(_battle_headings, paint.get("network_battle_stats", {}))
	var buttons := get_node("Buttons").get_children()
	for index in range(buttons.size()):
		buttons[index].caption = _messages[258 + index]
		buttons[index].selected = index == int(paint.get("network_battle_selected", 0))


static func battle_zone_button_rect(index: int) -> Rect2i:
	if _default_button_rects.is_empty():
		var scene: PackedScene = load(SCENE_PATH)
		var page = scene.instantiate()
		_default_button_rects.assign(page.button_rects())
		page.free()
	return _default_button_rects[index]


func button_rects() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	var buttons: VBoxContainer = get_node("Buttons")
	var y := 0.0
	for button: Control in buttons.get_children():
		if is_inside_tree():
			result.append(Rect2i(button.get_global_rect()))
		else:
			var minimum := button.get_combined_minimum_size()
			result.append(Rect2i(buttons.position + Vector2(0, y), Vector2(buttons.size.x, minimum.y)))
			y += minimum.y + buttons.get_theme_constant("separation")
	return result
