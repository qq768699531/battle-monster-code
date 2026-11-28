extends "res://engine/ui/window_transition/window_transition.gd"

## 原生 `Game_Book_Monster`（GAME_STATE_BOOK_MONSTER_19／`GAME_STATE_BOOK_MONSTER_16`）：228×240 窗口。
##
## 依据：
## * `Game_Book_Monster_init`（开窗、按类别装载）与 `Game_Book_Monster_Load`
##   （切类别时把光标与滚动清零，按 `22 * 类别 + 序号` 取物种）。
## * `Menu_mon_DrawBookList`：标题「图鉴」、6 个 33×30 属性页签（未选中走
##   `GRP_MODE_GRAY`）、格框 (x+8, y+54, 212, 68)、6×2 个 30×30 格子（步距 32，起点
##   (x+11, y+57)）、格内 24×24 剪裁的战斗精灵、右侧 60 高的滚动条，向下 70 像素是详情。
## * `Menu_Monster_Draw3`：70×75 立绘（含 `obj/ui_eff` 底光）、稀有度图标、
##   NO.（3 位补零，物种号 + 1）、名字、6 项数值（3 行 × 2 列，行距 9、列距 71、宽 68）、
##   底栏 ACTIVE SKILL。
## * `Game_Book_Monster_mKeyPressed`：页签模式左右换类别、下／OK 进格子；
##   格子模式四方向按 24 格取模移动、CLR 退回页签模式；页签模式 CLR 回图鉴目录。

signal back_requested
## 状态 16 的确认框选「是」：原生 `Game_Book_Monster_mKeyPressed:38-96` 入队三只并
## `GameCanvas_SetNext(GAME_STATE_FIELD, 1)`，宿主收到这条信号后提交选择。
signal starter_confirmed

const Book = preload("res://game/menu/book/book_model/book_model.gd")
const Battle = preload("res://game/battle/combat/battle.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")
const SlotFrames = preload("res://game/menu/party/slot_frames/slot_frames.gd")
const SlotGrade = preload("res://game/menu/party/slot_grade/slot_grade.gd")
## 未选中的页签按 `GRP_MODE_GRAY` 画成灰度（与怪物立绘同一套灰度公式）。
const GRAY_SHADER := preload("res://engine/anim/monster_animation/ani_brightness.gdshader")

const MONSTER_TEXT_SOURCE := "common/item_mon.dat"
const TAB_SHEET := "common/ui_battle/frame-014"
## `Menu_winDrawIcon4` 的 6 张稀有度标签（宽度随字长）。
const RARITY_FRAME := 4
const RARITY_REGIONS := [Rect2i(0, 0, 53, 10), Rect2i(53, 0, 69, 10), Rect2i(122, 0, 37, 10),
	Rect2i(159, 0, 56, 10), Rect2i(215, 0, 53, 10), Rect2i(268, 0, 29, 10)]
## `Menu_winDrawIcon8`：ui_window 帧 8 每 5 像素一行，顺序 ATK/DEF/MATK/MDEF/HP/SPD 在 10/11/12/13/6/5。
const STAT_LABEL_FRAME := 8
const STAT_LABEL_ROWS := [10, 11, 12, 13, 6, 5]
const ATTRIBUTE_SHEET := "common/ui_battle/frame-000"
## `Menu_Party_GetRGB` → `Ball_stdGradeRGB`：已获得的格子外面再套一圈 1 px 稀有度描边，
## 与队伍列表同一套颜色（`SlotGrade.BALL_GRADE_RGB`），按 `attribute_entry` 取。
## `Menu_detailDrawMonster` 的 68×73 剪裁框中心（立绘节点在框内的原点）。
const PORTRAIT_ANCHOR := Vector2(34, 64)

