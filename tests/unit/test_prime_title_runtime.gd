extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://prime/prime_title_runtime/prime_title_runtime.gd")


func test_legacy_suite() -> void:
	var runtime = Runtime.new()
	for _index in range(149):
		runtime.tick(0.05)
	runtime.tick(0.05)
	assert_true(runtime.scene == Runtime.TITLE)
	runtime.key_down(65)
	runtime.key_up()
	var opening: Dictionary = runtime.tick(0.08)
	for _index in range(7):
		opening = runtime.tick(0.08)
	assert_true(opening.paint.items.size() == 5)
	assert_true(Runtime.keycode_to_native(KEY_UP) == -1 and
		Runtime.keycode_to_native(KEY_DOWN) == -2 and
		Runtime.keycode_to_native(KEY_LEFT) == -3 and
		Runtime.keycode_to_native(KEY_RIGHT) == -4 and
		Runtime.keycode_to_native(KEY_ENTER) == -5 and
		Runtime.keycode_to_native(KEY_ESCAPE) == -16,
		"Prime keyboard keys map to the native movement, confirm and back codes")
