extends Control
## 任务页（原生 `MENU_STATE_QUEST` = 3）：三框列表 + 详情／放弃。
##
## 版式与内容照抄 `Menu_Quest_Draw` → `Menu_Quest_DrawList` →
## `Menu_Quest_DrawItem`：框1 = `ParamData.current_quest_display`（脚本任务，标题取自
## `evt/evtlist.fxt`，`Menu_Quest_init` 用 `Menu_Quest_Set` 填），框2 = `ParamData.quests[0]`
## （公会任务），框3 = `ParamData.quests[1..10]`（3 行窗口）。行内只有标题、状态图标与达标时的
## `[结束]`；空槽写 msg 187。行数 `max(非空普通槽, 3)`（`Menu_Quest_init` 的补齐分支），滚动走
## `JC_knlSTART`：`top = max(min(new, old), new - 2)`。
##
## 任务数据只从 `host.story_progress["quests"]` 上的 `QuestLog` 取（与 `Story.quest_log()` 同一份
## 字典）：页面只改槽，不写存档。

## `qst/qstlist.fxt` 的六段正文（行标题与 `Menu_Quest_DrawDetail` 用的是同一份）；
## 拆段规则复用野外详情页的同名 helper，避免同一份格式在两处各写一遍。
## 源标识本身只认 `TextTables.QUEST_SOURCE`，本页不再自带常量。
const FieldQuestDetail = preload("res://field/quest_detail/quest_detail.gd")

## 段序：0 标题、1 说明、2 目标、3 地图号（`JC_fxtQINDEX(slot, 3, i)`）。
const TITLE_PAGE := 0
const DESCRIPTION_PAGE := 1
const MAP_PAGE := 3
## `Menu_Quest_DrawDetail` 最多取 10 个地图号（`for i = 0; i != 10`）。
const REGION_LIMIT := 10

## 行序号：把原生「列表组 1／2／3」＋「框3 行号」压成一条序号，
## 0 = 框1，1 = 框2，2 + n = 框3 第 n 行（n 从滚动顶算，对应 `MenuData.transition_parameter_bits`）。
const ROW_MAIN_QUEST := 0
const ROW_GUILD := 1
const FIRST_NORMAL_ROW := 2

## 列表组号（原生 `QstData.active_marker`）：1 = 脚本任务（`Menu_Quest_Set` 的 flag），2 = 公会槽、
## 3 = 普通槽（槽里的值就是 `QuestLog.CONTEXT_GUILD`／`CONTEXT_NPC`）。
const MAIN_QUEST_CONTAINER := 1

## `Menu_Quest_DrawList`：框3 三行可见、行高 23、步进 26；`Menu_Quest_init` 不足 3 条补 3。
const VISIBLE_ROWS := 3
const MIN_ROWS := 3

## `Menu_Quest_DrawItem` 的 `JC_fntSetRGB`：选中行 `0xFFFFFF`，未选中 `7894646`（= `#787676`）。
const COLOR_SELECTED := Color.WHITE
const COLOR_IDLE := Color("#787676")

## 行宽：`Menu_Quest_DrawList` 在行数 > 3 时把 208 收到 192，给 `Menu_Item_DrawScroll` 让位。
const ROW_RIGHT_PLAIN := -2.0
const ROW_RIGHT_SCROLLED := -18.0

var host: Control

## 框3 的滚动顶（`MenuData` 的 `current_state_index_bits + 3`）。
var _scroll_top := 0
## 框3 的行数（`MenuData` 的 `transition_parameter_bits + 1`）。
var _row_count := MIN_ROWS

@onready var _rows: Array[Button] = [$Panel0/QuestRow, $Panel1/QuestRow,
	$Panel2/QuestRow0, $Panel2/QuestRow1, $Panel2/QuestRow2]


func _ready() -> void:
	hide()
	host = get_parent()
	for index in range(_rows.size()):
		_rows[index].pressed.connect(_select_row.bind(index))
	$Panel2/Scroll/UpHit.pressed.connect(_move.bind(-1))
	$Panel2/Scroll/DownHit.pressed.connect(_move.bind(1))


## 框3 的行数（详情页与测试共用；等价于 `MenuData.transition_parameter_bits + 1`）。
func row_count() -> int:
	return _row_count


## `Story.quest_log()` 的同一份字典：槽写进 `progress["quests"]`，落盘仍由 host 走存档。
func quest_log() -> QuestLog:
	if not host.story_progress.has("quests") or not QuestLog.validate(host.story_progress["quests"]):
		host.story_progress["quests"] = QuestLog.empty_dict()
	return QuestLog.new(host.story_progress["quests"])


## 放弃确认选「是」后由详情页调用：清槽并压实（`QuestLog.remove` 即 `Qst_stdRemove`），
## 再按 `Menu_Quest_mKeyPressed` 的清槽尾段重算行数、滚动顶与选中项。
func discard_quest(quest_id: int) -> bool:
	if not quest_log().remove(quest_id):
		return false
	_row_count = _normal_row_count(quest_log())
	if _row_count <= MIN_ROWS:
		_scroll_top = 0
	host.selected_quest_index = mini(host.selected_quest_index, FIRST_NORMAL_ROW + _row_count - 1)
	return true


