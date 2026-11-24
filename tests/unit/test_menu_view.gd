extends "res://tests/unit/gut_case.gd"

const ViewScene = preload("res://game/menu/screen/menu/menu.tscn")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")
const Box2Prompt = preload("res://game/field/runtime/box2_prompt/box2_prompt.gd")
const Layout = preload("res://prime/layout/layout.gd")

## 任务页夹具：公会槽 1 条、普通槽 5 条（行数 > 3，滚动条出现）。
const GUILD_QUEST_ID := 1
const FIRST_NORMAL_QUEST_ID := 2
const NORMAL_QUEST_COUNT := 5
## 写盘失败文案的拼长倍数：`common/msg.fxt` 的记录 38 重复这么多遍后宽到装不进 160 窗的
## 折行宽（`ConfirmLayout.WRAP_INSET` 后的 144），用来证明失败窗宽按实测正文宽撑开。
const FAILURE_TEXT_REPEAT := 4

var _closed := 0


func _view(progress: Dictionary, catalog: Variant = null) -> Control:
	var view: Control = ViewScene.instantiate()
	get_tree().root.add_child(view)
	view.bind(progress, catalog if catalog != null else Fixtures.data(), null)
	view.close_requested.connect(func(): _closed += 1)
	return view


func _item_catalog() -> GameplayData:
	return Fixtures.data({
		"items": [{"id": 1001, "type": 1, "index": 1, "icon": 1,
			"detail_slots": [0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]}],
		"monsters": [{"id": 49, "kind": 0, "attribute_group": 3,
			"ability_inputs": [14, 13, 12, 11, 17, 16],
			"attribute_inputs": [16, 4, 22, 2, 11, 2]}],
	})


func _item_progress() -> Dictionary:
	return {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"1001": 4},
		"parameter": {}}


## 窗口的开合动画期间原生会吞掉按键，等它播完再继续按键。
func _settle_window(view: Control) -> void:
	var window: Control = view._pages.item_discard.get_node("Window")
	while window.is_transitioning():
		await get_tree().process_frame


func _visible_glyphs(box: Node) -> int:
	var count := 0
	for glyph in box.get_children():
		if glyph.visible:
			count += 1
	return count


