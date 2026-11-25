extends "res://engine/ui/window_transition/window_transition.gd"
## 世界地图窗口（`Menu_world_Draw` 的 228x208 Box4 窗 + `Map_worldDRAW`）。
##
## 窗口本身是 `components/window_transition.tscn`（`window_size` 228×208、`side_width` 12、
## `header_height` 12、条形相位高 18 = 头部 12 + 6）。`Menu_world_Draw` 在**每个**开合相位
## 都画标题（相位 1／2 的条形与相位 3 的条文都画），所以标题图 `ui_battle/frame-010` 挂在
## `Bounds/TitleIcon`（相对开合矩形 `rect.x+15, rect.y+7`），四向箭头与 OK／BACK
## （`Menu_win_Box_DrawKeyInfo`）挂在 `Content` 里、按稳态窗框相对摆位：
## 组件开着 `content_follows_window`，相位 3 的 `y-6`／`height+12` 由 `Layout.box4_window_rect`
## 统一给，页面不再自己算偏移。关窗播完才发 `closed`。
##
## 浏览的焦点是格。取证 `Map_worldKEY`：方向键对**焦点格** `MapData.reserved_0x152[26]`／
## `[28]` 做 ±1（不是镜头，也不是「跳最近节点」），镜头像素 `[22]`／`[24]` 不动；
## `Map_worldDRAW` 每帧把镜头朝焦点格的居中位置折半靠拢（`(镜头 + 目标) / 2`）。
## 所以「上下左右切换」是逐像素平移。**空格不能停留**：原生 ±1 允许走进没有地图的格，但
## `Map_worldDRAW` 在空格处没有节点可画，镜头跟过去之后视口里只剩边缘零散节点（鼠标点方向
## 箭头报的「地图内容消失」），所以 `move_focus` 沿方向跳到本层最近的有地图格。
## OK（`-5`）是 `Map_worldINIT(开图地图号, 0)`：焦点格重设回开图那张图、镜头不瞬移，随后折半回到它。
## BACK／Esc 关闭。`map_id` 只决定角色图标的位置，初始焦点可由 `focus_map_id` 另给
## （任务页传 `JC_fxtQINDEX(text_resource, 3, 0)`）。
##
## **方向箭头只有一条路径**：原生 `Menu_world_Draw` 给四支箭登记的就是
## `EFC_mainTouchSET(-4／-3／-2／-1, 1, …)` 这组键码，键盘方向键再经 `JC_keyMODIFY`
## 归一成同一组，两者都进 `Menu_Quest_mKeyPressed` → `Map_worldKEY`，所以一次按下只改一格焦点、
## 镜头由 `Map_worldDRAW` 的追焦推过去。这里同样只留 `_press_arrow()` 一处：UI 的 `gui_input`
## 与 `handle_key()` 都调到它，镜头动画在 `world_map_canvas.move_focus()` 里统一起停。

signal close_requested
signal closed

const TICK_SECONDS := 0.05
const PRESSED_MODULATE := Color(1.6, 1.6, 1.6)

const WorldMapCanvas = preload("res://game/menu/world_map/world_map_canvas/world_map_canvas.gd")

## 键盘动作名 → 焦点格方向：`Map_worldKEY` 的 `-4／-3／-2／-1` 分别对
## `reserved_0x152[26]`（列）与 `[28]`（行）做 ±1。
const ARROW_DIRECTIONS := {
	"ArrowUp": Vector2i.UP,
	"ArrowDown": Vector2i.DOWN,
	"ArrowLeft": Vector2i.LEFT,
	"ArrowRight": Vector2i.RIGHT,
}

var _elapsed := 0.0
var _closing := false

@onready var _canvas: WorldMapCanvas = $Content/Viewport/Canvas


