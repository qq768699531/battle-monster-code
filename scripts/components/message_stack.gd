extends Control
## 原生消息提示栈（`Game_infoInit` / `Game_infoDraw`，见 `wiki\ui\message-stack.md`）。
##
## 8 槽环形缓冲：`push()` 先把**所有**槽的 `target_y` 减 15（旧消息整体上移一行），
## 再占用 `head` 槽（`current_y = 15` 从下方一行升上来、`target_y = 0`、`remaining = 80`）。
## 原生在 `Game_infoDraw` 里每次绘制推进一帧，所以这里用 0.05 秒的固定步长驱动，
## 与宿主帧率无关；`advance_frames()` 是同一个步进的公开入口。
##
## 锚点：`v14 = viewport.width / 2 - 110`、`v13` 按画面状态三档（400×240 下 220／189／180，见 `State`）；
## 底板 `FillRECT(x - 2, y - 2, 字宽 + 图标缩进 + 4, 14)` 用黑、alpha 分档见 `slot_alphas()`；
## 图标 `fbmDrawSPRITE(x + 10, y + 5)`（fbm 帧的 offset 就是半宽半高 ⇒ 以该点为中心），帧号走
## `ItemRes.item_ui_resource` 即 `common/ui_item`；正文每帧 `JC_fntSetRGB(0, 0xFFFFFF)` 固定白，
## 行内 `#C<十六进制>` 换色由 `text_segments()` 处理（`JC_fntDrawText:265-274`），
## 记录正文开头的 `#P<3 位十六进制>` 调色板定义也走同一处（`JC_fntSetPALETTE@0x20CC0`）。
## 翻译资源里的换色改写成内联 `[color=#RRGGBB]…[/color]` 标记（`script\export_text_colors.py`
## 把原生 `#C`／`#P` 的调色板语义展开成 `JC_fntGetRGB` 的 `0xRRGGBB`），`text_segments()` 同一遍扫描里也认它。

const FRAME_SECONDS := 0.05
const SLOT_COUNT := 8
## 一条消息的存活帧数（`v3[2] = 80`）。
const SLOT_LIFETIME := 80
## 新消息的起始 y 偏移与每次 push 的整列步长。
const NEW_OFFSET := 15
const SHIFT_STEP := 15
## `x` 基准 = `PixelData.viewport.width / 2 - 110`；`y` 基准的默认档 `height - 20`（400×240 下 220）。
const BASE_X := 90
const BASE_Y := 220

## `y` 基准（原生 `Game_infoDraw` 的 `v13`）随画面状态取哪一档。
## 状态由宿主给出（`field_runtime` 按进出战斗／文字窗），**偏移只有本表一份**。
enum State {
	## 其余页面：`v13 = PixelData.viewport.height - 20`（`0x416D0` 第 22 行）。
	FIELD,
	## `GAME_STATE_BATTLE` 且战斗状态不在掩码 `0x788B` 内：`height - 51`（第 28／32 行）。
	BATTLE,
	## 掩码 `0x788B` 命中的战斗状态（19 资料／20 道具一／22 捕获道具／26 胜利／30 清屏／
	## 31 设置／32 方式／33 主菜单）：不改基高，沿用 `height - 20`。
	BATTLE_WINDOW,
	## 文字窗打开（`*((_BYTE *)&EvtRes.dialog.page + 216) != 0`）：`height - 60`（第 35 行，
	## 在战斗分支之后判断，覆盖前两支）。
	DIALOG,
}

## 每档相对视口高度的让位，取自 `Game_infoDraw` 的三个 `base_y` 赋值。
const STATE_MARGIN := {
	State.FIELD: 20,
	State.BATTLE: 51,
	State.BATTLE_WINDOW: 20,
	State.DIALOG: 60,
}

## `y` 基准的运行时值；出生取 `State.FIELD` 在 400×240 下的结果，进树后由宿主校正。
var base_y := BASE_Y

## 原生 `JC_fxt2Return` 的默认来源就是 `Msg.SOURCE`；绝大多数提示文本都是这个表里的记录号。

