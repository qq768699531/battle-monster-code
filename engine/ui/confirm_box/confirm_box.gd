extends "res://engine/ui/window_transition/window_transition.gd"
## Box2 是否确认框：原生 `Menu_win_Box2_DrawSelect`（正文 + 点线 + 是／否）与
## `Menu_win_Box2_DrawOk`（正文 + 点线 + 一个确定键）两个绘制入口的共用实现。
##
## 页脚本继承本件，只传正文与形态；窗框开合、正文折行、点线与按键摆位、光标与落键都在这里：
## - 窗高：`ConfirmLayout.select_size(width, 折行数)`（两个入口同一个公式，`+33 + n11`）；
## - 正文：`Layout.wrap_text(text, width − 16, UI_FONT)` 折行后交给 `text_line_list`，顶在 `(8, 11)`；
## - 点线：正文末行下 5 px，`x + 4` 起、长 `宽 − 8`、1 px 高；
## - 按键：点线下 5 px、44×16，是／否分别居中于 `宽/4` 与 `3×宽/4`，确定键居中；
## - 落键：方向键换光标（`move_selection`），OK 把当前光标当答案（`accept`），CLR 在选择页等价「否」；
##   触控/鼠标按到非光标的那颗键只移光标，再按一次才确认（原生按光标分配触控键：选中那颗发 −5，另一颗发 −3／−4）。

## 选择页（是／否）的结果：`accepted` 为是。
signal chosen(accepted: bool)
## 确定页（单个确认键）的结果。
signal confirmed

const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")

## 两个绘制入口：`DrawOk` 一颗确定键、`DrawSelect` 是／否两颗。
enum Form { OK, SELECT }

## 窗宽：原生 `Menu_win_Box2_DrawSelect(&width__0, …)` 的 160；正文按 `宽 − 16` 折行。
@export var width := 160
## 提示上方还有一格内容（道具／数量／价格行，原生 `Field_Item_DrawSelect` 那三页）：
## 置 true 时正文顶固定 38、点线 53、按键 58（`ConfirmLayout.ITEM_SELECT_*`），窗高由页面自己给。
@export var header := false
## 带价格行时整套下移 12 px（`ConfirmLayout.ITEM_SELECT_PRICE_ROW`，买卖正文顶 50）。
@export var header_offset := 0

@onready var _assets: Node = get_node("/root/AssetCatalog")
@onready var _lines: Control = $Content/Lines
@onready var _divider: Control = $Content/Divider
@onready var _confirm: Button = $Content/Confirm
@onready var _yes: Button = $Content/Yes
@onready var _no: Button = $Content/No

var _form := Form.OK
var _body := ""
var _selected := 1
var _neutral := false


func _ready() -> void:
	super()
	transition_finished.connect(_transition_finished)
	_confirm.pressed.connect(accept)
	_yes.pressed.connect(_choose.bind(true))
	_no.pressed.connect(_choose.bind(false))


## 原生 `Menu_win_Box2_DrawOk`：一段正文 + 点线 + 确定键。
func present_message(text: String) -> void:
	_present(text, Form.OK, 0)


## 原生 `Menu_win_Box2_DrawSelect`：一段正文 + 点线 + 是／否。`selected` 默认落在「否」。
func present_select(text: String, selected: int = 1) -> void:
	_present(text, Form.SELECT, selected)


## 原生 `Field_Item_DrawSelect` 的数量相位：是／否两颗画出来但都不选中（光标还不在框里）。
func present_neutral(text: String) -> void:
	_present(text, Form.SELECT, 1)
	_neutral = true
	_refresh_choices()


## 方向盘左右换是／否（原生选择页只有两颗键：0 是、1 否）。
func move_selection(change: int) -> void:
	if _form != Form.SELECT or is_transitioning():
		return
	_selected = posmod(_selected + change, 2)
	_refresh_choices()


## OK／触控确认：确定页直接回报，选择页把当前光标当答案。
func accept() -> void:
	if is_transitioning():
		return
	if _form == Form.OK:
		confirmed.emit()
	else:
		chosen.emit(_selected == 0)


