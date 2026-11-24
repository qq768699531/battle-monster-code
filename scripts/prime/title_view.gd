extends Node2D
## 标题主菜单展示层。


func _ready() -> void:
	hide()


func present(paint: Dictionary) -> void:
	visible = paint.scene == 10
	if not visible:
		return
	$Version.visible = paint.menu_open
	$Prompt.visible = not paint.menu_open and int(paint.frame) > 16
	if $Prompt.visible:
		var phase := (int(paint.frame) - 17) % 8
		$Prompt.modulate.a = (64 * phase if phase <= 4 else 512 - 64 * phase) / 256.0
