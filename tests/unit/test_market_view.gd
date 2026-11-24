extends "res://tests/unit/gut_case.gd"

var _checks := 0
var _failures := 0


func _check(condition: bool, message: String) -> void:
	assert_true(condition, message)
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL market: ", message)


func _key(runtime: RefCounted, key: int) -> Dictionary:
	runtime.key_down(key)
	runtime.key_up()
	return runtime.tick(0.08)


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	_check(main._startup_error.is_empty(), "Market resources must configure through Main.")
	var runtime = main._runtime
	runtime.resume()
	runtime.scene = runtime.NETWORK
	runtime.network_menu_open = true
	runtime.network_selected = 1
	runtime.window_state = 4
	var tick := _key(runtime, -5)
	_check(tick.paint.network_market_open and tick.effects.is_empty(),
		"Entering the native market hub needs no listing request or transaction.")
	main._render(tick.paint)
	tick = _key(runtime, -16)
	_check(not tick.paint.network_market_open and tick.paint.network_menu_open and
		tick.paint.network_selected == 1, "BACK returns to the selected basic network entry.")
	main.queue_free()
	print("Market Scene and native hub input: %d checks, %d failures" % [_checks, _failures])


func test_legacy_suite() -> void:
	_run()
