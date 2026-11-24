extends "res://ui/window_transition/window_transition.gd"

## 原生 `Field_Warp1_*`（`FieldCanvas` 状态 4，野外触控键 48 进；反编译见 `wiki\field\npc-service-menu.md` §5.1）：
## `Field_Warp1_init` 只把 Box2 开窗计数置 1（不动光标、无其它状态）；
## `Field_Warp1_mPaint:5-12` 是 `Map_Copy()` + `Menu_win_Box2_DrawSelect(160, 标题 null,
## fxt 42「前往飞艇吗?」, 光标 `FieldData+0x2C`)`——**没有 Box4 调用，所以没有标题栏；
## 背景只是 `JC_grpCopyFRAME` 的原样快照，没有灰阶／降饱和，也没有模糊层**；
## `Field_Warp1_mKeyPressed` 的 −3／−4 把光标 `(光标 + 1) % 2`，−5 且光标 0（是）才写
## `warp_saved_map_id／warp_saved_tile_x／warp_saved_tile_y`、把待定目的地置地图 148 与 tile (7, 12)、
## 播英雄 `direction 32` + ANI 10；−16 或确认之后关窗（开窗计数 −1）。
##
## 本页只负责这一格确认框。几何**不是固定尺寸**：`Menu_win_Box2_DrawSelect` 每帧按正文
## 折行数重算，窗高由 `ConfirmLayout.select_size` 算（全仓唯一实现）、`layout()` 只做摆位
## （WARP2 的确认框 `Menu_win_Box2_DrawSelect(…, fxt 44, …)`，见 `Field_Warp2_mPaint:11-19`，
## 共用同一个函数）。位置与颜色由 `warp_confirm.tscn` 声明，脚本只算折行数并写回数值；
## 一行的「前往飞艇吗?」就是 160×57 @ (120, 91)。
##
## 「是」只发 `board_requested`：写 `warp_saved_*`、改待定目的地、播英雄 ANI 10 都由宿主做。
## 本页**不换图、不写存档**——原生换图发生在英雄 ANI 10 播完之后
## （`Field_Hero_procNext` 的 ANI 10 分支 → `Map_warpProc(英雄, 地图, x, y)`）。

## 用户要求关窗（Esc／「否」）：宿主据此回野外状态（原生关窗计数到 −4 才 `SetNext(BASIC)`）。
signal close_requested
## 关窗动画播完（窗口已隐藏）。
signal closed
## 确认「是」：宿主写 `warp_saved_*`、置待定目的地并播英雄登船动画。
signal board_requested

## `Menu_win_Box2_DrawSelect` 的 cursor（原生 `FieldData+0x2C`）：0 = 左「是」、1 = 右「否」。
enum Answer { YES, NO }

const ConfirmLayout = preload("res://ui/confirm_layout/confirm_layout.gd")

## 调用方给的窗口宽（`Field_Warp1_mPaint:8` 的 `&width__0` 是 160）。
const BOX_WIDTH := 160
## 正文折行宽度：`width_1 - 16`（`Menu_win_Box2_DrawSelect:41` 的 `JC_fntGetPage`）。
const TEXT_WIDTH := 144

## 当前高亮的那只键（原生光标初值 0 = 「是」，`Field_Warp1_init` 不重置）。
var cursor := Answer.YES
## 正文记录号：WARP1 是 `Field_Warp1_mPaint@0x3C5D8:7` 的 fxt 42，WARP2 是
## `Field_Warp2_mPaint@0x3F714:13` 的 fxt 44——同一个 `Menu_win_Box2_DrawSelect`，只有正文不同。
var message_id := Msg.Id.WARP_BOARD_CONFIRM
## 由宿主接管收窗：WARP2 的确认框随整页一起消失（`Field_Warp2_mKeyPressed:26` 只把整页相位写 −1），
## 所以确认／取消后只发信号，不自己 `close()`。
var managed := false

var _catalog: Object
var _closing := false