## CLR：选择页等价于「否」（原生 `Battle_Run_mKeyPressed` 的 answer = 0 走回 MENU）；
## 确定页与 OK 同义（`Battle_Run_mKeyPressed` 的子状态 1 把 CLR 和 OK 都当推进）。
func cancel() -> void:
	if is_transitioning():
		return
	if _form == Form.SELECT:
		chosen.emit(false)
	else:
		confirmed.emit()


func form() -> Form:
	return _form


func body_text() -> String:
	return _body


## 正文行的水平对齐（原生数量框 `Field_Item_DrawSelect` 的提示行是居中，普通消息仍是左对齐）。
## 行节点由 `text_line_list` 按需创建，所以要在 `present_*` 之后调用。`Plain` 是
## `plain_label`（用 `anchor` + 绘制原点对齐，没有宽度自适应的 `horizontal_alignment`），
## 所以居中时把绘制原点挪到行宽的一半；富文本行才用 `native_label.horizontal_alignment`。
func set_body_alignment(alignment: int) -> void:
	var width := _lines.size.x
	var origin := width * 0.5 if alignment == 1 else (width if alignment == 2 else 0.0)
	for index in range(1, _lines.get_child_count()):
		var row: Control = _lines.get_child(index)
		for path: String in ["Line/Normal/Plain", "Line/Indented/Plain"]:
			var label: Variant = row.get_node_or_null(path)
			if label == null:
				continue
			var plain := false
			for property: Dictionary in label.get_property_list():
				if property.name == "anchor":
					plain = true
					break
			if plain:
				label.set("anchor", alignment)
				label.position.x = origin
			else:
				label.horizontal_alignment = alignment


func selection() -> int:
	return _selected


## 宿主直接指定光标（原生各页的 cursor 与确认框共用同一个值）。
func set_selection(index: int) -> void:
	if _form != Form.SELECT:
		return
	_selected = 1 if index != 0 else 0
	_refresh_choices()


## 换正文／换绘制入口：窗口保持当前相位，只按新的折行数重算窗高与正文。
## 原生状态 28 的子状态 3 → 4、5 → 7 → 8 就是这样在同一个窗口里换入口，不重开。
func _present(text: String, form: Form, selected: int) -> void:
	_form = form
	_neutral = false
	_body = text
	_selected = 1 if selected != 0 else 0
	var lines: Array[String] = Layout.wrap_text(text, width - ConfirmLayout.WRAP_INSET, Layout.UI_FONT)
	if not header:
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
	if header:
		# `Field_Item_DrawSelect:117-169`：正文顶 38、点线 53、按键 58，三处都是固定值，不随行数走。
		var top := ConfirmLayout.ITEM_SELECT_TEXT_TOP + header_offset
		_lines.offset_top = float(top)
		_lines.offset_bottom = float(top + ConfirmLayout.LINE_STEP * lines)
		_divider.offset_top = float(ConfirmLayout.ITEM_SELECT_RULE_TOP + header_offset)
		_divider.offset_bottom = float(ConfirmLayout.ITEM_SELECT_RULE_TOP + header_offset + ConfirmLayout.RULE_HEIGHT)
		for button: Button in [_confirm, _yes, _no]:
			button.offset_top = float(ConfirmLayout.ITEM_SELECT_CHOICE_TOP + header_offset)
			button.offset_bottom = float(ConfirmLayout.ITEM_SELECT_CHOICE_TOP + header_offset + ConfirmLayout.CHOICE_SIZE.y)
		return
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
	_yes.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES),
		not _neutral and _selected == 0)
	_no.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO),
		not _neutral and _selected == 1)


## 触控/鼠标按下某一颗键：光标不在它上面时只把光标移过去（原生按光标分配触控键），
## 光标已经在的那颗才是确认。
func _choose(accepted: bool) -> void:
	if _form != Form.SELECT or is_transitioning():
		return
	var index := 0 if accepted else 1
	if index != _selected:
		_selected = index
		_refresh_choices()
		return
	chosen.emit(accepted)


## 收窗动画播完（相位 −4）才真正隐藏：页面收窗后不用再自己管可见性（原生关窗后整条不再绘制）。
func _transition_finished(opened: bool) -> void:
	if not opened:
		hide()
