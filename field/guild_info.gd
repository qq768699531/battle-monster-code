extends "res://ui/window_transition.gd"

## 原生 `Field_Guild_Info_Detail_*`（`FieldCanvas` 状态 9）：
## `Field_Guild_Info_Detail_init`（`EFC_fsLoadRES("common/guild.fxt")`、开窗计数置 1）／
## `mRun`（关窗计数到 −4 才 `SetNext(6, 2)`：回列表页并把光标放回第 3 行）／
## `mKeyPressed`／`mPaint`。
##
## 窗口 228×208 @ (86, 16)、**侧白边 12**、header 16；标题 `msg 60`，副标题 `msg 61`
## （「[会长的建议]」，`0xFFFFAA`）居中于 `y+27`。
## 面板外框 `#196485` `(x+20, y+43, 188, 147)`，框内 `y+64` 一条 2 px 虚线（起点 `x+32`、步距 3）。
## 一页 = `common/guild.fxt` 的两条记录：标签 = 记录 `2·页号`（`#FFB655`，居中于 `(x+114, y+49)`）、
## 正文 = 记录 `2·页号+1`（白色，`JC_fntGetPage` 最大行宽 158、最多 9 行，`y+72` 起每行 +12）。
## `FieldData+0x20` 页号、`+0x24` 页数、`+0x34` 行滚动（夹在 `0 .. 行数−9`）；`−3` 上页、`−4` 下页
## （换页把滚动清零）、`−1`/`−2` 行滚动、`−16` 关窗（回列表页，参数 2）。

signal closed

const INFO_SOURCE := "common/guild.fxt"
## 一页固定 9 行（native `y+72` 起 12 px 步距到 `y+168`）。
const ROWS := 9
const TEXT_WIDTH := 158.0
const TextLayout = preload("res://ui/native_text_layout.gd")

## `FieldData+0x20`／`+0x24`／`+0x34`。
var page := 0
var page_count := 0
var scroll := 0

var _pages: Array = []
var _closing := false


func _ready() -> void:
	super()
	transition_finished.connect(_transition_finished)
	$Content/PrevHit.pressed.connect(_step_page.bind(-1))
	$Content/NextHit.pressed.connect(_step_page.bind(1))


## `start_page` = 进入本页时的 transition 参数（原生从列表页进是 0）。
func present(assets: Node, start_page: int = 0) -> void:
	_closing = false
	_pages = _load_pages(assets)
	page_count = _pages.size()
	if page_count == 0:
		hide()
		return
	page = clampi(start_page, 0, page_count - 1)
	scroll = 0
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.GUILD_INFO_TITLE)
	$Content/Subtitle.text = assets.text_message(Msg.SOURCE, Msg.Id.GUILD_INFO_SUBTITLE)
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
	match key:
		"ArrowLeft":
			_step_page(-1)
		"ArrowRight":
			_step_page(1)
		"ArrowUp":
			_scroll_by(-1)
		"ArrowDown":
			_scroll_by(1)
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


## 原生 `(页号 ± 1) % 页数`：换页同时把 `FieldData+0x34`（滚动）清零。
func _step_page(step: int) -> void:
	if _closing or is_transitioning() or page_count == 0:
		return
	page = posmod(page + step, page_count)
	scroll = 0
	_render()


func _scroll_by(step: int) -> void:
	if _closing or is_transitioning() or page_count == 0:
		return
	var rows: int = _pages[page].lines.size()
	var before := scroll
	scroll = clampi(scroll + step, 0, maxi(0, rows - ROWS))
	if scroll != before:
		_render()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	closed.emit()


func _render() -> void:
	var entry: Dictionary = _pages[page]
	var lines: Array = entry.lines
	scroll = clampi(scroll, 0, maxi(0, lines.size() - ROWS))
	$Content/Label.text = entry.label
	for index in range(ROWS):
		var row: Control = get_node("Content/Body/Line%d" % index)
		var at: int = scroll + index
		row.visible = at < lines.size()
		if row.visible:
			row.set_line(lines[at])
	$Content/Page.visible = page_count > 1
	$Content/Page.text = "%d/%d" % [page + 1, page_count]
	$Content/Scroll.visible = lines.size() > ROWS
	if $Content/Scroll.visible:
		_place_scroll(lines.size())


## `Menu_Item_DrawScroll(面板右−16, y+72, 106, 滚动值, 行数−8)`：拇指按行数比例占轨道。
func _place_scroll(rows: int) -> void:
	var bar: Control = $Content/Scroll
	var track: float = bar.size.y - 20.0
	var thumb: float = maxf(4.0, track * float(ROWS) / float(rows))
	var limit: float = float(maxi(1, rows - ROWS))
	var at: float = 10.0 + (track - thumb) * float(scroll) / limit
	bar.get_node("Thumb").offset_top = at
	bar.get_node("Thumb").offset_bottom = at + thumb


## `common/guild.fxt` 的记录是「标签, 正文」成对出现的；正文按原生最大行宽 158 折行。
func _load_pages(assets: Node) -> Array:
	if not assets.has_text(INFO_SOURCE):
		push_error("缺少原生文本源 %s，资料页没有正文可显示。" % INFO_SOURCE)
		return []
	var messages: Dictionary = assets.text_messages(INFO_SOURCE)
	var records: Array[int] = []
	for record: Variant in messages.keys():
		records.append(int(record))
	records.sort()
	if records.is_empty() or records.size() % 2 != 0:
		push_error("原生文本源 %s 的记录数不是「标签 + 正文」成对：%d。" % [INFO_SOURCE, records.size()])
		return []
	var result: Array = []
	for index in range(records.size() / 2):
		var body: String = str(messages[records[2 * index + 1]])
		var layout := TextLayout.layout(body, Layout.UI_FONT, Layout.FONT_SIZE, TEXT_WIDTH)
		if not layout.error.is_empty():
			push_error(layout.error)
			return []
		result.append({"label": str(messages[records[2 * index]]), "lines": layout.lines})
	return result
