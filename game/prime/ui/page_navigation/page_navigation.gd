extends Node2D
## 分页导航：左右翻页、页码与滚动条。

const UI = preload("res://game/prime/ui/layout/layout.gd")
var _numbers: Texture2D


func configure(catalog: Object) -> bool:
	var arrows: Texture2D = catalog.load_sprite("common/ui_battle/frame-001")
	for arrow in [$LeftArrow, $RightArrow, $MethodScroll/Up, $MethodScroll/Down,
			$InfoScroll/Up, $InfoScroll/Down]:
		arrow.texture.atlas = arrows
	if not $Numbers.configure(catalog):
		return false
	_numbers = $Numbers.texture
	return arrows != null


func present(paint: Dictionary) -> void:
	$Numbers.visible = paint.page_count > 1
	$Numbers.present("%d/%d" % [paint.page_index + 1, paint.page_count])
	var scrolling: bool = paint.page.lines.size() > int(get_meta("visible_lines")) and not (
		paint.scene == 14 and paint.page_index == 2)
	$MethodScroll.visible = scrolling and paint.scene == 13
	$InfoScroll.visible = scrolling and paint.scene != 13
	if not scrolling:
		return
	var scroll := $MethodScroll if paint.scene == 13 else $InfoScroll
	var track: Control = scroll.get_node("Track")
	var thumb: Control = scroll.get_node("Track/Thumb")
	var count: int = paint.page.lines.size() - int(get_meta("visible_lines")) + 1
	var step := int(thumb.custom_minimum_size.y)
	var height := maxi(step, int(track.size.y) + step * (1 - count))
	thumb.offset_top = floorf(paint.page_scroll * (track.size.y - height) / float(count - 1))
	thumb.offset_bottom = thumb.offset_top + height


func touch_rects(scene: int) -> Array[Rect2i]:
	var scroll: Control = $MethodScroll if scene == 13 else $InfoScroll
	if is_inside_tree():
		return [Rect2i($LeftHit.get_global_rect()), Rect2i($RightHit.get_global_rect()),
			Rect2i(scroll.get_node("UpHit").get_global_rect()), Rect2i(scroll.get_node("DownHit").get_global_rect())]
	var rect := UI.control_rect(scroll)
	return [UI.control_rect($LeftHit), UI.control_rect($RightHit),
		UI.control_rect(scroll.get_node("UpHit"), rect), UI.control_rect(scroll.get_node("DownHit"), rect)]


func regions(paint: Dictionary, back: Rect2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if paint.modal_state != 0 or paint.window_state not in UI.BODY_PHASES:
		return result
	var rects := touch_rects(paint.scene)
	result.append(UI._region(TouchCode.Pad.LEFT, rects[0]))
	result.append(UI._region(TouchCode.Pad.RIGHT, rects[1]))
	if paint.window_state == 4:
		result.append(UI._region(TouchCode.Key.BACK, back))
	if paint.page.lines.size() > int(get_meta("visible_lines")) and not (paint.scene == 14 and paint.page_index == 2):
		result.append(UI._region(TouchCode.Pad.UP, rects[2]))
		result.append(UI._region(TouchCode.Pad.DOWN, rects[3]))
	return result
