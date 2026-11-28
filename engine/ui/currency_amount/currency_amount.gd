extends Panel
## 金币数量通用控件：蓝色底板 + 左侧金币图标 + 右侧数字。
##
## 页面只声明 `length`／`height` 和位置，不再自己算图标/数字的 offset；图标固定左对齐、
## 数字固定右对齐，两者都按控件高度内部垂直居中。

@export var length := 92.0:
	set(value):
		length = value
		if is_node_ready():
			_apply_layout()
@export var height := 7.0:
	set(value):
		height = value
		if is_node_ready():
			_apply_layout()

@onready var _icon: TextureRect = $Icon
@onready var _number: Control = $Number


func _ready() -> void:
	_apply_layout()


func _apply_layout() -> void:
	size = Vector2(length, height)
	_icon.position = Vector2(3.0, floorf((height - _icon.size.y) * 0.5))
	_number.position = Vector2(10.0, floorf((height - _number.size.y) * 0.5))
	_number.size = Vector2(maxf(0.0, length - 13.0), _number.size.y)


func present(value: int) -> void:
	_number.call("present", str(value))
