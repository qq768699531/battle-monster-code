extends Control
## 用原数字图集拼接数值文本，保持原生字距与符号。

const Glyph = preload("res://ui/atlas_glyph/atlas_glyph.tscn")
const UI = preload("res://prime/layout.gd")
const SYMBOL_DIGITS := {".": 10, "/": 10, "%": 11, "+": 12, "-": 13, ":": 14, "X": 15}
@export var sprite_id := "common/ui_number/frame-000"
@export var source_y := 14
@export var glyph_height := 7
@export var fixed_advance := 0
@export var compact_dot := false
@export var alignment: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_END
@export var texture: Texture2D


func _ready() -> void:
	$Glyphs.alignment = alignment


func configure(catalog: Object) -> bool:
	texture = catalog.load_sprite(sprite_id)
	return texture != null


func present(text: String, row: int = 0) -> void:
	while $Glyphs.get_child_count() < text.length():
		$Glyphs.add_child(Glyph.instantiate())
	var source_x := 0
	for index in range($Glyphs.get_child_count()):
		var glyph := $Glyphs.get_child(index)
		glyph.visible = index < text.length()
		if not glyph.visible:
			continue
		var character := text[index]
		var digit: int = SYMBOL_DIGITS.get(character, text.unicode_at(index) - 48)
		var width: int = (1 if digit == 10 else 5) if fixed_advance > 0 else UI.NUMBER_WIDTHS[digit]
		source_x = 5 * digit if fixed_advance > 0 else 0
		if fixed_advance == 0:
			for preceding in range(digit):
				source_x += UI.NUMBER_WIDTHS[preceding]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(source_x, source_y + glyph_height * row, width, glyph_height)
		var image: TextureRect = glyph.get_node("Image")
		image.texture = atlas
		image.position.x = 2 if fixed_advance > 0 and digit == 10 and not compact_dot else 0
		image.size = atlas.get_size()
		var advance: int = fixed_advance if fixed_advance > 0 else width - 1
		if fixed_advance > 0 and digit == 10 and compact_dot:
			advance = 2
		if index == text.length() - 1:
			advance = advance - 1 if fixed_advance > 0 else width
		glyph.custom_minimum_size = Vector2(advance, glyph_height)
	$Glyphs.notification(Container.NOTIFICATION_SORT_CHILDREN)
