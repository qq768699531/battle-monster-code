extends "res://tests/unit/gut_case.gd"

const ChatView = preload("res://field/chat_view/chat_view.gd")
const CHAT_SCENE = preload("res://field/chat_view/chat_view.tscn")
const MessageText = preload("res://core/message_stack/message_stack.gd")


func test_legacy_suite() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var view := CHAT_SCENE.instantiate() as ChatView
	get_tree().root.add_child(view)
	view.configure(catalog)
	view.present_record({"portrait_id": 1, "portrait_animation_1based": 1,
		"flags": 0, "text": "对话文本"}, "说话人")
	assert_true(view.visible and view._text_label.get_parsed_text() == "对话文本" and
		view._speaker_label.text == "说话人" and view.get_node("Window/Left").visible,
		"presenting a record composes the native left frame with speaker and body text")
	var typing := not view.is_text_page_complete()
	# 原生 `Evt_chtPROC:14-15` 每帧把 `visible_byte_limit_bits` 加 4（2 个双字节字形），
	# 帧间隔 50 ms（`EFC_thrPLAY:3-5`）→ 0.025 s/字。
	assert_almost_eq(view._entry_player.get_animation(&"text_character").length, 0.025, 0.0001,
		"one character is revealed per 4 bytes of a 50 ms native frame")
	view.reveal_text_page()
	assert_true(typing and view.is_text_page_complete() and not view.advance_text_page(),
		"confirm reveals the current page without inventing an extra page")
	assert_true(ChatView.dialogue_touch_key(Vector2(200, 120)) == -5 and
		ChatView.dialogue_touch_key(Vector2(370, 30)) == -5 and
		ChatView.dialogue_touch_key(Vector2(30, 30)) == 35 and
		ChatView.dialogue_touch_key(Vector2(200, 30)) == 0,
		"dialogue touch keys follow the native hit rectangles")
	view.queue_free()


## 原生 `#C`／`#P` 只是配色码（`JC_fntDrawText:265-274`、`JC_fntSetPALETTE:16-33`），
## 反斜杠 + n 是换行（`JC_fntGetSPACE:83-92`）：两者都不能留在正文里。
func test_body_control_codes_and_missing_text() -> void:
	var catalog: Node = get_tree().root.get_node("AssetCatalog")
	var view := CHAT_SCENE.instantiate() as ChatView
	get_tree().root.add_child(view)
	view.configure(catalog)
	view.present_record({"portrait_id": 1, "portrait_animation_1based": 1, "flags": 0,
		"text": "#P0F0第一行\\n#C5第二行"}, "说话人", 1)
	assert_eq(view._text_label.get_parsed_text(), "第一行\n第二行",
		"body control codes are consumed and backslash-n becomes a line break")
	assert_eq(view.body_glyphs("#C5第二行")[0]["color"], MessageText.palette_color(5),
		"#C selects the palette entry instead of printing itself")
	view.present_record({"portrait_id": 1, "portrait_animation_1based": 1, "flags": 0},
		"说话人", 2)
	assert_true(view._text_label.get_parsed_text().is_empty(),
		"a record without body text stays empty instead of showing a placeholder")
	view.queue_free()
