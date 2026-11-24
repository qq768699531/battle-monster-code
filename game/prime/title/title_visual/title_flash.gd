extends Control
## 标题菜单选中项的高亮：全部用绘制指令画，不拼 Sprite、不加提亮 shader。
## 原生 `Prime_Title_DrawItem`：白色圆角块（`JC_grpFillRoundRECT`）+ 图集第 2 帧的斜光
## （`JC_fbmDrawSPRITE／CLIP`）。层级压在文字 Label 之下，避免白块盖住菜单文字。

const PLATE_SIZE := Vector2(25, 21)
const GLEAM_SIZE := Vector2(28, 21)
const CLIP_SIZE := Vector2(20, 21)
## 四帧的贴图落点（相对选中项原点）：原生 x-39／x-15／x+15／x+19。第 2 帧原生写 y+22，
## 会把斜光画到下一项上（实测有压字），这里收进同一行 y+1。
const GLEAM_AT := [Vector2(-39, 1), Vector2(-15, 1), Vector2(14, 1), Vector2(19, 1)]
## 第 0／3 帧只取斜光左侧 20 像素：`JC_fbmDrawCLIP(..., 20, 21, 8, 0, ...)`。
const CLIP_SOURCE_OFFSET := Vector2(8, 0)
## 白色圆角块只在第 1／2 帧出现：原生 `x-39` 与 `x+14`。
const PLATE_AT := [Vector2(-39, 1), Vector2(14, 1)]

var _phase := -1
var _sheet: Texture2D
var _gleam := Rect2()


## 传入斜光贴图（可以是图集切片）：拆出底层图与区域，绘制时直接按区域取。
func setup(texture: Texture2D) -> void:
	if texture is AtlasTexture:
		_sheet = (texture as AtlasTexture).atlas
		_gleam = (texture as AtlasTexture).region
	elif texture != null:
		_sheet = texture
		_gleam = Rect2(Vector2.ZERO, texture.get_size())
	else:
		_sheet = null
		_gleam = Rect2()
	queue_redraw()


func present(phase: int, origin: Vector2) -> void:
	_phase = phase
	position = origin
	visible = phase >= 0 and _sheet != null
	queue_redraw()


func _draw() -> void:
	if _phase < 0 or _sheet == null or _phase >= GLEAM_AT.size():
		return
	if _phase == 1 or _phase == 2:
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(1, 1, 1, 1)
		plate.set_corner_radius_all(1)
		draw_style_box(plate, Rect2(PLATE_AT[_phase - 1], PLATE_SIZE))
	var at: Vector2 = GLEAM_AT[_phase]
	if _phase == 0 or _phase == 3:
		draw_texture_rect_region(_sheet, Rect2(at, CLIP_SIZE),
			Rect2(_gleam.position + CLIP_SOURCE_OFFSET, CLIP_SIZE))
	else:
		draw_texture_rect_region(_sheet, Rect2(at, GLEAM_SIZE), _gleam)
