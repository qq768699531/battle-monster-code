extends "res://scripts/components/window_transition.gd"
## 原生状态 26「战斗结果」（`Battle_Win_*`）：228×240 窗口、四行经验条、金币条与掉落列表。
##
## 窗口尺寸的原生出处是 `Battle_Win_Draw:49` 的
## `Menu_win_Box4_DrawWindow(&out, &outa, 228, 240, &n4, 1, 16)`：正文 228×240、两侧白边 1、
## 头部白条 16——`result.tscn` 根节点上的 `window_size`／`side_width`／`header_height` 就是这三个值，
## 居中矩形由 `Layout.box4_window_frame` 算（x = (400 − 228) / 2 = 86、y = (240 − 240) / 2 = 0）。
##
## 依据：`Battle_Win_init`（`Battle_Win_SetResult` 一次算完 → 载入
## `common/ui_window.fbm` → 开窗计数置 1）、`Battle_Win_mRun`（子状态 0 等开窗动画，
## 子状态 1 每次推进发经验与金币、升级的行走 5 帧高亮，子状态 2 入包等确认）、
## `Battle_Win_Draw`／`Battle_Win_DrawGage`（坐标与配色）、
## `Battle_Win_mKeyPressed`（子状态 1 确认 = 快进，子状态 2 确认 = 离开）。
## 数值全部来自 `BattleSettlement`（`Param_expSET`／`Ball_stdEXP` 的同一套阈值）。

signal finished
## 进入 `items` 阶段：原生 `Battle_Win_mRun@0x322F0:173-191` 在经验与金币都发完（`n4 == 4`）后
## 才进子状态 2，这时逐件 `Item_stdAddEx`（掉落入包 + fxt416 入手提示），窗口本身早已开着。
signal items_reached

const MonsterAnimation = preload("res://scripts/components/monster_animation.gd")
const TextLayout = preload("res://scripts/native_text_layout.gd")
const Battle = preload("res://scripts/battle.gd")

## 原生 `Battle_Win_mRun` 返回 500（单位未取证）；这里与战斗其它步进一致用 0.05 秒一帧，
## 剩余量由 `BattleSettlement.GAIN_FRAMES`（20 帧 = 1 秒）均摊。
const STEP_SECONDS := 0.05
## `Battle_Win_DrawGage` 的条长 = 150 − 38。
const GAGE_WIDTH := 112
const ITEM_ROWS := 3
## 原生主角行是 kind 11（`Battle_Hero_resBUFF`），载入的是**战斗**主角 `hero/h_b_01`
## （`Battle_Hero_resLOAD`），不是野外行走的 `hero/h_f_01`。
const HERO_IDENTITY := "hero/h_b_01"
## 原生 `Object_drawBASIC(rectangle_outa.x + 18, rectangle_outa.y + 67, …, 11, …)`：
## 减去格子左上角（窗口 x + 12、y + 26）后相对剪裁框的锚点 = (6, 41)。
const HERO_ICON_OFFSET := Vector2(6, 41)
const HIGHLIGHT := Color("#fccf45")

var settlement: RefCounted
var scroll := 0
var stage := "closed"

var _presentation: RefCounted
var _progress: Dictionary = {}
var _rows: Array[Control] = []
var _item_rows: Array[Control] = []
var _species_names: Dictionary = {}
var _clock := 0.0


func _ready() -> void:
	super()
	for index in 4:
		_rows.append(get_node("Content/Row%d" % index))
	for index in ITEM_ROWS:
		var row: Control = get_node("Content/Item%d" % index)
		_item_rows.append(row)
		row.get_node("Icon").set_anchors_preset(Control.PRESET_TOP_LEFT)
	$Content/Confirm.pressed.connect(_on_confirm_pressed)
	transition_finished.connect(_transition_finished)


## `Battle_Win_init`：传入算好的结算与窗口标题（`JC_fxt2Return(13)` 战斗、`(14)` 野外事件）。
func open(model: RefCounted, presentation: RefCounted, progress: Dictionary,
		title_id: int = 13) -> bool:
	if model == null or presentation == null or model.rows.is_empty():
		return false
	settlement = model
	_presentation = presentation
	_progress = progress
	_species_names = presentation.assets.text_messages("common/item_mon.dat")
	scroll = 0
	_clock = 0.0
	$Bounds/Title.text = presentation.message(title_id)
	$Content/Footer.configure(presentation.assets, 0)
	$Shade.show_shade()
	show()
	_render()
	stage = "opening"
	open_window()
	return true


func _transition_finished(opened: bool) -> void:
	if not opened or stage != "opening":
		return
	stage = "gain"
	_render()


