extends Control

## 原生 `Evt_scrInit`／`Evt_scrDRAW`／`Evt_stdPAINT1`：叙事字幕（事件 opcode 4）把 CHT 组里
## 每条记录当一页；页内按步推进——每步 1000 ms 放出一行（最新一行在这一步内淡入），行放完后再
## 保持 3 步，然后从第一行起逐行淡出；一页走完由 `Evt_scrNEXT` 换下一条记录，没有下一条就结束。
## 步长与淡入／淡出的比例都由 Scene 的 `Rhythm/step` 动画轨给出（长度 1 秒、`.:ramp` 0→1），
## 本脚本只按原生公式摆块、切步与切页，时间量全部来自这条轨。
##
## 版式号＝原生 `EvtData.required_item_quantity`（叙事脚本 p[1]），见
## `Evt_scrDRAW:18-35`／`:144-151`（位置与字色）与 `Evt_stdPAINT1:32-46`（填不填背景）。
enum Format {
	## 全屏填黑、白字，块心 `height / 2`
	WHITE_ON_BLACK = 1,
	## 全屏填白、黑字，块心 `height / 2`
	BLACK_ON_WHITE = 2,
	## 不填背景、白字＋1 px 黑描边，块心 `height / 3`
	OUTLINE_ON_THIRD = 3,
}

## `Evt_scrDRAW:39-134` 的三段，按步号与页行数比较得到。
enum Phase {
	## `R <= n`：放出到第 R 行，最新一行淡入
	REVEAL,
	## `n < R <= n + 3`：整页常亮
	HOLD,
	## `n + 3 < R <= 2n + 3`：从第一行起逐行淡出
	FADE,
}

## `Evt_scrDRAW:41` 的 `page_count + 3`：最后一行放出后再保持 3 步。
const HOLD_STEPS := 3
## `Evt_scrDRAW:66` 的 `2 * page_count + 3`：放出 n 步之后再走「保持 3 步 + 淡出 n 步」，共 2 遍行数。
const LINE_PASSES := 2
## `Evt_scrDRAW:38` 的 `(acc << 8) / 1000` 与 `:90` 的 `256 - acc`：alpha 用 256 级刻度。
const ALPHA_SCALE := 256
## 版式 3 的 1 px 黑描边：原生每行先 `SetBOLD(1) + SetRGB(0, 0)` 画一遍再画白字（`Evt_scrDRAW:52-58`）。
const OUTLINE_SIZE := 1
## 换行宽度＝`viewport.width - 50`（`Evt_scrInit:29` 传给 `JC_fntGetPage` 的 `maximum_line_width`）。
const TEXT_MARGIN := 50
## Scene 里 `Rhythm` 的步动画名：一步＝原生 `Evt_scrDRAW:136-140` 的 1000 ms。
const RHYTHM_ANIMATION := &"step"

var placement: int = Format.WHITE_ON_BLACK
var last_error := ""
## Scene 的 `Rhythm/step` 每帧写进来：本步已过的比例（0→1），给最新一行／淡出行算 alpha。
var ramp: float = 0.0

## 每条记录一页（原生一次 `Evt_scrInit` 读一条记录），页内各行由 `_wrap` 切。
var _pages: Array = []
var _page := 0
## 原生 `EvtRes.scrolling_text.page + 228`：步号 R，`Evt_scrInit:17` 置 1，`Evt_scrDRAW:138` 每步加一。
var _step := 1
## 原生 `EvtRes.scrolling_text.page` 的 `PixelData.viewport`：字幕按它算块心与折行宽度。
var _viewport_size := Vector2i.ZERO
## 行距与行框高都取 Scene 里 `Lines/Line0..2` 的摆放：原生 `Evt_scrDRAW:49/86/116` 每行
## `y += extra_line_spacing + 10`（`extra_line_spacing` 由 `Evt_scrInit:30` 传入的 10 决定），
## 块高用 `:33-34` 的 `10 * page_count`。
var _line_advance := 0
var _glyph_height := 0
var _font: Font
var _font_size := 0
var _done := false

@onready var _lines: Control = $Lines
@onready var _rhythm: AnimationPlayer = $Rhythm


