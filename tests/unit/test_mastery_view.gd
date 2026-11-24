extends "res://tests/unit/gut_case.gd"

const MasteryScene = preload("res://field/mastery_view/mastery_view.tscn")
const MasteryScript = preload("res://field/mastery_view/mastery_view.gd")
const ConfirmLayout = preload("res://core/confirm_layout/confirm_layout.gd")

## `Menu_CharacterSelect_Draw:56-61` 的六个流派名，详情页只用来摆位。
const MASTERY_NAMES: Array[String] = ["水", "火", "木", "风", "光", "暗"]


func test_legacy_suite() -> void:
	var view: Control = MasteryScene.instantiate()
	add_child_autofree(view)
	await get_tree().process_frame
	assert_true(view.present(MASTERY_NAMES),
		"一级页按六个流派名摆出候选行")
	assert_eq((view.get_node("Bounds/Title") as Control).text, "属性决定",
		"标题取 fxt 96（Menu_CharacterSelect_Draw:7）")
	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	view._input(press)
	assert_true(view._confirm == MasteryScript.ConfirmState.OPEN and
		(view.get_node("Confirm") as Control).visible and
		view._answer == MasteryScript.Answer.NO,
		"OK 打开 Box2 确认框并默认停在「否」（Game_Character_Select_mKeyPressed:28 写 1）")
	var confirm: Control = view.get_node("Confirm")
	for _frame in range(200):
		if not confirm.is_transitioning():
			break
		await get_tree().process_frame
	assert_eq(confirm.window_size, ConfirmLayout.select_size(MasteryScript.CONFIRM_WIDTH, 1),
		"确认框窗高按正文折行数算（Menu_win_Box2_DrawSelect:41-48，fxt 164 一行 = 160×57）")
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	view._input(right)
	assert_eq(view._answer, MasteryScript.Answer.YES, "框内左右翻到「是」")
	var back := InputEventKey.new()
	back.keycode = KEY_ESCAPE
	back.pressed = true
	view._input(back)
	assert_true(view._confirm == MasteryScript.ConfirmState.OPEN and confirm.is_transitioning(),
		"CLR 关框只起收拢：子相位仍是 1，框要等相位 -4 才落回列表")
	for _frame in range(200):
		if not confirm.is_transitioning():
			break
		await get_tree().process_frame
	assert_true(view._confirm == MasteryScript.ConfirmState.BROWSE and not confirm.visible,
		"收拢到 -4（transition_finished(false)）才回列表（Game_Character_Select_mRun）")
	# 触控：原生每格登记 −3／−4，光标格登记 −5（`Menu_CharacterSelect_Draw:156/168/203`），
	# 所以点已选那格等于按 OK 开确认框，点别的格只移光标。
	view.press_row(2)
	assert_eq(view.selected(), 2, "点非光标格只把光标移过去（−3／−4）")
	view.press_row(2)
	assert_true(view._confirm == MasteryScript.ConfirmState.OPEN,
		"点光标格等于按 OK（−5）：打开 Box2 确认框而不是直接提交")
	# 触控「否」走同一条 `_close_confirm()`：原生触控在框相位 1..4 与 -1..-3 都注册，
	# 所以开框动画里点「否」也只是起收拢，子相位到 -4 才清零。
	(view.get_node("Confirm/Content/No") as Button).pressed.emit()
	for _frame in range(200):
		if not confirm.is_transitioning():
			break
		await get_tree().process_frame
	assert_true(view._confirm == MasteryScript.ConfirmState.BROWSE and not confirm.visible,
		"触控「否」同样先播收拢、收拢完才回列表")
	# 二级页（状态 16）是图鉴页实例，见 test_book.gd；这里只核对一级页不再有第二页。
	assert_false(view.has_node("Content/StarterPage"),
		"二级页落到 book_monster（同一个 Game_Book_Monster），一级视图不再画第二份列表")
