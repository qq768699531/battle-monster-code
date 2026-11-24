extends "res://ui/window_transition/window_transition.gd"

const MessageStack = preload("res://ui/message_stack/message_stack.gd")

## 原生任务详情页：`FieldCanvas` 状态 10（支线）／状态 8（公会）自己只 `Map_Copy` 清屏，
## 窗口与输入由 `GameCanvas` 层的任务浮层给——`Qst_chtDRAW`（画）／
## `Qst_chtRUN`（每帧）／`Qst_chtKeyPress`（按键）。
##
## 窗口 `Menu_win_Box4_DrawWindow(228, 212, …, side 1, header 16)` 居中于 (86, 14)，标题按上下文码取
## `JC_fxt2Return(513)`［公会任务］／`(514)`［支线任务］；正文整块交给
## `Menu_Quest_DrawDetail`（先进来的矩形 `y -= 28`、`height += 28`，即 y = 2、高 224）：
## 类型条 `#04070C` (x+9, y+51, w−18, 11)、正文底 `#0E1B2F` (x+9, y+62, w−18, h−81)、
## 圆角外框 `#CFCCCC` 1 px (x+8, y+50, w−16, h−68)、标题 `[ 标题 ]` `#FFFFAA` 在 (x+12, y+66)、
## 说明 `JC_fntDrawCharsEx(…, w−24)` 从 (x+12, y+80) 起、`[结束NPC]`／`[道具]` 两组标签
## （`#6DB6FF`）与正文各 +14、`[关联地域]`（`#B6FF55`）在地域名上一行、
## 分隔线 `#273448` 在 (x+11, y+h−46, w−22, 1)、页脚图标在 (x+12, y+h−43) + 文本 y+h−32。
##
## 页脚两项是 `Menu_winDrawIcon18` 的 49×22 按下块（与菜单侧 `menu/quest_detail` 同一个组件）：
## 左「世界地图」(msg 191) 固定在 `x+12`，右「接受／放弃」(msg 192／193) 在 `x+w−69`，只在
## `Qst_stdFind` 未命中的 2 项模式里画。选中的一项按 `-5` 执行、未选中的按 `-3` 只换选中。
##
## 点「世界地图」进**层 1**：原生 `Qst_chtDRAW` 的层 1 只画
## `Menu_world_Draw(&QstData.detail, …)`，本页同等处理——详情窗框、标题与正文全部让开，
## 复用 `scenes/menu/world_map.tscn` 那扇 228×208 窗；CLR 只把层号写回 0 并把两个窗口共用的
## 开合相位写 1（`Qst_chtKeyPress` 的 `:26-28`），即地图窗同帧退场、详情窗从条形重开。
##
## 页脚右侧的奖励三项是**本移植新增**（原生详情页不显示奖励，`Field_Quest_Complete_SetResult`
## 只在交任务时入账），按任务要求补在 `[关联地域]` 那一行的右端。

signal closed
## 接取成功：`slot` 是写进 `QuestLog` 的槽位（公会任务 0、普通任务 1..10）。
signal accepted(quest_id: int, slot: int)

const TextLayout = preload("res://ui/native_text_layout/native_text_layout.gd")
const ConfirmLayout = preload("res://ui/confirm_layout/confirm_layout.gd")
const UI_THEME = preload("res://ui/ui_theme.tres")

## 任务正文走 `TextTables.QUEST_SOURCE`（`qst/qstlist.fxt:<任务号>`），payload 是
## 「标题 \t 说明 \t 目标 \t 关联地域号 \t 目标地域号 \t 地域名」六段（尾段可能整体缺失）。
## 第 4／5 段正是 `QuestMark` 的两个标记页（原生 `JC_fxtQINDEX(res, 3, n)`／`(res, 4, 0)`）。
## 本页自有的两处 `JC_fxt2Return`：奖励三项里原生详情页没有的标签（本移植新增的展示）。
## `[道具]` 那一行直接用 `Msg.Id.QUEST_ITEM_LABEL`（与 `Menu_Quest_DrawDetail` 同一个 190）。
const MESSAGE_EXPERIENCE := 413     ## 「经验值」
const MESSAGE_MONEY := 414          ## 「金币」
const NPC_SOURCE := "npc"

