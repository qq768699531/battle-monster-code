extends "res://engine/ui/window_transition/window_transition.gd"
## 队伍页的详细情报窗口。

const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")

var host: Control


func _ready() -> void:
	super()
	host = get_parent()
	transition_finished.connect(func(opened: bool):
		if not opened:
			host.party_details_open = false
			host._render_content())
	phase_changed.connect(func(phase: int):
		%Monster.get_node("Toggle").visible = phase == 4)


func handle_key(key: String) -> bool:
	if is_transitioning():
		return true
	if key in ["Escape", "Backspace"]:
		close_window()
	elif key in ["0", "Digit0"]:
		toggle_equipment()
	elif key in ["ArrowLeft", "ArrowRight"] and not host.party_equipment_display_open:
		select_skill(posmod(host.selected_party_detail_skill +
			(-1 if key == "ArrowLeft" else 1), 6))
	return true


func select_skill(index: int) -> void:
	if is_transitioning() or host.party_equipment_display_open:
		return
	host.selected_party_detail_skill = index
	host._render_content()


func toggle_equipment() -> void:
	if is_transitioning():
		return
	host.party_equipment_display_open = not host.party_equipment_display_open
	host._render_content()


func _render_party_detail() -> void:
	$Bounds/Title.text = host._menu_text(153)
	var member: Dictionary = host.story_progress.monsters[host.selected_party_member_index]
	var details: Dictionary = host.Menu.native_member_details(host.story_progress,
		host.gameplay_catalog, host.selected_party_member_index)
	%Error.visible = not details.get("ok", false)
	%Monster.visible = not %Error.visible
	if %Error.visible:
		%Error.text = "详情不可用：%s" % details.get("error", "原始成员记录缺失")
		return
	%Monster.present(member, details)
	var nickname: String = %Monster.get_node("Nickname").text
	var caption: Control = %Caption
	caption.text = (nickname + " " if not nickname.is_empty() else "") + %Monster.get_node("Name").text
	var layout: Dictionary = TextLayout.layout(caption.text, caption.theme.default_font,
		caption.theme.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	caption.custom_minimum_size.x = layout.lines[0].width
	var attribute: TextureRect = %Monster.get_node("Vitals/Attribute")
	%Attribute.texture = attribute.texture
	%Attribute.visible = attribute.visible
