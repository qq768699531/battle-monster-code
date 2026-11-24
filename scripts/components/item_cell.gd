extends Button
class_name ItemCell
## 通用物品格（30×30）：格底贴图、选中呼吸与品级描边。
##
## 原生 `Menu_Item_DrawItem@0x55238` 三层：按 `Menu_winDrawIcon16` 的帧号画格底
## （`(有内容 ? 0 : 2) + (选中 ? 1 : 0)`，见 `SlotFrame`）→ 用品级色画 1px、四角各切 1px 的描边
## （`JC_grpDrawRoundRECT(1, x, y, 30, 30)`）→ 画图标与数量。呼吸亮度来自 `GRP_MODE_BRIGHT` 的
## `8 * frames % 128`，由 `Frame/Breath` 轨驱动。
##
## 描边与亮度都画在 `shaders/item_cell_frame.gdshader` 里：`StyleBoxFlat` 的 `corner_radius = 1`
## 在 1px 边框上实测不切角，只有按像素画才对得上 style 1。调用方只走下面两个入口，不再直接摸
## `Frame`／画描边的节点。


func _ready() -> void:
	resized.connect(_sync_slot_size)
	_sync_slot_size()


## 画格底并开关呼吸。贴图由调用方按 `SlotFrame.frame_of()`／`SlotFrame.index()` 取。
func present_frame(texture: Texture2D, focused: bool) -> void:
	set_frame_texture(texture)
	_material().set_shader_parameter("focused", focused)


## 只换格底贴图，不动呼吸开关：图鉴格停掉了呼吸轨（`book_monster._ready`），不该再写 `focused`。
func set_frame_texture(texture: Texture2D) -> void:
	($Frame as TextureRect).texture = texture


## `color` 是 `Color` 时用品级色画描边；`null` 表示这一格不显示品级（空位或该页不画品级）。
func set_grade(color: Variant) -> void:
	var material := _material()
	material.set_shader_parameter("grade_enabled", color is Color)
	if color is Color:
		material.set_shader_parameter("grade_color", color)


func _material() -> ShaderMaterial:
	return $Frame.material as ShaderMaterial


func _sync_slot_size() -> void:
	var extent := size if size.x > 0.0 and size.y > 0.0 else custom_minimum_size
	_material().set_shader_parameter("slot_size", extent)
