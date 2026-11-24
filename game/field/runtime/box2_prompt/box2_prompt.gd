extends "res://engine/ui/window_transition/window_transition.gd"

## Box2 正文窗：一条正文 + 可选确认键，窗高按正文折行数算。
##
## 框体、相位与开合动画继承自 `window_transition.gd`（场景里 `kind` 固定 `BOX2`），本组件只加正文、
## 点线与确认键。两个原生绘制入口共用这一个组件：
## - `Menu_win_Box2_DrawMessage@0x4B918`（纯消息）：窗高 `13 × 折行数 + 18`，无点线、无确认键；
## - `Menu_win_Box2_DrawOk@0x4B11C`（消息 + 确认键）：窗高 `13 × 折行数 + 44`，
##   正文末行下方 5 px 点线，再下方 5 px 的 44×16 确认键。
## 两者正文都画在窗口 `(x + 8, y + 11)`、按 `宽度 − 16` 折行（`DrawMessage:22-35`、`DrawOk:37-63`）；
## 窗高只在 `components/confirm_layout.gd` 里算一份，本组件不写死高度，也不新增计时：
## `transition_finished` 来自开合动画本身，调用方等它回报 `opened` 之后才写盘或换文。

signal confirmed

const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")

## 确认键正文是 `Msg.SOURCE` 里 `Msg.Id.CONFIRM_OK` 这一条（`Menu_win_Box2_DrawOk` 的
## `JC_fxt2Return(138)`）；文本源标识统一走 `Msg.SOURCE`，本组件不再自带常量。

## 两段原生绘制入口。
enum Form {
	## `Menu_win_Box2_DrawMessage`：纯消息，没有点线与确认键。
	MESSAGE,
	## `Menu_win_Box2_DrawOk`：正文 + 点线 + 确认键。
	OK,
}

## 窗口宽度：`Menu_Option_mPaint` 与 `Field_Save_mPaint` 传的 `&width__0` 是地址 0xA0 的伪全局
## （imagebase 0，不可能是可写变量），`Menu_win_Box2_DrawMessage` 按值用首参，即立即数 0xA0＝160。
@export var width := 160

## 正文顶端、点线／确认键的间隔与确认键尺寸都用 `ConfirmLayout` 里那几个常量（Box2 三个绘制入口
## 共用一份，见 `components/confirm_layout.gd`）；正文左端 8 px 与折行宽 `宽度 − 16` 由场景里
## `Lines` 的锚点固定。

@onready var _assets: Node = get_node("/root/AssetCatalog")
@onready var _lines: Control = $Content/Lines
@onready var _divider: Control = $Content/Divider
@onready var _confirm: Button = $Content/Confirm

var _form := Form.MESSAGE
var _body := ""


func _ready() -> void:
	super()
	_confirm.pressed.connect(_confirm_pressed)


## 换文／换绘制入口：窗口保持当前相位，只按新的折行数重算窗高与正文。
## 原生层 1→2→3 就是这样在同一个窗口里换绘制入口，不重开。
func present(text: String, form: Form) -> void:
	_present(text, form, width)


## 按实测正文宽撑开的入口：原生 Box2 的窗宽是各页绘制入口的立即数（`Menu_Option_mPaint` 与
## `Field_Save_mPaint` 都是 0xA0 = 160），没有「按正文撑开」的形态。本工程的写盘失败文案
## （`Game_saveSAVE` 的返回码从不被读取，见 `Menu_Option_mPaint:41-43` 只有层 1／2／3）
## 用它把整句放进同一个框：窗宽取实测正文宽加左右留白，夹在原生窗宽与
## `ConfirmLayout.FIT_MAX_WIDTH` 之间，再按该宽度折行定高。
func present_fitted(text: String, form: Form) -> void:
	_present(text, form, _fitted_width(text))


## 实测正文宽：`NativeTextLayout` 的可见正文（颜色标记零宽）加正文左右留白。
func _fitted_width(text: String) -> int:
	var measured := Layout.UI_FONT.get_string_size(TextLayout.plain_text(text),
		HORIZONTAL_ALIGNMENT_LEFT, -1, Layout.FONT_SIZE).x
	return clampi(int(ceil(measured)) + ConfirmLayout.WRAP_INSET,
		width, ConfirmLayout.FIT_MAX_WIDTH)


func _present(text: String, form: Form, box_width: int) -> void:
	_form = form
	_body = text
	var lines: Array[String] = Layout.wrap_text(text, box_width - ConfirmLayout.WRAP_INSET, Layout.UI_FONT)
	window_size = ConfirmLayout.message_size(box_width, lines.size()) if form == Form.MESSAGE \
		else ConfirmLayout.ok_size(box_width, lines.size())
	_layout_body(lines.size())
	_lines.present(lines)
	# `text_line_list` 的行原型最小宽度是 196（给 196 宽的正文页用），而 Box2 窗的正文宽只有
	# `宽度 − 16`（160 窗即 144）。控件不能小于自身最小尺寸，`grow_horizontal = BOTH` 会把
	# 容器左右各撑 (196 − 144) / 2 = 26 px，正文就整体溢出窗框。所以把行宽下限归零，
	# 宽度交给场景里 `Lines` 的锚点（左 8、右 −8）。
	for index in range(1, _lines.get_child_count()):
		var row: Control = _lines.get_child(index)
		row.custom_minimum_size.x = 0.0
	_divider.visible = form == Form.OK
	_confirm.visible = form == Form.OK
	if form == Form.OK:
		_confirm.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.CONFIRM_OK), true)


## 当前正文原文；换行位置由折行算出，这里不保留拆行结果。
func body_text() -> String:
	return _body


func form() -> Form:
	return _form


## 确认键的全局矩形，就是原生 `EFC_mainTouchSET(-5, 1, xa - 22, …, 44, 16)` 那块触控区。
func confirm_rect() -> Rect2:
	return _confirm.get_global_rect()


func confirm_visible() -> bool:
	return _form == Form.OK and _confirm.visible


## 正文、点线与确认键的纵向摆位：三者都相对窗口顶边，行距 13 px 由 `ConfirmLayout` 给。
func _layout_body(lines: int) -> void:
	var text_bottom := ConfirmLayout.TEXT_INSET.y + ConfirmLayout.LINE_STEP * lines
	_lines.offset_top = ConfirmLayout.TEXT_INSET.y
	_lines.offset_bottom = text_bottom
	var rule_top := text_bottom + ConfirmLayout.RULE_GAP
	_divider.offset_top = rule_top
	_divider.offset_bottom = rule_top + ConfirmLayout.RULE_HEIGHT
	var choice_top := rule_top + ConfirmLayout.RULE_GAP
	_confirm.offset_top = choice_top
	_confirm.offset_bottom = choice_top + ConfirmLayout.CHOICE_SIZE.y


## 只有稳态的确认框响应按键：开窗动画期间与纯消息窗都不发 `confirmed`。
func _confirm_pressed() -> void:
	if not confirm_visible() or is_transitioning():
		return
	confirmed.emit()