## 队伍／状态共用面板的四项（`Menu_detailDrawAbil1`）：BRAIN 取
## `brain_current/brain_limit`、EXP 取 `experience_current/65 × 等级²`、FEEL 取
## `feel_value/999`，只有 FOOD 是单值。这里按图集字形的个数确认格式，占位符的
## 长度（`--/--` 5、`--/999` 6、`--` 2）与真实值都不同。
func _member_metrics_flow() -> void:
	var progress := {"quest": 0, "mapId": 1, "eventId": 0, "partyOrder": [0], "inventory": {},
		"monsters": [{"species": 49, "level": 5, "nativeArguments": [49, 5, 0, -1, 0],
			"nickname": 1, "experience": 0, "feel": 7, "food": 100,
			"brainCurrent": 7, "brainLimit": 99}],
		"parameter": {"identity": 0, "level": 1}, "guildCode": 4}
	var view := _view(progress, _item_catalog())
	view.press("Enter")
	view.press("ArrowRight")
	var monster: Control = view._pages.status.get_node("Monster")
	assert_eq(_visible_glyphs(monster.get_node("Brain/Number/Glyphs")), 4,
		"BRAIN 画 brain_current/brain_limit 的 7/99")
	assert_eq(_visible_glyphs(monster.get_node("Feel/Number/Glyphs")), 5,
		"FEEL 画 feel_value 对固定上限 999 的 7/999")
	assert_eq(_visible_glyphs(monster.get_node("Food/Number/Glyphs")), 3,
		"FOOD 只画 food_value 一个数（100）")
	# 详细情报窗传 `a7=1`（`Menu_Monster_DrawDetail:82`）：`Menu_detailDrawAbil1@0x57EC8:31,42` 的行距是
	# `(a7 != 0) + 1 + n7 = 9`，三行顶边 87／96／105；`Abil2` 从 `Abil1` 的 y 起 +30（`:83`）。
	var detail_panel: Control = view._pages.party_detail.get_node("Content/Monster")
	assert_eq([detail_panel.get_node("Level").offset_top, detail_panel.get_node("Party").offset_top,
		detail_panel.get_node("Food").offset_top, detail_panel.get_node("Stats").offset_top],
		[87.0, 96.0, 105.0, 117.0], "详细情报窗三行按 9px 步进，六项从 +30 处起")
	# 六格（`Menu_detailDrawAbil1`）与下方六项（`Menu_detailDrawAbil2`）不是同一套列宽：
	# 六格按 `n68 − 16`／`n68 + 16` 取 52／84（左列 167..219、右列 222..306），六项两列各 68。
	# STATUS 页与详细情报窗必须取同一组数值（详细情报窗是 `status_monster.tscn` 的实例，只覆盖 y）。
	var rows: Array[String] = ["Level", "Brain", "Party", "Experience", "Food", "Feel"]
	var status_edges: Array = []
	var detail_edges: Array = []
	for row_name in rows:
		var status_row: Control = monster.get_node(row_name)
		status_edges.append([status_row.offset_left, status_row.offset_right])
		var detail_row: Control = detail_panel.get_node(row_name)
		detail_edges.append([detail_row.offset_left, detail_row.offset_right])
	assert_eq(status_edges, detail_edges,
		"STATUS 页与详细情报窗的六格取同一套左列起点／宽度与右列起点")
	assert_eq([status_edges[0], status_edges[1]], [[167.0, 219.0], [222.0, 306.0]],
		"六格按原生 52／84 两列排布，右列比左列宽 32 像素给 EXP 留位置")
	# 经验值是六格里最长的一行（`%d/%d`），右对齐后不得越过自己的数值格右边界。
	var experience: Control = monster.get_node("Experience")
	var last_glyph: Control = null
	for glyph in experience.get_node("Number/Glyphs").get_children():
		if (glyph as Control).visible:
			last_glyph = glyph
	assert_true(last_glyph != null and last_glyph.global_position.x + last_glyph.size.x
		<= experience.global_position.x + experience.size.x,
		"EXP 右对齐后落在 222..306 的数值格内")
	# 六项三行 7 高 + 2 间距共 25，`Skills` 顶边 144 之前收口；左栏 Vitals 不与六项列重叠。
	assert_true(detail_panel.get_node("Stats").get_theme_constant("v_separation") == 2
		and detail_panel.get_node("Stats").offset_bottom == 142.0
		and detail_panel.get_node("Vitals").offset_right <= detail_panel.get_node("Stats").offset_left,
		"六项行距 2、三行合计 25，且不与左栏 Vitals 重叠")
	view.queue_free()
	await get_tree().process_frame


func _item_flows() -> void:
	var discard_progress := _item_progress()
	var discard_view := _view(discard_progress, _item_catalog())
	discard_view.select_tab(1)
	var grid: Control = discard_view._pages.items.get_node("Grid")
	assert_eq([grid.get_child(0).get_node("Frame").texture,
		grid.get_child(1).get_node("Frame").texture],
		[discard_view._party_frames[SlotFrame.Frame.IN_RANGE],
			discard_view._party_frames[SlotFrame.Frame.IN_RANGE]],
		"容量内的空格子也是帧 0：原生 `a6` 是「格号 < 上限」，不是「有没有道具」")
	discard_view.press("ArrowDown")
	discard_view.press("ArrowDown")
	discard_view.press("Enter")
	assert_true(discard_view.item_actions_open and discard_view.selected_item_action == 0,
		"item OK opens the native action list on the first entry")
	discard_view.press("ArrowDown")
	discard_view.press("Enter")
	assert_true(discard_view.item_discard_open and discard_view.item_discard_step == 0
		and discard_view.item_discard_count == 4,
		"discard starts from the recorded total in the quantity step")
	await _settle_window(discard_view)
	discard_view.press("ArrowRight")
	assert_true(discard_view.item_discard_count == 1,
		"increasing past the total wraps back to one like the native picker")
	discard_view.press("ArrowLeft")
	discard_view.press("ArrowLeft")
	assert_true(discard_view.item_discard_count == 3,
		"decreasing below one wraps to the total")
	discard_view.press("Enter")
	assert_true(discard_view.item_discard_step == 1 and discard_view.selected_item_discard == 1,
		"OK moves the picker to the confirm step with NO preselected")
	discard_view.press("ArrowLeft")
	assert_true(discard_view.selected_item_discard == 0, "left selects YES in the confirm step")
	discard_view.press("Enter")
	assert_true(discard_progress.inventory.get("1001") == 1,
		"confirming the discard removes exactly the chosen quantity")
	await _settle_window(discard_view)
	assert_true(not discard_view.item_discard_open, "the discard window closes after the removal")
	discard_view.queue_free()
	await get_tree().process_frame

	var use_progress := _item_progress()
	var use_view := _view(use_progress, _item_catalog())
	use_view.select_tab(1)
	use_view.press("ArrowDown")
	use_view.press("ArrowDown")
	use_view.press("Enter")
	use_view.press("Enter")
	assert_true(use_view.item_target_open and not use_view.item_actions_open,
		"USE closes the action list and opens the native member target list")
	use_view.press("Enter")
	assert_true(not use_view.item_target_open and use_progress.inventory.get("1001") == 3
		and int(use_progress.monsters[0].hp) > 5,
		"targeting a member consumes one item and restores its HP")
	use_view.queue_free()
	await get_tree().process_frame


