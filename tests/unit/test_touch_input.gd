extends "res://tests/unit/gut_case.gd"

const FIELD_TOUCH_SCENE = preload("res://game/field/runtime/touch_controls/touch_controls.tscn")
const TouchControls = preload("res://game/field/runtime/touch_controls/touch_controls.gd")


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	get_tree().root.push_input(event, true)


func test_legacy_suite() -> void:
	await get_tree().process_frame
	var feedback := get_tree().root.get_node("NativeTouchFeedback")
	feedback.set_process(false)
	_mouse(Vector2(50, 60), true)
	var effect: Dictionary = feedback._effects.back()
	assert_true(effect.frame == 4 and effect.sprites[0].visible and
		effect.sprites[0].texture.get_size() == Vector2(46, 45),
		"global touch feedback draws the native first frame at the press point")
	_mouse(Vector2(50, 60), false)
	feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var controls: Node2D = FIELD_TOUCH_SCENE.instantiate()
	get_tree().root.add_child(controls)
	controls.present(TouchControls.Style.FIELD_WILD, TouchCode.Pad.RIGHT)
	assert_true(controls.touch_keys(Vector2(83, 190)) == [TouchCode.Pad.RIGHT] and
		controls.touch_keys(Vector2(100, 190)).is_empty(),
		"field touch pad maps native hit rectangles to direction keys")
	controls.free()
