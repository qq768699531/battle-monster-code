extends "res://engine/ui/window_transition/window_transition.gd"
## 环境设定页：原生 Box4 窗框、五行选项与标题／页脚。
##
## 窗口主体复用 `components/window_transition.tscn`：正文尺寸由场景里的 `window_size`
## （原生 228×208）声明，矩形、折叠态与过冲相位全交给 `_apply_geometry()`；paint 的
## `window_state`（1→4 开窗、−1→−4 关窗）直接写进 `phase`。标题在 `Bounds` 里，
## 跟着框架一起动，选项行与页脚放在 `Content` 里，只在定型的相位 4 出现。
## 页脚 OK／BACK 图标本身就是原生的窗口内按键行（`Menu_win_Box_DrawKeyInfo`），只有
## paint 里的 `settings_touch_style` 含 `Mask.WINDOW_KEYS` 时才画；游戏内 OPTION 的 style 35
## 不画它，改用窗外的半透明摇杆与 OK／CLR。

const PrimeLayout = preload("res://prime/layout/layout.gd")
const TouchControls = preload("res://field/touch_controls/touch_controls.gd")
const TOUCH_CONTROLS := preload("res://field/touch_controls/touch_controls.tscn")
const SCENE := 12
const ROW_COUNT := PrimeLayout.SETTINGS_ROW_COUNT
const OPEN_PHASE := 4
## 原生 style 35（`EFC_mainTouchDRAW` 的 `style & 1`）只画半透明方向盘与 OK／CLR：
## 命中区读 `components/touch_controls.tscn` 里摆好的控件矩形，不另抄一套坐标。
const TOUCH_DIRECTIONS := {"Left": TouchCode.Pad.LEFT, "Up": TouchCode.Pad.UP,
	"Right": TouchCode.Pad.RIGHT, "Down": TouchCode.Pad.DOWN}
const TOUCH_KEYS := {"Confirm": TouchCode.Key.OK, "Clear": TouchCode.Key.BACK}
## 未选中行的箭头用底槽色替换掉原调色板里的高亮色。
const NATIVE_TRACK_VALUE := Color("#196485")
const ARROW_SPRITES: Array[String] = ["common/ui_name/frame-001", "common/ui_name/frame-002"]
const ARROW_SOURCE_COLORS: Array[Color] = [Color("#00DBFF"), Color("#FFB251")]

var messages: Dictionary = {}
var _active_arrows: Array[Texture2D] = []
var _inactive_arrows: Array[Texture2D] = []
var _touch_panel: Array[Dictionary] = []


func configure(catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	if not _load_arrows(catalog):
		return false
	return $Content/Accept.configure(catalog, 0) and $Content/Back.configure(catalog, 1)


func live_regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not visible or int(paint.get("window_state", 0)) != OPEN_PHASE:
		return result
	var selected: int = int(paint.get("settings_selected", 0))
	for index in range(ROW_COUNT):
		var row: Node2D = get_node("Content/Row%d" % index)
		var areas := ["Decrease", "Increase"] if index == selected else ["Select"]
		for area_name: String in areas:
			var key := -3
			if area_name == "Increase":
				key = -4
			elif index != selected:
				key = TouchCode.Pad.UP if index < selected else TouchCode.Pad.DOWN
			var area: Control = row.get_node(area_name)
			var region := PrimeLayout._region(key, Rect2i(area.get_global_rect()))
			region.repeats = 1 if index == selected else absi(index - selected)
			result.append(region)
	if TouchControls.draws_window_keys(_touch_style(paint)):
		result.append(PrimeLayout._region(TouchCode.Key.OK, Rect2i($Content/Accept.get_global_rect())))
		result.append(PrimeLayout._region(TouchCode.Key.BACK, Rect2i($Content/Back.get_global_rect())))
	else:
		result.append_array(_touch_panel_regions())
	return result


## 游戏内入口（原生 style 35）没有窗口内图标，底部改用面板：方向盘四向与 OK／CLR。
func _touch_panel_regions() -> Array[Dictionary]:
	if _touch_panel.is_empty():
		var probe: Node = TOUCH_CONTROLS.instantiate()
		for node_name: String in TOUCH_DIRECTIONS:
			var control: Control = probe.get_node(node_name)
			_touch_panel.append(PrimeLayout._region(TOUCH_DIRECTIONS[node_name],
				Rect2i(control.get_rect())))
		for node_name: String in TOUCH_KEYS:
			var control: Control = probe.get_node(node_name)
			_touch_panel.append(PrimeLayout._region(TOUCH_KEYS[node_name],
				Rect2i(control.get_rect())))
		probe.free()
	return _touch_panel


func _touch_style(paint: Dictionary) -> int:
	return int(paint.get("settings_touch_style", TouchControls.Style.PRIME_WINDOW))


func present(paint: Dictionary) -> void:
	var state: int = int(paint.get("window_state", 0))
	visible = paint.scene == SCENE and state not in [-4, 0]
	if not visible:
		return
	if phase != state:
		phase = state
	$Bounds.modulate.a = PrimeLayout.phase_alpha(state)
	$Bounds/WindowTitle.text = messages[213]
	var window_keys := TouchControls.draws_window_keys(_touch_style(paint))
	$Content/Accept.visible = window_keys
	$Content/Back.visible = window_keys
	var open: bool = state == OPEN_PHASE
	$Content.visible = open
	if not open:
		return
	var selected: int = int(paint.get("settings_selected", 0))
	for index in range(ROW_COUNT):
		get_node("Content/Row%d" % index).present(index, paint.settings, selected, messages,
			_active_arrows, _inactive_arrows)


func _load_arrows(catalog: Object) -> bool:
	_active_arrows.clear()
	_inactive_arrows.clear()
	for index in range(ARROW_SPRITES.size()):
		var sprite_id := ARROW_SPRITES[index]
		var arrow: Texture2D = catalog.load_sprite(sprite_id)
		if arrow == null or arrow.get_size() != Vector2(4, 5):
			push_error("Native Prime settings arrow is unavailable: %s" % sprite_id)
			return false
		var image := arrow.get_image()
		if image == null or image.get_size() != Vector2i(4, 5):
			push_error("Native Prime settings arrow image is invalid: %s" % sprite_id)
			return false
		var inactive := image.duplicate()
		for y in range(5):
			for x in range(4):
				var pixel := image.get_pixel(x, y)
				if pixel.a == 0.0:
					continue
				if not pixel.is_equal_approx(ARROW_SOURCE_COLORS[index]):
					push_error("Native Prime settings arrow palette is invalid: %s" % sprite_id)
					return false
				inactive.set_pixel(x, y, NATIVE_TRACK_VALUE)
		_active_arrows.append(arrow)
		_inactive_arrows.append(ImageTexture.create_from_image(inactive))
	return true
