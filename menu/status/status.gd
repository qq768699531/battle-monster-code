extends Control
## 状态页：顶部页签下的人物/怪物切换与能力分配入口。

const MonsterAttribute = preload("res://core/monster_animation/monster_attribute/monster_attribute.gd")

## 六格流派进度条的几何：`Menu_Hero_Draw1` 逐格调 `Menu_Attr_Draw`，
## 每格传 `w = 99`（`a3`）与行高 13（`a4`）。内轨从 `x + 18` 起、宽 `w − 44`，
## 那 44 = 左内缩 18 + 图标前 5 空隙 + 右侧图标从行右缘起算的 21（`x + w − 21`）。
const GROWTH_ROW_WIDTH := 99
const GROWTH_TRACK_INSET := 44
const GROWTH_TRACK_WIDTH := GROWTH_ROW_WIDTH - GROWTH_TRACK_INSET

var host: Control

func _ready() -> void:
	hide()
	host = get_parent()
	for index in range(4):
		var tab: Button = $Tabs.get_child(index)
		tab.pressed.connect(func(): host._select_status_page(index))
	for index in range(3):
		var card: Button = $Cards.get_child(index)
		card.pressed.connect(func():
			if host.status_allocation_open:
				host._stage_status_attribute(index)
			else:
				host._select_status_attribute(index))

func handle_key(key: String) -> bool:
	if host.status_confirmation_open:
		return host._pages.status_confirmation.handle_key(key)
	if key in ["0", "Digit0"] and host.status_navigation_open and host.selected_status_page > 0:
		$Monster.toggle_equipment()
		return true
	if key in ["Escape", "Backspace"]:
		if host.status_allocation_open:
			host.status_allocation_open = false
			host.pending_status_allocation.assign([0, 0, 0])
			host.notice = "待分配能力点已取消"
		elif host.status_skill_open:
			host.status_skill_open = false
			host.notice = ""
		elif host.status_navigation_open:
			host.status_navigation_open = false
			host.notice = ""
		else:
			return false
		host._render_content()
		return true
	if key in ["Enter", "Space"]:
		if host.status_skill_open:
			return true
		elif host.status_allocation_open:
			if key == "Space":
				host._stage_status_allocation()
			elif host.pending_status_allocation.any(func(value: int) -> bool: return value > 0):
				host.status_confirmation_open = true
				host.selected_status_confirmation = 1
				host._render_content()
			else:
				host.notice = "尚未分配能力点"
				host._render_content()
		elif host.status_navigation_open:
			_enter_details()
			host._render_content()
		else:
			host.status_navigation_open = true
			host.selected_status_skill = 0
			host.notice = ""
			host._render_content()
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		var direction = -1 if key == "ArrowLeft" else 1
		if host.status_skill_open:
			host.selected_status_skill = posmod(host.selected_status_skill + direction, 6)
		elif host.status_allocation_open:
			host.selected_status_attribute = posmod(host.selected_status_attribute + direction, 3)
		elif host.status_navigation_open:
			host.selected_status_page = posmod(host.selected_status_page + direction, host._status_page_count())
			host.selected_status_skill = 0
			host.notice = ""
		else:
			return false
		host._render_content()
		return true
	if key in ["ArrowUp", "ArrowDown"]:
		if host.status_allocation_open:
			return true
		if host.status_skill_open:
			if key == "ArrowDown":
				return true
			host.status_skill_open = false
		elif key == "ArrowUp":
			host.status_navigation_open = false
		elif host.status_navigation_open:
			_enter_details()
		else:
			host.status_navigation_open = true
			host.selected_status_skill = 0
		host.notice = ""
		host._render_content()
		return true
	return false


func _enter_details() -> void:
	if host.selected_status_page == 0:
		host.status_allocation_open = true
		host.selected_status_attribute = 0
		host.pending_status_allocation.assign([0, 0, 0])
		host.notice = ""
	elif not host.status_equipment_open:
		host.status_skill_open = true
		host.notice = ""
	else:
		host.notice = "成员状态为只读"


