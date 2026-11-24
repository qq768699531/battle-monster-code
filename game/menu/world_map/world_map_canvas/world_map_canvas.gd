extends Control
## 世界地图绘制层：连线、节点图标、名称与右上角总览点阵。
##
## 几何照 `Map_worldDRAW`：节点中心在视口内为 `(34 + 68*列 - 相机x, 24 + 58*行 - 相机y)`
## （`Map_worldINIT` 的 `68*col - 宽/2 + 34`、`58*row + 29 - 高/2` 是居中的相机初值），
## 名称在中心下方 16 像素（`JC_fntDrawStringBold(x_3, v91 + 16, …)`），连线宽 3 像素。
## 当前地图由单独的英雄动画小人标记：`Marker` 是 `hero/h_f_01.tscn` 实例，脚点落在节点中心，
## 对应原生 `Object_drawBASIC(x_3, v91, 32, 1, 0, 1026, …)`。`1026 % 100 = 26`，即该 ANI 的
## 动作 26——只有 4 帧、每帧两层 `frame-083`（17×8，后两帧镜像）与 `frame-082`（25×22，下移
## 1 像素），不是待机循环，所以这里固定播这一个片段。
## 视口裁剪由父节点 `Viewport` 的 `clip_contents` 负责；本节点自己的绘制按视口手写裁剪。
##
## 右上角总览（整个世界的点阵缩略图 + 10×10 视口框）画在兄弟节点 `Overview` 的
## `ImageTexture` 上，不在本节点的 `_draw` 里：原生 `Map_worldDRAW` 的第三段循环在
## **名称之后**才画这些 2×2 点，而本节点的子节点（名称标签）总在本节点的 `_draw` 之上。
## 取证与公式见 `wiki\world-map\world-map-thumbnail.md`。
##
## 各层：记录列 > 99 为室内层，只在当前地图本身是室内层时绘制（`Map_worldINIT` 的 `+80` 标志）。
## 浏览的焦点是**格**（原生 `MapData.reserved_0x152[26]`／`[28]`）：方向键沿该方向跳到本层
## 最近的有地图格（原生是 ±1，空格也能停留，但空格上没有节点可画、镜头跟过去就是空白，
## 见 `_next_focus_cell`）；
## 镜头位移交给 Scene 里的线性动画（`CameraMove` 的唯一一条 value 轨道驱动 `CameraRig` 的
## `position`），本节点每帧只把它的位置取整成 `_camera` 做像素精确绘制。

