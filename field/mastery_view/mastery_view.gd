extends "res://ui/window_transition/window_transition.gd"

## 原生初始精灵选择的第一级：`Game_Character_Select`（`GAME_STATE_CHARACTER_SELECT_15`，六个流派
## 候选的立绘）。第二级 `GAME_STATE_BOOK_MONSTER_16` 与图鉴是同一张页，落点是
## `scripts\menu\book_monster.gd` 的 `Mode.STARTER`（`field_runtime` 直接显示那份 Scene）。
##
## 依据：
## * `Game_Character_Select_init`：六个候选物种 `21／43／65／87／109／131`
##   （每 22 个一组的最后一只），立绘走 `Object_resLOAD(12, 物种 + 1000)`；
## * `Game_Character_Select_mPaint` → `Menu_CharacterSelect_Draw`：228×214 的 Box4 窗、
##   33×93 的格子、步距 35、立绘站位表 `v43`、选中格的渐变与白框；
## * `Game_Character_Select_mKeyPressed:23-31`：OK 打开 Box2「决定吗?」（fxt 164），
##   `:58-61` 选「是」才 `GameCanvas_SetNext(GAME_STATE_BOOK_MONSTER_16, 流派)`。
##
## 确认框是嵌套在同一个 Box4 窗里的 `components/window_transition`（Box2 相位），
## 取值、几何与差异见 wiki\growth\starter-select.md。
## `field_runtime` 只调用 `present`／`move`／`row_at`／`press_row`／`selected`／`clear`。

const Book = preload("res://menu/book_model/book_model.gd")
const MonsterAnimation = preload("res://ui/monster_animation/monster_animation.gd")
const ConfirmLayout = preload("res://ui/confirm_layout/confirm_layout.gd")
const TextLayout = preload("res://ui/native_text_layout/native_text_layout.gd")

## Box2 确认框的页面状态：原生 `current_state_index_bits+1`（`Game_Character_Select_mKeyPressed`），
## 0 浏览候选、1 确认框打开；框收拢到相位 −4 时 `Game_Character_Select_mRun` 把它清零。
## 这是**页面**状态，不是窗相位——框的开合相位用父脚本的 `BoxPhase`。
enum ConfirmState { BROWSE, OPEN }

## `Menu_win_Box2_DrawSelect` 的 cursor（原生 `transition_parameter_bits+6`）：
## 0 = 左「是」、1 = 右「否」。一级确认框打开时置 1（`Game_Character_Select_mKeyPressed:28`）。
enum Answer { YES = 0, NO = 1 }