## 页脚选中项（原生 `QstData.context_parameter_bits + 2`）。`Qst_chtINIT` 进页面就写 0，
## 所以进页面时聚焦在「世界地图」上；`Qst_chtKeyPress` 的 `-3`／`-4` 都是
## `(选中项 + 1) % 页脚项数`——两项时就是两项互换。
const PAGE_MAP := 0
const PAGE_ACTION := 1
## 页脚项数（原生 `QstData.quest_lookup_state`）：`Qst_stdFind` 命中（任务在册）时只有世界地图一项，
## 否则再加「接受」；`Menu_Quest_DrawDetail` 的右按钮也只在项数 > 1 时画。
const PAGE_COUNT_MAP_ONLY := 1
const PAGE_COUNT_WITH_ACTION := 2
## 层号（原生 `QstData.context_parameter_bits + 1`）：0 详情、1 世界地图、2 接受确认。
const LAYER_DETAIL := 0
const LAYER_WORLD_MAP := 1
const LAYER_CONFIRM := 2
## 接受确认的选择项（原生 `QstData.quest_lookup_state + 1`，`Menu_win_Box2_DrawSelect` 的 a4）。
const CHOICE_YES := 0
const CHOICE_NO := 1
## 确认框宽：`Qst_chtKeyPress:112-117` 进层 2 时 `Menu_win_Box2_DrawSelect` 的 `width` 参数。
## 窗高不写死，`_open_confirm` 按正文折行数走 `ConfirmLayout.select_size`。
const CONFIRM_WIDTH := 160
## 正文折行宽度 `width − 16`（`Menu_win_Box2_DrawSelect:41` 的 `JC_fntGetPage(…, width_1 - 16, …)`）。
const CONFIRM_TEXT_WIDTH := 144
## 窗口开合相位用父脚本的 `BoxPhase`（原生 `Menu_win_Box4_DrawWindow@0x4F82C` 的 `*a5`）：
## 进页面（`Field_Quest_Detail_init` 写 1）、开图与层 1 返回（`Qst_chtKeyPress` 都写 1）都从 1 起，
## 每帧按符号 ±1；4 是稳态，-1 起收拢、-4 由 `Qst_chtRUN` 收尾。接受确认框与外层同一个枚举
## （原生 `MainData + 7`；层 0 进层 2 时 `Qst_chtKeyPress:116` 写 1，层 2 的 CLR 与选「否」
## 转发的 -16（`:52`／`:59`）只写 -1，`Qst_chtRUN:9-13` 收到 -4 才把层号写回 0）。
## `Menu_win_Box2_DrawSelect:34` 只在 -3..-1／1..4 画，0 与 -4 都不画。
## 开合本身由 `components/window_transition` 的 `open`／`close` 轨道给。

## `JC_fntDrawCharsEx` 的 `maximum_line_width = 228 − 24`；原生正文区到 `[结束NPC]` 之前。
const DESCRIPTION_WIDTH := 204.0
const DESCRIPTION_ROWS := 3
## 目标段里的进度占位（`JC_fxtQUEST` 找的就是 `"0/"`）。
const GOAL_PLACEHOLDER := "0/"
const MIN_SEGMENTS := 3

## 正文六段（`qst/qstlist.fxt` 原文分段，不做任何改写）。
var segments: Array[String] = []
## 目标行：`JC_fxtQUEST` 把目标段的 `0/` 换成当前进度（`击退赫拉 2/5`）。
var goal_text := ""
var quest_id := -1
var context := QuestLog.CONTEXT_NPC

var _assets: Node
var _table: QuestTable
var _log: QuestLog
var _record: Dictionary = {}
var _counts: Dictionary = {}
## 存档进度：世界地图要当前地图号与已开通的传送边（`Map_worldINIT` 的焦点另有任务地域）。
var _progress: Dictionary = {}
## 拒绝/失败的记录号（页内不再画静态文本，调用方可据此或直接看提示栈）。
var notice_id := -1
var _notice := "":
	set(value):
		_notice = value
		if value.is_empty():
			return
		MessageStack.say(value)