const CELL := Vector2i(68, 58)
const NODE_OFFSET := Vector2i(34, 24)
## 原生 `Map_worldDRAW` 的节点屏幕 y 是 `58*行 + 24 - 镜头y`（`v40 = -5 - 镜头y` 与 `+29` 相抵），
## 而 `Map_worldINIT` 居中用 `58*行 + 29 - 高/2`：居中时节点比视口中心高这 5 像素（下方留名称）。
const NODE_CENTER_OFFSET_Y := 5
## `Map_worldINIT`／`Map_worldDRAW` 的居中与夹取边距：`(34, 29)`。
const CAMERA_MARGIN := Vector2i(NODE_OFFSET.x, NODE_OFFSET.y + NODE_CENTER_OFFSET_Y)
## `Map_worldDRAW` 每帧把镜头朝焦点格的居中位置折半靠拢：
## `JC_ptSET(&MapData.reserved_0x152[22], ([22] + 34 + 68*[26] - width/2) / 2,
## ([24] + 29 - height/2 + 58*[28]) / 2)`——[22]/[24] 是镜头像素、[26]/[28] 是焦点格，
## 68 像素差 8 拍收口（20 fps 一拍 0.05 s）。本工程把这段逐帧折半换成 Scene 的动画：
## `world_map.tscn` 的 `CameraMove` 驱动 `CameraRig` 的 `position`，关键帧按折半序列采样
## （0、1/2、3/4、7/8…即「先快后慢」的指数收敛），所以观感接近原版；落点仍是折半收敛后的
## `_clamp_camera(centered_camera_cell(_focus_cell))`。表现依据见 `wiki\world-map\world-map.md`。
const CAMERA_CLIP := &"camera_move"
## 折半 8 拍的时长（20 fps 一拍 0.05 s），与 Scene 里那条 clip 的 `length` 一致。
const CAMERA_SECONDS := 0.4
## `CameraMove` 那条 value 轨道的下标。
const CAMERA_CURVE_TRACK := 0
const ICON_FORMAT := "obj/ui_world/frame-%03d"
const DISABLED_ICON := 8
const LABEL_WIDTH := 120
const LABEL_OFFSET_Y := 16
## 总览点阵：3 像素一格、2×2 点，右对齐到视口右上角。
## `Map_worldDRAW` 583–588 行：`x = 3*列 + 视口宽 - 3*列数 - 3`、`y = 3*行 + 4`
## （`x`／`y` 是 reserve 矩形原点，即本节点的 0／0）。
const OVERVIEW_STEP := 3
const OVERVIEW_RIGHT_MARGIN := 3
const OVERVIEW_TOP := 4
const OVERVIEW_DOT := Vector2i(2, 2)
## 视口框：同函数 916–923 行 `JC_grpDrawRECT(..., 10, 10)`，
## `x = 视口宽 - 3*列数 - 4 + 3*(焦点列 - 1)`、`y = 3*(焦点行 - 1) + 3`，色 `0xC0C000`。
const OVERVIEW_BOX := 10
const OVERVIEW_BOX_INSET := 4
const OVERVIEW_BOX_TOP := 3
const GRAY_DOT := Color(0.502, 0.502, 0.502)
## `Map_worldDRAW` 里当前地图用 `(frames << 29 >> 30)` 的两位计数在 0x800000／0xC00000／0xFF0000 间闪：
## 四相位依次是 0x800000、0xC00000、0xFF0000、0xC00000（`n3 == 1 || n3 == 3` 同一档）。
const BLINK := [Color(0.502, 0, 0), Color(0.753, 0, 0), Color(1, 0, 0), Color(0.753, 0, 0)]
## 任务标记同一套三档闪烁：mark 1 = 0x004000／0x00A000／0x00FF00，mark 2 = 0x808000／0xC0C000／0xFFFF00。
const MARK_BLINK_RELATED := [
	Color(0, 0.251, 0), Color(0, 0.627, 0), Color(0, 1, 0), Color(0, 0.627, 0)]
const MARK_BLINK_TARGET := [
	Color(0.502, 0.502, 0), Color(0.753, 0.753, 0), Color(1, 1, 0), Color(0.753, 0.753, 0)]
const DISABLED_DOT := Color(0.753, 0.502, 0.753)
## 视口框颜色：`Map_worldDRAW` 922 行的 `JC_grpSetRGB(0xC0C000)`。
const BOX_COLOR := Color8(0xC0, 0xC0, 0x00)
## 任务标记图标：`Menu_winDrawIcon12` 从 `common/ui_window` 第 12 帧裁 21×25，
## 源 x = `21 * a3`（`a3 = mark - 1`），锚点 `GRP_IMAGE_ANCHOR_MIDDLE_CENTER`。
const MARK_FRAME := 12
const MARK_SIZE := Vector2i(21, 25)
const MARK_SLOT_OFFSET := 1
## `Menu_winDrawIcon12(x + 15, y - 10 + 浮动)` 的锚点位置（`JC_grpGetANCHOR` 减半宽半高）。
const MARK_OFFSET := Vector2i(15, -10)
## 浮动 = 画布计数 `% 10` 的三角波 5,4,3,2,1,0,1,2,3,4，加到 y 上（图标在最高位与下移 5 像素间往返）。
const MARK_FLOAT_PERIOD := 10
const MARK_FLOAT_AMPLITUDE := 5

## `Object_drawBASIC` 把 `animation_id` 当动作号用时只取低两位十进制（`1011 % 100 = 11`，同规则见
## `AniAction.action_of`）。
const HERO_MARKER_ANIMATION_ID := 1026

