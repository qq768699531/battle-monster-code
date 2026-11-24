extends "res://tests/unit/gut_case.gd"

const GuildQuestScene = preload("res://game/field/guild/guild_quest/guild_quest.tscn")

## 任务表里唯一的公会 NPC：`npc:46`（「公会会长」，`qstlist.sub` 里带 38 条任务、档位 97→2）。
const GUILD_NPC := 46
const FIRST_QUEST := 0
## 别的 NPC 的任务（`npc:25` 的 38 号）：用真实记录占住公会槽 0。
const FOREIGN_QUEST := 38


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


## T-B4：`Field_Guild_List_mKeyPressed` 的 `case 1` → `Qst_stdQuest` →
## `Qst_chtINIT(2, quest_id)` → 状态 8；接受写 `Qst_stdEmpty` 模式 2 的专用槽 0。
func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")
	var table: QuestTable = load("res://assets/quests.tres")
	var context := {"guild_code": 0, "event_id": 0}
	var log := QuestLog.new(QuestLog.empty_dict())

	var page: Control = GuildQuestScene.instantiate()
	get_tree().root.add_child(page)
	var shown: bool = page.present_for_npc(assets, table, log, GUILD_NPC, context)
	await _settle(page)
	assert_true(shown and page.quest_id == FIRST_QUEST,
		"Qst_stdQuest 取公会会长（46）任务链链头：任务 0（档位 97、无前置、事件号 0）")
	page._open_confirm()
	page._resolve_confirm(0)
	assert_eq(log.slot_of(FIRST_QUEST), QuestLog.SLOT_GUILD,
		"接受后写进公会专用槽 0（Qst_stdEmpty 模式 2）")
	page.queue_free()

	# 槽 0 被别的 NPC 的任务 38 占着：本 NPC 仍能取到链头任务 0 并打开详情，
	# 接受时 `Qst_stdEmpty(2)` 抢不到槽 → `msg 512`，原任务不被覆盖。
	var occupied := QuestLog.new(QuestLog.empty_dict())
	assert_true(occupied.accept(table, FOREIGN_QUEST, QuestLog.CONTEXT_GUILD),
		"槽 0 先被 npc 25 的任务 38 占用")
	var second: Control = GuildQuestScene.instantiate()
	get_tree().root.add_child(second)
	var reopened: bool = second.present_for_npc(assets, table, occupied, GUILD_NPC, context)
	await _settle(second)
	second._open_confirm()
	second._resolve_confirm(0)
	assert_push_error("公会任务槽已被占用")
	# 静态提示行已退役（T-D4）：拒绝原因现在由 `_notice` 的 setter 推给提示栈，
	# 所以断言看记录号而不是看页面上那行文本。
	assert_true(reopened and occupied.slot_of(FOREIGN_QUEST) == QuestLog.SLOT_GUILD and
		int(second.notice_id) == 512,
		"槽 0 已占用时按原生拒绝（msg 512）且不覆盖原任务")
	second.queue_free()
