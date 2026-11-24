extends Node2D
## 存档槽的角色名列表。


func configure(catalog: Object) -> bool:
	var name_texture: Texture2D = catalog.load_sprite("common/ui_name/frame-003")
	for slot in [$Slot0, $Slot1]:
		slot.get_node("Name").texture.atlas = name_texture
		slot.get_node("Number").texture.atlas = name_texture
	return name_texture != null


func present(paint: Dictionary) -> void:
	for index in range(2):
		var slot := get_node("Slot%d" % index)
		slot.position = paint.slot_positions[index]
		slot.modulate.a = 1.0 if index == paint.save_slot_selected else 0.5
