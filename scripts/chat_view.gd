extends Control
## Native CHT window, speaker portrait, and text projection.

## 正文控制码引擎（`#C`／`#P`／`[color=…]`）只有 `components/message_stack.gd` 一处实现，
## 对话正文复用同一份：`JC_fntDrawText:265-274` 换调色板下标、`JC_fntSetPALETTE` 定义调色板。
const MessageText = preload("res://scripts/components/message_stack.gd")

const CHAT_WINDOW := Rect2(1, 184, 398, 55)
const TEXT_PAGE_LINE_COUNT := 2
const TEXT_FONT_SIZE := 10
## 对话页独有的面板键：EXIT（退出对话）。确认键用通用的 `TouchCode.Key.OK`。
enum TouchKey {
	EXIT = 35,
}
const DIALOGUE_CONFIRM_BUTTON := Rect2(350, 10, 40, 40)
const DIALOGUE_EXIT_BUTTON := Rect2(10, 10, 40, 40)
const DIALOGUE_BODY_TOUCH := Rect2(0, 60, 400, 180)
const FACE_TEXT_OFFSETS := {
	5: 160, 6: 140, 9: 140, 47: 160, 49: 140,
}
const TEXT_SETTLE_TICKS := 4
## 原生把三种写法都当换行：`\n`（0x0A）、`\r\n`（0x0D 0x0A）、反斜杠 + `n`（0x5C 0x6E），
## 依据 `JC_fntGetSPACE:70-92` 与 `JC_fntDrawText:290-307`。
const LINE_BREAK_TEXT := "\n"
const ESCAPED_LINE_BREAK_LEAD := "\\"
const ESCAPED_LINE_BREAK_FOLLOW := "n"
## 折行插进去的换行字符没有字形；这个颜色只用来占住 `relative_index` 的位置。
const INSERTED_LINE_BREAK_COLOR := Color("#FFFFFF")

var last_error := ""
var portrait_id := 999
var portrait_action := -1
var portrait_flags := 0
var portrait_position := Vector2.ZERO
var portrait_layers: Node2D
var _catalog: Object
var _portrait_sprites: Array[Sprite2D] = []
var _corner_sprites: Array[Sprite2D] = []
var _touch_sprites: Array[Sprite2D] = []
var _speaker_label: Label
var _text_label: RichTextLabel
var _record_key: Array = []
var _text_pages: Array[String] = []
var _text_page_colors: Array[PackedColorArray] = []
var _text_page_index := 0
var _visible_characters := 0
var _text_elapsed := 0.0
var _font: Font
var _portrait_loaded := false
var _portrait_action_valid := false
var _portrait_render_action := -1
var _entry_frame := 0
@onready var _portrait: Node2D = $PortraitLayers/PortraitAnimation
@onready var _entry_player: AnimationPlayer = $PortraitEntry


func _ready() -> void:
	hide()
	_catalog = get_node_or_null("/root/AssetCatalog")
	portrait_layers = $PortraitLayers
	_portrait.set_manual(true)
	_entry_player.play(&"enter")
	_entry_player.seek(_entry_player.current_animation_length, true)
	_entry_player.pause()
	for corner: Sprite2D in $Corners/Left.get_children():
		_corner_sprites.append(corner)
	for button in [$Confirm, $Exit]:
		for sprite: Sprite2D in button.get_node("Visuals").get_children():
			_touch_sprites.append(sprite)
	_speaker_label = $Speaker
	_text_label = $TextLayouts/LeftNormal
	_font = _text_label.get_theme_font("normal_font")


static func original_layout(flags: int, portrait_resource_loaded: bool,
		entry_frame: int, portrait: int) -> Dictionary:
	var side := flags & 1
	var face_x := CHAT_WINDOW.position.x + CHAT_WINDOW.size.x - 159 + 16 * entry_frame \
		if side != 0 else CHAT_WINDOW.position.x + 159 - 16 * entry_frame
	var text_offset := 6
	if side == 0 and portrait_resource_loaded:
		text_offset = int(FACE_TEXT_OFFSETS.get(portrait, 120))
	return {
		"window": CHAT_WINDOW,
		"portrait_anchor": Vector2(face_x, CHAT_WINDOW.position.y + CHAT_WINDOW.size.y + 1),
		"portrait_direction": 0 if side != 0 else 1,
		"speaker_origin": CHAT_WINDOW.position.x + 37 if side != 0 else \
			CHAT_WINDOW.position.x + CHAT_WINDOW.size.x - 37,
		"text_origin": Vector2(CHAT_WINDOW.position.x + text_offset,
			CHAT_WINDOW.position.y + 20),
	}


