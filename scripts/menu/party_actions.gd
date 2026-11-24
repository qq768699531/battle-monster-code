extends VBoxContainer
## 队伍页的动作菜单。

@onready var host: Control = get_parent().get_parent().get_parent()

var _messages: Array[int] = []


func _ready() -> void:
	hide()
	for index in range(get_child_count()):
		get_child(index).pressed.connect(func(): _select(index))


func present() -> void:
	visible = host.party_actions_open
	if not visible:
		return
	var index: int = host.selected_party_member_index
	var member: Dictionary = host.story_progress.monsters[index]
	var in_party: bool = host.Menu.native_party_order(host.story_progress).has(index)
	_messages.assign([172 if in_party else 171, 175,
		174 if member.nativeArguments[3] >= 0 else 173])
	if not in_party:
		_messages.append(178)
	host.selected_party_action = clampi(host.selected_party_action, 0, _messages.size() - 1)
	for row in range(get_child_count()):
		var button: Button = get_child(row)
		button.visible = row < _messages.size()
		if button.visible:
			button.get_node("Caption").text = host._menu_text(_messages[row])
			button.button_pressed = row == host.selected_party_action


func handle_key(key: String) -> bool:
	if key in ["Escape", "Backspace"]:
		host.party_actions_open = false
		host.notice = ""
		host._render_content()
	elif key in ["ArrowUp", "ArrowDown"]:
		host.selected_party_action = posmod(host.selected_party_action +
			(-1 if key == "ArrowUp" else 1), _messages.size())
		host.notice = ""
		host._render_content()
	elif key in ["Enter", "Space"]:
		_confirm()
	return true


func _select(index: int) -> void:
	if host.selected_party_action == index:
		_confirm()
	else:
		host.selected_party_action = index
		host.notice = ""
		host._render_content()


func _confirm() -> void:
	if _messages[host.selected_party_action] == 175:
		host.open_party_detail()
		return
	if _messages[host.selected_party_action] == 173:
		host.open_party_equipment()
		return
	if _messages[host.selected_party_action] == 171:
		host.join_selected_party_member()
		return
	if _messages[host.selected_party_action] == 172:
		host.leave_selected_party_member()
		return
	if _messages[host.selected_party_action] == 174:
		host.unequip_selected_party_member()
		return
	if _messages[host.selected_party_action] == 178:
		host.open_party_discard()
