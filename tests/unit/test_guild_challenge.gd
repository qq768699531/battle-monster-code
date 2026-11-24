extends "res://tests/unit/gut_case.gd"

## `Field_Guild_Challenge_*`（状态 7）与 `Game_Guild_Battle_init` 的关键路径。

const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const GuildBattle = preload("res://game/field/guild/guild_battle/guild_battle.gd")
const ItemKind = preload("res://game/menu/item/item_kind/item_kind.gd")
const GuildChallengeScene = preload("res://game/field/guild/guild_challenge/guild_challenge.tscn")
const WindowTransitionScript = preload("res://engine/ui/window_transition/window_transition.gd")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")

## 组 39 是 `wiki\data-format\dat-item-guild.md` 记录的 `evt0001` 那一组；`组号 = 99 − code % 1000` ⇒ code 60。
const GROUP := 39
const CODE := 60


## 一条 `type = 28` 的 `item_guild.dat` 组：三条 × 5 槽（物种、觉醒、被动、被动等级、装备+1），
## 首记录名是三条共用的等级参数 12。
func _catalog() -> GameplayData:
	var catalog: GameplayData = Fixtures.battle_catalog()
	catalog.items.append(Fixtures.item({
		"id": ItemKind.id_of(28, GROUP), "type": 28, "index": GROUP, "name_record": "12",
		"detail_slots": [49, 0, 0, 0, 0, 62, 1, 0, 0, 0, 86, 0, 0, 0, 0],
	}))
	return catalog


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if not page.get_node("Window").is_transitioning() and \
				not page.get_node("Confirm").is_transitioning():
			return


func test_legacy_suite() -> void:
	var catalog := _catalog()
	var resolution := GuildBattle.enemy_constructors(catalog, CODE)
	assert_eq(resolution.get("constructors"), [
		[49, 12, -1, 0, 0, 0, 0, 0, -1, -1],
		[62, 12, -1, 0, 0, 1, 0, 0, -1, -1],
		[86, 12, -1, 0, 0, 0, 0, 0, -1, -1]],
		"Game_Guild_Battle_init 按 99 − code%1000 取 item_guild.dat 的组，三条依次填对手")

	var assets := get_node("/root/AssetCatalog")
	var page: Control = GuildChallengeScene.instantiate()
	get_tree().root.add_child(page)
	var started: Array = []
	page.started.connect(func(rows: Array) -> void: started.append(rows))
	page.present(assets, catalog, CODE)
	await _settle(page)

	# bm-P2-249：确认框直接用共用组件的 Box2 框体，页面不再往 `Confirm/Bounds` 加覆盖节点。
	var confirm: Control = page.get_node("Confirm")
	assert_eq(confirm.kind, WindowTransitionScript.BoxKind.BOX2,
		"the confirm box draws the shared Box2 frame")
	assert_true(confirm.get_node("Bounds/Box2").visible
		and not confirm.get_node("Bounds/Header").visible
		and not confirm.get_node("Bounds").has_node("Fill"),
		"Box2 comes from the component, with no page-level chrome override")
	assert_eq(confirm.window_size, ConfirmLayout.select_size(160, 1),
		"确认框窗高按 msg 59 的折行数由 ConfirmLayout 算出，场景不再写死 160×57")

	page.handle_key("Enter")
	await _settle(page)
	var default_choice: int = page.choice
	page.handle_key("Enter")
	var emitted_by_no := started.size()
	await _settle(page)
	page.handle_key("Enter")
	await _settle(page)
	page.handle_key("ArrowLeft")
	page.handle_key("Enter")
	assert_true(default_choice == 1 and emitted_by_no == 0 and started.size() == 1,
		"确认框默认停在「否」；停在「否」时不发信号，切到「是」才发 started")

	var progress := {"guildCode": 42}
	var challenge: Dictionary = GuildBattle.apply_win(progress, GuildBattle.KIND_CHALLENGE)
	var event: Dictionary = GuildBattle.apply_win(progress, GuildBattle.KIND_EVENT)
	assert_true(challenge.ok and progress.guildCode == 41 and event.code == 41 and not event.changed,
		"Battle_Win_mRun 只对 kind 3 把公会码 −1；kind 4（事件公会战）不动")
