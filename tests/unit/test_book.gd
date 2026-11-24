extends "res://tests/unit/gut_case.gd"

const Book = preload("res://menu/book_model/book_model.gd")
const BookScene = preload("res://menu/book/book.tscn")
const MonsterScene = preload("res://menu/book_monster/book_monster.tscn")
const Story = preload("res://core/story/story.gd")
const Battle = preload("res://battle/combat/battle.gd")
const ItemKind = preload("res://menu/item_kind/item_kind.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")

## 刺球兽（49）：原生 1 级无成长个体的截图数值是 ATK 82 / HP 378 / SPD 100。
const MONSTER := {"id": 49, "kind": 0, "attribute_group": 3, "attribute_entry": 1,
	"ability_inputs": [14, 13, 12, 11, 17, 16],
	"attribute_inputs": [16, 4, 22, 2, 11, 2], "prime_portrait_position": 1132}
const SKILL_BOOK := {"id": 4136, "type": 4, "index": 136, "icon": 74, "grade_index": 2}


class FixtureProvider extends RefCounted:
	var events: Dictionary = {}
	var gameplay: GameplayData

	func _resource(payload: Dictionary) -> Resource:
		var resource := Resource.new()
		resource.set_meta("payload", payload)
		return resource

	func load_map(_id: int) -> Resource:
		return _resource({"id": 0, "info": {"name_text": "起点地图", "npcs": [], "monster_spawns": []}})

	func load_event(id: int) -> Resource:
		return _resource(events.get(id, {}))

	func load_dialogue(_id: String) -> Resource:
		return _resource({})

	func load_gameplay() -> GameplayData:
		return gameplay


func _record(opcode: int, params: Array = [0, 0, 0, 0, 0]) -> Dictionary:
	return {"opcode": opcode, "params": params}


func _catalog() -> GameplayData:
	return Fixtures.data({"monsters": [MONSTER], "items": [SKILL_BOOK],
		"passives": [{"id": 136, "base": 1, "effect": 0, "increment": 1}]})


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


func _visible_glyphs(box: Node) -> int:
	var count := 0
	for glyph in box.get_children():
		if glyph.visible:
			count += 1
	return count


## `monster_animation` 把 ANI 场景挂在 `Content` 下，播放器是该场景的 `AnimationPlayer`。
func _cell_player(monster: Node2D) -> AnimationPlayer:
	return monster.get_node("Content").get_child(0).get_node("AnimationPlayer")


func _open_monster_page(assets: Node, catalog: GameplayData, progress: Dictionary,
		knowledge: Dictionary = {}) -> Control:
	var view: Control = BookScene.instantiate()
	get_tree().root.add_child(view)
	view.open(assets, catalog, progress, knowledge)
	await _settle(view.get_node("BookList"))
	view.press("Enter")
	await _settle(view.get_node("BookMonster"))
	return view


## 状态 16（初始精灵选择）与图鉴同一张页：`Game_Book_Monster_init:12-35` 只把所选流派的
## 第 4…8 格标成可选，`Menu_mon_DrawBookList` 的页签／6×2 格／滚动条／详情照常画。
func test_starter_selection_page() -> void:
	var assets := get_node("/root/AssetCatalog")
	var catalog: GameplayData = assets.load_gameplay_catalog()
	var page: Control = MonsterScene.instantiate()
	add_child_autofree(page)
	# 流派 0 的五只候选 = `22 × 0 + 4 … + 8`（`Game_Book_Monster_init:18-26`）。
	var starters: Array[int] = [4, 5, 6, 7, 8]
	page.present_starter(assets, catalog, 0, starters)
	await _settle(page)
	assert_eq(Rect2i(page.get_node("Bounds").get_rect()), Rect2i(86, 0, 228, 240),
		"状态 16 与图鉴同一个 228×240 窗（Menu_mon_DrawBookList:46）")
	assert_true(page.get_node("Content/Scroll").visible and
		(page.get_node("Content/Cell0") as Control).position == Vector2(97, 57),
		"6×2 格从 (97,57) 起步距 32、右侧滚动条按 22 条记录占两页（:121-123 与 :217）")
	assert_true(page.get_node("Content/Cell4/Clip/Monster").visible and
		not page.get_node("Content/Cell0/Clip/Monster").visible,
		"只有第 4…8 格有精灵，其余格是 Param_bookIsMonster = 0 的空白格（:148-149）")
	# 光标从第 1 格开始（`Game_Book_Monster_Load` 把 transition+0 清零）：不可选的格 OK 不开框。
	page.handle_key("Enter")
	assert_false(page.get_node("Confirm").visible,
		"OK 只在 Param_bookIsMonster = 1 的格上开确认框（Game_Book_Monster_mKeyPressed:150-159）")
	for _step in range(4):
		page.handle_key("ArrowRight")
	assert_eq(page.starter_choice(), 0, "光标移到第 5 格就是第一只候选（22 × 流派 + 4）")
	page.handle_key("Enter")
	await get_tree().process_frame
	var species_name := str(assets.text_messages("common/item_mon.dat")
		.get("item_mon.group.4.name", ""))
	assert_true(page.get_node("Confirm").visible and not species_name.is_empty() and
		(page.get_node("Confirm/Content/Prompt") as Control).text.contains(species_name),
		"确认框正文是 fxt 101「[%s]确定吗?」套物种名（Game_Book_Monster_mPaint:33-38）")
	# CLR 回状态 15（`:128-132`）：二级页不发新效果，只把页面交回宿主。
	page.present_starter(assets, catalog, 0, starters)
	await _settle(page)
	watch_signals(page)
	page.handle_key("Escape")
	assert_signal_emitted(page, "back_requested",
		"CLR 回一级：GameCanvas_SetNext(CHARACTER_SELECT_15, preferred_mastery_index)")


