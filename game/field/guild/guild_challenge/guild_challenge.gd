extends Control

const MessageStack = preload("res://engine/ui/message_stack/message_stack.gd")

## 原生 `Field_Guild_Challenge_*`（`FieldCanvas` 状态 7）：`Field_Guild_Challenge_init`
## （开窗）／`mRun`（关窗计数到 −4 才 `SetNext(6)`）／`mKeyPressed`／
## `mPaint` → `Field_Guild_Challenge_Draw` ＋ `Menu_win_Box2_DrawSelect`。
##
## 窗口 180×136 @ (110, 52)、侧白边 1、header 16，标题 `msg 54`。正文只在 Box4 全开时画：
## `msg 55`（`0xFFFFAA`）居中于 `y+27`，外框 `#196485` `(x+10, y+43, 160, 74)`、底 `#E1B2F`
## `(x+11, y+44, 158, 72)`，`msg 56`（现在的排名 = `guild_code`）`y+55`、`msg 57`（对手的排名 =
## `guild_code − 1`）`y+75` 白、`msg 58`（胜利后排名上升一位）`y+95` `#FFFF55`，三行都居中于 `x+90`。
##
## 确认框是 `Menu_win_Box2_DrawSelect(160, 标题 null, msg 59, 光标)`：窗高与正文／点线／按键
## 摆位都由 `_layout_confirm()` 按 msg 59 的实际折行数算（高度公式在 `ConfirmLayout`），
## 单行时就是 160×57 @ (120, 91)；正文 `(x+8, y+11)`、点线 `(x+4, 13·行数+5+y)`、
## 两个 44×16 键中心在 `x + w/4`／`x + 3w/4`，左「是」`msg 85`、右「否」`msg 86`，
## 选中那只 `#FF9200` 底 + 黑字、另一只灰字。
##
## 与原生的一处**有意差异**：原生进确认框时把光标置 0（「是」）；这里默认停在「否」，
## 免得连按 OK 直接开战，按 ←／→ 或点另一只键切到「是」才发 `started`。
##
## 对手阵容读不出来时不在本页造替代阵容：`GuildBattle.enemy_constructors()` 失败即
## `push_error` ＋ 底部错误行（原生没有这一行，是本工程响亮失败的出口），确认框也不开。

## 确认「是」：`constructors` 是 `Game_Guild_Battle_init` 的三条实参，宿主据此开战
## （`guild_battle.create_battle()`），`kind` 恒为 `guild_battle.KIND_CHALLENGE`。
signal started(constructors: Array)
## 窗口关完（CLR）：原生 `mRun` 到此才 `SetNext(FIELD_STATE_GUILD_LIST)`。
signal closed

const GuildBattle = preload("res://game/field/guild/guild_battle/guild_battle.gd")
const Layout = preload("res://game/prime/ui/layout/layout.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")

## `FieldData+0x08`：0 = 本页、1 = 确认框。
enum Page { MAIN, CONFIRM }
## `Menu_win_Box2_DrawSelect` 的 cursor：0 = 左「是」、1 = 右「否」。
enum Answer { YES, NO }

## 确认框的 `Menu_win_Box2_DrawSelect` 宽度（原生 `Field_Guild_Challenge_Draw` 传的立即数 160）。
const CONFIRM_WIDTH := 160
## 确认框正文折行宽度 `width − 16`（`Menu_win_Box2_DrawSelect:41` 的 `JC_fntGetPage`）。
const CONFIRM_TEXT_WIDTH := 144

## `ParamData.guild_code_bits`（原生挑战页只显示原始名次数字）。
var code := 0
var page := Page.MAIN
var choice := Answer.NO

var _assets: Node
var _catalog: GameplayData
var _constructors: Array = []
var _error := ""
## 已推到提示栈的那条错误，避免每帧重复推。
var _error_shown := ""
var _closing := false


func _ready() -> void:
	$Window.transition_finished.connect(_window_finished)
	$Confirm.transition_finished.connect(_confirm_finished)
	$Window/Content/AcceptHit.pressed.connect(_open_confirm)
	$Window/Content/BackHit.pressed.connect(close)
	$Confirm/Content/Yes.pressed.connect(_choose.bind(Answer.YES))
	$Confirm/Content/No.pressed.connect(_choose.bind(Answer.NO))


## `guild_code` = 原生的转移参数（`ParamData.guild_code_bits`）；`assets` 提供
## `text_message()`／`load_sprite()`，`catalog` 是 `GameplayData`。
func present(assets: Node, catalog: GameplayData, guild_code: int) -> void:
	_assets = assets
	_catalog = catalog
	code = guild_code
	page = Page.MAIN
	choice = Answer.NO
	_closing = false
	_resolve_enemies()
	$Window/Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.GUILD_CHALLENGE_TITLE)
	$Window/Content/Accept.configure(assets, 0)
	$Window/Content/Back.configure(assets, 1)
	_render()
	show()
	$Confirm.hide()
	$Window.open_window()


func close() -> void:
	if _closing or $Window.is_transitioning():
		return
	_closing = true
	$Window.close_window()


func handle_key(key: String) -> bool:
	if _closing or $Window.is_transitioning():
		return true
	if page == Page.CONFIRM:
		return _handle_confirm_key(key)
	match key:
		"Enter", "Space":
			_open_confirm()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


func _handle_confirm_key(key: String) -> bool:
	if $Confirm.is_transitioning():
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			choice = Answer.NO if choice == Answer.YES else Answer.YES
			_render()
		"Enter", "Space":
			_decide()
		"Escape", "Backspace":
			_cancel_confirm()
		_:
			return false
	return true


