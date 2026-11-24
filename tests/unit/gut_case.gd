extends GutTest
## 单进程连跑全部用例时，前一个用例留在 root 的节点、改过的窗口尺寸与时间倍率
## 会污染后一个用例；这里在每个用例结束时复位。

static var _autoloads: Array[String] = []


func before_each() -> void:
	hide_runner_gui()


func after_each() -> void:
	reset_scene()


## GUT 的 runner 界面是画在 root viewport 上的 CanvasLayer，会盖住用例自己截的
## 像素；不隐藏的话所有 get_tree().root.get_texture() 断言拿到的都是测试面板。
func hide_runner_gui() -> void:
	var layer := get_tree().root.get_node_or_null("GutRunner/GutLayer")
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = false


## 释放用例遗留在 root 的节点，并复位全局状态。
func reset_scene() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	var root := get_tree().root
	# 全局触控反馈是 autoload，不会被清掉：按焦点丢失复位按点与残留特效，
	# 否则上一个用例按住的手指会让下一个用例的点击被当成第二根手指；
	# 主帧间隔也会被 Main 按速度档位改写，这里回到 autoload 的基准值。
	var feedback := root.get_node_or_null("NativeTouchFeedback")
	if feedback != null:
		feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		feedback.frame_interval_ms = feedback.DEFAULT_FRAME_INTERVAL_MS
	for child in root.get_children():
		if _is_kept(child):
			continue
		root.remove_child(child)
		child.free()
	var default_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	if DisplayServer.window_get_size() != default_size:
		DisplayServer.window_set_size(default_size)


func _is_kept(child: Node) -> bool:
	if child == self or child.is_ancestor_of(self):
		return true
	var node_name := String(child.name)
	if node_name.begins_with("@"):
		return true
	return node_name in _autoload_names()


static func _autoload_names() -> Array[String]:
	if not _autoloads.is_empty():
		return _autoloads
	for property in ProjectSettings.get_property_list():
		var setting := String(property.name)
		if setting.begins_with("autoload/"):
			_autoloads.append(setting.trim_prefix("autoload/"))
	return _autoloads