var _data: Variant
var _map_id := -1
## 开图时传给 `Map_worldINIT` 的地图号（原生 `MapData.reserved_0x152[18]`）：
## `Map_worldKEY` 的 `-5`（OK）把焦点格重设回它。
var _anchor := -1
## 焦点格（原生 `MapData.reserved_0x152[26]`／`[28]`，`Map_worldGET` 的 `+38` 列／`+40` 行
## 取 `% 100`）：方向键沿该方向走到本层最近的有地图格（见 `_next_focus_cell`）。
var _focus_cell := Vector2i.ZERO
## 焦点格 → 该格地图号（本层）。同格可能有多条记录，取该层表里第一个；空格不在表里。
var _cells: Dictionary = {}
var _interior := false
var _camera := Vector2i.ZERO
var _columns := 1
var _rows := 1
var _enabled: Dictionary = {}
var _passed: Dictionary = {}
var _layer: Array = []
var _icons: Array[Texture2D] = []
var _gray_icons: Dictionary = {}
var _labels: Array[Control] = []
var _label_scene: PackedScene
## 画布计数（每 `advance()` 加一）：总览点闪烁与标记浮动的相位都从它推。
var _ticks := 0
## 地图号 → `QuestMark.MapMark`（原生 `Map_worldDRAW` 的 mark 表，由调用方传入）。
var _marks: Dictionary = {}
var _mark_sheet: Texture2D

@onready var _marker: Node2D = $Marker
@onready var _marker_player: AnimationPlayer = $Marker/AnimationPlayer
## 镜头节点与它的动画播放器住在 `world_map.tscn` 的 `Content/Viewport` 下（与画布同级）：
## 轨道只驱动 `CameraRig` 的 `position`，本节点再取整成像素精确的 `_camera`。
@onready var _camera_rig: Node2D = $"../CameraRig"
@onready var _camera_player: AnimationPlayer = $"../CameraMove"
## 右上角总览画在这个兄弟节点的 `ImageTexture` 上（见文件头：原生在名称之后才画点阵）。
@onready var _overview: TextureRect = $"../Overview"

var _overview_image: Image
var _overview_texture: ImageTexture
## `CameraMove` 轨道的归一化形状（折半采样序列），`_ready` 时从 Scene 读一次。
var _camera_shape := PackedFloat32Array()


func _ready() -> void:
	var clip := AniAction.clip_name(_marker_player, AniAction.action_of(HERO_MARKER_ANIMATION_ID))
	if clip != &"":
		_marker_player.play(clip)
	_camera_shape = _scene_camera_shape()


## `quest_pages` 是任务文本资源的各页（`menu/quest.gd` 的 `split_segments` 结果）：page 3 =
## 地图号列表、page 4 = 目标地图。原生只有菜单任务页与野外任务详情页传它，HUD 小地图传 0。
## `focus_map_id` 是初始聚焦的地图（任务页传 `JC_fxtQINDEX(res, 3, 0)`），`-1` 表示没有。
func present(catalog: Object, data: Variant, map_id: int, enabled: Dictionary, passed: Dictionary,
		quest_pages: Variant = null, focus_map_id := -1) -> bool:
	if catalog == null or data == null or not data.has_method("count") or data.count() <= 0:
		push_error("世界地图节点表缺失：不能打开世界地图。")
		return false
	_data = data
	# `Map_worldINIT` 只吃一个地图号，它同时写焦点（`MapData.reserved_0x152[18]`）、
	# 内外层（`+34`）与网格尺寸（`+30`）。从任务页进来时这个号是任务第一个关联地域，
	# 从 HUD／野外进来时是角色所在地图；`_map_id` 只留给角色图标与总览闪烁。
	_map_id = map_id
	var anchor := focus_map_id if not data.node(focus_map_id).is_empty() else map_id
	# `reserved_0x152[18]`：`-5` 用它把焦点格写回去，所以这里存一份。
	_anchor = anchor
	_interior = bool(data.interior(anchor)) if data.has_method("interior") else false
	var extents: Vector2i = data.extents(_interior)
	_columns = extents.x
	_rows = extents.y
	_enabled = enabled
	_passed = passed
	_layer = data.layer_ids(_interior)
	_icons.clear()
	for index in range(DISABLED_ICON + 1):
		_icons.append(catalog.load_sprite(ICON_FORMAT % index))
	_gray_icons.clear()
	_mark_sheet = catalog.load_window_frame(MARK_FRAME)
	_marks = QuestMark.marks_from_pages(quest_pages)
	_ticks = 0
	_cells.clear()
	for layer_id: int in _layer:
		if not _cells.has(_cell(layer_id)):
			_cells[_cell(layer_id)] = layer_id
	# `Map_worldINIT` 写的是 `(列 % 100, 行)` 这个原始格，进 DRAW 后才按可视范围夹取，
	# 所以这里不夹（任务地域／角色所在地图就是初始焦点格）。
	_focus_cell = _cell(_anchor) if not data.node(_anchor).is_empty() else _cell(_first_layer_id())
	_camera = centered_camera_cell(_focus_cell)
	_place_camera()
	_build_labels(catalog)
	_sync_display()
	return true


