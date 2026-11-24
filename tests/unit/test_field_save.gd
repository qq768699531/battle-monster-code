extends "res://tests/unit/gut_case.gd"

## 原生 `Field_Save_*`（`Field_Save_init` / `mRun` / `mPaint`）：
## 开窗画 msg 39「数据存档ing...」→ 写盘 → msg 41「已存档」＋确认，确认后才关窗。

const SaveViewScene = preload("res://field/save_view/save_view.tscn")
const ConfirmLayout = preload("res://core/confirm_layout/confirm_layout.gd")


func test_legacy_suite() -> void:
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var texts: Dictionary = assets.text_messages(Msg.SOURCE)
	var view := SaveViewScene.instantiate()
	get_tree().root.add_child(view)
	var writes := [0]
	view.save_requested.connect(func() -> void:
		writes[0] += 1
		view.finish_save(true))
	view.open(texts, 39, true)
	assert_true(view.visible and view.substate() == 1 and
		view.get_node("Window").body_text() == texts[39],
		"开窗阶段先显示「数据存档ing...」")
	await get_tree().create_timer(0.3).timeout
	assert_true(writes[0] == 1 and view.substate() == 3 and
		view.get_node("Window").body_text() == texts[41],
		"开窗动画结束才写盘，并换成「已存档」＋确认")
	assert_eq(view.get_node("Window").window_size, ConfirmLayout.ok_size(160, 1),
		"「已存档」窗高按 `Menu_win_Box2_DrawOk` 的公式算，不再写死 160×57")
	var window: Control = view.get_node("Window")
	var row: Control = window.get_node("Content/Lines").get_child(1)
	assert_true(window.get_node("Bounds").get_global_rect().encloses(row.get_global_rect()),
		"正文行必须整行落在窗框内（行容器最小宽度 196 会把 144 宽的正文左右各撑 26 px）")
	assert_true(view.press("Escape") and view.closing(), "第三段按返回开始关窗")
	await get_tree().create_timer(0.3).timeout
	assert_true(not view.visible and view.substate() == 0, "关窗动画结束后收起")
