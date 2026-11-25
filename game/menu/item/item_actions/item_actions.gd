extends VBoxContainer
## 道具页的动作菜单（原生 `Menu_List_Draw`，动作号取自 `common/msg.fxt`）。

@onready var host: Control = get_parent().get_parent().get_parent()

var _actions: Array[int] = []


func _ready() -> void:
	hide()
	for index in range(get_child_count()):
		get_child(index).pressed.connect(func(): _select(index))


func present() -> void:
	visible = host.item_actions_open
	if not visible:
		return
	_actions = host.Menu.item_actions(host._selected_inventory_item())
	host.selected_item_action = clampi(host.selected_item_action, 0, maxi(0, _actions.size() - 1))
	for row in range(get_child_count()):
		var button: Button = get_child(row)
		button.visible = row < _actions.size()
		if button.visible:
			button.get_node("Caption").text = host._menu_text(_actions[row])
		button.button_pressed = button.visible and row == host.selected_item_action


func handle_key(key: String) -> bool:
	if key in ["Escape", "Backspace"]:
		host.item_actions_open = false
		host.notice = ""
		host._render_content()
	elif key in ["ArrowUp", "ArrowDown"] and not _actions.is_empty():
		host.selected_item_action = posmod(host.selected_item_action +
			(-1 if key == "ArrowUp" else 1), _actions.size())
		host.notice = ""
		host._render_content()
	elif key in ["Enter", "Space"]:
		_confirm()
	return true


func _select(index: int) -> void:
	if host.selected_item_action == index:
		_confirm()
	else:
		host.selected_item_action = index
		host.notice = ""
		host._render_content()


func _confirm() -> void:
	if _actions.is_empty():
		return
	match _actions[host.selected_item_action]:
		host.Menu.ITEM_ACTION_USE:
			host.use_selected_item()
		host.Menu.ITEM_ACTION_MIX:
			_confirm_mix()
		host.Menu.ITEM_ACTION_DISCARD:
			host.open_item_discard()


## 技能书袋（原生袋 3）的「合成」：`Menu_Item_mKeyPressed` 的 `quest_layer = 11` 分支里
## `n10 == 10` 时先问 `Menu_Item_Mix_IsPossible`——为 0 就 `Ball_stdUseEx(0, 0, record)` 立刻报
## 返回码 33（`Msg.Id.ITEM_MIX_NO_MATERIAL` = 506「材料不足.」），为 1 才 `quest_layer = 10`、
## `Menu_Party_Set(0, 1)` 定位第一只并进成员选择。
func _confirm_mix() -> void:
	var item: Dictionary = host._selected_inventory_item()
	if item.is_empty():
		return
	host.item_actions_open = false
	if not host.Menu.material_recipe_possible(host.story_progress, item):
		host.notice = host._menu_text(Msg.Id.ITEM_MIX_NO_MATERIAL)
		host._render_content()
		return
	if host.Menu.native_party_order(host.story_progress).is_empty():
		host.notice = "当前没有可选择的出战成员。"
		host._render_content()
		return
	host.selected_party_member_index = 0
	host.selected_item_target_slot = 0
	host.party_navigation_open = true
	host.item_target_open = true
	host.notice = ""
	host._render_content()