## 方向键：焦点格沿该方向走到本层最近的有地图格，镜头从当前实际位置线性走向新目标。
func move_focus(direction: Vector2i) -> bool:
	var next := _next_focus_cell(direction)
	if next == _focus_cell:
		return false
	_focus_cell = next
	_sync_display()
	_start_camera_move()
	return true


## 原生 `Map_worldKEY` 对 `reserved_0x152[26]`／`[28]` 只做 ±1，空格也允许停留；但空格处
## `Map_worldDRAW` 没有节点可画，镜头跟过去之后视口里只剩零散几个边缘节点，看上去就是
## 「地图内容消失」（鼠标点方向箭头报的就是这个），所以这里沿方向跳过空格，只落在本层
## 有地图的格子上。也顺带不再把焦点夹进 `v84`／`v11` 的可视范围——那会在第一次按左右时
## 把行一起夹走（(7,0) → (8,1)），表现为一次点击斜着跳了一格。
func _next_focus_cell(direction: Vector2i) -> Vector2i:
	var grid := Rect2i(Vector2i.ZERO, Vector2i(_columns, _rows))
	var cell := _focus_cell
	while true:
		cell += direction
		if not grid.has_point(cell):
			return _focus_cell
		if _cells.has(cell):
			return cell
	return _focus_cell


## 原生 `Map_worldKEY` 的 `case -5`：`Map_worldINIT(MapData.reserved_0x152[18], 0)`——
## `[18]` 是**开图时**传给 INIT 的地图号（不是浏览位置），`a2 = 0` 所以不重算镜头，
## 镜头随后由线性动画走回这张图的格（`_start_camera_move`）。
func recenter() -> void:
	if _data != null and not _data.node(_anchor).is_empty():
		_focus_cell = _cell(_anchor)
	_sync_display()
	_start_camera_move()


func advance() -> void:
	_ticks += 1
	if _sync_camera():
		_sync_labels()
		_sync_marker()
	_refresh_overview()
	queue_redraw()


## 镜头动画按真实时间推进；逻辑拍只有 20 fps（`world_map.gd` 的 `TICK_SECONDS`），若只在
## `advance()` 里取整，60 fps 渲染下每段位移仍是 8 个台阶。所以动画播放期间每帧取整并重绘，
## 让线性位移真正连续；钟点、总览点阵等按拍推进的内容仍留在 `advance()` 里。
func _process(_delta: float) -> void:
	if _data == null or not _camera_player.is_playing():
		return
	if _sync_camera():
		_sync_labels()
		_sync_marker()
		queue_redraw()


## 镜头当前左上角（原生 `MapData.reserved_0x152[22]`／`[24]`）。
func camera() -> Vector2i:
	return _camera


## 把 Scene 动画驱动的 `CameraRig` 位置取整成像素精确的镜头左上角，返回是否发生位移。
func _sync_camera() -> bool:
	if _data == null:
		return false
	var before := _camera
	_camera = Vector2i(_camera_rig.position.round())
	return _camera != before


## 从镜头**当前实际位置**走向焦点格的居中值：关键帧按 Scene 里那条折半采样曲线的归一化形状
## 缩放，所以位移是「先快后慢」的指数收敛（原生逐帧折半的观感），途中再次改向时端点重写成
## 「当前位置 → 新目标」，不会跳回这次移动的起点。注意 `AnimationPlayer.stop()` 会把被驱动的属性
## 复位到上一段动画的起点，所以当前位置要在 `stop()` 之前取。
func _start_camera_move() -> void:
	if _data == null:
		return
	var from := _camera_rig.position
	var to := Vector2(_clamp_camera(centered_camera_cell(_focus_cell)))
	_camera_player.stop()
	var animation := _camera_player.get_animation(CAMERA_CLIP)
	if animation == null:
		return
	var span := to - from
	for index in _camera_shape.size():
		animation.track_set_key_value(CAMERA_CURVE_TRACK, index, from + span * _camera_shape[index])
	_camera_player.play(CAMERA_CLIP)
	_camera_rig.position = from


