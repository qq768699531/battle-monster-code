extends Control

## 原生 `Field_Save_*`（`FieldCanvas` 状态 2，`Field_Save_init` /
## `Field_Save_mRun` / `Field_Save_mPaint` / `Field_Save_mKeyPressed`）。
##
## 两扇窗：`SavingWindow` 画 `Menu_win_Box2_DrawMessage` 的「数据存档ing...」（msg 39），
## `Window` 画 `Menu_win_Box2_DrawOk` 的「已存档」（msg 41）＋确认键。写盘在存档窗开到底
## （相位 4）后进行；写完先把存档窗**收拢**，收拢结束再让「已存档」窗**展开**——两扇窗之间
## 因此有一段开合动画，而不是在同一扇窗里直接换字。关到底才把 `FieldCanvas` 切回行走。
## 原生写盘失败不做处理，本移植用同一套窗换成 msg 38「现在无法存档」，不提交假成功。
##
## 窗口由共用组件 `components/box2_prompt` 承担（Box2 框体 + 两段绘制入口），本脚本只跑子状态、
## 写盘与确认：窗宽取 `Field_Save_mPaint` 的立即数 0xA0（160），窗高由 `ConfirmLayout` 按折行数算，
## 正文／点线／确认键的摆位全在组件里，这里不再摆位。两扇窗都不自己管屏幕遮罩——存档页根节点
## 在 `open()` 里抓一次冻结帧并持有遮罩，整段两窗切换都压在同一张定格背景上。

signal save_requested
signal closed


const Box2Prompt = preload("res://game/field/runtime/box2_prompt/box2_prompt.gd")

@onready var _saving_window: Control = $SavingWindow
@onready var _window: Control = $Window

var messages: Dictionary = {}

var _substate := 0
var _saves := false
var _closing := false
## 存档窗收拢结束后要换成哪条正文（0 表示没有待切换的第三段）。
var _pending_done := 0


func _ready() -> void:
	_saving_window.transition_finished.connect(_saving_finished)
	_window.transition_finished.connect(_done_finished)
	_window.confirmed.connect(_accept)


## `message_id` 是 `SavingWindow` 开窗阶段显示的正文；`saves` 为真时开窗结束后先写盘，
## 再收拢存档窗、展开 msg 41／38 的「已存档」窗。`saves` 为假时直接把这条消息画成
## 带确认按钮的说明页（对应原生 `Game_infoInit` 的「现在无法存档」）。
func open(texts: Dictionary, message_id: int, saves: bool) -> void:
	messages = texts
	_saves = saves
	_closing = false
	_pending_done = 0
	_substate = 1 if saves else 3
	show()
	if saves:
		_window.hide()
		_saving_window.present(_text(message_id), Box2Prompt.Form.MESSAGE)
		_saving_window.show()
		_saving_window.open_window()
	else:
		_saving_window.hide()
		_present_done(message_id)


## 写盘结果：先把「数据存档ing...」窗收拢；收拢结束的 `_saving_finished(false)` 再展开
## msg 41「已存档」或 msg 38「现在无法存档」。
func finish_save(saved: bool) -> void:
	if _substate != 2:
		return
	_pending_done = Msg.Id.FIELD_SAVE_DONE if saved else Msg.Id.FIELD_SAVE_UNAVAILABLE
	_saving_window.close_window()


func press(key: String) -> bool:
	if key not in ["Enter", "Space", "Escape", "Backspace"]:
		return false
	if _substate != 3 or _closing or _window.is_transitioning():
		return false
	_accept()
	return true


## 确认只在第三段注册（原生 DrawOk 的 `EFC_mainTouchSET(-5, …)` 矩形就是那个按钮），
## 存档窗收拢／已存档窗展开期间两块都不生效。
func accepts(point: Vector2) -> bool:
	return _substate == 3 and not _closing and not _window.is_transitioning() and \
		_window.confirm_visible() and _window.confirm_rect().has_point(point)


func substate() -> int:
	return _substate


func closing() -> bool:
	return _closing


func _present_done(message_id: int) -> void:
	_window.present(_text(message_id), Box2Prompt.Form.OK)
	_window.show()
	_window.open_window()


func _accept() -> void:
	if _substate != 3 or _closing or _window.is_transitioning():
		return
	_closing = true
	_window.close_window()


## 存档窗：开到底（相位 4）的下一帧才写盘；收拢结束若有待切换正文，展开「已存档」窗。
func _saving_finished(opened: bool) -> void:
	if opened:
		if _substate != 1:
			return
		_substate = 2
		save_requested.emit()
		return
	_saving_window.hide()
	if _pending_done == 0:
		return
	var message_id := _pending_done
	_pending_done = 0
	_substate = 3
	_present_done(message_id)


## 「已存档」窗：关到底才回行走。
func _done_finished(opened: bool) -> void:
	if opened:
		return
	_substate = 0
	_closing = false
	_window.hide()
	hide()
	closed.emit()


func _text(message_id: int) -> String:
	var value: Variant = messages.get(message_id, "")
	return value if value is String else ""