## 全局唯一实例。原生 `Game_infoInit` 是**全局函数**，任何系统都能直接推一条；
## 本工程用静态实例指针复刻这一点：持有者 `_enter_tree()` 登记，`_exit_tree()` 注销。
static var active: Control
## 栈还没挂上时（标题层、启动期）先缓存，挂上后按顺序补推；超过 8 条丢最旧的，与环形缓冲同规则。
static var _deferred: Array = []


## 通用入口（原生 `Game_infoInit`）：**图标帧 + 已格式化文本**。
## 图标帧 < 0 表示无图标。任何脚本 `preload` 本脚本后直接调用，不需要知道栈挂在哪里。
static func notify(icon_frame: int, text: String) -> bool:
	if text.is_empty():
		return false
	if active == null or not is_instance_valid(active):
		_deferred.append([icon_frame, text])
		while _deferred.size() > SLOT_COUNT:
			_deferred.pop_front()
		return true
	active.call("push", icon_frame, text)
	return true


## 无图标的一条提示。
static func say(text: String) -> bool:
	return notify(-1, text)


## `JC_fxt2Return(记录号)` 风格的提示：文本取自 `common/msg.fxt`，`args` 走 GDScript 的 `%` 格式化。
static func say_record(record_id: int, args: Array = []) -> bool:
	return say_source(Msg.SOURCE, record_id, args)


## 任意文本源的记录（`qst/qstlist.fxt`、`npc/...` 等同理）。
static func say_source(source: String, record_id: int, args: Array = []) -> bool:
	return notify(-1, _resolve(source, record_id, args))


## 带图标的记录式提示（原生 `Game_infoInit(icon, fxtN)` 的直接对应）。
static func say_record_icon(icon_frame: int, record_id: int, args: Array = []) -> bool:
	return notify(icon_frame, _resolve(Msg.SOURCE, record_id, args))


## 文本解析：从 `/root/AssetCatalog` 取正文（与 `text_message()` 同一条路径），缺记录时响亮报错。
static func _resolve(source: String, record_id: int, args: Array) -> String:
	var catalog := _catalog_node()
	if catalog == null or not catalog.has_method("text_message"):
		push_error("消息提示栈：AssetCatalog 不可用，无法解析 %s:%d" % [source, record_id])
		return ""
	var text: String = catalog.text_message(source, record_id)
	if text.is_empty():
		push_error("消息提示栈：%s:%d 没有正文" % [source, record_id])
		return ""
	return text % args if not args.is_empty() else text


static func _catalog_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AssetCatalog")
## 有图标时文字右移的宽度（`Game_infoDraw:75` 的 `(~icon >> 31) & 0x15`：有图标 21、没有 0）。
const ICON_INDENT := 21
## 图标锚点相对 (x, y)（`JC_fbmDrawSPRITE(slot_x + 10, slot_y + 5, …)`，`0x416D0:85`）。
const ICON_ANCHOR := Vector2(10, 5)
const BOX_HEIGHT := 14
const TEXT_CELL_HEIGHT := 10