## `CameraMove` 轨道的归一化形状（0 → 1）：Scene 里存的是折半采样序列
## （0、0.5、0.75、0.875…），这里去掉首尾量纲后按任意端点缩放。
func _scene_camera_shape() -> PackedFloat32Array:
	var animation := _camera_player.get_animation(CAMERA_CLIP)
	var shape := PackedFloat32Array()
	if animation == null:
		return shape
	var count := animation.track_get_key_count(CAMERA_CURVE_TRACK)
	if count < 2:
		return shape
	var first: float = animation.track_get_key_value(CAMERA_CURVE_TRACK, 0).x
	var last: float = animation.track_get_key_value(CAMERA_CURVE_TRACK, count - 1).x
	shape.resize(count)
	for index in count:
		shape[index] = (animation.track_get_key_value(CAMERA_CURVE_TRACK, index).x - first) / (last - first)
	return shape


## 开图／重开时镜头直接落位（原生 `Map_worldINIT` 的 `a2 = 1` 分支当场算居中值，不播动画）。
func _place_camera() -> void:
	_camera_player.stop()
	_camera_rig.position = Vector2(_camera)


## 某张地图所在格的居中镜头（测试与 `world_map.gd` 用；地图号无效时返回 `Vector2i.ZERO`）。
func centered_camera(map_id: int) -> Vector2i:
	if _data == null or _data.node(map_id).is_empty():
		return Vector2i.ZERO
	return centered_camera_cell(_cell(map_id))


## 焦点格居中时的镜头左上角：`Map_worldINIT` 的 `a2 = 1` 分支
## （`68*列 - 宽/2 + 34`、`58*行 + 29 - 高/2`），再按 `Map_worldDRAW` 夹进地图范围。
func centered_camera_cell(cell: Vector2i) -> Vector2i:
	return _clamp_camera(Vector2i(
		CELL.x * cell.x - int(size.x) / 2 + NODE_OFFSET.x,
		CELL.y * cell.y + CAMERA_MARGIN.y - int(size.y) / 2))


## 当前焦点格（总览方框用）。
func focus_cell() -> Vector2i:
	return _focus_cell


## 焦点格上的地图号。原生没有「焦点节点」，只有 `[26]/[28]` 这个格，所以这里只给一个代表值：
## 格上有开图那张地图（`_anchor`）就返回它，否则取该层表里第一个；空格返回 -1。
func focus_id() -> int:
	if _data != null and not _data.node(_anchor).is_empty() and _cell(_anchor) == _focus_cell:
		return _anchor
	return node_at(_focus_cell)


## 该格的地图号（本层），空格返回 -1。
func node_at(cell: Vector2i) -> int:
	return int(_cells.get(cell, -1))


## 焦点格的合法范围（含端点，返回 `Rect2i(min, 尺寸)`）：`Map_worldDRAW` 的
## `v84 = (width - 34) / 2 / 68`、`v11 = (height - 29) / 2`，上界是 `列数 - 1 + v84 / -68`、
## `行数 - 1 + v11 / -58`（C 整数除法向零截断）。这条夹取保证居中后的镜头不出地图边界。
## 只剩总览方框（`overview_dot`）用它——方向键不再按它夹焦点，否则第一次按左右会把行一起
## 夹走（(7,0) → (8,1)），看着像斜着跳了一格。
func focus_bounds() -> Rect2i:
	var margin_x := (int(size.x) - CAMERA_MARGIN.x) / 2
	var margin_y := (int(size.y) - CAMERA_MARGIN.y) / 2
	var low := Vector2i(margin_x / CELL.x, margin_y / CELL.y)
	var high := Vector2i(_columns - 1 + margin_x / -CELL.x, _rows - 1 + margin_y / -CELL.y)
	return Rect2i(low, high - low + Vector2i.ONE)


func _clamp_focus_cell(cell: Vector2i) -> Vector2i:
	var bounds := focus_bounds()
	return Vector2i(
		clampi(cell.x, bounds.position.x, bounds.end.x - 1),
		clampi(cell.y, bounds.position.y, bounds.end.y - 1))


func node_center(map_id: int) -> Vector2:
	if _data == null or _data.node(map_id).is_empty():
		return Vector2.ZERO
	return Vector2(
		NODE_OFFSET.x + CELL.x * (int(_data.column(map_id)) % 100) - _camera.x,
		NODE_OFFSET.y + CELL.y * int(_data.row(map_id)) - _camera.y)


