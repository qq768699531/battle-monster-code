extends "res://tests/unit/gut_case.gd"

const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const MenuFixtures = preload("res://tests/unit/gameplay_fixtures.gd")
## `qst/qstlist.fxt:2` 的地图段是 `15,16,17`，详情页左按钮才会真的开世界地图。
const REGION_QUEST_ID := 2

const QuestDetailScene = preload("res://game/menu/quest/quest_detail/quest_detail.tscn")
const QuestDetailScript = preload("res://game/menu/quest/quest_detail/quest_detail.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")
const QuestCompleteScene = preload("res://game/field/quests/quest_complete/quest_complete.tscn")
const MonsterAttribute = preload("res://game/growth/monster_attribute/monster_attribute.gd")
const Story = preload("res://engine/data/story/story.gd")

const QUEST_ID := 43
## `qst/qstlist.fxt:43` 的 page 3（关联地域号）只有 `29`，页脚开图的焦点就是它
## （`Qst_chtKeyPress` 的 `JC_fxtQINDEX(text_resource, 3, 0)`）。
const QUEST_REGION_MAP_ID := 29
const GOAL_COUNT := 5
## 出战怪的物种号（`gameplay.tres` 里真实存在、属性组 1..6 的那一类）。
const PARTY_SPECIES := 49
## 「半透明 + 模糊」层用的 shader（`Field_Basic_Capture` 的 `JC_grpFillBLUR`）。
const BLUR_SHADER := "res://engine/ui/screen_shade/menu_map_blur.gdshader"


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


## 整棵树里可见的半透明模糊层数：原生菜单与世界地图画的是同一张 `MapRes.map_scratch_image`
## （`Map_Copy`），叠加窗口不会再做第二层。
func _visible_blur_layers(node: Node) -> int:
	var total := 0
	var item := node as CanvasItem
	if item != null:
		var material := item.material as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path == BLUR_SHADER and item.is_visible_in_tree():
			total += 1
	for child in node.get_children():
		total += _visible_blur_layers(child)
	return total


## P2-10：`Menu_Quest_DrawDetail` 的左按钮（msg 191「世界地图」+ `EFC_mainTouchSET(-3)`
## 49×22 触控区）在详情页页脚；`Menu_Quest_mKeyPressed` 的 overlay 1 按 -5（OK）调
## `Map_worldINIT(任务首个地域, 1)` 并把层号置 2。
func test_menu_detail_world_map_entry() -> void:
	var quests := QuestLog.empty_dict()
	quests["slots"][QuestLog.SLOT_FIRST_NORMAL] = {"marker": QuestLog.CONTEXT_NPC, "npc": 4,
		"quest": REGION_QUEST_ID, "goal_kind": QuestTable.GOAL_PROGRESS, "goal_target": 0,
		"goal_count": 5, "progress": 0}
	var progress := {"quest": 0, "mapId": 1, "quests": quests, "monsters": [], "partyOrder": [],
		"inventory": {}, "parameter": {}, "guildCode": 0, "eventId": 0}
	var view: Control = MenuScene.instantiate()
	get_tree().root.add_child(view)
	view.bind(progress, MenuFixtures.data(), null)
	view.select_tab(MenuModel.Tab.QUEST)
	view.press("ArrowDown")
	view.press("ArrowDown")
	view.press("ArrowDown")
	view.press("Enter")
	var detail: Control = view._pages.quest_detail
	var button: Control = detail.get_node("Bounds/MapButton")
	# 左按钮几何：`Menu_winDrawIcon18(x_1 = rect.x + 12, v42 - 25)`，49×22（`rect` = (86,0,228,240)）。
	assert_true(view.quest_detail_open and button.visible and
		button.get_global_rect() == Rect2(98, 197, 49, 22),
		"详情页页脚画出「世界地图」按钮，位置 (98,197) 49×22")
	view.press("Enter")
	# overlay 2 只画 `Menu_world_Draw`，详情层的框整段不画（`Menu_Quest_Draw`）。
	assert_true(view.world_map_open and view._pages.world_map.visible and
		not detail.get_node("Bounds").visible,
		"OK 打开世界地图，详情层的框让开")
	# overlay 2 跳过 `Menu_win_DrawBasic`：菜单窗框与页签一起消失，且世界地图窗口在
	# 详情层之后绘制（`get_index()` 更大），否则页签会盖住地图窗的顶边框。
	assert_true(not view.get_node("Frame").visible
		and view._pages.world_map.get_index() > detail.get_index(),
		"世界地图窗口之上没有菜单窗框与页签")
	# 世界地图复用的是菜单自己那一层底（`Menu_Quest_mPaint` 的 overlay 2 同样只
	# `Map_Copy` 那张快照），整棵树里的半透明模糊层始终只有一层。
	assert_eq(_visible_blur_layers(get_tree().root), 1, "任务页开图后仍只有一层半透明模糊底")
	# `Map_worldINIT(JC_fxtQINDEX(text_resource, 3, 0), 1)`：焦点是任务 2 的第一个关联地域 15，
	# 不是存档里的地图 1。
	var canvas: Control = view._pages.world_map.get_node("Content/Viewport/Canvas")
	assert_eq(canvas.focus_id(), 15, "开图焦点是任务地域 15，不退回玩家所在地图 1")
	while view._pages.world_map.is_transitioning():
		await get_tree().process_frame
	view.press("Escape")
	while view._pages.world_map.is_transitioning():
		await get_tree().process_frame
	assert_true(detail.get_node("Bounds").visible,
		"CLR 关窗回到详情层（`Menu_Quest_mKeyPressed` 的 -16 把层号写回 1）")
	view.queue_free()
	await get_tree().process_frame