## `Menu_CharacterSelect_Draw:74`：`Menu_win_Box4_DrawWindow(…, 228, 214, …, 1, 16)`。
const MASTERY_WINDOW := Vector2i(228, 214)
## 确认框宽：`Menu_win_Box2_DrawSelect` 的 `width` 参数（`Game_Character_Select_mKeyPressed:27`
## 传 160）。窗高不写死，按正文折行数走 `ConfirmLayout.select_size`。
const CONFIRM_WIDTH := 160
## 正文折行宽度 `width − 16`（`Menu_win_Box2_DrawSelect:41` 的 `JC_fntGetPage(…, width_1 - 16, …)`）。
const CONFIRM_TEXT_WIDTH := 144
## 候选数：`Game_Character_Select_init` 写 `transition+1 = 6`。
const MASTERY_ROWS := 6
## 六个物种号＝每组（`Book.MONSTER_SLOTS` 个）的最后一只（`22 * m + 21`）。
const MASTERY_REPRESENTATIVE_SLOT := 21
## 候选格：`JC_grpFillRECT(x, y, 33, 93)`（`Menu_CharacterSelect_Draw:133`）。
## 选中格的白框是 `JC_grpDrawRoundRECT(x - 1, y - 1, 35, 95)`（`:185`），几何在场景里。
const MASTERY_CELL := Vector2(33, 93)
## 立绘原点（格内）：`x 偏移 + 16`、`y 偏移 - 10 + 93`（`:137-139`，`v34 = y + 119`）。
## 格外的部分由 `Menu_CharacterSelect_Draw` 的 `JC_grpSetRESERVE(x, y, 33, 93)` 裁掉（`:138-148`），
## 场景里是每行一个 `clip_contents` 的 `Clip` 容器。
const PORTRAIT_ORIGIN := Vector2(16, 83)
## 六个流派名（`Menu_CharacterSelect_Draw:56-61` 的 `v44`；正文是 `[水` 这种带方括号的前缀，
## 页脚 fxt 162 `%s属性]精灵` 把它拼成 `[水属性]精灵`）。
const MASTERY_NAME_IDS := [
	Msg.Id.MASTERY_NAME_WATER, Msg.Id.MASTERY_NAME_FIRE, Msg.Id.MASTERY_NAME_WOOD,
	Msg.Id.MASTERY_NAME_WIND, Msg.Id.MASTERY_NAME_LIGHT, Msg.Id.MASTERY_NAME_DARK,
]
## `v43`（`:43-54`）每个候选的立绘参数：x 偏移／y 偏移／朝向码（`2 - t`，1 在
## `MonsterAnimation.present` 里镜像，见 `Object_drawBASIC` 的第 3 个参数）。
const PORTRAIT_PARAMETERS: Array[Vector3i] = [
	Vector3i(-2, 0, FieldAction.Facing.RIGHT),
	Vector3i(-10, 0, FieldAction.Facing.RIGHT),
	Vector3i(-15, -5, FieldAction.Facing.RIGHT),
	Vector3i(0, 0, FieldAction.Facing.LEFT),
	Vector3i(18, 0, FieldAction.Facing.LEFT),
	Vector3i(11, 0, FieldAction.Facing.LEFT),
]
## 选中格底色（`JC_grpFillGradientV` 的上下两色，颜色表 `v42`，`:61-72`）。
const SELECTION_GRADIENT: Array[Array] = [
	[Color("#5a8ebd"), Color("#05052c")],
	[Color("#bd3c29"), Color("#2c0505")],
	[Color("#6b9629"), Color("#052c05")],
	[Color("#5aa69c"), Color("#052c2c")],
	[Color("#cea629"), Color("#2c2c05")],
	[Color("#ad65ce"), Color("#2c052c")],
]
## 二级列表里立绘的朝向、格框切片与格子数都是 `book_monster.gd`（状态 16／19 同一张页）的事。

var last_error := ""

var _mastery_names: Array[String] = []
## 当前选中的流派（`Game_Book_Monster_init:12` 的 `transition_parameters % 6` 就是它；
## 从二级页 CLR 回来时也停在它上面）。
var _selected := 0
var _catalog: GameplayData
var _confirm := ConfirmState.BROWSE
var _answer := Answer.NO
## 确认框在收拢中（原生相位 −1..−4、子相位仍是 1）：收拢播完才回列表，期间不再开框或提交。
var _closing_confirm := false


func _ready() -> void:
	super()
	set_process_input(true)
	_catalog = AssetCatalog.load_gameplay_catalog()
	for index in MASTERY_ROWS:
		(_mastery_row(index).get_node("Selected") as TextureRect).texture = _selection_texture(index)
	$Confirm.transition_finished.connect(_confirm_finished)
	$Confirm/Content/Yes.pressed.connect(_choose.bind(Answer.YES))
	$Confirm/Content/No.pressed.connect(_choose.bind(Answer.NO))
	# 候选格没有 Button，选中走 `field_runtime.handle_touch` → `row_at` → `press_row`。


## `choice` 是二级页 CLR 回来时要停在的流派（`GameCanvas_SetNext(CHARACTER_SELECT_15,
## preferred_mastery_index)`）；新开局传 0。
func present(names: Array[String], choice: int = 0) -> bool:
	last_error = ""
	_reset_confirm()
	if names.size() != MASTERY_ROWS:
		last_error = "流派候选数量不是 %d" % MASTERY_ROWS
		return false
	_mastery_names = names.duplicate()
	_enter_mastery(choice)
	if not visible:
		visible = true
		open_window()
	return true


func move(step: int) -> void:
	if step == 0:
		return
	if _confirm == ConfirmState.OPEN:
		# 原生子相位 1 的 −4／−3 只翻单选的「是／否」（`Game_Character_Select_mKeyPressed:40-48`）。
		_answer = Answer.NO if _answer == Answer.YES else Answer.YES
		_render_confirm()
		return
	var count := _mastery_names.size()
	if count == 0:
		return
	_selected = posmod(_selected + step, count)
	_render_mastery()


func selected() -> int:
	return _selected


