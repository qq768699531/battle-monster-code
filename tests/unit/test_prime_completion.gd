extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://prime/prime_title_runtime/prime_title_runtime.gd")
const Story = preload("res://core/story/story.gd")
const Store = preload("res://core/save_store/save_store.gd")


func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var runtime: Runtime = main._runtime
	runtime.scene = Runtime.TITLE
	runtime.menu_open = true
	runtime.selected = 1
	runtime.key_down(-5)
	var tick: Dictionary = runtime.tick(0.08)
	assert_true(runtime.scene == Runtime.SETTINGS)
	runtime.set_warning(1, "Original warning")
	for index in range(4):
		tick = runtime.tick(0.08)
		main._render(tick.paint)
	var region: Dictionary = main._prime_view.regions[0]
	runtime.touch("down", region.x + 5, region.y + 5)
	runtime.touch("up")
	for index in range(4):
		runtime.tick(0.08)
	assert_true(runtime.warning_kind == 0)
	var directory := "user://prime-time-test-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var store := Store.new(directory)
	var state := Story.initial_progress(0)
	state.playedTimeMs = 3723000
	store.save(0, state)
	assert_true(store.load_slot(0).progress.playedTimeMs == 3723000)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.slot_path(0)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	main.queue_free()
	await get_tree().process_frame


func test_legacy_suite() -> void:
	await _run()