func _quest_slot(context: int, quest_id: int) -> Dictionary:
	return {"marker": context, "npc": 4, "quest": quest_id,
		"goal_kind": QuestTable.GOAL_PROGRESS, "goal_target": 0, "goal_count": 5, "progress": 0}


func _quest_progress() -> Dictionary:
	var quests := QuestLog.empty_dict()
	quests["slots"][QuestLog.SLOT_GUILD] = _quest_slot(QuestLog.CONTEXT_GUILD, GUILD_QUEST_ID)
	for offset in range(NORMAL_QUEST_COUNT):
		quests["slots"][QuestLog.SLOT_FIRST_NORMAL + offset] = _quest_slot(
			QuestLog.CONTEXT_NPC, FIRST_NORMAL_QUEST_ID + offset)
	return {"quest": 0, "mapId": 1, "quests": quests, "monsters": [], "partyOrder": [],
		"inventory": {}, "parameter": {}, "guildCode": 0, "eventId": 0}


## 任务页：三框数据绑定、详情、放弃确认（`Menu_Quest_mKeyPressed`）。
func _quest_flows() -> void:
	var progress := _quest_progress()
	var view := _view(progress)
	view.select_tab(MenuModel.Tab.QUEST)
	var page: Control = view._pages.quest
	var guild_title := str(view._assets.text_message("qst/qstlist.fxt",
		GUILD_QUEST_ID)).split("\t")[0]
	assert_true(page.get_node("Panel1/QuestRow/QuestTitle").text == guild_title.strip_edges()
		and page.get_node("Panel0/QuestRow/QuestTitle").text == \
			view._menu_text(Msg.Id.QUEST_ROW_EMPTY),
		"公会槽写 qstlist 标题，没有脚本任务时框1 写 msg 187")
	view.press("ArrowDown")
	view.press("ArrowDown")
	view.press("ArrowDown")
	view.press("Enter")
	var detail: Control = view._pages.quest_detail
	assert_true(view.quest_detail_open
		and int(detail.quest().get("id", -1)) == FIRST_NORMAL_QUEST_ID,
		"框3 第一行 OK 打开该槽的详情")
	# 页脚是并列两项（左「世界地图」msg 191、右「放弃」msg 193），`MenuData+0x20` 只是高亮哪一项：
	# `Menu_Quest_DrawDetail:187-221` 选中项传 Icon18 切片 0、未选中项传 1。
	var footer: Control = detail.get_node("Bounds")
	assert_true(footer.get_node("DiscardButton").visible
		and footer.get_node("MapButton").button_pressed
		and not footer.get_node("DiscardButton").button_pressed,
		"进详情层焦点在左项「世界地图」且公会／普通槽才有右项（`Menu_Quest_mKeyPressed` 进场写 `+0x20 = 0`）")
	view.press("ArrowRight")
	assert_true(footer.get_node("DiscardButton").button_pressed
		and not footer.get_node("MapButton").button_pressed
		and not detail.get_node("Confirm").visible,
		"列表组 2／3 的左右键只把焦点挪到页脚右项「放弃」（`+0x20 ^= 1`），不直接开窗")
	# 鼠标点**未选中**的那一项只换焦点（`Menu_Quest_DrawDetail:187-221`：未选中项登记的是
	# `EFC_mainTouchSET(-3/−4)`，选中项才登记 `-5`），再点一次才执行。
	footer.get_node("MapButton").pressed.emit()
	assert_true(detail._page == 0 and not detail.get_node("Confirm").visible,
		"点未选中的「世界地图」只把焦点挪回左项，不执行")
	footer.get_node("DiscardButton").pressed.emit()
	assert_true(detail._page == 1 and not detail.get_node("Confirm").visible,
		"再点「放弃」仍然只是把焦点挪到右项，不开确认框")
	view.press("Enter")
	var confirm: Control = detail.get_node("Confirm")
	while confirm.is_transitioning():
		await get_tree().process_frame
	assert_true(confirm.get_node("Content").visible,
		"放弃确认框走开窗动画，正文在最后一帧才显示（`Menu_win_Box2_DrawWindow` 每帧推进相位）")
	view.press("ArrowLeft")
	view.press("Enter")
	while detail._closing:
		await get_tree().process_frame
	assert_true(view.quest_detail_open
		and QuestLog.new(progress["quests"]).is_active(FIRST_NORMAL_QUEST_ID),
		"放弃确认选「否」只收框，回到详情层且槽不变（`Menu_Quest_mRun` 把层号写回 1）")
	view.press("Enter")
	view.press("Enter")
	assert_true(progress["quests"]["slots"][QuestLog.SLOT_FIRST_NORMAL + NORMAL_QUEST_COUNT - 1]
		.is_empty() and not QuestLog.new(progress["quests"]).is_active(FIRST_NORMAL_QUEST_ID)
		and page.row_count() == NORMAL_QUEST_COUNT - 1 and not view.quest_detail_open,
		"放弃确认选「是」清槽并压实，行数按剩余普通槽重算，层号立刻回列表")
	view.queue_free()
	await get_tree().process_frame