## 记录的行列口径：`Map_worldGET` 把记录读进 64 字节结构，列在 `+38`（`v4[19]`）、
## 行在 `+40`（`v4[20]`）；`Map_worldINIT` 用 `列 % 100` 当格坐标（列 > 99 是室内层）。
func _cell(map_id: int) -> Vector2i:
	if _data == null or _data.node(map_id).is_empty():
		return Vector2i.ZERO
	return Vector2i(int(_data.column(map_id)) % 100, int(_data.row(map_id)))


## 该节点上的任务标记（`Map_worldDRAW` 的 mark：page 3 → 1、page 4 → 2）。
func mark_of(map_id: int) -> int:
	return int(_marks.get(map_id, QuestMark.MapMark.NONE))


## 标记图标左上角：中心在 `(节点x + 15, 节点y - 10 + 浮动)`，锚点按 `JC_grpGetANCHOR` 的
## 整数截断（21 >> 1 = 10、25 >> 1 = 12）扣半宽半高。
func mark_icon_origin(map_id: int) -> Vector2i:
	return Vector2i(node_center(map_id)) + MARK_OFFSET + Vector2i(0, _mark_float()) - MARK_SIZE / 2


## 图标浮动：画布计数 `% 10` 的三角波 5,4,3,2,1,0,1,2,3,4（加到 y 上，0–5 像素）。
func _mark_float() -> int:
	var phase := _ticks % MARK_FLOAT_PERIOD
	return MARK_FLOAT_AMPLITUDE - phase if phase <= MARK_FLOAT_AMPLITUDE else phase - MARK_FLOAT_AMPLITUDE


func _first_layer_id() -> int:
	return int(_layer[0]) if not _layer.is_empty() else -1


func _clamp_camera(camera: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(camera.x, 0, maxi(0, CELL.x * _columns - int(size.x))),
		clampi(camera.y, 0, maxi(0, CELL.y * _rows - int(size.y))))


func _sync_display() -> void:
	_sync_labels()
	_sync_marker()
	_refresh_overview()
	queue_redraw()


## 原生 `Map_worldDRAW:322-364`：先 `Map_worldGET(MapData.map_id, v117)` 取角色所在地图，
## 再遍历**当前层**的节点，把节点的列／行与它比（`SHIWORD(v118[9]) == v117[19]`、
## `SLOWORD(v118[10]) == v117[20]`），相同的那一格才画 `Object_drawBASIC(..., 1026, ...)`。
## 比的是格坐标而不是地图号：同一格里可能有几条记录（`layer_ids` 只留带连线的代表），角色在
## 那些次级记录上时原样画在本格；列不取 `% 100`，所以室内层（列 > 99）不会与室外格子撞上。
func _sync_marker() -> void:
	if _data == null or _data.node(_map_id).is_empty():
		_marker.visible = false
		return
	for map_id: int in _layer:
		if _data.column(map_id) == _data.column(_map_id) and _data.row(map_id) == _data.row(_map_id):
			_marker.visible = true
			_marker.position = node_center(map_id)
			return
	_marker.visible = false


func _build_labels(catalog: Object) -> void:
	for label: Control in _labels:
		label.queue_free()
	_labels.clear()
	if _label_scene == null:
		_label_scene = load("res://engine/ui/native_label/native_label.tscn")
	for map_id: int in _layer:
		var label: Control = _label_scene.instantiate()
		label.text = String(catalog.text_message("map/m%d.mif" % map_id, "name"))
		label.horizontal_alignment = 1
		label.outline = Color.BLACK
		label.size = Vector2(LABEL_WIDTH, 10)
		add_child(label)
		_labels.append(label)


func _sync_labels() -> void:
	for index in range(_labels.size()):
		var center := node_center(_layer[index])
		_labels[index].position = Vector2(center.x - LABEL_WIDTH / 2.0, center.y + LABEL_OFFSET_Y)


func _draw() -> void:
	if _data == null:
		return
	_draw_links()
	for map_id: int in _layer:
		_draw_node(map_id)


## `clip_contents` 只裁剪子节点，本节点自己的绘制必须手动画在视口矩形内。
func _clip_rect() -> Rect2i:
	return Rect2i(Vector2i.ZERO, Vector2i(size))


