extends RefCounted
## 提示/警告的状态机。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const View = preload("res://game/prime/network/notice_view/notice_view.gd")

var _notices: Dictionary = {}


func set_notice(target: int, notice: Dictionary) -> void:
	if target not in [C.NETWORK, C.PRESENT, C.ZONE] or not notice.get("title") is String or \
			not notice.get("heading") is String or not notice.get("lines") is Array:
		push_error("Invalid Prime notice resource.")
		return
	_notices[target] = notice.duplicate(true)


func _dispatch_notice_key(context: RefCounted, key: int) -> void:
	if context.modal_state != 0:
		if key == TouchCode.Key.BACK or (key == TouchCode.Key.OK and context.modal_selection == 1):
			context.modal_state = -1
		elif key in [TouchCode.Pad.LEFT, TouchCode.Pad.RIGHT]:
			context.modal_selection = 1 - context.modal_selection
		return
	if key == TouchCode.Key.BACK:
		context.window_state = -1
	elif key == TouchCode.Key.OK:
		context.modal_state = 1
		context.modal_selection = 0
		context._clear_input()


func paint_page(context: RefCounted, paint: Dictionary) -> void:
	paint.merge({"notice": _notices[context.scene], "window_state": context.window_state,
		"modal_state": context.modal_state, "modal_selection": context.modal_selection})
	paint.regions = View.notice_regions(paint)


func run(context: RefCounted) -> void:
	if context.scene not in [C.PRESENT, C.ZONE]:
		return
	if context.modal_state == -4:
		context.modal_state = 0
	elif context.modal_state == 0 and context.window_state == -4:
		context._return_to_title(6 if context.scene == C.PRESENT else 7)
