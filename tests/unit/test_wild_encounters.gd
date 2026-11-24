extends "res://tests/unit/gut_case.gd"

const Wild = preload("res://field/wild_encounters/wild_encounters.gd")
const Battle = preload("res://battle/combat/battle.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const EncounterDefinition = preload("res://field/encounter_definition/encounter_definition.gd")


func _monster(point: Vector2, state: int = 5) -> Dictionary:
	return {"id": 10024, "species": 24, "x": point.x / 16, "y": point.y / 16,
		"action": state, "direction": 32, "emotion": null,
		"wild": {"home": point, "target": point + Vector2(30, 0), "state": state,
			"idle": 0.0, "idle_seconds": 0.4}}


func test_legacy_suite() -> void:
	var terrain := {"width_tiles": 50, "height_tiles": 50, "cell_flags": []}
	for y in 50:
		terrain.cell_flags.append([])
		for x in 50:
			terrain.cell_flags[y].append(0)
	var random := func(_limit: int) -> int: return 0
	var hero := Vector2(200, 200)
	var monster := _monster(hero + Vector2(24, 5))
	assert_true(Wild.contact([monster], hero).is_empty(), "strict squared contact boundary 601")
	monster.y = 203.0 / 16.0
	assert_true(Wild.contact([monster], hero) == monster, "contact inside native 600 threshold")
	monster = _monster(hero + Vector2(60, 0))
	Wild.advance([monster], terrain, hero, 0.05, random)
	assert_true(monster.wild.state == 7 and monster.emotion == 7 and
		is_equal_approx(monster.x * 16, 256), "nearby monster alerts and pursues at 4px/50ms")


## 原生 `Map_mifLOAD` 的动态池（97–121 号图）：按玩家等级取权重行，
## 每一档稀有度随机取一只该稀有度的物种。
func test_dynamic_pool() -> void:
	var catalog: GameplayData = Fixtures.data({
		"monsters": [
			{"id": 40, "attribute_entry": 0}, {"id": 41, "attribute_entry": 1},
			{"id": 42, "attribute_entry": 2}, {"id": 43, "attribute_entry": 3},
			{"id": 44, "attribute_entry": 4}, {"id": 45, "attribute_entry": 5},
		],
		"encounters": {97: {"mode": "native-dynamic-unimplemented", "world_level": 0}},
	})
	var encounter: EncounterDefinition = catalog.encounter(97)
	var pool: Array = encounter.dynamic_pool(catalog, 25, func(_limit: int) -> int: return 0)
	assert_eq(pool.map(func(entry: EncounterEntry) -> int: return entry.weight),
		[32, 35, 30, 2, 1], "player level 25 uses the row-2 rarity weights")
	assert_eq(pool.map(func(entry: EncounterEntry) -> int: return entry.species),
		[40, 41, 42, 43, 44], "each non-zero rarity column picks its own grade")


## 缺记录时的降级球不能让 `nickname` 保持 -1：原生 `Ball_stdSet` 对负数
## `nickname_code` 写的是 `EFC_mainGetRAND() % 7`，所以落下来的性格必须落在 0..6，
## 否则 `Battle.make_ball` 的断言在 debug 下直接失败。
func test_unknown_ball_nickname() -> void:
	var catalog: GameplayData = Fixtures.data({"monsters": [{"id": 24, "attribute_group": 3}]})
	var species: MonsterDefinition = catalog.monster(24)
	var roll := func(limit: int) -> int: return limit - 1
	var unspecified: Dictionary = Wild._unknown_ball(
		species, 24, 5, Battle.NICKNAME_UNSPECIFIED, roll)
	assert_eq(unspecified.nickname, Battle.NICKNAMES.size() - 1,
		"neither record nor caller supplies a personality: Ball_stdSet rolls rand()%7")
	var record_personality := Battle.NICKNAMES.size() - 2
	var recorded: Dictionary = Wild._unknown_ball(species, 24, 5, record_personality, roll)
	assert_eq(recorded.nickname, record_personality, "the record's own personality is kept as-is")