## T-C3：`Qst_chtDRAW`／`Qst_chtKeyPress` 的详情页与 `Field_Quest_Complete_SetResult` 的完成页。
func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")
	var table: QuestTable = QuestSet.load_table()
	var log := QuestLog.new(QuestLog.empty_dict())
	# 一名出战怪（属性组见 `MonsterDefinition.attribute_group`）：完成页要给它的属性格记经验。
	var species: MonsterDefinition = assets.load_gameplay_catalog().monster(PARTY_SPECIES)
	assert_true(species != null, "测试用的出战怪物种存在")
	var progress := {"parameter": {"level": 1, "moneyBalance": 0, "development": {"experience": 0}},
		"monsters": [{"species": PARTY_SPECIES, "nativeArguments": [PARTY_SPECIES, 5, 0],
			"nickname": 0, "hp": 5, "experience": 0}],
		"partyOrder": [0]}

	var detail: Control = QuestDetailScene.instantiate()
	get_tree().root.add_child(detail)
	detail.present(assets, table, log, QUEST_ID, QuestLog.CONTEXT_NPC)
	await _settle(detail)
	# `qst/qstlist.fxt:43` 的六段：标题／说明／目标／事件号／图标／地图，目标行的 `0/` 换成当前进度。
	assert_eq(detail.segments, ["击退赫拉", "击退在塔莲洞窟中欺负人们的赫拉。", "击退赫拉0/5", "29",
		"6", "塔莲洞窟"], "qstlist.fxt 的六段正文按 TAB 原样切分")
	assert_true(detail.goal_text == "击退赫拉 0/%d" % GOAL_COUNT and detail.segment(0) == "击退赫拉",
		"JC_fxtQUEST 把目标段的 0/ 换成槽里的进度值")
	# OK → 确认框（原生默认停在「是」）→ 再按 OK 写入普通槽 1..10。
	# P2-10 野外侧：页脚左项是「世界地图」（`Qst_chtKeyPress` 的 case 0，`Qst_chtINIT` 默认选中），
	# 49×22 按 `Menu_winDrawIcon18(x+12, v42−25)`；OK 走 `Map_worldINIT(page3[0], 1)` 并把层号置 1
	# （`Qst_chtDRAW` 的层 1 只画世界地图，详情窗整段不画）。
	var map_button: Control = detail.get_node("Content/MapButton")
	assert_true(map_button.button_pressed and map_button.get_global_rect() == Rect2(98, 183, 49, 22),
		"野外详情页页脚左项「世界地图」在 (98,183) 49×22，进页面时默认选中")
	detail.handle_key("Enter")
	var canvas: Control = detail.get_node("WorldMap/Content/Viewport/Canvas")
	assert_true(canvas.focus_id() == QUEST_REGION_MAP_ID and not detail.get_node("Bounds").visible,
		"OK 开图：焦点是任务 43 的第一个关联地域 %d，详情层让开" % QUEST_REGION_MAP_ID)
	# CLR 只把层号写回 0、共用相位写 1（`Qst_chtKeyPress` 层 1 的 -16），页面本身不关：
	# 地图窗同帧退场，详情窗从相位 1（条形）重放开窗动画——一段，不是「先收拢再开」两段。
	detail.handle_key("Escape")
	var field_map: Control = detail.get_node("WorldMap")
	assert_true(not field_map.visible and detail.is_transitioning()
		and detail.phase == QuestDetailScript.BoxPhase.BAR_FADED,
		"CLR 回详情层：地图窗不再画，详情窗从相位 1 重放开窗动画")
	# P2-66：层 1 的 -16 让地图窗同帧退场（原生不写 -1，没有收拢那段），逐拍也停。
	assert_true(not field_map.is_processing(),
		"CLR 回详情层时世界地图窗的逐拍已停（`leave()`：停 tick + 隐藏，不播 close）")
	for _frame in range(200):
		if not detail.is_transitioning():
			break
		await get_tree().process_frame
	assert_true(detail.get_node("Bounds").visible and detail.phase == QuestDetailScript.BoxPhase.STABLE,
		"重放的开窗动画把详情窗框带回稳态")
	detail.handle_key("ArrowRight")
	detail.handle_key("Enter")
	# `Qst_chtINIT:13`／`Qst_chtKeyPress:112` 都把确认项写 0 ⇒ 默认停在「是」。
	assert_true(detail.get_node("Confirm/Content/Yes/Choice/Highlight").visible
		and not detail.get_node("Confirm/Content/No/Choice/Highlight").visible,
		"接受确认框默认选中「是」（选定项 0）")
	# P2-65：进层 2 先把确认框自己的相位写 1（`Qst_chtKeyPress:116`），开合照
	# `Menu_win_Box2_DrawWindow` 的分相走 1→4；「否」只写 -1（`:59` → `:52`），
	# 要等 `Qst_chtRUN:9-13` 收到 -4 才把层号写回 0。
	var confirm: Control = detail.get_node("Confirm")
	var action_button: Control = detail.get_node("Content/ActionButton")
	assert_true(confirm.visible and confirm.is_transitioning()
		and confirm.phase == QuestDetailScript.BoxPhase.BAR_FADED,
		"接受确认框从相位 1 起播开窗动画")
	assert_eq(confirm.window_size, ConfirmLayout.select_size(QuestDetailScript.CONFIRM_WIDTH, 1),
		"确认框窗高按正文折行数算（Menu_win_Box2_DrawSelect:41-48，fxt 515 一行 = 160×57）")
	detail.handle_key("ArrowLeft")
	detail.handle_key("Enter")
	# 收拢期间层号仍是 2：右方向键还归确认层（被吞掉），不能落到页脚去换选中项。
	detail.handle_key("ArrowRight")
	assert_true(confirm.visible and confirm.is_transitioning() and action_button.button_pressed,
		"选「否」只起收拢动画：层号仍是 2，方向键没落到页脚")
	for _frame in range(200):
		if not confirm.is_transitioning():
			break
		await get_tree().process_frame
	assert_true(not confirm.visible and not detail.closing_confirm()
		and confirm.phase == QuestDetailScript.BoxPhase.CLOSED,
		"收拢播完（相位 -4）才回详情层")
	# 再开一次（`_open_confirm` 把确认项复位到「是」）并接受。
	detail.handle_key("Enter")
	detail.handle_key("Enter")
	assert_true(log.is_active(QUEST_ID) and log.slot_of(QUEST_ID) >= QuestLog.SLOT_FIRST_NORMAL,
		"接受任务后 QuestLog 的 1..10 普通槽里出现该任务")
	detail.queue_free()

	var complete: Control = QuestCompleteScene.instantiate()
	get_tree().root.add_child(complete)
	var record := table.record(QUEST_ID)
	assert_true(complete.present_quest(assets, table, log, QUEST_ID, progress),
		"在册任务的完成页可以打开")
	assert_true(complete.settlement.money == int(record["reward_money"]) and
		complete.settlement.rows[0].experience_left == int(record["reward_experience"]),
		"Field_Quest_Complete_SetResult 的金钱与经验取自任务记录的 reward_money／reward_experience")
	# 入账（`QuestReward.apply`）：金钱进 `moneyBalance`、经验进主角等级/经验，道具由 Story 走背包规则。
	var money_before := int(progress.parameter.moneyBalance)
	complete.settlement.apply(progress, assets.load_gameplay_catalog())
	assert_eq(int(progress.parameter.moneyBalance), money_before + int(record["reward_money"]),
		"奖励金钱写回 moneyBalance")
	assert_true(int(progress.parameter.level) > 1 or
		int(progress.parameter.development.experience) > 0,
		"奖励经验写回主角等级或经验（阈值 65 × 等级²）")
	# `BattleData + 10 + 属性`：出战怪按自己的属性落一格，值是 `总经验 / 10`。
	var mastery: Array = progress.parameter.development.get("masteryExperience", [])
	var attribute_slot: int = MonsterAttribute.index_of(int(species.attribute_group))
	assert_true(mastery.size() == MonsterAttribute.COUNT and
		int(mastery[attribute_slot]) == int(record["reward_experience"]) / 10,
		"任务完成把总经验 / 10 记进出战怪属性对应的那一格")
	# 经验加成窗口（`Field_Quest_Complete_SetResult:40-41`）：窗口内 `v2 += v2 / 5`，
	# 属性进度取加成后的 `v2 / 10`；窗口外的上一段是基础值。
	progress.parameter[Story.EXP_BONUS_KEY] = Story.EXP_BONUS_MILLISECONDS
	# 上一段 `present_quest` 末尾的 `Qst_stdComplete` 已清槽，重开完成页前先重新在册。
	assert_true(log.accept(table, QUEST_ID))
	var boosted: Control = QuestCompleteScene.instantiate()
	get_tree().root.add_child(boosted)
	assert_true(boosted.present_quest(assets, table, log, QUEST_ID, progress))
	var base := int(record["reward_experience"])
	assert_eq([int(boosted.settlement.rows[0].experience_left),
		int(boosted.settlement.attribute_experience)],
		[base + base / Story.EXP_BONUS_DIVISOR, (base + base / Story.EXP_BONUS_DIVISOR) / 10],
		"经验加成窗口内任务奖励经验 ×1.2，属性进度取加成后的 / 10")
	boosted.queue_free()
	complete.queue_free()


