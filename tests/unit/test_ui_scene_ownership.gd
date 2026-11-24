extends "res://tests/unit/gut_case.gd"

## 1. 每个 `.tscn` 里的脚本只挂在根节点上（子节点用内联数据，不各自带脚本）；
## 2. 关键 UI 控制器（主循环、视图、渲染器）必须在场景里被挂上，不允许只剩孤零零的脚本；
## 3. 确认框类场景不覆盖鼠标光标（原生是触屏游戏，`bm-P2-312`）。
## 脚本被多个场景共用是允许的（`BattleMap` 基类、`atlas_number` 组件），不在此处判违规。

const SCENE_ROOTS := ["res://"]

## 第三方与工具目录不参与归属检查（GUT 自己的场景带旧 UID，会刷无关警告）。
const SKIP_DIRS := ["addons", ".godot", ".tmp", "tests", "tools", "docs"]

## 必须有场景承载的控制器（脚本路径 → 无场景即视为回归）。
const CONTROLLERS := [
	"res://game/prime/entry/entry/entry.gd",
	"res://game/prime/startup/prime_view/prime_view.gd",
	"res://game/menu/screen/menu_view/menu_view.gd",
	"res://game/battle/presentation/battle_view/battle_view.gd",
	"res://game/field/dialogue/chat_view/chat_view.gd",
	"res://game/field/map/map/map_renderer.gd",
	"res://game/field/runtime/field_actors/field_actors.gd",
	"res://game/field/runtime/touch_controls/touch_controls.gd",
	"res://game/field/runtime/field_runtime/field_runtime.gd",
	"res://game/field/runtime/native_touch_feedback/native_touch_feedback.gd",
]

## 确认框：这些场景不应设置鼠标光标形状。
const CONFIRM_DIALOGS := [
	"res://game/menu/item/item_discard/item_discard.tscn",
	"res://game/menu/party/party_discard/party_discard.tscn",
	"res://game/menu/quest/quest_detail/quest_detail.tscn",
	"res://game/field/map/warp_confirm/warp_confirm.tscn",
	"res://game/field/shops/shop_select/shop_select.tscn",
	"res://game/field/shops/inn/inn.tscn",
	"res://game/field/monsters/mastery_view/mastery_view.tscn",
	"res://game/field/guild/guild_challenge/guild_challenge.tscn",
]

var _owners: Dictionary = {}
var _violations: Array[String] = []


func _check_directory(path: String) -> void:
	for directory in DirAccess.get_directories_at(path):
		if directory in SKIP_DIRS:
			continue
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
				_owners[script.resource_path] = scene_path


func test_legacy_suite() -> void:
	for root: String in SCENE_ROOTS:
		_check_directory(root)
	var unowned: Array[String] = []
	for controller: String in CONTROLLERS:
		if not _owners.has(controller):
			unowned.append(controller)
	assert_true(_violations.is_empty(), "Every Scene script owns its own Scene: %s" % [_violations])
	assert_true(unowned.is_empty(), "Every UI controller must own a Scene: %s" % [unowned])

	var cursor_dialogs: Array[String] = []
	for path: String in CONFIRM_DIALOGS:
		var packed := load(path) as PackedScene
		if packed == null:
			cursor_dialogs.append("%s: scene missing" % path)
			continue
		var state := packed.get_state()
		for node in range(state.get_node_count()):
			for property in range(state.get_node_property_count(node)):
				if state.get_node_property_name(node, property) == &"mouse_default_cursor_shape":
					cursor_dialogs.append("%s:%s" % [path, state.get_node_name(node)])
	assert_true(cursor_dialogs.is_empty(), "Confirm dialogs keep the default cursor: %s" % [cursor_dialogs])
