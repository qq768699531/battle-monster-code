extends Control
## 窗口页脚（接受/返回图标）。

var icon := 0


func configure(catalog: Object, kind: int) -> bool:
	icon = kind
	var frame: Texture2D = catalog.load_sprite("common/ui_battle/frame-011")
	var icons: Texture2D = catalog.load_sprite("common/ui_battle/frame-017")
	if frame == null or icons == null:
		return false
	var variants := [$Accept, $Back, $Middle]
	for index in range(variants.size()):
		var variant: Node2D = variants[index]
		variant.visible = index == kind
		variant.get_node("Frame").texture.atlas = frame
		variant.get_node("Icon").texture.atlas = icons
	return true
