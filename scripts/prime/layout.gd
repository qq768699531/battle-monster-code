extends RefCounted
## Prime 几何、文字定位、输入区域与窗口相位的计算，不绘制页面。
## `follow_window_title` 是唯一会写控件的一处（跟着开合窗框改标题偏移）。

const PANEL := Rect2i(86, 14, 228, 212)
const SETTINGS_ROW_COUNT := 5
const TEXT_CELL_HEIGHT := 10
const UI_THEME = preload("res://assets/fonts/ui_theme.tres")
const TextLayout = preload("res://scripts/native_text_layout.gd")
const ICON_WIDTHS := [15, 31, 36, 38, 40, 24, 42, 36, 42, 35, 15, 29, 10]
## prime 页面的面板按钮键码（正数）。负数码统一用 `TouchCode.Key`／`TouchCode.Pad`；
## 正数码各页含义不同，这里只登记 prime 存档页用到的删除键。
enum PanelKey {
	DELETE = 48,
}
const NUMBER_WIDTHS := [6, 3, 6, 6, 6, 6, 6, 6, 6, 6, 4, 8, 5, 5, 3, 5]


static func control_rect(control: Control, parent: Rect2i = Rect2i()) -> Rect2i:
	var start := Vector2(parent.position) + Vector2(parent.size) * Vector2(
		control.anchor_left, control.anchor_top) + Vector2(control.offset_left, control.offset_top)
	var end := Vector2(parent.position) + Vector2(parent.size) * Vector2(
		control.anchor_right, control.anchor_bottom) + Vector2(control.offset_right, control.offset_bottom)
	return Rect2i(Vector2i(start), Vector2i(end - start))

static var FONT_SIZE: int:
	get: return UI_THEME.default_font_size
static var UI_FONT: Font:
	get: return UI_THEME.default_font


