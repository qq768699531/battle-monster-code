extends "res://tests/unit/gut_case.gd"

const ItemEffect = preload("res://game/battle/combat/item_effect/item_effect.gd")
const ItemKind = preload("res://game/menu/item/item_kind/item_kind.gd")
const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")


func _item(group: int, index: int) -> Dictionary:
	return {"id": ItemKind.id_of(group, index), "type": group, "index": index,
		"quantity": 1, "name": "测试"}


## `Menu_Item_SetMenuList@0x4A49C`：第 7 组 9–18 的第二层状态号是 5（直用），其余是 9（选精灵）。
func test_needs_target_follows_the_native_menu_list() -> void:
	assert_false(ItemEffect.needs_target(_item(ItemKind.Kind.GROUP_7, 9)), "随机球直用")
	assert_false(ItemEffect.needs_target(_item(ItemKind.Kind.GROUP_7, 13)), "随机书直用")
	assert_false(ItemEffect.needs_target(_item(ItemKind.Kind.GROUP_7, 18)), "经验加成直用")
	assert_true(ItemEffect.needs_target(_item(ItemKind.Kind.GROUP_7, 3)), "脑力上限要选精灵")
	assert_true(ItemEffect.needs_target(_item(ItemKind.Kind.GROUP_7, 21)), "清被动要选精灵")
	assert_true(ItemEffect.needs_target(_item(ItemKind.Kind.CONSUMABLE, 1)), "第 1 组都要选精灵")


## 无目标直用：`Ball_stdUse:123-127` 的守卫只在传了目标时才查「对象倒下」。
## 第 7 组 17（不可用类）正好能区分两支：有目标且 hp=0 → TARGET_DOWN；没目标 → FAILED 且不消耗。
func test_direct_use_skips_the_target_down_guard() -> void:
	var item := _item(ItemKind.Kind.GROUP_7, 17)
	var targeted: Dictionary = ItemEffect.apply({"hp": 0}, item)
	assert_eq(int(targeted.get("code", -1)), ItemEffect.Code.TARGET_DOWN,
		"传了目标且它倒着 → 目标倒下")
	var direct: Dictionary = ItemEffect.apply({}, item)
	assert_true(int(direct.get("code", ItemEffect.Code.TARGET_DOWN)) != ItemEffect.Code.TARGET_DOWN,
		"不传目标就不查倒下")
	assert_false(bool(direct.get("consumed", true)), "不可用类不消耗")
	# 第 7 组 18（经验加成）也是直用：没有精灵也要能生效并扣掉一件。
	var bonus := _item(ItemKind.Kind.GROUP_7, 18)
	bonus["parameter"] = {"moneyBalance": 0}
	var used: Dictionary = ItemEffect.apply({}, bonus)
	assert_true(bool(used.get("ok", false)) and bool(used.get("consumed", false)),
		"经验加成无目标也能用并消耗：%s" % str(used))

## 野外 `_menu_progress_changed` 会按 `last_progress_operation` 把同一操作在活存档上重放一次，
## 结果必须与提交快照逐字段相等；随机球／随机书这种结果由种子决定，所以直用必须把种子记进操作。
func test_direct_use_replays_identically() -> void:
	var catalog: GameplayData = AssetCatalog.load_gameplay_catalog()
	for index in [9, 13]:
		var item_id: int = ItemKind.id_of(ItemKind.Kind.GROUP_7, index)
		var live := {"inventory": {str(item_id): 1}, "monsters": [], "monsterCapacity": 24,
			"itemCapacity": [99, 99, 99, 99, 99], "parameter": {"moneyBalance": 0},
			"quests": {"slots": []}}
		var seed := 424242
		var snapshot: Dictionary = live.duplicate(true)
		assert_true(bool(Menu.use_item(snapshot, catalog, item_id, -1, seed).get("ok", false)),
			"第 7 组 %d 无目标可用" % index)
		var replay := Menu.replay_operation(live, catalog, {"kind": "use", "item_id": item_id,
			"member": -1, "seed": seed})
		assert_true(bool(replay.get("ok", false)), "重放认得无目标 use")
		assert_eq(replay["progress"], snapshot, "同种子重放结果与提交快照逐字段相等")