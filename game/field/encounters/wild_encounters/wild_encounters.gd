extends RefCounted
## 野外遭遇：野怪移动/接触判定与遭遇池的纯逻辑。

const Battle = preload("res://battle/combat/battle.gd")
const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const TILE := 16.0
const CONTACT_SQUARED := 600.0
const AGGRO_SQUARED := 4000.0
const LEASH_SQUARED := 16000.0
const SPEED := 80.0
const BOOKS := [
	[[36, 39, 42, 45, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 161],
		[37, 40, 43, 46], [38, 41, 44, 47]],
	[[0, 3, 6, 9, 24, 27, 30, 33, 60, 63, 66, 67, 70, 156, 158],
		[1, 4, 7, 10, 25, 28, 31, 34, 61, 64, 67, 71, 159],
		[2, 5, 8, 11, 26, 29, 32, 35, 62, 65, 68, 72, 160]],
	[[12, 15, 18, 21, 48, 51, 54, 57, 91, 94, 97, 100, 103, 106, 118, 121, 124, 127, 130, 133, 157],
		[13, 16, 19, 22, 49, 52, 55, 58, 92, 95, 98, 101, 104, 107, 119, 122, 125, 128, 131, 134],
		[14, 17, 20, 23, 50, 53, 56, 59, 93, 96, 99, 102, 105, 108, 120, 123, 126, 129, 132, 135]],
	[[73, 76, 79, 82, 85, 88, 109, 112, 115, 146, 149, 152, 155, 158, 165],
		[74, 77, 80, 83, 86, 89, 110, 113, 116, 147, 150, 153, 156, 159],
		[75, 78, 81, 84, 87, 90, 111, 114, 117, 148, 151, 154, 157, 167]],
]


static func bind(actors: Array, spawns: Array, assets: Node) -> void:
	var index := 0
	var identities := {}
	for actor: Dictionary in actors:
		if int(actor.id) < 1000:
			continue
		if not actor.has("wild"):
			var species := int(actor.get("species", int(actor.id) % 1000))
			var definition: MonsterDefinition = assets.load_gameplay_catalog().monster(species)
			if definition == null or definition.idle_frames <= 0:
				push_error("Wild species has no recorded idle animation: %d" % species)
				continue
			var idle_seconds: float = definition.idle_frames * 0.05
			var home := Vector2(actor.x, actor.y) * TILE
			if index < spawns.size():
				home = Vector2(spawns[index].tile_x, spawns[index].tile_y) * TILE
			actor.species = species
			if identities.has(int(actor.id)):
				actor.id = 10000 + index
				while identities.has(int(actor.id)):
					actor.id += 1
			actor.wild = {"home": home, "target": home, "state": 0,
				"idle": idle_seconds, "idle_seconds": idle_seconds}
		identities[int(actor.id)] = true
		index += 1


static func contact(actors: Array, hero: Vector2) -> Dictionary:
	var nearest := {}
	var distance := CONTACT_SQUARED
	for actor: Dictionary in actors:
		if not actor.has("wild"):
			continue
		var squared := hero.distance_squared_to(Vector2(actor.x, actor.y) * TILE)
		if squared < distance:
			nearest = actor
			distance = squared
	return nearest


static func _arrive(actor: Dictionary, target: Vector2, state: int) -> void:
	actor.wild.target = target
	actor.wild.state = state
	actor.action = state


static func _emotion(actor: Dictionary, action: int) -> void:
	actor.emotion = action
	actor.emotionFrame = 0
	actor.emotionRepeats = 1
	actor.emotionRevision = int(actor.get("emotionRevision", 0)) + 1


static func _passable(terrain: Dictionary, point: Vector2) -> bool:
	var tile := Vector2i((point + Vector2(8, 8)) / TILE)
	return tile.x >= 0 and tile.y >= 0 and tile.x < terrain.width_tiles and \
		tile.y < terrain.height_tiles and (int(terrain.cell_flags[tile.y][tile.x]) & 7) == 0


