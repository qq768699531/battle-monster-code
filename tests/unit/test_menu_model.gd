extends "res://tests/unit/gut_case.gd"

const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const Story = preload("res://engine/data/story/story.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")


func _run() -> void:
	assert_true(Menu.party_point_limit({"guildCode": 99, "parameter": {"standardProgressPoints": 0}}) == 27
		and Menu.party_point_limit({"guildCode": 99, "parameter": {"standardProgressPoints": 97020}}) == 33
		and Menu.party_point_limit({"guildCode": 100, "parameter": {"standardProgressPoints": 0}}) == \
			Menu.GUILD_GRADE_PARTY_POINTS[0],
		"native PARTY limit adds standard-progress bands on top of the guild grade base")
	var progress := {"guildCode": 4, "parameter": {"identity": 2, "level": 10,
		"trait": 1, "development": {"experience": 120, "growth": [1, 2, 3, 4, 5, 6],
			"points": 3, "allocated": [1, 0, 2]}},
		"inventory": {"1001": 2}, "monsters": []}
	var before: Dictionary = progress.duplicate(true)
	var preview := Menu.status_allocation_preview(progress, [0, 0, 0], 1)
	var result := Menu.apply_status_allocation(progress, [1, 1, 0])
	assert_true(preview.get("ok", false) and preview.pending == [0, 1, 0]
		and result.get("ok", false) and result.spent == 2
		and result.progress.parameter.development.points == 1
		and result.progress.parameter.development.allocated == [2, 1, 2]
		and progress == before,
		"status allocation previews and applies point deltas on an isolated copy")
	var admission := {"parameter": {"level": 10}, "guildCode": 99, "partyOrder": [0],
		"monsters": [{"nativeArguments": [49, 5, 0, -1, 0]},
			{"nativeArguments": [49, 5, 0, -1, 0]},
			{"nativeArguments": [49, 16, 0, -1, 0]},
			{"nativeArguments": [49, 15, 0, -1, 0]}]}
	var admission_catalog := Fixtures.data({"monsters": [{"id": 49, "attribute_entry": 5}]})
	assert_true(Menu.join_party(admission, admission_catalog, 3).ok
		and admission.partyOrder == [0, 3]
		and Menu.party_points(admission, admission_catalog, admission.partyOrder) == 18,
		"party admission appends an owned ball within the native point limit")
	assert_true(Menu.guild_grade(0) == Menu.GUILD_GRADE_MAX
		and Menu.guild_grade(Story.GUILD_CODE_MAX) == Menu.GUILD_GRADE_MAX
		and Menu.guild_grade(Story.GUILD_CODE_MAX + 1) == 0
		and Menu.guild_title_record({"guildCode": Story.GUILD_CODE_MAX}) == \
			Msg.Id.GUILD_TITLE_FIRST + Menu.GUILD_GRADE_MAX,
		"guild grade follows the native all-99 comparison chain and picks the title record")
	var capped := {"parameter": {"level": 10}, "guildCode": Story.GUILD_CODE_MAX + 1,
		"partyOrder": [], "monsters": [{"nativeArguments": [49, 5, 0, -1, 0]}]}
	assert_true(Menu.join_party(capped, admission_catalog, 0).get("message") == \
			Msg.Id.PARTY_POINTS_SHORT and capped.partyOrder == [],
		"party admission rejects a member above the guild grade's point cap")
	assert_true(Menu.item_actions({"id": 1001, "type": 1, "index": 1}) ==
			[Menu.ITEM_ACTION_USE, Menu.ITEM_ACTION_DISCARD]
		and Menu.item_actions({"id": 1025, "type": 1, "index": 25}) ==
			[Menu.ITEM_ACTION_DISCARD]
		and Menu.item_actions({"id": 7003, "type": 7, "index": 3}) ==
			[Menu.ITEM_ACTION_USE, Menu.ITEM_ACTION_DISCARD]
		and Menu.item_actions({"id": 7006, "type": 7, "index": 6}) ==
			[Menu.ITEM_ACTION_DISCARD]
		and Menu.item_actions({"id": 2001, "type": 2, "index": 1}) ==
			[Menu.ITEM_ACTION_DISCARD],
		"item action lists follow the native bag/kind table")
	assert_true(Menu.item_stack_limit({"type": 1, "index": 0}) == 99
		and Menu.item_stack_limit({"type": 1, "index": 19}) == 10
		and Menu.item_stack_limit({"type": 3, "index": 0}) == 99
		and Menu.item_stack_limit({"type": 4, "index": 0}) == 10
		and Menu.item_stack_limit({"type": 7, "index": 0}) == 20
		and Menu.item_stack_limit({"type": 7, "index": 6}) == 1
		and Menu.item_stack_limit({"type": 2, "index": 0}) == 1,
		"item stack limits follow Item_stdMax")
	# `Item_stdExplain@0x82F70` 的 case 3 只置 `n220 = 220`，记录号由 `:136-138` 的
	# `JC_fxt2Return(2 * n220)` 算出 440（「材料道具」）；220 本身是「送礼物」。
	var explanation_text := func(id: int) -> String:
		return str(({Msg.Id.ITEM_EXPLANATION_MATERIAL: "材料道具",
			Msg.Id.ITEM_EXPLANATION_MATERIAL_BASE: "送礼物"}).get(id, ""))
	var material_explanation := Menu.native_item_explanation({"type": 3, "index": 0}, explanation_text)
	assert_true(material_explanation == "材料道具" and material_explanation != "送礼物",
		"material bag explanations read the doubled record 2 * 220 = 440, not the 220 gift record")
	var bag := {"inventory": {"1001": 5, "3000": 1}}
	assert_true(Menu.discard_inventory_item(bag, {"id": 1001}, 3).ok
		and bag.inventory == {"1001": 2, "3000": 1},
		"discard subtracts from the recorded total and keeps the other slots")
	assert_true(not Menu.discard_inventory_item(bag, {"id": 1001}, 5).ok
		and not Menu.discard_inventory_item(bag, {"id": 1001}, 0).ok
		and bag.inventory == {"1001": 2, "3000": 1},
		"discard rejects counts outside the recorded quantity without touching the bag")
	assert_true(Menu.discard_inventory_item(bag, {"id": 1001}, 2).ok
		and bag.inventory == {"3000": 1},
		"discard drops the key when the stack is emptied")
	# 丢弃也走宿主回放：同一件道具、同一数量重做一次，快照必须一致。
	var discard_source := {"inventory": {"1001": 3}}
	var discard_direct := discard_source.duplicate(true)
	Menu.discard_inventory_item(discard_direct, {"id": 1001}, 2)
	var discard_catalog := Fixtures.data({"items": [{"id": 1001, "type": 1, "index": 1,
		"icon": 1, "detail_slots": [0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]}]})
	var discard_replay := Menu.replay_operation(discard_source, discard_catalog,
		{"kind": "discard", "item_id": 1001, "count": 2, "category": 0})
	assert_true(discard_replay.get("ok", false) and discard_replay.progress == discard_direct,
		"replay_operation reproduces an item discard")
	# 菜单侧使用道具与战斗共用 `ItemEffect`（`Ball_stdUse`）：HP 药扣一个并回血；
	# 复活道具对活着的成员返回 10 且不扣、对倒下的成员回满并扣掉最后一个；未接的效果直接拒绝。
	var use_catalog := Fixtures.data({"items": [
		{"id": 1001, "type": 1, "index": 1, "icon": 1,
			"detail_slots": [0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]},
		{"id": 1017, "type": 1, "index": 17, "icon": 1,
			"detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 0, 0, 0, 0]},
		{"id": 1031, "type": 1, "index": 31, "icon": 31},
		{"id": 1037, "type": 1, "index": 37, "icon": 37},
		{"id": 7003, "type": 7, "index": 3, "icon": 3},
		{"id": 7015, "type": 7, "index": 15, "icon": 15},
		{"id": 1019, "type": 1, "index": 19, "icon": 19},
		{"id": 1020, "type": 1, "index": 20, "icon": 20},
		{"id": 7009, "type": 7, "index": 9, "icon": 9},
		{"id": 7010, "type": 7, "index": 10, "icon": 10},
		{"id": 7011, "type": 7, "index": 11, "icon": 11},
		{"id": 7012, "type": 7, "index": 12, "icon": 12},
		{"id": 7013, "type": 7, "index": 13, "icon": 13},
		{"id": 7014, "type": 7, "index": 14, "icon": 14},
		{"id": 7016, "type": 7, "index": 16, "icon": 16},
		{"id": 7017, "type": 7, "index": 17, "icon": 17},
		{"id": 7021, "type": 7, "index": 21, "icon": 21},
		{"id": 4000, "type": 4, "index": 0, "grade_index": 0},
		{"id": 4001, "type": 4, "index": 1, "grade_index": 1,
			"detail_slots": [0, 0x0201, 0x0002]}],
		"monsters": [{"id": 49, "kind": 0, "attribute_group": 3, "attribute_entry": 0,
			"ability_inputs": [14, 13, 12, 11, 17, 16],
			"attribute_inputs": [16, 4, 22, 2, 11, 2]},
			{"id": 50, "attribute_entry": 1}, {"id": 51, "attribute_entry": 2},
			{"id": 52, "attribute_entry": 3}],
		"passives": [{"id": 1, "effect": 0, "base": 10, "increment": 1},
			{"id": 2, "effect": 1, "base": 10, "increment": 1}]})
	var use_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0],
		"inventory": {"1001": 2, "1017": 2}, "parameter": {}}
	var healed := Menu.use_item(use_progress, use_catalog, 1001, 0)
	assert_true(healed.get("code") == ItemEffect.Code.HP
		and healed.get("message_id") == Msg.Id.ITEM_RECOVER
		and int(use_progress.monsters[0]["hp"]) > 5
		and int(use_progress.inventory["1001"]) == 1,
		"menu HP items heal through the shared Ball_stdUse rule and consume one")
	var alive := Menu.use_item(use_progress, use_catalog, 1017, 0)
	use_progress.monsters[0]["hp"] = 0
	var revived := Menu.use_item(use_progress, use_catalog, 1017, 0)
	assert_true(alive.get("code") == ItemEffect.Code.NOT_DOWN
		and int(use_progress.inventory.get("1017", 0)) == 1
		and revived.get("code") == ItemEffect.Code.REVIVED
		and int(use_progress.monsters[0]["hp"]) > 0,
		"menu revive items skip living members without consuming and refill a downed one")
	assert_true(Menu.item_actions({"id": 1017, "type": 1, "index": 17}) ==
			[Menu.ITEM_ACTION_DISCARD]
		and Menu.item_actions({"id": 1001, "type": 1, "index": 1}) ==
			[Menu.ITEM_ACTION_USE, Menu.ITEM_ACTION_DISCARD],
		"the native action list offers 使用 only for indices <=7, 19-24 and 31-37")
	assert_true(not Menu.item_use_supported({"id": ItemKind.id_of(ItemKind.Kind.CONSUMABLE, 25)})
		and not Menu.use_item(use_progress, use_catalog,
			ItemKind.id_of(ItemKind.Kind.CONSUMABLE, 25), 0).get("ok", false)
		and int(use_progress.inventory.get("1001", 0)) == 1,
		"menu item use rejects the unimplemented passive-boost family without consuming")
	# 饥饿度补充（第 1 组 37 只回饱食度、31–36 加心情并回满）：菜单侧走同一份 Ball_stdUse。
	var food_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5, "food": 10}], "partyOrder": [0],
		"inventory": {"1031": 1, "1037": 2}, "parameter": {}}
	var fed := Menu.use_item(food_progress, use_catalog, 1037, 0)
	assert_true(fed.get("code") == ItemEffect.Code.FOOD_RESTORED
		and int(food_progress.monsters[0]["food"]) == ItemEffect.FOOD_MAX
		and int(food_progress.inventory.get("1037", 0)) == 1,
		"menu food item 1037 fills hunger and consumes one")
	var stuffed := Menu.use_item(food_progress, use_catalog, 1037, 0)
	var tasted := Menu.use_item(food_progress, use_catalog, 1031, 0)
	assert_true(stuffed.get("code") == ItemEffect.Code.FOOD_STUFFED
		and int(food_progress.inventory.get("1037", 0)) == 1
		and tasted.get("code") in [ItemEffect.Code.FEEL_GOOD, ItemEffect.Code.FEEL_BAD]
		and int(food_progress.monsters[0]["food"]) == ItemEffect.FOOD_MAX
		and not food_progress.inventory.has("1031"),
		"full hunger rejects 37 without consuming, while 31-36 still add feel and refill")
	# 第 7 组 3：才能写 99；已满返回 20 且不扣。第 7 组 15：退回已分配能力点。
	var brain_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5, "brainCurrent": 5}], "partyOrder": [0],
		"inventory": {"7003": 1}, "parameter": {}}
	var brain_up := Menu.use_item(brain_progress, use_catalog, 7003, 0)
	brain_progress.inventory["7003"] = 1
	var brain_max := Menu.use_item(brain_progress, use_catalog, 7003, 0)
	assert_true(brain_up.get("code") == ItemEffect.Code.BRAIN_UP
		and int(brain_progress.monsters[0]["brainCurrent"]) == ItemEffect.BRAIN_BOOSTED
		and brain_max.get("code") == ItemEffect.Code.BRAIN_MAX
		and int(brain_progress.inventory["7003"]) == 1,
		"group-7 index 3 raises brain_current to 99 and a maxed one is rejected without consuming")
	var ability_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7015": 1},
		"parameter": {"development": {"points": 1, "allocated": [1, 0, 2]}}}
	var recovered := Menu.use_item(ability_progress, use_catalog, 7015, 0)
	assert_true(recovered.get("code") == ItemEffect.Code.ABILITY_RECOVERED
		and int(ability_progress.parameter.development.points) == 4
		and ability_progress.parameter.development.allocated == [0, 0, 0]
		and not ability_progress.inventory.has("7015"),
		"group-7 index 15 refunds the allocated development points and consumes one")
	var no_points := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7015": 1},
		"parameter": {"development": {"points": 0, "allocated": [0, 0, 0]}}}
	var none := Menu.use_item(no_points, use_catalog, 7015, 0)
	assert_true(none.get("code") == ItemEffect.Code.ABILITY_NONE
		and int(no_points.inventory["7015"]) == 1,
		"group-7 index 15 with nothing to refund reports code 26 and keeps the item")
	# 第 7 组 21：等级 > 0 的被动槽清零并扣道具（返回 29／502）；本来全空返回 30／503 且不扣。
	var clear_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5, "passiveSlots": [[1, 2], [0, 0], [2, 1], [0, 0], [0, 0], [0, 0]]}],
		"partyOrder": [0], "inventory": {"7021": 1}, "parameter": {}}
	var cleared := Menu.use_item(clear_progress, use_catalog, 7021, 0)
	assert_true(cleared.get("code") == ItemEffect.Code.PASSIVES_CLEARED
		and clear_progress.monsters[0]["passiveSlots"] == [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
		and not clear_progress.inventory.has("7021")
		and cleared.get("message_id") == Msg.Id.ITEM_PASSIVES_CLEARED,
		"group-7 index 21 clears every occupied passive slot and consumes one")
	var bare_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7021": 1}, "parameter": {}}
	var bare := Menu.use_item(bare_progress, use_catalog, 7021, 0)
	assert_true(bare.get("code") == ItemEffect.Code.PASSIVES_NONE
		and int(bare_progress.inventory["7021"]) == 1
		and bare.get("message_id") == Msg.Id.ITEM_PASSIVES_NONE,
		"group-7 index 21 with no passives reports code 30 and keeps the item")
	# 第 7 组 16 扣一件并返回码 27（页面由宿主打开）；17 原生无分支，返回 0／提示 510 且不扣。
	var mastery_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7016": 1},
		"parameter": {}}
	var mastery := Menu.use_item(mastery_progress, use_catalog, 7016, 0)
	assert_true(mastery.get("code") == ItemEffect.Code.MASTERY_SELECT
		and mastery.get("consumed") and not mastery_progress.inventory.has("7016")
		and mastery.get("message_id") == 0,
		"group-7 index 16 consumes one and reports code 27 without a prompt")
	var unusable_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7017": 1},
		"parameter": {}}
	var unusable := Menu.use_item(unusable_progress, use_catalog, 7017, 0)
	assert_true(unusable.get("code") == ItemEffect.Code.FAILED
		and not unusable.get("consumed")
		and unusable.get("message_id") == Msg.Id.ITEM_UNUSABLE
		and int(unusable_progress.inventory["7017"]) == 1,
		"group-7 index 17 reports code 0 with msg 510 and keeps the item")
	# 技能书袋（原生袋 3）的「合成」：`Menu_Item_SetMenuList` 的 case 3 给合成＋丢弃，
	# `Menu_Item_Mix_IsPossible` 按 detail[1]／[2]（低字节材料、高字节数量，0 即不需要）核材料，
	# 确认时原生先查余额（199 以下报 79）；第 4 组效果未落地，所以扣钱之前就拒绝、钱不动。
	var book := {"id": ItemKind.id_of(ItemKind.Kind.SKILL_BOOK, 1),
		"type": ItemKind.Kind.SKILL_BOOK, "index": 1,
		"detail_slots": [0, 0x0201, 0x0002]}
	var book_progress := {"partyOrder": [0], "monsters": [{"nativeArguments": [49, 5, 0, -1, 0]}],
		"inventory": {"3001": 2}, "parameter": {"moneyBalance": 500}}
	assert_true(Menu.item_actions(book) == [Menu.ITEM_ACTION_MIX, Menu.ITEM_ACTION_DISCARD]
		and Menu.material_recipe_possible(book_progress, book)
		and not Menu.material_recipe_possible({"inventory": {"3001": 1}}, book),
		"skill books offer 合成 and check the recorded material counts")
	var short_funds := Menu.mix_item({"partyOrder": [0], "monsters": [{}],
		"parameter": {"moneyBalance": 199}}, book, 0)
	# 原生 `Menu_Item_mKeyPressed` 的 0xA 先 `Param_moneySET(-200)` 再 `Ball_stdUseEx`：
	# 成功写进首个空被动槽（返回码 31），材料按 detail[1]／[2] 各扣一次。
	var mixed := Menu.mix_item(book_progress, book, 0)
	assert_true(short_funds.get("message_id") == Msg.Id.SHOP_NOT_ENOUGH_MONEY
		and mixed.get("code") == ItemEffect.Code.MIX_DONE
		and int(mixed["slot"]) == 0
		and int(book_progress.parameter.moneyBalance) == 300
		and not book_progress.inventory.has("3001")
		and book_progress.monsters[0]["passiveSlots"][0] == [1, 1],
		"mix charges 200 first, then writes the passive into slot 0 and consumes the materials")
	# 宿主回放合成：同一份活存档重做扣钱、扣料与写被动，快照必须逐字段相同。
	var mix_source := {"partyOrder": [0], "monsters": [{"nativeArguments": [49, 5, 0, -1, 0]}],
		"inventory": {"3001": 2, "4001": 1}, "parameter": {"moneyBalance": 500}}
	var mix_direct := mix_source.duplicate(true)
	Menu.mix_item(mix_direct, book, 0)
	var mix_replay := Menu.replay_operation(mix_source, use_catalog,
		{"kind": "mix", "item_id": 4001, "member": 0, "category": 3})
	assert_true(mix_replay.get("ok", false) and mix_replay.progress == mix_direct,
		"replay_operation reproduces the mix fee, materials and passive slot")
	var again := Menu.mix_item(book_progress, book, 0)
	assert_true(again.get("code") == ItemEffect.Code.MIX_NO_MATERIAL,
		"spent materials make the second mix report 33")
	var duplicate := {"partyOrder": [0], "monsters": [{"nativeArguments": [49, 5, 0, -1, 0],
		"passiveSlots": [[1, 1], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]}],
		"inventory": {"3001": 2}, "parameter": {"moneyBalance": 500}}
	var repeated := Menu.mix_item(duplicate, book, 0)
	assert_true(repeated.get("code") == ItemEffect.Code.MIX_DUPLICATE
		and int(duplicate.parameter.moneyBalance) == 300
		and int(duplicate.inventory["3001"]) == 2,
		"an already known passive reports 32, still charges the fee, keeps the materials")
	var occupied := {"partyOrder": [0], "monsters": [{"nativeArguments": [49, 5, 0, -1, 0],
		"passiveSlots": [[2, 1], [3, 1], [4, 1], [5, 1], [6, 1], [7, 1]]}],
		"inventory": {"3001": 2}, "parameter": {"moneyBalance": 500}}
	var full := Menu.mix_item(occupied, book, 0)
	assert_true(full.get("code") == ItemEffect.Code.MIX_NO_SLOT
		and int(occupied.parameter.moneyBalance) == 300,
		"six occupied slots report 34 after the fee")

	# 第 1 组 19–24：属性技能上升卡。原生先按 kind 核卡属性，再把 0–5 槽里 1–8 级的
	# 被动各升一级；全空 13、全部到 9 级 12，这两支不扣卡。
	var upgrade_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5,
			"passiveSlots": [[1, 8], [2, 9], [0, 0], [0, 0], [0, 0], [0, 0]]}],
		"partyOrder": [0], "inventory": {"1020": 1}, "parameter": {}}
	var upgraded := Menu.use_item(upgrade_progress, use_catalog, 1020, 0)
	assert_true(upgraded.get("code") == ItemEffect.Code.PASSIVE_UPGRADE_DONE
		and upgraded.get("message_id") == Msg.Id.ITEM_PASSIVE_UPGRADE_DONE
		and upgrade_progress.monsters[0]["passiveSlots"] ==
			[[1, 9], [2, 9], [0, 0], [0, 0], [0, 0], [0, 0]]
		and not upgrade_progress.inventory.has("1020"),
		"a matching attribute card raises occupied passive levels, caps at 9 and consumes one")
	var maxed_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5,
			"passiveSlots": [[1, 9], [2, 9], [0, 0], [0, 0], [0, 0], [0, 0]]}],
		"partyOrder": [0], "inventory": {"1020": 1}, "parameter": {}}
	var maxed := Menu.use_item(maxed_progress, use_catalog, 1020, 0)
	var empty_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5,
			"passiveSlots": [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]}],
		"partyOrder": [0], "inventory": {"1020": 1}, "parameter": {}}
	var empty := Menu.use_item(empty_progress, use_catalog, 1020, 0)
	assert_true(maxed.get("code") == ItemEffect.Code.PASSIVE_UPGRADE_MAX
		and maxed.get("message_id") == Msg.Id.ITEM_PASSIVE_UPGRADE_MAX
		and empty.get("code") == ItemEffect.Code.PASSIVE_UPGRADE_NONE
		and empty.get("message_id") == Msg.Id.ITEM_PASSIVE_UPGRADE_NONE
		and int(maxed_progress.inventory["1020"]) == 1
		and int(empty_progress.inventory["1020"]) == 1,
		"all-maxed and no-passive cards report 12/13 without consuming")
	var wrong_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5,
			"passiveSlots": [[1, 5], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]}],
		"partyOrder": [0], "inventory": {"1019": 1}, "parameter": {}}
	var wrong := Menu.use_item(wrong_progress, use_catalog, 1019, 0)
	assert_true(wrong.get("code") == ItemEffect.Code.PASSIVE_UPGRADE_WRONG_KIND
		and wrong.get("message_id") == Msg.Id.ITEM_PASSIVE_UPGRADE_WRONG_KIND
		and wrong_progress.monsters[0]["passiveSlots"][0] == [1, 5]
		and int(wrong_progress.inventory["1019"]) == 1,
		"a fire card on a water monster reports 11, leaves levels and keeps the card")
	# 旧存档没有 passiveSlots：按 nativeArguments[6]/[7] 落 0 号槽。
	var legacy_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0, 0, 1, 8],
			"nickname": 0, "hp": 5, "sp": 5}],
		"partyOrder": [0], "inventory": {"1020": 1}, "parameter": {}}
	var legacy := Menu.use_item(legacy_progress, use_catalog, 1020, 0)
	assert_true(legacy.get("code") == ItemEffect.Code.PASSIVE_UPGRADE_DONE
		and legacy_progress.monsters[0]["passiveSlots"] ==
			[[1, 9], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
		and not legacy_progress.inventory.has("1020"),
		"a legacy save without passiveSlots seeds slot 0 from nativeArguments and persists the upgrade")


	# 第 7 组 9–14：随机球按品级过滤物种并追加进怪物背包；随机技能书按 grade_index 入袋。
	# 成功码 21／23 原生静默，失败码 22／24 走 msg 498／499 且不扣道具。
	var roll_progress := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0],
		"inventory": {"7009": 1, "7013": 1, "7014": 1},
		"parameter": {"level": 7}, "monsterCapacity": 20,
		"itemCapacity": [72, 72, 72, 72, 72, 72]}
	var ball_used := Menu.use_item(roll_progress, use_catalog, 7009, 0)
	var recruited: Dictionary = roll_progress.monsters.back()
	assert_true(ball_used.get("code") == ItemEffect.Code.RANDOM_BALL_ADDED
		and ball_used.get("message_id") == 0
		and roll_progress.monsters.size() == 2
		and int(recruited.level) == 7
		and use_catalog.monster(int(recruited.species)).attribute_entry == 0
		and recruited.passiveSlots.size() == ItemEffect.PASSIVE_SLOT_COUNT
		and int(recruited.passiveSlots[0][1]) == 1
		and int(recruited.brainCurrent) >= 1
		and not roll_progress.inventory.has("7009"),
		"group-7 random balls append a grade-matched monster and consume one")
	var book_used := Menu.use_item(roll_progress, use_catalog, 7013, 0)
	var rare_used := Menu.use_item(roll_progress, use_catalog, 7014, 0)
	assert_true(book_used.get("code") == ItemEffect.Code.RANDOM_BOOK_ADDED
		and rare_used.get("code") == ItemEffect.Code.RANDOM_BOOK_ADDED
		and int(roll_progress.inventory.get("4000", 0)) == 1
		and int(roll_progress.inventory.get("4001", 0)) == 1
		and not roll_progress.inventory.has("7013")
		and not roll_progress.inventory.has("7014"),
		"group-7 random skill books add a grade-matched book and consume one")
	var full_roll := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7009": 1},
		"parameter": {"level": 7}, "monsterCapacity": 1,
		"itemCapacity": [72, 72, 72, 72, 72, 72]}
	var full_ball := Menu.use_item(full_roll, use_catalog, 7009, 0)
	assert_true(full_ball.get("code") == ItemEffect.Code.RANDOM_BALL_FULL
		and full_ball.get("message_id") == Msg.Id.ITEM_MONSTER_STORAGE_FULL
		and full_roll.monsters.size() == 1
		and int(full_roll.inventory["7009"]) == 1,
		"a full monster bag reports 22 with msg 498 and keeps the ball")
	# 宿主回放：同一种子的随机球必须生成同一只怪，菜单提交的快照才能逐字段对账。
	var replay_seed := 424242
	var replay_source := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0],
			"nickname": 0, "hp": 5, "sp": 5}], "partyOrder": [0],
		"inventory": {"7009": 1}, "parameter": {"level": 3}, "monsterCapacity": 20,
		"itemCapacity": [0, 0, 0, 0, 0, 0]}
	var direct := replay_source.duplicate(true)
	Menu.use_item(direct, use_catalog, 7009, 0, replay_seed)
	var replayed := Menu.replay_operation(replay_source, use_catalog,
		{"kind": "use", "item_id": 7009, "member": 0, "seed": replay_seed})
	assert_true(replayed.get("ok", false) and replayed.progress == direct
		and replayed.progress.monsters.size() == 2,
		"replay_operation regenerates the same random ball from the carried seed")
	var full_book := {"monsters": [{"nativeArguments": [49, 5, 0, -1, 0], "nickname": 0,
			"hp": 5, "sp": 5}], "partyOrder": [0], "inventory": {"7013": 1},
		"parameter": {"level": 7}, "monsterCapacity": 20,
		"itemCapacity": [0, 0, 0, 0, 0, 0]}
	var no_room := Menu.use_item(full_book, use_catalog, 7013, 0)
	assert_true(no_room.get("code") == ItemEffect.Code.RANDOM_BOOK_FULL
		and no_room.get("message_id") == Msg.Id.ITEM_SKILL_BOOK_STORAGE_FULL
		and not full_book.inventory.has("4000")
		and int(full_book.inventory["7013"]) == 1,
		"a full book bag reports 24 with msg 499 and keeps the used book")
	assert_true(Menu.item_use_supported({"id": 7009, "type": 7, "index": 9})
		and Menu.item_use_supported({"id": 7014, "type": 7, "index": 14})
		and Menu.item_use_supported({"id": 7021, "type": 7, "index": 21})
		and Menu.item_use_supported({"id": 7016, "type": 7, "index": 16})
		and Menu.item_use_supported({"id": 7017, "type": 7, "index": 17})
		and not Menu.item_use_supported({"id": 7019, "type": 7, "index": 19}),
		"supports() admits every native use branch; 19 has no 使用 action")

func test_legacy_suite() -> void:
	_run()
