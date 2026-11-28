extends "res://tests/unit/gut_case.gd"

const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const Msg = preload("res://engine/ui/msg/msg.gd")


func _menu(party: Array) -> Control:
	var progress := {"inventory": {}, "monsters": [], "partyOrder": party,
		"monsterCapacity": 20, "itemCapacity": [72, 72, 72, 72, 72, 72],
		"parameter": {"moneyBalance": 0, "level": 1, "development": {}},
		"quests": {"slots": []}, "warpEnabled": {}}
	var menu: Control = load("res://game/menu/screen/menu/menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.open(progress, AssetCatalog.load_gameplay_catalog(), null)
	return menu


## 原生 `Menu_Party_mKeyPressed@0x4D37C:41-42`：队伍页的 −16 分支先看 `Ball_stdPartys()`，
## 队伍为空就 `Game_warnSet(2)`（fxt 133「请组建队伍」）并留在本页——不能切页、也不能关菜单。
func test_empty_party_cannot_leave_the_party_page() -> void:
	var menu := _menu([])
	menu.select_tab(MenuModel.Tab.PARTY)
	assert_eq(menu.selected_tab, MenuModel.Tab.PARTY, "先进到队伍页")
	menu.select_tab(MenuModel.Tab.ITEMS)
	assert_eq(menu.selected_tab, MenuModel.Tab.PARTY, "空队伍时切页被拒")
	assert_eq(menu.notice, menu._menu_text(Msg.Id.PARTY_REQUIRED), "提示「请组建队伍」")
	menu.select_tab(MenuModel.Tab.PARTY)
	menu.close_menu()
	assert_false(menu.closed, "空队伍时关菜单也被拒")
	assert_eq(menu.notice, menu._menu_text(Msg.Id.PARTY_REQUIRED), "提示保持")
