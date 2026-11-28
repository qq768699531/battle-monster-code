@tool
extends Control
## 窗口开合动画的播放与状态恢复。
##
## `Content`、`Bounds/Body`、`Bounds/Footer`、`Bounds/Interior` 的显隐挂在 `open`／`close` 动画轨道上，
## 按原生
## `Menu_win_Box4_DrawWindow` 的分相：相位 1／2（条形，只画 `header_height + 6` 高的条）只留
## 窗框，相位 3（`y-6`、`height+12` 的条文）起才画标题、正文框、页脚与正文（原生各页 `Draw` 的
## `0xC4` 掩码 = 相位 -1／3／4，`0x33` = 相位 -3／-2／1／2 只画条），关窗时相位 -1 还在、-2 起收起。
## 相位 4 只是稳态帧，不是正文的起点。
##
## `Bounds/Interior` 给「要在整个 `Bounds` 上铺满、但只在窗口展开后才该出现」的页内底板用：
## 原生这段是 `Menu_win_Box4_Draw` 条形阶段不画的那块正文填充。窗框（`Bounds/Outline`）与
## 替换整窗底板的 Box2 页留在 `Bounds` 上不随相位收起，因为原生 `Menu_win_Box2_Draw`／
## `Menu_win_Box4_Draw` 每帧都画边框。

signal transition_finished(opened: bool)
signal phase_changed(value: int)

const Layout = preload("res://game/prime/ui/layout/layout.gd")
const UiWindowManager = preload("res://engine/ui/window_manager/ui_window_manager.gd")

## 窗框种类：原生 `Menu_win_Box4_DrawWindow@0x4F82C`（带头部白条／标题／页脚，正文窗）与
## `Menu_win_Box2_DrawWindow@0x4ADE8`（只有 `Menu_win_Box2_Draw@0x4AD78` 三层描边＋填充的
## 确认框，无头部、无标题、无页脚）。
enum BoxKind {
	BOX4,
	BOX2,
}

## 开合相位。原生 `Menu_win_Box4_DrawWindow@0x4F82C` 与 `Menu_win_Box2_DrawWindow@0x4ADE8`
## 的 `n4`（`*a5`）取值与掩码完全一致：`n4 & 0x33`（相位 1／2／-2／-3）只画条形，
## `n4 & 0x44`（相位 3／-1）画 `y-6`、`height+12` 的条文，`n4 & 0x80`（相位 4）画稳态全窗；
## 相位 1 与 -3 先 `JC_grpSetMODE(GRP_MODE_ALPHA, 128)`。|相位| > 3 起不再绘制。
enum BoxPhase {
	BAR_FADED = 1,
	BAR = 2,
	BODY = 3,
	STABLE = 4,
	CLOSING_BODY = -1,
	CLOSING_BAR = -2,
	CLOSING_FADED = -3,
	CLOSED = -4,
}

## 页脚白条颜色：Box2 没有页脚（`Menu_win_Box2_Draw` 只画三层描边与填充），页脚设透明而
## 不是隐藏，因为 `Bounds/Footer:visible` 挂在开合轨道上。
const BOX2_FOOTER_COLOR := Color.TRANSPARENT
## Box4 的头部／正文内框构件。有些页在场景里主动把它们关掉（`inn`／`warp_confirm`／
## `guild_challenge` 与 `mastery_view` 的确认窗自带内框，所以藏起 `Header`／`Title`／
## `Body` 的 `Edge`／`Background`／`Left`／`Right`），所以切到 Box2 再切回来时按场景声明恢复，
## 不一律点亮。
const BOX4_CHROME_NODES := [
	"Bounds/Outline", "Bounds/Header",
	"Bounds/Body/Edge", "Bounds/Body/Background", "Bounds/Body/Left", "Bounds/Body/Right",
]

@export var kind: BoxKind = BoxKind.BOX4:
	set(value):
		kind = value
		if is_node_ready():
			_apply_geometry()