## 行内换色控制码的前缀：`#C` + 1 位十六进制调色板下标
## （`JC_fntDrawText:265-274`：命中后跳过 3 字节、不画字形，只换 `rgb_color`）。
const COLOR_CODE_PREFIX := "#C"
## 一个控制码占的字节数（`0x21D94:271` 的 `initial_byte_offset_3 += 3`）。
const COLOR_CODE_LENGTH := 3
## 调色板定义码的前缀：`#P` + 3 位十六进制 = 一条 5 字节、下标从 0 起逐条递增
## （`JC_fntSetPALETTE@0x20CC0:16` 判 `*p == 35 && p[1] == 80`，`:27` 的 `v5 += 5`）。
const PALETTE_CODE_PREFIX := "#P"
## 一条定义码占的字节数（`JC_fntSetPALETTE@0x20CC0:27`）。
const PALETTE_CODE_LENGTH := 5
## 3 位十六进制数字相对 `#P` 起点的偏移（`JC_fntSetPALETTE@0x20CC0:24-26` 依次取 `p[2]`／`p[3]`／`p[4]`）。
const PALETTE_CODE_RED_OFFSET := 2
const PALETTE_CODE_GREEN_OFFSET := 3
const PALETTE_CODE_BLUE_OFFSET := 4
## `JC_fntSetPALETTE@0x20CC0:28` 的 `(r << 20) | (g << 12) | (16 * b)`。
const PALETTE_CODE_RED_SHIFT := 20
const PALETTE_CODE_GREEN_SHIFT := 12
const PALETTE_CODE_BLUE_SCALE := 16
## 调色板可写条目数：下标必须 `<` 该值（`JC_fntSetRGB@0x20C78:7` 只接受 `palette_index <= 0xF`，
## 越界的 `#P` 仍被消费 5 字节但静默丢弃，与原生一致）。
const PALETTE_INDEX_LIMIT := 0x10
## 翻译资源的段色开标记前缀：`[color=#RRGGBB]`（`script\export_text_colors.py` 的输出格式，
## 对应原生 `#C` 换色到 `JC_fntGetRGB` 的 `0xRRGGBB`）。
const COLOR_SPAN_OPEN_PREFIX := "[color="
## 段色闭标记，回到 `DEFAULT_COLOR_INDEX` 的颜色（正文默认白，`Game_infoDraw:87`）。
const COLOR_SPAN_CLOSE := "[/color]"
## 开标记的总长度：`[color=`(7) + `#RRGGBB`(7) + `]`(1)。
const COLOR_SPAN_OPEN_LENGTH := 15
const COLOR_SPAN_HASH_PREFIX := "#"
## `#RRGGBB` 的十六进制位数（`JC_fntGetRGB` 的三字节各两位）。
const COLOR_SPAN_HEX_LENGTH := 6
const COLOR_SPAN_TERMINATOR := "]"
## 正文默认调色板下标：`Game_infoDraw:87` 每帧先 `JC_fntSetRGB(0, 0xFFFFFF)`，正文因此固定白。
const DEFAULT_COLOR_INDEX := 0
## 原生字体调色板 `FontData.rgb_palette_resource` 的 16 条 0xRRGGBB。
## `JC_fntInitialize:25` 只分配 48 字节并零初始化（`JC_memSET:24` 的 `memset`），
## 1..4 全库没有任何写入点 ⇒ 保持黑；5..15 只在 `Item_Initialize:28-48` 写入。
const PALETTE_RGB := {
	0: 0xFFFFFF,  # `Game_infoDraw:87` 每帧写白
	1: 0x000000,  # 从未写入，零初始化
	2: 0x000000,
	3: 0x000000,
	4: 0x000000,
	5: 0xFFFF00,  # `Item_Initialize:28`（任务名／道具名用 `#C5`）
	6: 0xFFFFFF,  # `Item_stdGradeRGB` 品级 0（`CSWTCH.125[0]`）
	7: 0xC676FB,  # 品级 1（`CSWTCH.125[1]`）
	8: 0xFCCF45,  # 品级 2（`CSWTCH.125[2]`）
	9: 0xFF2020,  # 品级 3（`CSWTCH.125[3]`）
	10: 0x20C0B2,  # `Ball_stdGradeRGB` 品级 0（`CSWTCH.125[4]`）
	11: 0x226BFF,  # 球品级 1（`CSWTCH.125[5]`）
	12: 0xFD7139,  # 球品级 2（`CSWTCH.125[6]`）
	13: 0xB85EF3,  # 球品级 3（`CSWTCH.125[7]`）
	14: 0x60A22A,  # 球品级 4（`CSWTCH.125[8]`）
	15: 0xFCCF45,  # 球品级 5（`CSWTCH.125[9]`）
}
const PALETTE_RED_SHIFT := 16
const PALETTE_GREEN_SHIFT := 8
const PALETTE_BYTE_MASK := 0xFF
const UI_THEME = preload("res://assets/fonts/ui_theme.tres")
## 原生 `ItemRes.item_ui_resource` 就是 `common/ui_item`（`Item_Initialize:20`），帧号即图标号。
const ICON_IDENTITY := "common/ui_item/frame-%03d"
const ICON_PATH := "res://assets/sprite/common/ui_item/frame-%03d.webp"

