extends Node2D
## Prime（标题）页面宿主：只做配置、分发、汇总命中区与整层可见性，再把这一层登记成窗口。
##
## 每个子页的窗口／绘制／命中区都在自己的目录里，宿主不写任何一页的实现：
## - 标题 `title_view`、启动欢迎页与空间不足页 `startup_view`、环境设定 `settings_view`；
## - 对话框与警告 `dialog_view`；帮助 `text_page_view`、支持 `info_view`；
## - 网络连接与提示页 `notice_view`（网络页的按钮／子页矩形与页脚命中区都在 `notice_view.regions()` 里汇总）；
## - 存档槽 `slot_view`、战场区域 `battle_zone_scene`、市场／未知岛／邮箱各自 `*_view`。
##
## 子页统一实现 `present(paint)`；需要命中区的页再实现 `regions(paint)`，不在本页范围时返回空。
## 命中区优先级＝`_region_pages` 的顺序，对话框／警告浮层最后覆盖整页。

const RuntimeConstants = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const Msg = preload("res://engine/ui/msg/msg.gd")
const WindowTransitionScript = preload("res://engine/ui/window_transition/window_transition.gd")

## 主菜单开出来的子页（原生都画成 `Menu_win_Box4_DrawWindow` 的窗）：环境设定／帮助／支持／
## 网络连接，以及网络页弹出的两张网络提示页。这些页是同一个 `PrimeView` 换页画出来的，按「一扇窗口」
## 登记给 `UiWindows`，半透明 + 模糊背景才会铺在标题页／野外下面。
## 标题页与存档槽页不登记：前者是主菜单本身，后者是整页换屏而不是弹窗。
const WINDOW_SCENES := [
	RuntimeConstants.SETTINGS, RuntimeConstants.METHOD, RuntimeConstants.INFO,
	RuntimeConstants.NETWORK, RuntimeConstants.PRESENT, RuntimeConstants.ZONE,
]

## 分发顺序：每个子页自己决定 `visible`。
@onready var _pages: Array[Node] = [
	$Title, $Startup, $Settings, $Dialogs, $TextPage, $Info, $Notice,
	$Slots, $BattleZone, $Market, $Island, $Mail,
]
## 只有这些页自己产出命中区；对话框／警告由 `_dialogs` 单独覆盖，其余页的命中区由网络页汇总。
@onready var _region_pages: Array[Node] = [
	$Startup, $Settings, $TextPage, $Info, $Notice, $Slots,
]
## 需要装资源／文案的子页（标题页只有展示，没有可装的东西）。
@onready var _configure_pages: Array[Node] = [
	$Startup, $Settings, $Dialogs, $TextPage, $Info, $Notice,
	$Slots, $BattleZone, $Market, $Island, $Mail,
]
@onready var _dialogs: Node = $Dialogs
@onready var _notice: Node = $Notice
@onready var _request: Node = $Request
@onready var _slots: Node = $Slots

var messages: Dictionary = {}
var regions: Array[Dictionary] = []
var last_error := ""


## 各页自己装自己的贴图／文案；任何一页失败就把它自己的 `last_error` 交出去。
func configure(catalog: Object) -> bool:
	messages = catalog.text_messages(Msg.SOURCE)
	_notice.bind_network_pages(_slots, $BattleZone, $Market, $Island, $Mail)
	for page: Node in _configure_pages:
		if not page.configure(catalog, messages):
			last_error = str(page.get("last_error"))
			if last_error.is_empty():
				last_error = "Prime page failed: %s" % page.name
			return false
	return true


## 分发一帧 paint：先各页自绘，再取当前页的命中区，最后决定整层可见性与窗口登记。
func present(paint: Dictionary) -> void:
	for page: Node in _pages:
		page.present(paint)
	_request.present_page(paint, messages)
	if _dialogs.overlay_active(paint):
		regions.assign(_dialogs.regions(paint))
	else:
		regions.clear()
		for page: Node in _region_pages:
			var page_regions: Array[Dictionary] = page.regions(paint)
			if not page_regions.is_empty():
				regions.assign(page_regions)
				break
	visible = _any_page_visible() or _dialogs.overlay_active(paint)
	_sync_window(paint)


## 每个子页自己决定 `visible`；整层只在有页时渲染，比维护一张场景号清单更不容易漏。
func _any_page_visible() -> bool:
	for page: Node in _pages:
		if (page as CanvasItem).visible:
			return true
	return false


## 页由 `paint.scene` 切换，同一个节点换页时一直可见，`visibility_changed` 不会发，所以每次
## `present()` 都显式登记／注销一次；重复调用在管理器里是幂等的（同一层入栈即返回）。
func _sync_window(paint: Dictionary) -> void:
	var scene := int(paint.get("scene", -1))
	if is_inside_tree() and is_visible_in_tree() and scene in WINDOW_SCENES:
		WindowTransitionScript.register_window(self)
	else:
		WindowTransitionScript.unregister_window(self)


## 网络提示页的文案由 `notice_view` 自己生成（原生 `Prime_Notice_*` 的标题与正文）。
func notice_resource(target: int) -> Dictionary:
	return _notice.notice_resource(target)


## entry 推进的存档槽进度；字段本身留在 `slot_view`。
var slot_progress: Array[Dictionary]:
	get: return _slots.slot_progress
	set(value): _slots.slot_progress = value