var _closing := false
## 确认框在收拢中（`Qst_chtKeyPress:52` 已把 `+7` 写 -1、层号仍是 2，等 `Qst_chtRUN`
## 收到 -4 才回详情层）。原生层 2 没有「收拢中」分支：`-5` 仍按当前选中项处理（`:57-89`），
## 方向键（换选中项）与 CLR（再写一次 -1）在这段里没有可做的事。所以 `handle_key` 只吞这两类，
## 确认键继续转发；任何按键都不会落到详情层的页脚。
var _closing_confirm := false
var _page := PAGE_MAP
var _page_count := PAGE_COUNT_WITH_ACTION
var _layer := LAYER_DETAIL
## 接受确认的选择项（原生 `QstData.quest_lookup_state + 1`）。`Qst_chtINIT` 与
## `Qst_chtKeyPress` 层 0 进层 2 时都把它写 0（`:112`），也就是原生默认停在「是」。
var _choice := CHOICE_YES
var _world_map: Node


func _ready() -> void:
	super()
	transition_finished.connect(_transition_finished)
	$Content/MapButton.pressed.connect(_on_page_pressed.bind(PAGE_MAP))
	$Content/ActionButton.pressed.connect(_on_page_pressed.bind(PAGE_ACTION))
	$Content/BackHit.pressed.connect(close)
	$Confirm.transition_finished.connect(_confirm_transition_finished)
	$Confirm/Content/Yes.pressed.connect(_resolve_confirm.bind(CHOICE_YES))
	$Confirm/Content/No.pressed.connect(_resolve_confirm.bind(CHOICE_NO))
	_world_map = $WorldMap
	_world_map.close_requested.connect(_close_world_map)


## `assets` = `AssetCatalog`；`log` 取自 `story.quest_log()`（同一个 `progress["quests"]` 字典）。
## `counts` 是 `goal_kind` 1／2 的现场清点（任务号 → 当前持有量，原生 `Ball_bagFindCount`）。
## `progress` 是整份存档进度，世界地图取 `mapId`／`warpEnabled`／`warpPassed`。
func present(assets: Node, table: QuestTable, log: QuestLog, id: int,
		quest_context: int, counts: Dictionary = {}, progress: Dictionary = {}) -> bool:
	_assets = assets
	_table = table
	_log = log
	_counts = counts
	quest_id = id
	context = quest_context
	_record = table.record(id)
	if _record.is_empty():
		return false
	segments = split_segments(assets.text_message(TextTables.QUEST_SOURCE, id))
	if segments.size() < MIN_SEGMENTS:
		push_error("任务 %d 的 %s 正文不足 %d 段：%d" % [id, TextTables.QUEST_SOURCE, MIN_SEGMENTS, segments.size()])
		return false
	_closing = false
	_layer = LAYER_DETAIL
	_page = PAGE_MAP
	_choice = CHOICE_YES
	_progress = progress
	_notice = ""
	goal_text = quest_goal(segments[2], counted())
	# `Qst_chtINIT`：`Qst_stdFind(quest_id)` 命中时 `quest_lookup_state = 1`（页脚只有
	# 世界地图），否则 = 2（多一项「接受」）。
	_page_count = PAGE_COUNT_MAP_ONLY if _log.is_active(id) else PAGE_COUNT_WITH_ACTION
	_reset_confirm()
	$WorldMap.hide()
	$Bounds/Title.text = assets.text_message(Msg.SOURCE,
		Msg.Id.QUEST_GUILD_DETAIL_TITLE if quest_context == QuestLog.CONTEXT_GUILD
		else Msg.Id.QUEST_SIDE_DETAIL_TITLE)
	# `Menu_Quest_DrawDetail` 的页脚正文：左项固定 msg 191，右项按 `Qst_stdFind` 取 193／192。
	$Content/MapButton/Caption.text = assets.text_message(Msg.SOURCE, Msg.Id.QUEST_WORLD_MAP)
	$Content/ActionButton/Caption.text = assets.text_message(Msg.SOURCE,
		Msg.Id.QUEST_ABANDON if _log.is_active(id) else Msg.Id.QUEST_ACCEPT)
	_render_pages()
	_render()
	show()
	open_window()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	if is_transitioning():
		# 开窗动画还没播完就按 CLR：等它播完再走关窗，避免两条轨道互相打断。
		await transition_finished
		if not is_inside_tree():
			return
	close_window()


