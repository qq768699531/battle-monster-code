extends "res://engine/ui/window_transition/window_transition.gd"

## 原生 `Game_Book_Skill`（GAME_STATE_BOOK_SKILL）：228×227 窗口。
##
## 依据：
## * `Game_Book_Skill_init`：开窗 + 技能书条数（`Item_passiveCount`）。
## * `Menu_skill_DrawBookList`：标题「图鉴」、副标题 `JC_fxt2Return(166)`「[技能书]」居中、
##   格框 (x+8, y+43, 212, 132)、6×4 个 30×30 格子（步距 32，起点 (x+11, y+46)）、
##   右侧 124 高的滚动条、下方 32 高的详情（NO. + 品级色的 `[ 名称 ]` + 白色说明）。
## * `Game_Book_Skill_mKeyPressed`：四方向按 6 的倍数取模移动、CLR 回图鉴目录，OK 无动作。
## 技能书不是分类表，168 条正好 7 页，所以格子里不会出现 X 帧。

signal back_requested

const Book = preload("res://game/menu/book/book_model/book_model.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")
const SlotFrames = preload("res://game/menu/party/slot_frames/slot_frames.gd")
const SlotGrade = preload("res://game/menu/party/slot_grade/slot_grade.gd")
const SKILL_TEXT_SOURCE := "common/item_skill.dat"
const CELL_COLUMNS := 6
const CELL_ROWS := 4
## 无品级／越界品级落到默认调色板 `#C6`，即品级 0 的白
## （`Item_stdGradeINDEX@0x812C8` 越界返回空串，`Item_stdGradeRGB@0x81318` 越界返回 `0xFFFFFF`）。
const WHITE_GRADE_INDEX := 0

var cursor := 0
var scroll := 0

var _assets: Node
var _catalog: GameplayData
var _knowledge: Dictionary = {}
var _messages: Dictionary = {}
var _cell_frames: Array[Texture2D] = []
var _count := 0
var _desc_width := 0.0
var _desc_age := 0.0


func _ready() -> void:
	super()
	for index in range(CELL_COLUMNS * CELL_ROWS):
		$Content.get_node("Cell%d" % index).pressed.connect(_select_slot.bind(index))
	$Content/Scroll/UpHit.pressed.connect(func(): _step(-CELL_COLUMNS))
	$Content/Scroll/DownHit.pressed.connect(func(): _step(CELL_COLUMNS))
	$Content/BackHit.pressed.connect(_back)