## 按 `Menu_win_Box2_DrawSelect` 折行后摆好窗口内容，返回还原出的窗口尺寸。
## 窗高由 `ConfirmLayout.select_size` 算（`13 × 折行数 + 33 + 11`，本两处标题参数都是 `nullptr`），
## 本函数只摆位；正文位置、点线缩进与间隔、确认键尺寸都取 `ConfirmLayout` 里那几个常量
## （Box2 三个绘制入口共用一份）。`content` 下要有 `Lines`（`text_line_list`，行距 13）、`Rule`、
## `Yes`、`No`——WARP1／WARP2 两个确认框的 `Content` 同构，所以这一份几何只有这里一处。
static func layout(content: Node, lines: Array) -> Vector2i:
	var size := ConfirmLayout.select_size(BOX_WIDTH, lines.size())
	# `Menu_win_Box2_DrawWindow:28-29`：`x = (400 − w) / 2`、`y = (240 − h) / 2`。
	var origin := Vector2(Layout.box4_window_frame(size).position)
	var rows: Control = content.get_node("Lines")
	rows.position = origin + Vector2(ConfirmLayout.TEXT_INSET)
	rows.present(lines)
	# 先 `present` 再设尺寸：容器的最小高度按当前可见行数算，反过来设会被上一轮的行数顶住。
	rows.size = Vector2(TEXT_WIDTH, ConfirmLayout.LINE_STEP * lines.size())
	var rule: Control = content.get_node("Rule")
	rule.position = Vector2(origin.x + ConfirmLayout.RULE_INSET,
		origin.y + ConfirmLayout.TEXT_INSET.y + ConfirmLayout.LINE_STEP * lines.size() \
			+ ConfirmLayout.RULE_GAP)
	rule.size = Vector2(BOX_WIDTH - 2 * ConfirmLayout.RULE_INSET, ConfirmLayout.RULE_HEIGHT)
	var choice_y := rule.position.y + ConfirmLayout.RULE_GAP
	var yes: Control = content.get_node("Yes")
	yes.position = Vector2(origin.x + BOX_WIDTH / 4 - ConfirmLayout.CHOICE_SIZE.x / 2, choice_y)
	yes.size = Vector2(ConfirmLayout.CHOICE_SIZE)
	var no: Control = content.get_node("No")
	no.position = Vector2(origin.x + 3 * BOX_WIDTH / 4 - ConfirmLayout.CHOICE_SIZE.x / 2, choice_y)
	no.size = Vector2(ConfirmLayout.CHOICE_SIZE)
	return size


func _ready() -> void:
	super()
	transition_finished.connect(_transition_finished)
	$Content/Yes.pressed.connect(_choose.bind(Answer.YES))
	$Content/No.pressed.connect(_choose.bind(Answer.NO))


## `catalog` 提供 `text_message()`（`common/msg.fxt` 的 42／44／85／86）。
## `record` 是正文记录号，默认 WARP1 的 42；WARP2 传自己的 44。已在开合动画中时返回 false。
func open(catalog: Object, record: int = Msg.Id.WARP_BOARD_CONFIRM) -> bool:
	if visible or is_transitioning():
		return false
	_catalog = catalog
	message_id = record
	cursor = Answer.YES
	_closing = false
	_render()
	show()
	open_window()
	return true


## 宿主切光标：原生 `FieldData+0x2C` 的 cursor 与确认框共用同一个值。
func select(answer: int) -> void:
	cursor = answer
	_render()


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
			cursor = Answer.NO if cursor == Answer.YES else Answer.YES
			_render()
		"Enter", "Space":
			_decide()
		"Escape", "Backspace":
			_request_close()
		_:
			return false
	return true


## 原生 −5：光标 0（是）登船，光标 1（否）只是关窗。
func _decide() -> void:
	if cursor != Answer.YES:
		_request_close()
		return
	if _closing or is_transitioning():
		return
	board_requested.emit()
	if not managed:
		close()


func _request_close() -> void:
	if _closing or is_transitioning():
		return
	close_requested.emit()
	if not managed:
		close()


## 原生触控：`-5` 注册在选中那只上（确认），另一只是 `-3`／`-4`（切光标）。
func _choose(answer: int) -> void:
	if _closing or is_transitioning():
		return
	if answer == cursor:
		_decide()
		return
	cursor = answer
	_render()


func _render() -> void:
	var lines := Layout.wrap_text(String(_catalog.text_message(Msg.SOURCE, message_id)),
		TEXT_WIDTH, Layout.UI_FONT)
	window_size = layout($Content, lines)
	$Content/Yes/Choice.present(
		String(_catalog.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES)), cursor == Answer.YES)
	$Content/No/Choice.present(
		String(_catalog.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO)), cursor == Answer.NO)


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	closed.emit()