## 子状态 1：每个 0.05 秒帧推进一次经验／金钱；子状态 2 只剩升级高亮收尾
## （原生在 `Battle_Win_Draw` 里每次绘制都 `--*v14`，与子状态无关）。
func _process(delta: float) -> void:
	if stage not in ["gain", "items"] or settlement == null:
		return
	_clock += delta
	if _clock < STEP_SECONDS:
		return
	_clock -= STEP_SECONDS
	if stage == "gain":
		_settlement_step(false)
	else:
		_decay_flash()


func _decay_flash() -> void:
	var changed := false
	for row: Dictionary in settlement.rows:
		if int(row.flash) > 0:
			row.flash = int(row.flash) - 1
			changed = true
	if changed:
		_render()


func _settlement_step(fast: bool) -> void:
	var response: Dictionary = settlement.step(fast)
	for row: Dictionary in settlement.rows:
		if int(row.flash) > 0:
			row.flash = int(row.flash) - 1
	_render()
	if bool(response.done):
		stage = "items"
		items_reached.emit()


## 原生 `Battle_Win_mPaint` 在窗口左下角放的 OK 页脚只是提示，触摸区在 `EFC_mainTouchSET`
## 里注册的 key −5；这里给同一块矩形加一个透明按钮，点它就等于按确认。
func _on_confirm_pressed() -> void:
	handle_key("Enter")


## 原生 `Battle_Win_mKeyPressed`：子状态 1 的确认把剩余量一次发完，子状态 2 的确认离开战斗。
func handle_key(key: String) -> void:
	if stage in ["closed", "opening"]:
		return
	var confirm := key in ["Enter", "Space"]
	if confirm:
		if stage == "gain":
			for row: Dictionary in settlement.rows:
				row.flash = 0
			_settlement_step(true)
		else:
			stage = "closed"
			finished.emit()
	elif key in ["ArrowLeft", "ArrowRight"] and settlement.items.size() > ITEM_ROWS:
		scroll = clampi(scroll + (-1 if key == "ArrowLeft" else 1), 0,
			settlement.items.size() - ITEM_ROWS)
		_render()


func _render() -> void:
	for index in _rows.size():
		var row: Control = _rows[index]
		var shown: bool = index < settlement.rows.size()
		row.visible = shown
		if not shown:
			continue
		var data: Dictionary = settlement.rows[index]
		_set_name(row.get_node("Name"), data)
		var percent := int(100 * int(data.experience) / maxi(1, int(data.threshold)))
		row.get_node("Gage/Percent").present("%d%%" % percent)
		row.get_node("Gage/Level").present(str(int(data.level)))
		var ratio := clampf(float(data.experience) / float(maxi(1, int(data.threshold))), 0.0, 1.0)
		var width := floorf(GAGE_WIDTH * ratio)
		for name: String in ["FillTop", "FillBottom"]:
			var fill: ColorRect = row.get_node("Gage/" + name)
			fill.offset_right = 13.0 + width
		var flash: ColorRect = row.get_node("Flash")
		flash.visible = int(data.flash) > 0
		if flash.visible:
			flash.color.a = minf(1.0, int(data.flash) * 50.0 / 255.0)
		_place_icon(row.get_node("Clip/Monster"), data)
	$Content/MoneyNumber.present(_format_money(settlement.shown_money()))
	_render_items()


func _render_items() -> void:
	for index in ITEM_ROWS:
		var row: Control = _item_rows[index]
		var position := scroll + index
		var shown: bool = position < settlement.items.size()
		row.visible = shown
		if not shown:
			continue
		var item: Dictionary = settlement.items[position]
		var record: ItemDefinition = _presentation.catalog.item(int(item.id))
		# 原生 `JC_fbmDrawSPRITE(rect.x + 17, y, …, frame, 0, 0)` 把该帧的 (xOffset, yOffset)
		# 摆到 (rect.x + 17, y)：`common/ui_item.fbm` 的每一帧 xOffset/yOffset 都正好是
		# (宽÷2, 高÷2)，所以图标是以这个点为中心的 1:1 原尺寸绘制，不是左上角对齐。
		var icon: Control = row.get_node("Icon")
		icon.texture = _presentation.item_texture(
			{"icon": record.icon} if record != null else {})
		var icon_size: Vector2 = icon.texture.get_size() if icon.texture != null else Vector2.ZERO
		icon.size = icon_size
		icon.position = -(icon_size * 0.5).floor()
		icon.visible = icon.texture != null
		_set_item_name(row.get_node("Name"), record, int(item.count))
	var scrollbar: Control = $Content/Scrollbar
	scrollbar.visible = settlement.items.size() > ITEM_ROWS
	if not scrollbar.visible:
		return
	# 原生 `Menu_Item_DrawScroll(x, y, 52, index, count - 2)`：三行可视、共 count−2 个滚动位。
	var slots := maxi(1, settlement.items.size() - ITEM_ROWS)
	var track: Control = scrollbar.get_node("Track")
	var thumb: Control = scrollbar.get_node("Thumb")
	var length := maxi(3, int(track.size.y) - 3 * slots)
	thumb.position = track.position + Vector2(0, int(scroll * (track.size.y - length) / slots))
	thumb.size = Vector2(track.size.x, length)


