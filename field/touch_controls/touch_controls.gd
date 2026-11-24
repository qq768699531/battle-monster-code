extends Node2D
## 方向盘与 OK/CLR 触控区，命中区域读取真实控件。

signal key_pressed(key: int)

@export var interactive := false

const PAD := Rect2(0, 140, 100, 100)
## 方向盘整块命中区的哨兵键：命中时按触点相对中心的方向现算 `TouchCode.Pad` 的四向码。
const PAD_KEY := 158339877
const DIRECTIONS := {TouchCode.Pad.UP: Vector2i.UP, TouchCode.Pad.DOWN: Vector2i.DOWN,
	TouchCode.Pad.LEFT: Vector2i.LEFT, TouchCode.Pad.RIGHT: Vector2i.RIGHT}
## `EFC_mainTouchSTYLE` 返回值的位：`EFC_mainTouchDRAW` 按位画方向盘与页面按钮，
## `Menu_win_Box_DrawKeyInfo` 按位画窗口内的 OK／BACK 图标。
enum Mask {
	PAD = 0x1,            ## 半透明方向盘四向（`EFC_mainTouchBUTTON1(17, h-50, -3)` 一族）
	BACK = 0x2,           ## CLR／返回（`EFC_mainTouchBUTTON2(1, width-25, h-110, -16)`）
	OK = 0x20,            ## OK（`EFC_mainTouchBUTTON1(width-40, h-50, -5)`）
	WINDOW_KEYS = 0x1000, ## 窗口内 OK／BACK 图标（`Menu_win_Box_DrawKeyInfo:12` 的门控位）
}
## 页面用到的整份 style（按钮按各自的 `style_mask` 位选中）：地图页的公会／城镇／野外，
## 游戏内菜单与 OPTION 环境设定的 35（`PAD_KEYS`），Prime 画布默认分支的 4131（`PRIME_WINDOW`）。
enum Style {
	FIELD_GUILD = 0x25,
	FIELD_TOWN = 0x35,
	FIELD_WILD = 0x3d,
	NONE = 0x0,
	ARROWS_BACK = 0x3,
	PAD_KEYS = Mask.PAD | Mask.OK | Mask.BACK,
	PRIME_WINDOW = Mask.WINDOW_KEYS | Mask.PAD | Mask.OK | Mask.BACK,
}

var regions: Array[Dictionary] = []
var _buttons: Array[Dictionary] = []
var _style := -1
var held_key := 0
var _pointer_index := -1


func _ready() -> void:
	for control: Control in _controls():
		control.gui_input.connect(_on_control_input.bind(control))
		if interactive:
			control.mouse_filter = Control.MOUSE_FILTER_STOP


func _controls() -> Array[Control]:
	var result: Array[Control] = []
	for child in get_children():
		if child is Control:
			result.append(child)
	return result


## 运行期开关：Prime 环境设定页（原生 style 35）把面板留在 228×208 窗口外的两侧，
## 判点交给 Prime 侧（`settings_view.live_regions`），面板只负责画、把点击让给宿主。
func set_interactive(value: bool) -> void:
	if value == interactive:
		return
	interactive = value
	if not is_node_ready():
		return
	if not value and _pointer_index != -1:
		_release_pointer()
	for control: Control in _controls():
		control.mouse_filter = Control.MOUSE_FILTER_STOP if value \
			else Control.MOUSE_FILTER_IGNORE


## `Menu_win_Box_DrawKeyInfo:12`：只有 style 含 `WINDOW_KEYS` 才在窗口内画 OK／BACK，
## 这时 `EFC_mainTouchDRAW` 在 `:29` 直接跳过方向盘与页面按钮。
static func draws_window_keys(style: int) -> bool:
	return style & Mask.WINDOW_KEYS != 0


func _input(event: InputEvent) -> void:
	if _pointer_index == -1:
		return
	if event is InputEventScreenTouch and event.index == _pointer_index and \
			(not event.pressed or event.canceled):
		_release_pointer()
	elif event is InputEventMouseButton and _pointer_index == -2 and \
			event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and \
			event.device != InputEvent.DEVICE_ID_EMULATION:
		_release_pointer()


func _notification(what: int) -> void:
	if _pointer_index != -1 and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or \
			(what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree())):
		_release_pointer()


func _release_pointer() -> void:
	_pointer_index = -1
	present(_style, 0)


func _on_control_input(event: InputEvent, control: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and \
			event.device != InputEvent.DEVICE_ID_EMULATION:
		if not event.pressed or _pointer_index != -1:
			return
		_pointer_index = -2
	elif event is InputEventScreenTouch:
		if not event.pressed or event.canceled or _pointer_index != -1:
			return
		_pointer_index = event.index
	elif event is InputEventMouseMotion:
		if _pointer_index != -2 or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
	elif event is InputEventScreenDrag:
		if _pointer_index != event.index:
			return
	else:
		return
	var keys := touch_keys(control.get_transform() * event.position)
	var key := 0 if keys.is_empty() else keys[0]
	if key == held_key:
		return
	present(_style, key)
	if key != 0:
		key_pressed.emit(key)


static func field_style(map_group: int, game_mode: int = 12) -> int:
	if map_group == 6:
		return Style.FIELD_GUILD
	return Style.FIELD_TOWN if game_mode in [25, 26] else Style.FIELD_WILD


func present(style: int, pressed_key: int) -> void:
	if style != _style:
		_style = style
		_rebuild()
	held_key = pressed_key
	for button: Dictionary in _buttons:
		button.node.set_pressed(pressed_key == button.key)
	visible = style != 0


func touch_keys(point: Vector2) -> Array[int]:
	var keys: Array[int] = []
	for index in range(regions.size() - 1, -1, -1):
		var region: Dictionary = regions[index]
		region.rect = region.node.get_rect()
		if not region.rect.has_point(point):
			continue
		if region.key == PAD_KEY:
			var offset: Vector2 = point - region.rect.get_center()
			keys.append((TouchCode.Pad.UP if offset.y < 0 else TouchCode.Pad.DOWN) if absf(offset.x) < absf(offset.y)
				else (TouchCode.Pad.LEFT if offset.x < 0 else TouchCode.Pad.RIGHT))
		else:
			keys.append(region.key)
	return keys


func _rebuild() -> void:
	_buttons.clear()
	regions.clear()
	for button in get_children():
		if button == $Pad:
			continue
		button.visible = _style & button.style_mask != 0
		if not button.visible:
			continue
		_buttons.append({"key": button.key, "node": button, "sprites": button.sprites})
		if button.register_touch:
			regions.append({"key": button.key,
				"rect": button.get_rect(), "node": button})
		elif button.name == "Down":
			regions.append({"key": PAD_KEY, "rect": $Pad.get_rect(), "node": $Pad})
