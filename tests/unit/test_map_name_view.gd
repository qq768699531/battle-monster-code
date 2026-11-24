extends "res://tests/unit/gut_case.gd"

const ViewScene = preload("res://game/field/map/map_name_view/map_name_view.tscn")
const MapNameView = preload("res://game/field/map/map_name_view/map_name_view.gd")


func test_legacy_suite() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var view: Control = ViewScene.instantiate()
	viewport.add_child(view)
	var text: Label = view.get_node("Bounds/Roll/Text")
	view.present("风之城\n城门", MapNameView.Source.WARP)
	assert_true(view.visible and text.text == "风之城 城门",
		"native name strip opens and normalizes line breaks")
	view.advance(3.0)
	assert_true(not view.visible, "all native display frames finish without looping")
	# 同图传送：原生 `Map_warpProc:54` 在 `GameCanvas_mapLOAD` 之后无条件
	# `Game_msgInit(1, MapData.reserved_0x10)`，名字没变也要重播。
	view.present("风之城\n城门", MapNameView.Source.WARP)
	assert_true(view.visible and text.text == "风之城 城门", "同图传送：同名也重播")
	view.advance(3.0)
	# 剧情 opcode 14 载入的仍是当前地图时不换图，不重播。
	view.present("风之城\n城门", MapNameView.Source.STORY)
	assert_true(not view.visible, "剧情载入当前图不重播")
	view.present("基连神殿1", MapNameView.Source.WARP)
	assert_true(view.visible and text.text == "基连神殿1", "换到另一张图才重新播名称")
	view.present(null, MapNameView.Source.STORY)
	assert_true(not view.visible and text.text.is_empty(),
		"unavailable names never become a fabricated map ID")
	viewport.free()
