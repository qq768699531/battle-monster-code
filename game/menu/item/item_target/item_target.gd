extends Control
## 道具使用目标选择层。

## 成员选择层的操作提示：动作不同，Enter 做的事不同（`Menu_Item_mKeyPressed` 的
## `quest_layer` 9 = 使用、10 = 合成）。
const USE_INSTRUCTIONS := "Enter使用  ←/→选择  Esc返回"
const MIX_INSTRUCTIONS := "Enter合成  ←/→选择  Esc返回"

var host: Control

func _ready() -> void:
	host = get_parent()

## 待确认的动作：直接从 `MenuModel.item_actions` 的动作表推出来（袋 3 才有「合成」），
## 不再另存一份并行状态——原生也是靠 `quest_layer` 9／10 区分这两层。
func _pending_action() -> int:
	var actions: Array = host.Menu.item_actions(host._selected_inventory_item())
	return host.Menu.ITEM_ACTION_MIX if actions.has(host.Menu.ITEM_ACTION_MIX) \
		else host.Menu.ITEM_ACTION_USE


func handle_key(key: String) -> bool:
	if key in ["Escape", "Backspace"]:
		host.item_target_open = false
		host.notice = ""
		host._render_content()
	elif key in ["Enter", "Space"]:
		if _pending_action() == host.Menu.ITEM_ACTION_MIX:
			_confirm_mix()
		else:
			host.use_selected_item_on_target()
	elif key in ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]:
		var order = host.Menu.native_party_order(host.story_progress)
		if not order.is_empty():
			var direction = -1 if key in ["ArrowLeft", "ArrowUp"] else 1
			host.selected_item_target_slot = posmod(host.selected_item_target_slot + direction, order.size())
			host._render_content()
	return true


## 技能书「合成」的成员确认（原生 `Menu_Item_mKeyPressed` 的 `quest_layer == 10`）：
## 先查余额（不足报 `msg 79` 且不扣钱），再走 `MenuModel.mix_item`。
func _confirm_mix() -> void:
	var item: Dictionary = host._selected_inventory_item()
	var order: Array = host.Menu.native_party_order(host.story_progress)
	if item.is_empty() or order.is_empty():
		host.item_target_open = false
		host.notice = "道具或出战成员已不可用。"
		host._render_content()
		return
	var member_index: int = int(order[posmod(host.selected_item_target_slot, order.size())])
	var result: Dictionary = host.Menu.mix_item(host.story_progress, item, member_index)
	host.notice = _mix_notice(result)
	if bool(result.get("ok", false)):
		host.item_target_open = false
		host.last_progress_operation = {"kind": "mix", "item_id": int(item.id),
			"member": member_index, "category": host.selected_bag_category}
		host.progress_changed.emit(host.story_progress.duplicate(true))
	host._render_content()


func _mix_notice(result: Dictionary) -> String:
	if result.has("message_id"):
		return host._menu_text(int(result["message_id"]))
	return str(result.get("error", "道具合成失败"))


func _render_item_target() -> void:
	var order = host.Menu.native_party_order(host.story_progress)
	$Instructions.text = MIX_INSTRUCTIONS if _pending_action() == host.Menu.ITEM_ACTION_MIX \
		else USE_INSTRUCTIONS
	$Vitals.visible = not order.is_empty()
	$Instructions.visible = not order.is_empty()
	if order.is_empty():
		$Target.text = "没有可选的出战成员。"
		return
	host.selected_item_target_slot = posmod(host.selected_item_target_slot, order.size())
	var member_index = int(order[host.selected_item_target_slot])
	var monsters: Variant = host.story_progress.get("monsters", [])
	var member: Variant = monsters[member_index] if monsters is Array and \
		member_index >= 0 and member_index < monsters.size() else null
	var details = host.Menu.native_member_details(host.story_progress, host.gameplay_catalog, member_index)
	$Target.text = "对象：%s  %d/%d" % [host._member_caption(member),
		host.selected_item_target_slot + 1, order.size()]
	var ball: Variant = details.get("ball")
	var hp_max = int(ball.get("max_hp", -1)) if ball is Dictionary else -1
	var sp_max = int(ball.get("max_sp", -1)) if ball is Dictionary else -1
	$Vitals.text = "HP %s/%s  SP %s/%s" % [host._recorded(details, "hp"),
			str(hp_max) if hp_max >= 0 else "?", host._recorded(details, "sp"),
			str(sp_max) if sp_max >= 0 else "?"]
