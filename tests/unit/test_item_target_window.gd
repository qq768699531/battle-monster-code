extends "res://tests/unit/gut_case.gd"

## 道具使用／合成的二级选择：原生 `Menu_Item_mPaint` 在 quest_layer 9／10 开独立窗口，
## 重制里窗口正文直接实例化 `party.tscn`，与 PARTY 页同一份页面／脚本、同一套坐标，
## 不裁剪立绘与格位；开／关走 `WindowTransition` 相位动画，屏幕上只剩这一个窗口。

const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const WindowScript = preload("res://game/menu/item/item_target/item_target_window.gd")
const PartyScript = preload("res://game/menu/party/party.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")


func test_item_target_opens_as_single_window() -> void:
	var menu: Control = MenuScene.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var window: Control = menu.get_node("item_target")
	var window_party: Control = window.get_node("Content/Party")
	var menu_party: Control = menu.get_node("party")
	menu.story_progress = {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0],
		"nickname": 0, "hp": 5, "sp": 5}], "partyOrder": [0], "monsterCapacity": 6,
		"parameter": {}, "guildCode": 99}
	menu.gameplay_catalog = Fixtures.data({"monsters": [{"id": 49, "kind": 0,
		"attribute_group": 3, "attribute_entry": 0,
		"ability_inputs": [14, 13, 12, 11, 17, 16],
		"attribute_inputs": [16, 4, 22, 2, 11, 2]}]})
	assert_eq(window.get_script(), WindowScript, "二级选择继承 WindowTransition")
	assert_eq(window.window_size, Vector2i(228, 240), "与队伍页同高的窗口")
	assert_false(window.visible, "初始不显示")
	assert_eq(window_party.get_script(), PartyScript, "正文复用 party.gd，不另写一套")
	assert_ne(window_party, menu_party, "窗口自带独立实例")
	menu.party_navigation_open = true
	menu.selected_party_member_index = 0
	menu.item_target_open = true
	menu._render_content()
	assert_true(window.visible, "进入二级选择时开窗")
	await wait_seconds(0.3)
	assert_eq(window.phase, 4, "开窗动画到稳态相位")
	assert_false(menu.get_node("Frame").visible, "菜单窗框收起，只剩二级选择窗")
	assert_false(menu_party.visible, "菜单里的队伍页同时收起")
	# 与 PARTY 页一致：立绘与六个精灵格位都要画出来，不能裁剪。
	assert_true(window_party.visible, "窗口内的队伍页已挂上")
	assert_true(window_party.get_node("Portrait").visible, "精灵立绘显示")
	var slots: Control = window_party.get_node("Slots")
	for index in range(6):
		assert_true(slots.get_child(index).visible, "第 %d 个精灵格位显示" % index)
	assert_true(window_party.get_node("Monster/Skills").visible, "被动技能栏显示")
	assert_false(window_party.get_node("Monster/Equipment").visible, "装备栏不同时显示")
	menu.item_target_open = false
	menu._render_content()
	await wait_seconds(0.3)
	assert_false(window.visible, "关窗动画结束后隐藏")
	assert_true(menu.get_node("Frame").visible, "关窗后菜单窗框回来")
	# 回到 PARTY 页时技能与装备栏仍互斥（上一轮的重叠回归）。
	menu.selected_tab = MenuModel.Tab.PARTY
	menu._render_content()
	var monster: Control = menu_party.get_node("Monster")
	assert_true(monster.get_node("Skills").visible, "队伍页默认显示被动技能")
	assert_false(monster.get_node("Equipment").visible, "队伍页不同时显示装备栏")
