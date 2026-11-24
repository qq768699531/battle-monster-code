extends RichTextEffect
## 对话逐字显示的节奏控制（纯逻辑）。

const WINDOW_BYTES := 8
## 没有段色时用白色做乘法单位元：原生正文默认色就是调色板 0 的白（`Game_infoDraw:87`）。
const NO_SPAN_COLOR := Color("#FFFFFF")

@export var revealed_color := Color("#E9E9E9")
@export var frontier_color := Color("#FFFFA0")
@export var pending_color := Color("#6E6E6E")

var _byte_offsets := PackedInt32Array()
var _span_colors := PackedColorArray()
var _frontier := 0
var _complete := false


## `span_colors` 是逐字的段色（原生 `#C`／`#P` 与 `[color=…]` 由 `chat_view.body_glyphs()` 解析，
## 与 `text` 一一对应）；留空表示整段都按 `revealed_color` 画。
func present(text: String, characters: int, complete: bool,
		span_colors: PackedColorArray = PackedColorArray()) -> void:
	_byte_offsets.clear()
	_span_colors = span_colors
	var offset := 0
	_frontier = 0
	for index in text.length():
		_byte_offsets.append(offset)
		offset += 1 if text.unicode_at(index) < 128 else 2
		if index < characters:
			_frontier = offset
	if characters > text.length():
		_frontier += (characters - text.length()) * 2
	_complete = complete


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	# RichTextLabel includes a synthetic trailing space outside the source text.
	if char_fx.glyph_flags & TextServer.GRAPHEME_IS_SPACE:
		return true
	var color := revealed_color
	if not _complete:
		var offsets: PackedInt32Array = char_fx.env.byte_offsets
		var offset := offsets[char_fx.relative_index]
		var weight := maxi(0, WINDOW_BYTES - absi(_frontier - offset))
		color = revealed_color if offset < _frontier else pending_color
		color = Color8(
			color.r8 + ((weight * (frontier_color.r8 - color.r8)) >> 3),
			color.g8 + ((weight * (frontier_color.g8 - color.g8)) >> 3),
			color.b8 + ((weight * (frontier_color.b8 - color.b8)) >> 3))
		char_fx.offset.y -= floorf(weight / 2.0)
	char_fx.color *= color * _span_color(char_fx.relative_index)
	return true


func _span_color(index: int) -> Color:
	if index < 0 or index >= _span_colors.size():
		return NO_SPAN_COLOR
	return _span_colors[index]
