@tool
extends Control

## 原生图标以「格子中心 - floor(纹理尺寸/2)」放置（`Menu_winDrawIcon` 一类绘制），
## 必须落在整数像素上：引擎的 STRETCH_KEEP_CENTERED 在奇数尺寸时会留下半像素，
## 最近邻采样会因此复制或丢掉一列像素。这里直接按真实纹理尺寸绘制。

var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

## 当前的整数绘制原点（相对本控件），供调用方和用例核对。
var icon_origin := Vector2.ZERO


func _draw() -> void:
	if texture == null:
		return
	var icon_size := texture.get_size()
	icon_origin = (size * 0.5).floor() - (icon_size * 0.5).floor()
	draw_texture_rect(texture, Rect2(icon_origin, icon_size), false)