static func text_page_width(portrait: int) -> float:
	return maxf(0.0, 400.0 - 16.0 - int(FACE_TEXT_OFFSETS.get(portrait, 120)))


static func dialogue_touch_key(point: Vector2) -> int:
	if DIALOGUE_CONFIRM_BUTTON.has_point(point) or DIALOGUE_BODY_TOUCH.has_point(point):
		return TouchCode.Key.OK
	if DIALOGUE_EXIT_BUTTON.has_point(point):
		return TouchKey.EXIT
	return 0


func set_touch_key(key: int) -> void:
	$Confirm.set_pressed(key == TouchCode.Key.OK)
	$Exit.set_pressed(key == TouchKey.EXIT)


func touch_key(point: Vector2) -> int:
	if $Confirm.get_rect().has_point(point) or $BodyTouch.get_rect().has_point(point):
		return TouchCode.Key.OK
	return TouchKey.EXIT if $Exit.get_rect().has_point(point) else 0


func configure(catalog: Object) -> void:
	_catalog = catalog


func present_record(record: Dictionary, speaker: String, record_identity: int = -1) -> void:
	var id := int(record.get("portrait_id", 999))
	var animation_1based := int(record.get("portrait_animation_1based", 1))
	var flags := int(record.get("flags", 0))
	# 正文槽为 null 时原生 `JC_fntGetPage:12-14` 返回 0、`Evt_chtDRAW:16` 只画窗口不画字形，
	# 所以没有正文就是空正文：不拿占位串冒充原文。
	var text := ""
	if record.get("text") is String:
		text = record.text
	else:
		last_error = "CHT record has no body text: %d" % record_identity
	var key := [record_identity, id, animation_1based, flags, text, speaker]
	if key == _record_key:
		return

	var previous_portrait := portrait_id
	var previous_action := portrait_action
	var previous_flags := portrait_flags
	_record_key = key
	portrait_id = id
	portrait_action = (animation_1based - 1) & 255
	portrait_flags = flags & 1
	_entry_player.stop()
	_entry_player.play(&"enter")
	_entry_player.advance(0.0)
	if previous_portrait == id or id == 999:
		_entry_player.seek(_entry_player.current_animation_length, true)
	if previous_portrait != id or previous_action != portrait_action:
		_load_portrait()
	elif previous_flags != portrait_flags:
		_render_portrait()
	_update_layout()
	_speaker_label.text = speaker if not speaker.is_empty() else "???"
	_paginate_body(text)
	_text_page_index = 0
	_visible_characters = 0
	_text_elapsed = 0.0
	_update_text_page()
	visible = true
	queue_redraw()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0:
		return
	if not visible:
		return
	_portrait.advance(delta)
	if _portrait_loaded:
		_portrait_sprites.assign(_portrait.visible_sprites())
	if _entry_frame > 0:
		_entry_player.advance(delta)
		_update_layout()
		return
	# 逐字间隔就是 `text_character` 的长度：原生 `Evt_chtPROC:14-15` 每帧把
	# `visible_byte_limit_bits` 加 4（＝ 2 个双字节字形），帧间隔 50 ms（`EFC_thrPLAY:3-5`），
	# 所以一个字的时长是 0.025 s。
	var text_interval := _entry_player.get_animation(&"text_character").length
	_text_elapsed += minf(delta, text_interval)
	if _text_elapsed + 0.000000001 < text_interval:
		return
	_text_elapsed = maxf(0.0, _text_elapsed - text_interval)
	if not is_text_page_complete():
		_visible_characters += 1
		_update_text_page()


func is_text_page_complete() -> bool:
	return _current_page_text().is_empty() or \
		_visible_characters >= _current_page_text().length() + TEXT_SETTLE_TICKS


