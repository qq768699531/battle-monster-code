extends "res://tests/unit/gut_case.gd"

const ItemEffect = preload("res://game/battle/combat/item_effect/item_effect.gd")
const ItemKind = preload("res://game/menu/item/item_kind/item_kind.gd")


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
