extends Node2D
## 对话窗口外框与两个布局分支。


func set_portrait_side(right: bool) -> void:
	$Right.visible = right
	$Left.visible = not right