## `Battle_Win_Draw` 的行文本：主角是 `#PFF5#C0公会称号 #C6角色名`，
## 队员是 `Ball_stdNickText` 前缀 + 物种名；`feel_state_code == 3`（变异）描黄。
func _set_name(label: Control, data: Dictionary) -> void:
	var parts: Array = []
	if data.kind == "hero":
		var parameter: Dictionary = _progress.get("parameter", {})
		var identity: Variant = parameter.get("identity")
		parts.append([_presentation.message(MenuModel.guild_title_record(_progress)) + " ",
			HIGHLIGHT])
		if identity is int:
			parts.append([_presentation.assets.text_message("npc", int(identity)), Color.WHITE])
	else:
		var combat_species := Battle.combat_species(int(data.species))
		var color := HIGHLIGHT if int(data.species) > 999 else Color.WHITE
		var nickname := int(data.nickname)
		if nickname > 0:
			parts.append([_presentation.message(471 + nickname) + " ", color])
		parts.append([str(_species_names.get("item_mon.group.%d.name" % combat_species,
			"怪物 %d" % combat_species)), color])
		if _presentation.catalog.monster(combat_species) == null:
			parts.append(["（原物种记录缺失）", Color("#ff2020")])
	_apply(label, parts)


## 原生 `%s%s#C6 X %d`：品级只决定颜色（`Item_stdGradeINDEX` 返回的是颜色码）。
func _set_item_name(label: Control, record: ItemDefinition, count: int) -> void:
	if record == null:
		label.text = "原道具缺失 X %d" % count
		return
	var item := {"name_record": record.name_record, "grade_index": record.grade_index}
	var color: Variant = _presentation.item_color(item)
	_apply(label, [[_presentation.item_name(item),
		color if color is Color else Color.WHITE], [" X %d" % count, Color.WHITE]])


func _apply(label: Control, parts: Array) -> void:
	var plain := ""
	var markup := ""
	for part: Array in parts:
		var text := str(part[0])
		if text.is_empty():
			continue
		plain += text
		var color: Color = part[1]
		markup += "[color=#%s]%s[/color]" % [color.to_html(false), text]
	var font: Font = label.theme.default_font
	var size: int = label.theme.default_font_size
	var layout: Dictionary = TextLayout.layout(markup, font, size)
	if layout.get("error", "").is_empty():
		label.set_line(layout.lines[0])
		return
	label.text = plain


## 原生图标是 1:1 裁切的战斗精灵（`Object_drawBASIC` 传 kind 12 + 物种记录的
## `kind_specific_value_bits` 锚点），不是立绘：22×22 的剪裁框里只露出头部。
## 该锚点由 `MonsterDefinition.prime_portrait_position` 以 `x * 100 + y` 导出；未登记的物种
## （0）沿用最常见的 `(12, 31)`，等导出工具补齐后自动生效。
##
## 朝向：`Battle_Win_Draw` 传的 direction 是 2，`Object_drawSPRITE` 对 kind 11／12 取
## `v14 = (direction_code == 1)`，所以这里是 0——图层 x 取反、贴图走镜像档
## （`Object_drawBUFFER0` 的 `v33[0] = -1` 与 `JC_imgGetMIRROR(v32[0])`）。导出场景本身
## 就是这一档（`convert_ani.py` 用 direction 0），所以 `present(..., 0)` 不加额外翻转，
## 锚点也按原生原值直接摆在剪裁框里。
func _place_icon(icon: Node2D, data: Dictionary) -> void:
	var identity := HERO_IDENTITY
	var anchor := HERO_ICON_OFFSET
	if data.kind == "member":
		identity = MonsterAnimation.battle_identity(int(data.species))
		var species: MonsterDefinition = _presentation.catalog.monster(
			Battle.combat_species(int(data.species)))
		anchor = MonsterDefinition.icon_anchor(species)
	icon.position = anchor
	icon.visible = icon.present(identity, 0, 0, true)


static func _format_money(value: int) -> String:
	# `Menu_num2DrawNumber` 样式 2：每三位插一个点。
	var text := str(value)
	var parts := PackedStringArray()
	while text.length() > 3:
		parts.insert(0, text.right(3))
		text = text.left(text.length() - 3)
	parts.insert(0, text)
	return ".".join(parts)