func select_skill(index: int) -> void:
	host.status_navigation_open = true
	host.status_skill_open = true
	host.selected_status_skill = index
	host.notice = ""
	host._render_content()


func _render_status() -> void:
	var order: Array = host.Menu.native_party_order(host.story_progress)
	if host.selected_status_page > order.size():
		host.selected_status_page = 0
	for slot in range(4):
		var tab: Button = $Tabs.get_child(slot)
		tab.disabled = slot >= host._status_page_count() or host.status_allocation_open or host.status_confirmation_open
		var frame_index := 9
		if slot == 0:
			frame_index = 0 if host.status_navigation_open and host.selected_status_page == 0 else 7
		elif slot <= order.size() and host.status_navigation_open and host.selected_status_page == slot:
			var member_index := int(order[slot - 1])
			var members: Variant = host.story_progress.get("monsters", [])
			if members is Array and member_index >= 0 and member_index < members.size():
				frame_index = host._member_attribute_group(members[member_index])
				if frame_index < 1 or frame_index > 6:
					frame_index = 9
		elif slot <= order.size():
			frame_index = 8
		tab.get_node("Icon").texture = host._status_frames[frame_index] \
			if frame_index < host._status_frames.size() else null
	for node in [$Title, $CharacterName, $Monster, $Error]:
		node.hide()
	var hero: bool = host.selected_status_page == 0
	for node in [$Cards, $Gradient, $Metric0, $Metric1, $Metric2, $Metric3,
			$Points, $GrowthFrame, $Growth]:
		node.visible = hero
	$Portrait.show()
	if host.selected_status_page == 0:
		var parameter: Variant = host.story_progress.get("parameter", {})
		if not parameter is Dictionary:
			parameter = {}
		$Title.text = host._menu_text(host.Menu.guild_title_record(host.story_progress))
		$Title.show()
		var identity: Variant = parameter.get("identity")
		if identity is int and identity >= 0 and identity < host._npc_records.size():
			var name_text: Variant = host._npc_records[identity].get("name_text")
			if name_text is String:
				$CharacterName.text = name_text
				$CharacterName.show()
		for index in range(3):
			var card: Button = $Cards.get_child(index)
			card.get_node("Label").text = host._menu_text(146 + index)
			card.disabled = host.status_confirmation_open or \
				not (host.status_navigation_open or host.status_allocation_open)
		_render_hero(parameter, order)
	else:
		var member_index = int(order[host.selected_status_page - 1])
		var members: Variant = host.story_progress.get("monsters", [])
		var member: Variant = members[member_index] if members is Array and \
			member_index >= 0 and member_index < members.size() else null
		var details = host.Menu.native_member_details(host.story_progress, host.gameplay_catalog, member_index)
		if details.get("ok", false):
			$Monster.present(member, details)
			$Monster.show()
		else:
			$Error.text = "成员详情不可用：%s" % details.get("error", "未知原因")
			$Error.show()


