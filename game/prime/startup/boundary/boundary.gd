extends ColorRect
## 边界/错误提示层。
@onready var label: Label = $Label

func show_message(message: String) -> void:
	visible = true
	label.text = message
