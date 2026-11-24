extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://game/prime/title/prime_title_runtime/prime_title_runtime.gd")
const MainScript = preload("res://game/prime/entry/entry/entry.gd")
const TouchControls = preload("res://game/field/runtime/touch_controls/touch_controls.gd")
## 组件场景按使用方归档后不再集中在一个目录：这张表就是它们的新位置。
const WIDGET_SCENES := {
	"native_label": "res://engine/ui/native_label/native_label.tscn",
	"native_panel": "res://engine/ui/native_panel/native_panel.tscn",
	"native_button": "res://game/prime/ui/native_button/native_button.tscn",
	"native_gradient": "res://game/prime/ui/native_gradient/native_gradient.tscn",
	"battle_stat_row": "res://game/prime/title/battle_stat_row/battle_stat_row.tscn",
}


func _key(runtime: RefCounted, key: int) -> Dictionary:
	runtime.key_down(key)
	runtime.key_up()
	return runtime.tick(0.08)


func _verify_widget_scenes() -> void:
	for name in ["native_label", "native_panel", "native_button", "native_gradient",
			"battle_stat_row"]:
		var scene: PackedScene = load(_widget_scene(name))
		var state := scene.get_state()
		var script_count := 0
		for node in range(state.get_node_count()):
			for property in range(state.get_node_property_count(node)):
				if state.get_node_property_name(node, property) == &"script":
					script_count += 1
		assert_true(script_count == 1, "Each widget Scene owns one script; children are Scene instances.")


## 设置页音量行改值只发「哪一行变了」，试听音效与振动时长由启动层唯一那张映射表决定；
## 速度改完回野外时按新值重设 `Engine.time_scale`（战斗结束回地图走同一处）。
func _verify_setting_effects(main: Node) -> void:
	var runtime: RefCounted = main._runtime
	var values: Dictionary = runtime.settings.duplicate(true)
	values.volume = 1
	runtime.set_settings(values)
	runtime.scene = Runtime.SETTINGS
	runtime.select_setting(2)
	var tick: Dictionary = _key(runtime, TouchCode.Pad.RIGHT)
	var changed := 0
	for effect: Dictionary in tick.effects:
		assert_ne(String(effect.get("kind", "")), "audio-request",
			"Prime 设置页不再自带试听映射，由 main 的单一映射表产生。")
		if String(effect.get("kind", "")) == "setting-changed":
			changed += 1
			assert_eq(String(effect.setting_key), "volume")
	assert_eq(changed, 1, "改音量只发一条 setting-changed。")
	var mapped: Array = main._setting_effects(runtime.settings, "volume", 1)
	assert_eq(int(mapped[1].get("resource_id", 0)), MainScript.VOLUME_PREVIEW_RESOURCE_ID)
	values = runtime.settings.duplicate(true)
	values.speed = 1
	main._apply_field_settings(values, false)
	assert_almost_eq(Engine.time_scale, main._launch_time_scale * runtime.speed_scale(), 0.0001)
	Engine.time_scale = main._launch_time_scale


## 环境设定页底部的形态：原生 `EFC_mainTouchSTYLE` 对两条入口给不同 style——Prime 画布的 4131
## 让 `Menu_win_Box_DrawKeyInfo` 画窗口内 OK／BACK；游戏内 OPTION 层 4 的 35 只留摇杆与 OK／CLR。
func _verify_settings_touch_style(main: Node) -> void:
	var runtime: RefCounted = main._runtime
	var view: Node = main._prime_view.settings_view
	runtime.scene = Runtime.SETTINGS
	runtime.window_state = 4
	runtime.settings_touch_style = TouchControls.Style.PRIME_WINDOW
	main._render(runtime._paint())
	var keys := _region_keys(main)
	assert_true(view.get_node("Content/Accept").visible and view.get_node("Content/Back").visible
		and keys.has(TouchCode.Key.OK) and keys.has(TouchCode.Key.BACK),
		"Prime 入口（style 4131）画窗口内 OK／BACK 并登记这两个命中区")
	runtime.settings_touch_style = TouchControls.Style.PAD_KEYS
	main._render(runtime._paint())
	var panel: Array[Dictionary] = view._touch_panel_regions()
	var missing := 0
	for expected: Dictionary in panel:
		if not main._prime_view.regions.has(expected):
			missing += 1
	assert_true(not view.get_node("Content/Accept").visible
		and not view.get_node("Content/Back").visible
		and panel.size() == view.TOUCH_DIRECTIONS.size() + view.TOUCH_KEYS.size()
		and missing == 0,
		"游戏内入口（style 35）不画窗口内图标，改登记摇杆四向与 OK／CLR")


func _region_keys(main: Node) -> Array[int]:
	var keys: Array[int] = []
	for region: Dictionary in main._prime_view.regions:
		keys.append(int(region.key))
	return keys


func _run() -> void:
	await get_tree().process_frame
	_verify_widget_scenes()
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	assert_true(main._startup_error.is_empty(), main._startup_error)
	var runtime: RefCounted = main._runtime
	runtime.scene = Runtime.TITLE
	runtime.menu_open = true
	runtime.selected = 2
	var tick: Dictionary = _key(runtime, -5)
	for index in range(4):
		main._apply_effects(tick.effects)
		main._render(tick.paint)
		tick = runtime.tick(0.08)
	main._render(tick.paint)
	main._handle_pointer(Vector2(305, 120), "down")
	main._handle_pointer(Vector2(305, 120), "up")
	tick = runtime.tick(0.08)
	assert_true(tick.paint.page_index == 1 and tick.paint.page_scroll == 0)
	_verify_setting_effects(main)
	_verify_settings_touch_style(main)
	main.free()


func test_legacy_suite() -> void:
	await _run()

## 组件场景按使用方归档后不再集中在一个目录：这里给出名字到新路径的映射。
func _widget_scene(name: String) -> String:
	match name:
		"native_label": return "res://engine/ui/native_label/native_label.tscn"
		"native_panel": return "res://engine/ui/native_panel/native_panel.tscn"
		"native_button": return "res://game/prime/ui/native_button/native_button.tscn"
		"native_gradient": return "res://game/prime/ui/native_gradient/native_gradient.tscn"
		"battle_stat_row": return "res://game/prime/title/battle_stat_row/battle_stat_row.tscn"
	return ""
