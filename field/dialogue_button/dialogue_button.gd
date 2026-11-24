extends Control
## 对话窗口的 SKIP/OK 按钮。

func set_pressed(pressed: bool) -> void:
	$Visuals.position = $Anchor.position + (Vector2.DOWN if pressed else Vector2.ZERO)