## `Qst_chtKeyPress` 的三个层：0 详情（左右换页脚项、OK 执行选中项、CLR 关窗）、
## 1 世界地图（`-5` 与方向键转给 `Map_worldKEY`，CLR 只把层号写回 0）、2 接受确认。
func handle_key(key: String) -> bool:
	if _closing:
		return true
	if _layer == LAYER_WORLD_MAP:
		return bool(_world_map.handle_key(key))
	if _layer == LAYER_CONFIRM:
		# 原生层 2 不看收拢相位：`-5` 一律按当前选中项处理（`Qst_chtKeyPress:57-89`）。
		# 收拢期只有方向键（换选中项）没有可做的事，CLR 由 `_close_confirm` 自己的守卫挡掉。
		match key:
			"ArrowLeft", "ArrowRight":
				if _closing_confirm:
					return true
				_choice = CHOICE_NO if _choice == CHOICE_YES else CHOICE_YES
				_render_confirm()
			"Enter", "Space":
				_resolve_confirm(_choice)
			"Escape", "Backspace":
				_close_confirm()
			_:
				pass
		return true
	if is_transitioning():
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			# 原生 `-3`／`-4` 是同一个式子 `(选中项 + 1) % 页脚项数`。
			_page = (_page + 1) % _page_count
			_render_pages()
		"Enter", "Space":
			_activate_page()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


## 第 `index` 段正文（超出实际段数返回空串）。`0` 标题、`1` 说明、`2` 目标、`3` 关联地域号、
## `4` 目标地域号（`QuestMark` 的两个标记页）、`5` 地域名；`qstlist.fxt` 里有 5 段的记录（如 30 号）。
func segment(index: int) -> String:
	return segments[index] if index >= 0 and index < segments.size() else ""


## 目标行里显示的当前进度（原生：`goal_kind` 0 读槽里的 `progress_value`，1／2 现场清点背包）。
func counted() -> int:
	if int(_record.get("goal_kind", QuestTable.GOAL_PROGRESS)) == QuestTable.GOAL_PROGRESS:
		return _log.progress_of(quest_id)
	return int(_counts.get(quest_id, 0))


static func split_segments(text: String) -> Array[String]:
	var result: Array[String] = []
	for part: String in text.split("\t", true):
		result.append(part.strip_edges())
	return result


## `JC_fxtQUEST`：把目标段的 `0/` 换成当前数量，`0/` 之前若不以空格结尾就补一个。
static func quest_goal(template: String, count: int) -> String:
	var at := template.find(GOAL_PLACEHOLDER)
	if at < 0:
		return template
	var head := template.left(at)
	if not head.is_empty() and not head.ends_with(" "):
		head += " "
	return "%s%d/%s" % [head, count, template.substr(at + GOAL_PLACEHOLDER.length())]


## 页脚选中项的执行（`Qst_chtKeyPress` 层 0 的 `-5`）：选中世界地图就开图，
## 选中右项（只在不册时存在）才进接受确认。
func _activate_page() -> void:
	if _page == PAGE_ACTION and _page_count > PAGE_ACTION:
		_open_confirm()
		return
	_open_map()


## 触摸页脚项：`Menu_Quest_DrawDetail` 给未选中的项注册 `-3`、选中的项注册 `-5`，
## 也就是**点没选中的那一项只换选中，再点一次才执行**。
func _on_page_pressed(target: int) -> void:
	if _closing or _layer != LAYER_DETAIL or is_transitioning():
		return
	if _page != target:
		_page = target
		_render_pages()
		return
	_activate_page()


func _render_pages() -> void:
	$Content/MapButton.set_pressed_no_signal(_page == PAGE_MAP)
	$Content/ActionButton.visible = _page_count > PAGE_ACTION
	$Content/ActionButton.set_pressed_no_signal(_page == PAGE_ACTION)