func has_more_text_pages() -> bool:
	return _text_page_index + 1 < _text_pages.size()


func reveal_text_page() -> void:
	_visible_characters = _current_page_text().length() + TEXT_SETTLE_TICKS
	_update_text_page()


func advance_text_page() -> bool:
	if not has_more_text_pages():
		return false
	_text_page_index += 1
	_visible_characters = 0
	_text_elapsed = 0.0
	_update_text_page()
	return true


func clear_dialogue() -> void:
	_record_key.clear()
	_text_pages.clear()
	_text_page_colors.clear()
	_text_page_index = 0
	_visible_characters = 0
	_text_elapsed = 0.0
	portrait_id = 999
	portrait_action = -1
	portrait_flags = 0
	_entry_frame = 0
	_entry_player.pause()
	_portrait_loaded = false
	_portrait_action_valid = false
	_portrait_render_action = -1
	_clear_portrait()
	visible = false


## 原生正文 → 「逐字 + 颜色」。`#C`／`#P`／`[color=…]` 由 `MessageText.text_segments()` 消费，
## 不进可见文本（`JC_fntDrawText:265-274`）；三种换行写法统一成 `\n`（`JC_fntGetSPACE:70-92`）。
static func body_glyphs(text: String) -> Array[Dictionary]:
	var glyphs: Array[Dictionary] = []
	for segment: Dictionary in MessageText.text_segments(text):
		var color := MessageText.rgb_color(int(segment.rgb))
		var chunk := String(segment.text)
		for index in chunk.length():
			glyphs.append({"character": chunk[index], "color": color})
	var normalized: Array[Dictionary] = []
	var cursor := 0
	while cursor < glyphs.size():
		var entry: Dictionary = glyphs[cursor]
		var character := String(entry["character"])
		var color: Color = entry["color"]
		if character == "\r":
			# `\r\n` 只算一次换行（`JC_fntDrawText:292-295`）。
			if cursor + 1 < glyphs.size() and \
					String(glyphs[cursor + 1]["character"]) == "\n":
				cursor += 1
			normalized.append({"character": LINE_BREAK_TEXT, "color": color})
		elif character == ESCAPED_LINE_BREAK_LEAD and cursor + 1 < glyphs.size() \
				and String(glyphs[cursor + 1]["character"]) == ESCAPED_LINE_BREAK_FOLLOW:
			normalized.append({"character": LINE_BREAK_TEXT, "color": color})
			cursor += 1
		else:
			normalized.append({"character": character, "color": color})
		cursor += 1
	return normalized


## 原生 `Evt_chtINIT:85` → `JC_fntGetPage(page, 正文, 行宽, 5, 2)`：每页 2 行、行距额外 5 px
## （`JC_fntSetPage:15-30` 每数满 `page_line_limit_bits` 行就记一次页起点）。
## 折行按 10px 字号的实宽量，宽度取自当前文本通道的矩形。
func _paginate_body(text: String) -> void:
	var width := _dialogue_text_width()
	var lines: Array[Array] = []
	var line: Array = []
	var line_text := ""
	for glyph: Dictionary in body_glyphs(text):
		var character := String(glyph["character"])
		if character == LINE_BREAK_TEXT:
			lines.append(line)
			line = []
			line_text = ""
			continue
		var candidate := line_text + character
		if not line.is_empty() and _font.get_string_size(candidate,
				HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_FONT_SIZE).x > width:
			lines.append(line)
			line = []
			candidate = character
		line.append(glyph)
		line_text = candidate
	lines.append(line)
	_text_pages.clear()
	_text_page_colors.clear()
	for first_line in range(0, lines.size(), TEXT_PAGE_LINE_COUNT):
		var page := ""
		var colors := PackedColorArray()
		for offset in TEXT_PAGE_LINE_COUNT:
			var line_index := first_line + offset
			if line_index >= lines.size():
				break
			if offset > 0:
				page += LINE_BREAK_TEXT
				colors.append(INSERTED_LINE_BREAK_COLOR)
			for glyph: Dictionary in lines[line_index]:
				page += String(glyph["character"])
				colors.append(glyph["color"])
		_text_pages.append(page)
		_text_page_colors.append(colors)
	if _text_pages.is_empty():
		_text_pages.append("")
		_text_page_colors.append(PackedColorArray())