func present(assets: Node, catalog: GameplayData, knowledge: Dictionary) -> void:
	_assets = assets
	_catalog = catalog
	_knowledge = knowledge
	_messages = assets.text_messages(SKILL_TEXT_SOURCE)
	_count = mini(catalog.passives.size(), Book.SKILL_SLOTS)
	_load_frames()
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.BOOK_TITLE)
	$Content/Subtitle.text = assets.text_message(Msg.SOURCE, Msg.Id.BOOK_SKILL_SUBTITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	cursor = 0
	scroll = 0
	_render()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if is_transitioning():
		return true
	match key:
		"Escape", "Backspace":
			_back()
		"ArrowUp":
			_step(-CELL_COLUMNS)
		"ArrowDown":
			_step(CELL_COLUMNS)
		"ArrowLeft":
			_step(-1)
		"ArrowRight":
			_step(1)
		"Enter", "Space":
			# 原生技能书里的 OK 没有动作。
			pass
		_:
			return false
	return true


func _process(delta: float) -> void:
	if not visible:
		return
	var clip: Control = $Content/Detail/DescClip
	if _desc_width <= 0.0:
		return
	_desc_age += delta
	var scrolling := _desc_width > clip.size.x
	var shift := fmod(maxf(0.0, _desc_age - 1.0) * 40.0, _desc_width + 40.0) if scrolling else 0.0
	clip.get_node("Desc").position.x = -floorf(shift)


func _back() -> void:
	back_requested.emit()


func _select_slot(slot: int) -> void:
	cursor = scroll + slot
	scroll = Book.skill_scroll(cursor, scroll)
	_render()


func _step(delta: int) -> void:
	cursor = Book.step_skill_cursor(cursor, delta, _count)
	scroll = Book.skill_scroll(cursor, scroll)
	_render()


func _load_frames() -> void:
	# 格底四帧（`Menu_winDrawIcon16`）与其它页面共用 `assets/ui/slot/` 的同一份切片。
	_cell_frames = SlotFrames.frames()


func _render() -> void:
	for slot in range(CELL_COLUMNS * CELL_ROWS):
		var row := scroll + slot
		var cell := $Content.get_node("Cell%d" % slot) as ItemCell
		var in_range := row < _count
		var found := in_range and Book.contains(_knowledge, Book.BOOK_SKILLS, row)
		var focus := row == cursor
		cell.present_frame(_cell_frames[SlotFrame.index(in_range, focus)], focus)
		var icon: Control = cell.get_node("Icon")
		cell.get_node("QuantityNumber").hide()
		cell.get_node("Quantity").hide()
		icon.texture = null
		cell.set_grade(null)
		if not found:
			continue
		var record: ItemDefinition = _catalog.item(ItemKind.id_of(ItemKind.Kind.SKILL_BOOK, row))
		if record == null:
			continue
		icon.texture = _assets.item_icon(int(record.icon))
		if record.grade_index in range(SlotGrade.ITEM_GRADE_RGB.size()):
			cell.set_grade(SlotGrade.ITEM_GRADE_RGB[record.grade_index])
	_update_scrollbar()
	_render_detail()


func _update_scrollbar() -> void:
	var scrollbar: Control = $Content/Scroll
	var pages := Book.skill_cursor_slots(_count) / CELL_COLUMNS
	scrollbar.call("set_page", cursor / CELL_COLUMNS, pages)


## `Menu_skill_DrawBookList` 的详情：NO. 是「技能号 + 1」，名称与说明来自技能书道具记录的
## `name_text`／`detail_text`（`Item_datBasic` 类型 31：名称是 `item_skill.group.N.name`，
## 说明是该记录 `entry.0` 的正文；这一槽为空时原生向前退到最近一条非空记录，
## `ItemDefinition.result_description_record` 在导出时已按这条规则解析，所以这里不再自己拼
## `group.N.entry.0.name`）；未获得的格显示 NO.000 且不画名称／说明。
##
## 颜色分工（`Menu_skill_DrawBookList@0x55F8C`）：
## * `:238-240` 名称行 = `Item_stdGradeINDEX@0x812C8` 的 `#C6..#C9` + `[ 名称 ]`。那四个下标是
##   `Item_stdGradeRGB@0x81318` 按品级 0..3 写进调色板 6..9 的
##   `#FFFFFF`／`#C676FB`／`#FCCF45`／`#FF2020`（`Item_Initialize@0x87640:30-36`），
##   与格框描边同一张 `SlotGrade.ITEM_GRADE_RGB`；
## * `:246` 说明行固定 `#C6`（白），不随品级变化；
## * 列表格没有文字，品级只体现在 `Menu_Item_DrawItem` 的格框描边（`cell.set_grade`）。
func _render_detail() -> void:
	var detail: Control = $Content/Detail
	var found := cursor < _count and Book.contains(_knowledge, Book.BOOK_SKILLS, cursor)
	detail.get_node("Number").present("%03d" % (cursor + 1 if found else 0))
	var record: ItemDefinition = _catalog.item(ItemKind.id_of(ItemKind.Kind.SKILL_BOOK, cursor)) \
		if found else null
	var name := str(_messages.get("item_skill.group.%d.name" % cursor, "")) if found else ""
	# 说明取道具记录自己的正文（与 `menu/items.gd` 的书籍结果行同一入口）；记录没有说明槽时
	# 原生 `Menu_skill_DrawBookList` 也不画这一行，所以留空而不是回落其它来源。
	var description := ""
	if found and record != null and not record.result_description_record.is_empty():
		description = str(_messages.get(record.result_description_record, ""))
	var name_label: Control = detail.get_node("Name")
	name_label.text = "[ %s ]" % name if not name.is_empty() else ""
	_paint_line(name_label, name_label.text, _grade_color(record))
	var label: Control = detail.get_node("DescClip/Desc")
	label.text = description
	_desc_age = 0.0
	_desc_width = 0.0
	label.position.x = 0.0
	if description.is_empty():
		return
	var layout := _paint_line(label, description, SlotGrade.ITEM_GRADE_RGB[WHITE_GRADE_INDEX])
	if layout.is_empty():
		return
	_desc_width = layout.lines[0].width if not layout.lines.is_empty() else 0.0


## 品级 → 文字颜色：`Item_stdGradeINDEX@0x812C8` 只在品级 0..3 返回 `#C6..#C9`，
## 其余（含没有记录）返回空串，落到默认调色板 `#C6`（白）。颜色表直接复用格框描边那张
## `SlotGrade.ITEM_GRADE_RGB`（`Item_stdGradeRGB` 的 `CSWTCH.125[0..3]`），不另起一份。
func _grade_color(record: ItemDefinition) -> Color:
	var grade := record.grade_index if record != null else WHITE_GRADE_INDEX
	if grade < 0 or grade >= SlotGrade.ITEM_GRADE_RGB.size():
		grade = WHITE_GRADE_INDEX
	return SlotGrade.ITEM_GRADE_RGB[grade]


## 用内联色标把一行正文染成 `color`，再由 `NativeLabel.set_line` 逐字形上色
## （与 `book_monster.gd` 的 ACTIVE SKILL 同一做法）。调用方先把 `text` 写进标签，
## 空正文只清掉上一次的行数据。
func _paint_line(label: Control, text: String, color: Color) -> Dictionary:
	if text.is_empty():
		return {}
	var markup := "[color=#%s]%s[/color]" % [color.to_html(false), text]
	var layout := TextLayout.layout(markup, label.theme.default_font,
		label.theme.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return {}
	label.set_line(layout.lines[0])
	return layout
