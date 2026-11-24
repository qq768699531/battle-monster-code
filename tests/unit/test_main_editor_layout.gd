extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://prime/prime_title_runtime/prime_title_runtime.gd")


func _run() -> void:
	var assets := get_tree().root.get_node("AssetCatalog")
	var title: Node2D = load("res://prime/title_visual/title_visual.tscn").instantiate()
	get_tree().root.add_child(title)
	title._menu_text.assign(["Start", "Settings", "Help", "Info", "Network"])
	title._title_textures.assign([
		load("res://assets/sprite/prime/title-0.webp"),
		load("res://assets/sprite/prime/title-1.webp")])
	title._title_flash_texture = assets.load_sprite("common/ui_title2/frame-002")
	var layout := Runtime.title_layout(0, 99, 4)
	var paint := {"scene": Runtime.TITLE, "frame": 30, "title_animation_frame": 0,
		"menu_open": true, "opening_frame": 99, "items": layout.items}
	title.present(paint)
	var item := title.get_node("Menu/Item0")
	var image := item.get_node("Image")
	var label := item.get_node("Label")
	var original_image_at: Vector2 = image.position
	var original_label_rect: Rect2 = label.get_rect()
	item.position += Vector2(12, 4)
	image.position += Vector2(3, 0)
	label.size.x += 8
	title.present(paint)
	assert_true(item.position == Vector2(212, 56)
		and image.position == original_image_at + Vector2(3, 0)
		and label.size.x == original_label_rect.size.x + 8,
		"title refresh preserves edited item, image and label layout")
	title.free()
	var main: Node2D = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main._runtime.scene = Runtime.TITLE
	main._runtime.menu_open = true
	main._runtime.opening_frame = 99
	main._runtime.highlight_frame = 4
	main.get_node("Title/Menu/Item0").position.x += 10
	var live_paint: Dictionary = main._runtime._paint()
	main._render(live_paint)
	assert_true(main._runtime._regions.back().x == 160,
		"main routes title input using actual composed scene controls")
	main.free()
	await get_tree().process_frame


func test_legacy_suite() -> void:
	await _run()