## 条形相位（1／2／-2／-3）的窗高。原生 `Menu_win_Box4_DrawWindow` 用的是
## `height_2 + 6`（`height_2` 即 `header_height`），头部 16 的页是 22；头部 12 的页（世界地图）
## 要在自己的场景里声明 18。
@export var collapsed_height := 22
## 头部白条高度（原生 `Menu_win_Box4_Draw(..., widtha, height)` 的 height；世界地图是 12）。
@export var header_height := 16:
	set(value):
		header_height = value
		if is_node_ready():
			_apply_geometry()
## 两侧白边宽度（`Menu_win_Box4_Draw` 的第一个参数；资料／说明／世界地图窗是 12）。
@export var side_width := 1:
	set(value):
		side_width = value
		if is_node_ready():
			_apply_geometry()
## 窗口正文尺寸。原生 `Menu_win_Box4_DrawWindow(w, h)` 把窗口在 400×240 里居中，
## 所以继承页只声明宽高即可，不用再去改 `Bounds` 的 offset。`Vector2i.ZERO` 表示沿用
## 场景里已经摆好的 `Bounds` 矩形（给需要偏离居中规则的老页面用）。
@export var window_size := Vector2i.ZERO:
	set(value):
		window_size = value
		if is_node_ready():
			_normal_rect = _base_rect()
			_apply_geometry()
@export var phase := BoxPhase.STABLE:
	set(value):
		phase = value
		if is_node_ready():
			_apply_geometry()
			phase_changed.emit(value)
## 正文是否跟着 `box4_window_rect` 的开合矩形走。原生各页的正文都相对
## `Menu_win_Box4_DrawWindow` 写回的那个矩形画（相位 3 是 `y-6`、`height+12` 的条文），
## 所以开了这一项的页把 `Content` 的子节点按稳态窗框相对摆位，相位偏移由组件统一给。
## 默认关：老页面仍按 400×240 绝对坐标摆位。
@export var content_follows_window := false:
	set(value):
		content_follows_window = value
		if is_node_ready():
			_apply_geometry()
## 开本级时旧窗层的去向：false = 出栈（管理器收起它，调用方自己关窗／释放），
## true = 旧窗层留在栈里先收起，本级关掉后自动恢复（菜单收起 `Frame` 再开二级选择窗那种）。
## 窗口栈、背景层与冻结判据都归 `UiWindows`（`engine/ui/window_manager`）。
@export var keep_previous := false

var _normal_rect: Rect2i
## Box4 稳态下场景自己声明的构件显隐与页脚颜色（见 `BOX4_CHROME_NODES`）。
var _box4_chrome_visible: Dictionary = {}
var _box4_title_visible: bool
var _box4_footer_color: Color


func _ready() -> void:
	_normal_rect = _base_rect()
	_box4_title_visible = $Bounds/Title.visible
	_box4_footer_color = $Bounds/Footer.color
	for path: String in BOX4_CHROME_NODES:
		_box4_chrome_visible[path] = (get_node(path) as Control).visible
	$AnimationPlayer.animation_finished.connect(_finished)
	_apply_geometry()


## 只要还有窗口／确认框在显示，这个查询就为真；野外据此冻结地图。
static func any_open() -> bool:
	var manager := _window_manager()
	return bool(manager.call("any_open")) if manager != null else false


## 开窗：先入栈（按 `keep_previous` 顶掉或收起旧的同类窗层），再播开合动画。
## 半透明 + 模糊的背景层由管理器挂在栈底那一扇窗层的紧下方，这里不碰可见性。
func open_window() -> void:
	var manager := _window_manager()
	if manager != null:
		manager.call("push", self, _slot_kind(self),
			UiWindowManager.Previous.KEEP_HIDDEN if keep_previous else UiWindowManager.Previous.DISMISS)
	$AnimationPlayer.play("open")
	$AnimationPlayer.advance(0)


## 任何窗口（包括菜单这种自绘全屏页）都通过这里登记：`kind` 决定它占窗口还是确认框的槽。
static func register_window(window: CanvasItem) -> void:
	var manager := _window_manager()
	if manager != null:
		manager.call("push", window, _slot_kind(window), UiWindowManager.Previous.DISMISS)


static func unregister_window(window: CanvasItem) -> void:
	var manager := _window_manager()
	if manager != null:
		manager.call("pop", window)


