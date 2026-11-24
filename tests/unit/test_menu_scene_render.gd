extends "res://tests/unit/gut_case.gd"

const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const MenuScene = preload("res://menu/menu/menu.tscn")

var viewport: SubViewport
var menu: Control


func _frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _item_catalog() -> GameplayData:
	return Fixtures.data({"items": [{"id": 1001, "type": 1, "index": 1, "icon": 1,
		"detail_slots": [0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]}]})


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(400, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	menu = MenuScene.instantiate()
	viewport.add_child(menu)
	menu.settings_path = "user://menu-scene-render-test.cfg"
	menu.bind({"monsters": [], "inventory": {}, "parameter": {}}, Fixtures.data(), "标题\n内容\n目标")
	await _frame()
	var status_frame := viewport.get_texture().get_image().get_pixelv(Vector2i(89, 46))
	assert_true(status_frame.is_equal_approx(Color.WHITE),
		"status frame renders at the native origin")
	menu.select_tab(3)
	await _frame()
	menu.press("ArrowDown")
	await _frame()
	var quest_row := viewport.get_texture().get_image().get_pixelv(Vector2i(97, 64))
	assert_true(quest_row.is_equal_approx(Color("#007ea1")),
		"selected quest row uses the native highlight")
	# 丢弃窗口的数量框：原生选数量时是 #FF9600 底 + 黑字，进入确认后改成黑底白字。
	menu.bind({"monsters": [], "inventory": {"1001": 2}, "parameter": {}}, _item_catalog(),
		"标题\n内容\n目标")
	menu.select_tab(1)
	menu.press("ArrowDown")
	menu.press("ArrowDown")
	menu.press("Enter")
	menu.press("ArrowDown")
	menu.press("Enter")
	var window: Control = menu._pages.item_discard.get_node("Window")
	while window.is_transitioning():
		await _frame()
	await _frame()
	assert_true(viewport.get_texture().get_image().get_pixelv(Vector2i(210, 100)).is_equal_approx(
		Color("#ff9600")), "discard quantity step uses the native orange count box")
	menu.press("Enter")
	await _frame()
	assert_true(viewport.get_texture().get_image().get_pixelv(Vector2i(210, 100)).is_equal_approx(
		Color.BLACK), "discard confirm step switches the count box to black")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.settings_path))


func test_legacy_suite() -> void:
	await _run()
