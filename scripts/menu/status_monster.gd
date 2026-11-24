extends Control
## 怪物资料页：数值、技能与装备显示切换。

const Battle = preload("res://scripts/battle.gd")
const TextLayout = preload("res://scripts/native_text_layout.gd")
const Settlement = preload("res://scripts/battle_settlement.gd")

## 记录缺失这四项时的占位：原生直接画记录里的字节，本工程取不到就不伪造数值。
const BRAIN_UNKNOWN := "--/--"
const EXPERIENCE_UNKNOWN := "--/--"
const FEEL_UNKNOWN := "--/%d" % ItemEffect.FEEL_MAX

@export var rarity_frames: Array[Texture2D] = []
@export var attribute_frames: Array[Texture2D] = []
@export var equipment_icons: Array[Texture2D] = []
@export var party_view := false
@export var detail_view := false
@export var controller_path := NodePath("..")

var _monster_text: Dictionary = {}
var _active_width := 0.0
var _active_age := 0.0
var _active_text := ""
@onready var _equipment_name_color: Color = $Equipment/Name.color
@onready var _controller: Control = get_node(controller_path)


func _ready() -> void:
	_monster_text = get_node("/root/AssetCatalog").text_messages("common/item_mon.dat")
	$Toggle.pressed.connect(toggle_equipment)
	for index in range(6):
		var slot: Button = $Skills/Slots.get_child(index)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE if party_view and not detail_view else Control.MOUSE_FILTER_STOP
		if not party_view or detail_view:
			slot.pressed.connect(func(): _controller.select_skill(index))


func toggle_equipment() -> void:
	if detail_view:
		_controller.toggle_equipment()
		return
	var host: Control = _controller.host
	if party_view and (not host.party_navigation_open or host.party_actions_open \
			or host.party_discard_open):
		return
	if not party_view and not host.status_navigation_open:
		return
	if party_view:
		host.party_equipment_display_open = not host.party_equipment_display_open
	else:
		host.status_equipment_open = not host.status_equipment_open
		if host.status_equipment_open:
			host.status_skill_open = false
	host._render_content()


func present(member: Dictionary, details: Dictionary) -> void:
	var host: Control = _controller.host
	var args: Array = member.nativeArguments
	var species: MonsterDefinition = host._party_species_record(int(args[0]))
	var rarity: Variant = species.attribute_entry if species != null else null
	var equipment: Variant = details.get("equipment")
	var equipment_open: bool = host.party_equipment_display_open if party_view else host.status_equipment_open
	var skill_selected: bool = (host.party_details_open if detail_view else
		not party_view and host.status_navigation_open and host.status_skill_open) and not equipment_open
	var selected_skill: int = host.selected_party_detail_skill if detail_view else host.selected_status_skill
	var nickname: Variant = member.get("nickname")
	var slots: Array[int] = []
	for index in 6:
		slots.append((0 if index < 2 or args[2] == 1 else 1) if args[2] in [0, 1] else 2)
	var grade: Variant = equipment.get("grade_index") if equipment is Dictionary else null
	var icon: int = host._item_icon_id(int(equipment["id"])) \
		if equipment is Dictionary and not equipment.is_empty() else -1
	var level := int(args[1])
	present_record(int(args[0]), level, details, {
		"species": species, "party_cost": host.Menu.PARTY_COSTS[rarity] if rarity is int and rarity in range(6) else null,
		"nickname": host._menu_text(471 + nickname) if nickname is int and nickname in range(1, 7) else
			"" if nickname is int and nickname == 0 else "--",
		"attribute": host._member_attribute_group(member), "equipment_open": equipment_open,
		"toggle_visible": host.party_navigation_open if party_view else host.status_navigation_open,
		"equipment_empty": args[3] == -1, "empty_text": host._menu_text(149),
		"equipment_name": host._native_item_name(equipment) if equipment is Dictionary else "--",
		"equipment_color": host._native_grade_color(grade, false) if grade is int else null,
		"equipment_icon": host._assets.item_icon(icon),
		"slots": slots, "skill_selected": skill_selected, "selected_skill": selected_skill,
		"skill_description": host._menu_text(151 if slots[selected_skill] == 0 else 150)
			if slots[selected_skill] != 2 else "--",
		# `Menu_detailDrawAbil1` 右侧三项与左列 FOOD 都直接取记录里的字段；
		# EXP 的上限不是记录字段，而是 `Ball_stdEXPS` 按等级重算的 `65 × 等级²`。
		"metrics": {
			"brain_current": int(member.get("brainCurrent", Battle.BRAIN_CURRENT_INITIAL)),
			"brain_limit": int(member.get("brainLimit", Battle.BRAIN_LIMIT)),
			"experience": int(member.get("experience", 0)),
			"experience_threshold": Settlement.EXPERIENCE_PER_LEVEL * level * level,
			"food": int(member.get("food", ItemEffect.FOOD_MAX)),
			"feel": int(member.get("feel", 0)),
		},
	})