## 原生 `Game_Book_Monster` 同时服务两个状态：19（图鉴，从目录进）与 16（初始精灵选择，
## `Game_Book_Monster_init:12-35`）。两者是同一个类、同一份 `Menu_mon_DrawBookList`／
## `Menu_Monster_Draw3`，差别只有「哪些格 `Param_bookIsMonster` = 1」——状态 16 只把所选流派
## （`22 × 流派`）的第 4…8 格置 1。本工程用一张只含这五只的知识表表达那张遮罩，于是格内精灵、
## 详情预览（`Menu_mon_DrawBookList:148-149`／`:219`）与 OK 能否确认
## （`Game_Book_Monster_mKeyPressed:150-159`）都读同一张表，不再有第二份列表实现。
enum Mode { BOOK, STARTER }

## Box2 确认框的页面状态：原生 `current_state_index_bits+2`，0 浏览、1 打开；
## 框收拢到相位 −4 时 `Game_Book_Monster_mRun` 把它清零。
enum ConfirmState { BROWSE, OPEN }

## `Menu_win_Box2_DrawSelect` 的 cursor（原生 `transition_parameter_bits+6`）：0 = 左「是」、
## 1 = 右「否」；状态 16 打开时写 1（`Game_Book_Monster_mKeyPressed:157`）。
enum Answer { YES = 0, NO = 1 }

## 确认框宽：`Menu_win_Box2_DrawSelect` 的 `width` 参数（状态 16 传 160）。
## 正文折行宽度 `width − 16`（`Menu_win_Box2_DrawSelect:41` 的 `JC_fntGetPage(…, width − 16, …)`）。

var category := 0
var cursor := 0
var scroll := 0
var grid_mode := false
var mode := Mode.BOOK

var _assets: Node
var _catalog: GameplayData
var _knowledge: Dictionary = {}
## 状态 16 的五只候选物种（`22 × 流派 + 4 … + 8`），也是 `starter_choice()` 的序号来源。
var _starter_species: Array[int] = []
var _confirm := ConfirmState.BROWSE
var _answer := Answer.NO
## 确认框在收拢中（原生相位 −1..−4、子相位仍是 1）：收拢播完才回列表，期间不再开框或提交。
var _closing_confirm := false
var _messages: Dictionary = {}
var _cell_frames: Array[Texture2D] = []
var _tab_frames: Array[Texture2D] = []
var _rarity_frames: Array[Texture2D] = []
var _stat_labels: Array[Texture2D] = []
var _attribute_frames: Array[Texture2D] = []
var _active_width := 0.0
var _active_age := 0.0
var _active_text := ""


func _ready() -> void:
	super()
	for index in range(Book.MONSTER_CATEGORIES):
		var tab: Button = $Content.get_node("Tab%d" % index)
		tab.pressed.connect(_select_category.bind(index))
		# 六个页签共用同一份材质会互相覆盖灰度开关，这里各建一份。
		var material := ShaderMaterial.new()
		material.shader = GRAY_SHADER
		tab.get_node("Frame").material = material
	for index in range(Book.MONSTER_COLUMNS * Book.MONSTER_ROWS):
		var cell := $Content.get_node("Cell%d" % index) as ItemCell
		cell.pressed.connect(_select_slot.bind(index))
		# 格组件（`item_cell` 的呼吸轨）自带一条 0→63 的呼吸，但 `Menu_mon_DrawBookList` 全文没有
		# `GRP_MODE_BRIGHT`（格框直接走 `Menu_winDrawIcon16`），图鉴格亮度恒定。
		cell.get_node("Frame/Breath").stop()
	$Content/Scroll/UpHit.pressed.connect(func(): _step(-Book.MONSTER_COLUMNS, false))
	$Content/Scroll/DownHit.pressed.connect(func(): _step(Book.MONSTER_COLUMNS, false))
	$Content/AcceptHit.pressed.connect(_accept)
	$Content/BackHit.pressed.connect(_back)
	$Confirm.transition_finished.connect(_confirm_finished)
	$Confirm.chosen.connect(_on_confirm_choice)
	# `Menu_detailDrawMonster` 先画 `obj/ui_eff` 动作 1 的底光，再画精灵；底光静止在首帧。
	var effect: AnimationPlayer = $Content/Detail/Portrait/Clip/Effect/AnimationPlayer
	effect.speed_scale = 0.0
	effect.play(AniAction.clip_name(effect, 1))
	effect.advance(0.0)


