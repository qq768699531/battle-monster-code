extends "res://tests/unit/gut_case.gd"

var _checks := 0
var _failures := 0


func _check(condition: bool, message: String) -> void:
	assert_true(condition, message)
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL mail: ", message)


func _key(runtime: RefCounted, key: int) -> Dictionary:
	runtime.key_down(key)
	runtime.key_up()
	return runtime.tick(0.08)


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	_check(main._startup_error.is_empty(), "Main configures the mail Scene and native messages.")
	var runtime = main._runtime
	runtime.resume()
	runtime.scene = runtime.NETWORK
	runtime.network_menu_open = true
	runtime.network_selected = 3
	runtime.window_state = 4
	var tick := _key(runtime, -5)
	_check(tick.paint.network_mail_open and tick.effects.is_empty() and not tick.paint.network_request_pending,
		"Native mailbox entry opens directly, without a generic mail query or claim action.")
	main._render(tick.paint)
	for frame in range(4):
		tick = runtime.tick(0.08)
	main._render(tick.paint)
	await get_tree().process_frame
	var back: Rect2i = main._prime_view.mail_view.layout_geometry().footers[1]
	main._handle_pointer(Vector2(back.get_center()), "down")
	main._handle_pointer(Vector2(back.get_center()), "up")
	tick = runtime.tick(0.08)
	_check(not tick.paint.network_mail_open and tick.paint.network_menu_open and
		tick.paint.network_selected == 3, "BACK returns to basic-menu selection 3.")
	main.queue_free()
	print("Mail Scene and native hub input: %d checks, %d failures" % [_checks, _failures])


func test_legacy_suite() -> void:
	await _run()
