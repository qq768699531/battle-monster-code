extends "res://tests/unit/gut_case.gd"

## 原生 `Field_Warp1_mKeyPressed`：−3／−4 把光标 `(光标 + 1) % 2`；−5 只在光标 0（是）时
## 写 `warp_saved_*` 并登船（本页只发 `board_requested`）；光标 1 与 −16 都只是关窗。

const WarpConfirmScene = preload("res://game/field/map/warp_confirm/warp_confirm.tscn")
const WarpConfirm = preload("res://game/field/map/warp_confirm/warp_confirm.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")


func _settle(page: Control, visible: bool) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible == visible and not page.is_transitioning():
			return


func test_legacy_suite() -> void:
	var page: Control = WarpConfirmScene.instantiate()
	get_tree().root.add_child(page)
	watch_signals(page)
	# `Menu_win_Box2_DrawSelect:44`：高 = `13 × 折行数 + 33 + 11`（标题参数是 nullptr），
	# 公式只有 `ConfirmLayout` 一份：两行 70（与 `inn.tscn` 两行 fxt 90 的 160×70 同尺寸）、单行 57。
	var content: Control = page.get_node("Content")
	assert_eq([WarpConfirm.layout(content, ["一", "二"]), WarpConfirm.layout(content, ["一"])],
		[ConfirmLayout.select_size(160, 2), ConfirmLayout.select_size(160, 1)],
		"确认框高度按正文折行数算：13 × 行数 + 33 + 11")
	var rows: Control = page.get_node("Content/Lines")
	assert_eq([rows.position, rows.size], [Vector2(128, 102), Vector2(144, 13)],
		"正文框在 (窗x+8, 窗y+11)、宽 144（`width − 16` 的折行宽度）")
	var assets := get_node("/root/AssetCatalog")
	page.open(assets)
	await _settle(page, true)
	assert_eq(int(page.get("cursor")), WarpConfirm.Answer.YES,
		"Field_Warp1_init 不动光标：开窗后停在左键「是」")

	page.handle_key("ArrowRight")
	page.handle_key("Enter")
	await _settle(page, false)
	assert_true(int(page.get("cursor")) == WarpConfirm.Answer.NO and
		get_signal_emit_count(page, "board_requested") == 0,
		"方向键切到「否」后确认只关窗，不发 board_requested")

	page.open(assets)
	await _settle(page, true)
	page.handle_key("Enter")
	await _settle(page, false)
	assert_true(get_signal_emit_count(page, "board_requested") == 1 and not page.visible,
		"光标在「是」时确认发 board_requested 并走完关窗")