## 按真实的 GUI 命中测试点一次（不是直接 emit `pressed`）。
func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)


## P2-69／P2-70／P2-72：接受确认框的三条原生边界。
func test_confirm_guards() -> void:
	var assets := get_node("/root/AssetCatalog")
	var table: QuestTable = QuestSet.load_table()
	# 普通槽 1..10 先占满：`Qst_stdEmpty` 模式 3 抢不到槽，走 `Qst_chtKeyPress:84-89` 的失败分支。
	var quests := QuestLog.empty_dict()
	for slot in range(QuestLog.SLOT_FIRST_NORMAL, QuestLog.SLOT_LAST_NORMAL + 1):
		quests["slots"][slot] = {"marker": QuestLog.CONTEXT_NPC, "npc": 4,
			"quest": QUEST_ID + slot, "goal_kind": QuestTable.GOAL_PROGRESS,
			"goal_target": 0, "goal_count": 1, "progress": 0}

	var detail: Control = QuestDetailScene.instantiate()
	get_tree().root.add_child(detail)
	detail.present(assets, table, QuestLog.new(quests), QUEST_ID, QuestLog.CONTEXT_NPC)
	await _settle(detail)
	detail.handle_key("ArrowRight")
	detail.handle_key("Enter")
	var confirm: Control = detail.get_node("Confirm")
	detail.handle_key("Enter")
	assert_push_error("个普通任务槽已满")
	# P2-69：失败只推 fxt 512 就 return，层号 `context_parameter_bits + 1` 与相位都不动。
	assert_true(confirm.visible and not detail.closing_confirm()
		and detail._layer == QuestDetailScript.LAYER_CONFIRM,
		"抢槽失败只推提示：确认框留在场上，层号仍是确认层")
	# P2-72：确认框盖一层铺满 400×240 的 STOP 拦截层（`Confirm/ModalLayer`，在 `Content` 之前）：
	# 点页脚右下角的 CLR 命中区（`Content/BackHit` → `close()`，没有层号守卫）不会关掉整页。
	var back_hit: Control = detail.get_node("Content/BackHit")
	var modal: Control = detail.get_node("Confirm/ModalLayer")
	_click(back_hit)
	assert_true(not detail._closing and detail._layer == QuestDetailScript.LAYER_CONFIRM
		and modal.get_index() < detail.get_node("Confirm/Content").get_index(),
		"确认框打开时点页脚坐标不触发页脚动作（模态拦截层吃掉点击）")
	detail.queue_free()

	# P2-70：原生层 2 没有「收拢中」判断，`-5` 仍按当前选中项处理（`Qst_chtKeyPress:57-89`）。
	var log := QuestLog.new(QuestLog.empty_dict())
	var collapsing: Control = QuestDetailScene.instantiate()
	get_tree().root.add_child(collapsing)
	collapsing.present(assets, table, log, QUEST_ID, QuestLog.CONTEXT_NPC)
	await _settle(collapsing)
	collapsing.handle_key("ArrowRight")
	collapsing.handle_key("Enter")
	collapsing.handle_key("Escape")
	collapsing.handle_key("Enter")
	assert_true(log.is_active(QUEST_ID),
		"收拢期按确认键仍按选中项「是」接取（层 2 的 -5 不看收拢相位）")
	collapsing.queue_free()
