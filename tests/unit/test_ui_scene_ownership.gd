extends "res://tests/unit/gut_case.gd"

var _owners: Dictionary = {}
var _violations: Array[String] = []


func _check_directory(path: String) -> void:
	for directory in DirAccess.get_directories_at(path):
		_check_directory(path.path_join(directory))
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".tscn"):
			continue
		var scene_path := path.path_join(file)
		var scene := load(scene_path) as PackedScene
		if scene == null:
			_violations.append("Scene must load: %s" % scene_path)
			continue
		var state := scene.get_state()
		for node in range(state.get_node_count()):
			for property in range(state.get_node_property_count(node)):
				if state.get_node_property_name(node, property) != &"script":
					continue
				var script: Script = state.get_node_property_value(node, property)
				if script == null:
					continue
				if node != 0:
					_violations.append("Scripts belong to their own Scene root: %s" % scene_path)
				if _owners.has(script.resource_path):
					_violations.append("One UI script must not own multiple Scenes: %s" % script.resource_path)
				if script.source_code.contains("common_view.gd"):
					_violations.append("Scene scripts must not depend on common_view: %s" % scene_path)
				if scene_path.begins_with("res://scenes/components/"):
					if script.resource_path != "res://scripts/components/%s.gd" % scene_path.get_file().get_basename():
						_violations.append("Shared components keep matching scripts: %s" % scene_path)
					elif not FileAccess.file_exists(script.resource_path + ".uid"):
						_violations.append("Moved component scripts keep their UID: %s" % scene_path)
				_owners[script.resource_path] = scene_path


func test_legacy_suite() -> void:
	_check_directory("res://scenes")
	var unowned: Array[String] = []
	for script in ["res://scripts/main.gd", "res://prime/prime_view/prime_view.gd",
			"res://game/menu/screen/menu_view/menu_view.gd", "res://battle/battle_view/battle_view.gd",
			"res://game/field/dialogue/chat_view/chat_view.gd", "res://game/field/map/map/map_renderer.gd",
			"res://game/field/runtime/field_actors/field_actors.gd", "res://game/field/runtime/touch_controls/touch_controls.gd",
			"res://game/field/runtime/field_runtime/field_runtime.gd", "res://game/field/runtime/native_touch_feedback/native_touch_feedback.gd"]:
		if not _owners.has(script):
			unowned.append(script)
	assert_true(_violations.is_empty(), "Every Scene script owns its own Scene: %s" % [_violations])
	assert_true(unowned.is_empty(), "Every UI controller must own a Scene: %s" % [unowned])
	assert_true(not FileAccess.file_exists("res://scripts/prime/common_view.gd"),
		"The legacy unified drawing view must not remain.")
	# 原生是触屏游戏：确认框的「是／否」不改变光标样式（bm-P2-312）。
	var cursor_dialogs: Array[String] = []
	for path: String in ["res://game/menu/item/item_discard/item_discard.tscn",
			"res://game/menu/party/party_discard/party_discard.tscn", "res://scenes/menu/quest_detail.tscn",
			"res://game/field/map/warp_confirm/warp_confirm.tscn", "res://game/field/shops/shop_select/shop_select.tscn",
			"res://game/field/shops/inn/inn.tscn", "res://game/field/monsters/mastery_view/mastery_view.tscn",
			"res://game/field/guild/guild_challenge/guild_challenge.tscn"]:
		var state := (load(path) as PackedScene).get_state()
		for node in range(state.get_node_count()):
			for property in range(state.get_node_property_count(node)):
				if state.get_node_property_name(node, property) == &"mouse_default_cursor_shape":
					cursor_dialogs.append("%s:%s" % [path, state.get_node_name(node)])
	assert_true(cursor_dialogs.is_empty(),
		"Confirm dialogs keep the default cursor: %s" % [cursor_dialogs])
