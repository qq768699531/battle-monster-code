extends "res://tests/unit/gut_case.gd"

## 原生 `Field_Inn_mKeyPressed`：光标 0（是）且 `money_balance > 0x31` 时
## `Ball_stdHP／Ball_stdSP(party_monsters[0..2], 100)` + `Param_moneySET(-50)`，否则只写
## fxt 79（`n79` 的默认值）；两种情况都 `Field_Warp1_mKeyPressed(-16)` 关窗。

const InnScene = preload("res://game/field/shops/inn/inn.tscn")
const Inn = preload("res://game/field/shops/inn/inn.gd")
const Layout = preload("res://prime/layout/layout.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")
const Story = preload("res://engine/data/story/story.gd")
const Battle = preload("res://battle/combat/battle.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")

class Provider extends RefCounted:
	var gameplay: GameplayData = Fixtures.battle_catalog()

	func _resource(payload: Dictionary) -> Resource:
		var resource := Resource.new()
		resource.set_meta("payload", payload)
		return resource

	func load_map(_id: int) -> Resource:
		return _resource({"id": 0,
			"info": {"name_text": "起点地图", "npcs": [], "monster_spawns": []}})

	func load_event(_id: int) -> Resource:
		return _resource({"records": [{"opcode": 0, "params": [0, 0, 0, 0, 0]}]})

	func load_dialogue(_id: String) -> Resource:
		return _resource({})

	func load_gameplay() -> GameplayData:
		return gameplay


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


## 三名出战队员都是 hp = 1／sp = 0，方便区分「回满」与「没动」。
func _story(money: int) -> RefCounted:
	var state := Story.initial_progress(0, 2)
	state["parameter"]["moneyBalance"] = money
	var monsters: Array = []
	for species: int in [49, 62, 86]:
		monsters.append({"species": species, "level": 10,
			"nativeArguments": [species, 10, 0, -1, 0], "nickname": 0, "experience": 0,
			"hp": 1, "sp": 0})
	state["monsters"] = monsters
	state["partyOrder"] = [0, 1, 2]
	var story = Story.new(Provider.new(), state, func(_limit: int) -> int: return 0)
	story.initialize()
	return story


func _open(money: int) -> Array:
	var story := _story(money)
	var page: Control = InnScene.instantiate()
	get_tree().root.add_child(page)
	page.present(get_node("/root/AssetCatalog"), story)
	await _settle(page)
	return [page, story]


func _full(species: int) -> Dictionary:
	return Battle.make_ball(Fixtures.battle_catalog(),
		[species, 10, -1, 0, 0, 0, 0, 0, -1, -1], 0)


func test_legacy_suite() -> void:
	var poor: Array = await _open(49)
	var page: Control = poor[0]
	var story: RefCounted = poor[1]
	var assets: Node = get_node("/root/AssetCatalog")
	var prompt: String = assets.text_message(Msg.SOURCE, Msg.Id.INN_PROMPT)
	var lines := Layout.wrap_text(prompt, Inn.TEXT_WIDTH, Layout.UI_FONT)
	assert_eq(Rect2i(page.get_node("Bounds").get_rect()),
		Layout.box4_window_frame(ConfirmLayout.select_size(Inn.WIDTH, lines.size())),
		"Menu_win_Box2_DrawSelect 用 13 × 折行数 + 33 + 11 定高，两行 fxt 90 提示在 400×240 里居中")
	# 折行只按可见正文量宽度：颜色标记零宽（原生 `JC_fntGetSPACE` 量宽时同样跳过控制码），
	# 否则带标记的正文会把窗高算多一行。
	assert_eq(Layout.wrap_text("[color=#FFFFFF]" + prompt + "[/color]",
			Inn.TEXT_WIDTH, Layout.UI_FONT).size(), lines.size(),
		"颜色标记不计入折行宽度")
	page.handle_key("Enter")
	assert_true(int(story.progress["parameter"]["moneyBalance"]) == 49 and
		int(story.progress["monsters"][0]["hp"]) == 1 and
		int(story.progress["monsters"][0]["sp"]) == 0,
		"money 49 fails the native > 0x31 test: no heal and no 50-coin charge")
	page.queue_free()

	var rich: Array = await _open(120)
	page = rich[0]
	story = rich[1]
	page.handle_key("Enter")
	var healed := true
	for index in range(3):
		var member: Dictionary = story.progress["monsters"][index]
		var ball := _full(int(member["species"]))
		healed = healed and int(member["hp"]) == int(ball.max_hp) and \
			int(member["sp"]) == int(ball.max_sp)
	assert_true(int(story.progress["parameter"]["moneyBalance"]) == 70 and healed,
		"confirming with 120 coins charges INN_COST and refills the three party monsters")
	watch_signals(page)
	page.handle_key("Escape")
	await _settle(page)
	assert_signal_emitted(page, "closed", "CLR closes the inn page and reports it")
	page.queue_free()
