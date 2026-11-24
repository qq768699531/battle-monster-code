extends "res://tests/unit/gut_case.gd"

const GuildMenuScene = preload("res://game/field/guild/guild_menu/guild_menu.tscn")
const GuildInfoScene = preload("res://game/field/guild/guild_info/guild_info.tscn")


func _settle(page: Control) -> void:
	for _frame in range(200):
		await get_tree().process_frame
		if page.visible and not page.is_transitioning():
			return


func test_legacy_suite() -> void:
	var assets := get_node("/root/AssetCatalog")

	var menu: Control = GuildMenuScene.instantiate()
	get_tree().root.add_child(menu)
	menu.present(assets)
	await _settle(menu)
	var rows: Array = []
	for index in range(3):
		rows.append(menu.get_node("Content/Option%d/Label" % index).text)
	assert_eq(rows, [assets.text_message(Msg.SOURCE, Msg.Id.GUILD_CHALLENGE),
		assets.text_message(Msg.SOURCE, Msg.Id.GUILD_QUEST),
		assets.text_message(Msg.SOURCE, Msg.Id.GUILD_INFO)],
		"Field_Guild_List_mPaint draws the three fixed msg 51/52/53 rows, not a guild roster")
	assert_eq(Rect2i(menu.get_node("Bounds").get_rect()), Rect2i(86, 16, 228, 208),
		"Menu_win_Box4_DrawWindow centers the 228x208 guild menu at (86, 16)")
	menu.queue_free()

	var info: Control = GuildInfoScene.instantiate()
	get_tree().root.add_child(info)
	info.present(assets)
	await _settle(info)
	assert_eq(info.page_count, 3, "common/guild.fxt holds 3 label+body pages")
	assert_eq(info.get_node("Content/Body").get_child_count(), 9,
		"Field_Guild_Info_Detail_mPaint draws at most 9 body lines per page")
	assert_eq(info.get_node("Content/Label").text, assets.text_message("common/guild.fxt", 0),
		"each page pairs the label record 2*page with the body record 2*page+1")
	info.handle_key("ArrowRight")
	info.handle_key("ArrowRight")
	var last_page: int = info.page
	info.handle_key("ArrowRight")
	assert_true(last_page == 2 and info.page == 0 and info.scroll == 0,
		"paging past the last page wraps to the first one instead of overflowing")
	info.queue_free()