func handle_key(key: String) -> bool:
	if host.quest_detail_open:
		return host._pages.quest_detail.handle_key(key)
	# `Menu_Quest_mKeyPressed` 的 LABEL_10：列表层的左右键一律交给页签（不在此吞掉）。
	if key in ["ArrowLeft", "ArrowRight"]:
		return false
	if not host.quest_navigation_open:
		if key in ["ArrowDown", "Enter", "Space"]:
			_move_to(ROW_MAIN_QUEST)
			return true
		return key == "ArrowUp"
	match key:
		"ArrowUp":
			_move(-1)
		"ArrowDown":
			_move(1)
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			host.quest_navigation_open = false
			host.notice = ""
			host._render_content()
		_:
			return false
	return true


## 列表层的上下键（`Menu_Quest_mKeyPressed` 的组 1／2／3 分支）。
func _move(delta: int) -> void:
	var selected: int = host.selected_quest_index
	if delta > 0:
		if selected == ROW_MAIN_QUEST:
			_move_to(ROW_GUILD)
		elif selected == ROW_GUILD:
			_move_to(FIRST_NORMAL_ROW)
		elif selected - FIRST_NORMAL_ROW >= _row_count - 1:
			_move_to(ROW_MAIN_QUEST)
		else:
			_move_to(selected + 1)
		return
	if selected == ROW_MAIN_QUEST:
		_move_to(FIRST_NORMAL_ROW + _row_count - 1)
	elif selected == ROW_GUILD:
		_move_to(ROW_MAIN_QUEST)
	elif selected == FIRST_NORMAL_ROW:
		_move_to(ROW_GUILD)
	else:
		_move_to(selected - 1)


func _move_to(row: int) -> void:
	host.quest_navigation_open = true
	host.selected_quest_index = clampi(row, ROW_MAIN_QUEST, FIRST_NORMAL_ROW + _row_count - 1)
	var index: int = host.selected_quest_index - FIRST_NORMAL_ROW
	if index >= 0:
		_scroll_top = _scroll_start(index)
	host.notice = ""
	host._render_content()


## `JC_knlSTART`（`a3 = 1`、`a4 = 3`）：`max(min(new, old), new − 2)`。
func _scroll_start(index: int) -> int:
	return maxi(mini(index, _scroll_top), index - (VISIBLE_ROWS - 1))


func _select_row(button_index: int) -> void:
	if host.quest_detail_open:
		return
	var row := button_index
	if row >= FIRST_NORMAL_ROW:
		row += _scroll_top
	var already: bool = host.quest_navigation_open and host.selected_quest_index == row
	_move_to(row)
	if already:
		_confirm()


## 组 1／2／3 的 OK：槽为空时不进详情（`Menu_Quest_DrawItem` 的 `marker == 0` 分支直接返回）。
func _confirm() -> void:
	if _row_quest(host.selected_quest_index).is_empty():
		return
	if host.selected_quest_index == ROW_MAIN_QUEST:
		host._open_quest_detail()
		return
	host.quest_detail_open = true
	host.notice = ""
	host._render_content()


func _render_quest() -> void:
	var log := quest_log()
	_row_count = _normal_row_count(log)
	_scroll_top = clampi(_scroll_top, 0, maxi(0, _row_count - VISIBLE_ROWS))
	for index in range(3):
		var panel: Panel = get_node("Panel%d" % index)
		# `Menu_Quest_Draw` 的 overlay 1／2 都不画列表（只画详情／世界地图窗口）。
		panel.visible = not host.quest_detail_open and not host.world_map_open
		panel.add_theme_stylebox_override("panel", host._native_outline_style)
		panel.get_node("Caption").texture = host._quest_label_slices[index] \
			if index < host._quest_label_slices.size() else null
	_present_row(ROW_MAIN_QUEST, _main_quest_row())
	_present_row(ROW_GUILD, _slot_row(log.slot_at(QuestLog.SLOT_GUILD)))
	for offset in range(VISIBLE_ROWS):
		_present_row(FIRST_NORMAL_ROW + offset,
			_slot_row(log.slot_at(QuestLog.SLOT_FIRST_NORMAL + _scroll_top + offset)))
	_present_scroll()
	if host.quest_detail_open:
		host._pages.quest_detail._render_quest_detail(_row_quest(host.selected_quest_index))


func _present_row(row: int, data: Dictionary) -> void:
	var button: Button = _rows[row]
	var selected: bool = host.quest_navigation_open and host.selected_quest_index == row
	var color: Color = COLOR_SELECTED if selected else COLOR_IDLE
	var done: bool = bool(data.get("done", false))
	var title: Control = button.get_node("QuestTitle")
	title.text = str(data["title"]) if data.has("title") else host._menu_text(Msg.Id.QUEST_ROW_EMPTY)
	title.color = color
	var mark: Control = button.get_node("EndMark")
	mark.visible = done
	mark.text = host._menu_text(Msg.Id.QUEST_ROW_DONE)
	mark.color = color
	button.get_node("StatusDone").visible = done
	button.get_node("StatusTodo").visible = not data.is_empty() and not done
	button.get_node("Background").visible = selected