func present(assets: Node, catalog: GameplayData, knowledge: Dictionary) -> void:
	_assets = assets
	_catalog = catalog
	_knowledge = knowledge
	_messages = assets.text_messages(MONSTER_TEXT_SOURCE)
	_load_frames()
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.BOOK_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	mode = Mode.BOOK
	category = 0
	cursor = 0
	scroll = 0
	grid_mode = false
	_reset_confirm()
	_render()
	show()
	open_window()


## 原生状态 16（`Game_Book_Monster_init`）：与图鉴同一张页，只把所选流派
## （`22 × mastery`）的第 4…8 格 `Param_bookSetMonster(…, 1)` 当可选遮罩，光标清零、
## `current_state_index_bits+1 = 1`（格子模式）。`species` 就是那五只候选。
func present_starter(assets: Node, catalog: GameplayData, mastery: int, species: Array) -> void:
	_assets = assets
	_catalog = catalog
	_messages = assets.text_messages(MONSTER_TEXT_SOURCE)
	_starter_species.clear()
	for entry: Variant in species:
		_starter_species.append(int(entry))
	_starter_species.sort()
	_knowledge = {Book.BOOK_MONSTERS: _starter_species.duplicate(), Book.BOOK_SKILLS: []}
	_load_frames()
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.BOOK_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	mode = Mode.STARTER
	category = mastery
	cursor = 0
	scroll = 0
	grid_mode = true
	_reset_confirm()
	_render()
	# 状态 15 与 16 共用同一张 `Field_Basic_Capture` 快照（`Evt_stdPROC` case 0x20 只抓一次），
	# 图鉴页自己开窗时也要这层模糊，否则二级页背景会变成实时画面。
	screen_shade = true
	show()
	open_window()


## 光标格在五只候选里的序号（原生 `Game_Book_Monster_mKeyPressed:71-73` 直接拿
## `22 × 流派 + transition+0` 当物种号，本工程按候选表取序号交给剧情侧）；不可选时为 -1。
func starter_choice() -> int:
	if mode != Mode.STARTER:
		return -1
	return _starter_species.find(Book.monster_id(category, cursor))


## 事件门结束／换页时复位：原生换状态时窗口直接换成另一张页，不播关窗动画。
func clear() -> void:
	_reset_confirm()
	visible = false
	stop_transition()


func handle_key(key: String) -> bool:
	if is_transitioning():
		return true
	if _confirm == ConfirmState.OPEN:
		return _confirm_key(key)
	if mode == Mode.STARTER:
		return _starter_key(key)
	if not grid_mode:
		match key:
			"ArrowLeft":
				_select_category(posmod(category - 1, Book.MONSTER_CATEGORIES))
			"ArrowRight":
				_select_category(posmod(category + 1, Book.MONSTER_CATEGORIES))
			"ArrowDown", "Enter", "Space":
				grid_mode = true
				_render()
			"Escape", "Backspace":
				_back()
			_:
				return false
		return true
	match key:
		"Escape", "Backspace":
			grid_mode = false
			_render()
		"ArrowUp":
			_step(-Book.MONSTER_COLUMNS)
		"ArrowDown":
			_step(Book.MONSTER_COLUMNS)
		"ArrowLeft":
			_step(-1)
		"ArrowRight":
			_step(1)
		"Enter", "Space":
			# 原生状态 19 的 OK 在格子里没有动作（只有角色选择用的状态 16 会确认）。
			pass
		_:
			return false
	return true


## `_process` 只为详情栏的 ACTIVE SKILL 横向滚动与立绘待机推进计时。
## `Menu_Monster_Draw3@0x575E8:112-119`：第一份画在 `x_1 - v20`，第二份画在 `v18 + x_1 - v20`
## （`v18 = WIDTH + 10`），两份始终隔 `WIDTH + 10`，所以重复文本不会和正文叠在一起。
func _process(delta: float) -> void:
	if not visible or _active_width <= 0.0:
		return
	_active_age += delta
	var clip: Control = $Content/Detail/Skills/ActiveClip
	var scrolling := _active_width > clip.size.x - 1
	var shift := fmod(maxf(0.0, _active_age - 1.0) * 40.0, _active_width + 10.0) if scrolling else 0.0
	var text: Control = clip.get_node("Text")
	var second_copy: Control = clip.get_node("Repeat")
	text.position.x = -floorf(shift)
	second_copy.position.x = text.position.x + _active_width + 10.0
	second_copy.visible = scrolling