## `Qst_chtKeyPress` 层 0 的 `-5`：`Sint32 = JC_fxtQINDEX(QstData.detail.text_resource, 3, 0)`，
## 焦点是任务文本资源 page 3（关联地域列表）的第一项；`< 0` 时只提示 `JC_fxt2Return(511)`
## （菜单侧同一情形是 msg 195）。开图后层号写 1，`Qst_chtDRAW` 的层 1 只画
## `Menu_world_Draw(&QstData.detail, …)`——详情窗框、标题与正文整段不画。
func _open_map() -> void:
	if _closing or _layer != LAYER_DETAIL or is_transitioning():
		return
	var focus_map_id := _first_region_id()
	if focus_map_id < 0:
		notice_id = Msg.Id.QUEST_NO_INFO
		_notice = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_NO_INFO)
		return
	var data: Variant = _assets.call("load_world_map") \
		if _assets.has_method("load_world_map") else null
	if data == null:
		_notice = "世界地图节点表缺失；未打开世界地图。"
		return
	if not _world_map.open(_assets, data, int(_progress.get("mapId", 0)),
			_progress.get("warpEnabled", {}), _progress.get("warpPassed", {}),
			segments, focus_map_id):
		return
	_layer = LAYER_WORLD_MAP
	$Bounds.visible = false
	$Content.visible = false


## 任务文本资源 page 3 的第一个地图号（`QuestMark.RELATED_PAGE` 与 `Map_worldDRAW`
## 画关联地域标记读的是同一页），没有可解析项时返回 −1。
func _first_region_id() -> int:
	for part: String in QuestMark.page_text(segments, QuestMark.RELATED_PAGE).split(",", true):
		var value := part.strip_edges()
		if value.is_valid_int():
			return int(value)
	return -1


## `Qst_chtKeyPress` 层 1 的 `-16`：只把层号写回 0、把**共用的开合相位** `MainData + 3` 写 1
## （`:26-28`），页面本身不关。详情窗（`Qst_chtDRAW` 层 0 的 `Menu_win_Box4_DrawWindow(228, 212, …)`）
## 与世界地图窗（`Menu_world_Draw` 的 `Menu_win_Box4_DrawWindow(228, 208, …, 12, 12)`，`:101`
## 把推进后的值写回同一个变量）共用这一个相位，所以原生没有「地图窗收拢」那一段：层号一换层 0 就不再
## 调 `Menu_world_Draw`，地图窗同帧消失，写回的 1 让详情窗从条形重放开窗动画。
## 所以这里不播世界地图窗的 `close`，直接让它退场再重放详情窗的 `open`（对应相位 1 起的一段）。
func _close_world_map() -> void:
	if _closing or _layer != LAYER_WORLD_MAP or _world_map.closing():
		return
	# 层 0 只画 `Menu_win_Box4_DrawWindow`：地图窗同帧退场，逐拍（`Map_worldDRAW` 的镜头折半）也停。
	_world_map.leave()
	_layer = LAYER_DETAIL
	open_window()


## `Qst_chtKeyPress:112-117`：进层 2 时把确认框的相位写 1，开合照 `Menu_win_Box2_DrawWindow`
## 的分相走（1→2→3→4 稳态），轨道在 `window_transition` 的 `open` 里。
func _open_confirm() -> void:
	if _closing or _layer != LAYER_DETAIL or is_transitioning():
		return
	_layer = LAYER_CONFIRM
	_closing_confirm = false
	_choice = CHOICE_YES
	_notice = ""
	$Confirm/Content/Prompt.text = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_FIELD_ACCEPT_PROMPT)
	var lines := Layout.wrap_text(String($Confirm/Content/Prompt.text),
		CONFIRM_TEXT_WIDTH, Layout.UI_FONT)
	$Confirm.window_size = ConfirmLayout.select_size(CONFIRM_WIDTH, lines.size())
	_render_confirm()
	$Confirm.show()
	$Confirm.open_window()


## `Qst_chtKeyPress` 层 2 的 `-16`（选「否」转发的是同一条，`:59`）：只把确认框的相位写 -1 起
## 收拢，层号仍是 2；`Qst_chtRUN:9-13` 收到 -4（收拢完）才把层号写回 0。
func _close_confirm() -> void:
	if _closing_confirm:
		return
	_closing_confirm = true
	$Confirm.close_window()


## 确认框的收拢播完（`animation_finished` 的 opened = false，即相位到 -4）才回详情层。
func _confirm_transition_finished(opened: bool) -> void:
	if opened:
		return
	$Confirm.hide()
	_closing_confirm = false
	if _layer != LAYER_CONFIRM:
		return
	_layer = LAYER_DETAIL
	_render()


