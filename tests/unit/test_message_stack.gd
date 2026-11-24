extends "res://tests/unit/gut_case.gd"
const MessageStack = preload("res://core/message_stack/message_stack.gd")

const StackScene = preload("res://core/message_stack/message_stack.tscn")
const Msg = preload("res://core/msg/msg.gd")

var _stack: Control


func before_each() -> void:
	super()
	_stack = StackScene.instantiate()
	add_child_autofree(_stack)
	_stack.set_process(false)


## `Game_infoDraw` 的正文带：`y = height − 20`（400×240 下 220）起、高 14，
## 新消息从下方一行升上来，所以取 (88, 216) 起的一条横带。
const MESSAGE_BAND := Rect2i(88, 216, 240, 22)
## 图标位：`JC_fbmDrawSPRITE(x + 10, y + 5)` 以 (100, 225) 为中心画 `ui_item` 帧 148
## （21×20、原点 (10,10) ⇒ x 90..110／y 215..234），取 x ≥ 93 是避开空文本时那块 4 px 宽的底板
## （x 88..91）。
const ICON_BAND := Rect2i(93, 216, 15, 18)
## 原生任务消息用的图标帧（`Evt_msgSET:32` 等传的 `0x94`）。
const QUEST_ICON_FRAME := 0x94


