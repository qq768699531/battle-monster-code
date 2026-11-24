extends "res://tests/unit/gut_case.gd"

const Store = preload("res://core/save_store/save_store.gd")
const Story = preload("res://core/story/story.gd")


func _cleanup(path: String) -> void:
	var folder := DirAccess.open(path)
	if folder == null:
		return
	for child in folder.get_directories():
		_cleanup(path.path_join(child))
	for child in folder.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(child)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_legacy_suite() -> void:
	var directory := "user://native-save-store-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var store := Store.new(directory)
	var state: Dictionary = Story.initial_progress(0, 0)
	state["quest"] = 100
	state["actors"][0]["x"] = 8.5
	assert_true(store.load_slot(0)["status"] == "empty" and not store.load_slot(0)["occupied"],
		"empty slot reports a new game")
	var saved: bool = store.save(0, state) == OK
	var loaded: Dictionary = store.load_slot(0)
	assert_true(saved and loaded["occupied"] and loaded["status"] == "ready" and
		loaded["progress"] == state, "native save round trip")
	assert_true(store.save(0, Story.initial_progress(1, 0)) == ERR_INVALID_DATA and
		store.load_slot(0)["progress"] == state, "wrong slot write rejected")
	_cleanup(directory)
