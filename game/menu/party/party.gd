extends Control
const SaveData = preload("res://engine/data/save_data/save_data.gd")
## 队伍页：球列表与怪物资料。

const StatusPortrait = preload("res://game/menu/status/status_portrait/status_portrait.gd")

var host: Control
var _first_index := 0

func _ready() -> void:
	host = get_parent()
	for slot in range(6):
		var button: Button = $Slots.get_child(slot)
		button.pressed.connect(func():
			host._select_party_slot(_first_index + slot))
	$Scrollbar/UpHit.pressed.connect(func(): _move_selection(-6))
	$Scrollbar/DownHit.pressed.connect(func(): _move_selection(6))


func slot_count() -> int:
	var count: int = host._party_display_members().size()
	var capacity: Variant = SaveData.monster_capacity(host.story_progress)
	if capacity is int and capacity >= 0:
		count = maxi(count, capacity)
	return maxi(1, ceili(float(count) / 6.0)) * 6


func _move_selection(direction: int) -> void:
	host._select_party_slot(posmod(host.selected_party_member_index + direction, slot_count()))


func handle_key(key: String) -> bool:
	if host.item_target_open:
		return _handle_item_target_key(key)
	if host.party_discard_open:
		return host._pages.party_discard.handle_key(key)
	if host.party_actions_open:
		return $ActionAnchor/Actions.handle_key(key)
	if host.party_equip_open:
		return host._pages.party_equipment.handle_key(key)
	if host.party_details_open:
		return host._pages.party_detail.handle_key(key)
	if not host.party_navigation_open:
		if key in ["ArrowDown", "Enter", "Space"]:
			host.party_navigation_open = true
			host.notice = ""
			host._render_content()
			return true
		return key == "ArrowUp"
	if key in ["Escape", "Backspace"]:
		host.party_navigation_open = false
		host.notice = ""
		host._render_content()
		return true
	if key in ["0", "Digit0"]:
		$Monster.toggle_equipment()
		return true
	if key in ["Enter", "Space"]:
		if host.selected_party_member_index >= host._party_display_members().size():
			return true
		host.party_actions_open = true
		host.selected_party_action = 0
		host.notice = ""
		host._render_content()
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		_move_selection(-1 if key == "ArrowLeft" else 1)
		return true
	if key in ["ArrowUp", "ArrowDown"]:
		_move_selection(-6 if key == "ArrowUp" else 6)
		return true
	return false


## 道具使用／合成的二级选择（原生 `MENU_STATE_PARTY` 的 quest_layer 9／10）：
## 只移动光标、确认、取消，不打开队伍动作表。
func _handle_item_target_key(key: String) -> bool:
	if key in ["Escape", "Backspace"]:
		host.cancel_item_target()
		return true
	if key in ["Enter", "Space"]:
		host.confirm_item_target()
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		_move_selection(-1 if key == "ArrowLeft" else 1)
		return true
	if key in ["ArrowUp", "ArrowDown"]:
		_move_selection(-6 if key == "ArrowUp" else 6)
		return true
	return true