func _render_hero(parameter: Dictionary, order: Array) -> void:
	var development: Variant = parameter.get("development", {}) \
		if parameter is Dictionary else {}
	var allocated: Variant = development.get("allocated", []) \
		if development is Dictionary else []
	for index in range(3):
		var card: Control = $Cards.get_child(index)
		card.get_node("Choice").texture = host._status_choice_frames[
			0 if host.status_allocation_open and index == host.selected_status_attribute else 1] \
			if host._status_choice_frames.size() == 2 else null
		var count: Variant = null
		if allocated is Array and index < allocated.size() and \
				allocated[index] is int and allocated[index] >= 0:
			var pending = host.pending_status_allocation[index] \
				if index < host.pending_status_allocation.size() else 0
			if pending >= 0:
				count = allocated[index] + pending
		_present_number(card.get_node("Number"), count)
	for index in range(4):
		var metric: Control = get_node("Metric%d" % index)
		metric.get_node("Icon").texture = host._status_indicator_frames[index] \
			if index < host._status_indicator_frames.size() else null
		var value: Variant = parameter.get("level") if index == 0 else \
			host.Menu.guild_code(host.story_progress) if index == 1 else null
		var denominator := -1
		# 原生 Menu_Hero_Draw1 第一行右侧为 PARTY 已用/上限（Ball_stdGetPartys / Ball_guildPartys）。
		if index == 2:
			var limit: Variant = host.Menu.party_point_limit(host.story_progress)
			if limit is int:
				value = host.Menu.party_points(host.story_progress, host.gameplay_catalog, order)
				denominator = limit
		elif index == 3 and development is Dictionary:
			var level: Variant = parameter.get("level")
			if level is int and level > 0:
				value = development.get("experience")
				denominator = 65 * level * level
		_present_number(metric.get_node("Number"), value, denominator)
		metric.get_node("Unknown").visible = not metric.get_node("Number").visible
	$Points/Icon.texture = host._status_indicator_frames[5] \
		if host._status_indicator_frames.size() > 5 else null
	_present_number($Points/Number, development.get("points") if development is Dictionary else null)
	var growth: Variant = development.get("growth", []) if development is Dictionary else []
	var mastery_experience: Variant = development.get("masteryExperience", []) \
		if development is Dictionary else []
	var preferred_mastery: int = int(parameter.get("preferredMastery", -1))
	for index in range(6):
		var row: Control = $Growth.get_child(index)
		row.get_node("Attribute").texture = host._status_attribute_frames[index] \
			if index < host._status_attribute_frames.size() else null
		row.get_node("Marker").texture = host._status_growth_icon
		# 右侧数字是 `mastery_progress[i].level`（`Menu_Attr_Draw` 取 `*(u8*)(a6 + 8)`）。
		var level: Variant = growth[index] \
			if growth is Array and index < growth.size() else null
		_present_number(row.get_node("Number"), level)
		_present_growth_fill(row.get_node("Fill"), level,
			mastery_experience[index] \
				if mastery_experience is Array and index < mastery_experience.size() else null,
			preferred_mastery, index)


## 进度条填充宽：`Menu_Attr_Draw` 的
## `point_remainder × (w − 44) / next_level_threshold`（整数截断）；阈值 ≤ 0 时不画，
## 对应原生的 `if (*(int *)(a6 + 4) > 0)`。余数与阈值分别对应
## `development.masteryExperience[i]` 与 `Param_expINIT` 的系数 × 等级²。
func _present_growth_fill(fill: ColorRect, level: Variant, experience: Variant,
		preferred_mastery: int, index: int) -> void:
	var filled := 0
	if level is int and experience is int and experience >= 0:
		var threshold := MonsterAttribute.threshold(preferred_mastery, index, level)
		if threshold > 0:
			filled = experience * GROWTH_TRACK_WIDTH / threshold
	fill.size = Vector2(filled, fill.size.y)


