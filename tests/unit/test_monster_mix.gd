extends "res://tests/unit/gut_case.gd"

## 原生 `GAME_STATE_MONSTER_MIX`(22)：`Game_Monster_Mix_Percent` 的成功率、
## `_Proc` 的品级 ±1、两只的删除、200 金币与合成石的消耗、新精灵入包。

const MixScene = preload("res://game/field/monsters/monster_mix/monster_mix.tscn")
const MixScript = preload("res://game/field/monsters/monster_mix/monster_mix.gd")
const Story = preload("res://engine/data/story/story.gd")
const SlotFrame = preload("res://game/menu/party/slot_frame/slot_frame.gd")


class Provider extends RefCounted:
	var gameplay: GameplayData

	func load_gameplay() -> GameplayData:
		return gameplay


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


func _catalog() -> GameplayData:
	return get_node("/root/AssetCatalog").load_gameplay_catalog()


## 该品级里挑前两只（`Game_Monster_SetList(0)` 会排除出战三只，测试里不出战）。
func _pair(grade: int) -> Array[int]:
	var found: Array[int] = []
	for record: MonsterDefinition in _catalog().monsters:
		if int(record.attribute_entry) == grade:
			found.append(int(record.id))
		if found.size() == 2:
			break
	return found


func _story(species: Array[int], stones: Array[int], money: int) -> RefCounted:
	var state := Story.initial_progress(0, 2)
	state["parameter"]["moneyBalance"] = money
	var monsters: Array = []
	for id: int in species:
		monsters.append({"species": id, "level": 10, "nativeArguments": [id, 10, -1, -1, 0],
			"nickname": 0, "experience": 0, "hp": 1, "sp": 1,
			"brainCurrent": 2, "brainLimit": 5})
	state["monsters"] = monsters
	state["partyOrder"] = []
	var inventory := {}
	for item_id: int in stones:
		inventory[str(item_id)] = int(inventory.get(str(item_id), 0)) + 1
	state["inventory"] = inventory
	var provider := Provider.new()
	provider.gameplay = _catalog()
	var story = Story.new(provider, state, func(_limit: int) -> int: return 99)
	story.initialize()
	return story


func _open(story: RefCounted) -> Control:
	var page: Control = MixScene.instantiate()
	get_tree().root.add_child(page)
	page.present(story, get_node("/root/AssetCatalog"))
	await _settle(page)
	return page


## 页面按「主位 → 副位 → 确认框 → 合成石表 → 合成」走一遍；
## `stone` 为 true 时在合成石表里选中唯一那颗石头。
func _drive(page: Control, stone: bool) -> void:
	page.handle_key("Enter")
	page.handle_key("ArrowRight")
	page.handle_key("Enter")
	if stone:
		page.handle_key("Enter")
		page.handle_key("Enter")
		page.handle_key("Escape")
	page.handle_key("ArrowDown")
	page.handle_key("Enter")


## `_Proc` 的两次 `randi() % 100`：先掷加成、再掷判定。找一个判定必失败的种子，
## 让「降品级」这一支可复现（加成会把百分比抬高，所以按同一顺序模拟）。
func _failure_seed(percent: int, grade: int) -> int:
	for candidate in range(2000):
		seed(candidate)
		var bonus_roll := randi() % MonsterGrowth.ROLL_MODULUS
		var success_roll := randi() % MonsterGrowth.ROLL_MODULUS
		var bonus := MonsterMix.ability_bonus(0, grade, bonus_roll)
		if not MonsterMix.is_success(percent + bonus, success_roll):
			return candidate
	return 0


func test_legacy_suite() -> void:
	assert_true(MonsterMixTable.percent(0, ItemKind.index_of(
		ItemKind.id_of(ItemKind.Kind.GROUP_7, MonsterMixTable.MixStone.SCALE_220))) == 100 and
		MonsterMix.grade_after(4, true) == MonsterMixTable.GRADE_MAX and
		MonsterMix.grade_after(1, false) == 0 and
		MonsterMix.is_stone(ItemKind.id_of(ItemKind.Kind.GROUP_7,
			MonsterMixTable.MixStone.SCALE_170)) and
		not MonsterMix.is_stone(ItemKind.id_of(ItemKind.Kind.GROUP_7, 19)),
		"0x40F7C: grade 0 is 90% and the x2.2 stone lifts it past the 100 cap; 0x46D5C steps " +
		"the grade +1 on success / -1 on failure; only kind 7's 4/5 count as mix stones")

	# 成功率 100%：品级 0 的两只 + ×2.2 的合成石 ⇒ 必升到品级 1。
	var stone := ItemKind.id_of(ItemKind.Kind.GROUP_7, MonsterMixTable.MixStone.SCALE_220)
	var success_story := _story(_pair(0), [stone], 1000)
	var success_page: Control = await _open(success_story)
	assert_eq([success_page.get_node("Content/Ball0/Frame").texture,
		success_page.get_node("Content/Ball2/Frame").texture],
		[success_page.cell_frames[SlotFrame.Frame.IN_RANGE_FOCUSED],
			success_page.cell_frames[SlotFrame.Frame.IN_RANGE]],
		"Menu_Party_DrawBall 的格底公式：两只精灵占帧 0／1，第 3 格起是普通帧（空位也在范围内）")
	_drive(success_page, true)
	await get_tree().create_timer(1.4).timeout
	var remaining: Array = success_story.progress["monsters"]
	var child: Dictionary = remaining[0] if remaining.size() == 1 else {}
	var child_species: MonsterDefinition = _catalog().monster(int(child.get("species", -1)))
	assert_true(int(success_page.get("sub_state")) == MixScript.Phase.SUCCEEDED and
		remaining.size() == 1 and child_species != null and
		int(child_species.attribute_entry) == 1 and
		int(success_story.progress["parameter"]["moneyBalance"]) == 800 and
		not success_story.progress["inventory"].has(str(stone)) and
		int(child.get("level", 0)) == 10 and int(child.get("brainCurrent", -1)) == 2,
		"a 100% mix deletes both parents, charges 200 coins, eats the stone and Ball_stdSet " +
		"adds one grade-1 child with the averaged level / brain_current")
	success_page.queue_free()

	# 成功率 60%（品级 1、不放石头）：找一个判定失败的种子，品级应降到 0。
	var failure_pair := _pair(1)
	var failure_grade: int = int(_catalog().monster(failure_pair[0]).attribute_entry)
	var failure_seed := _failure_seed(MonsterMixTable.percent(failure_grade), failure_grade)
	var failure_story := _story(failure_pair, [], 1000)
	var failure_page: Control = await _open(failure_story)
	_drive(failure_page, false)
	seed(failure_seed)
	await get_tree().create_timer(1.4).timeout
	var failed: Array = failure_story.progress["monsters"]
	var failed_child: MonsterDefinition = _catalog().monster(
		int(failed[0].get("species", -1))) if failed.size() == 1 else null
	assert_true(int(failure_page.get("sub_state")) == MixScript.Phase.FAILED and
		failed_child != null and int(failed_child.attribute_entry) == 0 and
		int(failure_story.progress["parameter"]["moneyBalance"]) == 800,
		"a failed mix still consumes both parents and 200 coins, and the child drops one " +
		"grade (Game_Monster_Mix_Proc's v55 = 0 branch)")
	failure_page.queue_free()