func _draw_links() -> void:
	for map_id: Variant in _data.nodes.keys():
		var a := node_center(int(map_id))
		for target: int in _data.links(int(map_id)):
			var b := node_center(target)
			if a.x == b.x:
				_line(a, b)
				_line(a - Vector2(1, 0), b - Vector2(1, 0))
				_line(a + Vector2(1, 0), b + Vector2(1, 0))
			else:
				_line(a, b)
				_line(a - Vector2(0, 1), b - Vector2(0, 1))
				_line(a + Vector2(0, 1), b + Vector2(0, 1))


## 直线按视口做 Liang–Barsky 裁剪；整段在外面就不画。
func _line(from: Vector2, to: Vector2) -> void:
	var delta := to - from
	var enter := 0.0
	var exit := 1.0
	var clip := Rect2(_clip_rect())
	var edges := [
		[-delta.x, from.x - clip.position.x],
		[delta.x, clip.end.x - from.x],
		[-delta.y, from.y - clip.position.y],
		[delta.y, clip.end.y - from.y],
	]
	for edge: Array in edges:
		var p: float = edge[0]
		var q: float = edge[1]
		if is_zero_approx(p):
			if q < 0.0:
				return
			continue
		var ratio := q / p
		if p < 0.0:
			enter = maxf(enter, ratio)
		else:
			exit = minf(exit, ratio)
		if enter > exit:
			return
	draw_line(from + delta * enter, from + delta * exit, Color.WHITE)


func _draw_node(map_id: int) -> void:
	var center := node_center(map_id)
	if not _visible_around(center):
		return
	_draw_icon(_data.icon(map_id), center, _is_passed(map_id))
	if not _is_enabled(map_id):
		_draw_icon(DISABLED_ICON, center, true)
	_draw_mark(map_id)


## 任务标记图标：`common/ui_window` 第 12 帧按 mark 切片（mark 1 → 源 x 0、mark 2 → 源 x 21）。
func _draw_mark(map_id: int) -> void:
	var mark := mark_of(map_id)
	if mark == QuestMark.MapMark.NONE or _mark_sheet == null:
		return
	var source := Rect2i(MARK_SIZE.x * (mark - MARK_SLOT_OFFSET), 0, MARK_SIZE.x, MARK_SIZE.y)
	_blit_region(_mark_sheet, source, mark_icon_origin(map_id))


func _draw_icon(index: int, center: Vector2, passed: bool) -> void:
	if index < 0 or index >= _icons.size():
		return
	var texture: Texture2D = _icons[index] if passed else _gray_texture(index)
	if texture == null:
		return
	var texture_size := Vector2i(texture.get_size())
	_blit(texture, Vector2i(center) - texture_size / 2)


## 把纹理画在 rect 原点处，按视口裁掉超出部分（原生 `JC_grpSetRESERVE` 的效果）。
func _blit(texture: Texture2D, origin: Vector2i) -> void:
	_blit_region(texture, Rect2i(Vector2i.ZERO, Vector2i(texture.get_size())), origin)


## 同上，但只取 `source` 这块（图集切片）
func _blit_region(texture: Texture2D, source: Rect2i, origin: Vector2i) -> void:
	var placement := Rect2i(origin, source.size)
	var visible := placement.intersection(_clip_rect())
	if visible.size.x <= 0 or visible.size.y <= 0:
		return
	var offset := visible.position - placement.position
	draw_texture_rect_region(texture, Rect2(visible), Rect2(source.position + offset, visible.size))


## 未通过的地图按 `GRP_MODE_GRAY` 画成灰度：这里用同一图集生成灰度副本。
func _gray_texture(index: int) -> Texture2D:
	if _gray_icons.has(index):
		return _gray_icons[index]
	var texture: Texture2D = _icons[index]
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			var gray := (pixel.r8 * 76 + pixel.g8 * 150 + pixel.b8 * 29) >> 8
			image.set_pixel(x, y, Color8(gray, gray, gray, pixel.a8))
	var result := ImageTexture.create_from_image(image)
	_gray_icons[index] = result
	return result


## 总览点左上角：3 像素一格、2×2 点，右对齐到视口右上角。
## 原生 `Map_worldDRAW` 583–588 行：`destination_xa = 3 * (列 % 100) + 视口宽
## - 3 * 列数 - 3 + x`、`destination_y_2 = 3 * 行 + 4 + y`。
func overview_dot(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(size.x) - OVERVIEW_STEP * _columns - OVERVIEW_RIGHT_MARGIN + OVERVIEW_STEP * cell.x,
		OVERVIEW_TOP + OVERVIEW_STEP * cell.y)