func _present_number(number: Control, value: Variant, denominator: int = -1) -> void:
	number.visible = value is int and value >= 0 and str(value).length() <= 20
	if not number.visible:
		return
	if not number.configure(host._assets):
		push_error("Native status number texture is unavailable.")
		number.hide()
		return
	number.present("%d/%d" % [value, denominator] if denominator >= 0 else str(value))
	for glyph: Control in number.get_node("Glyphs").get_children():
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _status_portrait_request() -> Dictionary:
	if host.status_confirmation_open:
		return {}
	var layers: Array[Dictionary] = [{
		"path": "obj/ui_eff", "action": 1, "frame": 0, "direction": 0,
	}]
	if host.selected_tab == MenuModel.Tab.STATUS and host.selected_status_page == 0:
		layers.append({"path": "face/fc00", "action": 0, "direction": 1})
		return {"key": "hero", "layers": layers}
	var order = host.Menu.native_party_order(host.story_progress)
	var member_index: int = host.selected_party_member_index
	if host.selected_tab == MenuModel.Tab.STATUS:
		var member_slot = host.selected_status_page - 1
		if member_slot < 0 or member_slot >= order.size():
			return {}
		member_index = int(order[member_slot])
	var monsters: Variant = host.story_progress.get("monsters", [])
	var capacity: Variant = host.story_progress.get("monsterCapacity")
	if host.selected_tab == MenuModel.Tab.PARTY and monsters is Array \
			and (not host.party_navigation_open or member_index >= monsters.size()) \
			and (not monsters.is_empty() or (capacity is int and capacity >= 0)):
		return {"key": "party:empty", "layers": layers}
	if not monsters is Array or member_index < 0 or member_index >= monsters.size():
		return {}
	var member: Variant = monsters[member_index]
	if not member is Dictionary:
		return {}
	var args: Variant = member.get("nativeArguments", [])
	if not args is Array or args.is_empty() or not args[0] is int:
		return {}
	var species_id: int = args[0]
	var base_species = species_id % 1000
	var form = 2 if species_id > 999 else 1
	var path = "mon2/m_b_%03d_%d" % [base_species, form]
	var offset: Vector2 = host.portrait_offset(base_species, form - 1)
	layers.append({"path": path, "action": 0,
		"direction": 0, "offset": Vector2(offset.x, -offset.y)})
	return {"key": "member:%d:%s" % [member_index, path], "layers": layers, "monster": true}


func _sync_status_portrait() -> void:
	if not is_instance_valid(host._status_portrait_node):
		return
	var portrait_view: Control = $Portrait
	if host.selected_tab == MenuModel.Tab.PARTY:
		portrait_view = host._pages.party_detail.get_node("Content/Portrait") \
			if host.party_details_open else host._pages.party.get_node("Portrait")
	var layers: Control = portrait_view.get_node("StatusPortraitLayers")
	var monster: Node2D = portrait_view.get_node("StatusPortraitLayers/Monster")
	var hero: Node2D = portrait_view.get_node("StatusPortraitLayers/Hero")
	if host._status_portrait_node != layers:
		host._status_portrait_node = layers
		host._status_portrait_border_node = portrait_view.get_node("StatusPortraitBorder")
		host._status_portrait_frame_key = ""
	var error: Control = portrait_view.get_node("PortraitError")
	error.hide()
	var party_visible: bool = host.selected_tab == MenuModel.Tab.PARTY and not host.party_equip_open
	var request = _status_portrait_request() if host.selected_tab == MenuModel.Tab.STATUS or party_visible else {}
	monster.visible = not request.is_empty() and bool(request.get("monster", false))
	hero.visible = not request.is_empty() and request.key == "hero"
	if request.is_empty():
		host._status_portrait_key = ""
		host._status_portrait_path = ""
		host._status_portrait_frame_key = ""
		host._status_portrait_node.visible = false
		host._status_portrait_border_node.visible = false
		return
	var requested_key: String = request.key
	var layer_requests: Variant = request.get("layers", [])
	if not layer_requests is Array or layer_requests.is_empty():
		host._status_portrait_node.visible = false
		host._status_portrait_border_node.visible = false
		return
	var requested_frame_key = requested_key
	if host._status_portrait_key == requested_key and \
			host._status_portrait_frame_key == requested_frame_key:
		if not host._status_portrait_error.is_empty():
			error.show()
		return
	host._status_portrait_key = requested_key
	host._status_portrait_path = requested_key
	host._status_portrait_frame_key = requested_frame_key
	host._status_portrait_error = ""
	for layer_request: Dictionary in layer_requests:
		var path: String = layer_request.path
		if path == "obj/ui_eff":
			continue
		var animation: Node2D = monster if path.begins_with("mon2/") else hero
		if not animation.present(path, int(layer_request.action), int(layer_request.direction)):
			host._status_portrait_error = animation.last_error
			error.show()
			host._status_portrait_node.visible = false
			host._status_portrait_border_node.visible = false
			return
		if animation == monster:
			monster.get_node("Content").position = layer_request.offset
	host._status_portrait_node.visible = true
	host._status_portrait_border_node.visible = true



