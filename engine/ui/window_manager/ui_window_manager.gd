extends Node
## 窗口与确认框的唯一管理者（autoload `UiWindows`）。
##
## 原生只有一套窗层：一帧里当前页 `Menu_win_Box4_DrawWindow`（窗口）与弹出框
## `Menu_win_Box2_DrawWindow`（确认框）各最多一扇；开窗前 `Field_Basic_Capture`／
## `Battle_info_Capture` 把整帧画面写成半透明黑 + 模糊的背景层（`MapRes.map_scratch_image`），
## 之后所有窗层每帧 `Map_Copy()` 都画同一张。重制里窗框仍由各页自己的 `WindowTransition`
## 场景承担，本管理器只做三件事：
##
## 1. **入栈／出栈**：同一宿主（窗层的 `get_parent()`）同一类（`Kind`）里只允许一扇可见，
##    后入栈的把先入栈的顶掉；关窗时窗层自己出栈，栈顶若是被收起的那一扇就恢复它。
## 2. **背景层**：只要栈里还有可见的窗层，就把唯一的 `ScreenShade` 挂在**最底层那一扇的
##    紧下方**（同一个父节点、同 `z_index`、排在它前面），所以背景只压暗一次、也只模糊
##    到窗层下面的场景；确认框叠在窗口上时不会把窗口本身也糊掉。最后一扇收起才隐藏。
## 3. **冻结判据**：`any_open()` 给野外判断「现在该停住推进」。
##
## 旧窗层的去向由开窗方决定（`Previous`）：`DISMISS` 是出栈（管理器把它收起，调用方自己
## 关窗／释放），`KEEP_HIDDEN` 是留在栈里先收起，本窗关掉后自动恢复显示。`WindowTransition`
## 用 `keep_previous` 声明，默认出栈——与原生「一页换一页」一致；菜单收起 `Frame` 后开二级
## 选择窗那一类「旧的还要回来」的页面才用 `KEEP_HIDDEN`。

## 窗层种类：窗口（原生 Box4）与确认框（原生 Box2）。
enum Kind { WINDOW, DIALOG }
## 旧窗层的去向。
enum Previous {
	## 出栈：管理器把旧窗层收起并停止追踪，调用方负责关窗／释放。
	DISMISS,
	## 留在栈里并收起，本窗层出栈时恢复显示。
	KEEP_HIDDEN,
}

const SCREEN_SHADE_SCENE := preload("res://engine/ui/screen_shade/screen_shade.tscn")
## 逻辑分辨率：背景层按整屏铺，和 400×240 的窗口坐标系一致。
const LOGICAL_SIZE := Vector2(400, 240)

## 入栈顺序（栈底在前）。`host` 记入栈时的父节点：出栈时窗层可能已经被换父或释放。
var _entries: Array[Dictionary] = []
## 管理器自己收起的窗层：紧随其后的 `visibility_changed` 不算调用方关窗。
var _manager_hidden: Array[CanvasItem] = []
## 整个栈共用的背景层；最后一扇窗层收起后保留实例、只隐藏，下次开窗接着用。
var _shade: ScreenShade
## 背景层挂载会动树（reparent／move_child），不能在可见性传播、节点进出树的途中做，统一推到空闲帧。
var _shade_queued := false


## 窗口自己状态变了（可见性／开合相位）就调它同步一次：开着的入栈，关掉的出栈。
## 管理器只认窗口的契约方法 `window_open()`／`window_kind()`／`window_previous()`，不认具体窗类；
## 外面（宿主页、调用方）不需要也不应该手工登记窗口。
func sync(window: CanvasItem) -> void:
	if window == null or not is_instance_valid(window) or not window.is_inside_tree():
		return
	if bool(window.call("window_open")):
		_push(window, int(window.call("window_kind")), int(window.call("window_previous")))
	else:
		_pop(window)


