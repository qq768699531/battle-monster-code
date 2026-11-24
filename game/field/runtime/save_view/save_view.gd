extends Control

## 原生 `Field_Save_*`（`FieldCanvas` 状态 2，`Field_Save_init` /
## `Field_Save_mRun` / `Field_Save_mPaint` / `Field_Save_mKeyPressed`）。
##
## 三段子状态：1 画 `Menu_win_Box2_DrawMessage` 的「数据存档ing...」（msg 39）；开窗计数走到 4 的
## 下一帧写盘并把子状态置 2；3 换 `Menu_win_Box2_DrawOk` 的「已存档」（msg 41）＋确认按钮。
## 确认／返回只在子状态 3 生效，`mRun` 在开窗计数回到 -4 时才把 `FieldCanvas` 切回行走。
## 原生写盘失败不做处理，本移植用同一个句柄的 msg 38「现在无法存档」代替「已存档」，不提交假成功。
##
## 窗口由共用组件 `components/box2_prompt` 承担（Box2 框体 + 两段绘制入口），本脚本只跑子状态、
## 写盘与确认：窗宽取 `Field_Save_mPaint` 的立即数 0xA0（160），窗高由 `ConfirmLayout` 按折行数算，
## 正文／点线／确认键的摆位全在组件里，这里不再摆位。

signal save_requested
signal closed

const Box2Prompt = preload("res://game/field/runtime/box2_prompt/box2_prompt.gd")

@onready var _window: Control = $Window

var messages: Dictionary = {}

var _substate := 0
var _saves := false
var _closing := false


func _ready() -> void:
	_window.transition_finished.connect(_transition_finished)
	_window.confirmed.connect(_accept)


## `message_id` 是开窗阶段显示的正文；`saves` 为真时开窗结束后先写盘，
## 再按 `finish_save()` 的结果换成 msg 41／38。`saves` 为假时直接把这条消息画成
## 带确认按钮的说明页（对应原生 `Game_infoInit` 的「现在无法存档」）。
func open(texts: Dictionary, message_id: int, saves: bool) -> void:
	messages = texts
	_saves = saves
	_closing = false
	_substate = 1 if saves else 3
	show()
	_window.present(_text(message_id),
		Box2Prompt.Form.MESSAGE if saves else Box2Prompt.Form.OK)
	_window.open_window()


## 写盘结果：成功换成「已存档」，失败换成「现在无法存档」。
func finish_save(saved: bool) -> void:
	if _substate != 2:
		return
	_substate = 3
	_window.present(_text(Msg.Id.FIELD_SAVE_DONE if saved else Msg.Id.FIELD_SAVE_UNAVAILABLE),
		Box2Prompt.Form.OK)


func press(key: String) -> bool:
	if key not in ["Enter", "Space", "Escape", "Backspace"]:
		return false
	if _substate != 3 or _closing:
		return false
	_accept()
	return true


## 确认只在子状态 3 注册（原生 DrawOk 的 `EFC_mainTouchSET(-5, …)` 矩形就是那个按钮），
## 开窗动画期间两块都不生效。
func accepts(point: Vector2) -> bool:
	return _substate == 3 and not _closing and not _window.is_transitioning() and \
		_window.confirm_visible() and _window.confirm_rect().has_point(point)


func substate() -> int:
	return _substate


func closing() -> bool:
	return _closing


func _accept() -> void:
	if _substate != 3 or _closing or _window.is_transitioning():
		return
	_closing = true
	_window.close_window()


## 原生 mRun：开窗计数到 4 的下一帧才写盘；关到底才回到行走。
func _transition_finished(opened: bool) -> void:
	if not opened:
		_substate = 0
		_closing = false
		hide()
		closed.emit()
		return
	if not _saves:
		return
	_substate = 2
	save_requested.emit()


func _text(message_id: int) -> String:
	var value: Variant = messages.get(message_id, "")
	return value if value is String else ""
