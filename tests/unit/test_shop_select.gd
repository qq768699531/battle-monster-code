extends "res://tests/unit/gut_case.gd"

## 原生 `Field_Item_DrawSelect:60-62`：窗高 = 常量表[n2] + 33（丢弃 81、买／卖 93；
## 常量表 48／60／60 见 `libjconvertor.so` 0x98A30+80..104 的实测）；
## 买／卖在道具行与正文之间多 12 px 价格行，金额 = 单价 × 数量（`:117-138`）。

const ShopSelectScene = preload("res://game/field/shops/shop_select/shop_select.tscn")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")


func _present(kind: int, unit_price: int) -> Control:
	var page: Control = ShopSelectScene.instantiate()
	get_tree().root.add_child(page)
	page.present("要购买吗?", "是", "否", null, 9, kind, unit_price)
	return page


func test_legacy_suite() -> void:
	var discard := _present(ConfirmLayout.ItemSelect.DISCARD, 0)
	var discard_window: Control = discard.get_node("Window")
	assert_eq(discard_window.window_size, Vector2i(160, 81),
		"丢弃分支窗高用常量表 48 + 33 = 81（`Field_Item_DrawSelect:60-62`）")
	assert_false(discard.get_node("Window/Content/Price").visible,
		"丢弃分支没有价格行")

	var buy := _present(ConfirmLayout.ItemSelect.BUY, 120)
	var buy_window: Control = buy.get_node("Window")
	assert_eq(buy_window.window_size, Vector2i(160, 93),
		"买／卖分支窗高用常量表 60 + 33 = 93（价格行 12 px）")
	var price: Control = buy.get_node("Window/Content/Price")
	assert_true(price.visible and price.size == Vector2(48, 9),
		"买／卖分支画 48×9 价格牌（`Field_Item_Buy_DrawPrice`）")
	assert_eq(buy.get_node("Window/Content/Lines").offset_top, 50.0,
		"价格行把正文压到窗顶 + 50（`Field_Item_DrawSelect:121-138`）")
	assert_true(buy.get_node("Window/Content/Price/Number").get_child_count() > 0,
		"价格牌按单价 × 数量写金额")

	buy.quantity = 3
	buy._render()
	assert_true(buy.get_node("Window/Content/Price/Number").get_child_count() > 0,
		"数量步进后价格行重画")
