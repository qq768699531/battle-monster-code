extends Node
## 大型场景管理器：主菜单（标题＋Prime 页）、地图野外、战斗三个大场景，
## 同一时刻只让一个渲染。所有 `visible`／`process_mode` 的切换只在这里做，
## entry／field 只回报“进入了哪个大场景”。
##
## 三个场景的归属：
## - MENU：`main.tscn` 的 `Background`／`Title`／`PrimeView`；
## - FIELD：`entry._enter_field()` 创建的 `FieldRuntime`（地图、HUD、对话都在它下面）；
## - BATTLE：`FieldRuntime._open_battle()` 创建的 `BattleView`（野外的子节点）。
##
## 战斗是野外节点的子节点，所以切到 BATTLE 时野外本身仍可见，只收起它的其余画布；
## 回 MENU 时野外已被启动层释放，不需要再恢复。

enum Scene { NONE, MENU, FIELD, BATTLE }

var current := Scene.NONE

## 主菜单的三个图层。进入野外/战斗后整体不可见。
var _menu: Array[CanvasItem] = []
## 主菜单里带 ANI 的图层（标题背景那套 Buffer/Layer），只在主菜单推进动画。
var _menu_animated: Array[Node] = []
var _field: Node = null
var _battle: CanvasItem = null
## 战斗时收起的野外画布（World／HUD／对话…），按原可见性恢复。
var _field_hidden: Array[CanvasItem] = []


## 启动层在 `_ready()` 里登记主菜单图层；`animated` 是进入野外/战斗时要停推进的节点。
func bind_menu(nodes: Array, animated: Array = []) -> void:
	_menu.clear()
	for node in nodes:
		if node is CanvasItem:
			_menu.append(node)
	_menu_animated.clear()
	for node in animated:
		if node is Node:
			_menu_animated.append(node)


func enter_menu() -> void:
	current = Scene.MENU
	_field = null
	_battle = null
	_field_hidden.clear()
	_set_menu(true)


func enter_field(field: Node) -> void:
	current = Scene.FIELD
	_field = field
	_battle = null
	_set_menu(false)
	_restore_field()
	if field is CanvasItem:
		(field as CanvasItem).show()


func enter_battle(battle: CanvasItem) -> void:
	current = Scene.BATTLE
	_battle = battle
	_set_menu(false)
	if battle != null and is_instance_valid(battle):
		battle.show()
	_hide_field_for_battle()


func _set_menu(active: bool) -> void:
	for node in _menu:
		node.visible = active
	for node in _menu_animated:
		node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _hide_field_for_battle() -> void:
	_field_hidden.clear()
	if _field == null or not is_instance_valid(_field):
		return
	for child in _field.get_children():
		if child == _battle or not (child is CanvasItem):
			continue
		if (child as CanvasItem).visible:
			_field_hidden.append(child)
			(child as CanvasItem).visible = false


func _restore_field() -> void:
	for child in _field_hidden:
		if is_instance_valid(child):
			(child as CanvasItem).visible = true
	_field_hidden.clear()