static func advance(actors: Array, terrain: Dictionary, hero: Vector2,
		delta: float, random: Callable) -> void:
	for actor: Dictionary in actors:
		if not actor.has("wild"):
			continue
		var state: Dictionary = actor.wild
		var point := Vector2(actor.x, actor.y) * TILE
		var squared := point.distance_squared_to(hero)
		if int(state.state) == 0:
			state.idle -= delta
			if state.idle > 0:
				continue
			_arrive(actor, state.home + Vector2(random.call(81) - 40,
				random.call(81) - 40), 5)
		if int(state.state) == 5 and squared < AGGRO_SQUARED:
			_emotion(actor, 7)
			_arrive(actor, hero, 7)
		if int(state.state) == 7:
			if squared < LEASH_SQUARED:
				state.target = hero
			else:
				_emotion(actor, 6)
				_arrive(actor, state.home, 8)
		var target: Vector2 = state.target
		var offset := target - point
		var step := Vector2.ZERO
		if offset != Vector2.ZERO:
			var squared_length := offset.length_squared()
			# JC_mathNORMAL truncates each integer square-root component, including diagonals.
			var vector := Vector2(
				floorf(sqrt(floorf(16.0 * offset.x * offset.x / squared_length))) * signf(offset.x),
				floorf(sqrt(floorf(16.0 * offset.y * offset.y / squared_length))) * signf(offset.y))
			step = vector * (SPEED * delta / 4.0)
			step.x = clampf(step.x, minf(0, offset.x), maxf(0, offset.x))
			step.y = clampf(step.y, minf(0, offset.y), maxf(0, offset.y))
		# Map_tileMove resolves the secondary axis before the facing/dominant axis.
		var axes := [Vector2(step.x, 0), Vector2(0, step.y)] if \
			absf(step.x) <= absf(step.y) else [Vector2(0, step.y), Vector2(step.x, 0)]
		var next := point
		for axis: Vector2 in axes:
			if _passable(terrain, next + axis):
				next += axis
		if offset != Vector2.ZERO:
			actor.lastDirection = (2 if offset.x > 0 else 1) if \
				absf(offset.x) > absf(offset.y) else (32 if offset.y > 0 else 16)
			actor.direction = actor.lastDirection
		actor.x = next.x / TILE
		actor.y = next.y / TILE
		if next == point or next.is_equal_approx(target):
			if int(state.state) == 7:
				_emotion(actor, 6)
				_arrive(actor, state.home, 8)
			else:
				if int(state.state) == 8:
					state.home = next
				state.state = 0
				state.idle = state.idle_seconds
				actor.action = FieldAction.Hero.IDLE


## 队伍成员原始参数不可用（`MenuModel.native_member_details` 拿不到 `ball`）时的降级球：只留
## 显示要用的字段，数值与上限留 null 由战斗侧按不可用处理。性格按 `Ball_stdSet` 落
## 合法值——调用方给 `Battle.NICKNAME_UNSPECIFIED` 时掷 `EFC_mainGetRAND() % 7`，所以这里的
## `nickname` 恒在 0..6，不会以 −1 进 `Battle.make_ball`（那一步只报一次错并按
## `Ball_stdNickAbils` 回落第 0 行）。
static func _unknown_ball(species: MonsterDefinition, id: int, level: int,
		nickname: int, roll: Callable) -> Dictionary:
	return {"species": id, "level": level,
		"nickname": Battle.nickname_or_roll(nickname, roll),
		"attribute": species.attribute_group - 1, "direction": 0,
		"hp": null, "max_hp": null, "sp": null, "max_sp": null}


static func _species(catalog: GameplayData, id: int) -> MonsterDefinition:
	return catalog.monster(id)