func _ready() -> void:
	visible = false
	_font = _lines.get_theme_font("font")
	if _font == null:
		last_error = "字幕字体缺失"
	_viewport_size = Vector2i(int(_lines.offset_right - _lines.offset_left),
		int(_lines.offset_bottom - _lines.offset_top))
	var first: Label = _lines.get_child(0) as Label
	var second: Label = _lines.get_child(1) as Label
	_line_advance = int(second.offset_top - first.offset_top)
	_glyph_height = int(first.offset_bottom - first.offset_top)
	_font_size = first.get_theme_font_size("font_size")


## 建立字幕：`records` 是 CHT 组记录，`layout` 是版式号（原样收下，1–3 之外的取值也要跑完时间轴）。
## 返回 false 表示没有任何正文（翻译缺失），调用方应立即结束该指令而不是显示空白屏。
func present(records: Array, layout: int) -> bool:
	placement = layout
	_pages.clear()
	for record: Variant in records:
		if not record is Dictionary:
			continue
		var text: Variant = record.get("text")
		if text is String and not text.is_empty():
			_pages.append(_wrap(text))
	if _pages.is_empty():
		last_error = "叙事字幕没有正文"
		return false
	_apply_backdrop()
	_page = 0
	_step = 1
	ramp = 0.0
	_done = false
	_present_page()
	_rhythm.play(RHYTHM_ANIMATION)
	visible = true
	return true


## 原生把每帧的毫秒数累进 `page + 220`（`Evt_scrDRAW:136-140`），满 1000 ms 就把
## `page + 228`（步号）+1；推进本身交给 Scene 的 `Rhythm/step`。这里按**整步数**结算：
## 每满一步就调一次 `_on_rhythm_finished`（与动画自己的 `animation_finished` 同一入口），
## 余量再灌给新起的这一步。
##
## 不用 `current_animation_length - current_animation_position` 当步长：动画刚播完那一刻
## 位置等于长度、`_on_rhythm_finished` 里的 `play()` 也不保证立刻把位置清零，算出来是 0，
## `remaining` 就永远减不下去——`test_narration_view` 因此空转挂住过。
func advance(delta: float) -> void:
	if not visible or _done or not is_finite(delta) or delta <= 0.0:
		return
	var step_seconds: float = _rhythm.get_animation(RHYTHM_ANIMATION).length
	if step_seconds <= 0.0:
		# 场景里没有这一步动画就没有可推的步长；宁可不动，也不能空转。
		return
	var remaining := delta
	while remaining >= step_seconds and not _done:
		remaining -= step_seconds
		_on_rhythm_finished(RHYTHM_ANIMATION)
	if not _done and remaining > 0.0:
		_rhythm.advance(remaining)
	_present_page()


## 一步走完（`Rhythm/step` 的 `animation_finished`，见 `narration_view.tscn` 的连接）：
## `R >= 2n + 4` 时调 `Evt_scrNEXT`（`Evt_scrDRAW:65-73`），没有下一条记录就结束整条指令。
func _on_rhythm_finished(_finished_animation: StringName) -> void:
	if _done:
		return
	_step += 1
	if _step > _line_count() * LINE_PASSES + HOLD_STEPS:
		if _page + 1 >= _pages.size():
			_done = true
			return
		_page += 1
		_step = 1
	_rhythm.play(RHYTHM_ANIMATION)


## 确定键：`Evt_stdKEY:51-55` 在字幕步骤只放行键码 35（确定）并直接置 `+10`，
## `Evt_stdPROC:168-171` 下一帧调 `Evt_scrFINAL` 清场再跳到下一条记录——
## 也就是说确定键**结束整条叙事指令**（连未播的页一起丢），不是快进到最后一页最后一行。
func finish() -> void:
	if not visible or _done:
		return
	_done = true
	_rhythm.stop()


func finished() -> bool:
	return _done


func clear() -> void:
	visible = false
	_done = false
	_pages.clear()
	_page = 0
	_step = 1
	ramp = 0.0
	_rhythm.stop()


func _line_count() -> int:
	return (_pages[_page] as Array).size()


