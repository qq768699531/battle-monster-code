extends Control
## 小地图：按 MDT 通行标志生成像素并按原生顺序做 RGB565 处理。

## 对象 id 段：原生 `Map_miniDRAW` 按 object_kind 分辨，工程里落到 actor 的 id。
const HERO_ID := 0
const MONSTER_ID_MIN := 1000
## 原生小地图方块边长（tile = 2 逻辑像素）与黑色外框向左上外扩的宽度。
const MARKER_TILE := 2
const MARKER_BORDER := 1
## 原生主循环 20 fps（`FramePacing.NATIVE_FRAME_SECONDS`）：`Field_Basic_mPaint` 每帧把锚点推进一半，
## 8 帧（0.4 s）收敛到 1 px；场景 `slide` 轨道按同样 8 段采样。
## 场景 `slide` 轨道（`Bounds:position:x`）在该 AnimationPlayer 的默认库里。
const SLIDE_ANIMATION := &"slide"
const SLIDE_TRACK := 0

## NPC 头顶任务码的枚举只有一份：`scripts/data/quest_mark.gd`（`Qst_icoGET` 的结果，
## 由 field_runtime 落到 actor 的 `quest_status`；头顶图标与 HUD 色块共用）。
const QuestMark = preload("res://field/quest_mark/quest_mark.gd")

@export var terrain_opacity := 0.625
@export var player_color := Color.GREEN
@export var monster_color := Color.RED
## `Map_miniDRAW`：码 2／4／5（可接、目标达成、事件任务）画 `0xFFFF00`。
@export var quest_available_color := Color(1, 1, 0)
## `Map_miniDRAW`：码 3（进行中）画 `0x808080`。
@export var quest_progress_color := Color(0.501961, 0.501961, 0.501961)
@export var enabled_warp_color := Color.BLUE
@export var disabled_warp_color := Color.RED
@export var marker_border_color := Color.BLACK

var _warps: Array = []
var _warp_views: Array[ColorRect] = []
var _actors: Array = []
var _warp_enabled: Dictionary = {}
## 场景 `slide` 轨道的归一化形状（0 → 1），`_ready` 时从 Scene 读一次。
var _slide_shape := PackedFloat32Array()
var _target_left_edge := 0.0
var _left := false
var _elapsed := 0.0
var _tick := 0
var _has_map := false
var _positioned := false


func _ready() -> void:
	_slide_shape = _scene_slide_shape()
	hide()


func set_map(map: Dictionary) -> void:
	var terrain: Dictionary = map.terrain
	var width: int = int(terrain.width_tiles) * 2
	var height: int = int(terrain.height_tiles) * 2
	var pixels := PackedInt32Array()
	pixels.resize(width * height)
	if int(map.info.map_group) not in [7, 8, 12]:
		for y in range(height):
			for x in range(width):
				if (int(terrain.cell_flags[y >> 1][x >> 1]) & 7) == 0:
					pixels[y * width + x] = 0xffff
	# JC_grpFillBLUR updates RGB565 in place, from bottom-right to top-left.
	for y in range(height - 1, -1, -1):
		for x in range(width - 1, -1, -1):
			var red := 0
			var green := 0
			var blue := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if x + dx < 0 or y + dy < 0 or x + dx >= width or y + dy >= height:
						continue
					var weight := (2 if dx == 0 else 1) * (2 if dy == 0 else 1)
					var pixel := pixels[(y + dy) * width + x + dx]
					red += ((pixel >> 11) & 31) * weight
					green += ((pixel >> 5) & 63) * weight
					blue += (pixel & 31) * weight
			pixels[y * width + x] = ((red >> 4) << 11) | ((green >> 4) << 5) | (blue >> 4)
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	for y in range(height):
		for x in range(width):
			var pixel := pixels[y * width + x]
			image.set_pixel(x, y, Color8(((pixel >> 11) & 31) << 3,
				((pixel >> 5) & 63) << 2, (pixel & 31) << 3))
	$Bounds/Terrain.texture = ImageTexture.create_from_image(image)
	$Bounds/Terrain.modulate.a = terrain_opacity
	$Bounds.size = image.get_size()
	_warps = map.info.warps
	for dot: ColorRect in _warp_views:
		dot.free()
	_warp_views.clear()
	for warp: Dictionary in _warps:
		var dot := ColorRect.new()
		dot.position = Vector2(warp.tile_x, warp.tile_y) * 2 - Vector2.ONE
		dot.size = Vector2(4, 4)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Bounds/Warps.add_child(dot)
		_warp_views.append(dot)
	_has_map = true
	_positioned = false
	_elapsed = 0.0
	_tick = 0


func present(actors: Array, warp_enabled: Dictionary, hero_screen: Vector2) -> void:
	_actors = actors
	_warp_enabled = warp_enabled
	_left = hero_screen.x > size.x / 2 and hero_screen.y < size.y / 2
	_show_anchor()
	_refresh_warps()
	queue_redraw()


