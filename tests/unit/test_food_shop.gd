extends "res://tests/unit/gut_case.gd"

## 原生 `Field_Item_Food_*`：选食谱 → 扣三种材料 + 100 钱 → 产品 +1。
## 覆盖 `Field_Item_Food_Proc` 的成功/缺钱/缺材料三条路径，以及 12 条 `item_food.dat` 食谱。

const FoodShopScene = preload("res://game/field/shops/food_shop/food_shop.tscn")
const Msg = preload("res://engine/ui/msg/msg.gd")


class FakeStory extends RefCounted:
	var progress: Dictionary

	func _init(money: int, inventory: Dictionary) -> void:
		progress = {"parameter": {"moneyBalance": money}, "inventory": inventory.duplicate()}

	func _add_inventory_item(item_id: int, quantity: int, _blocking := true, _announce := true) -> bool:
		var key := str(item_id)
		progress.inventory[key] = int(progress.inventory.get(key, 0)) + quantity
		return true

	func consume_item(item_id: int, quantity: int) -> bool:
		var key := str(item_id)
		progress.inventory[key] = int(progress.inventory.get(key, 0)) - quantity
		return true


func _page(money: int, inventory: Dictionary) -> Control:
	var page: Control = FoodShopScene.instantiate()
	get_tree().root.add_child(page)
	page.call("present", FakeStory.new(money, inventory), get_node("/root/AssetCatalog"))
	return page


func test_recipes_and_craft() -> void:
	var page := _page(1000, {"3024": 10, "3012": 10, "3018": 10})
	assert_eq(page.call("entry_count"), 12, "item_food.dat 有 12 条可制作食谱")
	assert_eq(page.call("selected_id"), 1025, "列表首项是产品 1025")
	var materials: Array = page._entries[0].materials
	assert_eq(materials, [{"id": 3024, "count": 3}, {"id": 3012, "count": 4},
		{"id": 3018, "count": 2}], "首条食谱的三种材料与 DAT 一致")
	assert_eq(page.call("craft"), -1, "材料/金钱足够时制作成功")
	assert_eq(page.notice_id, -1, "成功不弹失败提示")
	var story: FakeStory = page._story
	assert_eq(story.progress.inventory.get("1025", 0), 1, "产品 +1 入包")
	assert_eq(story.progress.parameter.moneyBalance, 900, "扣除固定 100 钱")
	assert_eq(story.progress.inventory.get("3024", 0), 7, "材料 3024 −3")
	assert_eq(story.progress.inventory.get("3012", 0), 6, "材料 3012 −4")
	assert_eq(story.progress.inventory.get("3018", 0), 8, "材料 3018 −2")


func test_missing_money() -> void:
	var page := _page(50, {"3024": 10, "3012": 10, "3018": 10})
	assert_eq(page.call("craft"), Msg.Id.SHOP_NOT_ENOUGH_MONEY, "金钱 ≤ 99 时拒绝")
	var story: FakeStory = page._story
	assert_eq(story.progress.parameter.moneyBalance, 50)
	assert_false(story.progress.inventory.has("1025"), "失败不产出产品")


func test_missing_materials() -> void:
	var page := _page(1000, {"3024": 10})
	assert_eq(page.call("craft"), Msg.Id.FOOD_CRAFT_NO_MATERIAL, "材料不足时拒绝")
	var story: FakeStory = page._story
	assert_eq(story.progress.parameter.moneyBalance, 1000, "失败不扣钱")
	assert_false(story.progress.inventory.has("1025"), "失败不产出产品")