## 原生子状态 0 的 `−5`：光标清零（这里是「否」）后开确认框。
func _open_confirm() -> void:
	if _closing or page != Page.MAIN or $Window.is_transitioning() or $Confirm.is_transitioning():
		return
	if not _error.is_empty():
		return
	page = Page.CONFIRM
	choice = Answer.NO
	_render()
	$Confirm.show()
	$Confirm.open_window()


## 原生子状态 1 的 `−5`：光标 0（是）→
## `GameCanvas_SetNext(GAME_STATE_GUILD_BATTLE_5, guild_code)`；否则只是关框回本页。
func _decide() -> void:
	if $Confirm.is_transitioning():
		return
	if choice != Answer.YES or _constructors.size() != GuildBattle.MONSTERS:
		_cancel_confirm()
		return
	_closing = true
	hide()
	started.emit(_constructors)


func _cancel_confirm() -> void:
	if $Confirm.is_transitioning():
		return
	$Confirm.close_window()


func _choose(answer: int) -> void:
	if _closing or page != Page.CONFIRM or $Confirm.is_transitioning():
		return
	if answer == choice:
		_decide()
		return
	choice = answer
	_render()


func _window_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	closed.emit()


func _confirm_finished(opened: bool) -> void:
	if opened or page != Page.CONFIRM:
		return
	$Confirm.hide()
	page = Page.MAIN
	_render()


func _resolve_enemies() -> void:
	var resolution := GuildBattle.enemy_constructors(_catalog, code)
	_constructors = resolution.constructors if resolution.get("ok", false) else []
	_error = "" if _constructors.size() == GuildBattle.MONSTERS else str(resolution.get("error", ""))
	if not _error.is_empty():
		push_error("公会挑战页：%s" % _error)


func _render() -> void:
	$Window/Content/Subtitle.text = _assets.text_message(Msg.SOURCE,
		Msg.Id.GUILD_CHALLENGE_SUBTITLE)
	$Window/Content/RankCurrent.text = _format(Msg.Id.GUILD_CHALLENGE_RANK, code)
	$Window/Content/RankOpponent.text = _format(Msg.Id.GUILD_CHALLENGE_OPPONENT_RANK, code - 1)
	$Window/Content/Up.text = _assets.text_message(Msg.SOURCE, Msg.Id.GUILD_CHALLENGE_UP)
	# 静态诊断行已退役：数据缺失的说明改走提示栈（错误本身仍 push_error 响亮记录）。
	$Error.visible = false
	if not _error.is_empty() and _error != _error_shown:
		_error_shown = _error
		MessageStack.say(_error)
	_layout_confirm(_assets.text_message(Msg.SOURCE, Msg.Id.GUILD_CHALLENGE_PROMPT))
	$Confirm/Content/Yes/Choice.present(
		_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES), choice == Answer.YES)
	$Confirm/Content/No/Choice.present(
		_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO), choice == Answer.NO)


## 确认框是 `Menu_win_Box2_DrawSelect(160, 标题 null, msg 59, 光标)`：窗高按实际折行数由
## `ConfirmLayout` 算（场景里不再写死尺寸），正文／点线／两只按键都跟着窗口矩形摆位——正文位置、
## 点线缩进与间隔、按键 44×16 都取 `ConfirmLayout` 里那几个常量（Box2 三个绘制入口共用一份）。
func _layout_confirm(prompt: String) -> void:
	$Confirm/Content/Prompt.text = prompt
	var lines := Layout.wrap_text(prompt, CONFIRM_TEXT_WIDTH, Layout.UI_FONT)
	var size := ConfirmLayout.select_size(CONFIRM_WIDTH, lines.size())
	$Confirm.window_size = size
	# `Menu_win_Box2_DrawWindow` 在 400×240 里居中（整数截断）。
	var rect := Layout.box4_window_frame(size)
	$Confirm/Content/Prompt.position = Vector2(rect.position + ConfirmLayout.TEXT_INSET)
	var rule_y := rect.position.y + ConfirmLayout.TEXT_INSET.y + \
		ConfirmLayout.LINE_STEP * lines.size() + ConfirmLayout.RULE_GAP
	$Confirm/Content/Rule.position = Vector2(rect.position.x + ConfirmLayout.RULE_INSET, rule_y)
	$Confirm/Content/Rule.size = Vector2(rect.size.x - 2 * ConfirmLayout.RULE_INSET,
		ConfirmLayout.RULE_HEIGHT)
	var choice_y := rule_y + ConfirmLayout.RULE_GAP
	var yes: Control = $Confirm/Content/Yes
	yes.position = Vector2(rect.position.x + rect.size.x / 4 - ConfirmLayout.CHOICE_SIZE.x / 2,
		choice_y)
	yes.size = Vector2(ConfirmLayout.CHOICE_SIZE)
	var no: Control = $Confirm/Content/No
	no.position = Vector2(rect.position.x + 3 * rect.size.x / 4 - \
		ConfirmLayout.CHOICE_SIZE.x / 2, choice_y)
	no.size = Vector2(ConfirmLayout.CHOICE_SIZE)


## 原生 `EX_knlSprintk(s, JC_fxt2Return(56/57), 值)`：记录正文里带 `%d`。
func _format(record: int, value: int) -> String:
	return _assets.text_message(Msg.SOURCE, record) % value