## 触控点中某一格（`row_at` 的返回值）。原生每个候选格都登记一个触控键
## （`Menu_CharacterSelect_Draw`）：光标左侧的格是 −3、右侧是 −4（带「按几次」的计数，
## `:156`／`:168`），**光标格是 −5**（`:203`）——所以点光标格等于按 OK，打开 Box2 确认框，
## 不会直接提交。
func press_row(index: int) -> void:
	if _confirm == ConfirmState.OPEN:
		return
	if index < 0 or index >= _mastery_names.size():
		return
	if index == _selected:
		_open_confirm()
		return
	move(index - _selected)


## 点到的行号（-1 表示没点在任何一行上），用于触屏选择。
## 确认框打开时列表不再接受触点（原生 `Menu_win_Box2_DrawSelect:36` 先 `EFC_mainTouchINIT`
## 只登记框内两块）。
func row_at(point: Vector2) -> int:
	if _confirm == ConfirmState.OPEN:
		return -1
	for index in _mastery_names.size():
		var row: Control = _mastery_row(index)
		if row.visible and row.get_global_rect().has_point(point):
			return index
	return -1


func clear() -> void:
	_reset_confirm()
	visible = false
	_selected = 0


## 确认框打开时这里拦框内的键：−4／−3 翻选项、−5／−16 关框回列表，只有右「否」这一侧
## 关框（原生 `Game_Character_Select_mKeyPressed:54-61` 的 `transition+6 != 0` 分支）。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if _confirm == ConfirmState.OPEN:
		if _confirm_key(key.keycode):
			get_viewport().set_input_as_handled()
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		# 开合动画里也要拦：宿主的 OK 分支会直接提交，跳过确认框。
		_open_confirm()
		get_viewport().set_input_as_handled()


## 确认框内的按键。返回 true 表示事件已处理（拦住不外传）。
func _confirm_key(keycode: int) -> bool:
	match keycode:
		KEY_LEFT, KEY_RIGHT:
			move(1)
			return true
		KEY_ESCAPE, KEY_BACKSPACE:
			_close_confirm()
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# 收拢中不提交：原生这一帧框已在退场，宿主的 OK 分支会直接读 `selected()`。
			if _answer == Answer.NO or _closing_confirm:
				_close_confirm()
				return true
			# 「是」不拦事件：宿主的 OK 分支读 `selected()` 后提交，`clear()` 顺手收起确认框。
			return false
	return false


func _enter_mastery(choice: int) -> void:
	window_size = MASTERY_WINDOW
	$Bounds/Title.text = AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_TITLE)
	($Content/MasteryPage/Headline as Control).text = _mastery_headline()
	_selected = clampi(choice, 0, MASTERY_ROWS - 1)
	_render_mastery()


func _render_mastery() -> void:
	($Content/MasteryPage/Notice as Control).text = _mastery_notice()
	($Content/MasteryPage/Caption as Control).text = _mastery_names[_selected]
	for index in MASTERY_ROWS:
		var row := _mastery_row(index)
		var focused := index == _selected
		(row.get_node("Selected") as Control).visible = focused
		(row.get_node("Outline") as Control).visible = focused
		var parameters: Vector3i = PORTRAIT_PARAMETERS[index]
		# 立绘按原生 `JC_grpSetRESERVE(x, y, 33, 93)` 的矩形裁掉外溢部分（`@0x4FE58:138-148`）。
		var portrait: Node2D = row.get_node("Clip/Portrait")
		portrait.position = PORTRAIT_ORIGIN + Vector2(parameters.x, parameters.y)
		var species := Book.monster_id(index, MASTERY_REPRESENTATIVE_SLOT)
		if not portrait.present(MonsterAnimation.battle_identity(species),
				AniAction.Clip.IDLE, parameters.z):
			last_error = portrait.last_error
			return
		# 原生只有选中格按帧号推待机（`Object_drawBASIC` 的第 7 参），未选中的停在首帧。
		portrait.set_running(focused, true)


## 头部一行：fxt 160「主角的 」+ fxt 161「请确认属性」（`Menu_CharacterSelect_Draw:93-98`）。
func _mastery_headline() -> String:
	return AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_HEADLINE) + \
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_HEADLINE_SUFFIX)


