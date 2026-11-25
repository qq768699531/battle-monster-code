extends "res://engine/ui/window_transition/window_transition.gd"
## 道具使用／合成的二级选择窗。
##
## 原生 `Menu_Item_mPaint` 的 quest_layer 9／10（选「使用」的目标、技能书合成）不再调
## `Menu_win_DrawBasic`，而是 `Menu_Monster_DrawList(JC_fxt2Return(184), ...)`：
## 开一个 228×214 的 Box4 窗（`Menu_win_Box4_DrawWindow(..., 228, 214, ..., 1, 16)`，标题
## `common/msg.fxt` 184「精灵球」），正文是 `Menu_Party_DrawList` 的球列表 + `Menu_Monster_Draw2`
## 的怪物资料。所以这一层在场景里独立成一个窗口，菜单窗框与页签同时收起，屏幕上只留它。
##
## 正文直接放一份 `party.tscn`，渲染与按键都转发给 `party.gd`，本脚本不复制任何列表／资料逻辑。
## 原生两处的绘制只有窗口内 y 偏移不同（队伍页 `DrawList(rect+8, rect+50)`、本窗
## `DrawList(rect+8, rect+24)`，资料同理差 13），所以场景里把 `Party` 上移 13 即可对齐。

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
	# 原生这一层只画 `Menu_Party_DrawList` 与 `Menu_Monster_Draw2`：队伍页的立绘、空位提示、
	# 动作表与装备栏都不在窗内（列装／被动的切换只属于队伍页）。
	for path: String in ["Portrait", "ActionAnchor", "EmptyNotice",
			"Monster/Equipment", "Monster/Toggle"]:
		(_party.get_node(path) as Control).hide()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	host._render_content()
