extends Control
## 选项页：四张卡与返回主菜单确认。

var host: Control

func _ready() -> void:
	host = get_parent()
	hide()
	for index in range(host.OPTION_MESSAGE_IDS.size()):
		var button: Button = get_node("Card%d" % index)
		button.pressed.connect(_select_option.bind(index))
	$ReturnWindow/Content/Yes.pressed.connect(_choose_return.bind(0))
	$ReturnWindow/Content/No.pressed.connect(_choose_return.bind(1))
	$ReturnWindow.transition_finished.connect(_return_finished)

func handle_key(key: String) -> bool:
	if host.settings_open or host.help_open:
		return true
	if host.option_return_open:
		if $ReturnWindow.is_transitioning():
			return true
		if key in ["Escape", "Backspace"]:
			$ReturnWindow.close_window()
		elif key in ["ArrowLeft", "ArrowRight"]:
			host.selected_option_return = 1 - host.selected_option_return
			host._render_content()
		elif key in ["Enter", "Space"]:
			_confirm_return()
		return true
	if not host.option_navigation_open:
		if key in ["ArrowUp", "ArrowDown", "Enter", "Space"]:
			host.option_navigation_open = true
			host.selected_option_index = host.OPTION_MESSAGE_IDS.size() - 1 if key == "ArrowUp" else 0
			host._render_content()
			return true
		return false
	if key in ["Escape", "Backspace"]:
		host.option_navigation_open = false
		host.notice = ""
		host._render_content()
		return true
	if key in ["Enter", "Space"]:
		host._activate_option(host.selected_option_index)
		return true
	if key in ["ArrowUp", "ArrowDown"]:
		var direction = -1 if key == "ArrowUp" else 1
		host.selected_option_index = posmod(host.selected_option_index + direction, host.OPTION_MESSAGE_IDS.size())
		host._render_content()
		return true
	return false


func _render_options() -> void:
	for index in range(host.OPTION_MESSAGE_IDS.size()):
		var label: Control = get_node("Card%d/Label" % index)
		label.text = host._menu_text(host.OPTION_MESSAGE_IDS[index])
		var button: Button = get_node("Card%d" % index)
		var border = host.OPTION_CARD_SELECTED_BORDER \
			if host.option_navigation_open and index == host.selected_option_index else host.OPTION_CARD_BORDER
		button.get_node("Inner").modulate = border
		button.get_node("Outer").modulate = border
		button.disabled = host.option_return_open
	$ReturnWindow.visible = host.option_return_open
	if host.option_return_open:
		$ReturnWindow/Content/Prompt.text = host._menu_text(36)
		$ReturnWindow/Content/Yes/Choice.present(host._menu_text(85), host.selected_option_return == 0)
		$ReturnWindow/Content/No/Choice.present(host._menu_text(86), host.selected_option_return == 1)


func _select_option(index: int) -> void:
	if host.option_return_open:
		return
	var selected: bool = host.option_navigation_open and index == host.selected_option_index
	host.option_navigation_open = true
	host.selected_option_index = index
	host.notice = ""
	if selected:
		host._activate_option(index)
	else:
		host._render_content()


func _choose_return(index: int) -> void:
	if $ReturnWindow.is_transitioning():
		return
	if index == host.selected_option_return:
		_confirm_return()
	else:
		host.selected_option_return = index
		host._render_content()


func _confirm_return() -> void:
	host.option_return_accepted = host.selected_option_return == 0
	$ReturnWindow.close_window()


func _return_finished(opened: bool) -> void:
	if opened:
		return
	var accepted: bool = host.option_return_accepted
	host.option_return_open = false
	host.option_return_accepted = false
	host._render_content()
	if accepted:
		host.closed = true
		host.title_requested.emit()
