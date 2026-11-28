extends Node2D
## 帮助/说明分页展示层。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
var _page_number_texture: Texture2D
var messages: Dictionary = {}
var last_error := ""
@onready var _frame_rect := UI.box4_window_frame($Frame.window_size)
@onready var _title_origin: Vector2 = $Title.position


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	if not $Navigation.configure(catalog) or not $Back.configure(catalog, 1):
		last_error = "Prime page navigation sprites are unavailable."
		push_error(last_error)
		return false
	_page_number_texture = $Navigation._numbers
	return true


static func page_regions(paint: Dictionary) -> Array[Dictionary]:
	var page = load("res://game/prime/pages/text_page_view/text_page_view.tscn").instantiate()
	var result: Array[Dictionary] = page.live_regions(paint)
	page.free()
	return result


func live_regions(paint: Dictionary) -> Array[Dictionary]:
	var back := Rect2i($Back.get_global_rect()) if is_inside_tree() else UI.control_rect($Back)
	return $Navigation.regions(paint, back)


## 帮助页自己的命中区（上一页、下一页、返回）。
func regions(paint: Dictionary) -> Array[Dictionary]:
	if not visible or int(paint.get("scene", -1)) != C.METHOD:
		return []
	return live_regions(paint)


static func page_scroll_origin(scene: int) -> Vector2i:
	var navigation = load("res://game/prime/ui/page_navigation/page_navigation.tscn").instantiate()
	var origin: Vector2i = UI.control_rect(navigation.get_node("MethodScroll" if scene == C.METHOD else "InfoScroll")).position
	navigation.free()
	return origin


func present(paint: Dictionary) -> void:
	var state: int = paint.get("window_state", 0)
	visible = paint.scene == C.METHOD and state not in [-4, 0]
	if not visible:
		return
	var rect := UI.box4_window_rect(_frame_rect, state)
	modulate.a = UI.phase_alpha(state)
	$Frame.phase = state
	$Title.position = _title_origin + Vector2(0, rect.position.y - _frame_rect.position.y)
	$Title.text = messages[214]
	$Body.visible = state in UI.BODY_PHASES
	$Navigation.visible = $Body.visible
	$Back.visible = state == 4
	if $Body.visible:
		$Body.present(paint)
		$Navigation.present(paint)
