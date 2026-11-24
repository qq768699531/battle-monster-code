extends "res://engine/ui/window_transition/window_transition.gd"
## 战斗情报窗口。

signal closed

const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const Battle = preload("res://battle/combat/battle.gd")
const ItemEffect = preload("res://battle/item_effect/item_effect.gd")

var selected_skill := 0
var equipment_open := false
var _ball: Dictionary
var _presentation: RefCounted


func _ready() -> void:
	super()
	transition_finished.connect(func(opened: bool):
		if not opened and visible:
			hide()
			closed.emit())
	phase_changed.connect(func(phase: int): %Monster.get_node("Toggle").visible = phase == 4)


func open_monster(ball: Dictionary, presentation: RefCounted) -> bool:
	_ball = ball
	_presentation = presentation
	selected_skill = 0
	equipment_open = false
	show()
	_render()
	open_window()
	return true


func handle_key(key: String) -> void:
	if _ball.is_empty() or is_transitioning():
		return
	if key in ["Escape", "Backspace"]:
		close_window()
	elif key in ["0", "Digit0"]:
		toggle_equipment()
	elif key in ["ArrowLeft", "ArrowRight"] and not equipment_open:
		select_skill(posmod(selected_skill + (-1 if key == "ArrowLeft" else 1), 6))


func select_skill(index: int) -> void:
	if is_transitioning() or equipment_open:
		return
	selected_skill = index
	_render()


func toggle_equipment() -> void:
	if is_transitioning():
		return
	equipment_open = not equipment_open
	_render()


func _render() -> void:
	var species_id := int(_ball.species) % 1000
	var species: MonsterDefinition = _presentation.catalog.monster(species_id)
	var equipment: Dictionary = {}
	var arguments: Array = _ball.get("native_arguments", [])
	var equipment_known := arguments.size() == 10
	var equipment_index := int(arguments[8]) if equipment_known else -1
	if equipment_index >= 0:
		var record: ItemDefinition = _presentation.catalog.item(2000 + equipment_index)
		if record != null:
			equipment = Menu.item_row(record)
	var rarity: int = species.attribute_entry
	# 战斗里的球记录带着大脑（`Ball_stdSet` 的 `+0x2B` 当前值／`+0x2C` 上限 99）、心情（`+0x28`）
	# 与饱食度（`+0x2D`），直接交给资料页，不再退化成占位。EXP 不是球记录字段（战后才结算），
	# 原生情报条 `Game_Monster_DrawInfo1` 也只画 LEVEL 与 BRAIN，所以这一项留空。
	var metrics := {
		"brain_current": int(_ball.get("brain_current", Battle.BRAIN_CURRENT_INITIAL)),
		"brain_limit": int(_ball.get("brain_limit", Battle.BRAIN_LIMIT)),
		"feel": int(_ball.get("feel", 0)),
		"food": int(_ball.get("food", ItemEffect.FOOD_MAX)),
	}
	%Monster.present_record(species_id, int(_ball.level), {
		"ball": _ball, "hp": _ball.hp, "sp": _ball.sp, "equipment": equipment,
	}, {
		"species": species, "party_cost": Menu.PARTY_COSTS[rarity],
		"nickname": _presentation.message(471 + int(_ball.nickname)) if int(_ball.nickname) > 0 else "",
		"attribute": int(species.attribute_group), "equipment_open": equipment_open, "toggle_visible": true,
		"equipment_empty": equipment_known and equipment_index == -1, "empty_text": _presentation.message(149),
		"equipment_name": _presentation.item_name(equipment) if not equipment.is_empty() else "--",
		"equipment_color": _presentation.item_color(equipment) if not equipment.is_empty() else null,
		"equipment_icon": _presentation.item_texture(equipment) if not equipment.is_empty() else null,
		"slots": [2, 2, 2, 2, 2, 2], "skill_selected": true, "selected_skill": selected_skill,
		"skill_description": "--", "metrics": metrics,
	})
	%Caption.text = ("%s %s" % [%Monster.get_node("Nickname").text, %Monster.get_node("Name").text]).strip_edges()
	var layout: Dictionary = TextLayout.layout(%Caption.text, %Caption.theme.default_font,
		%Caption.theme.default_font_size)
	if not layout.error.is_empty():
		push_error(layout.error)
		return
	%Caption.custom_minimum_size.x = layout.lines[0].width
	%Attribute.texture = %Monster.get_node("Vitals/Attribute").texture
	var portrait: Node2D = $Content/Portrait/StatusPortraitLayers/Monster
	var identity := MonsterAnimation.battle_identity(int(_ball.species))
	var offset: Vector2 = _presentation.portrait_offset(species_id, int(identity.ends_with("_2")))
	portrait.get_node("Content").position = Vector2(offset.x, -offset.y)
	portrait.visible = portrait.present(identity, 0, 0, true)
	var error: Label = $Content/Portrait/PortraitError
	error.visible = not portrait.visible
	error.tooltip_text = portrait.last_error