## 窗层入栈。同一宿主同一类里已经有一扇时按 `previous` 收起它，再让 `layer` 成为新的栈顶。
## 重复入栈同一层只刷新背景（页面重开动画时不该再顶掉自己）。只由 `sync()` 调用。
func _push(layer: CanvasItem, kind: Kind, previous: Previous) -> bool:
	if layer == null or not is_instance_valid(layer):
		return false
	if _index_of(layer) >= 0:
		_sync_shade()
		return false
	var host := layer.get_parent()
	_supersede(host, kind, previous)
	_entries.append({"layer": layer, "host": host, "kind": kind, "hidden": false})
	# 窗层自己变可见／不可见都要回流：可见时补挂背景层（宿主可能晚一帧才 show 整页），
	# 不可见时（关窗动画播完、整页被宿主收起）就是出栈信号。
	var on_visibility := _on_visibility_changed.bind(layer)
	if not layer.visibility_changed.is_connected(on_visibility):
		layer.visibility_changed.connect(on_visibility)
	var on_exit_tree := _on_tree_exited.bind(layer)
	if not layer.tree_exited.is_connected(on_exit_tree):
		layer.tree_exited.connect(on_exit_tree)
	_sync_shade()
	return true


## 窗层出栈：若它当时是该宿主该类的栈顶，栈里剩下的最新一扇（被 `KEEP_HIDDEN` 收起的）
## 恢复显示，再把背景层挪到新的最底层下面。只由 `sync()` 与树/可见性回流调用。
func _pop(layer: CanvasItem) -> void:
	# 管理器自己收起的那一扇：它的可见性变化不算关窗，不能把自己从栈里摘掉。
	if _manager_hidden.has(layer):
		return
	var index := _index_of(layer)
	if index < 0:
		return
	var entry: Dictionary = _entries[index]
	_entries.remove_at(index)
	if bool(entry.hidden):
		# 被收起的那一扇只是离开栈，不是关窗：不再有「恢复旧的」这回事。
		_sync_shade()
		return
	var latest := _latest(int(entry.kind), entry.host)
	if latest >= 0 and bool(_entries[latest].hidden):
		_entries[latest].hidden = false
		var older: CanvasItem = _entries[latest].layer
		if is_instance_valid(older):
			older.show()
	_sync_shade()


## 该类当前可见的栈顶（`KEEP_HIDDEN` 收起的层不算）。
func top(kind: Kind) -> CanvasItem:
	var found: CanvasItem = null
	for entry: Dictionary in _entries:
		if int(entry.kind) == int(kind) and not bool(entry.hidden):
			found = entry.layer
	return found


## 当前是否还有可见的窗口／确认框（野外据此停住推进）。
func any_open() -> bool:
	for entry: Dictionary in _entries:
		var layer: CanvasItem = entry.layer
		if is_instance_valid(layer) and layer.is_visible_in_tree():
			return true
	return false


## 整个栈共用的背景层；还没建过或已被宿主释放时为 null。
func shade() -> ScreenShade:
	return _shade if _shade != null and is_instance_valid(_shade) else null


## 入栈顺序的快照（栈底在前），测试与诊断用。
func entries() -> Array:
	return _entries.duplicate()


## 一扇新窗层要进来：同宿主同类的旧窗层按 `previous` 收起。
func _supersede(host: Node, kind: Kind, previous: Previous) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if entry.host != host or int(entry.kind) != int(kind):
			continue
		if previous == Previous.DISMISS:
			_entries.remove_at(index)
		_hide_by_manager(entry)


## 管理器收回一扇窗层的可见性。`_manager_hidden` 只在这一帧生效：随后的
## `visibility_changed` 由 `_on_visibility_changed` 忽略，不会把它当成关窗。
func _hide_by_manager(entry: Dictionary) -> void:
	var layer: CanvasItem = entry.layer
	entry.hidden = true
	if not is_instance_valid(layer) or not layer.visible:
		return
	_manager_hidden.append(layer)
	layer.hide()
	_manager_hidden.erase(layer)