func _back() -> void:
	back_requested.emit()


## 底部确定条：原生状态 19 的格子里 OK 没有动作（只有状态 16 会确认），所以图鉴模式下
## 这里仍只是进格子模式；状态 16 走同一条 OK 分支。
func _accept() -> void:
	if mode == Mode.STARTER:
		_open_confirm()
		return
	grid_mode = true


## 状态 16 的按键（`Game_Book_Monster_mKeyPressed:128-186`）。光标本来就在格子模式
## （`Game_Book_Monster_init` 把 `current_state_index_bits+1` 置 1），所以 CLR 直接回状态 15，
## 没有页签模式这一级。
func _starter_key(key: String) -> bool:
	match key:
		"Escape", "Backspace":
			# `:128-132`：`GameCanvas_SetNext(GAME_STATE_CHARACTER_SELECT_15, preferred_mastery_index)`。
			back_requested.emit()
		"Enter", "Space":
			# `:150-159`：只有 `Param_bookIsMonster(22 × 流派 + 光标) == 1` 才打开确认框。
			_open_confirm()
		"ArrowUp":
			_step(-Book.MONSTER_COLUMNS)
		"ArrowDown":
			_step(Book.MONSTER_COLUMNS)
		"ArrowLeft":
			_step(-1)
		"ArrowRight":
			_step(1)
		_:
			return false
	return true


## 光标格是否可选：`Param_bookIsMonster(22 × 流派 + 光标) == 1`。状态 16 的可选遮罩就是
## 「知识表里有这只」，所以格内精灵、详情与确认用的是同一个判据。
func _cursor_selectable() -> bool:
	return Book.monster_slot_exists(category, cursor) and \
		Book.contains(_knowledge, Book.BOOK_MONSTERS, Book.monster_id(category, cursor))


## 原生 OK 打开 Box2 确认框：子相位 `+2` 置 1、选项置 1（「否」）、框的窗口相位置 1
## （`Game_Book_Monster_mKeyPressed:154-158`）。
func _open_confirm() -> void:
	if _confirm == ConfirmState.OPEN or _closing_confirm or not _cursor_selectable():
		return
	_confirm = ConfirmState.OPEN
	_answer = Answer.NO
	_render_confirm()
	var confirm := $Confirm as Control
	confirm.show()
	confirm.open_window()


## 关框回列表：原生把框相位写 −1 起收拢（`Menu_win_Box2_DrawWindow` 每帧 ±1），
## `Game_Book_Monster_mRun` 收到 `MainData + 7 == −4` 才把子相位清零
## ⇒ 这里只起收拢，`_confirm` 落回 `BROWSE` 在 `_confirm_finished(false)` 里做。
func _close_confirm() -> void:
	if _confirm != ConfirmState.OPEN or _closing_confirm:
		return
	_closing_confirm = true
	($Confirm as Control).close_window()


## 宿主强制复位（`present`／`present_starter`／`clear`）：原生换页或确认时把相位直接写
## 0／−1，框同帧不再画，所以这条路径不播收拢动画。
func _reset_confirm() -> void:
	_confirm = ConfirmState.BROWSE
	_answer = Answer.NO
	_closing_confirm = false
	var confirm := $Confirm as Control
	confirm.stop_transition()
	confirm.hide()


func _render_confirm() -> void:
	($Confirm as Control).present_select(_confirm_prompt(), _answer)


## 框内按键：−4／−3 翻「是／否」（`Game_Book_Monster_mKeyPressed:107-114`）、
## −16 关框（`:99-105`）、OK 在「否」上关框（`:32-37`）、在「是」上提交（`:38-96`）。
func _confirm_key(key: String) -> bool:
	match key:
		"ArrowLeft", "ArrowRight":
			$Confirm.move_selection(-1)
			_answer = $Confirm.selection()
		"Escape", "Backspace":
			_close_confirm()
		"Enter", "Space":
			if _answer == Answer.NO or _closing_confirm:
				_close_confirm()
			else:
				$Confirm.accept()
			return false
	return true


