extends "res://tests/unit/gut_case.gd"

const BoxScene = preload("res://engine/ui/confirm_box/confirm_box.tscn")
const Box = preload("res://engine/ui/confirm_box/confirm_box.gd")
const Msg = preload("res://engine/ui/msg/msg.gd")

var _box


func before_each() -> void:
	super()
	_box = BoxScene.instantiate()
	add_child_autofree(_box)


## 原生 `Menu_win_Box2_DrawSelect`：窗高 `13 × 折行数 + 33 + 11`，点线在正文末行下 5 px，
## 两颗 44×16 键在点线下 5 px；确定页换成一颗居中键。
func test_select_layout_matches_the_native_box2() -> void:
	_box.present_select("要逃跑吗?")
	var yes: Button = _box.get_node("Content/Yes")
	var no: Button = _box.get_node("Content/No")
	var confirm: Button = _box.get_node("Content/Confirm")
	assert_eq(_box.window_size, Vector2i(160, 13 + 33 + 11), "单行 160 窗高 57")
	assert_eq([_box.get_node("Content/Divider").offset_top, yes.offset_top], [29.0, 34.0],
		"点线与按键按 ConfirmLayout 的 5 px 间隔摆")
	assert_eq([yes.visible, no.visible, confirm.visible], [true, true, false],
		"选择页是「是／否」，没有确定键")


func test_ok_form_swaps_to_the_single_confirm_key() -> void:
	_box.present_message("全部复活了")
	var confirm: Button = _box.get_node("Content/Confirm")
	assert_eq([_box.form(), _box.get_node("Content/Yes").visible,
		_box.get_node("Content/Confirm").visible], [Box.Form.OK, false, true],
		"确定页只留确定键")
	assert_eq(confirm.get_node("Choice/Caption").text,
		_box.get_node("/root/AssetCatalog").text_message(Msg.SOURCE, Msg.Id.CONFIRM_OK),
		"确定键文案取原生 85／86 之外的 OK")
