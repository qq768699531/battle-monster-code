extends "res://tests/unit/gut_case.gd"


func _key(runtime: RefCounted, key: int) -> Dictionary:
	runtime.key_down(key)
	runtime.key_up()
	return runtime.tick(0.08)


func test_legacy_suite() -> void:
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var runtime = main._runtime
	runtime.resume()
	runtime.scene = runtime.NETWORK
	runtime.network_menu_open = true
	runtime.network_selected = 2
	runtime.window_state = 4
	var tick := _key(runtime, -5)
	assert_true(tick.effects.size() == 1 and tick.effects[0].action == "island-entry" and
		tick.paint.network_request_pending and not tick.paint.network_island_open,
		"Entry waits for personal island data, not a public-island listing.")
	runtime.complete_network_request("island-entry", 503, {"message": "test island unavailable"})
	runtime.tick(0.08)
	for frame in range(4):
		runtime.tick(0.08)
	_key(runtime, -16)
	_key(runtime, -5)
	runtime.complete_network_request("island-entry", 200, {"islands": []})
	assert_push_error("unknown-island entry response")
	tick = runtime.tick(0.08)
	assert_true(not tick.paint.network_island_open and tick.paint.network_detail and
		tick.paint.network_result.payload.message.contains("响应无效"),
		"A public list or malformed response cannot masquerade as personal data.")
	main.queue_free()
