extends RefCounted
## 帮助/说明分页的状态机。

const C = preload("res://prime/runtime_constants.gd")
const View = preload("res://prime/text_page_view.gd")

var page_index := 0
var page_scroll := 0
var _pages: Dictionary = {}


func set_pages(target: int, pages: Array) -> void:
	if target not in [C.METHOD, C.INFO] or pages.is_empty():
		push_error("Prime page resource must contain at least one title/body pair.")
		return
	for page: Variant in pages:
		if not page is Dictionary or not page.get("title") is String or \
				not page.get("lines") is Array:
			push_error("Invalid Prime page resource.")
			return
	_pages[target] = pages.duplicate(true)


func _dispatch_page_key(context: RefCounted, key: int) -> void:
	match key:
		TouchCode.Key.BACK:
			if context.window_state > 0:
				context.window_state = -1
		TouchCode.Pad.LEFT, TouchCode.Pad.RIGHT:
			page_index = posmod(page_index + (1 if key == TouchCode.Pad.RIGHT else -1),
			_pages[context.scene].size())
			if context.scene == C.METHOD:
				page_scroll = 0
		TouchCode.Pad.UP:
			page_scroll = maxi(0, page_scroll - 1)
		TouchCode.Pad.DOWN:
			page_scroll += 1


func paint_page(context: RefCounted, paint: Dictionary) -> void:
	var page: Dictionary = _pages[context.scene][page_index]
	page_scroll = clampi(page_scroll, 0, maxi(0, page.lines.size() - 12))
	paint.merge({
		"page": page, "page_index": page_index, "page_count": _pages[context.scene].size(),
		"page_scroll": page_scroll, "window_state": context.window_state,
		"modal_state": context.modal_state, "modal_selection": context.modal_selection,
	})
	paint.regions = View.page_regions(paint)


func run(context: RefCounted) -> void:
	if context.scene in [C.METHOD, C.INFO] and context.window_state == -4:
		context._return_to_title(2 if context.scene == C.METHOD else 3)
