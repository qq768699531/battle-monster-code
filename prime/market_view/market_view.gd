extends Node2D
## 精灵市场主页。

const UI = preload("res://prime/layout/layout.gd")
const BUTTON_COUNT := 3
const SCENE_PATH := "res://prime/market_view/market_view.tscn"

var last_error := ""
var _messages: Dictionary = {}
var _title_delta_y := 0


func configure(catalog: Object, messages: Dictionary) -> bool:
	_messages = messages
	if not $Bounds/Accept.configure(catalog, 0) or not $Bounds/Back.configure(catalog, 1):
		last_error = "Market footer sprites are unavailable."
		push_error(last_error)
		return false
	return true


static func geometry() -> Dictionary:
	return UI.scene_geometry(SCENE_PATH)


func layout_geometry() -> Dictionary:
	return UI.page_geometry(self)


static func regions(paint: Dictionary) -> Array[Dictionary]:
	var data: Dictionary = paint.get("network_market_geometry", geometry())
	return UI.menu_regions(data, int(paint.get("network_market_selected", 0)), int(paint.get("window_state", 0)))


func present(paint: Dictionary) -> void:
	var state := int(paint.get("window_state", 0))
	visible = paint.scene == 15 and paint.get("network_market_open", false) and \
		not paint.get("network_detail", false) and state != -4
	if not visible:
		return
	var bounds: Control = $Bounds
	var normal := Rect2i(Vector2i(bounds.position), Vector2i(bounds.size))
	var rect := UI.box4_window_rect(normal, state)
	var delta := rect.position - normal.position
	$Frame.phase = state
	modulate.a = UI.phase_alpha(state)
	$Bounds/Title.text = _messages[279]
	_title_delta_y = UI.follow_window_title($Bounds/Title, delta.y, _title_delta_y)
	$Bounds/Buttons.visible = state in UI.BODY_PHASES
	for index in range(BUTTON_COUNT):
		var button = $Bounds/Buttons.get_child(index)
		button.caption = _messages[280 + index]
		button.selected = index == int(paint.get("network_market_selected", 0))
	$Bounds/Accept.visible = state == 4
	$Bounds/Back.visible = state == 4
