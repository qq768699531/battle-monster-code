extends "res://tests/unit/gut_case.gd"

const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const WorldMapScene = preload("res://game/menu/world_map/world_map/world_map.tscn")
const BLUR_SHADER := "res://engine/ui/screen_shade/menu_map_blur.gdshader"

## 菜单页序里任务页的下标（`MenuModel.Tab.QUEST`）。
const QUEST_TAB := 3


func _frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 整棵树里可见的半透明模糊层数：原生只有 `MapRes.map_scratch_image` 一张快照
## （`Map_Copy` 每帧拷同一张），窗口叠几层都还是那一张，所以任何时刻最多一层。
func _visible_blur_layers(node: Node) -> int:
	var total := 0
	var item := node as CanvasItem
	if item != null:
		var material := item.material as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path == BLUR_SHADER and item.is_visible_in_tree():
			total += 1
	for child in node.get_children():
		total += _visible_blur_layers(child)
	return total


func _run() -> void:
	var catalog: Node = get_node("/root/AssetCatalog")
	var data: Variant = catalog.load_world_map()
	var settings_path := "user://menu-map-blur-test.cfg"

	var viewport := SubViewport.new()
	viewport.size = ScreenShade.LOGICAL_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.2, 0.6, 0.3)
	background.size = Vector2(ScreenShade.LOGICAL_SIZE)
	viewport.add_child(background)
	await _frame()

	var menu: Control = MenuScene.instantiate()
	menu.settings_path = settings_path
	viewport.add_child(menu)
	menu.open({"monsters": [], "inventory": {}, "parameter": {}, "mapId": 41,
		"warpEnabled": {}, "warpPassed": {}}, Fixtures.data(), "标题")
	await _frame()

	# ① 定格：`frozen` 采样的是开窗前的 viewport 快照（原生 `Field_Basic_Capture` 写
	# `MapRes.map_scratch_image`，模糊与半透明都只作用在这一张上），不再是实时屏幕。
	var shade: ScreenShade = menu.get_node("MapShade")
	var material := shade.material as ShaderMaterial
	var snapshot: Texture2D = material.get_shader_parameter("snapshot")
	assert_true(material.get_shader_parameter("frozen") == true and snapshot is ImageTexture
		and snapshot.get_size() == Vector2(ScreenShade.LOGICAL_SIZE),
		"shade 采样的是一张开窗前抓的 400×240 快照，而不是实时屏幕")

	# ② 可见期内只抓一次：任务页开出的世界地图复用菜单那一层，`Map_Copy()` 拷的还是同一张。
	menu.select_tab(QUEST_TAB)
	menu.quest_detail_open = true
	menu._open_world_map(36, ["标题", "说明", "目标", "41,38", "36"])
	await _frame()
	var frozen_snapshot: ImageTexture = shade.snapshot()
	assert_true(menu.world_map_open and frozen_snapshot != null and frozen_snapshot == snapshot,
		"世界地图复用菜单那一层且不重抓快照（一次 capture 之后全是 Map_Copy）")

	# ③ 最多一层：菜单任务页入口与野外 MAP 键入口（单开一扇世界地图窗）各只有一层可见 shade。
	var menu_layers := _visible_blur_layers(get_tree().root)
	menu.queue_free()
	await _frame()
	var page: Control = WorldMapScene.instantiate()
	viewport.add_child(page)
	var opened: bool = page.open(catalog, data, 41, {}, {})
	await _frame()
	var field_layers := _visible_blur_layers(get_tree().root)
	assert_true(opened and menu_layers == 1 and field_layers == 1,
		"两条入口都只有一层可见的半透明模糊底")

	viewport.queue_free()
	await _frame()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func test_legacy_suite() -> void:
	await _run()