## 原生 `Menu_win_Box4_DrawWindow` 是页窗口、`Menu_win_Box2_DrawWindow` 是确认框：
## 两者各占一个槽，所以确认框可以叠在窗口上而不把窗口顶掉。
static func _slot_kind(window: Node) -> int:
	var value: Variant = window.get("kind")
	if value is int and int(value) == int(BoxKind.BOX2):
		return UiWindowManager.Kind.DIALOG
	return UiWindowManager.Kind.WINDOW


## 管理器是 autoload；本脚本是 `@tool`，编辑器里没有 autoload 时返回 null。
static func _window_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("UiWindows")


func close_window() -> void:
	$AnimationPlayer.play("close")
	$AnimationPlayer.advance(0)


func is_transitioning() -> bool:
	return $AnimationPlayer.is_playing()



## 中止开合：把轨道改过的一切落回稳态（相位 4），组件立刻可当作稳态窗用。
func stop_transition() -> void:
	$AnimationPlayer.stop()
	phase = BoxPhase.STABLE
	for node: Control in [$Bounds, $Content, $Bounds/Body, $Bounds/Footer, $Bounds/Interior]:
		node.visible = true
	$Bounds.modulate.a = 1.0


func _apply_geometry() -> void:
	var rect := _rect_for_phase()
	$Bounds.position = Vector2(rect.position)
	$Bounds.size = Vector2(rect.size)
	if content_follows_window:
		$Content.anchor_right = 0.0
		$Content.anchor_bottom = 0.0
		$Content.position = Vector2(rect.position)
		$Content.size = Vector2(rect.size)
	if kind == BoxKind.BOX2:
		_apply_box2_chrome()
	else:
		_apply_box4_chrome()


func _rect_for_phase() -> Rect2i:
	if kind == BoxKind.BOX2:
		return Layout.box2_window_rect(_normal_rect, phase)
	return Layout.box4_window_rect(_normal_rect, phase, collapsed_height)


## 原生 `Menu_win_Box4_Draw`：头部白条 3 + header_height，正文两侧各留 side_width 白边，
## 内侧再压 1 像素灰框与 1 像素黑底；条形相位只画条（无标题），正文相位（`0xC4` 掩码）才画标题。
func _apply_box4_chrome() -> void:
	var header_bottom := 3 + header_height
	$Bounds/Header.offset_bottom = header_bottom
	$Bounds/Title.offset_top = 3 + floori((header_height - 10) / 2.0)
	$Bounds/Title.offset_bottom = $Bounds/Title.offset_top + 10
	$Bounds/Body.offset_top = header_bottom
	$Bounds/Body/Edge.offset_left = side_width
	$Bounds/Body/Edge.offset_right = -side_width
	$Bounds/Body/Background.offset_left = side_width + 1
	$Bounds/Body/Background.offset_right = -(side_width + 1)
	$Bounds/Body/Left.offset_right = side_width
	$Bounds/Body/Right.offset_left = -side_width
	for path: String in BOX4_CHROME_NODES:
		(get_node(path) as Control).visible = _box4_chrome_visible[path]
	$Bounds/Title.visible = _box4_title_visible and phase in Layout.BODY_PHASES
	$Bounds/Footer.color = _box4_footer_color
	$Bounds/Box2.visible = false


## 原生 `Menu_win_Box2_Draw@0x4AD78` 画的是一整块三层描边（黑·黑·#CFCCCC）＋填充的圆角框，
## 没有头部白条、标题与页脚；所以只留 `Bounds/Box2`，其余 Box4 的构件全部收起。
func _apply_box2_chrome() -> void:
	$Bounds/Outline.visible = false
	$Bounds/Header.visible = false
	$Bounds/Title.visible = false
	$Bounds/Body/Edge.visible = false
	$Bounds/Body/Background.visible = false
	$Bounds/Body/Left.visible = false
	$Bounds/Body/Right.visible = false
	$Bounds/Footer.color = BOX2_FOOTER_COLOR
	$Bounds/Box2.visible = true


func _base_rect() -> Rect2i:
	if window_size == Vector2i.ZERO:
		return Rect2i($Bounds.get_rect())
	return Layout.box4_window_frame(window_size)


func _finished(animation: StringName) -> void:
	transition_finished.emit(animation == &"open")
