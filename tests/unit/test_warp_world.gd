extends "res://tests/unit/gut_case.gd"

const WarpWorldScene = preload("res://field/warp_world/warp_world.tscn")
## 场景根脚本：静态候选表在这里。
const WarpWorldScript = preload("res://field/warp_world/warp_world.gd")
## 共用的 Box2 确认框脚本：WARP1／WARP2 的框是同一个场景实例。
const WarpConfirmScript = preload("res://field/warp_confirm/warp_confirm.gd")
## 开合相位枚举（`Menu_win_Box4_DrawWindow@0x4F82C` 的 `n4`）在父脚本里。
const WindowTransitionScript = preload("res://engine/ui/window_transition/window_transition.gd")
## 「半透明 + 模糊」层用的 shader（`Field_Basic_Capture` 的 `JC_grpFillBLUR`）。
const BLUR_SHADER := "res://shaders/menu_map_blur.gdshader"

## 上船时记下的位置（原生 `ParamData.warp_saved_*`），即候选下标 3。
const SAVED_MAP_ID := 41
const SAVED_TILE := Vector2i(12, 34)
## `Field_Warp2_Draw` 的候选数组下标：3 是「当前（上船）位置」。
const CURRENT_SLOT := 3


func _frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 开窗动画整段播完（0.15 s）。
func _settle() -> void:
	await get_tree().create_timer(0.2).timeout
	await _frame()


## 整棵树里可见的半透明模糊层数。飞艇页开窗前也有 `Field_Basic_Capture`，
## 落到画面上就是一张 `Map_Copy` 的模糊快照。
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


func test_legacy_suite() -> void:
	var catalog: Node = get_node("/root/AssetCatalog")
	var data: Variant = catalog.load_world_map()
	var page: Control = WarpWorldScene.instantiate()
	get_tree().root.add_child(page)
	page.open(catalog, data, SAVED_MAP_ID, SAVED_TILE.x, SAVED_TILE.y,
		{str(SAVED_MAP_ID): false}, {str(SAVED_MAP_ID): true})
	assert_eq(_visible_blur_layers(get_tree().root), 1, "野外侧的飞艇世界地图也只有一层模糊底")
	# 原生 `Field_Warp2_Draw`：`0x33` 掩码（相位 −3／−2／1／2）只画标题图，
	# `0xC4`（−1／3／4）才画标题图加正文与 5 个候选节点。
	assert_true(page.is_transitioning() and page.phase == WindowTransitionScript.BoxPhase.BAR_FADED
		and page.get_node("Bounds/TitleIcon").is_visible_in_tree(),
		"相位 1（条形）就要有标题图：原生 0x33 掩码只画 Menu_battleDrawIcon10")
	assert_false(page.get_node("Content").visible, "相位 1／2 不画正文与节点")
	await _settle()
	assert_true(page.phase == WindowTransitionScript.BoxPhase.STABLE
		and page.get_node("Bounds/TitleIcon").is_visible_in_tree(), "稳态相位 4 标题图仍在")
	var current: Variant = page.candidates[CURRENT_SLOT]
	assert_eq([page.candidates.size(), current.map_id, current.tile_x, current.tile_y],
		[5, SAVED_MAP_ID, SAVED_TILE.x, SAVED_TILE.y], "候选固定 5 个、下标 3 用上船位置")
	# 下标 3 的占位值不另写数字：`Param_saveINIT` 的 memset 0 之后才被
	# `Field_Warp1_mKeyPressed:17-19` 覆盖，本工程取 `StoryRuntime` 那唯一一份初值。
	var placeholder := WarpWorldScript._static_candidates()[CURRENT_SLOT]
	assert_eq([placeholder.map_id, placeholder.tile_x, placeholder.tile_y],
		[StoryRuntime.WARP_SAVED_MAP_INITIAL, StoryRuntime.WARP_SAVED_TILE_INITIAL,
			StoryRuntime.WARP_SAVED_TILE_INITIAL],
		"候选下标 3 的占位值与 `ParamData.warp_saved_*` 的工程初值同源")

	# `Map_warpIsEnable == 0` 时原生只提示 fxt 43，不进确认框、也不交目的地。
	watch_signals(page)
	page.handle_key("Enter")
	assert_signal_not_emitted(page, "move_requested", "未开放的节点不能移动")

	# 开放后 OK → 确认框（游标 0 = 是）→ 再 OK 才把候选表里的目的地交出去。
	page.open(catalog, data, SAVED_MAP_ID, SAVED_TILE.x, SAVED_TILE.y,
		{str(SAVED_MAP_ID): true}, {str(SAVED_MAP_ID): true})
	watch_signals(page)
	page.handle_key("Enter")
	page.handle_key("Enter")
	assert_signal_emitted_with_parameters(page, "move_requested",
		[SAVED_MAP_ID, SAVED_TILE.x, SAVED_TILE.y])
	# WARP2 的确认框（fxt 44）走 `Menu_win_Box2_DrawSelect` 同一套折行：几何由
	# `warp_confirm.gd` 的 `layout()` 写回，正文只有 1 行时就是 Prototype + 1 行。
	assert_eq(page.get_node("Confirm/Content/Lines").get_child_count(), 2,
		"WARP2 确认框正文按折行数展开，不是固定高度里的一行")
	assert_eq(page.get_node("Confirm").get_script(), WarpConfirmScript,
		"确认框是共享的 warp_confirm.tscn 实例，本页不再内联第二份节点树")
