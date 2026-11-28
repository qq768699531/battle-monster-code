extends "res://tests/unit/gut_case.gd"

## 窗口／确认框管理器：一次只有一个窗口、一个确认框，背景层永远只有一层且压在栈底那一扇下面。
## 原生依据：`Menu_win_Box4_DrawWindow`（窗口）与 `Menu_win_Box2_DrawWindow`（确认框）各一扇，
## `Field_Basic_Capture` 的模糊背景在整个窗层会话里只有一张（`Map_Copy` 复用）。

const WindowScene = preload("res://engine/ui/window_transition/window_transition.tscn")
const WindowScript = preload("res://engine/ui/window_transition/window_transition.gd")
const Manager = preload("res://engine/ui/window_manager/ui_window_manager.gd")
const PrimeViewScene = preload("res://game/prime/startup/prime_view/prime_view.tscn")
const RuntimeConstants = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")

var _host: Control
var _first: Control
var _second: Control


func before_each() -> void:
	super()
	_host = Control.new()
	_host.size = Vector2(400, 240)
	add_child_autofree(_host)
	_first = _window()
	_second = _window()


func _window() -> Control:
	var window: Control = WindowScene.instantiate()
	_host.add_child(window)
	window.show()
	return window


## 背景层是窗口的兄弟、排在窗口紧前面：同父节点、同 z_index ⇒ 压住场景但不盖窗口。
func test_shade_sits_directly_beneath_the_open_window() -> void:
	_first.open_window()
	var shade: Control = UiWindows.shade()
	assert_not_null(shade, "开窗后建出唯一一层背景")
	assert_eq(shade.get_parent(), _host, "背景层挂到窗层所在的宿主")
	assert_eq(shade.get_index() + 1, _first.get_index(), "背景层排在窗层紧前面")
	assert_true(shade.is_visible_in_tree(), "有窗层时背景层可见")


## 同一宿主同类（都是 Box4 窗口）只能有一扇可见：后开的把先开的顶掉并收起。
func test_a_second_window_replaces_the_first() -> void:
	_first.open_window()
	_second.open_window()
	assert_false(_first.visible, "旧窗口出栈后由管理器收起")
	assert_true(_second.visible, "新窗口接管")
	assert_eq(UiWindows.top(Manager.Kind.WINDOW), _second, "窗口槽只剩新的这一扇")


## Box2 确认框占的是另一个槽：它叠在窗口上，窗口不出栈，背景层仍在窗口下面。
func test_a_dialog_stacks_on_the_window() -> void:
	_first.open_window()
	_second.kind = WindowScript.BoxKind.BOX2
	_second.open_window()
	assert_true(_first.visible, "确认框不顶掉窗口")
	assert_eq(UiWindows.top(Manager.Kind.DIALOG), _second, "确认框占确认框的槽")
	var shade: Control = UiWindows.shade()
	assert_eq(shade.get_index() + 1, _first.get_index(), "背景层仍压在最底层窗层下面")


## `keep_previous` 的旧窗只收起不出栈：本窗关掉后再露出来（菜单收 Frame 开二级窗那一类）。
func test_kept_window_returns_when_the_new_one_closes() -> void:
	_first.open_window()
	_second.keep_previous = true
	_second.open_window()
	assert_false(_first.visible, "被保留的旧窗先收起")
	_second.hide()
	assert_true(_first.visible, "新窗关掉后旧窗恢复")
	assert_eq(UiWindows.top(Manager.Kind.WINDOW), _first, "栈顶回到旧窗")


## 最后一扇窗层收起时背景层跟着收起，冻结判据同时变假。
func test_shade_leaves_with_the_last_window() -> void:
	_first.open_window()
	assert_true(UiWindows.any_open(), "有窗层时野外要停住推进")
	_first.hide()
	assert_false(UiWindows.any_open(), "窗层收起后恢复推进")
	assert_false(UiWindows.shade().is_visible_in_tree(), "背景层跟着收起")


## 主菜单的环境设定／帮助／支持／网络连接共用同一个 `PrimeView` 换页画，换页不发
## `visibility_changed`，靠 `present()` 自己登记／注销；回到标题页要出栈。
func test_prime_pages_take_the_window_slot() -> void:
	var view: Node2D = PrimeViewScene.instantiate()
	var host := Control.new()
	host.size = Vector2(400, 240)
	add_child_autofree(host)
	host.add_child(view)
	view.get_node("Settings").messages = {213: "环境设定"}
	view.present({"scene": RuntimeConstants.SETTINGS, "window_state": 2})
	assert_eq(UiWindows.top(Manager.Kind.WINDOW), view, "环境设定页占窗口槽")
	var shade: Control = UiWindows.shade()
	assert_eq(shade.get_index() + 1, view.get_index(), "背景层排在 PrimeView 前面")
	view.present({"scene": RuntimeConstants.TITLE, "window_state": 0,
		"menu_open": true, "frame": 0})
	assert_false(UiWindows.any_open(), "回标题页就出栈")
	assert_eq(UiWindows.top(Manager.Kind.WINDOW), null)