## 确认框的收拢播完（相位 −4，`transition_finished(false)`）才回列表。
func _confirm_finished(opened: bool) -> void:
	if opened:
		return
	_reset_confirm()


## 触控：框内两块是真实 Button（原生 `EFC_mainTouchSET(-5/-3)`），点「是」直接请宿主提交。
## 触控：光标先移过去，光标已在的那颗才算确认（`chosen` 只在确认时发）。
func _on_confirm_choice(accepted: bool) -> void:
	if _confirm != ConfirmState.OPEN or _closing_confirm:
		return
	_answer = Answer.YES if accepted else Answer.NO
	if not accepted:
		_close_confirm()
		return
	starter_confirmed.emit()

## 正文 fxt 101「[%s]确定吗?」，`%s` 是 `Item_datBasic` 读出的物种名
## （`Game_Book_Monster_mPaint:33-38`）；本工程取 `common/item_mon.dat` 的组名，与详情同一份。
func _confirm_prompt() -> String:
	var species := Book.monster_id(category, cursor)
	return AssetCatalog.text_message(Msg.SOURCE, Msg.Id.STARTER_CONFIRM) % \
		str(_messages.get("item_mon.group.%d.name" % species, ""))


func _select_category(index: int) -> void:
	if index == category:
		return
	category = index
	# `Game_Book_Monster_Load` 换类别时把光标与滚动清零。
	cursor = 0
	scroll = 0
	_render()


func _select_slot(slot: int) -> void:
	var target := scroll + slot
	# 状态 16 没有登记触控区（`Menu_mon_DrawBookList` 全文没有 `EFC_mainTouchSET`）；本工程的格
	# 仍是真实 Button，沿用一级页「点光标格 = OK」的同一条规则（`mastery_view.press_row`）。
	if mode == Mode.STARTER and grid_mode and target == cursor:
		_open_confirm()
		return
	grid_mode = true
	cursor = target
	var chosen := Book.monster_scroll(cursor, scroll)
	if chosen == scroll:
		_render()
	else:
		scroll = chosen
		_render()


func _step(delta: int, enter := true) -> void:
	if enter:
		grid_mode = true
	cursor = Book.step_monster_cursor(cursor, delta)
	scroll = Book.monster_scroll(cursor, scroll)
	_render()


func _load_frames() -> void:
	# 格底四帧（`Menu_winDrawIcon16`）与其它页面共用 `assets/ui/slot/` 的同一份切片。
	_cell_frames = SlotFrames.frames()
	_tab_frames.clear()
	var tabs: Texture2D = _assets.load_sprite(TAB_SHEET)
	for index in range(Book.MONSTER_CATEGORIES):
		_tab_frames.append(_slice(tabs, Rect2i(index * 33, 0, 33, 30)))
	_rarity_frames.clear()
	var rarity: Texture2D = _assets.load_window_frame(RARITY_FRAME)
	for region: Rect2i in RARITY_REGIONS:
		_rarity_frames.append(_slice(rarity, region))
	_stat_labels.clear()
	var labels: Texture2D = _assets.load_window_frame(STAT_LABEL_FRAME)
	for row: int in STAT_LABEL_ROWS:
		_stat_labels.append(_slice(labels, Rect2i(0, row * 5, 23, 5)))
	_attribute_frames.clear()
	var attributes: Texture2D = _assets.load_sprite(ATTRIBUTE_SHEET)
	for index in range(Book.MONSTER_CATEGORIES):
		_attribute_frames.append(_slice(attributes, Rect2i(index * 13, 0, 13, 13)))


func _render() -> void:
	_render_tabs()
	_render_grid()
	_render_detail()


func _render_tabs() -> void:
	for index in range(Book.MONSTER_CATEGORIES):
		var frame: TextureRect = $Content.get_node("Tab%d/Frame" % index)
		frame.texture = _tab_frames[index]
		# 未选中的页签按 `GRP_MODE_GRAY` 画成灰度。
		frame.material.set_shader_parameter("grayscale", index != category)


