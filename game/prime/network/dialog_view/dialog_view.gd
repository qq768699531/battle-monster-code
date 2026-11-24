extends Node2D
## Prime 对话框页面。

const UI = preload("res://game/prime/ui/layout/layout.gd")
var messages: Dictionary = {}


func configure(texts: Dictionary) -> void:
	messages = texts


func _modal_text(paint: Dictionary) -> String:
	if paint.scene in [16, 17]:
		return messages[398]
	return messages[391 if paint.slot_substate == 1 else 392]


func modal_layout(paint: Dictionary) -> Dictionary:
	var width: int = $Modal.get_meta("network_width") if paint.scene in [16, 17] else $Modal.get_meta("default_width")
	return $Modal.measure(UI.wrap_text(_modal_text(paint), $Modal.text_width(width), UI.UI_FONT), width)


func _modal_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.modal_state not in [-1, 2, 3, 4]:
		return result
	var layout := modal_layout(paint)
	var single: bool = paint.scene == 11 and paint.slot_substate == 2
	var rects: Array[Rect2i] = $Modal.button_rects(layout, single)
	for index in range(rects.size()):
		result.append(UI._region(TouchCode.Key.OK if single or index == paint.modal_selection else (TouchCode.Pad.LEFT if index == 0 else TouchCode.Pad.RIGHT), rects[index]))
	return result


func warning_layout(paint: Dictionary) -> Dictionary:
	var kind := int(paint.warning_kind)
	var text := str(paint.warning_text) if kind == 1 else str(messages[[0, 0, 133, 134, 135, 136, 144, 145][kind]])
	var width: int = $Warning.get_meta("wide_width") if kind == 6 else $Warning.get_meta("default_width")
	return $Warning.measure(UI.wrap_text(text, $Warning.text_width(width), UI.UI_FONT), width)


func present(paint: Dictionary) -> void:
	var modal_state: int = paint.get("modal_state", 0)
	$Modal.visible = modal_state != 0 and modal_state != -4
	if $Modal.visible:
		var single: bool = paint.scene == 11 and paint.slot_substate == 2
		var labels := [messages[138]] if single else [messages[85], messages[86]]
		$Modal.present(modal_layout(paint), modal_state, labels, 0 if single else int(paint.modal_selection))
	$Warning.visible = paint.get("warning_kind", 0) != 0
	if $Warning.visible:
		$Warning.present(warning_layout(paint), int(paint.warning_state), [messages[138]], 0)