## 接受成功时原生直接写层号 3 与两个相位 0／-1（`Qst_chtKeyPress:68-70`），确认框同帧不再画，
## 所以这条路径不播 `close`，只复位。
func _reset_confirm() -> void:
	_closing_confirm = false
	$Confirm.hide()


## 确认框是否在收拢中（原生相位 -1..-4，层号仍是 2）。
func closing_confirm() -> bool:
	return _closing_confirm


func _render_confirm() -> void:
	$Confirm/Content/Yes/Choice.present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_YES),
		_choice == CHOICE_YES)
	$Confirm/Content/No/Choice.present(_assets.text_message(Msg.SOURCE, Msg.Id.ANSWER_NO),
		_choice == CHOICE_NO)


## `Qst_chtKeyPress` 子状态 2 的 `-5`：选「否」退回详情，选「是」先 `Qst_stdEmpty`
## 抢槽（失败弹 fxt 512），成功再 `Qst_stdSET` 写入任务槽。
## 原生这一段没有「收拢中」判断，`-5` 一律按当前选中项处理，所以这里也不看 `_closing_confirm`。
func _resolve_confirm(value: int) -> void:
	if _layer != LAYER_CONFIRM:
		return
	if value != CHOICE_YES:
		_close_confirm()
		return
	if not _log.accept(_table, quest_id, context):
		# `Qst_chtKeyPress:84-89`：抢槽失败只 `Game_infoInit(0x94, JC_fxt2Return(512))` 就 return，
		# 层号 `context_parameter_bits + 1` 与相位 `MainData + 7` 都不动——确认框留在场上。
		notice_id = Msg.Id.QUEST_SLOTS_FULL
		_notice = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_SLOTS_FULL)
		return
	var slot := _log.slot_of(quest_id)
	_reset_confirm()
	accepted.emit(quest_id, slot)
	close()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	closed.emit()


func _render() -> void:
	$Content/Name.text = "[ %s ]" % segment(0)
	var layout := TextLayout.layout(segment(1), UI_THEME.default_font,
		UI_THEME.default_font_size, DESCRIPTION_WIDTH)
	if layout.error.is_empty():
		for index in DESCRIPTION_ROWS:
			var row: Control = get_node("Content/Desc%d" % index)
			row.visible = index < layout.lines.size()
			if row.visible:
				row.set_line(layout.lines[index])
	else:
		push_error(layout.error)
	var regions := segment(5)
	$Content/RegionCaption.visible = not regions.is_empty()
	$Content/RegionNames.visible = not regions.is_empty()
	$Content/RegionCaption.text = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_REGION_LABEL)
	$Content/RegionNames.text = regions
	$Content/NpcCaption.text = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_END_NPC_LABEL)
	$Content/NpcName.text = _assets.text_message(NPC_SOURCE, int(_record.get("npc_id", 0)))
	$Content/GoalCaption.text = _assets.text_message(Msg.SOURCE, Msg.Id.QUEST_ITEM_LABEL)
	$Content/GoalText.text = goal_text
	$Content/Reward.text = _reward_text()
	# 静态提示行已退役：`_notice` 的 setter 推提示栈（如「不可以再接受更多的任务了」）。
	$Content/Notice.visible = false


## 奖励三项（本移植新增的展示，数值直接取任务记录：`record+19` 金钱、`record+23` 经验、
## `record+13`／`+15` 道具号与数量）。
func _reward_text() -> String:
	var parts := PackedStringArray()
	parts.append("%s %d" % [_assets.text_message(Msg.SOURCE, MESSAGE_EXPERIENCE),
		int(_record.get("reward_experience", 0))])
	parts.append("%s %d" % [_assets.text_message(Msg.SOURCE, MESSAGE_MONEY),
		int(_record.get("reward_money", 0))])
	var item := int(_record.get("reward_item", 0))
	if item != 0:
		parts.append("%s %d×%d" % [_assets.text_message(Msg.SOURCE, Msg.Id.QUEST_ITEM_LABEL), item,
			int(_record.get("reward_item_count", 0))])
	return "  ".join(parts)