## 选项页「存档」：原生 `Menu_Option_mPaint` 的层 1→2→3——先开「存档中...」，
## 开窗动画走完（`Menu_Option_mRun:26-29`）才写盘，再换「存档完毕」的确认框。
func _option_save_flow() -> void:
	var view := _view(_item_progress(), _item_catalog())
	view.save_requested.connect(func(_snapshot): view.notice = view._menu_text(Msg.Id.SAVE_DONE))
	view.select_tab(MenuModel.Tab.OPTIONS)
	view.press("Enter")
	view.press("Enter")
	var layer: Control = view.get_node("OptionSaveLayer")
	var window: Control = layer.get_node("Window")
	assert_true(layer.visible and window.body_text() == view._menu_text(Msg.Id.SAVE_IN_PROGRESS)
		and window.form() == Box2Prompt.Form.MESSAGE,
		"存档先开 `Menu_win_Box2_DrawMessage` 的「存档中...」，此时没有写盘也没有确认键")
	assert_eq(window.window_size, ConfirmLayout.message_size(160, 1),
		"「存档中...」按 `Menu_win_Box2_DrawMessage` 的一行正文算高（13 + 18 = 31），不再由场景写死")
	while window.is_transitioning():
		await get_tree().process_frame
	assert_true(window.body_text() == view._menu_text(Msg.Id.SAVE_DONE)
		and window.form() == Box2Prompt.Form.OK and window.confirm_visible(),
		"开窗动画走完才写盘，结果换成 `Menu_win_Box2_DrawOk` 的「存档完毕」确认框")
	view.press("Enter")
	while window.is_transitioning():
		await get_tree().process_frame
	assert_true(not layer.visible and view.selected_tab == MenuModel.Tab.OPTIONS,
		"确认后关窗回选项页（`Menu_Option_mRun:8-18` 把层号写回 0）")
	view.queue_free()
	await get_tree().process_frame


## 写盘失败：原生 `Game_saveSAVE` 的返回码从不被读取（`Menu_Option_mPaint:41-43` 只有层 1／2／3），
## 所以没有原生形态；本工程让失败文案留在同一个 `Menu_win_Box2_DrawOk` 句柄里，窗宽按实测正文宽撑开。
func _option_save_failure_flow() -> void:
	var view := _view(_item_progress(), _item_catalog())
	var failure: String = view._menu_text(Msg.Id.FIELD_SAVE_UNAVAILABLE).repeat(FAILURE_TEXT_REPEAT)
	view.save_requested.connect(func(_snapshot): view.notice = failure)
	view.select_tab(MenuModel.Tab.OPTIONS)
	view.press("Enter")
	view.press("Enter")
	var layer: Control = view.get_node("OptionSaveLayer")
	var window: Control = layer.get_node("Window")
	while window.is_transitioning():
		await get_tree().process_frame
	var lines: Array[String] = Layout.wrap_text(failure,
		window.window_size.x - ConfirmLayout.WRAP_INSET, Layout.UI_FONT)
	assert_true(layer.visible and window.body_text() == failure
		and window.form() == Box2Prompt.Form.OK and window.confirm_visible()
		and window.window_size.x > window.width and lines.size() == 1
		and window.window_size == ConfirmLayout.ok_size(window.window_size.x, lines.size()),
		"写盘失败也在同一个 DrawOk 句柄里给出整句：窗宽按实测正文宽撑开，正文一行放下、窗高按折行数算")
	view.queue_free()
	await get_tree().process_frame