func test_legacy_suite() -> void:
	assert_eq(Book.step_monster_cursor(0, -1), 23,
		"the native monster cursor wraps over 24 slots, not the 22 recorded ones")
	assert_eq(Book.monster_scroll(23, 0), 12,
		"JC_knlSTART keeps the last row visible by scrolling to the third page")
	var ball := Book.native_ball(_catalog(), 49)
	assert_true(Battle.effective_stat(ball, 0) == 82 and ball.max_hp == 378 and
		int(ball.speed) == 100,
		"the dex shows the level-1 individual the native Ball_stdSet builds")

	var progress := Story.initial_progress(0)
	var provider := FixtureProvider.new()
	provider.gameplay = _catalog()
	provider.events[0] = {"records": [_record(0), _record(31, [49, 1, 0, 0, 0]),
		_record(17, [4136, 1, 0, 0, 0])]}
	var story = Story.new(provider, progress, func(_limit: int) -> int: return 0)
	story.initialize()
	assert_true(story.progress["book"][Book.BOOK_MONSTERS] == [49] and
		story.progress["book"][Book.BOOK_SKILLS] == [136],
		"Ball_stdAdd and Item_stdAdd record the obtained monster and skill book")
	var unordered := progress.duplicate(true)
	unordered["book"][Book.BOOK_SKILLS] = [12, 3]
	assert_false(Story.validate_progress(unordered, 0),
		"an unsorted dex record is rejected as a corrupt save")

	# 老存档／直接写 `monsters`、`inventory` 的路径：进图前用当前持有补齐获得记录。
	var owned := Story.initial_progress(0)
	owned["monsters"] = [{"species": 62, "level": 1, "nativeArguments": [62, 1, 0, 0, -1]}]
	owned["inventory"] = {"4137": 1}
	var owned_story = Story.new(provider, owned, func(_limit: int) -> int: return 0)
	owned_story.initialize()
	assert_true(Book.is_discovered(owned_story.progress, Book.BOOK_MONSTERS, 62) and
		Book.is_discovered(owned_story.progress, Book.BOOK_SKILLS, 137),
		"owned monsters and held skill books are folded into the dex record on load")

	# 知识表可整体替换：页面只认传进来的表，存档不被改写。
	var scratch := Story.initial_progress(0)
	assert_true(Book.set_records(scratch,
		{Book.BOOK_MONSTERS: [5, 5, 3], Book.BOOK_SKILLS: []}) and
		scratch["book"][Book.BOOK_MONSTERS] == [3, 5],
		"an injected record is deduplicated and sorted before it is stored")
	assert_false(Book.set_records(scratch, {Book.BOOK_MONSTERS: [0, 999],
		Book.BOOK_SKILLS: []}),
		"an out-of-range dex id is rejected instead of being clamped")
	var assets := get_node("/root/AssetCatalog")
	var catalog: GameplayData = assets.load_gameplay_catalog()
	var closed_dex: Control = await _open_monster_page(assets, catalog, Story.initial_progress(0))
	assert_false(closed_dex.get_node("BookMonster/Content/Cell0/Clip/Monster").visible,
		"a fresh save shows no monster portrait in the dex grid")
	var open_dex: Control = await _open_monster_page(assets, catalog, Story.initial_progress(0),
		Book.all_records())
	assert_true(open_dex.get_node("BookMonster/Content/Cell0/Clip/Monster").visible,
		"Book.all_records() unlocks every entry for the injected view only")
	open_dex.press("Enter")
	await _settle(open_dex.get_node("BookMonster"))
	assert_true(_cell_player(open_dex.get_node("BookMonster/Content/Cell0/Clip/Monster")).active and
		not _cell_player(open_dex.get_node("BookMonster/Content/Cell1/Clip/Monster")).active,
		"Menu_mon_DrawBookList feeds frames_since_canvas_change to the cursor cell only, " +
		"so every other recorded cell holds the first frame")

	var book: Control = BookScene.instantiate()
	get_tree().root.add_child(book)
	# 品级 2 的技能书（135）与品级 0 的技能书（136）一起放进知识表，用来对照详情名称的颜色。
	var dex_progress: Dictionary = story.progress.duplicate(true)
	dex_progress["book"][Book.BOOK_SKILLS] = [135, 136]
	book.open(assets, assets.load_gameplay_catalog(), dex_progress)
	await _settle(book.get_node("BookList"))
	assert_eq(Rect2i(book.get_node("BookList/Bounds").get_rect()), Rect2i(86, 16, 228, 208),
		"Menu_win_Box4_DrawWindow centers the 228x208 dex menu at (86, 16)")
	book.press("Enter")
	await _settle(book.get_node("BookMonster"))
	var monster_page := book.get_node("BookMonster")
	assert_eq(Rect2i(monster_page.get_node("Bounds").get_rect()), Rect2i(86, 0, 228, 240),
		"the monster dex is the full 228x240 window")
	book.press("ArrowRight")
	book.press("ArrowRight")
	book.press("ArrowDown")
	for _step in range(5):
		book.press("ArrowRight")
	assert_eq(monster_page.get_node("Content/Detail/Name").text, "刺球兽",
		"the detail panel names the monster under the cursor")
	assert_eq(monster_page.get_node("Content/Cell6/Frame").texture.region, Rect2(0, 0, 30, 30),
		"a recorded but undiscovered slot keeps the plain cell frame, not the X padding")
	assert_eq(monster_page.get_node("Content/Cell0/Frame").texture.region, Rect2(0, 0, 30, 30),
		"the found slot uses the plain frame until the cursor enters the grid")
	var graded: ShaderMaterial = monster_page.get_node("Content/Cell5/Frame").material
	assert_true(bool(graded.get_shader_parameter("grade_enabled")) and
		graded.get_shader_parameter("grade_color") == Color("#226bff"),
		"a recorded monster gets the Ball_stdGradeRGB outline for its attribute_entry")
	var cursor_frame: TextureRect = monster_page.get_node(
		"Content/Cell%d/Frame" % monster_page.cursor)
	assert_true(not cursor_frame.material.get_shader_parameter("focused") and
		not cursor_frame.get_node("Breath").is_playing(),
		"Menu_mon_DrawBookList never enables GRP_MODE_BRIGHT, so the cell frame brightness is fixed")
	assert_false(bool((monster_page.get_node("Content/Cell4/Frame").material as ShaderMaterial)
		.get_shader_parameter("grade_enabled")),
		"an undiscovered slot keeps the plain frame without a rarity outline")
	assert_eq(_visible_glyphs(monster_page.get_node("Content/Detail/Vitals/HP/Number/Glyphs")), 3,
		"Game_monDraw2 prints the current HP in the portrait corner")
	assert_eq(_visible_glyphs(monster_page.get_node("Content/Detail/Vitals/SP/Number/Glyphs")), 3,
		"the SP readout is the current/limit pair, not the limit alone")
	# `Menu_Monster_Draw3@0x575E8:98-102`：技能名走 `#PF95` 的 `#F09050`，`]#C6` 之后是白色说明。
	var long_skill := "长技能名称反复叠加直到正文宽过一百一十三像素的裁切框"
	monster_page._present_active("%s/%s" % [long_skill, long_skill])
	await get_tree().process_frame
	var marquee: Control = monster_page.get_node("Content/Detail/Skills/ActiveClip/Text")
	var second_copy: Control = monster_page.get_node("Content/Detail/Skills/ActiveClip/Repeat")
	assert_almost_eq(second_copy.position.x - marquee.position.x,
		monster_page._active_width + 10.0, 0.001,
		"the marquee's second copy stays WIDTH + 10 px right of the first instead of overlapping it")
	var glyphs: Array = marquee.get("_line").glyphs
	assert_true((glyphs[0].color as Color).is_equal_approx(Color("#f09050")) and
		(glyphs[long_skill.length() + 2].color as Color).is_equal_approx(Color.WHITE),
		"the active skill title uses the #PF95 palette color and the description stays white")
	book.press("Escape")
	book.press("Escape")
	await _settle(book.get_node("BookList"))
	book.press("ArrowDown")
	book.press("Enter")
	await _settle(book.get_node("BookSkill"))
	var skill_page := book.get_node("BookSkill")
	assert_eq(Rect2i(skill_page.get_node("Bounds").get_rect()), Rect2i(86, 6, 228, 227),
		"the odd 227 px skill window floors to y = 6 like the native integer division")
	skill_page._step(136)
	assert_eq(skill_page.get_node("Content/Detail/Name").text, "[ 混乱反射 ]",
		"the skill dex shows NO. 137 as the bracketed skill name")
	assert_eq(skill_page.get_node("Content/Detail/DescClip/Desc").text, "使混乱攻击无效并反弹",
		"the skill dex shows the native skill description below the name")
	# `Menu_skill_DrawBookList@0x55F8C:238-246`：名称前缀取 `Item_stdGradeINDEX@0x812C8` 的品级色
	# 槽（`Item_stdGradeRGB@0x81318` 品级 0..3 = #FFFFFF / #C676FB / #FCCF45 / #FF2020），说明固定 #C6。
	var detail_name: Control = skill_page.get_node("Content/Detail/Name")
	var desc_glyphs: Array = skill_page.get_node("Content/Detail/DescClip/Desc").get("_line").glyphs
	var grade_zero_color: Color = detail_name.get("_line").glyphs[0].color
	skill_page._step(-1)
	var grade_two_color: Color = detail_name.get("_line").glyphs[0].color
	assert_true(grade_zero_color.is_equal_approx(Color("#ffffff")) and
		grade_two_color.is_equal_approx(Color("#fccf45")),
		"the skill detail name takes the grade palette: grade 0 stays #C6 white, " +
		"grade 2 turns #C8 #FCCF45")
	assert_true(not desc_glyphs.is_empty() and
		(desc_glyphs[0].color as Color).is_equal_approx(Color.WHITE),
		"the skill detail description is prefixed with #C6, so it stays white at every grade")
	# `Item_datBasic` 类型 31：说明取该记录 `entry.0` 的正文，槽为空时向前退到最近的非空记录
	# （135 → 133）。分组 135 自己的说明槽是空串，详情不能跟着空。
	var skill_messages: Dictionary = assets.text_messages("common/item_skill.dat")
	var fallback_record: ItemDefinition = catalog.item(
		ItemKind.id_of(ItemKind.Kind.SKILL_BOOK, 135))
	var fallback_text := str(skill_messages.get(fallback_record.result_description_record, ""))
	var desc_label: Control = skill_page.get_node("Content/Detail/DescClip/Desc")
	assert_true(str(skill_messages.get("item_skill.group.135.entry.0.name", "")).is_empty() and
		not fallback_text.is_empty() and desc_label.text == fallback_text,
		"a skill book whose own group has an empty description slot still shows the " +
		"record's own detail text, which the export resolved to the nearest non-empty entry")
	# `Menu_skill_DrawBookList` 的横向滚动周期是 `WIDTH + 40`（怪物页那行是 `WIDTH + 10`）。
	var clip: Control = skill_page.get_node("Content/Detail/DescClip")
	skill_page._desc_width = clip.size.x + 10.0
	skill_page._desc_age = 4.0
	skill_page._process(0.0)
	var marquee_start: float = desc_label.position.x
	skill_page._desc_age = 4.0 + (clip.size.x + 50.0) / 40.0
	skill_page._process(0.0)
	assert_almost_eq(desc_label.position.x, marquee_start, 0.001,
		"the skill description marquee repeats every WIDTH + 40 px, so one period later " +
		"it sits at the same offset")
