extends Control
## 通用滚动条：原生 `Menu_Item_DrawScroll` 的蓝色拇指 + 灰色轴 + 上下箭头。
##
## 所有页面只给「可见首行 / 总页数」，不再各自算 Track／Thumb 的尺寸和位置。
## 原生这里另登记了触摸，但本工程统一走页面的方向键／触摸十字，箭头只画不响应。

## 轨道上下各留出的箭头区域高度。
@export var track_inset := 10.0
## 拇指宽度（原生 `JC_grpFillRECT(..., 3, ...)`）。
@export var thumb_width := 3

@onready var _track: ColorRect = $Track
@onready var _thumb: ColorRect = $Thumb


## `first_row` 是可见首行（0 起），`pages` 是总页数（行数）。一页时整体隐藏。
func set_page(first_row: int, pages: int) -> void:
	visible = pages > 1
	if not visible:
		return
	var track := maxf(0.0, size.y - track_inset * 2.0)
	var thumb_height := maxf(3.0, 3.0 * (1.0 - float(pages)) + track)
	var value := 0.0 if pages <= 1 else float(first_row) / float(pages - 1)
	_thumb.position = Vector2(_track.position.x, track_inset + value * (track - thumb_height))
	_thumb.size = Vector2(thumb_width, thumb_height)