func present_record(species_id: int, level: int, details: Dictionary, presentation: Dictionary) -> void:
	$Vitals.show()
	$Skills/Arrow.show()
	$Skills/ActiveClip.show()
	var species: MonsterDefinition = presentation.species
	$Nickname.text = presentation.nickname
	$Name.text = _monster_text.get("item_mon.group.%d.name" % species_id, "--")
	var rarity: Variant = species.attribute_entry if species != null else null
	$Rarity.visible = rarity is int and rarity in range(rarity_frames.size())
	if $Rarity.visible:
		$Rarity.texture = rarity_frames[rarity]
	_present_metric($Level, level)
	_present_metric($Party, presentation.party_cost)
	# 原生 `Menu_detailDrawAbil1`：BRAIN 取 `brain_current/brain_limit`、EXP 取
	# `experience_current/experience_threshold`、FEEL 取 `feel_value/999`，FOOD 是单值。
	# 三个占位常量只在调用方确实拿不到记录时兜底（当前只有战斗情报页的 EXP 一项），
	# 不是首选画法——原生 `Menu_Abil_Draw1` 没有 `--` 分支，缺记录时画 `0`／`0/0`。
	var metrics: Dictionary = presentation.get("metrics", {})
	_present_ratio($Brain, metrics.get("brain_current"), metrics.get("brain_limit"), BRAIN_UNKNOWN)
	_present_ratio($Experience, metrics.get("experience"), metrics.get("experience_threshold"),
		EXPERIENCE_UNKNOWN)
	_present_metric($Food, metrics.get("food"))
	_present_ratio($Feel, metrics.get("feel"), ItemEffect.FEEL_MAX, FEEL_UNKNOWN)
	var ball: Variant = details.get("ball")
	var values: Array = [null, null, null, null, null, null]
	if ball is Dictionary:
		for index in range(4):
			values[index] = Battle.effective_stat(ball, index)
		values[4] = ball.max_hp
		values[5] = ball.speed
	for index in range(6):
		_present_metric($Stats.get_child(index), values[index])
	var group: int = presentation.attribute
	$Vitals/Attribute.visible = group in range(1, 7)
	if $Vitals/Attribute.visible:
		$Vitals/Attribute.texture = attribute_frames[group - 1]
	_present_vital($Vitals/HP, details.get("hp"), ball.get("max_hp") if ball is Dictionary else null, false)
	_present_vital($Vitals/SP, details.get("sp"), ball.get("max_sp") if ball is Dictionary else null, true)
	var active: String = _monster_text.get("item_mon.group.%d.entry.0.name" % species_id, "")
	_present_active(active)
	_present_mode(presentation)
	var equipment_open: bool = $Equipment.visible
	$Equipment/Empty.visible = presentation.equipment_empty
	$Equipment/Empty.text = presentation.empty_text
	var equipment: Variant = details.get("equipment")
	$Equipment/Name.visible = not presentation.equipment_empty
	$Equipment/Name.text = "[ %s ]" % presentation.equipment_name if equipment is Dictionary else "--"
	$Equipment/Name.color = _equipment_name_color
	$Equipment/Item.visible = equipment is Dictionary
	if equipment is Dictionary:
		var grade: Variant = presentation.equipment_color
		($Equipment/Item as ItemCell).set_grade(grade)
		if grade is Color:
			$Equipment/Name.color = grade
		$Equipment/Item/Icon.visible = presentation.equipment_icon != null
		$Equipment/Item/Icon.texture = presentation.equipment_icon
	for index in range(14):
		var metric: Control = $Equipment/Stats.get_child(index)
		var slots: Array = equipment.get("detail_slots", []) if equipment is Dictionary else []
		var value: Variant = slots[index] if index < slots.size() else null
		metric.visible = value is int and value != 0
		metric.get_node("Icon").texture = equipment_icons[index]
		if metric.visible:
			_present_metric(metric, value, "--", true)
	$Stats.tooltip_text = str(details.unavailable) if not ball is Dictionary else ""
	var skill_selected: bool = presentation.skill_selected and not equipment_open
	var selected_skill: int = presentation.selected_skill
	for index in range(6):
		var slot: Control = $Skills/Slots.get_child(index)
		var state: int = presentation.slots[index]
		slot.get_node("Selection").visible = not detail_view and skill_selected and selected_skill == index
		slot.get_node("CompactSelection").visible = detail_view and skill_selected and selected_skill == index
		slot.get_node("EmptyBook").visible = state == 0
		slot.get_node("Lock").visible = state == 1
		slot.get_node("Unknown").visible = state == 2
	$Skills/Description.text = ""
	if skill_selected:
		$Skills/Description.text = presentation.skill_description
	$Skills.tooltip_text = "被动技能槽未记录" if presentation.slots.has(2) else ""


