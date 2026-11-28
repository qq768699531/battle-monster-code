extends Control
## 原生 `Menu_Item_DrawScroll` 的滑块几何：轨道从顶端箭头下 10 px 起，拇指高
## `3*(1-页数) + 轨道`（最小 3），位置按首行在轨道内分页。控件本身的 13×92 位置与大小
## 由使用场景在 `.tscn` 里排好，这里只按滚动值移动拇指。

@export var track_inset := 10.0
@export var thumb_width := 3


## `first_row` 是可见首行（0 起），`pages` 是总页数（行数）。一页时拇指铺满轨道。
func set_page(first_row: int, pages: int) -> void:
	var track := maxf(0.0, size.y - track_inset * 2.0)
	var thumb_height := maxf(3.0, 3.0 * (1.0 - float(pages)) + track)
	var value := 0.0 if pages <= 1 else float(first_row) / float(pages - 1)
	var thumb: ColorRect = $Thumb
	thumb.position.y = track_inset + value * (track - thumb_height)
	thumb.size = Vector2(thumb_width, thumb_height)
