extends "res://tests/unit/gut_case.gd"

const FoodShopScene = preload("res://game/field/shops/food_shop/food_shop.tscn")
const Story = preload("res://engine/data/story/story.gd")
const SlotFrame = preload("res://menu/slot_frame/slot_frame.gd")


class CatalogProvider extends RefCounted:
	var catalog: GameplayData
	var maps: Dictionary = {
		0: {"id": 0, "info": {"name_text": "起点地图", "npcs": [], "monster_spawns": []}},
	}

	func _payload(value: Dictionary) -> Resource:
		var resource := Resource.new()
		resource.set_meta("payload", value)
		return resource

	func load_map(id: int) -> Resource:
		return _payload(maps.get(id, {}))

	func load_event(_id: int) -> Resource:
		return _payload({})

	func load_dialogue(_id: String) -> Resource:
		return _payload({"groups": []})

	func load_gameplay() -> GameplayData:
		return catalog


func _story(catalog: GameplayData, money: int, inventory: Dictionary) -> RefCounted:
	var provider := CatalogProvider.new()
	provider.catalog = catalog
	var story = Story.new(provider, Story.initial_progress(0),
		func(_limit: int) -> int: return 0)
	story.progress["parameter"]["moneyBalance"] = money
	story.progress["inventory"] = inventory
	return story


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")
	var catalog: GameplayData = assets.load_gameplay_catalog()
	# 首条食谱是 `item_food.dat` 25 组（材料 24×3／12×4／18×2），产品是 basic 第 1 组 25 号。
	var story := _story(catalog, 1000,
		{"3024": 3, "3012": 4, "3018": 2})
	var page: Control = FoodShopScene.instantiate()
	get_tree().root.add_child(page)
	page.present(story, assets)
	await _settle(page)

	# ① 格底走 `SlotFrame` 公式：12 条食谱都有内容，光标格用帧 1、其余用帧 0。
	assert_eq([page.get_node("Content/Cell0/Frame").texture,
		page.get_node("Content/Cell1/Frame").texture],
		[page.cell_frames[SlotFrame.Frame.IN_RANGE_FOCUSED],
			page.cell_frames[SlotFrame.Frame.IN_RANGE]],
		"Menu_Item_DrawItem 的格底公式：光标格帧 1、其余有内容的格帧 0")

	# ② `Field_Item_Food_init` 只列有食谱的 12 组（25–36），标题为 `msg 78`，
	# 条底的选中名走 `Menu_Item_DrawListInfo`（产品名来自 basic 第 1 组）。
	assert_eq([page.entry_count(), page.get_node("Bounds/Title").text,
		page.get_node("Content/Name").text],
		[12, assets.text_message(Msg.SOURCE, Msg.Id.FOOD_CRAFT_TITLE),
			assets.text_message("common/item_basic.dat", "item_basic.group.1.entry.25.name")],
		"列表就是 item_food.dat 里带食谱的 12 组，首条是 25 组对应的产品")

	# ② `Field_Item_Food_Proc` 成功分支：产品 +1 入包、`Param_moneySET(-100)`、
	# 三个材料槽按件数扣除；原生成功时不弹任何消息。
	var crafted: int = page.craft()
	var inventory: Dictionary = story.progress["inventory"]
	assert_true(crafted == -1 and page.money() == 900 and
		int(inventory.get("1025", 0)) == 1 and not inventory.has("3024") and
		not inventory.has("3012") and not inventory.has("3018"),
		"制作一次：产品 1025 入包 1 个、100 金币扣除、三种材料按件数扣光，且没有提示")

	# ③ `Field_Item_Food_mKeyPressed` 先拦钱（≤ 99 → msg 79），
	# `Field_Item_Food_Proc` 的 LABEL_7 再拦材料（msg 88）；两个分支都不扣料也不扣钱。
	story.progress["parameter"]["moneyBalance"] = 99
	var no_money: int = page.craft()
	story.progress["parameter"]["moneyBalance"] = 900
	var no_material: int = page.craft()
	assert_true(no_money == Msg.Id.SHOP_NOT_ENOUGH_MONEY and
		no_material == Msg.Id.FOOD_CRAFT_NO_MATERIAL and page.money() == 900 and
		int(inventory.get("1025", 0)) == 1,
		"钱不够给 msg 79、材料不够给 msg 88，两者都不改背包与金钱")

	# ④ 食谱来自 `assets/food-recipes.tres`（`FoodRecipes`，`script\export_food_recipes.py` 从
	# `item_food.dat` 原字节导出），不再有脚本常量。
	var recipes: FoodRecipes = load("res://game/field/shops/food_shop/food-recipes.tres")
	var materials: Array = recipes.get_recipe(1025).get("materials", [])
	assert_true(recipes != null and recipes.size() == 12 and materials.size() == 3 and
		int(materials[0].id) == 3024 and int(materials[0].count) == 3 and
		int(materials[2].id) == 3018 and int(materials[2].count) == 2,
		"食谱资源是 12 条，1025 号产品的三个材料与 item_food.dat 一致")
	page.queue_free()