func _wrap(text: String) -> Array[String]:
	var lines: Array[String] = []
	var limit := float(_viewport_size.x - TEXT_MARGIN)
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	for paragraph: String in normalized.split("\n"):
		var line := ""
		for character_index in range(paragraph.length()):
			var character := paragraph.substr(character_index, 1)
			var candidate := line + character
			if not line.is_empty() and _font.get_string_size(candidate,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x > limit:
				lines.append(line)
				line = character
			else:
				line = candidate
		lines.append(line)
	return lines


## `Evt_stdPAINT1:32-46`：版式 1 填黑、版式 2 填白；版式 3 与其余取值都不填（`case 3: return 0`）。
func _apply_backdrop() -> void:
	var back: ColorRect = $Back
	back.visible = placement == Format.WHITE_ON_BLACK or placement == Format.BLACK_ON_WHITE
	back.color = Color.BLACK if placement == Format.WHITE_ON_BLACK else Color.WHITE


## `Evt_scrDRAW:152-159`：只有版式 1 设白、版式 2 设黑；版式 3 每行自己设白（`:52-58`）。
## 其余取值原生不调 `JC_fntSetRGB`（沿用调色板残留色，无从复现），这里固定按白字画。
func _text_color() -> Color:
	return Color.BLACK if placement == Format.BLACK_ON_WHITE else Color.WHITE


func _outlined() -> bool:
	return placement == Format.OUTLINE_ON_THIRD


## `Evt_scrDRAW:18-35`／`:144-151`：版式 1／2 的块心是 `(width / 2, height / 2)`，版式 3 是
## `(width / 2, height / 3)`；其余一切取值走 `v2 = 0; x = 0`，整块画到屏幕左上角之外。
func _block_center() -> Vector2i:
	match placement:
		Format.WHITE_ON_BLACK, Format.BLACK_ON_WHITE:
			return Vector2i(_viewport_size.x / 2, _viewport_size.y / 2)
		Format.OUTLINE_ON_THIRD:
			return Vector2i(_viewport_size.x / 2, _viewport_size.y / 3)
		_:
			return Vector2i.ZERO


## `extra_line_spacing * (n - 1) + 10 * n`（`Evt_scrDRAW:33-34`）。
func _block_height(count: int) -> int:
	return _line_advance * (count - 1) + _glyph_height


func _phase(count: int) -> Phase:
	if _step <= count:
		return Phase.REVEAL
	if _step <= count + HOLD_STEPS:
		return Phase.HOLD
	return Phase.FADE


## `Evt_scrDRAW:79`：`R - 1 - (n + 3)`，即这一步正在淡出的行号。
func _fading_line(count: int) -> int:
	return _step - count - HOLD_STEPS - 1


func _line_visible(index: int, count: int, phase: Phase) -> bool:
	match phase:
		Phase.REVEAL:
			return index < _step
		Phase.HOLD:
			return true
		_:
			return index >= _fading_line(count)


## `Evt_scrDRAW:38` 的 `ramp = (acc << 8) / 1000`：放出阶段最新一行用 `ramp`，淡出阶段那一行用
## `ALPHA_SCALE - ramp`（`:90`），其余行全不透明（`:92`／`:120` 的 `JC_grpReset`）。`ramp` 由 Scene
## 的动画轨按比例写入，这里只做原生的 256 级取整。
func _line_alpha(index: int, count: int, phase: Phase) -> float:
	var level := int(ramp * ALPHA_SCALE)
	if phase == Phase.REVEAL and index == _step - 1:
		return float(level) / ALPHA_SCALE
	if phase == Phase.FADE and index == _fading_line(count):
		return float(ALPHA_SCALE - level) / ALPHA_SCALE
	return 1.0


func _present_page() -> void:
	var lines: Array = _pages[_page]
	var count := lines.size()
	_grow_lines(count)
	var phase := _phase(count)
	var center := _block_center()
	_lines.position = Vector2(center.x - _viewport_size.x * 0.5, center.y - _block_height(count) / 2)
	for index in range(_lines.get_child_count()):
		var label := _lines.get_child(index) as Label
		label.visible = index < count and _line_visible(index, count, phase)
		if not label.visible:
			continue
		label.text = str(lines[index])
		label.add_theme_color_override("font_color", _text_color())
		if _outlined():
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
		else:
			label.remove_theme_constant_override("outline_size")
		label.modulate = Color(1, 1, 1, _line_alpha(index, count, phase))


## Scene 只摆数据实测的最大行数（3 行，`wiki\ui\chat-log-formats.md` §5）；记录折行更多时按同一行距补，
## 不另起一套版式（原生对 `page_count` 没有上限，块会整体溢出屏幕）。
func _grow_lines(count: int) -> void:
	while _lines.get_child_count() < count:
		var extra := _lines.get_child(_lines.get_child_count() - 1).duplicate() as Label
		extra.name = "Line%d" % _lines.get_child_count()
		extra.text = ""
		extra.visible = false
		extra.position = Vector2(0, _line_advance * _lines.get_child_count())
		_lines.add_child(extra)