func _bright_pixels(image: Image, band: Rect2i) -> int:
	var total := 0
	for y in range(band.position.y, band.end.y):
		for x in range(band.position.x, band.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.75 and pixel.g > 0.75 and pixel.b > 0.75:
				total += 1
	return total


## 槽里的数据对不代表画得出来（宿主曾把整个栈 `visible = false`）；这里取真实帧缓冲核对。
func test_pushed_message_is_drawn() -> void:
	_stack.clear_all()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var before := _bright_pixels(get_viewport().get_texture().get_image(), MESSAGE_BAND)
	_stack.push(-1, "消息提示")
	_stack.advance_frames(2)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var after := _bright_pixels(get_viewport().get_texture().get_image(), MESSAGE_BAND)
	assert_gt(after, before, "推送后消息栈真的往帧缓冲里画了字")


## 底板与背景都是中性灰（黑底叠灰背景），所以「有彩色像素」只可能来自图集帧。
func _colored_pixels(image: Image, band: Rect2i) -> int:
	var total := 0
	for y in range(band.position.y, band.end.y):
		for x in range(band.position.x, band.end.x):
			var pixel := image.get_pixel(x, y)
			var high := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var low := minf(pixel.r, minf(pixel.g, pixel.b))
			if high - low > 0.2:
				total += 1
	return total


## `Game_infoDraw:83-88`：`icon_frame >= 0` 时画 `ItemRes.item_ui_resource` 的该帧
## （`common/ui_item/frame-N`），文字缩进 21；不带图标的与原来一致（缩进 0、图标位不动）。
func test_message_icon_frame_draws_item_sprite() -> void:
	# 文本留空：图标带里除了底板就只有图标，底板是黑的、不会出彩色像素。
	_stack.clear_all()
	_stack.push(-1, "")
	_stack.advance_frames(4)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var plain := get_viewport().get_texture().get_image()
	_stack.clear_all()
	_stack.push(QUEST_ICON_FRAME, "")
	_stack.advance_frames(4)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var with_icon := get_viewport().get_texture().get_image()
	assert_eq(MessageStack.text_indent(-1), 0, "无图标时文字不缩进")
	assert_eq(MessageStack.text_indent(QUEST_ICON_FRAME), MessageStack.ICON_INDENT,
		"有图标时文字右移 21 px（`(~icon >> 31) & 0x15`）")
	assert_eq(_colored_pixels(plain, ICON_BAND), 0, "不带图标帧时不画图集帧")
	assert_gt(_colored_pixels(with_icon, ICON_BAND), 0, "带图标帧时在图标位画出图集帧")


## 非白像素（含半透明底板与图集帧）的包围盒，用于核对图标的实际落点与尺寸。
func _non_white_bounds(image: Image, area: Rect2i) -> Rect2i:
	var min_point := Vector2i(area.end)
	var max_point := Vector2i(area.position)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.98 and pixel.g > 0.98 and pixel.b > 0.98:
				continue
			min_point = Vector2i(mini(min_point.x, x), mini(min_point.y, y))
			max_point = Vector2i(maxi(max_point.x, x), maxi(max_point.y, y))
	return Rect2i(min_point, max_point - min_point + Vector2i.ONE)


func _capture() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## `bm-368`：三处都按帧缓冲取样。字段对不代表画得出来——道具名的品级色曾被
## `common/msg.fxt:416` 外层 `[color=#FFFFFF]` 段标记吞掉，渲染成纯白。
## 白底让底板 alpha 直接落在像素上：44／255 的底板 = 211／255 的灰。
func test_rendered_pixels_follow_native() -> void:
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.size = Vector2(400, 240)
	background.z_index = -1
	add_child_autofree(background)
	# 剩余 80 帧：`Game_infoDraw:44-69` 的第一档底板 alpha 44。
	_stack.clear_all()
	_stack.push(-1, "")
	var first: Image = await _capture()
	assert_almost_eq(first.get_pixel(90, 236).r, (255.0 - 44.0) / 255.0, 0.01,
		"底板第一档 alpha 44 叠在白底上")

	# `Game_infoDraw:83-88`：图标是 `common/ui_item` 帧原尺寸（21×20，中心 (90,215)+半宽高）。
	_stack.clear_all()
	_stack.push(QUEST_ICON_FRAME, "")
	_stack.advance_frames(4)
	var icon: Image = await _capture()
	assert_eq(_non_white_bounds(icon, Rect2i(80, 210, 40, 30)), Rect2i(88, 215, 25, 20),
		"图标 21×20 落在 (90,215)，14 高的底板不撑大包围盒")

	# `Item_stdAddEx:73`：记录正文 `[color=#FFFFFF]获得%s%s X %d[/color]` 里填 `#C9`，
	# `JC_fntDrawText:265-274` 后写的 `#C` 赢，必须是调色板 9 的 FF2020。
	_stack.clear_all()
	MessageStack.say_record_icon(QUEST_ICON_FRAME, Msg.Id.ITEM_OBTAINED, ["#C9", "道具", 3])
	_stack.advance_frames(4)
	var colored: Image = await _capture()
	# 从文字起点（`BASE_X + 缩进 21`）往右数：图标帧本身带彩色像素，不能算成正文上色。
	var text_x := MessageStack.BASE_X + MessageStack.ICON_INDENT
	var red := 0
	for y in range(MESSAGE_BAND.position.y, MESSAGE_BAND.end.y):
		for x in range(text_x, MESSAGE_BAND.end.x):
			var pixel := colored.get_pixel(x, y)
			if pixel.r > 0.9 and pixel.g < 0.4 and pixel.b < 0.4:
				red += 1
	assert_gt(red, 0, "`#C9` 的道具名按调色板 9（FF2020）上色")


## 正文颜色与 alpha：`Game_infoDraw:87` 固定白、`:44-69` 五档 alpha；
## 行内 `#C<n>` 换色来自 `JC_fntDrawText:265-274`，颜色取 `Item_Initialize` 写的调色板。
func test_text_color_and_alpha_follow_native() -> void:
	var segments := MessageStack.text_segments("#C5[任务]#C0文字")
	assert_eq(segments.size(), 2, "控制码把一条文本切成两段颜色")
	assert_eq([segments[0].color_index, segments[0].text], [5, "[任务]"], "`#C5` 起作用到下一个控制码")
	assert_eq([segments[1].color_index, segments[1].text], [0, "文字"], "`#C0` 恢复正文白")
	assert_eq(MessageStack.visible_text("#C5[任务]"), "[任务]", "控制码本身不参与绘制")
	assert_eq(MessageStack.palette_color(0), Color.WHITE,
		"0 号是 `Game_infoDraw:87` 每帧写的白")
	assert_eq(MessageStack.palette_color(5), Color8(0xFF, 0xFF, 0x00),
		"5 号 = `Item_Initialize:28` 的 0xFFFF00")
	assert_eq(MessageStack.slot_alphas(80), Vector2i(44, 88), "剩余 80 帧：底板 44／正文 88")
	assert_eq(MessageStack.slot_alphas(77), Vector2i(176, 255), "剩余 77 帧：底板 176／正文 255")
	assert_eq(MessageStack.slot_alphas(76), Vector2i(220, 255), "其余：底板 220／正文 255")

	# `#P000` + `#C0` 组合：`#P` 那 5 字节把调色板 0 改写成黑
	# （`JC_fntSetPALETTE@0x20CC0:24-28` 的 `(r<<20)|(g<<12)|(16*b)`），紧接的 `#C0` 就画这个黑；
	# 两个控制码都不产生字形，也不进宽度（`JC_fntSetPALETTE` 的返回值是正文起点）。
	var plain_body := "相克导致技能伤害下降"
	var coded: String = "#P000#C0" + plain_body
	var coded_segments: Array[Dictionary] = MessageStack.text_segments(coded)
	assert_eq([MessageStack.visible_text(coded), coded_segments[0].color_index,
		MessageStack.rgb_color(coded_segments[0].rgb)],
		[plain_body, MessageStack.DEFAULT_COLOR_INDEX, Color.BLACK],
		"`#P000` 改写调色板 0、`#C0` 取到这个黑，两个码都不出现在可见文本里")
	var font: Font = MessageStack.UI_THEME.default_font
	var font_size: int = MessageStack.UI_THEME.default_font_size
	assert_eq(_stack._text_width(coded, font, font_size),
		_stack._text_width(plain_body, font, font_size),
		"`#P` 的 5 字节与 `#C` 的 3 字节都不计入宽度")

	# 翻译资源的段色标记走同一遍扫描：开标记直接给 `0xRRGGBB`，闭标记回到正文默认白。
	var spanned: Array[Dictionary] = MessageStack.text_segments("[color=#F00000]红[/color]白")
	assert_eq(spanned.map(func(segment: Dictionary) -> Array:
			return [segment.text, MessageStack.rgb_color(int(segment.rgb))]),
		[["红", Color8(0xF0, 0x00, 0x00)], ["白", Color.WHITE]],
		"`[color=#RRGGBB]` 影响到 `[/color]`，闭标记回到 `DEFAULT_COLOR_INDEX` 的白")
	assert_eq(_stack._text_width("[color=#F00000]红[/color]白", font, font_size),
		_stack._text_width("红白", font, font_size), "段色标记不计入宽度")
	# `Item_stdAddEx` 把 `#C5`–`#C9` 填进被 `[color=#FFFFFF]` 包裹的记录：后写的 `#C` 赢，
	# 不能像 `bm-368` 那样把品级色吞成白。
	var injected: Array[Dictionary] = MessageStack.text_segments(
		"[color=#FFFFFF]获得#C9道具 X 3[/color]")
	assert_eq([injected[1].text, MessageStack.rgb_color(int(injected[1].rgb))],
		["道具 X 3", Color8(0xFF, 0x20, 0x20)], "`#C9` 覆盖外层的白色段标记")


func test_legacy_suite() -> void:
	_stack.push(-1, "first")
	_stack.push(-1, "second")
	assert_eq(_stack.slot_at(0).target_y, -15, "旧的提示被新来的顶上一行")
	assert_eq([_stack.slot_at(1).current_y, _stack.slot_at(1).target_y], [15, 0],
		"新提示从下方一行升到行首")

	for index in 7:
		_stack.push(-1, "m%d" % index)
	assert_eq(_stack.count(), 8, "环形缓冲只有 8 槽")
	assert_ne(_stack.slot_at(0).text, "first", "第 9 条覆盖了最早那条")

	_stack.advance_frames(80)
	assert_eq(_stack.count(), 0, "80 帧后所有槽过期清空")

	# `Game_infoDraw` 的 `v13` 按画面状态取档：战斗 HUD 期 `height−51`、其余 `height−20`
	# （400×240 下 189／220）。基准变化只影响绘制，不影响槽内偏移。
	_stack.push(-1, "offset")
	_stack.set_state_base_y(MessageStack.State.BATTLE)
	assert_eq([_stack.base_y, _stack.slot_at(0).target_y], [189, 0],
		"让位只改 y 基准，不动消息自身的行偏移")
	_stack.set_state_base_y(MessageStack.State.FIELD)
	assert_eq(_stack.base_y, 220, "切回野外复原 height−20")
	# `Game_infoInit` 是全局函数：任何系统都能推一条，不必逐层传节点引用。
	var before: int = _stack.count()
	assert_true(MessageStack.notify(-1, "global") and _stack.count() == before + 1,
		"静态入口 notify() 把消息推进已登记的提示栈")

	# 记录式封装：`say_record(记录号)` 自己从 `common/msg.fxt` 取正文（对应 `JC_fxt2Return`）。
	assert_true(MessageStack.say_record(Msg.Id.FLEE_SUCCEEDED) and
		_stack.slot_at(_stack.count() - 1).text ==
			get_node("/root/AssetCatalog").text_message(Msg.SOURCE, Msg.Id.FLEE_SUCCEEDED),
		"say_record() 按记录号取正文并推进栈")
