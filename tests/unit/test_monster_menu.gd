extends "res://tests/unit/gut_case.gd"

## 原生 `Game_Monster_List_mKeyPressed`：−1／−2 同一式 `(游标 + 1) % 2`；
## −5 按游标进 22（合成）／23（强化）；−16 立刻回野外，不播关窗。

const MonsterMenuScene = preload("res://field/monster_menu/monster_menu.tscn")

## `Game_Menu_List_Draw` 的填充色：`JC_grpSetRGB(0xE1B2F)`（24 位 `#0E1B2F`）。
const ROW_FILL := Color("#0e1b2f")
## `JC_grpDrawRoundRECT`／`JC_grpFillRoundRECT` 收 `&dword_0 + 1`（style 1）= 四角各切 1px。
const ROW_CORNER_RADIUS := 1


func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")
	var menu: Control = MonsterMenuScene.instantiate()
	get_tree().root.add_child(menu)
	watch_signals(menu)
	menu.present(assets)
	await RenderingServer.frame_post_draw

	var rows: Array = []
	for index in range(2):
		rows.append(menu.get_node("Content/Option%d/Label" % index).text)
	assert_true(rows == [assets.text_message(Msg.SOURCE, Msg.Id.MONSTER_MIX),
		assets.text_message(Msg.SOURCE, Msg.Id.MONSTER_ENCHANT)] and int(menu.get("cursor")) == 0,
		"Game_Monster_List_mPaint draws the fixed msg 103/104 rows and init leaves the cursor at 0")

	menu.handle_key("ArrowDown")
	var after_one_step: int = int(menu.get("cursor"))
	menu.handle_key("ArrowDown")
	assert_true(after_one_step == 1 and int(menu.get("cursor")) == 0,
		"-1 and -2 share the same (cursor + 1) % 2 expression, so two steps return to the first row")

	# 行样式：原生是 1px 切角的圆角矩形（不是 option_card 默认的圆角 3／2）。
	var fill: StyleBoxFlat = menu.get_node("Content/Option0/Fill").get_theme_stylebox("panel")
	var inner: StyleBoxFlat = menu.get_node("Content/Option0/Inner").get_theme_stylebox("panel")
	assert_true(fill.bg_color.is_equal_approx(ROW_FILL)
		and fill.corner_radius_top_left == ROW_CORNER_RADIUS
		and inner.corner_radius_top_left == ROW_CORNER_RADIUS,
		"rows use the native fill #E1B2F with a 1px corner chamfer on both the fill and the border rings")

	menu.handle_key("ArrowDown")
	menu.handle_key("Enter")
	var confirmed: bool = get_signal_emit_count(menu, "selected") == 1 and \
		get_signal_parameters(menu, "selected") == ["enchant"]
	# 确认后本页即作废（原生 `-5` 直接 `SetNext`），CLR 的瞬时关闭要单独验一次。
	menu.present(assets)
	menu.handle_key("Escape")
	assert_true(confirmed and get_signal_emit_count(menu, "closed") == 1,
		"-5 on cursor 1 enters GAME_STATE_MONSTER_ENCHANT and -16 closes the page right away")