## 页脚一行：fxt 162「%s属性]精灵」套 fxt 154–159 的流派名，再接 fxt 163「正确使用」
## （`Menu_CharacterSelect_Draw:105-119`：先 `EX_knlSprintk` 拼成一行，再 `JC_fntDrawChars` 整行画）。
## fxt 162 的正文整体落在自己的白色段里，而流派名带的是另一段颜色；
## `NativeTextLayout` 不允许嵌套段（`_strip_color_markup` 直接报错、整行不画），
## 所以把模板的开／闭标记挪到名字两侧，按原生的换色顺序并列成两段。
func _mastery_notice() -> String:
	var name := AssetCatalog.text_message(Msg.SOURCE, MASTERY_NAME_IDS[_selected])
	var template := AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_FOOTER)
	var suffix := AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_FOOTER_SUFFIX)
	var open := TextLayout.markup_token_at(template, 0)
	var inner := template.substr(open.length(),
		template.length() - open.length() - TextLayout.COLOR_SPAN_CLOSE.length())
	var parts := inner.split("%s")
	var tail := open + parts[1] + suffix + TextLayout.COLOR_SPAN_CLOSE
	if parts[0].is_empty():
		return name + tail
	return open + parts[0] + TextLayout.COLOR_SPAN_CLOSE + name + tail


## 原生 OK 打开 Box2 确认框：子相位置 1、选项置 1（「否」）、框的窗口相位置 1
## （`Game_Character_Select_mKeyPressed:27-30`／`Game_Book_Monster_mKeyPressed:155-157`）。
func _open_confirm() -> void:
	if _confirm == ConfirmState.OPEN:
		return
	_confirm = ConfirmState.OPEN
	_closing_confirm = false
	_answer = Answer.NO
	_render_confirm()
	var confirm := $Confirm as Control
	confirm.show()
	confirm.open_window()


## 关框回列表：原生把框相位写 −1 起收拢（`Menu_win_Box2_DrawWindow` 每帧 ±1），
## `Game_Character_Select_mRun`／`Game_Book_Monster_mRun` 收到 `MainData + 7 == −4` 才把子相位清零
## ⇒ 这里只起收拢，`_confirm` 落回 `BROWSE` 在 `_confirm_finished(false)` 里做。
func _close_confirm() -> void:
	if _confirm != ConfirmState.OPEN or _closing_confirm:
		return
	_closing_confirm = true
	($Confirm as Control).close_window()


## 确认框正在收拢：宿主（`field_runtime.submit_mastery`）这段时间不得提交。
func confirm_closing() -> bool:
	return _closing_confirm


## 宿主强制复位（`present`／`clear`）：原生接受或换页时把相位直接写 0／−1，框同帧不再画，
## 所以这条路径不播收拢动画。
func _reset_confirm() -> void:
	_confirm = ConfirmState.BROWSE
	_answer = Answer.NO
	_closing_confirm = false
	var confirm := $Confirm as Control
	confirm.stop_transition()
	confirm.hide()


func _render_confirm() -> void:
	var confirm := $Confirm as Control
	var prompt := _confirm_prompt()
	(confirm.get_node("Content/Prompt") as Control).text = prompt
	var lines := Layout.wrap_text(prompt, CONFIRM_TEXT_WIDTH, Layout.UI_FONT)
	confirm.window_size = ConfirmLayout.select_size(CONFIRM_WIDTH, lines.size())
	(confirm.get_node("Content/Yes/Choice") as Control).present(
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES), _answer == Answer.YES)
	(confirm.get_node("Content/No/Choice") as Control).present(
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO), _answer == Answer.NO)


## 正文 fxt 164「决定吗?」（`Menu_CharacterSelect_Draw:177-178`）。
func _confirm_prompt() -> String:
	return AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MASTERY_CONFIRM)


## 原生触控：选中那一块注册 −5（确认），另一块 −3／−4（切光标）。键盘的「是」靠宿主读光标后提交，
## 触控没有按键事件，只好请宿主的公开入口 `submit_mastery()`——与键盘确定走的是同一个入口。
func _choose(answer: int) -> void:
	if _confirm != ConfirmState.OPEN or _closing_confirm:
		return
	if answer != _answer:
		_answer = answer
		_render_confirm()
		return
	if answer == Answer.NO:
		_close_confirm()
		return
	var field: Object = get_parent()
	if field != null and field.has_method("submit_mastery"):
		field.submit_mastery()


## 确认框的收拢播完（相位 −4，`transition_finished(false)`）才回列表。
func _confirm_finished(opened: bool) -> void:
	if opened:
		return
	_reset_confirm()


func _mastery_row(index: int) -> Control:
	return $Content/MasteryPage.get_node("Row%d" % index) as Control


func _selection_texture(index: int) -> Texture2D:
	var pair: Array = SELECTION_GRADIENT[index]
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray(pair)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = int(MASTERY_CELL.x)
	texture.height = int(MASTERY_CELL.y)
	return texture
