extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://prime/prime_title_runtime/prime_title_runtime.gd")


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main._runtime.scene = Runtime.TITLE
	main._runtime.frame = 1
	main._runtime.title_animation_frame = 30
	main._runtime.menu_open = true
	main._runtime.selected = 1
	main._render(main._runtime.tick(0.08).paint)
	await RenderingServer.frame_post_draw
	main._runtime.key_down(-5)
	main._runtime.key_up()
	main.set_process(true)
	await get_tree().create_timer(0.4).timeout
	main.set_process(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	assert_true(main._capture_viewport != null and main._captured_background != null)
	var image: Image = main._captured_background.get_image()
	var background := image.get_pixel(0, 0)
	var different := 0
	for y in range(0, 240, 4):
		for x in range(0, 400, 4):
			if image.get_pixel(x, y) != background:
				different += 1
	assert_true(image.get_size() == Vector2i(400, 240) and different > 100,
		"The capture must contain the rendered 400x240 title artwork.")
	main._runtime.scene = Runtime.TITLE
	var tick: Dictionary = main._runtime.tick(0.08)
	main._render(tick.paint)
	assert_true(main._capture_viewport == null and main._captured_background == null,
		"Returning to the title releases the captured background.")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_legacy_suite() -> void:
	await _run()