## 折行按**可见正文**量宽度：颜色标记零宽（原生 `JC_fntGetSPACE`／`JC_fntDrawText:284-289`
## 量宽时同样跳过控制码）。跨行的颜色跨度在行尾收、下一行行首重开，保证每行标记自成闭合
## （`NativeTextLayout` 会拒绝未闭合的跨度）。
static func wrap_text(text: String, width: float, font: Font) -> Array[String]:
	var lines: Array[String] = []
	for paragraph: String in text.split("\n", true):
		var line := ""
		var visible := ""
		var open := ""
		var cursor := 0
		while cursor < paragraph.length():
			var token := TextLayout.markup_token_at(paragraph, cursor)
			if not token.is_empty():
				line += token
				open = "" if token == TextLayout.COLOR_SPAN_CLOSE else token
				cursor += token.length()
				continue
			var character := paragraph[cursor]
			if not visible.is_empty() and font.get_string_size(
					visible + character, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > width:
				lines.append(line if open.is_empty() else line + TextLayout.COLOR_SPAN_CLOSE)
				line = open
				visible = ""
			line += character
			visible += character
			cursor += 1
		lines.append(line)
	return lines


static func text_position(font: Font, text: String, at: Vector2, anchor: int = 0) -> Vector2:
	var line := TextLine.new()
	line.add_string(text, font, FONT_SIZE)
	var size := line.get_size()
	if anchor & 3 == 1:
		at.x -= floorf(size.x / 2.0)
	elif anchor & 3 == 2:
		at.x -= size.x
	if anchor & 0x30 == 0x10:
		at.y -= TEXT_CELL_HEIGHT / 2
	elif anchor & 0x30 == 0x20:
		at.y -= TEXT_CELL_HEIGHT
	at.y += ceilf((TEXT_CELL_HEIGHT - size.y) / 2.0) + line.get_line_ascent()
	return at


## 正文可用宽：内容框宽加上 `Lines` 控件自身的左右内缩（各页把正文左右留白写在场景偏移里）。
static func content_text_width(content_width: float, lines: Control) -> int:
	return int(content_width + lines.offset_right - lines.offset_left)


static func _region(key: int, rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x,
		"height": rect.size.y, "key": key, "repeats": 1}


static func menu_geometry(bounds: Control, buttons: VBoxContainer, footers: Array[Control]) -> Dictionary:
	var panel := Rect2i(bounds.get_global_rect()) if bounds.is_inside_tree() else control_rect(bounds)
	var rects: Array[Rect2i] = []
	if buttons.is_inside_tree():
		buttons.notification(Container.NOTIFICATION_SORT_CHILDREN)
		for button: Control in buttons.get_children():
			rects.append(Rect2i(button.get_global_rect()))
	else:
		var column := control_rect(buttons, panel)
		var y := column.position.y
		for button: Control in buttons.get_children():
			var minimum := Vector2i(button.get_combined_minimum_size())
			rects.append(Rect2i(column.position.x, y, column.size.x, minimum.y))
			y += minimum.y + buttons.get_theme_constant("separation")
	var footer_rects: Array[Rect2i] = []
	for footer in footers:
		footer_rects.append(Rect2i(footer.get_global_rect()) if footer.is_inside_tree() else control_rect(footer, panel))
	return {"panel": panel, "buttons": rects, "footers": footer_rects}


static var _scene_geometries: Dictionary = {}


# 网络页（未知岛／邮箱／市场）共用：静态取几何时实例一次页面，读取其真实控件矩形。
static func scene_geometry(scene_path: String) -> Dictionary:
	if not _scene_geometries.has(scene_path):
		var page: Node = load(scene_path).instantiate()
		_scene_geometries[scene_path] = page.layout_geometry()
		page.free()
	return _scene_geometries[scene_path]


static func page_geometry(page: Node) -> Dictionary:
	var footers: Array[Control] = []
	footers.append(page.get_node("Bounds/Accept") as Control)
	footers.append(page.get_node("Bounds/Back") as Control)
	return menu_geometry(page.get_node("Bounds") as Control,
		page.get_node("Bounds/Buttons") as VBoxContainer, footers)


static func menu_regions(data: Dictionary, selected: int, state: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state not in BODY_PHASES:
		return result
	for index in range(data.buttons.size()):
		var region := _region(TouchCode.Key.OK if index == selected else (TouchCode.Pad.UP if index < selected else TouchCode.Pad.DOWN), data.buttons[index])
		region.repeats = maxi(1, absi(index - selected))
		result.append(region)
	if state == 4:
		result.append(_region(TouchCode.Key.OK, data.footers[0]))
		result.append(_region(TouchCode.Key.BACK, data.footers[1]))
	return result


static func box4_footer_rect(panel: Rect2i, icon: int) -> Rect2i:
	return Rect2i(panel.position.x + 4 if icon == 0 else panel.end.x - 46,
		panel.end.y - 15, 42, 12)


static func box4_footer_regions(panel: Rect2i) -> Array[Dictionary]:
	return [_region(TouchCode.Key.OK, box4_footer_rect(panel, 0)), _region(TouchCode.Key.BACK, box4_footer_rect(panel, 1))]


static func window_rect(rect: Rect2i, state: int, title_height: int = 16) -> Rect2i:
	if state in [-3, -2, 1]:
		var height := title_height + 6
		return Rect2i(rect.position.x, int((240 - height) / 2), rect.size.x, height)
	if state in [-1, 2]:
		return Rect2i(rect.position - Vector2i(0, 6), rect.size + Vector2i(0, 12))
	return rect


## 原生 `Menu_win_Box2_DrawWindow@0x4ADE8` 的条形相位画的是 16px 高的条（`n16_1 = 16`，
## `y_1 = (viewport.height - 16) / 2`），不随窗口高度变。
const BOX2_BAR_HEIGHT := 16
## 条形相位（原生 `Menu_win_Box4_DrawWindow@0x4F82C`／`Menu_win_Box2_DrawWindow@0x4ADE8`
## 的 `n4 & 0x33`）：只画条。
const BAR_PHASES := [-3, -2, 1, 2]
## 条文相位（同一组函数的 `n4 & 0x44`）：`y-6`、`height+12`。
const STRIP_PHASES := [-1, 3]
## 正文相位（原生各页 `Draw` 的 `0xC4` 掩码）：只有相位 -1／3／4 画正文、认页内命中；
## 相位 1／2／-2／-3（`BAR_PHASES`）只有条。
const BODY_PHASES := [-1, 3, 4]
## 半透明相位：`Menu_win_Box4_DrawWindow:42` 在相位 1 与 -3 先
## `JC_grpSetMODE(GRP_MODE_ALPHA, 128)` 再画条，所以这两相位的窗口整体半透明。
const FADED_PHASES := [-3, 1]
## `GRP_MODE_ALPHA` 的参数制（`JC_grpSetMODE` 的 128 在 256 制里正好一半）。
const FADED_ALPHA := 128.0 / 256.0


## 原生 `Menu_win_Box2_DrawWindow@0x4ADE8`（确认框 Box2）的相位矩形：条形相位
## `n4 & 0x33`（相位 -3／-2／1／2）画 16px 高、竖直居中的条；条文相位 `n4 & 0x44`
## （相位 -1／3）画 `y-6`、`height+12`；相位 4 与 |相位|>3 用原矩形。
static func box2_window_rect(rect: Rect2i, state: int) -> Rect2i:
	if state in BAR_PHASES:
		return Rect2i(rect.position.x, int((240 - BOX2_BAR_HEIGHT) / 2), rect.size.x, BOX2_BAR_HEIGHT)
	if state in STRIP_PHASES:
		return Rect2i(rect.position - Vector2i(0, 6), rect.size + Vector2i(0, 12))
	return rect


static func box4_window_rect(rect: Rect2i, state: int, collapsed_height: int = 22) -> Rect2i:
	if state in BAR_PHASES:
		return Rect2i(rect.position.x, int((240 - collapsed_height) / 2), rect.size.x, collapsed_height)
	if state in STRIP_PHASES:
		return Rect2i(rect.position - Vector2i(0, 6), rect.size + Vector2i(0, 12))
	return rect


## 窗口整体的不透明度：条形淡入／淡出相位（`FADED_PHASES`）半透明，其余相位不透明。
static func phase_alpha(state: int) -> float:
	return FADED_ALPHA if state in FADED_PHASES else 1.0


## 标题跟着开合窗框的位移走：原生各页把标题画在 `Menu_win_Box4_DrawWindow` 写回的矩形上，
## 所以相位一变标题就要补上「本次位移 − 上次已加的位移」。返回本次位移，供下次调用接着算。
static func follow_window_title(title: Control, delta_y: int, applied_delta: int) -> int:
	title.offset_top += delta_y - applied_delta
	title.offset_bottom += delta_y - applied_delta
	return delta_y


## 原生 `Menu_win_Box4_DrawWindow(w, h)`：窗口在 400×240 屏幕里居中（整数截断）。
static func box4_window_frame(size: Vector2i) -> Rect2i:
	return Rect2i(int((400 - size.x) / 2.0), int((240 - size.y) / 2.0), size.x, size.y)
