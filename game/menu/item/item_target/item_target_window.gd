extends "res://engine/ui/window_transition/window_transition.gd"
## 道具使用／合成的二级选择窗。
##
## 原生 `Menu_Item_mPaint` 的 quest_layer 9／10（选「使用」的目标、技能书合成）不再调
## `Menu_win_DrawBasic`，而是走 `Menu_Monster_DrawList` 的独立窗。重制里这一层是
## `WindowTransition` 窗口，正文直接放一份 `party.tscn`，渲染、选中、滚动、确认全部由
## `party.gd` 负责，本脚本不复制任何列表／资料逻辑，也不再裁剪界面的任何部件。
##
## 窗口取与队伍页一致的 228×240（原生该层是 228×214 并裁掉立绘与空格，这里按与 PARTY 页
## 一致的要求不复刻裁剪），`Party` 保持原坐标，所以立绘、六个精灵格位、球数／PARTY 点、
## 装备／被动开关与 PARTY 页逐像素一致；窗口只负责开合动画与标题。

const Msg = preload("res://engine/ui/msg/msg.gd")

var host: Control
## 菜单是否已申请打开本窗（关窗动画期间为假，但 `is_active()` 仍算活动）。
var _opened := false
var _party


func _ready() -> void:
	super()
	host = get_parent()
	$Bounds/Title.text = AssetCatalog.text_message(Msg.SOURCE, Msg.Id.ITEM_TARGET_TITLE)
	_party = $Content/Party
	# 队伍页的 `host` 按父节点取，这里是窗口的 `Content`，改成菜单宿主。
	_party.host = host
	# 动作表按 `get_parent()` 三层取宿主（队伍页 → 菜单），窗内少一层，显式指定。
	$Content/Party/ActionAnchor/Actions.host = host
	transition_finished.connect(_transition_finished)


## 菜单确认「使用／合成」后调用；重复调用只刷新，不重播开窗动画。
func open_target() -> void:
	if _opened:
		return
	_opened = true
	show()
	open_window()


## 取消或结算后调用；关窗动画结束时才隐藏并交还菜单窗框。
func close_target() -> void:
	if not _opened:
		return
	_opened = false
	close_window()


func is_active() -> bool:
	return _opened or is_transitioning()


func handle_key(key: String) -> bool:
	if is_transitioning():
		return true
	return _party.handle_key(key)


func refresh() -> void:
	_party.call("_render_party")


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	host._render_content()
