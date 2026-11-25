extends "res://engine/ui/window_transition/window_transition.gd"
## 道具使用／合成的二级选择窗。
##
## 原生 `Menu_Item_mPaint` 的 quest_layer 9／10（选「使用」的目标、技能书合成）不再调
## `Menu_win_DrawBasic`，而是 `Menu_Monster_DrawList(JC_fxt2Return(184), ...)`：
## 开一个 228×214 的 Box4 窗（`Menu_win_Box4_DrawWindow(..., 228, 214, ..., 1, 16)`，标题
## `common/msg.fxt` 184「精灵球」），正文是 `Menu_Party_DrawList` 的球列表 + `Menu_Monster_Draw2`
## 的怪物资料。所以这一层在场景里独立成一个窗口，菜单窗框与页签同时收起，屏幕上只留它。
##
## 正文不再另做一份：`menu.tscn` 里唯一的 `party` 页在开窗时挂到本窗 `Content` 下，
## 关窗动画结束后原样还回菜单。原生两处的绘制只有窗口内 y 偏移不同（队伍页
## `DrawList(rect+8, rect+50)`、本窗 `DrawList(rect+8, rect+24)`，资料同理差 13），
## 所以挂进来时把 `party` 上移 13，离开时归零。

const Msg = preload("res://engine/ui/msg/msg.gd")

var host: Control
## 菜单是否已申请打开本窗（关窗动画期间为假，但 `is_active()` 仍算活动）。
var _opened := false
## 开窗时从菜单借来的 `party` 页；关窗结束归还，全程只有这一个实例。
var _party
## `party` 原本在菜单里的子节点序号，归还时放回原位以免盖到触控面板上。
var _party_slot := -1


func _ready() -> void:
	super()
	host = get_parent()
	$Bounds/Title.text = AssetCatalog.text_message(Msg.SOURCE, Msg.Id.ITEM_TARGET_TITLE)
	transition_finished.connect(_transition_finished)


## 菜单确认「使用／合成」后调用；重复调用只刷新，不重播开窗动画。
func open_target() -> void:
	if _opened:
		return
	_opened = true
	show()
	open_window()


## 取消或结算后调用；关窗动画结束时才隐藏、归还队伍页并交还菜单窗框。
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
	if _party == null:
		return false
	return _party.handle_key(key)


## 把菜单里的 `party` 页挂进窗口正文（同一份页面与脚本，不复制场景）。
func attach_party(party: Control) -> void:
	if _party == party:
		return
	if _party != null:
		detach_party()
	var parent := party.get_parent()
	if parent == null:
		return
	_party = party
	_party_slot = party.get_index()
	parent.remove_child(party)
	$Content.add_child(party)
	party.position = Vector2(0, -13)
	party.show()


## 关窗后把 `party` 页还回菜单原来的位置。
func detach_party() -> void:
	if _party == null:
		return
	var party: Control = _party
	_party = null
	party.hide()
	party.position = Vector2.ZERO
	if party.get_parent() == $Content:
		$Content.remove_child(party)
	if not is_instance_valid(host) or not host.is_inside_tree():
		return
	host.add_child(party)
	if _party_slot >= 0:
		host.move_child(party, mini(_party_slot, host.get_child_count() - 1))


func refresh() -> void:
	if _party == null:
		return
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
	# 不在动画回调栈里拆树：下一帧再归还队伍页并恢复菜单窗框。
	_restore_menu.call_deferred()


func _restore_menu() -> void:
	# 同一帧里又被要求开窗时，窗口已重新播放 open，别把正文还回去。
	if _opened:
		return
	detach_party()
	if is_instance_valid(host):
		host._render_content()
