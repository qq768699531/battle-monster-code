extends "res://tests/unit/gut_case.gd"

const TouchControls = preload("res://field/touch_controls/touch_controls.gd")
const Minimap = preload("res://field/minimap/minimap.gd")
## 任意 NPC 段 id（1 ≤ id < 1000）。
const NPC_ID := 12

func _map(width: int, height: int, group: int = 2) -> Dictionary:
	var flags: Array = []
	for y in height:
		var row: Array = []
		row.resize(width)
		row.fill(0)
		flags.append(row)
	return {"info": {"map_group": group, "warps": []},
		"terrain": {"width_tiles": width, "height_tiles": height, "cell_flags": flags}}


func test_legacy_suite() -> void:
	var summary: Control = load("res://field/hero_summary/hero_summary.tscn").instantiate()
	var minimap: Control = load("res://field/minimap/minimap.tscn").instantiate()
	var touch: Node2D = load("res://field/touch_controls/touch_controls.tscn").instantiate()
	add_child(summary)
	add_child(minimap)
	add_child(touch)
	var parameter := {"level": 2, "development": {"experience": 130}}
	var original := parameter.duplicate(true)
	summary.present(parameter)
	assert_true(parameter == original and
		summary.get_node("Level/Glyphs").get_child_count() == 1 and
		summary.get_node("Experience/Glyphs").get_child_count() == 3,
		"binding renders level and EXP glyphs from the supplied progress without mutating it")
	var map := _map(10, 8)
	map.info.warps = [
		{"tile_x": 0, "tile_y": 0, "destination_map_id": 1},
		{"tile_x": 9, "tile_y": 7, "destination_map_id": 2}]
	var actors := [{"id": 0, "x": 4.0, "y": 4.0}]
	minimap.set_map(map)
	minimap.present(actors, {"2": false}, Vector2(200, 120))
	minimap.set_map(map)
	minimap.present(actors, {"2": false}, Vector2(200, 120))
	assert_true(minimap._warp_views.size() == 2 and
		minimap.get_node("Bounds/Warps").get_child_count() == 2,
		"changing maps replaces rather than duplicates dynamic warp markers")
	assert_eq(minimap.quest_marker_color({"id": NPC_ID, "x": 1.0, "y": 1.0,
		"quest_status": QuestMark.Code.ACCEPTABLE}), Color(1, 1, 0),
		"NPC with a claimable quest draws the native yellow 0xFFFF00 minimap block")
	assert_eq(minimap.quest_marker_color({"id": NPC_ID, "x": 1.0, "y": 1.0}).a, 0.0,
		"NPC without a quest code draws no minimap block")
	# 小地图锚点：首次出现直接落位、越过中线才由场景 `slide` 轨道滑到另一侧（bm-P1-26）。
	var bounds: Control = minimap.get_node("Bounds")
	var right_edge: float = minimap.get_node("RightAnchor").position.x - bounds.size.x
	assert_true(is_equal_approx(bounds.position.x, right_edge) and
		not minimap.get_node("Slide").is_playing(),
		"first present places the minimap at the right anchor instead of sliding in")
	minimap.present(actors, {"2": false}, Vector2(250, 50))
	assert_true(minimap._left and is_equal_approx(bounds.position.x, right_edge),
		"crossing the midline flips the anchor without the one-panel jump")
	await wait_for_signal(minimap.get_node("Slide").animation_finished, 2.0)
	assert_true(not minimap.get_node("Slide").is_playing() and
		is_equal_approx(bounds.position.x, minimap.get_node("LeftAnchor").position.x),
		"the slide track lands on the left anchor")
	touch.present(TouchControls.Style.FIELD_WILD, 0)
	assert_true(touch.touch_keys(Vector2(30, 96)).has(TouchCode.Key.HELP),
		"transparent SAVE art retains its real 40x40 hit region")
	summary.free()
	minimap.free()
	touch.free()
