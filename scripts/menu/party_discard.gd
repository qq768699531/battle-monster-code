extends Control
## 队伍页的丢弃确认窗口。

var host: Control


func _ready() -> void:
	host = get_parent()
	visible = false
	$Window.transition_finished.connect(_transition_finished)
	$Window/Content/Yes.pressed.connect(_choose.bind(0))
	$Window/Content/No.pressed.connect(_choose.bind(1))


func render() -> void:
	visible = host.party_discard_open
	if not visible:
		return
	var member: Dictionary = host.party_discard_target
	var cell := $Window/Content/Ball
	cell.get_node("Icon").texture = host._party_icon(member)
	cell.set_grade(host._party_grade_color(member))
	var arguments: Array = member.nativeArguments
	$Window.tooltip_text = host._member_caption(member)
	if int(arguments[3]) >= 0:
		$Window.tooltip_text += "\n已穿戴的装备也会一并丢弃，不会返还背包。"
	cell.tooltip_text = $Window.tooltip_text
	$Window/Content/Prompt.text = host._menu_text(82)
	$Window/Content/Quantity.present("1")
	$Window/Content/Yes/Choice.present(host._menu_text(85), host.selected_party_discard == 0)
	$Window/Content/No/Choice.present(host._menu_text(86), host.selected_party_discard == 1)


func handle_key(key: String) -> bool:
	if $Window.is_transitioning():
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		host.selected_party_discard = 1 - host.selected_party_discard
		render()
	elif key in ["Enter", "Space"]:
		confirm()
	elif key in ["Escape", "Backspace"]:
		$Window.close_window()
	return true


func confirm() -> void:
	if not host.party_discard_open or $Window.is_transitioning():
		return
	if host.selected_party_discard == 1:
		$Window.close_window()
		return
	var members: Array = host.story_progress.monsters
	var index: int = host.party_discard_index
	if index < 0 or index >= members.size() or members[index] != host.party_discard_target:
		host.notice = "所选成员已变化，未丢弃；请取消后重新选择。"
		host._render_content()
		return
	var result: Dictionary = host.Menu.discard_party_member(host.story_progress, index)
	if not result.ok:
		host.notice = str(result.error)
		host._render_content()
		return
	host.notice = ""
	$Window.close_window()
	host.progress_changed.emit(host.story_progress.duplicate(true))
	host._render_content()


func _choose(index: int) -> void:
	if not host.party_discard_open or $Window.is_transitioning():
		return
	if host.selected_party_discard == index:
		confirm()
	else:
		host.selected_party_discard = index
		render()


func _transition_finished(opened: bool) -> void:
	if opened or not host.party_discard_open:
		return
	host.party_discard_open = false
	host.party_discard_index = -1
	host.party_discard_target = {}
	host.notice = ""
	host._render_content()