func _render_grid() -> void:
	for slot in range(Book.MONSTER_COLUMNS * Book.MONSTER_ROWS):
		var row := scroll + slot
		var cell := $Content.get_node("Cell%d" % slot) as ItemCell
		# 原生 `Menu_winDrawIcon16` 的帧 2／3（X）只给超出 22 条记录的格子；
		# 记录范围内但还没获得的格子仍是普通格（帧 0／1），只是不画精灵。
		var exists := Book.monster_slot_exists(category, row)
		var found := exists and Book.contains(_knowledge, Book.BOOK_MONSTERS,
			Book.monster_id(category, row))
		var focused := grid_mode and row == cursor
		cell.set_frame_texture(_cell_frames[SlotFrame.index(exists, focused)])
		cell.set_grade(null)
		var monster: Node2D = cell.get_node("Clip/Monster")
		monster.visible = found
		if not found:
			continue
		var species := Book.monster_id(category, row)
		var record: MonsterDefinition = _catalog.monster(species)
		var rarity: int = record.attribute_entry if record != null else -1
		if rarity in range(SlotGrade.BALL_GRADE_RGB.size()):
			cell.set_grade(SlotGrade.BALL_GRADE_RGB[rarity])
		if not monster.present(MonsterAnimation.battle_identity(species), 0, 0):
			push_error(monster.last_error)
		# 原生只把 `MainData.frames_since_canvas_change` 交给光标格
		# （`v24 && FieldData_2 == FieldData_1`），其余格传 0，即停在第一帧。
		monster.set_running(focused, true)
		monster.position = _icon_anchor(species)
	_update_scrollbar()


func _update_scrollbar() -> void:
	var scrollbar: Control = $Content/Scroll
	var pages: int = (Book.MONSTER_SLOTS + Book.MONSTER_COLUMNS - 1) / Book.MONSTER_COLUMNS
	scrollbar.call("set_page", cursor / Book.MONSTER_COLUMNS, pages)


func _render_detail() -> void:
	var detail: Control = $Content/Detail
	var species := _cursor_species()
	var record: MonsterDefinition = _catalog.monster(species) if species >= 0 else null
	var ball := Book.native_ball(_catalog, species) if species >= 0 else {}
	var portrait: Control = detail.get_node("Portrait")
	var monster: Node2D = portrait.get_node("Clip/Monster")
	monster.visible = not ball.is_empty()
	monster.get_node("Content").position = Vector2.ZERO
	if monster.visible:
		if not monster.present(MonsterAnimation.battle_identity(species), 0, 0):
			push_error(monster.last_error)
		monster.position = PORTRAIT_ANCHOR
		var offset: Vector2 = record.portrait_offset[0] \
			if not record.portrait_offset.is_empty() else Vector2.ZERO
		monster.get_node("Content").position = Vector2(offset.x, -offset.y)
	detail.get_node("Vitals").visible = monster.visible
	if monster.visible:
		# `Game_monDraw2`：HP 只画当前值，SP 画「当前/上限」。
		detail.get_node("Vitals/HP/Number").present(str(int(ball.hp)))
		detail.get_node("Vitals/SP/Number").present("%d/%d" % [int(ball.sp), int(ball.max_sp)])
	detail.get_node("Number").present("%03d" % (species + 1 if species >= 0 else 0))
	var grade: int = record.attribute_entry if record != null else -1
	var rarity: TextureRect = detail.get_node("Rarity")
	rarity.visible = grade in range(_rarity_frames.size())
	if rarity.visible:
		rarity.texture = _rarity_frames[grade]
		rarity.size = _rarity_frames[grade].get_size()
	detail.get_node("Name").text = str(_messages.get(
		"item_mon.group.%d.name" % species, "")) if species >= 0 else ""
	var group: int = record.attribute_group - 1 if record != null else -1
	var attribute: TextureRect = detail.get_node("Vitals/Attribute")
	attribute.visible = group in range(_attribute_frames.size())
	if attribute.visible:
		attribute.texture = _attribute_frames[group]
	for index in range(6):
		var metric: Control = detail.get_node("Stat%d" % index)
		metric.get_node("Icon").texture = _stat_labels[index]
		# 空记录（未获得或 X 格）原生画 0，不是隐藏。
		metric.get_node("Number").present(str(_stat_value(ball, index)))
	_present_active(str(_messages.get("item_mon.group.%d.entry.0.name" % species, ""))
		if species >= 0 and mode == Mode.BOOK else "")
	if mode == Mode.STARTER:
		_present_prompt()


