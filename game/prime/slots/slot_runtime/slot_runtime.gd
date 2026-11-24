extends RefCounted
## 存档槽选择的状态机。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const UI = preload("res://game/prime/ui/layout/layout.gd")

var save_slot_selected := 0
var slot_animation_phase := 0
var save_slots: Array[bool] = [false, false]
var slot_substate := 0
var deletion_pending := false


func complete_slot_delete(context: RefCounted, error: int) -> void:
	if not deletion_pending:
		push_error("Prime has no pending slot deletion.")
		return
	deletion_pending = false
	if error != OK:
		push_error("Prime slot deletion failed: %s" % error_string(error))
		return
	save_slots[save_slot_selected] = false
	slot_substate = 2
	context.modal_state = 1
	context._clear_input()


func _dispatch_save_select_key(context: RefCounted, key: int) -> void:
	if deletion_pending:
		return
	if slot_substate == 1:
		if key == TouchCode.Key.OK:
			if context.modal_selection == 0:
				deletion_pending = true
				context._pending_effects.append({"kind": "save-slot-delete", "slot": save_slot_selected})
			else:
				context.modal_state = -1
		elif key == TouchCode.Key.BACK:
			context.modal_state = -1
		elif key in [TouchCode.Pad.LEFT, TouchCode.Pad.RIGHT]:
			context.modal_selection = 1 - context.modal_selection
		return
	if slot_substate == 2:
		if key in [TouchCode.Key.OK, TouchCode.Key.BACK]:
			context.modal_state = -1
		return
	if key == TouchCode.Key.BACK:
		if context.window_state > 0:
			context.window_state = -1
	elif key == TouchCode.Pad.UP or key == TouchCode.Pad.DOWN:
		save_slot_selected = 1 - save_slot_selected
		slot_animation_phase = 0
	elif key == UI.PanelKey.DELETE and save_slots[save_slot_selected]:
		slot_substate = 1
		context.modal_selection = 1
		context.modal_state = 1
		context._clear_input()
	elif key == TouchCode.Key.OK:
		var occupied := save_slots[save_slot_selected]
		var target := 13 if occupied else 12
		context._pending_effects.append({
			"kind": "save-slot-selected",
			"slot": save_slot_selected,
			"occupied": occupied,
			"target": target,
		})
		context.boundary_target = target
		context._clear_input()


func paint_page(context: RefCounted, paint: Dictionary) -> void:
	paint.merge({"slot_substate": slot_substate, "modal_state": context.modal_state,
		"modal_selection": context.modal_selection, "window_state": context.window_state})
	if context.window_state > 0 and context.window_state < 4:
		context.window_state += 1
	elif context.window_state < 0 and context.window_state > -4:
		context.window_state -= 1


func positions(context: RefCounted) -> Array:
	var geometry: Dictionary = load("res://game/prime/slots/slot_view/slot_view.gd").geometry()
	var result := [geometry.cards[0].position, geometry.cards[1].position]
	if context.scene == C.SAVE_SELECT or (context.scene == C.NETWORK and context.network_slot_page and
			not context.network_menu_open and not context.network_detail and not context.network_request_pending):
		var panel := UI.box4_window_rect(geometry.window, context.window_state)
		var offset: Vector2i = panel.position - geometry.window.position
		result[0] += offset
		result[1] += offset
		if context.window_state in UI.BODY_PHASES and slot_animation_phase < 3 and \
				(context.scene != C.SAVE_SELECT or slot_substate == 0):
			result[save_slot_selected].y += -1 if slot_animation_phase == 1 else 1
			slot_animation_phase += 1
	return result


func run(context: RefCounted) -> void:
	if context.scene == C.SAVE_SELECT and context.modal_state == -4:
		context.modal_state = 0
		slot_substate = 0
	if context.scene == C.SAVE_SELECT and slot_substate == 0 and context.window_state == -4:
		context._return_to_title(0)