func present_empty() -> void:
	var host: Control = _controller.host
	$Nickname.text = ""
	$Name.text = ""
	$Rarity.hide()
	$Vitals.hide()
	# Native empty slots draw a cleared record; these are not recorded monster stats.
	for metric: Control in [$Level, $Party, $Food] + $Stats.get_children():
		_present_metric(metric, 0)
	_present_metric($Brain, null, "0/0")
	_present_metric($Experience, null, "0/0")
	_present_metric($Feel, null, "0/999")
	$Stats.tooltip_text = ""
	_active_text = ""
	$Skills/Arrow.hide()
	$Skills/ActiveClip.hide()
	$Skills/Description.text = ""
	$Skills.tooltip_text = ""
	for slot: Control in $Skills/Slots.get_children():
		slot.get_node("Selection").hide()
		slot.get_node("CompactSelection").hide()
		slot.get_node("EmptyBook").show()
		slot.get_node("Lock").hide()
		slot.get_node("Unknown").hide()
	_present_mode()
	$Equipment/Empty.show()
	$Equipment/Empty.text = host._menu_text(149)
	$Equipment/Name.hide()
	$Equipment/Item.hide()
	for metric: Control in $Equipment/Stats.get_children():
		metric.hide()


func _present_mode(presentation: Dictionary = {}) -> void:
	var equipment_open: bool
	var toggle_visible: bool
	if presentation.is_empty():
		var host: Control = _controller.host
		equipment_open = host.party_equipment_display_open if party_view else host.status_equipment_open
		toggle_visible = host.party_navigation_open if party_view else host.status_navigation_open
	else:
		equipment_open = presentation.equipment_open
		toggle_visible = presentation.toggle_visible
	$Skills.visible = not equipment_open
	$Equipment.visible = equipment_open
	$Toggle.visible = toggle_visible
	$Toggle/Equip.visible = not equipment_open
	$Toggle/Passive.visible = equipment_open


func _present_metric(metric: Control, value: Variant, unknown := "--", percentage := false) -> void:
	var number: Control = metric.get_node("Number")
	var available: bool = value is int and (value >= 0 or percentage)
	metric.get_node("Unknown").hide()
	number.show()
	number.present(("%d%%" % value if percentage else str(value)) if available else unknown)


## 原生 `Menu_Abil_Draw1` 里 `a6 == 1` 那条：`Menu_numDrawNumber` 的 1 号格式
## 就是 `"%d/%d"`，两个值都右对齐到格子 `x + width − 1`（`Menu_numDrawNumber2` 的
## `GRP_IMAGE_ANCHOR_MIDDLE_RIGHT`）。
func _present_ratio(metric: Control, current: Variant, maximum: Variant, unknown: String) -> void:
	var number: Control = metric.get_node("Number")
	var available: bool = current is int and current >= 0 and maximum is int and maximum >= 0
	metric.get_node("Unknown").hide()
	number.show()
	number.present("%d/%d" % [current, maximum] if available else unknown)


func _present_vital(vital: Control, current: Variant, maximum: Variant, ratio: bool) -> void:
	var available: bool = current is int and current >= 0 and maximum is int and maximum > 0
	var number: Control = vital.get_node("Number")
	var current_text := str(current) if current is int and current >= 0 else "--"
	var maximum_text := str(maximum) if maximum is int and maximum > 0 else "--"
	number.present("%s/%s" % [current_text, maximum_text] if ratio else current_text)
	var track: Control = vital.get_node("Gauge/Track")
	var fill: ColorRect = track.get_node("Fill")
	fill.visible = available
	fill.offset_right = floorf(track.size.x * clampf(float(current) / float(maximum), 0.0, 1.0)) if available else 0.0


func _present_active(source: String) -> void:
	if source == _active_text:
		return
	_active_text = source
	_active_age = 0.0
	var parts := source.split("/", true, 1)
	var title: String = "[%s]" % parts[0] if not source.is_empty() else "--"
	var text := title + (parts[1] if parts.size() > 1 else "")
	var label: Control = $Skills/ActiveClip/Text
	var markup := "[color=#%s]%s[/color][color=#%s]%s[/color]" % [
		label.color.to_html(false), title, Color.WHITE.to_html(false), text.substr(title.length())]
	var layout := TextLayout.layout(markup, label.theme.default_font, label.theme.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	_active_width = layout.lines[0].width
	for node in [$Skills/ActiveClip/Text, $Skills/ActiveClip/Repeat]:
		node.text = text
		node.set_line(layout.lines[0])


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not $Skills.visible:
		return
	_active_age += delta
	var clip: Control = $Skills/ActiveClip
	var scrolling := _active_width > clip.size.x - 1
	var shift := fmod(maxf(0.0, _active_age - 1.0) * 40.0, _active_width + 10.0) if scrolling else 0.0
	$Skills/ActiveClip/Text.position.x = -floorf(shift)
	$Skills/ActiveClip/Repeat.visible = scrolling
	$Skills/ActiveClip/Repeat.position.x = _active_width + 10.0 - floorf(shift)
