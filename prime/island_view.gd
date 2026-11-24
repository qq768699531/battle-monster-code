extends Node2D
## 未知岛主页。

const UI = preload("res://prime/layout.gd")
const SCENE_PATH := "res://prime/island_view/island_view.tscn"

var last_error := ""
var _messages: Dictionary = {}
var _title_delta_y := 0


func configure(catalog: Object, messages: Dictionary) -> bool:
	_messages = messages
	var icons: Texture2D = catalog.load_sprite("common/ui_window/frame-007")
	if icons == null or not $Bounds/Accept.configure(catalog, 0) or not $Bounds/Back.configure(catalog, 1):
		last_error = "Unknown-island interface sprites are unavailable."
		push_error(last_error)
		return false
	$Bounds/Information/LevelIcon.texture.atlas = icons
	$Bounds/Information/ExperienceIcon.texture.atlas = icons
	return true


static func geometry() -> Dictionary:
	return UI.scene_geometry(SCENE_PATH)


func layout_geometry() -> Dictionary:
	return UI.page_geometry(self)


static func regions(paint: Dictionary) -> Array[Dictionary]:
	return UI.menu_regions(paint.get("network_island_geometry", geometry()),
		int(paint.get("network_island_selected", 0)), int(paint.get("window_state", 0)))


func present(paint: Dictionary) -> void:
	var state := int(paint.get("window_state", 0))
	visible = paint.scene == 15 and paint.get("network_island_open", false) and \
		not paint.get("network_detail", false) and state != -4
	if not visible:
		return
	var bounds: Control = $Bounds
	var normal := Rect2i(Vector2i(bounds.position), Vector2i(bounds.size))
	var rect := UI.box4_window_rect(normal, state)
	var delta := rect.position - normal.position
	$Frame.phase = state
	modulate.a = UI.phase_alpha(state)
	$Bounds/Title.text = _messages[301]
	_title_delta_y = UI.follow_window_title($Bounds/Title, delta.y, _title_delta_y)
	var content_visible := state in UI.BODY_PHASES
	$Bounds/Buttons.visible = content_visible
	$Bounds/Information.visible = content_visible
	for index in range(4):
		var button = $Bounds/Buttons.get_child(index)
		button.caption = _messages[302 + index]
		button.selected = index == int(paint.get("network_island_selected", 0))
	var info = $Bounds/Information
	info.get_node("Heading").text = _messages[306]
	info.get_node("MyVisitsHeading").text = _messages[307]
	info.get_node("TotalVisitsHeading").text = _messages[309]
	info.get_node("Level").text = "--"
	info.get_node("Experience").text = "--/--"
	info.get_node("MyVisits").text = _messages[308].replace("%d", "--")
	info.get_node("TotalVisits").text = _messages[308].replace("%d", "--")
	$Bounds/Accept.visible = state == 4
	$Bounds/Back.visible = state == 4
