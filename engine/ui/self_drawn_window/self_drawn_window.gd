extends Control
## 自绘全屏窗的基类：没有窗框组件、整页自己画的弹窗（例如游戏菜单）也按一扇窗口入栈。
##
## 窗口自己声明契约：可见即开、隐藏即关；`window_kind_slot` 与 `keep_previous` 在场景里声明。
## 管理器只认 `window_open()`／`window_kind()`／`window_previous()`，宿主页与调用方不再插手，
## 也不需要在 `_ready()` 里接可见性信号去登记窗口。

const UiWindowManager = preload("res://engine/ui/window_manager/ui_window_manager.gd")

## 本窗占哪个槽：窗口（默认）还是确认框。
@export var window_kind_slot := UiWindowManager.Kind.WINDOW
## 旧窗层的去向，语义与 `WindowTransition.keep_previous` 相同。
@export var keep_previous := false


func _enter_tree() -> void:
	_sync_membership()


## 可见性就是窗口的开合：整页被宿主收起、被隐藏，都从这里出栈。
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_membership()


func window_open() -> bool:
	return is_inside_tree() and is_visible_in_tree()


func window_kind() -> int:
	return window_kind_slot


func window_previous() -> int:
	return UiWindowManager.Previous.KEEP_HIDDEN if keep_previous else UiWindowManager.Previous.DISMISS


## 自己状态变了就向管理器同步一次；栈的规则不在页面里写。
func _sync_membership() -> void:
	var manager := _window_manager()
	if manager != null:
		manager.call("sync", self)


## 管理器是 autoload；编辑器预览里没有 autoload 时返回 null。
static func _window_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("UiWindows")
