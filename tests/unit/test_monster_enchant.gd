extends "res://tests/unit/gut_case.gd"

## 原生 `GAME_STATE_MONSTER_ENCHANT`(23)：`Game_Monster_Enchant_Percent` 的成功率、
## `_Get` 的强化剂消耗与 `_Proc` 的 `Ball_stdBrain` 结算。

const EnchantScene = preload("res://game/field/monsters/monster_enchant/monster_enchant.tscn")
const EnchantScript = preload("res://game/field/monsters/monster_enchant/monster_enchant.gd")
const Story = preload("res://engine/data/story/story.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")

const SPECIES := 49
const BRAIN_LIMIT := 5


class Provider extends RefCounted:
	var gameplay: GameplayData

	func load_gameplay() -> GameplayData:
		return gameplay


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


## 一只 `brain_current = 0` 的精灵 + 若干强化剂：成功率基数 100，
## 选上位宝珠（定义号 2）后 `100 + 10 × 3 = 130` 被截到 100，判定必然成功。
func _story(money: int, brain_current: int, enhancers: Array[int]) -> RefCounted:
	var state := Story.initial_progress(0, 2)
	state["parameter"]["moneyBalance"] = money
	state["monsters"] = [{"species": SPECIES, "level": 10,
		"nativeArguments": [SPECIES, 10, -1, -1, 0], "nickname": 0, "experience": 0,
		"hp": 1, "sp": 1, "brainCurrent": brain_current, "brainLimit": BRAIN_LIMIT}]
	state["partyOrder"] = [0]
	var inventory := {}
	for item_id: int in enhancers:
		inventory[str(item_id)] = int(inventory.get(str(item_id), 0)) + 1
	state["inventory"] = inventory
	var provider := Provider.new()
	provider.gameplay = _catalog()
	var story = Story.new(provider, state, func(_limit: int) -> int: return 99)
	story.initialize()
	return story


func _catalog() -> GameplayData:
	return get_node("/root/AssetCatalog").load_gameplay_catalog()


func _open(story: RefCounted) -> Control:
	var page: Control = EnchantScene.instantiate()
	get_tree().root.add_child(page)
	page.present(story, get_node("/root/AssetCatalog"))
	await _settle(page)
	return page


func test_legacy_suite() -> void:
	var catalog: GameplayData = _catalog()
	var species: MonsterDefinition = catalog.monster(SPECIES)
	var attribute_enhancer := MonsterGrowth.attribute_enhancer_id(species)
	var orb := ItemKind.id_of(ItemKind.Kind.GROUP_7, 2)
	var super_enhancer := ItemKind.id_of(ItemKind.Kind.GROUP_7,
		MonsterGrowth.SUPER_ENHANCER_INDEX)
	assert_true(MonsterGrowth.percent(40, -1) == 60 and MonsterGrowth.percent(0, 2) == 100 and
		MonsterGrowth.enhancer_requirement(species, 3, true) == {"id": super_enhancer, "count": 1} and
		int(MonsterGrowth.enhancer_requirement(species, 3, false)["id"]) == attribute_enhancer,
		"percent is 100 - brain (+10 x (orb + 1), capped at 100); slot 0 costs brain + 1 of the " +
		"attribute enhancer unless the super enhancer is picked, which costs 1")

	var story := _story(200, 0, [orb, attribute_enhancer, attribute_enhancer])
	var page: Control = await _open(story)
	assert_eq([page.get_node("Content/Ball0/Frame").texture,
		page.get_node("Content/Ball1/Frame").texture],
		[page.cell_frames[SlotFrame.Frame.IN_RANGE_FOCUSED],
			page.cell_frames[SlotFrame.Frame.IN_RANGE]],
		"Menu_Party_DrawBall 的格底公式：只有一只精灵时第 2 格起是普通帧（空位也在范围内）")
	page.handle_key("Enter")
	page.handle_key("Enter")
	assert_eq(int(page.get("sub_state")), EnchantScript.Phase.ITEM,
		"0x43810 sub state 1 option 0 opens the enhancer list (sub state 2)")
	# 强化剂表只列 `kind 7` 的 0／1／2／19 号：这里只有上位宝珠 7002，光标停在第一格。
	page.handle_key("Enter")
	page.handle_key("Escape")
	page.handle_key("ArrowDown")
	page.handle_key("Enter")
	await get_tree().create_timer(1.4).timeout
	var monster: Dictionary = story.progress["monsters"][0]
	assert_true(int(page.get("sub_state")) == EnchantScript.Phase.SUCCEEDED and
		int(monster["brainCurrent"]) == 1 and
		int(story.progress["parameter"]["moneyBalance"]) == 100 and
		not story.progress["inventory"].has(str(orb)) and
		int(story.progress["inventory"].get(str(attribute_enhancer), 0)) == 1,
		"a 100% enhancement charges 100 coins, eats the orb and one attribute enhancer, " +
		"and Ball_stdBrain raises brain_current by 1 (sub state 5 = success)")
	# 关窗走共用生命周期（`field/field_window.gd`）：收拢动画播完才发 `closed`，
	# 宿主（`field_runtime` 的 `_close_monster_enchant`）靠它摘页。
	watch_signals(page)
	page.close()
	for _frame in range(200):
		await get_tree().process_frame
		if get_signal_emit_count(page, "closed") > 0:
			break
	assert_eq(get_signal_emit_count(page, "closed"), 1,
		"关闭页在收拢动画播完后发一次 closed，宿主才能摘页")
	page.queue_free()

	# 已经到上限的精灵：只弹 msg 127，不进确认框；钱不够（msg 79）／强化剂不够（msg 128）
	# 都停在确认框且什么都不改。
	var full_story := _story(200, BRAIN_LIMIT, [])
	var full_page: Control = await _open(full_story)
	full_page.handle_key("Enter")
	var refused_at_limit := int(full_page.get("sub_state")) == EnchantScript.Phase.MONSTER
	var broke_story := _story(50, 0, [])
	var broke_page: Control = await _open(broke_story)
	broke_page.handle_key("Enter")
	broke_page.handle_key("ArrowDown")
	broke_page.handle_key("Enter")
	var refused_money := int(broke_page.get("sub_state")) == EnchantScript.Phase.CONFIRM and \
		int(broke_story.progress["parameter"]["moneyBalance"]) == 50
	var poor_story := _story(200, 0, [])
	var poor_page: Control = await _open(poor_story)
	poor_page.handle_key("Enter")
	poor_page.handle_key("ArrowDown")
	poor_page.handle_key("Enter")
	var refused_shortage := int(poor_page.get("sub_state")) == EnchantScript.Phase.CONFIRM and \
		int(poor_story.progress["parameter"]["moneyBalance"]) == 200
	assert_true(refused_at_limit and refused_money and refused_shortage,
		"brain_current >= brain_limit stays in sub state 0 (msg 127); money <= 99 (msg 79) and " +
		"missing enhancers (msg 128) keep the confirm page and change nothing")
	full_page.queue_free()
	broke_page.queue_free()
	poor_page.queue_free()
