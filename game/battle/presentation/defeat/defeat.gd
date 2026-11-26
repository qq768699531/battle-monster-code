extends "res://engine/ui/window_transition/window_transition.gd"
## 战斗全灭（原生状态 28 DIE，`Battle_Die_*`）的 Box2 窗口。
##
## 原生三个绘制入口共用同一个窗口，只换正文与按键：
## - `Menu_win_Box2_DrawSelect`：子状态 3「使用%s[%s]复活吗?」（`msg.fxt` 23）与
##   子状态 2／6「返回主菜单吗?」（36），正文下点线 + 是／否两颗 44×16；
## - `Menu_win_Box2_DrawOk`：子状态 4／8「全部复活了」（24）与子状态 5
##   「使用100元的情报使用费可以复活」（25），正文下点线 + 一颗 44×16 确定键。
## 子状态 1 的正文取 `Item_datBasic` 的道具说明（本工程的文本表没有该说明，故不单独出页）。
##
## `Battle_Die_init` 先 `Battle_info_Capture()` 把当前画面拍成模糊 + 半透明底，所以本窗用
## `screen_shade = true` 在开窗时挂那一层；窗高与正文摆位和其余 Box2 页共用 `ConfirmLayout`。

## 选择页（是／否）的结果：`accepted` 为是。
signal chosen(accepted: bool)
## 确定页（单个确认键）的结果。
signal confirmed

const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")

## 原生 `Menu_win_Box2_DrawOk` 与 `Menu_win_Box2_DrawSelect` 两种落键形态。
enum Form { OK, SELECT }

## 窗口宽度：`Menu_win_Box2_DrawSelect(&width__0, …)` 的立即数 160。
@export var width := 160

@onready var _assets: Node = get_node("/root/AssetCatalog")
@onready var _lines: Control = $Content/Lines
@onready var _divider: Control = $Content/Divider
@onready var _confirm: Button = $Content/Confirm
@onready var _yes: Button = $Content/Yes
@onready var _no: Button = $Content/No

var _form := Form.OK
var _body := ""
var _selected := 1


func _ready() -> void:
	super()
	_confirm.pressed.connect(_accept_pressed)
	_yes.pressed.connect(_choose.bind(true))
	_no.pressed.connect(_choose.bind(false))


## 原生 `Menu_win_Box2_DrawOk`：一段正文 + 点线 + 确定键。
func present_message(text: String) -> void:
	_present(text, Form.OK, 0)


## 原生 `Menu_win_Box2_DrawSelect`：一段正文 + 点线 + 是／否。`selected` 默认落在「否」。
func present_select(text: String, selected: int = 1) -> void:
	_present(text, Form.SELECT, selected)


## 换正文／换绘制入口：窗口保持当前相位，只按新的折行数重算窗高与正文。
## 原生状态 28 的子状态 3 → 4、5 → 7 → 8 就是这样在同一个窗口里换入口，不重开。
func _present(text: String, form: Form, selected: int) -> void:
	_form = form
	_body = text
	_selected = 1 if selected != 0 else 0
	var lines: Array[String] = Layout.wrap_text(text, width - ConfirmLayout.WRAP_INSET, Layout.UI_FONT)
	window_size = ConfirmLayout.select_size(width, lines.size())
	_layout_body(lines.size())
	_lines.present(lines)
	# `text_line_list` 的行原型最小宽度是 196（给正文页用），不归零会把 160 窗撑开、正文溢出。
	for index in range(1, _lines.get_child_count()):
		var row: Control = _lines.get_child(index)
		row.custom_minimum_size.x = 0.0
	_divider.visible = true
	_confirm.visible = form == Form.OK
	_yes.visible = form == Form.SELECT
	_no.visible = form == Form.SELECT
	if form == Form.OK:
		_confirm.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.CONFIRM_OK), true)
	else:
		_refresh_choices()


## 正文、点线与按键的纵向摆位：三者都相对窗口顶边，行距 13 px 由 `ConfirmLayout` 给。
func _layout_body(lines: int) -> void:
	var text_bottom := ConfirmLayout.TEXT_INSET.y + ConfirmLayout.LINE_STEP * lines
	_lines.offset_top = float(ConfirmLayout.TEXT_INSET.y)
	_lines.offset_bottom = float(text_bottom)
	var rule_top := text_bottom + ConfirmLayout.RULE_GAP
	_divider.offset_top = float(rule_top)
	_divider.offset_bottom = float(rule_top + ConfirmLayout.RULE_HEIGHT)
	var choice_top := rule_top + ConfirmLayout.RULE_GAP
	for button: Button in [_confirm, _yes, _no]:
		button.offset_top = float(choice_top)
		button.offset_bottom = float(choice_top + ConfirmLayout.CHOICE_SIZE.y)


func _refresh_choices() -> void:
	_yes.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES), _selected == 0)
	_no.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO), _selected == 1)


func form() -> Form:
	return _form


func body_text() -> String:
	return _body


func selection() -> int:
	return _selected


## 方向盘左右移动光标（原生选择页只有两颗键：0 是、1 否）。
func move_selection(change: int) -> void:
	if _form != Form.SELECT or is_transitioning():
		return
	_selected = posmod(_selected + change, 2)
	_refresh_choices()


## 键盘 OK／触控确认：确定页直接回报，选择页把当前光标当成答案。
func accept() -> void:
	if is_transitioning():
		return
	if _form == Form.OK:
		confirmed.emit()
	else:
		chosen.emit(_selected == 0)


func _accept_pressed() -> void:
	accept()


func _choose(accepted: bool) -> void:
	if _form != Form.SELECT or is_transitioning():
		return
	chosen.emit(accepted)
