extends "res://tests/unit/gut_case.gd"

## 道具使用／合成的二级选择：原生 `Menu_Item_mPaint` 在 quest_layer 9／10 只
## `Menu_Monster_DrawList(JC_fxt2Return(184), ...)` 开 228×214 的 Box4 窗，不画菜单窗框；
## 重制里它必须是独立窗口：开／关走 `WindowTransition` 的相位动画，正文直接借用菜单里
## 唯一的 `party` 页（不复制页面），屏幕上只剩这一个窗口。

const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const WindowScript = preload("res://game/menu/item/item_target/item_target_window.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")


func test_item_target_opens_as_single_window() -> void:
	var menu: Control = MenuScene.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var window: Control = menu.get_node("item_target")
	var party: Control = menu.get_node("party")
	assert_eq(window.get_script(), WindowScript, "二级选择继承 WindowTransition")
	assert_eq(window.window_size, Vector2i(228, 214), "Menu_Monster_DrawList 的窗宽高")
	assert_false(window.visible, "初始不显示")
	assert_eq(window.get_node("Content").get_child_count(), 0, "窗口不自带一份队伍页")
	menu.item_target_open = true
	menu._render_content()
	assert_true(window.visible, "进入二级选择时开窗")
	await wait_seconds(0.3)
	assert_eq(window.phase, 4, "开窗动画到稳态相位")
	assert_false(menu.get_node("Frame").visible, "菜单窗框收起，只剩二级选择窗")
	assert_eq(window.get_node("Content/party"), party, "正文是菜单里同一个 party 页")
	menu.item_target_open = false
	menu._render_content()
	await wait_seconds(0.3)
	assert_false(window.visible, "关窗动画结束后隐藏")
	assert_true(menu.get_node("Frame").visible, "关窗后菜单窗框回来")
	assert_eq(party.get_parent(), menu, "party 页还回菜单原位")
	assert_eq(window.get_node("Content").get_child_count(), 0, "窗口正文清空")
	# 队伍页的被动技能与装备栏由 `_present_mode` 二选一，不能同时可见（否则两排会重叠）。
	menu.story_progress = {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0],
		"nickname": 0, "hp": 5, "sp": 5}], "partyOrder": [0], "parameter": {},
		"guildCode": 99}
	menu.gameplay_catalog = Fixtures.data({"monsters": [{"id": 49, "kind": 0,
		"attribute_group": 3, "attribute_entry": 0,
		"ability_inputs": [14, 13, 12, 11, 17, 16],
		"attribute_inputs": [16, 4, 22, 2, 11, 2]}]})
	menu.party_navigation_open = true
	menu.selected_party_member_index = 0
	menu.selected_tab = MenuModel.Tab.PARTY
	menu._render_content()
	var monster: Control = party.get_node("Monster")
	assert_true(monster.get_node("Skills").visible, "队伍页默认显示被动技能")
	assert_false(monster.get_node("Equipment").visible, "队伍页不同时显示装备栏")