func _current_page_text() -> String:
	if _text_pages.is_empty() or _text_page_index < 0 or _text_page_index >= _text_pages.size():
		return ""
	return _text_pages[_text_page_index]


func _current_page_colors() -> PackedColorArray:
	if _text_page_colors.is_empty() or _text_page_index < 0 or \
			_text_page_index >= _text_page_colors.size():
		return PackedColorArray()
	return _text_page_colors[_text_page_index]


func _dialogue_text_width() -> float:
	return _text_label.size.x


func _update_text_page() -> void:
	var page := _current_page_text()
	var effect: RichTextEffect = _text_label.custom_effects[0]
	effect.present(page, _visible_characters, is_text_page_complete(), _current_page_colors())
	if _text_label.get_parsed_text() != page:
		_text_label.clear()
		_text_label.push_customfx(effect, {"byte_offsets": effect._byte_offsets.duplicate()})
		_text_label.add_text(page)
		_text_label.pop()
	_text_label.queue_redraw()


func _position_corners() -> void:
	$Corners/Left.visible = portrait_flags == 0
	$Corners/Right.visible = portrait_flags != 0
	_corner_sprites.clear()
	for side in $Corners.get_children():
		for corner: Sprite2D in side.get_children():
			if side.visible:
				_corner_sprites.append(corner)


func _load_portrait() -> void:
	_clear_portrait()
	_portrait_loaded = false
	_portrait_action_valid = false
	_portrait_render_action = -1
	last_error = ""
	if portrait_id == 999:
		return
	var path := "face/fc%02d" % portrait_id
	if not ResourceLoader.exists(_portrait.scene_path(path)):
		_fail("Native portrait animation is not registered: %s." % path)
		return
	_portrait_loaded = true
	# Object_drawBASIC retries action zero when the requested action has no frames.
	if not _portrait.present(path, portrait_action, 1 if portrait_flags == 0 else 0,
			true, false, 0):
		_fail(_portrait.last_error)
		return
	_portrait_render_action = _portrait.playback_state().action
	_portrait_action_valid = true
	_render_portrait()


func _render_portrait() -> void:
	if not _portrait_loaded or not _portrait_action_valid:
		return
	var path := "face/fc%02d" % portrait_id
	_portrait.present(path, _portrait_render_action, 1 if portrait_flags == 0 else 0)
	portrait_position = _portrait_anchor()
	portrait_layers.position = portrait_position
	_portrait_sprites.clear()
	_portrait_sprites.assign(_portrait.visible_sprites())


func _clear_portrait() -> void:
	if not is_instance_valid(portrait_layers):
		return
	_portrait.clear()
	_portrait_sprites.clear()


func _update_layout() -> void:
	portrait_position = _portrait_anchor()
	portrait_layers.position = portrait_position
	_position_corners()
	$Window.set_portrait_side(portrait_flags != 0)
	$Speaker.visible = portrait_flags == 0
	$SpeakerLeft.visible = portrait_flags != 0
	_speaker_label = $SpeakerLeft if portrait_flags != 0 else $Speaker
	for label: RichTextLabel in $TextLayouts.get_children():
		label.hide()
	var lane := "Normal"
	match int(FACE_TEXT_OFFSETS.get(portrait_id, 120)):
		140: lane = "Wide"
		160: lane = "Widest"
	if not _portrait_loaded:
		_text_label = $TextLayouts/NoPortrait
	else:
		var side := "Right" if portrait_flags != 0 else "Left"
		_text_label = $TextLayouts.get_node(side + lane)
	_update_text_page()
	_text_label.visible = _entry_frame == 0


func _portrait_anchor() -> Vector2:
	var anchor: Marker2D = $RightPortraitAnchor if portrait_flags != 0 else $LeftPortraitAnchor
	return anchor.position + $PortraitEntryOffset.position * (1 if portrait_flags == 0 else -1)



func _fail(message: String) -> void:
	if last_error == message:
		return
	last_error = message
	push_warning(message)