func _render_party() -> void:
	if host.party_equip_open:
		$Portrait.hide()
		$Monster.hide()
		host._pages.party_equipment._render_party_equipment()
		return
	var monsters: Variant = SaveData.monsters(host.story_progress)
	if not monsters is Array:
		monsters = []
	var order: Array = host.Menu.native_party_order(host.story_progress)
	var capacity: Variant = SaveData.monster_capacity(host.story_progress)
	_present_summary(monsters, order)
	host.selected_party_member_index = clampi(host.selected_party_member_index, 0, slot_count() - 1)
	var selected_index: int = host.selected_party_member_index
	_first_index = selected_index / 6 * 6
	_update_scrollbar(selected_index / 6, slot_count() / 6)
	for slot in range(6):
		var cell := $Slots.get_child(slot) as ItemCell
		var display_index := _first_index + slot
		var has_member: bool = display_index < monsters.size()
		var member_index := display_index if has_member else -1
		var selected: bool = host.party_navigation_open and display_index == selected_index
		cell.disabled = host.party_actions_open or host.party_discard_open
		cell.get_node("Quantity").hide()
		var in_capacity: bool = has_member or (capacity is int and display_index < capacity)
		var frame_index := (0 if in_capacity else 2) + (1 if selected else 0)
		cell.present_frame(host._party_frames[frame_index], selected)
		var icon: Control = cell.get_node("Icon")
		var marker: TextureRect = cell.get_node("Marker")
		cell.set_grade(null)
		icon.texture = null
		marker.visible = has_member and order.has(member_index)
		var equipment_marker: TextureRect = cell.get_node("EquipmentMarker")
		equipment_marker.hide()
		if has_member:
			var monster: Dictionary = monsters[member_index]
			equipment_marker.visible = monster.nativeArguments[3] >= 0
			cell.set_grade(host._party_grade_color(monster))
			icon.texture = host._party_icon(monster)
	var has_slots: bool = not monsters.is_empty() or (capacity is int and capacity >= 0)
	$EmptyNotice.visible = not has_slots
	$Monster.hide()
	$Error.hide()
	var has_selected_member: bool = host.party_navigation_open and selected_index < monsters.size()
	$Scrollbar/UpHit.disabled = host.party_actions_open or host.party_discard_open
	$Scrollbar/DownHit.disabled = host.party_actions_open or host.party_discard_open
	$ActionAnchor/Actions.present()
	if host.party_actions_open:
		var cell: Control = $Slots.get_child(selected_index % 6)
		var actions: Control = $ActionAnchor/Actions
		$ActionAnchor.global_position = Vector2(
			minf(cell.get_global_rect().end.x,
				get_viewport_rect().end.x - actions.position.x - actions.size.x),
			cell.global_position.y)
	$Portrait.visible = has_slots and not host.party_details_open and not host.party_equip_open
	# 立绘由持有它的本页自己画；道具二级窗用的是本页的另一个实例，也走这里。
	var portrait_index: int = host.selected_party_member_index \
		if host.party_navigation_open else -1
	$Portrait.present_request(host, StatusPortrait.member_request(host, portrait_index))
	if not has_selected_member:
		if has_slots:
			$Monster.present_empty()
			$Monster.visible = not host.party_details_open and not host.party_equip_open
		return
	var member_index: int = host.selected_party_member_index
	var member: Variant = monsters[member_index] if member_index >= 0 and member_index < monsters.size() else null
	var details = host.Menu.native_member_details(host.story_progress, host.gameplay_catalog, member_index)
	if details.get("ok", false):
		$Monster.present(member, details)
		$Monster.visible = not host.party_equip_open
	else:
		$Error.text = "成员详情不可用：%s" % str(details.get("error", "未知原因"))
		$Error.show()


func _present_summary(monsters: Array, order: Array) -> void:
	var capacity: Variant = SaveData.monster_capacity(host.story_progress)
	var capacity_text := str(capacity) if capacity is int and capacity >= 0 else "--"
	$BallCount.present("%d/%s" % [monsters.size(), capacity_text])
	$BallCount.tooltip_text = "" if capacity_text != "--" else "当前进度未记录精灵球容量。"
	var used: Variant = host.Menu.party_points(host.story_progress, host.gameplay_catalog, order)
	var point_limit: Variant = host.Menu.party_point_limit(host.story_progress)
	$PartyUsage/Number.present("%s/%s" % [
		str(used) if used != null else "--",
		str(point_limit) if point_limit != null else "--",
	])
	if point_limit == null:
		$PartyUsage.tooltip_text = "PARTY 点上限依赖公会档位与原生标准进度。\n" + \
			"当前存档未记录可用的标准进度。"
	else:
		# 原生 `Ball_guildPartys`：档位基数（`Ball_guildGrade` 档位）+ 标准等级 / 20。
		var grade_title: String = str(host._menu_text(
			host.Menu.guild_title_record(host.story_progress)))
		$PartyUsage.tooltip_text = "当前公会档位：%s，PARTY 点上限 %d。" % [grade_title, point_limit]
	if used == null:
		$PartyUsage.tooltip_text += "\n出战成员品级资料缺失，已用 PARTY 点也无法确定。"


func _update_scrollbar(page: int, page_count: int) -> void:
	$Scrollbar.visible = page_count > 1
	if $Scrollbar.visible:
		var track: Control = $Scrollbar/Track
		var length := maxi(3, int(track.size.y) - 3 * (page_count - 1))
		var offset := int(clampi(page, 0, page_count - 1) *
			(track.size.y - length) / (page_count - 1))
		$Scrollbar/Thumb.position = track.position + Vector2(0, offset)
		$Scrollbar/Thumb.size = Vector2(track.size.x, length)