var _slots: Array[Dictionary] = []
var _head := 0
var _serial := 0
var _pending := 0.0
var _catalog: Object
var _icons: Dictionary = {}


func _init() -> void:
	for _index in SLOT_COUNT:
		_slots.append(_empty_slot())


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## 图标走 `ResourceCatalog.load_sprite()`；宿主没接 catalog 时直接读同一份贴图路径，
## 免得消息栈因为少一行接线就整块看不见图标。
func configure(catalog: Object) -> void:
	_catalog = catalog
	_icons.clear()
	queue_redraw()


func _enter_tree() -> void:
	active = self
	var deferred: Array = _deferred
	_deferred = []
	for item: Array in deferred:
		push(int(item[0]), str(item[1]))


func _exit_tree() -> void:
	if active == self:
		active = null


## 按画面状态切 `y` 基准。原生 `Game_infoDraw` 每帧重算 `v13`；本移植的页面状态由宿主持有，
## 所以由宿主在状态变化时给一次（`field_runtime._sync_message_state()`）。
func set_state_base_y(state: int) -> void:
	if not STATE_MARGIN.has(state):
		push_error("消息提示栈：未知画面状态 %d" % state)
		return
	var value := int(get_viewport_rect().size.y) - int(STATE_MARGIN[state])
	if value == base_y:
		return
	base_y = value
	queue_redraw()


func push(icon_frame: int, text: String) -> void:
	for index in SLOT_COUNT:
		_slots[index].target_y = int(_slots[index].target_y) - SHIFT_STEP
	var slot: Dictionary = _slots[_head]
	slot.current_y = NEW_OFFSET
	slot.target_y = 0
	slot.remaining = SLOT_LIFETIME
	slot.icon = icon_frame
	slot.text = text
	_serial += 1
	slot.serial = _serial
	_head = (_head + 1) % SLOT_COUNT
	queue_redraw()


func clear_all() -> void:
	for index in SLOT_COUNT:
		_slots[index] = _empty_slot()
	queue_redraw()


## 当前显示条数。
func count() -> int:
	var total := 0
	for slot: Dictionary in _slots:
		if int(slot.remaining) > 0:
			total += 1
	return total


## 按消息先后（最旧在前）取槽，测试与宿主核对用。
func slot_at(index: int) -> Dictionary:
	var ordered := _ordered()
	if index < 0 or index >= ordered.size():
		return {}
	var slot: Dictionary = _slots[ordered[index]]
	return {"current_y": int(slot.current_y), "target_y": int(slot.target_y),
		"remaining": int(slot.remaining), "icon": int(slot.icon), "text": String(slot.text)}


## 推进 `frames` 个原生帧（每帧 = `FRAME_SECONDS`）；`_process` 也走这里。
func advance_frames(frames: int) -> void:
	for _index in frames:
		_step()
	queue_redraw()


func _process(delta: float) -> void:
	_pending += delta
	while _pending >= FRAME_SECONDS:
		_pending -= FRAME_SECONDS
		_step()
		queue_redraw()


func _step() -> void:
	for index in SLOT_COUNT:
		var slot: Dictionary = _slots[index]
		if int(slot.remaining) <= 0:
			continue
		var target := int(slot.target_y)
		var current := int(slot.current_y)
		if absi(target - current) == 1:
			current = target
		else:
			# 原生 `((n >> 31) + n) << 15 >> 16` 是向负无穷取整，GDScript 整除向 0 截断。
			current = floori((target + current) / 2.0)
		slot.current_y = current
		slot.remaining = int(slot.remaining) - 1
		if int(slot.remaining) <= 0:
			_slots[index] = _empty_slot()


## 文字缩进（`Game_infoDraw:75` 的 `(~icon >> 31) & 0x15`：有图标 21、没有 0）。
static func text_indent(icon_frame: int) -> int:
	return ICON_INDENT if icon_frame >= 0 else 0


