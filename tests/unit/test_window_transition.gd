extends "res://tests/unit/gut_case.gd"

const WindowScene = preload("res://engine/ui/window_transition/window_transition.tscn")
const WindowScript = preload("res://engine/ui/window_transition/window_transition.gd")
const ShadeScene = preload("res://engine/ui/screen_shade/screen_shade.tscn")
## 原生 `Menu_win_Box4_DrawWindow` 每帧推进 1／2／3／4 四个相位，每相位一帧；
## 动画把每相位摆成 0.05 s，所以 0.05 是相位 1／2 的条形，0.1 是相位 3 的条文。
const BAR_PHASE_TIME := 0.05
const STRIP_PHASE_TIME := 0.1
## Box2 用例用的窗口尺寸：只为验证条形相位只改高、稳态相位恢复它。
const BOX2_WINDOW_SIZE := Vector2i(200, 100)

var _window: Control


func before_each() -> void:
	super()
	_window = WindowScene.instantiate()
	add_child_autofree(_window)


func test_content_shows_once_the_frame_reaches_the_strip_phase() -> void:
	_window.open_window()
	assert_false(_content().visible, "the window starts empty while the frame opens")
	_player().advance(STRIP_PHASE_TIME)
	assert_true(_content().visible,
		"content appears with the strip phase (native 0xC4 mask), not at the steady frame")


func test_interior_fill_stays_out_of_the_bar_phases() -> void:
	var interior := _window.get_node("Bounds/Interior") as Control
	assert_false(interior.visible, "the interior starts hidden like the body")
	_window.open_window()
	_player().advance(BAR_PHASE_TIME)
	assert_false(interior.visible, "phase 1/2 draw only the bar (native 0x33 mask)")
	_player().advance(BAR_PHASE_TIME)
	assert_true(interior.visible, "the strip phase draws the interior fill")


func test_discard_window_hides_its_buttons_while_the_frame_is_a_bar() -> void:
	var page := _page("res://game/menu/item/item_discard/item_discard.tscn")
	var window := page.get_node("Window") as Control
	window.present_select("要丢弃吗?", 1)
	window.show()
	var frame := page.get_node("Window/Bounds/Box2") as Control
	var yes := page.get_node("Window/Content/Yes") as Button
	window.open_window()
	window.get_node("AnimationPlayer").advance(BAR_PHASE_TIME)
	assert_true(frame.is_visible_in_tree(), "the Box2 frame is drawn with the collapsed bar")
	assert_false(yes.is_visible_in_tree(), "the discard buttons wait for the strip phase")
	window.get_node("AnimationPlayer").advance(BAR_PHASE_TIME)
	assert_true(yes.is_visible_in_tree(), "the discard buttons return with the strip phase")


func test_save_view_keeps_its_confirm_button_under_the_tracked_content() -> void:
	var page := _page("res://game/field/runtime/save_view/save_view.tscn")
	var content := page.get_node("Window/Content") as Control
	var confirm := page.get_node("Window/Content/Confirm") as Button
	assert_true(content.is_ancestor_of(confirm), "the confirm button must ride `Window/Content`")
	page.get_node("Window").open_window()
	page.get_node("Window/AnimationPlayer").advance(BAR_PHASE_TIME)
	assert_false(content.is_visible_in_tree(), "save view content waits for the strip phase")
	page.get_node("Window/AnimationPlayer").advance(BAR_PHASE_TIME)
	assert_true(content.is_visible_in_tree(), "save view content returns with the strip phase")


## 原生 `Menu_win_Box4_Draw` 只在 `0xC4` 掩码（相位 -1／3／4）画标题，`0x33` 掩码只画条。
func test_box4_title_waits_for_the_strip_phase() -> void:
	var title := _window.get_node("Bounds/Title") as Control
	_window.open_window()
	assert_false(title.visible, "the bar phase draws only the bar, so no title")
	_player().advance(STRIP_PHASE_TIME)
	assert_true(title.visible, "the title returns with the strip phase")


## 原生 `Menu_win_Box2_DrawWindow@0x4ADE8`：条形相位是 16px 高、竖直居中的条，
## 稳态相位画整个窗口；Box2 没有头部、标题与页脚（`Menu_win_Box2_Draw@0x4AD78`）。
func test_box2_draws_a_centered_bar_then_the_full_window() -> void:
	_window.stop_transition()
	_window.kind = WindowScript.BoxKind.BOX2
	_window.window_size = BOX2_WINDOW_SIZE
	_window.phase = WindowScript.BoxPhase.BAR
	var bounds := _window.get_node("Bounds") as Control
	assert_eq(bounds.size.y, 16.0, "the Box2 bar is 16px high")
	assert_eq(bounds.position.y, 112.0, "the Box2 bar is centered in 240px")
	assert_true(_window.get_node("Bounds/Box2").visible, "Box2 draws its own frame")
	assert_false(_window.get_node("Bounds/Header").visible, "Box2 has no header strip")
	assert_false(_window.get_node("Bounds/Title").visible, "Box2 has no title")
	_window.phase = WindowScript.BoxPhase.STABLE
	assert_eq(bounds.size, Vector2(BOX2_WINDOW_SIZE), "the steady phase restores the window")


func test_stop_transition_restores_the_steady_frame() -> void:
	_window.open_window()
	_player().advance(BAR_PHASE_TIME)
	_window.stop_transition()
	assert_false(_window.is_transitioning(), "stopping leaves no animation running")
	assert_eq(_window.phase, WindowScript.BoxPhase.STABLE, "stopping snaps back to the steady phase")
	assert_true(_content().visible, "the content is visible again at the steady phase")


func _page(path: String) -> Control:
	var holder := Control.new()
	add_child_autofree(holder)
	var page := (load(path) as PackedScene).instantiate() as Control
	holder.add_child(page)
	page.show()
	return page


func _content() -> Control:
	return _window.get_node("Content")


func _player() -> AnimationPlayer:
	return _window.get_node("AnimationPlayer")


## 开窗方在 `show()` 之前抓好的完整一帧可以直接作为背景快照，避免即时抓帧抓到空帧。
func test_screen_shade_accepts_supplied_snapshot() -> void:
	var shade: Control = ShadeScene.instantiate()
	add_child_autofree(shade)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	shade.set_snapshot(image)
	assert_true(shade.snapshot() != null and shade.snapshot().get_size() == Vector2(4, 4),
		"调用方抓的帧被原样用作快照")

