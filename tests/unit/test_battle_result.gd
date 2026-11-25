extends "res://tests/unit/gut_case.gd"

## 战斗结算（`Battle_Win`）的掉落列表滚动：原生 `Battle_Win_mKeyPressed` 子状态 2 用
## 上／下（−1／−2）改 `BattleData.transition_parameter_bits`，三行可视、共 `items − 3`
## 个滚动位；左右键不参与。

const ResultScene = preload("res://game/battle/presentation/result/result.tscn")


class StubCatalog:
	func item(_id: int) -> ItemDefinition:
		return null


class StubPresentation:
	var catalog := StubCatalog.new()

	func item_texture(_row: Dictionary) -> Texture2D:
		return null


class StubSettlement:
	var items: Array = []
	var rows: Array = []

	func shown_money() -> int:
		return 0


func test_drop_list_scrolls_with_up_down() -> void:
	var result: Control = ResultScene.instantiate()
	get_tree().root.add_child(result)
	await get_tree().process_frame
	var model := StubSettlement.new()
	model.items = [{"id": 0, "count": 1}, {"id": 0, "count": 1}, {"id": 0, "count": 1},
		{"id": 0, "count": 1}, {"id": 0, "count": 1}]
	result.settlement = model
	result._presentation = StubPresentation.new()
	result.stage = "items"
	result.handle_key("ArrowDown")
	assert_eq(int(result.scroll), 1, "下键滚一行")
	result.handle_key("ArrowRight")
	assert_eq(int(result.scroll), 1, "左右键不滚（原生只认上下）")
	result.handle_key("ArrowDown")
	result.handle_key("ArrowDown")
	assert_eq(int(result.scroll), 2, "底部夹住（items − 3）")
	result.handle_key("ArrowDown")
	assert_eq(int(result.scroll), 2, "到底后不越界")
	result.handle_key("ArrowUp")
	assert_eq(int(result.scroll), 1, "上键回滚一行")
	result.handle_key("ArrowUp")
	result.handle_key("ArrowUp")
	assert_eq(int(result.scroll), 0, "顶部夹住")
	result.handle_key("ArrowUp")
	assert_eq(int(result.scroll), 0, "到顶后不越界")
