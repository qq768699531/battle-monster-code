extends RefCounted
## 原生文字排版：按原版文字单元宽高计算换行与逐字形位置。
##
## 换行直接来自正文的 `\n`，颜色用正文内联的 `[color=#RRGGBB]…[/color]` 标记表示，
## 与文字一起保存在翻译资源中，不再依赖原版控制码导出表。

const SPACE_WIDTH := 6.0
const SINGLE_BYTE_WIDTH := 6.0
const DOUBLE_BYTE_WIDTH := 10.0
## 正文里的颜色标记：`[color=#RRGGBB]…[/color]`，与文字一起存在翻译资源里
## （见 `wiki\index.md` 的文本一节）。原生对应 `JC_fntDrawText:265-274` 的 `#C` 换色，
## 两者在量宽度时都按零宽跳过（`JC_fntGetSPACE` 同样先跳控制码）。
const COLOR_SPAN_OPEN_PREFIX := "[color="
const COLOR_SPAN_CLOSE := "[/color]"
const COLOR_SPAN_TERMINATOR := "]"
## 开标记里 `#RRGGBB` 的长度（`#` + 6 位十六进制）。
const COLOR_SPAN_HEX_LENGTH := 7


## 从 `cursor` 起的一个颜色标记；不是标记时返回空串。折行与量宽度共用一个文法。
static func markup_token_at(text: String, cursor: int) -> String:
	if text.substr(cursor, COLOR_SPAN_CLOSE.length()) == COLOR_SPAN_CLOSE:
		return COLOR_SPAN_CLOSE
	if text.substr(cursor, COLOR_SPAN_OPEN_PREFIX.length()) != COLOR_SPAN_OPEN_PREFIX:
		return ""
	var close := text.find(COLOR_SPAN_TERMINATOR, cursor)
	if close < 0:
		return ""
	var literal := text.substr(cursor + COLOR_SPAN_OPEN_PREFIX.length(),
		close - cursor - COLOR_SPAN_OPEN_PREFIX.length())
	if literal.length() != COLOR_SPAN_HEX_LENGTH or not literal.begins_with("#") or \
			not literal.substr(1).is_valid_hex_number():
		return ""
	return text.substr(cursor, close + 1 - cursor)


## 去掉颜色标记后的可见正文：折行与宽度计算只认它。标记写坏时按原文返回，
## 让排版侧照常报错而不是在这里吞掉。
static func plain_text(text: String) -> String:
	var styled := _strip_color_markup(text)
	return text if not styled.error.is_empty() else String(styled.text)


static func layout(text: String, font: Font, font_size: int,
		width: float = 0.0, justify: bool = false, default_color: Color = Color.WHITE) -> Dictionary:
	if font == null or font_size <= 0 or width < 0.0:
		return {"error": "Invalid native text font, size or line width."}
	var styled := _strip_color_markup(text)
	if not styled.error.is_empty():
		return styled
	var plain: String = styled.text
	var colors_at: Dictionary = styled.colors_at
	var lines: Array[Dictionary] = []
	var glyphs: Array[Dictionary] = []
	var line_width := 0.0
	var color: Color = default_color
	for index in range(plain.length()):
		if colors_at.has(index):
			var span: Variant = colors_at[index]
			color = default_color if span == null else span
		var character := plain[index]
		if character == "\n":
			lines.append(_finish_line(glyphs, line_width, width, false, justify))
			glyphs = []
			line_width = 0.0
			continue
		var codepoint := character.unicode_at(0)
		if codepoint < 32 or not font.has_char(codepoint):
			return {"error": "Native text has an unavailable glyph or control: U+%04X." % codepoint}
		# The original renderer skips leading ASCII spaces and gives each remaining space six pixels.
		if character == " " and glyphs.is_empty():
			continue
		var advance := SINGLE_BYTE_WIDTH if codepoint < 128 else DOUBLE_BYTE_WIDTH
		if width > 0.0 and advance > width:
			return {"error": "Native text line is narrower than a glyph."}
		if width > 0.0 and not glyphs.is_empty() and line_width + advance > width:
			lines.append(_finish_line(glyphs, line_width, width, true, justify))
			glyphs = []
			line_width = 0.0
			if character == " ":
				continue
		glyphs.append({"character": character, "x": line_width, "advance": advance,
			"color": color, "text_index": index})
		line_width += advance
	if lines.is_empty() or not plain.ends_with("\n"):
		lines.append(_finish_line(glyphs, line_width, width, false, justify))
	return {"error": "", "lines": lines}


## 剥离颜色标记，返回正文、按正文下标记录的颜色切换点以及纯文本长度。
## 颜色切换点的值为 null 表示颜色在该处回到调用方给出的默认色。
static func _strip_color_markup(text: String) -> Dictionary:
	var plain := ""
	var colors_at: Dictionary = {}
	var open := false
	var offset := 0
	while offset < text.length():
		if text.substr(offset, 7) == "[color=":
			if open:
				return {"error": "Native text color spans must not nest."}
			var close := text.find("]", offset)
			if close < 0:
				return {"error": "Native text color span is unterminated."}
			var literal := text.substr(offset + 7, close - offset - 7)
			if literal.length() != 7 or not literal.begins_with("#") or \
					not literal.substr(1).is_valid_hex_number():
				return {"error": "Native text color span requires a #RRGGBB value."}
			colors_at[plain.length()] = Color8(literal.substr(1, 2).hex_to_int(),
				literal.substr(3, 2).hex_to_int(), literal.substr(5, 2).hex_to_int())
			open = true
			offset = close + 1
			continue
		if text.substr(offset, 8) == "[/color]":
			if not open:
				return {"error": "Native text color span ends without a start."}
			colors_at[plain.length()] = null
			open = false
			offset += 8
			continue
		plain += text[offset]
		offset += 1
	if open:
		return {"error": "Native text color span is unterminated."}
	return {"error": "", "text": plain, "colors_at": colors_at}


static func _finish_line(glyphs: Array[Dictionary], natural_width: float, width: float,
		soft_wrap: bool, justify: bool) -> Dictionary:
	var trailing_space: bool = soft_wrap and not glyphs.is_empty() and glyphs[-1].character == " "
	var content_width := natural_width - (SPACE_WIDTH if trailing_space else 0.0)
	var spaces := 0
	for index in range(glyphs.size()):
		if glyphs[index].character == " " and not (trailing_space and index == glyphs.size() - 1):
			spaces += 1
	var remaining := maxi(0, int(floorf(width - content_width))) if justify and soft_wrap else 0
	var expansion := 0
	var text := ""
	for index in range(glyphs.size()):
		var glyph: Dictionary = glyphs[index]
		glyph.x += expansion
		text += glyph.character
		if remaining > 0 and glyph.character == " " and \
				not (trailing_space and index == glyphs.size() - 1):
			var extra := int(remaining / float(spaces))
			expansion += extra
			remaining -= extra
			spaces -= 1
	return {"text": text, "glyphs": glyphs, "width": content_width + expansion, "soft_wrap": soft_wrap}
