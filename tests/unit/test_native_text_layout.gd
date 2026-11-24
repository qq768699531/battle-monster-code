extends "res://tests/unit/gut_case.gd"

const Layout = preload("res://core/native_text_layout/native_text_layout.gd")
const View = preload("res://prime/prime_view/prime_view.gd")


func test_legacy_suite() -> void:
	var font: Font = View.UI_FONT
	var white := Color8(240, 240, 240)
	var accent := Color8(240, 176, 144)
	var width := 2.0 * Layout.DOUBLE_BYTE_WIDTH + Layout.SPACE_WIDTH + 5.0
	var styled := Layout.layout(
		"[color=#F0B090]精 [/color][color=#F0F0F0]灵状态[/color]\n[color=#F0B090]帮助[/color]",
		font, View.FONT_SIZE, width, true)
	assert_true(styled.error.is_empty() and styled.lines.size() == 3 and
		styled.lines[0].text == "精 灵" and styled.lines[1].text == "状态" and
		styled.lines[0].glyphs[0].color == accent and styled.lines[0].glyphs[2].color == white,
		"inline colors and native cells survive soft wrapping")
	var invalid := Layout.layout("[color=#F0B090]帮助", font, View.FONT_SIZE)
	assert_true(not invalid.error.is_empty(), "unterminated color spans are rejected")