func _on_visibility_changed(layer: CanvasItem) -> void:
	if _index_of(layer) < 0 or _manager_hidden.has(layer):
		return
	if is_instance_valid(layer) and not layer.is_visible_in_tree():
		_pop(layer)
	else:
		_sync_shade()


func _on_tree_exited(layer: CanvasItem) -> void:
	_pop(layer)


## 背景层：可见时挂在最底层那一扇窗层的紧下方，没有窗层就隐藏。
func _sync_shade() -> void:
	if _shade_queued:
		return
	_shade_queued = true
	_apply_shade.call_deferred()


func _apply_shade() -> void:
	_shade_queued = false
	var bottom := _bottom_layer()
	if bottom == null:
		if _shade != null and is_instance_valid(_shade):
			_shade.hide()
		return
	var shade_instance := _ensure_shade()
	_mount_under(shade_instance, bottom)
	shade_instance.show()


## 最底层的可见窗层：按有效 `z_index` 取最小，同值取先入栈的（树序＝绘制序）。
func _bottom_layer() -> CanvasItem:
	var bottom: CanvasItem = null
	var bottom_z := 0
	for entry: Dictionary in _entries:
		var layer: CanvasItem = entry.layer
		if not is_instance_valid(layer) or not layer.is_visible_in_tree():
			continue
		var z := _effective_z(layer)
		if bottom == null or z < bottom_z:
			bottom = layer
			bottom_z = z
	return bottom


## 绝对 `z_index`：`z_as_relative` 的层把祖先的 `z_index` 累加进来，才能跨宿主比较。
func _effective_z(layer: CanvasItem) -> int:
	var z := 0
	var node: Node = layer
	while node is CanvasItem:
		var item := node as CanvasItem
		z += item.z_index
		if not item.z_as_relative:
			break
		node = node.get_parent()
	return z


func _ensure_shade() -> ScreenShade:
	if _shade == null or not is_instance_valid(_shade):
		_shade = SCREEN_SHADE_SCENE.instantiate()
	return _shade


## 把背景层摆到 `layer` 前面一格：同父节点、同 `z_index`，所以它压住窗层下面的场景，
## 又不会盖住窗层本身；确认框是窗层的子节点时也仍然在这张背景之上。
func _mount_under(shade_instance: ScreenShade, layer: CanvasItem) -> void:
	var parent := layer.get_parent()
	if parent == null:
		return
	if shade_instance.get_parent() == null:
		parent.add_child(shade_instance)
	elif shade_instance.get_parent() != parent:
		shade_instance.reparent(parent, false)
	else:
		# 先挪到末尾，再插到窗层前面；否则从窗层前面往同一位挪会把它推到窗层之后。
		parent.move_child(shade_instance, parent.get_child_count() - 1)
	parent.move_child(shade_instance, layer.get_index())
	shade_instance.z_index = layer.z_index
	shade_instance.z_as_relative = layer.z_as_relative
	# 背景层固定铺满 400×240 逻辑屏幕，不跟父矩形走：图鉴的 `Book` 根节点没有尺寸，
	# 按父矩形铺会得到 0×0。
	shade_instance.set_anchors_preset(Control.PRESET_TOP_LEFT)
	shade_instance.size = LOGICAL_SIZE
	shade_instance.global_position = Vector2.ZERO


func _index_of(layer: CanvasItem) -> int:
	for index in range(_entries.size()):
		if _entries[index].layer == layer:
			return index
	return -1


## 同一宿主同一类里最后入栈的一层（可能已被 `KEEP_HIDDEN` 收起）。
func _latest(kind: int, host: Node) -> int:
	var found := -1
	for index in range(_entries.size()):
		if int(_entries[index].kind) == kind and _entries[index].host == host:
			found = index
	return found
