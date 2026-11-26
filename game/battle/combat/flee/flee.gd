extends "res://engine/ui/window_transition/window_transition.gd"
## 战斗逃跑窗（原生状态 18 `RUN`，`Battle_Run_*`）。同一个 Box2 160×57 窗有两页：
## - 子状态 0 `Menu_win_Box2_DrawSelect`：`msg.fxt` 7「要逃跑吗?」+ 是／否，
##   `Battle_Run_init` 把光标初值置 1（默认「否」）；
## - 子状态 1／2 `Menu_win_Box2_DrawOk`：`msg.fxt` 8「逃跑成功」／9「逃跑失败」+ 确定键。
## 原生落键后先把窗关上（相位 −1），`Battle_Run_mRun` 收到 −4 才重开窗显示结果，
## 所以调用方按「关 → 换文 → 开」两段驱动；第一页按 CLR 等价于「否」。

## 选择页（是／否）的结果：`accepted` 为是。
signal chosen(accepted: bool)
## 确定页（单个确认键）的结果。
signal confirmed

@onready var _assets: Node = get_node("/root/AssetCatalog")
@onready var _prompt: Control = $Content/Prompt
@onready var _yes: Button = $Content/Yes
@onready var _no: Button = $Content/No
@onready var _confirm: Button = $Content/Confirm

var _select := true
var _selected := 1


func _ready() -> void:
	super()
	_yes.pressed.connect(_choose.bind(true))
	_no.pressed.connect(_choose.bind(false))
	_confirm.pressed.connect(_confirm_pressed)


## 子状态 0：问题 + 是／否。
func present_select(text: String, selected: int = 1) -> void:
	_select = true
	_selected = 1 if selected != 0 else 0
	_prompt.text = text
	_yes.show()
	_no.show()
	_confirm.hide()
	_refresh_choices()


## 子状态 1／2：结果 + 确定键。
func present_message(text: String) -> void:
	_select = false
	_prompt.text = text
	_yes.hide()
	_no.hide()
	_confirm.show()
	_confirm.get_node("Choice").present(
		_assets.text_message(Msg.SOURCE, Msg.Id.CONFIRM_OK), true)


## 方向盘左右换是／否（原生选择页只有两颗键：0 是、1 否）。
func move_selection(change: int) -> void:
	if not _select or is_transitioning():
		return
	_selected = posmod(_selected + change, 2)
	_refresh_choices()


## OK／触控确认：选择页把当前光标当答案，确定页直接回报。
func accept() -> void:
	if is_transitioning():
		return
	if _select:
		chosen.emit(_selected == 0)
	else:
		confirmed.emit()


## CLR：选择页等价于「否」（原生 `Battle_Run_mKeyPressed` 的 answer = 0 走回 MENU）；
## 结果页与 OK 同义（`Battle_Run_mKeyPressed` 的子状态 1 把 CLR 和 OK 都当推进）。
func cancel() -> void:
	if is_transitioning():
		return
	if _select:
		chosen.emit(false)
	else:
		confirmed.emit()


func is_select() -> bool:
	return _select


func prompt_text() -> String:
	return _prompt.text


func selection() -> int:
	return _selected


func _choose(accepted: bool) -> void:
	if not _select or is_transitioning():
		return
	chosen.emit(accepted)


func _confirm_pressed() -> void:
	if _select or is_transitioning():
		return
	confirmed.emit()


func _refresh_choices() -> void:
	_yes.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES), _selected == 0)
	_no.get_node("Choice").present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO), _selected == 1)