## `Menu_Item_DrawScroll`（`x = 框 x + 196`、`y = 框 y + 16`、`a3 = 70`）。
func _present_scroll() -> void:
	var scroll: Control = $Panel2/Scroll
	scroll.visible = _row_count > VISIBLE_ROWS
	var right: float = ROW_RIGHT_SCROLLED if scroll.visible else ROW_RIGHT_PLAIN
	for offset in range(VISIBLE_ROWS):
		_rows[FIRST_NORMAL_ROW + offset].offset_right = right
	if not scroll.visible:
		return
	# 滑块高 `a3 - 20 + 3 * (1 - a5)`（`a5` = 行数，下限 3），顶端 `a4 * (a3 - 20 - 高) / (a5 - 1)`；
	# `track.size.y` 就是 `a3 - 20`。
	var track: Control = scroll.get_node("Track")
	var thumb: Control = scroll.get_node("Thumb")
	var length := maxi(3, int(track.size.y) - 3 * (_row_count - 1))
	thumb.size = Vector2(track.size.x, length)
	thumb.position = track.position + Vector2(0,
		int(_scroll_top * (track.size.y - length) / (_row_count - 1)))


## `Menu_Quest_init`：数 `quests[1..10]` 的非空槽，不足 3 条补 3（最多 10 条）。
func _normal_row_count(log: QuestLog) -> int:
	var used := 0
	for index in range(QuestLog.SLOT_FIRST_NORMAL, QuestLog.SLOT_LAST_NORMAL + 1):
		if not log.slot_at(index).is_empty():
			used += 1
	return maxi(MIN_ROWS, used)


func _row_quest(row: int) -> Dictionary:
	if row == ROW_MAIN_QUEST:
		return _main_quest_row()
	var log := quest_log()
	if row == ROW_GUILD:
		return _slot_row(log.slot_at(QuestLog.SLOT_GUILD))
	return _slot_row(log.slot_at(QuestLog.SLOT_FIRST_NORMAL + _scroll_top + row - FIRST_NORMAL_ROW))


## 框1：脚本任务（`ParamData.current_quest_display`）。没有脚本任务时 `current_quest_text_resource`
## 为 null，原生那一格就是空槽（`Menu_Quest_init` 只有它非空才调 `Menu_Quest_Set`）。
func _main_quest_row() -> Dictionary:
	var text: Variant = host.text_resource
	if not text is String or (text as String).is_empty():
		return {}
	var quest: Dictionary = host.Menu.native_main_quest(host.story_progress, text)
	quest["id"] = -1
	quest["container"] = MAIN_QUEST_CONTAINER
	quest["discardable"] = false
	quest["done"] = false
	return quest


func _slot_row(slot: Dictionary) -> Dictionary:
	if slot.is_empty():
		return {}
	var quest_id := int(slot["quest"])
	var segments := _segments(quest_id)
	var count := _goal_count(slot)
	return {"id": quest_id,
		"title": segments[TITLE_PAGE] if segments.size() > TITLE_PAGE else "",
		"description": segments[DESCRIPTION_PAGE] if segments.size() > DESCRIPTION_PAGE else "",
		# 任务文本资源的分页原样带出去：世界地图要 page 3／page 4 画标记（`Map_worldDRAW`）。
		"pages": segments,
		"region_ids": _region_ids(segments), "container": int(slot["marker"]),
		"done": count >= int(slot["goal_count"]), "discardable": true}


func _segments(quest_id: int) -> Array[String]:
	return FieldQuestDetail.split_segments(host._assets.text_message(TextTables.QUEST_SOURCE, quest_id))


func _region_ids(segments: Array[String]) -> Array[int]:
	var result: Array[int] = []
	if segments.size() <= MAP_PAGE:
		return result
	for part: String in segments[MAP_PAGE].split(",", true):
		var value := part.strip_edges()
		if not value.is_valid_int():
			continue
		var region := int(value)
		if region >= 0 and result.size() < REGION_LIMIT:
			result.append(region)
	return result


## `Menu_Quest_DrawItem` 的达标数：`goal_kind` 0 读槽里的 `progress_value`，1／2 现场清点背包。
func _goal_count(slot: Dictionary) -> int:
	match int(slot["goal_kind"]):
		QuestTable.GOAL_PROGRESS:
			return int(slot["progress"])
		QuestTable.GOAL_MONSTER:
			return _bag_monster_count(int(slot["goal_target"]))
		QuestTable.GOAL_MATERIAL:
			return _material_count(int(slot["goal_target"]))
	return 0


## `Ball_bagFindCount(goal_target, 0)` 与 `Item_fndCount(IK_METERIAL, goal_target)` 的共用清点：
## 规则在 `QuestGoals`（野外运行时用同一份，见 `story.gd::_check_monster_quest`）。
func _bag_monster_count(species: int) -> int:
	return QuestGoals.bag_monster_count(host.story_progress, species)


func _material_count(target: int) -> int:
	return QuestGoals.material_count(host.story_progress, target)