func advance(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= FramePacing.NATIVE_FRAME_SECONDS:
		_elapsed -= FramePacing.NATIVE_FRAME_SECONDS
		_tick += 1
	_refresh_warps()
	queue_redraw()


## 首次出现与换图后直接落到目标左边界；之后锚点翻转才由场景轨道滑过去。
func _show_anchor() -> void:
	var target := _target_left_edge_of(_left)
	if _positioned and is_equal_approx(target, _target_left_edge):
		return
	_target_left_edge = target
	if not _positioned:
		$Slide.stop()
		$Bounds.position = Vector2(target, $Bounds.position.y)
		_positioned = true
		return
	_slide_to(target)


## 两种锚点各对应一个箱体左边界：右锚对齐箱体右边缘（原生 `n110 = viewport.width - 52`），
## 左锚对齐箱体左边缘（原生 `n110 = 110`）；箱体宽度随地图变化，所以端点按当前宽度换算。
func _target_left_edge_of(left: bool) -> float:
	return $LeftAnchor.position.x if left else $RightAnchor.position.x - $Bounds.size.x


## 轨道端点按「起点 = 当前左边界、终点 = 目标左边界」写一次，逐帧位移全在 `Bounds:position:x` 上。
func _slide_to(left_edge: float) -> void:
	var animation: Animation = $Slide.get_animation(SLIDE_ANIMATION)
	var start: float = $Bounds.position.x
	var span := left_edge - start
	for index in _slide_shape.size():
		animation.track_set_key_value(SLIDE_TRACK, index, start + span * _slide_shape[index])
	$Slide.play(SLIDE_ANIMATION)


## 场景轨道的归一化形状：原生每帧取一半，前段快后段缓，与 `(n110 + x) >> 1` 的收敛一致。
func _scene_slide_shape() -> PackedFloat32Array:
	var animation: Animation = $Slide.get_animation(SLIDE_ANIMATION)
	var count := animation.track_get_key_count(SLIDE_TRACK)
	var first: float = animation.track_get_key_value(SLIDE_TRACK, 0)
	var last: float = animation.track_get_key_value(SLIDE_TRACK, count - 1)
	var shape := PackedFloat32Array()
	shape.resize(count)
	for index in count:
		shape[index] = (animation.track_get_key_value(SLIDE_TRACK, index) - first) / (last - first)
	return shape


func _refresh_warps() -> void:
	var pulse := (_tick * 16) % 256
	if pulse > 127:
		pulse = 255 - pulse
	for index in _warps.size():
		var warp: Dictionary = _warps[index]
		var enabled: bool = _warp_enabled.get(str(int(warp.destination_map_id))) != false
		var color := enabled_warp_color if enabled else disabled_warp_color
		var brightness := float(pulse) / 255.0
		color = color + Color(brightness, brightness, brightness, 0) if enabled else \
			color - Color(brightness, brightness, brightness, 0)
		_warp_views[index].color = color.clamp()


func _draw() -> void:
	if not _has_map:
		return
	var origin: Vector2 = $Bounds.position
	for actor: Dictionary in _actors:
		# Object kinds: hero=1, monster=2, NPC=3. Packaged NM marker bytes are all zero.
		if int(actor.id) < MONSTER_ID_MIN:
			continue
		_square_marker(origin + _marker_point(actor), monster_color)
	for actor: Dictionary in _actors:
		var id := int(actor.id)
		if id <= HERO_ID or id >= MONSTER_ID_MIN:
			continue
		var color := quest_marker_color(actor)
		if color.a <= 0.0:
			continue
		_square_marker(origin + _marker_point(actor), color)
	for actor: Dictionary in _actors:
		if int(actor.id) == HERO_ID:
			var point := origin + _marker_point(actor)
			_round_marker(point - Vector2.ONE, 4, player_color, false)
			_round_marker(point - Vector2(2, 2), 6, marker_border_color, true)
			break


## NPC 的任务码 → 小地图方块色，透明表示该 NPC 不画标记。
func quest_marker_color(actor: Dictionary) -> Color:
	return quest_color(int(actor.get("quest_status", QuestMark.Code.NONE)))


## `Map_miniDRAW`：码 2／4／5 黄，码 3 灰，码 0／1 不画。
func quest_color(code: int) -> Color:
	match code:
		QuestMark.Code.ACCEPTABLE, QuestMark.Code.GOAL_REACHED, QuestMark.Code.EVENT:
			return quest_available_color
		QuestMark.Code.IN_PROGRESS:
			return quest_progress_color
	return Color.TRANSPARENT


static func _marker_point(actor: Dictionary) -> Vector2:
	return Vector2(floorf(float(actor.x) * 2 + 1), floorf(float(actor.y) * 2 + 1))


func _square_marker(point: Vector2, color: Color) -> void:
	draw_rect(Rect2(point, Vector2(MARKER_TILE, MARKER_TILE)), color)
	_square_outline(Rect2(point - Vector2(MARKER_BORDER, MARKER_BORDER),
		Vector2(MARKER_TILE + MARKER_BORDER * 2, MARKER_TILE + MARKER_BORDER * 2)),
		marker_border_color)


func _square_outline(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), color)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), color)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), color)


func _round_marker(point: Vector2, width: int, color: Color, outline: bool) -> void:
	draw_rect(Rect2(point + Vector2(1, 0), Vector2(width - 2, 1)), color)
	draw_rect(Rect2(point + Vector2(1, width - 1), Vector2(width - 2, 1)), color)
	if outline:
		draw_rect(Rect2(point + Vector2(0, 1), Vector2(1, width - 2)), color)
		draw_rect(Rect2(point + Vector2(width - 1, 1), Vector2(1, width - 2)), color)
		for y in [1, width - 2]:
			for x in [1, width - 2]:
				draw_rect(Rect2(point + Vector2(x, y), Vector2.ONE), color)
	else:
		draw_rect(Rect2(point + Vector2(0, 1), Vector2(width, width - 2)), color)
