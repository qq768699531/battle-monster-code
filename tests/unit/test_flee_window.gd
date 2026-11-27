extends "res://tests/unit/gut_case.gd"

const FleeScene = preload("res://game/battle/combat/flee/flee.tscn")

var _flee
var _chosen: Array[bool] = []


func before_each() -> void:
	super()
	_flee = FleeScene.instantiate()
	add_child_autofree(_flee)
	_chosen = []
	_flee.chosen.connect(func(accepted: bool) -> void: _chosen.append(accepted))
	_flee.present_select("要逃跑吗?")


## 原生 `Battle_Run_init` 把光标初值置 1，即默认停在「否」。
func test_select_page_starts_on_no() -> void:
	assert_eq(_flee.selection(), 1, "光标默认在「否」")


## 原生 `Menu_win_Box2_DrawSelect` 的触控键按光标分配：光标不在的那颗发方向键，只移光标。
func test_press_on_other_button_only_moves_the_cursor() -> void:
	(_flee.get_node("Content/Yes") as Button).pressed.emit()
	assert_eq(_flee.selection(), 0, "第一次按下只把光标移到「是」")
	assert_eq(_chosen.size(), 0, "光标不在「是」时按下不算确认")


## 光标已经在的那颗键，按下即确认；换一颗键要按两次。
func test_press_on_cursor_confirms() -> void:
	(_flee.get_node("Content/No") as Button).pressed.emit()
	assert_eq(_chosen, [false] as Array[bool], "光标在「否」，一次按下就确认")
	(_flee.get_node("Content/Yes") as Button).pressed.emit()
	assert_eq(_flee.selection(), 0, "点「是」先把光标移过去")
	assert_eq(_chosen.size(), 1, "移光标不算确认")
	(_flee.get_node("Content/Yes") as Button).pressed.emit()
	assert_eq(_chosen, [false, true] as Array[bool], "再点一次才确认「是」")
