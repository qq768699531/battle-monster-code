extends "res://tests/unit/gut_case.gd"

const ShopListScene = preload("res://game/field/shops/shop_list/shop_list.tscn")
const ShopGoodsScene = preload("res://game/field/shops/shop_goods/shop_goods.tscn")
const Shops = preload("res://game/field/shops/shop_goods/shops.tres")
const Story = preload("res://engine/data/story/story.gd")


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


func _story(catalog: GameplayData, money: int, map_id: int = 0) -> RefCounted:
	var provider := CatalogProvider.new()
	provider.catalog = catalog
	var story = Story.new(provider, Story.initial_progress(0),
		func(_limit: int) -> int: return 0)
	story.progress["parameter"]["moneyBalance"] = money
	# `Field_Item_List_init` 按 `MapData.map_id` 决定行数，所以夹具必须给出地图号。
	story.map = {"id": map_id, "info": {}}
	story.progress["mapId"] = map_id
	return story


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")
	var catalog: GameplayData = assets.load_gameplay_catalog()
	var story := _story(catalog, 1000)

	# ① 列表页：`Field_Item_List_mPaint` 按 `shop_mode_code` 取 msg 64/65 或 66/67。
	var list: Control = ShopListScene.instantiate()
	get_tree().root.add_child(list)
	list.present(story, assets, 0)
	await _settle(list)
	assert_eq([list.get_node("Content/Option0/Label").text,
		list.get_node("Content/Option1/Label").text],
		[assets.text_message(Msg.SOURCE, Msg.Id.SHOP_BUY_ITEM),
			assets.text_message(Msg.SOURCE, Msg.Id.SHOP_SELL_ITEM)],
		"shop_mode_code 0 的道具商店只有「购买道具／出售道具」两行")
	var equip: Control = ShopListScene.instantiate()
	get_tree().root.add_child(equip)
	equip.present(story, assets, 1)
	await _settle(equip)
	assert_eq([equip.get_node("Content/Option0/Label").text,
		equip.get_node("Content/Option1/Label").text],
		[assets.text_message(Msg.SOURCE, Msg.Id.SHOP_BUY_EQUIPMENT),
			assets.text_message(Msg.SOURCE, Msg.Id.SHOP_SELL_EQUIPMENT)],
		"shop_mode_code 1 的装备商店换成 msg 66/67")
	equip.queue_free()
	list.queue_free()

	# 地图 148 的道具商店有第三行「食物制作」（`msg 70`），行距按条数算成 `(208 − 36) / (3 + 1) = 43`。
	var food: Control = ShopListScene.instantiate()
	get_tree().root.add_child(food)
	food.present(_story(catalog, 1000, 148), assets, 0)
	await _settle(food)
	assert_true(food.entries.size() == 3 and
		food.get_node("Content/Option2/Label").text ==
			assets.text_message(Msg.SOURCE, Msg.Id.SHOP_FOOD) and
		int(food.get_node("Content/Option1").offset_top -
			food.get_node("Content/Option0").offset_top) == 43,
		"地图 148 的道具商店是三行，第三行是食物制作，行距 43")
	food.queue_free()

	# ② 买页：`Field_Item_Buy_mKeyPressed` 成功后 `Item_stdAddEx` + `Param_moneySET(-总价)`。
	# 货架来自 `Field_Item_Buy_SetList` 的默认分支（0x3BD10/16/1A 的八个 int32 拆成
	# 两个 int16），不是按目录自造的清单。
	assert_eq(Shops.stock(0, 3),
		[1000, 1001, 1002, 1003, 1005, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1017, 1037, 5000],
		"道具店在非 148 地图的货架就是原生的 16 个 id，顺序一致")
	var goods: Control = ShopGoodsScene.instantiate()
	get_tree().root.add_child(goods)
	goods.present(story, assets, 0, 0)
	await _settle(goods)
	var item_id: int = goods.selected_id()
	var price: int = StoryRuntime.shop_buy_price(catalog.item(item_id), 1)
	assert_eq(goods.trade(1), -1, "买得起时成交，没有拒绝记录号")
	assert_true(goods.money() == 1000 - price and
		int(story.progress["inventory"].get(str(item_id), 0)) == 1,
		"买一件后金钱减少 %d、背包 +1" % price)

	# ③ 钱不够：原生只 `Game_infoInit(fxt 79)`，金钱与背包都不动。
	story.progress["parameter"]["moneyBalance"] = 0
	assert_eq(goods.trade(1), Msg.Id.SHOP_NOT_ENOUGH_MONEY,
		"金币不足时给出 msg 79")
	assert_true(goods.money() == 0 and
		int(story.progress["inventory"].get(str(item_id), 0)) == 1,
		"拒绝分支不改金钱也不改背包")
	goods.queue_free()

	# ④ 档位切换：`Field_Item_Buy_Get` 在 97 号地图的装备店给两组（1 装备／3 书），
	# `Field_Item_Buy_mKeyPressed` 列表子状态 0 的左右键按 `(游标 ± 1) % 组数` 切档并重取货架。
	var shelf: Control = ShopGoodsScene.instantiate()
	get_tree().root.add_child(shelf)
	shelf.present(_story(catalog, 1000, 97), assets, 0, 1)
	await _settle(shelf)
	var initial := [shelf.groups(), shelf.group_code(), shelf.stock_error]
	shelf.handle_key("ArrowRight")
	assert_true(shelf.group_index == 1 and shelf.group_code() == 3 and
		shelf.stock_error != initial[2],
		"右键换到下一档（组 3）并重取了那一组的货架")
	shelf.handle_key("ArrowRight")
	assert_eq([initial[0], initial[1], shelf.group_index], [[1, 3], 1, 0],
		"再按右键按 (游标 + 1) % 2 取模回到第 0 档")
	shelf.queue_free()