func _ready() -> void:
	super()
	hide()
	transition_finished.connect(_on_transition_finished)
	$Content/Up.gui_input.connect(_on_arrow_input.bind(Vector2i.UP, $Content/Up/Icon))
	$Content/Down.gui_input.connect(_on_arrow_input.bind(Vector2i.DOWN, $Content/Down/Icon))
	$Content/Left.gui_input.connect(_on_arrow_input.bind(Vector2i.LEFT, $Content/Left/Icon))
	$Content/Right.gui_input.connect(_on_arrow_input.bind(Vector2i.RIGHT, $Content/Right/Icon))
	$Content/FooterOk.gui_input.connect(_on_footer_input.bind(true))
	$Content/FooterBack.gui_input.connect(_on_footer_input.bind(false))


func open(catalog: Object, data: Variant, map_id: int, enabled: Dictionary, passed: Dictionary,
		quest_pages: Variant = null, focus_map_id := -1) -> bool:
	if not _canvas.present(catalog, data, map_id, enabled, passed, quest_pages, focus_map_id):
		push_error("世界地图节点表缺失：未打开世界地图。")
		return false
	for footer: Control in [$Content/FooterOk, $Content/FooterBack]:
		footer.configure(catalog, 1 if footer == $Content/FooterBack else 0)
	_closing = false
	_elapsed = 0.0
	set_process(true)
	# 开图那一刻定格背景：原生 `Field_Basic_Capture` 在窗口出现前把画面模糊一次写进
	# `MapRes.map_scratch_image`，之后每帧 `Map_Copy()` 都拷同一张，所以地图场景是静止的。
	# 从任务页开出来时复用菜单那一层与它已有的快照，不再叠第二层、也不重抓。
	if screen_shade:
		ScreenShade.acquire_frozen(self)
	show()
	open_window()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	set_process(false)
	close_window()


func closing() -> bool:
	return _closing


## 无动画退场：野外详情页层 1 的 `-16`（`Qst_chtKeyPress:26-31`）只把层号写回 0、把共用的开合
## 相位写 1，`Qst_chtDRAW` 同帧就不再调 `Menu_world_Draw`——原生没有地图窗收拢那一段。
## 所以这里停掉逐拍、直接隐藏，不播 `close`；开合相位当场落回稳态，免得残留的
## `transition_finished` 回声把页面当成「刚开窗」。
func leave() -> void:
	_closing = false
	stop_transition()
	set_process(false)
	hide()


func handle_key(key: String) -> bool:
	if ARROW_DIRECTIONS.has(key):
		_press_arrow(ARROW_DIRECTIONS[key])
		return true
	match key:
		"Enter", "Space":
			_canvas.recenter()
		"Escape", "Backspace":
			close_requested.emit()
	return true


## 焦点变更的唯一入口（UI 箭头与键盘方向键共用）：镜头位移由画布的 `move_focus()` 起停。
func _press_arrow(direction: Vector2i) -> void:
	_canvas.move_focus(direction)


## `TICK_SECONDS` 驱动总览点／标记闪烁的相位（镜头位移不在这里：它由 Scene 的 `CameraMove`
## 线性动画按真实时间推进，画布在动画播放期间每帧取整并重绘）。
func _process(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= TICK_SECONDS:
		_elapsed -= TICK_SECONDS
		_canvas.advance()


func _on_arrow_input(event: InputEvent, direction: Vector2i, icon: TextureRect) -> void:
	var pressed: Variant = _event_pressed(event)
	if pressed == null:
		return
	icon.modulate = PRESSED_MODULATE if pressed else Color.WHITE
	if pressed:
		_press_arrow(direction)


func _on_footer_input(event: InputEvent, accept: bool) -> void:
	if not _event_pressed(event):
		return
	if accept:
		_canvas.recenter()
	else:
		close_requested.emit()


func _on_transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	closed.emit()


## 只关心按下/松开，拖动不改变按住状态；返回 null 表示忽略该事件。
## 触摸屏会同时给出 `InputEventScreenTouch` 与 Godot 模拟出来的鼠标事件
## （`device == InputEvent.DEVICE_ID_EMULATION`），后者一律忽略——一次按下只走一次
## `Map_worldKEY`（同 `touch_controls.gd` 的口径），真实鼠标（device 非 −1）不受影响。
func _event_pressed(event: InputEvent) -> Variant:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed and not event.canceled
	return null