extends "res://tests/unit/gut_case.gd"

## 道具使用／合成的二级选择：原生 `Menu_Item_mPaint` 在 quest_layer 9／10 只
## `Menu_Monster_DrawList(JC_fxt2Return(184), ...)` 开 228×214 的 Box4 窗，不画菜单窗框；
## 重制里它必须是独立窗口：开／关走 `WindowTransition` 的相位动画，屏幕上只剩这一个窗口。

const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const WindowScript = preload("res://game/menu/item/item_target/item_target_window.gd")


func test_item_target_opens_as_single_window() -> void:
	var menu: Control = MenuScene.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var window: Control = menu.get_node("item_target")
	assert_eq(window.get_script(), WindowScript, "二级选择继承 WindowTransition")
	assert_eq(window.window_size, Vector2i(228, 214), "Menu_Monster_DrawList 的窗宽高")
	assert_false(window.visible, "初始不显示")
	menu.item_target_open = true
	menu._render_content()
	assert_true(window.visible, "进入二级选择时开窗")
	await wait_seconds(0.3)
	assert_eq(window.phase, 4, "开窗动画到稳态相位")
	assert_false(menu.get_node("Frame").visible, "菜单窗框收起，只剩二级选择窗")
	menu.item_target_open = false
	menu._render_content()
	await wait_seconds(0.3)
	assert_false(window.visible, "关窗动画结束后隐藏")
	assert_true(menu.get_node("Frame").visible, "关窗后菜单窗框回来")
