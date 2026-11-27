extends "res://engine/ui/confirm_box/confirm_box.gd"
## 原生 `Field_Warp1_*`（`FieldCanvas` 状态 4，野外触控键 48 进）与 WARP2 的确认框：
## `Field_Warp1_mPaint:5-12` 是 `Menu_Copy()` + `Menu_win_Box2_DrawSelect(160, 标题 null,
## fxt 42「前往飞艇吗?」，光标 `FieldData+0x2C`)`——没有 Box4 调用，所以没有标题栏；
## WARP2 用同一个函数、只把正文换成 fxt 44（`Field_Warp2_mPaint:11-19`）。
## 背景只是 `JC_grpCopyFRAME` 的原样快照，没有灰阶／降饱和，也没有模糊层。
##
## 按键：`-3`／`-4` 把光标 `(光标 + 1) % 2`；`-5` 且光标 0（是）才写 `warp_saved_*`、把待定目的地
## 置地图 148 与 tile (7, 12)、播英雄 `direction 32` + ANI 10（宿主做，本页只发 `board_requested`）；
## `-16` 或确认之后关窗。本页**不换图、不写存档**——原生换图发生在英雄 ANI 10 播完之后。
##
## 窗框、折行、点线与按键摆位与落键都在 `engine/ui/confirm_box`，本页只保留原生出处与宿主协议。

## 用户要求关窗（Esc／「否」）：宿主据此回野外状态（原生关窗计数到 −4 才 `SetNext(BASIC)`）。
signal close_requested
## 关窗动画播完（窗口已隐藏）。
signal closed
## 确认「是」：宿主写 `warp_saved_*`、置待定目的地并播英雄登船动画。
signal board_requested

## `Menu_win_Box2_DrawSelect` 的 cursor（原生 `FieldData+0x2C`）：0 = 左「是」、1 = 右「否」。
enum Answer { YES, NO }

## 正文记录号：WARP1 是 fxt 42，WARP2 是 fxt 44——同一个确认框，只有正文不同。
var message_id := Msg.Id.WARP_BOARD_CONFIRM
## 由宿主接管收窗：WARP2 的确认框随整页一起消失（`Field_Warp2_mKeyPressed:26` 只把整页相位写 −1），
## 所以确认／取消后只发信号，不自己 `close()`。
var managed := false

var _catalog: Object
var _closing := false


func _ready() -> void:
	super()
	chosen.connect(_chosen)
	transition_finished.connect(_transition_finished)


## 宿主开窗：`catalog` 提供 `text_message()`（`common/msg.fxt` 的 42／44／85／86），
## `record` 是正文记录号，默认 WARP1 的 42。已在开合动画中时返回 false。
func open(catalog: Object, record: int = Msg.Id.WARP_BOARD_CONFIRM) -> bool:
	if visible or is_transitioning():
		return false
	_catalog = catalog
	message_id = record
	_closing = false
	present_select(String(_catalog.text_message(Msg.SOURCE, message_id)), Answer.YES)
	show()
	open_window()
	return true


## 宿主切光标：原生 `FieldData+0x2C` 的 cursor 与确认框共用同一个值。
func select(answer: int) -> void:
	set_selection(answer)


func close() -> void:
	if _closing or is_transitioning():
		return
	_closing = true
	close_window()


func closing() -> bool:
	return _closing


func handle_key(key: String) -> bool:
	if _closing or is_transitioning():
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			move_selection(-1)
		"Enter", "Space":
			accept()
		"Escape", "Backspace":
			cancel()
		_:
			return false
	return true


## 原生 −5：光标 0（是）登船，光标 1（否）只是关窗。
func _chosen(accepted: bool) -> void:
	if accepted:
		board_requested.emit()
		if not managed:
			close()
		return
	_request_close()


func _request_close() -> void:
	if _closing or is_transitioning():
		return
	close_requested.emit()
	if not managed:
		close()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	closed.emit()
