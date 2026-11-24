extends "res://ui/window_transition.gd"

## 原生 `Field_Inn_*`（`FieldCanvas` 状态 16，NPC 交互码 5）：
## `Field_Inn_init` 只把开窗计数 `MainData+0xD` 置 1（不动光标），
## `Field_Inn_mRun` 在关窗计数回到 −4 时 `FieldCanvas_SetNext(FIELD_STATE_BASIC, 0)`，
## `Field_Inn_mPaint` = `Map_Copy()` + `Menu_win_Box2_DrawSelect(160, null, fxt 90, 光标, &开窗计数)`，
## `Field_Inn_destroy` 是空的。
##
## `Menu_win_Box2_DrawSelect` 的几何：窗口高由 `ConfirmLayout.select_size(WIDTH, 折行数)` 给出
## （`Menu_win_Box2_DrawSelect@0x4B630:41-44`：`13 × 折行数 + 33 + 11`，无标题），
## 宽 160 由 `Menu_win_Box2_DrawWindow` 居中成 `x = (400 − 160)/2 = 120`；
## 两行提示 ⇒ 160×70 @ (120, 85)。折行宽度是 `width − 16 = 144`（`JC_fntGetPage`）。
## 正文画在 `(窗x + 8, 窗y + 11)`，点线在正下方 5 px（`#196485`、2 亮 1 暗、长 `width − 8`），
## 两个 44×16 确认键的中心在 `窗x + w/4` 与 `窗x + 3w/4`、点线下方 5 px；选中那只
## `#FF9200` 底 + 黑字，另一只灰字（`JC_fntSetRGB(0, 0x808080)`）。正文顶端与窗口顶端
## 之间那 11 px、点线与按键的 5 px 间隔、44×16 的键尺寸都是 Box2 三个绘制入口共用的取值，
## 统一定义在 `components/confirm_layout.gd`（`TEXT_INSET`／`RULE_GAP`／`CHOICE_SIZE`），
## 这样 `13 × 行数 + 44` 的窗口高恰好留下 7 px 页脚。
##
## 按键（`Field_Inn_mKeyPressed`）：`-3`／`-4` 把光标 `±1 % 2`；`-5` 且光标 0（是）时
## `ParamData.money_balance > 0x31`（≥ 50）就 `Ball_stdHP／Ball_stdSP(party_monsters[0..2], 100)`
## + `Param_moneySET(-50)`，文案取 fxt 89（`n79 = 79` 是默认值，只有成功才改成 89）；
## 之后无条件 `Field_Warp1_mKeyPressed(-16)` 关窗。光标 1（否）不产生任何文案，直接关窗。
##
## 原生把结果文案交给野外信息行（`Game_infoInit`），本场景是自包含页面，所以把同一份
## 文案换成正文画在同一个窗口里，按 OK／CLR 关窗。

signal closed

const ConfirmLayout = preload("res://ui/confirm_layout.gd")
const WIDTH := 160
const TEXT_WIDTH := 144          ## 折行宽度：`width − 16`

var cursor := 0                  ## `FieldData+0x2C`：0 是／1 否

var _assets: Node
var _story: StoryRuntime
var _result := 0                 ## 非 0 时画结果文案，此时只剩一个居中的确认键
var _closing := false


func _ready() -> void:
	super()
	transition_finished.connect(_transition_finished)
	$Content/Yes.pressed.connect(_choose.bind(0))
	$Content/No.pressed.connect(_choose.bind(1))
	$Content/Confirm.pressed.connect(close)


## `assets` 提供 `text_message()`；`story` 是 `StoryRuntime`，`inn_rest()` 返回空串表示成功。
func present(assets: Node, story: StoryRuntime) -> void:
	_assets = assets
	_story = story
	cursor = 0
	_result = 0
	_closing = false
	_render()
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
			cursor = 1 - cursor
			_render()
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


func _confirm() -> void:
	if _closing or is_transitioning():
		return
	if cursor != 0:
		close()
		return
	var failure: String = _story.inn_rest()
	_result = Msg.Id.SHOP_NOT_ENOUGH_MONEY if not failure.is_empty() else Msg.Id.INN_RESTORED
	_render()


## 原生触控：`-5` 注册在选中那只上（确认），另一只是 `-3`／`-4`（切光标）。
func _choose(index: int) -> void:
	if _closing or is_transitioning() or _result != 0:
		return
	if index == cursor:
		_confirm()
		return
	cursor = index
	_render()


func _render() -> void:
	var message := Msg.Id.INN_PROMPT if _result == 0 else _result
	var lines := Layout.wrap_text(_assets.text_message(Msg.SOURCE, message), TEXT_WIDTH,
		Layout.UI_FONT)
	window_size = ConfirmLayout.select_size(WIDTH, lines.size())
	var rect := Layout.box4_window_frame(window_size)
	$Content/Lines.position = Vector2(rect.position + ConfirmLayout.TEXT_INSET)
	$Content/Lines.size = Vector2(TEXT_WIDTH, ConfirmLayout.LINE_STEP * lines.size())
	$Content/Lines.present(lines)
	var rule_y: int = rect.position.y + ConfirmLayout.TEXT_INSET.y + \
		ConfirmLayout.LINE_STEP * lines.size() + ConfirmLayout.RULE_GAP
	$Content/Rule.position = Vector2(rect.position.x + 4, rule_y)
	$Content/Rule.size = Vector2(WIDTH - 8, ConfirmLayout.RULE_HEIGHT)
	var row: int = rule_y + ConfirmLayout.RULE_GAP
	var button := ConfirmLayout.CHOICE_SIZE
	$Content/Yes.position = Vector2(rect.position.x + WIDTH / 4 - button.x / 2, row)
	$Content/No.position = Vector2(rect.position.x + 3 * WIDTH / 4 - button.x / 2, row)
	$Content/Confirm.position = Vector2(rect.position.x + (WIDTH - button.x) / 2, row)
	var decided := _result != 0
	$Content/Yes.visible = not decided
	$Content/No.visible = not decided
	$Content/Confirm.visible = decided
	if decided:
		$Content/Confirm/Choice.present(
			_assets.text_message(Msg.SOURCE, Msg.Id.CONFIRM_OK), true)
		return
	$Content/Yes/Choice.present(
		_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES), cursor == 0)
	$Content/No/Choice.present(
		_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO), cursor == 1)


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	_result = 0
	closed.emit()