static func battle_entry(story: RefCounted, contacted: Dictionary) -> RefCounted:
	var catalog: GameplayData = story._gameplay()
	# 进图时 `Map_mifLOAD` 已经定好物种池与怪物等级（动态图按入口等级生成）。
	var level: int = story.encounter_level
	var pool: Array = story.encounter_pool
	if pool.is_empty():
		var encounter: EncounterDefinition = catalog.encounter(story.map.id)
		if encounter != null:
			level = encounter.resolved_world_level(int(story._player_level()))
			pool = encounter.dynamic_pool(catalog, int(story._player_level()), story._roll) \
				if encounter.is_dynamic() else encounter.pool
	var count := int(story._roll(2)) + 1 + (1 if level > 9 else 0)
	var enemies: Array = []
	var party: Array = []
	var total := 0
	for row: EncounterEntry in pool:
		total += row.weight
	var candidates := [int(contacted.species)]
	if total > 0:
		for slot in 2:
			var choice := int(story._roll(total))
			for row: EncounterEntry in pool:
				choice -= row.weight
				if choice < 0:
					candidates.append(row.species)
					break
	var mastery: Variant = story.progress.get("parameter", {}).get("development", {}).get("growth")
	var known_mastery: bool = mastery is Array and mastery.size() == 6 and mastery.all(
		func(value: Variant) -> bool: return value is int and value >= 1)
	var growth := 0
	if known_mastery:
		var sorted: Array = mastery.duplicate()
		sorted.sort()
		growth = maxi(0, int((int(sorted[3]) + int(sorted[4]) + int(sorted[5])) / 3) - 1)
	var passive_id := 0
	var passive_level := 0
	for slot in count:
		var id: int = candidates[slot]
		var species: MonsterDefinition = _species(catalog, id)
		var enemy_level := maxi(1, level - 2 + int(story._roll(4)))
		var awakened := int(story._roll(100)) < 5
		var grade := species.attribute_entry
		if int(story._roll(100)) < 30 and grade in range(BOOKS.size()):
			var rarity := int(story._roll(100))
			var table: Array = BOOKS[grade][0 if rarity < 80 else 1 if rarity < 95 else 2]
			passive_id = table[int(story._roll(table.size()))]
			passive_level = 1
		var nickname := Battle.roll_nickname(story._roll)
		enemies.append(Battle.make_ball(catalog,
			[id, enemy_level, growth, 0, 0, int(awakened), passive_id, passive_level, -1, -1],
			nickname) if known_mastery else
			_unknown_ball(species, id + (1000 if awakened else 0), enemy_level,
				nickname, story._roll))
	for index: int in MenuModel.native_party_order(story.progress):
		var details := MenuModel.native_member_details(story.progress, catalog, index)
		var member: Dictionary = story.progress.monsters[index]
		var ball: Dictionary
		if details.ball != null:
			ball = details.ball.duplicate(true)
			if known_mastery:
				var args: Array = ball.native_arguments.duplicate()
				args[2] = int(mastery[int(ball.attribute)])
				ball = Battle.make_ball(catalog, args, int(ball.nickname))
			ball.hp = member.hp if member.get("hp") != null else ball.max_hp
			ball.sp = member.sp if member.get("sp") != null else ball.max_sp
			ball.feel = int(member.get("feel", 0))
			ball.food = int(member.get("food", ItemEffect.FOOD_MAX))
		else:
			# 记录自带性格就照抄（原生记录里本来就有 `nickname_code`）；记录缺这一项时按
			# `Ball_stdSet` 的负数分支掷 `EFC_mainGetRAND() % 7`。`nativeArguments`
			# 在存档载入时已校验成 5 个整数（`story.gd` 的 `_integer_array(…, 5)`），可直接取等级。
			var recorded: Variant = member.get("nickname")
			ball = _unknown_ball(_species(catalog, int(member.species) % 1000),
				int(member.species), int(member.nativeArguments[1]),
				int(recorded) if recorded is int else Battle.NICKNAME_UNSPECIFIED,
				story._roll)
		party.append(ball)
	while enemies.size() < 3:
		enemies.append({})
	while party.size() < 3:
		party.append({})
	var battle := Battle.new(enemies, party)
	battle.catalog = catalog
	battle.allow_flee = true
	battle.hero_level = int(story.progress.parameter.level)
	# 捕获率用到的三个主角参数（`Battle_Capture_Action_IsCapture`）。
	var parameter: Dictionary = story.progress.parameter
	var development: Dictionary = parameter.get("development", {})
	var allocated: Variant = development.get("allocated", [])
	battle.hero_ability = int(allocated[2]) if allocated is Array and allocated.size() == 3 else 0
	battle.preferred_mastery = int(parameter.get("preferredMastery", -1))
	battle.standard_level = MenuModel.standard_level(story.progress)
	return battle