## 环境设定是 Prime 页：原生 style 35 期间摇杆与 OK／CLR 留在 228×208 窗口外两侧，
## 面板要照长生出来，但判点在 Prime 侧（`settings_view.live_regions`），所以交出输入；
## 回选项页后恢复成菜单自己的触控面板。
func _option_settings_flow() -> void:
	var view := _view(_item_progress(), _item_catalog())
	var panel: Node = view.get_node("TouchControls")
	view.select_tab(MenuModel.Tab.OPTIONS)
	view.press("Enter")
	view.press("ArrowDown")
	view.press("Enter")
	var opened: bool = view.settings_open and panel.visible and not panel.interactive \
		and view.mouse_filter == Control.MOUSE_FILTER_IGNORE
	view.finish_shared_page(view._settings)
	assert_true(opened and panel.interactive and panel.visible
		and view.mouse_filter == Control.MOUSE_FILTER_STOP,
		"游戏内环境设定页保留触控面板但把命中让给 Prime 侧，回选项页后恢复交互")
	view.queue_free()
	await get_tree().process_frame


## 剧情期间（宿主按 `field_runtime.story_unsettled()` 折算的 `current_event_resource_id <= 2`）
## 存档项不进层 1：原生 `Menu_Option_mKeyPressed:37-40` 只推一条 `fxt` 198「现在无法存档」。
func _option_save_gate_flow() -> void:
	var view := _view(_item_progress(), _item_catalog())
	var requested := [false]
	view.save_requested.connect(func(_snapshot): requested[0] = true)
	view.option_save_blocked = true
	view.select_tab(MenuModel.Tab.OPTIONS)
	view.press("Enter")
	view.press("Enter")
	var layer: Control = view.get_node("OptionSaveLayer")
	assert_true(not layer.visible and not requested[0],
		"剧情期间存档项不开 `Menu_win_Box2_DrawMessage`，也不请求写盘")
	view.option_save_blocked = false
	view.press("Enter")
	assert_true(layer.visible, "回到稳定状态后同一入口照常开「存档中...」")
	view.queue_free()
	await get_tree().process_frame


func _run() -> void:
	var progress := {"quest": 3, "mapId": 2, "parameter": {"identity": 2, "level": 1,
		"rank": 4, "trait": 1, "preferredMastery": 0, "development": {"experience": 120,
			"growth": [1, 2, 3, 4, 5, 6], "points": 3, "allocated": [1, 0, 2],
			"masteryExperience": [65, 130, 0, 0, 0, 0]}},
		"monsters": [], "inventory": {}}
	var view := _view(progress)
	assert_true(view._pages.status.visible and not view._pages.items.visible,
		"menu opens with only its status page active")
	# 六格流派进度条（`Menu_Hero_Draw1` → `Menu_Attr_Draw`）：
	# 填充宽 = 余数 × (99 − 44) / 阈值，阈值 = `Param_expINIT` 的系数 × 等级²。
	assert_eq(int(view._pages.status.get_node("Growth/Growth0/Fill").size.x), 29,
		"第 0 格余数 65 对首选流派阈值 120（120 × 1²）只填 29px")
	assert_eq(int(view._pages.status.get_node("Growth/Growth1/Fill").size.x), 13,
		"第 1 格余数 130 对非首选阈值 520（130 × 2²）填 13px")
	assert_eq(int(view._pages.status.get_node("Growth/Growth5/Fill").size.x), 0,
		"余数为 0 的格子不画填充")
	view.select_tab(MenuModel.Tab.QUEST)
	view.press("ArrowRight")
	assert_true(view.selected_tab == MenuModel.Tab.NETWORK and view.get_node("network").visible,
		"QUEST moves right to NET in visual order rather than internal snapshot order")
	view.press("Escape")
	assert_true(view.closed and _closed == 1 and not view.visible,
		"menu CLR closes the panel exactly once")
	view.queue_free()
	await get_tree().process_frame
	await _item_flows()
	await _quest_flows()
	await _member_metrics_flow()
	await _option_save_flow()
	await _option_save_gate_flow()
	await _option_save_failure_flow()
	await _option_settings_flow()


func test_legacy_suite() -> void:
	await _run()
