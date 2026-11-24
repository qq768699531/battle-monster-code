extends Node2D
## 触控按下时的屏幕提亮效果。

var sprites: Array[Sprite2D] = []
var copies: Array[BackBufferCopy] = []


func _ready() -> void:
	for child in get_children():
		if child is Sprite2D:
			sprites.append(child)
		elif child is BackBufferCopy:
			copies.append(child)
