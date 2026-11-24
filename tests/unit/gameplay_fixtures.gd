extends RefCounted

## 测试夹具构造器：把紧凑字典写成 typed 玩法记录，避免每个用例重复逐字段赋值。
## 字段名与 `scripts/data/*` 的 `@export` 保持一致；缺省字段取记录里的默认值。

const ItemDefinition = preload("res://game/menu/item/item_definition/item_definition.gd")
const MonsterDefinition = preload("res://monsters/monster_definition/monster_definition.gd")
const PassiveDefinition = preload("res://battle/passive_definition/passive_definition.gd")
const EncounterDefinition = preload("res://game/field/encounters/encounter_definition/encounter_definition.gd")
const EncounterEntry = preload("res://game/field/encounters/encounter_entry/encounter_entry.gd")
const ScriptBattleDefinition = preload("res://battle/script_battle_definition/script_battle_definition.gd")
const GameplayData = preload("res://engine/data/gameplay_data/gameplay_data.gd")


static func data(values: Dictionary = {}) -> GameplayData:
	var result: GameplayData = GameplayData.new()
	for row: Variant in _list(values, "items"):
		result.items.append(row if row is ItemDefinition else item(row))
	for row: Variant in _list(values, "monsters"):
		result.monsters.append(row if row is MonsterDefinition else monster(row))
	for row: Variant in _list(values, "passives"):
		result.passives.append(row if row is PassiveDefinition else passive(row))
	for key: Variant in _dict(values, "encounters"):
		var row: Variant = values["encounters"][key]
		result.encounters.append(row if row is EncounterDefinition else encounter(int(key), row))
	for key: Variant in _dict(values, "script_battles"):
		var row: Variant = values["script_battles"][key]
		result.script_battles.append(
			row if row is ScriptBattleDefinition else script_battle(int(key), row))
	return result


static func _list(values: Dictionary, key: String) -> Array:
	var value: Variant = values.get(key)
	return value if value is Array else []


static func _dict(values: Dictionary, key: String) -> Dictionary:
	var value: Variant = values.get(key)
	return value if value is Dictionary else {}


static func item(values: Dictionary) -> ItemDefinition:
	var record: ItemDefinition = ItemDefinition.new()
	record.id = int(values.get("id", 0))
	record.type = int(values.get("type", 0))
	record.index = int(values.get("index", 0))
	record.grade_index = int(values.get("grade_index", 0))
	record.icon = int(values.get("icon", -1))
	record.purchase_price = int(values.get("purchase_price", -1))
	record.name_record = str(values.get("name_record", ""))
	record.result_name_record = str(values.get("result_name_record", ""))
	record.result_description_record = str(values.get("result_description_record", ""))
	_ints(record.detail_slots, values.get("detail_slots", []))
	return record


static func monster(values: Dictionary) -> MonsterDefinition:
	var record: MonsterDefinition = MonsterDefinition.new()
	record.id = int(values.get("id", 0))
	record.kind = int(values.get("kind", 0))
	record.attribute_group = int(values.get("attribute_group", 0))
	record.attribute_entry = int(values.get("attribute_entry", 0))
	record.name_record = str(values.get("name_record", ""))
	record.prime_portrait_position = int(values.get("prime_portrait_position", 0))
	record.idle_frames = int(values.get("idle_frames", 0))
	_ints(record.ability_inputs, values.get("ability_inputs", []))
	_ints(record.attribute_inputs, values.get("attribute_inputs", []))
	for offset: Variant in values.get("portrait_offset", []):
		record.portrait_offset.append(offset)
	return record


static func passive(values: Dictionary) -> PassiveDefinition:
	var record: PassiveDefinition = PassiveDefinition.new()
	record.id = int(values.get("id", 0))
	record.base = int(values.get("base", 0))
	record.effect = int(values.get("effect", 0))
	record.increment = int(values.get("increment", 0))
	return record


static func encounter(id: int, values: Dictionary) -> EncounterDefinition:
	var record: EncounterDefinition = EncounterDefinition.new()
	record.id = id
	record.mode = str(values.get("mode", ""))
	record.world_level = int(values.get("world_level", 0))
	for row: Dictionary in values.get("pool", []):
		var entry: EncounterEntry = EncounterEntry.new()
		entry.species = int(row.get("species", 0))
		entry.weight = int(row.get("weight", 0))
		record.pool.append(entry)
	return record


static func script_battle(id: int, values: Dictionary) -> ScriptBattleDefinition:
	var record: ScriptBattleDefinition = ScriptBattleDefinition.new()
	record.id = id
	for row: Variant in values.get("constructors", []):
		var args := PackedInt32Array()
		for value: Variant in row:
			args.append(int(value))
		record.constructors.append(args)
	return record


static func _ints(target: Array[int], values: Variant) -> void:
	for value: Variant in values:
		target.append(int(value))

## 战斗用例共用的物种／被动／装备夹具（与原生 49/62/86/93/99 等条目一致）。
static func battle_catalog() -> GameplayData:
	return data({
		"monsters": [
			{"id": 13, "kind": 0, "attribute_group": 1,
				"ability_inputs": [32, 37, 35, 35, 34, 33],
				"attribute_inputs": [21, 9, 27, 7, 10, 7]},
			{"id": 49, "kind": 0, "attribute_group": 3,
				"ability_inputs": [14, 13, 12, 11, 17, 16],
				"attribute_inputs": [16, 4, 22, 2, 11, 2]},
			{"id": 62, "kind": 0, "attribute_group": 3,
				"ability_inputs": [45, 43, 42, 41, 47, 45],
				"attribute_inputs": [19, 7, 25, 5, 14, 5]},
			{"id": 86, "kind": 0, "attribute_group": 4,
				"ability_inputs": [55, 54, 53, 53, 52, 57],
				"attribute_inputs": [21, 9, 25, 7, 10, 11]},
			{"id": 93, "kind": 0, "attribute_group": 5,
				"ability_inputs": [12, 11, 17, 16, 14, 13],
				"attribute_inputs": [15, 2, 26, 6, 9, 3]},
			{"id": 99, "kind": 0, "attribute_group": 5,
				"ability_inputs": [23, 22, 27, 25, 24, 24],
				"attribute_inputs": [16, 3, 27, 7, 10, 4]},
		],
		"passives": [
			{"id": 3, "effect": 1, "base": 10, "increment": 1},
			{"id": 39, "effect": 13, "base": 10, "increment": 1},
			{"id": 76, "effect": 26, "base": 30, "increment": 1},
			{"id": 140, "effect": 50, "base": 60, "increment": 1},
		],
		"items": [
			{"id": 2025, "type": 2, "index": 25,
				"detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 5, -1]},
			{"id": 2027, "type": 2, "index": 27,
				"detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 10, 0, 5]},
			{"id": 2029, "type": 2, "index": 29,
				"detail_slots": [0, 0, 0, 0, 0, -1, 0, 0, 5, 0, 0, 0, 10, 0]},
			{"id": 2064, "type": 2, "index": 64,
				"detail_slots": [0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 15, 0]},
			{"id": 1000, "type": 1, "index": 0,
				"detail_slots": [0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]},
		],
	})