## 视口框：`Map_worldDRAW` 916–923 行 `destination_x_4 = -3 * 列数 - 4 + x
## + 3 * (焦点列 - 1) + 视口宽`、`destination_y_3 = 3 * (焦点行 - 1) + 3 + y`，
## 再 `JC_grpDrawRECT(..., 10, 10)`。画框之前该函数已把焦点格 `[26]`／`[28]` 夹进可视范围
## （141–163 行），所以这里用夹取后的格——框不会跑到点阵外面。
func overview_box() -> Rect2i:
	var cell := _clamp_focus_cell(_focus_cell)
	return Rect2i(
		int(size.x) - OVERVIEW_STEP * _columns - OVERVIEW_BOX_INSET + OVERVIEW_STEP * (cell.x - 1),
		OVERVIEW_STEP * (cell.y - 1) + OVERVIEW_BOX_TOP,
		OVERVIEW_BOX, OVERVIEW_BOX)


## 重画右上角总览：整张世界地图的 2×2 点阵 + 10×10 视口框。
## 原生没有预渲染的缩略图，也不缩放主视图——`Map_worldDRAW` 每帧按记录坐标重画这些方块
## （三档闪烁的相位所以能逐拍变色），只有 `JC_grpSetRESERVE` 的视口裁剪，没有底色与边框。
func _refresh_overview() -> void:
	if _data == null:
		return
	var image_size := Vector2i(size)
	if _overview_image == null or _overview_image.get_size() != image_size:
		_overview_image = Image.create_empty(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
		_overview_texture = ImageTexture.create_from_image(_overview_image)
		_overview.texture = _overview_texture
	_overview_image.fill(Color(0, 0, 0, 0))
	for map_id: int in _layer:
		var origin := overview_dot(_cell(map_id))
		# 原生按 `(点 - 68, 点 - 68, 136, 116)` 的包围框与视口求交决定画不画（`JC_rtINTER1`）。
		if not Rect2i(origin - CELL, CELL * 2).intersects(_clip_rect()):
			continue
		_overview_image.fill_rect(Rect2i(origin, OVERVIEW_DOT), _dot_color(map_id))
	_fill_box_outline(_overview_image, overview_box(), BOX_COLOR)
	_overview_texture.update(_overview_image)


## `JC_grpDrawRECT`：左右各一列、上下各一行的 1 像素空心框（右边在 `x - 1 + 宽`，
## 下边在 `y - 1 + 高`），与 `draw_rect(..., false)` 的取法一致。
func _fill_box_outline(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(rect.position, Vector2i(1, rect.size.y)), color)
	image.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - 1, 0), Vector2i(1, rect.size.y)), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, 1)), color)
	image.fill_rect(Rect2i(rect.position + Vector2i(0, rect.size.y - 1), Vector2i(rect.size.x, 1)), color)


## `Map_worldDRAW` 的总览点颜色，优先级：当前地图 → mark 1 → mark 2 → 可 warp → 其余。
## 闪烁相位是 `(frames_since_canvas_change << 29 >> 30)` 的四档，逐拍取一档（不是「两拍一档」）。
func _dot_color(map_id: int) -> Color:
	var phase := _ticks % BLINK.size()
	if map_id == _map_id:
		return BLINK[phase]
	match mark_of(map_id):
		QuestMark.MapMark.RELATED:
			return MARK_BLINK_RELATED[phase]
		QuestMark.MapMark.TARGET:
			return MARK_BLINK_TARGET[phase]
	if not _is_enabled(map_id):
		return DISABLED_DOT
	if _is_passed(map_id):
		return Color.WHITE
	return GRAY_DOT


func _is_enabled(map_id: int) -> bool:
	return _enabled.get(str(map_id)) != false


func _is_passed(map_id: int) -> bool:
	return _passed.get(str(map_id), false)


## 原生按 136x116 的包围框和视口求交决定是否画（`JC_rtINTER1`）。
func _visible_around(center: Vector2) -> bool:
	return Rect2(center - Vector2(CELL), Vector2(CELL) * 2).intersects(
		Rect2(Vector2.ZERO, Vector2(size)))