func _stat_value(ball: Dictionary, index: int) -> int:
	if ball.is_empty():
		return 0
	match index:
		4:
			return int(ball.max_hp)
		5:
			return int(ball.speed)
		_:
			return Battle.effective_stat(ball, index)


## 状态 16（初始精灵选择）走 `Menu_Monster_Draw3` 的 book 分支：底栏不画 ACTIVE SKILL，
## 只在窗口中心画 `common/msg.fxt:152`「请选择精灵」。状态 19（图鉴）才画技能文本。
func _present_prompt() -> void:
	_active_width = 0.0
	$Content/Detail/Skills/Arrow.visible = false
	$Content/Detail/Skills/Active.visible = false
	$Content/Detail/Skills/ActiveClip.visible = false
	var prompt: Control = $Content/Detail/Skills/Prompt
	prompt.text = _assets.text_message(Msg.SOURCE, 152) if _assets != null else "请选择精灵"
	prompt.visible = true


## `Menu_Monster_Draw3@0x575E8:98-102` 的 ACTIVE SKILL：`#PF95#C0[` 起技能名、`]#C6` 起说明。
## `#PF95` 是调色板定义（`(r << 20) | (g << 12) | (16 * b)` → `#F09050`），`#C0`／`#C6` 是字体
## 调色板下标；本工程把两段颜色直接写进 markup，颜色来源仍是场景里的 `Text.color`（与状态页同一份）。
func _present_active(source: String) -> void:
	$Content/Detail/Skills/Active.visible = true
	$Content/Detail/Skills/Prompt.visible = false
	$Content/Detail/Skills/ActiveClip.visible = true
	if source == _active_text:
		return
	_active_text = source
	_active_age = 0.0
	var clip: Control = $Content/Detail/Skills/ActiveClip
	# 箭头跟着正文一起出现（原生 `Menu_battleDrawIcon8` 在正文分支末尾才画）。
	$Content/Detail/Skills/Arrow.visible = not source.is_empty()
	var parts := source.split("/", true, 1)
	var title := "[%s]" % parts[0] if not source.is_empty() else ""
	var text := title + (parts[1] if parts.size() > 1 else "")
	var label: Control = clip.get_node("Text")
	var markup := "[color=#%s]%s[/color][color=#%s]%s[/color]" % [
		label.color.to_html(false), title, Color.WHITE.to_html(false), text.substr(title.length())]
	var layout := TextLayout.layout(markup, label.theme.default_font, label.theme.default_font_size)
	_active_width = 0.0
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	_active_width = layout.lines[0].width if not layout.lines.is_empty() else 0.0
	for node in [clip.get_node("Text"), clip.get_node("Repeat")]:
		node.text = text
		node.set_line(layout.lines[0])


## 光标格有物种且已获得才给详情；原生对未获得／X 格只画空记录（NO.000、0 数值）。
func _cursor_species() -> int:
	if not Book.monster_slot_exists(category, cursor):
		return -1
	var species := Book.monster_id(category, cursor)
	if not Book.contains(_knowledge, Book.BOOK_MONSTERS, species):
		return -1
	if _catalog == null or _catalog.monster(species) == null:
		return -1
	return species


func _icon_anchor(species: int) -> Vector2:
	return MonsterDefinition.icon_anchor(_catalog.monster(species) if _catalog != null else null)


func _slice(texture: Texture2D, region: Rect2i) -> Texture2D:
	if texture == null:
		return null
	var sliced := AtlasTexture.new()
	sliced.atlas = texture
	sliced.region = region
	return sliced

