extends Control
## 状态页的能力分配确认。

var host: Control

func _ready() -> void:
	host = get_parent()

func handle_key(key: String) -> bool:
	if key in ["Escape", "Backspace"]:
		host.status_confirmation_open = false
		host._render_content()
	elif key in ["Enter", "Space"]:
		host._resolve_status_confirmation()
	elif key in ["ArrowLeft", "ArrowRight"]:
		host.selected_status_confirmation = posmod(host.selected_status_confirmation +
			(-1 if key == "ArrowLeft" else 1), 2)
		host._render_content()
	elif key not in ["ArrowUp", "ArrowDown"]:
		return false
	return true


func _render_confirmation() -> void:
	$Prompt.text = host._menu_text(170)
	$Apply/Label.text = host._menu_text(169)
	$Cancel/Label.text = host._menu_text(168)
	for option in range(2):
		var background: Panel = $Apply/Background if option == 0 else $Cancel/Background
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#081c29")
		style.border_color = host.OPTION_CARD_SELECTED_BORDER if \
			option == host.selected_status_confirmation else host.WINDOW_RULE
		style.set_border_width_all(1)
		style.anti_aliasing = false
		background.add_theme_stylebox_override("panel", style)


