extends "res://engine/ui/confirm_box/confirm_box.gd"
## 原生 `Field_Inn_*`（`FieldCanvas` 状态 16，NPC 交互码 5）：
## `Field_Inn_init` 只把开窗计数 `MainData+0xD` 置 1（不动光标），
## `Field_Inn_mRun` 在关窗计数回到 −4 时 `FieldCanvas_SetNext(FIELD_STATE_BASIC, 0)`，
## `Field_Inn_mPaint` = `Map_Copy()` + `Menu_win_Box2_DrawSelect(160, null, fxt 90, 光标, &开窗计数)`，
## `Field_Inn_destroy` 是空的。
##
## 按键（`Field_Inn_mKeyPressed`）：`-3`／`-4` 把光标 `±1 % 2`；`-5` 且光标 0（是）时
## `ParamData.money_balance > 0x31`（≥ 50）就 `Ball_stdHP／Ball_stdSP(party_monsters[0..2], 100)`
## + `Param_moneySET(-50)`，文案取 fxt 89（`n79 = 79` 是默认值，只有成功才改成 89）；
## 之后无条件 `Field_Warp1_mKeyPressed(-16)` 关窗。光标 1（否）不产生任何文案，直接关窗。
##
## 原生把结果文案交给野外信息行（`Game_infoInit`），本场景是自包含页面，所以把同一份
## 文案换成正文画在同一个窗口里（确定页），按 OK／CLR 关窗。
##
## 窗框、折行、点线与按键摆位与落键都在 `engine/ui/confirm_box`，本页只保留原生出处与休息判定。

signal closed

var _catalog: Node
var _story: StoryRuntime
## 非 0 时是结果页（确定键），对应原生 `n79`。
var _result := 0
var _closing := false


func _ready() -> void:
	super()
	chosen.connect(_chosen)
	confirmed.connect(close)
	transition_finished.connect(_transition_finished)


## `assets` 提供 `text_message()`；`story` 是 `StoryRuntime`，`inn_rest()` 返回空串表示成功。
func present(assets: Node, story: StoryRuntime) -> void:
	_catalog = assets
	_story = story
	_result = 0
	_closing = false
	present_select(String(assets.text_message(Msg.SOURCE, Msg.Id.INN_PROMPT)), 0)
	show()
	open_window()


func close() -> void:
	if _closing:
		return
	_closing = true
	close_window()


func handle_key(key: String) -> bool:
	if is_transitioning() or _closing:
		return true
	if _result != 0:
		match key:
			"Enter", "Space", "Escape", "Backspace":
				close()
			_:
				return false
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			move_selection(-1)
		"Enter", "Space":
			accept()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


## 原生 −5 落在光标那颗上：是 → 休息（成功／钱不够的文案），否 → 关窗。
func _chosen(accepted: bool) -> void:
	if _closing or is_transitioning() or _result != 0:
		return
	if not accepted:
		close()
		return
	var failure: String = _story.inn_rest()
	_result = Msg.Id.SHOP_NOT_ENOUGH_MONEY if not failure.is_empty() else Msg.Id.INN_RESTORED
	present_message(String(_catalog.text_message(Msg.SOURCE, _result)))


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	_result = 0
	closed.emit()