## `Game_infoDraw` 的 alpha 分档：(底板, 内容) / 255，分档只看 `remaining` 的原值。
static func slot_alphas(remaining: int) -> Vector2i:
	match remaining:
		1, SLOT_LIFETIME:
			return Vector2i(44, 88)
		2, SLOT_LIFETIME - 1:
			return Vector2i(88, 176)
		3, SLOT_LIFETIME - 2:
			return Vector2i(132, 255)
		4, SLOT_LIFETIME - 3:
			return Vector2i(176, 255)
		_:
			return Vector2i(220, 255)


## `0xRRGGBB` → Color（`JC_fntGetRGB@0x20C38:5-7` 的三字节拼装）。
static func rgb_color(rgb: int) -> Color:
	return Color8((rgb >> PALETTE_RED_SHIFT) & PALETTE_BYTE_MASK,
		(rgb >> PALETTE_GREEN_SHIFT) & PALETTE_BYTE_MASK, rgb & PALETTE_BYTE_MASK)


## 调色板下标 → 颜色（`JC_fntGetRGB`：`0xRRGGBB` 的三字节表，下标 > 15 取黑）。
static func palette_color(index: int) -> Color:
	return rgb_color(int(PALETTE_RGB.get(index, 0)))


## 把「控制码／段色标记」切成「颜色 + 可见文本」段：`#C<十六进制>` 换调色板下标（`JC_fntDrawText:265-274`），
## 同时清掉正在生效的段色覆盖（原生只有调色板一种换色，后写的那次赢）。
## `#P<3 位十六进制>` 改本段文本的调色板副本（`JC_fntSetPALETTE@0x20CC0:14-33`）后不画字形。
## 翻译资源的 `[color=#RRGGBB]…[/color]` 走同一遍扫描：开标记把颜色直接设成该 `0xRRGGBB`，
## 闭标记回到 `DEFAULT_COLOR_INDEX` 的颜色；标记本身与两种控制码一样不进可见文本。
## 未闭合或重复开标记没有第二条路径——最后一个标记生效，颜色延续到正文结束（标记总被消费掉）。
## 两类码都按出现顺序生效，段里带解析当时的 `0xRRGGBB`，`_draw` 直接用它。
## `JC_fntGetNUMBER` 对非十六进制字符返回 0，这里同样落到 0。
static func text_segments(text: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	# 调色板副本：原生 `#P` 改写 `FontData.rgb_palette_resource`，只对本次文本生效。
	var palette: Dictionary = {}
	for index: int in PALETTE_RGB:
		palette[index] = PALETTE_RGB[index]
	var palette_definition_count := 0
	var color_index := DEFAULT_COLOR_INDEX
	# 段色标记生效期间直接给 `0xRRGGBB`；null 表示按调色板下标取色。
	var span_rgb: Variant = null
	var chunk := ""
	var cursor := 0
	while cursor < text.length():
		if _is_color_code(text, cursor):
			if not chunk.is_empty():
				segments.append(_segment(chunk, color_index, palette, span_rgb))
				chunk = ""
			color_index = _hex_value(text[cursor + COLOR_CODE_PREFIX.length()])
			# 后写的 `#C` 覆盖段色：`Item_stdAddEx` 等调用方把 `#C5`–`#C9` 填进
			# `[color=#FFFFFF]…[/color]` 包裹的记录（`common/msg.fxt:416`）里，原生就是黄的／品级色。
			span_rgb = null
			cursor += COLOR_CODE_LENGTH
			continue
		if _is_palette_code(text, cursor):
			if not chunk.is_empty():
				segments.append(_segment(chunk, color_index, palette, span_rgb))
				chunk = ""
			if palette_definition_count < PALETTE_INDEX_LIMIT:
				palette[palette_definition_count] = _palette_code_rgb(text, cursor)
			palette_definition_count += 1
			cursor += PALETTE_CODE_LENGTH
			continue
		if _is_color_span_open(text, cursor):
			if not chunk.is_empty():
				segments.append(_segment(chunk, color_index, palette, span_rgb))
				chunk = ""
			span_rgb = _color_span_rgb(text, cursor)
			cursor += COLOR_SPAN_OPEN_LENGTH
			continue
		if _is_color_span_close(text, cursor):
			if not chunk.is_empty():
				segments.append(_segment(chunk, color_index, palette, span_rgb))
				chunk = ""
			color_index = DEFAULT_COLOR_INDEX
			span_rgb = null
			cursor += COLOR_SPAN_CLOSE.length()
			continue
		chunk += text[cursor]
		cursor += 1
	if not chunk.is_empty():
		segments.append(_segment(chunk, color_index, palette, span_rgb))
	return segments


## `#C` 是否从 `cursor` 起完整可读（不足 3 字节时不当作控制码）。
static func _is_color_code(text: String, cursor: int) -> bool:
	return text.substr(cursor, COLOR_CODE_PREFIX.length()) == COLOR_CODE_PREFIX \
		and cursor + COLOR_CODE_LENGTH <= text.length()


## `#P` 是否从 `cursor` 起完整可读（不足 5 字节时不当作控制码）。
static func _is_palette_code(text: String, cursor: int) -> bool:
	return text.substr(cursor, PALETTE_CODE_PREFIX.length()) == PALETTE_CODE_PREFIX \
		and cursor + PALETTE_CODE_LENGTH <= text.length()


## `[color=#RRGGBB]` 是否从 `cursor` 起完整合法（十六进制大小写都收）。
## 不合法的写法按普通字符处理——只有这一条判定路径，没有兜底分支。
static func _is_color_span_open(text: String, cursor: int) -> bool:
	if text.substr(cursor, COLOR_SPAN_OPEN_PREFIX.length()) != COLOR_SPAN_OPEN_PREFIX:
		return false
	if cursor + COLOR_SPAN_OPEN_LENGTH > text.length():
		return false
	var hex_offset := cursor + COLOR_SPAN_OPEN_PREFIX.length() + COLOR_SPAN_HASH_PREFIX.length()
	if text[cursor + COLOR_SPAN_OPEN_PREFIX.length()] != COLOR_SPAN_HASH_PREFIX:
		return false
	if text[cursor + COLOR_SPAN_OPEN_LENGTH - COLOR_SPAN_TERMINATOR.length()] != COLOR_SPAN_TERMINATOR:
		return false
	return text.substr(hex_offset, COLOR_SPAN_HEX_LENGTH).is_valid_hex_number()


## 开标记里的 `#RRGGBB` → `0xRRGGBB`（只在 `_is_color_span_open` 成立时调用）。
static func _color_span_rgb(text: String, cursor: int) -> int:
	return text.substr(cursor + COLOR_SPAN_OPEN_PREFIX.length() + COLOR_SPAN_HASH_PREFIX.length(),
		COLOR_SPAN_HEX_LENGTH).hex_to_int()


## `[/color]` 是否从 `cursor` 起完整可读。
static func _is_color_span_close(text: String, cursor: int) -> bool:
	return text.substr(cursor, COLOR_SPAN_CLOSE.length()) == COLOR_SPAN_CLOSE


## `JC_fntSetPALETTE@0x20CC0:24-28`：三字节十六进制 → `(r << 20) | (g << 12) | (16 * b)`。
static func _palette_code_rgb(text: String, cursor: int) -> int:
	var red := _hex_value(text[cursor + PALETTE_CODE_RED_OFFSET])
	var green := _hex_value(text[cursor + PALETTE_CODE_GREEN_OFFSET])
	var blue := _hex_value(text[cursor + PALETTE_CODE_BLUE_OFFSET])
	return (red << PALETTE_CODE_RED_SHIFT) | (green << PALETTE_CODE_GREEN_SHIFT) \
		| (PALETTE_CODE_BLUE_SCALE * blue)


## 一段可见正文 + 该处的颜色：`span_rgb` 非 null 时直接用段色标记的 `0xRRGGBB`，
## 否则按 `color_index` 取调色板副本（`color_index` 保持进入标记前／后的下标，只作诊断用）。
static func _segment(chunk: String, color_index: int, palette: Dictionary,
		span_rgb: Variant) -> Dictionary:
	var rgb := int(span_rgb) if span_rgb != null else int(palette.get(color_index, 0))
	return {"text": chunk, "color_index": color_index, "rgb": rgb}


## 去掉控制码与段色标记后的可见文本（`JC_fntGetSPACE:49-56` 量宽度时同样跳过 3 字节的控制码；
## `#P` 那 5 字节在 `JC_fntSetPALETTE` 里已被当作正文起点消费掉）。
static func visible_text(text: String) -> String:
	var result := ""
	for segment: Dictionary in text_segments(text):
		result += String(segment.text)
	return result


## 单个字符的十六进制值（`JC_fntGetNUMBER`：0-9／a-f／A-F，其余按 0）。
static func _hex_value(character: String) -> int:
	var code := character.unicode_at(0)
	var digit := code - "0".unicode_at(0)
	if digit >= 0 and digit <= 9:
		return digit
	var lower := code - "a".unicode_at(0)
	if lower >= 0 and lower <= 5:
		return lower + 10
	var upper := code - "A".unicode_at(0)
	return upper + 10 if upper >= 0 and upper <= 5 else 0


func _draw() -> void:
	var font: Font = UI_THEME.default_font
	var font_size: int = UI_THEME.default_font_size
	var baseline := _baseline(font, font_size)
	for slot: Dictionary in _slots:
		var remaining := int(slot.remaining)
		if remaining <= 0:
			continue
		var alphas := slot_alphas(remaining)
		var icon := int(slot.icon)
		var indent := text_indent(icon)
		var text := String(slot.text)
		var x := float(BASE_X)
		var y := float(base_y + int(slot.current_y))
		var width := _text_width(text, font, font_size) + indent
		draw_rect(Rect2(x - 2.0, y - 2.0, width + 4.0, BOX_HEIGHT),
			Color(0.0, 0.0, 0.0, alphas.x / 255.0))
		if icon >= 0:
			var texture := _icon_texture(icon)
			if texture != null:
				# 整数原点：fbm 帧的 offset 是半宽半高，奇数尺寸必须自己 floor，
				# 用 STRETCH_KEEP_CENTERED 会落在半像素上。
				var origin := Vector2(x, y) + ICON_ANCHOR - (texture.get_size() * 0.5).floor()
				draw_texture_rect(texture, Rect2(origin, texture.get_size()), false,
					Color(1.0, 1.0, 1.0, alphas.y / 255.0))
		var cursor_x := x + float(indent)
		for segment: Dictionary in text_segments(text):
			var base_color := rgb_color(int(segment.rgb))
			var color := Color(base_color.r, base_color.g, base_color.b, alphas.y / 255.0)
			var chunk := String(segment.text)
			draw_string(font, Vector2(cursor_x, y + baseline), chunk,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			cursor_x += _text_width(chunk, font, font_size)


func _ordered() -> Array[int]:
	var result: Array[int] = []
	for index in SLOT_COUNT:
		if int(_slots[index].remaining) > 0:
			result.append(index)
	result.sort_custom(func(a: int, b: int) -> bool:
		return int(_slots[a].serial) < int(_slots[b].serial))
	return result


func _icon_texture(frame: int) -> Texture2D:
	if _icons.has(frame):
		return _icons[frame]
	var texture: Texture2D = null
	if _catalog != null:
		texture = _catalog.load_sprite(ICON_IDENTITY % frame)
	else:
		var path := ICON_PATH % frame
		if ResourceLoader.exists(path):
			texture = load(path)
	_icons[frame] = texture
	return texture


func _text_width(text: String, font: Font, font_size: int) -> float:
	var visible := visible_text(text)
	if visible.is_empty():
		return 0.0
	var line := TextLine.new()
	line.add_string(visible, font, font_size)
	return line.get_size().x


func _baseline(font: Font, font_size: int) -> float:
	var line := TextLine.new()
	line.add_string("A", font, font_size)
	return ceilf((TEXT_CELL_HEIGHT - line.get_size().y) / 2.0) + line.get_line_ascent()


func _empty_slot() -> Dictionary:
	return {"current_y": 0, "target_y": 0, "remaining": 0, "icon": -1, "text": "", "serial": 0}
