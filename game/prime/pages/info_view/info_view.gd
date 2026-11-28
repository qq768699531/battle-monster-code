extends Node2D
## 说明/信息页。

const UI = preload("res://game/prime/ui/layout/layout.gd")
const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
var messages: Dictionary = {}
var last_error := ""
@onready var _frame_rect := UI.box4_window_frame($Frame.window_size)
@onready var _title_origin: Vector2 = $Title.position


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	if not $Navigation.configure(catalog) or not $Back.configure(catalog, 1):
		last_error = "Prime information navigation sprites are unavailable."
		push_error(last_error)
		return false
	return true


func live_regions(paint: Dictionary) -> Array[Dictionary]:
	return $Navigation.regions(paint, Rect2i($Back.get_global_rect()))


## 支持页自己的命中区（上一页、下一页、返回）。
func regions(paint: Dictionary) -> Array[Dictionary]:
	if not visible or int(paint.get("scene", -1)) != C.INFO:
		return []
	return live_regions(paint)


func present(paint: Dictionary) -> void:
	var state: int = paint.get("window_state", 0)
	visible = paint.scene == C.INFO and state not in [-4, 0]
	if not visible:
		return
	var rect := UI.box4_window_rect(_frame_rect, state)
	modulate.a = UI.phase_alpha(state)
	$Frame.phase = state
	$Title.position = _title_origin + Vector2(0, rect.position.y - _frame_rect.position.y)
	$Title.text = messages[215]
	$Body.visible = state in UI.BODY_PHASES
	$Navigation.visible = $Body.visible
	$Back.visible = state == 4
	if $Body.visible:
		$Body.present(paint)
		$Navigation.present(paint)
