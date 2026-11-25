extends "res://tests/unit/gut_case.gd"

const Battle = preload("res://game/battle/combat/battle.gd")
const BattleSettlement = preload("res://game/battle/combat/battle_settlement/battle_settlement.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")

var CATALOG: GameplayData = Fixtures.battle_catalog()


func test_legacy_suite() -> void:
	var party := [Battle.make_ball(CATALOG, [49, 66, -1, 0, 0, 0, 0, 0, 64, -1], 0)]
	assert_true(party[0]["stats"] == [346, 146, 368, 140, 744, 825], str(party[0]))
	# 性格越界按原生「照存 + 消费方回落」：`Ball_stdNickAbils` 行 18 对 `n6 > 6` 取第 0 行
	# （六项全 0），所以越界球的数值与性格 0 的球逐项相同；负值由 `Ball_stdSet` 掷一次。
	var out_of_range := Battle.make_ball(CATALOG, [49, 66, -1, 0, 0, 0, 0, 0, 64, -1],
		Battle.NICKNAMES.size())
	assert_eq([out_of_range["nickname"], out_of_range["stats"]],
		[Battle.NICKNAMES.size(), party[0]["stats"]],
		"越界的性格号照存，偏置按 Ball_stdNickAbils 回落第 0 行")
	assert_eq(Battle.nickname_or_roll(Battle.NICKNAME_UNSPECIFIED,
		func(limit: int) -> int: return limit - 1), Battle.NICKNAMES.size() - 1,
		"缺省 -1 等价于掷一次（Ball_stdSet 的 EFC_mainGetRAND() % 7）")
	var battle = Battle.new(_battle_enemies(), _battle_party(), func(_limit: int) -> int: return 0)
	assert_true(battle.actor == 5 and battle.get_manual(), "highest current speed acts first")
	battle.actor = 3
	var result: Dictionary = battle.act("skill", 0, {49: {AniAction.Clip.SKILL: 16,
		AniAction.Clip.CLONE_B: 3}})
	assert_true(result.ok and battle.turns == 1 and
		int(battle.balls[0]["hp"]) < int(battle.balls[0]["max_hp"]),
		"a skill resolves one turn and damages the target")
	# 捕获（`Battle_Capture_Action_IsCapture`）：品级 0、满血、无加成 = 90 − 30 = 60%；
	# 同属性球 ×1.5（物种 93 的属性是 4，即 type 5 index 5），血越少越高（50% → +15）。
	var target := _ball(93, 41)
	var plain := {"type": 5, "index": 0}
	assert_true(Battle.capture_rating(target, plain, 99, 0, -1, 0) == 60 and
		Battle.capture_rating(target, {"type": 5, "index": 5}, 99, 0, -1, 0) == 90,
		"capture rating uses the grade base and the matching attribute ball")
	target.hp = int(target.max_hp) / 2
	assert_eq(Battle.capture_rating(target, plain, 99, 0, -1, 0), 75)
	var capture := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	capture.allow_flee = true
	var attempt: Dictionary = capture.capture(plain, 0)
	assert_true(attempt.ok and attempt.caught and capture.balls[0].is_empty() and
		attempt.steps.size() == 34 and int(attempt.record.species) == 93,
		"a successful capture removes the enemy and yields a party record")
	# 败北后的复活（`Battle_Die_Revival` 的 0 档）：`Ball_stdInit(state, -1, 100, 100,
	# 100, 100)` 把速度／HP／SP 回满，随后这场战斗继续（`Battle_Die_mRun` 的 4／8 段
	# `BattleCanvas_SetNext(BATTLE_STATE_POSITION)`），所以 `result` 必须回到 null。
	var down := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	for index in range(3, down.balls.size()):
		down.balls[index].hp = 0
	down.result = "lost"
	assert_true(down.revive() and down.result == null, "revival resumes the battle")
	assert_eq([int(down.balls[3].hp), int(down.balls[5].sp), int(down.balls[4].speed)],
		[int(down.balls[3].max_hp), int(down.balls[5].max_sp), int(down.balls[4].stats[5])],
		"revival refills speed, HP and SP")
	# 战斗内道具（`Ball_stdUse` 的第 1 组分支）：HP 满返回 2、对倒下的对象用回复药返回 35、
	# 复活道具（索引 17／18）对活着的不生效（10），只对倒下的按百分比回 HP（9）。
	var items := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var heal := {"id": 1000, "detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0]}
	var revive_item := {"id": 1017, "detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0]}
	var full := int(items.use_item(heal, 3).get("code", 0))
	items.balls[3].hp = 0
	var downed := int(items.use_item(heal, 3).get("code", 0))
	var alive := int(items.use_item(revive_item, 4).get("code", 0))
	var recovered: Dictionary = items.use_item(revive_item, 3)
	assert_eq([full, downed, alive, int(recovered.get("code", 0)), int(items.balls[3].hp)],
		[ItemEffect.Code.HP_FULL, ItemEffect.Code.TARGET_DOWN, ItemEffect.Code.NOT_DOWN, ItemEffect.Code.REVIVED,
			int(items.balls[3].max_hp) * 10 / 100],
		"battle items return the native Ball_stdUse codes and only revive downed members")
	# 经验 +20% 窗口（`Ball_stdUse:1060-1070` 的第 7 组第 18 号）：第一次开窗 1 小时并扣道具，
	# 窗口还在时再用返回 36 且不重置；行上的 `parameter` 是存档参数表的同一份引用。
	var window := {StoryRuntime.EXP_BONUS_KEY: 0}
	var bonus_item := {"id": ItemKind.id_of(ItemKind.Kind.GROUP_7, ItemEffect.EXP_BONUS_INDEX),
		"detail_slots": [], "parameter": window}
	var opened: Dictionary = ItemEffect.apply(items.balls[4].duplicate(true), bonus_item)
	var reopened: Dictionary = ItemEffect.apply(items.balls[4].duplicate(true), bonus_item)
	assert_eq([int(opened.get("code", 0)), bool(opened.get("consumed", false)),
		int(reopened.get("code", 0)), bool(reopened.get("consumed", false)),
		int(window[StoryRuntime.EXP_BONUS_KEY])],
		[ItemEffect.Code.EXP_BONUS, true, ItemEffect.Code.EXP_BONUS_ACTIVE, false,
			StoryRuntime.EXP_BONUS_MILLISECONDS],
		"the exp bonus item opens a 3600000 ms window once and refuses to reset it")
	# `Ball_stdUseEx:205-208` 的 `case 36` 只给一条 509「已在使用中.」；28 原生无提示。
	assert_eq([ItemEffect.message_id(ItemEffect.Code.EXP_BONUS_ACTIVE),
		ItemEffect.message_id(ItemEffect.Code.EXP_BONUS)],
		[Msg.Id.ITEM_BONUS_ACTIVE, 0],
		"only the already-active code has a message record")
	# 窗口内的战斗经验是基础值的 ×1.2（`Battle_Win_SetResult:180-181` 把 20 并进 `n20`）。
	var plain_gain: int = BattleSettlement._base_experience(items, false, {})
	var boosted_gain: int = BattleSettlement._base_experience(items, false,
		{StoryRuntime.EXP_BONUS_KEY: StoryRuntime.EXP_BONUS_MILLISECONDS})
	assert_eq([plain_gain, boosted_gain],
		[plain_gain, plain_gain + plain_gain / StoryRuntime.EXP_BONUS_DIVISOR],
		"an active exp bonus window adds a fifth of the battle experience")
	# 食物／心情道具（`Ball_stdUse` 的 31–36／37／第 7 组 20 三段）：31–36 按物种属性判口味，
	# 对口味时饥饿（`food <= 30`）心情 +30、吃饱（`food > 30`）只 +10，不对口味固定 +5，
	# 两者都把饱食度补满；37 号只补饱食度，`food > 99` 时返回 18「饥饿度已达上限」；
	# 7020 饥饿时心情 +140。
	var fed := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var taste: int = ItemEffect.FOOD_ATTRIBUTES.find(int(fed.balls[3].attribute))
	var food_item := func(slot: int) -> Dictionary:
		return {"id": 1000 + ItemEffect.ITEM_FIRST_FOOD + slot, "detail_slots": []}
	fed.balls[3].food = 10
	var good := int(fed.use_item(food_item.call(taste), 3).get("code", 0))
	var hungry_feel := int(fed.balls[3].feel)
	var wrong := int(fed.use_item(food_item.call((taste + 1) % 6), 3).get("code", 0))
	var full_feel := int(fed.balls[3].feel)
	var stuffed := int(fed.use_item({"id": 1000 + ItemEffect.ITEM_LAST_FOOD, "detail_slots": []}, 3).get("code", 0))
	fed.balls[3].food = 50
	var restored := int(fed.use_item({"id": 1000 + ItemEffect.ITEM_LAST_FOOD, "detail_slots": []}, 3).get("code", 0))
	fed.balls[3].food = 20
	var marble := int(fed.use_item({"id": ItemEffect.super_marble_id(), "detail_slots": []}, 3).get("code", 0))
	assert_eq([good, hungry_feel, wrong, full_feel, stuffed, restored, marble, int(fed.balls[3].feel)],
		[ItemEffect.Code.FEEL_GOOD, 30, ItemEffect.Code.FEEL_BAD, 35, ItemEffect.Code.FOOD_STUFFED,
			ItemEffect.Code.FOOD_RESTORED, ItemEffect.Code.FEEL_GOOD, 175],
		"food items follow the native taste table and the food/feel clamps")
	# 被动 21（`Ball_stdUse` 的 `0x86ed6`／`0x87178`）：心情增量再叠加该值。
	fed.balls[3].passives.fill(0)
	fed.balls[3].passives[ItemEffect.FEEL_PASSIVE] = 40
	fed.balls[3].food = 10
	var before_passive := int(fed.balls[3].feel)
	fed.use_item(food_item.call(taste), 3)
	assert_eq(int(fed.balls[3].feel) - before_passive, 30 + 40,
		"passive 21 adds its value to the food feel gain")
	# 原生是 `if ((char)v106[21] > 0)`：负的被动 21 不加（也不减）心情。
	fed.balls[3].passives[ItemEffect.FEEL_PASSIVE] = -40
	fed.balls[3].food = 10
	var before_negative := int(fed.balls[3].feel)
	fed.use_item(food_item.call(taste), 3)
	assert_eq(int(fed.balls[3].feel) - before_negative, 30,
		"a negative passive 21 is ignored, not subtracted")
	# 心情到 999 的觉醒（`Ball_stdFeel` 的 LABEL_5）：状态码置 3、物种号 +1000、
	# 心情退回旧状态码 0、标准被动槽 2–5 清空、`Ball_stdBasic` 重算后 HP／SP 回满。
	# 这里是 `n999 > 999` 那一支（998 + 30 = 1028）：第 20 行把 `feel_value` 夹到 999 后
	# 顺序落进 `LABEL_5`，溢出同样觉醒。
	var evolving := Battle.new(_battle_enemies(),
		[Battle.make_ball(CATALOG, [49, 66, -1, 0, 0, 0, 3, 1, -1, -1], 0), _ball(62, 60),
			_ball(86, 62)], func(_limit: int) -> int: return 0)
	evolving.catalog = CATALOG
	var grown: Dictionary = evolving.balls[3]
	var passive_effect := int(CATALOG.passive(3).effect)
	var before_awaken := int(grown.passives[passive_effect])
	grown.feel = ItemEffect.FEEL_MAX - 1
	grown.food = 10
	var awakening: Dictionary = evolving.use_item(
		food_item.call(ItemEffect.FOOD_ATTRIBUTES.find(int(grown.attribute))), 3)
	assert_eq([int(grown.species), int(grown.feel_state), int(grown.feel),
		before_awaken, int(grown.passives[passive_effect]), int(grown.hp), int(grown.max_hp),
		bool(awakening.get("evolved", false))],
		[49 + Battle.AWAKENED_SPECIES_OFFSET, ItemEffect.FeelState.AWAKENED, 0,
			int(CATALOG.passive(3).base), 0, int(grown.max_hp), int(grown.max_hp), true],
		"feel 999 awakens: species +1000, state 3, passive slots 2-5 cleared, HP refilled")
	# 吃饱（`food > 30`）时对口味只 `feel += 10`（`Ball_stdUse` 的 31–36 分支）。
	var satisfied_gain := 10
	var below := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	below.catalog = CATALOG
	below.balls[3].feel = ItemEffect.FEEL_MAX - 100
	below.use_item(food_item.call(taste), 3)
	assert_eq([int(below.balls[3].species), int(below.balls[3].feel_state), int(below.balls[3].feel)],
		[49, ItemEffect.FeelState.NORMAL, ItemEffect.FEEL_MAX - 100 + satisfied_gain],
		"a feel gain below 999 keeps the species, the state code and adds the gain")
	# `Ball_stdFeel` 的另一条进 `LABEL_5` 的路是恰好 `== 999`（第 41–42 行的
	# `(int16)n999 == 999`）：饱食时不减半的 10 点刚好把 989 顶到 999，同样觉醒。
	var exact := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	exact.catalog = CATALOG
	exact.balls[3].passives.fill(0)
	exact.balls[3].food = ItemEffect.FOOD_MAX
	exact.balls[3].feel = ItemEffect.FEEL_MAX - satisfied_gain
	var exact_before: int = int(exact.balls[3].feel)
	var exact_result: Dictionary = exact.use_item(food_item.call(taste), 3)
	var exact_species: int = int(exact.balls[3].species)
	assert_eq([exact_before + satisfied_gain, bool(exact_result.get("evolved", false)),
		exact_species, int(exact.balls[3].feel_state), int(exact.balls[3].feel)],
		[ItemEffect.FEEL_MAX, true, 49 + Battle.AWAKENED_SPECIES_OFFSET,
			ItemEffect.FeelState.AWAKENED, 0],
		"feel that lands exactly on 999 also awakens")
	# 阵亡扣心情（`Param_dmgNUMBER` 在 HP 归零、原来非 0 时 `Ball_stdFeel(ball, -20)`）。
	var dying := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	dying.balls[0].feel = 50
	dying.balls[0].hp = 1
	dying._hit(3, 0, false, 100, {0: 999}, false)
	assert_eq(int(dying.balls[0].feel), 30, "a defeated monster loses 20 feel")
	# 饱食度 0 时 `atk1/atk2` 与 `def1/def2` 的百分比减半（`Param_dmg1BASIC`／`Param_dmg2BASIC`）。
	var hungry := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var fed_damage := int(hungry._base_damage(hungry.balls[3], hungry.balls[0], false))
	hungry.balls[3].food = 0
	var hungry_attack := int(hungry._base_damage(hungry.balls[3], hungry.balls[0], false))
	hungry.balls[3].food = ItemEffect.FOOD_MAX
	hungry.balls[0].food = 0
	var hungry_defense := int(hungry._base_damage(hungry.balls[3], hungry.balls[0], false))
	assert_true(fed_damage > 0 and hungry_attack < fed_damage and hungry_defense > fed_damage,
		"an empty stomach halves the attack and defense percentages")
	# 相性倍率只缩放技能（`Param_dmg2BASIC:98-105`：有利 `+40%`、不利 `−60%`）。普攻走
	# `Param_dmg1BASIC`，同一张表（`CSWTCH.95_0`）的两列在那里只当 0／1 闸门
	# （有利掷攻击方 39、不利掷受方 33／36），不参与伤害算术，所以三档普攻伤害相同。
	var odds := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	odds.balls[3].passives.fill(0)
	odds.balls[0].passives.fill(0)
	odds.balls[3].attribute = 0
	odds.balls[0].attribute = 1
	var favored := int(odds._base_damage(odds.balls[3], odds.balls[0], false))
	var favored_skill := int(odds._base_damage(odds.balls[3], odds.balls[0], true))
	odds.balls[0].attribute = 3
	var neutral := int(odds._base_damage(odds.balls[3], odds.balls[0], false))
	var neutral_skill := int(odds._base_damage(odds.balls[3], odds.balls[0], true))
	odds.balls[0].attribute = 5
	var opposed := int(odds._base_damage(odds.balls[3], odds.balls[0], false))
	var opposed_skill := int(odds._base_damage(odds.balls[3], odds.balls[0], true))
	assert_eq([favored > 0, favored, neutral, opposed], [true, neutral, neutral, neutral],
		"普攻不按相性缩放（Param_dmg1BASIC 的两列只是 39／33／36 的闸门）")
	assert_eq([favored_skill, opposed_skill],
		[neutral_skill + int(Battle.SKILL_ADVANTAGE_DAMAGE_PERCENT * neutral_skill / 100),
			neutral_skill + int(Battle.SKILL_DISADVANTAGE_DAMAGE_PERCENT * neutral_skill / -100)],
		"技能的相性倍率是有利 +40%、不利 −60%（Param_dmg2BASIC）")
	# 被动效果编号必须与模型真正读到的读取点一致：普攻／技能攻击加成 0–7、防守加成 12–19、
	# 暴击 8–11、速度削减 26、经验 23、金钱 61（读取点见 `battle.gd` 的常量注释）。
	var passive := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	passive.balls[3].passives.fill(0)
	passive.balls[3].passives[4] = 20
	passive.balls[3].passives[61] = 50
	var supported := Battle.SUPPORTED_PASSIVE_EFFECTS
	assert_true(passive.support_error().is_empty() and supported.has(4) and
		supported.has(61) and supported.has(48) and supported.has(39) and supported.has(45) and
		supported.has(3) and supported.has(7) and supported.has(21) and supported.has(57) and
		supported.has(59) and supported.has(64),
		"the supported passive list matches the effect numbers the model reads")
	# 3／7 在出货二进制里恒不生效（`ext[537]` 全库无写入点），所以带它们的怪不再被挡住。
	passive.balls[3].passives[3] = 50
	assert_true(passive.support_error().is_empty(), "passive 3 no longer blocks the battle")
	# 被动 64（`Battle_Delay_init` 的 `0x34dfe`）：技能这一手把 `ext[536]`
	# （`Battle.AiTargetGroup`）写成这一手的目标组，`Battle_Menu_Auto` 在它非 0 时不再选技能；
	# 掷中被动 64 就把刚写的清回 0，AI 才能连着放技能。
	var backoff = Battle.new(_battle_enemies(), _battle_party(),
		func(value: int) -> int: return value - 1)
	backoff.actor = 3
	backoff.act("skill", 0, {49: {AniAction.Clip.SKILL: 16, AniAction.Clip.CLONE_B: 3}})
	var written := int(backoff.balls[3]["ai_target_group"])
	backoff.actor = 3
	backoff.balls[3].cooldown = 0
	backoff.balls[3].sp = int(backoff.balls[3].max_sp)
	var gated := String(backoff.auto_action()["action"])
	backoff.balls[3]["ai_target_group"] = Battle.AiTargetGroup.NONE
	var ungated := String(backoff.auto_action()["action"])
	assert_eq([written, gated, ungated], [Battle.AiTargetGroup.SINGLE, "attack", "skill"],
		"a single-target skill queues the AI backoff and the non-zero group blocks the next skill")
	backoff.actor = 3
	backoff.balls[3].passives[Battle.SKILL_BACKOFF_PASSIVE] = 100
	backoff.act("skill", 0, {49: {AniAction.Clip.SKILL: 16, AniAction.Clip.CLONE_B: 3}})
	assert_eq(int(backoff.balls[3]["ai_target_group"]), Battle.AiTargetGroup.NONE,
		"passive 64 clears the backoff it was queued with on the same turn")
	# 普攻侧的被动（`Param_dmg1BASIC`）：37／38／39 是必杀（伤害 = 目标最大 HP）、
	# 31／32／33 是无效化（伤害归零）、30 把伤害记进攻击方的吸血池（受伤时按池回血）、
	# 35／36 让受方立即反击（把自己的 `ext[539]` 置成 35、锁住攻击方，见下方断言）。
	var brutal := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	brutal.balls[3].passives[37] = 100
	var lethal := int(brutal._base_damage(brutal.balls[3], brutal.balls[0], false))
	brutal.balls[3].passives.fill(0)
	brutal.balls[0].passives[31] = 100
	var blocked := int(brutal._base_damage(brutal.balls[3], brutal.balls[0], false))
	brutal.balls[0].passives[31] = 0
	brutal.balls[3].passives[30] = 100
	var drained := int(brutal._base_damage(brutal.balls[3], brutal.balls[0], false))
	assert_eq([lethal, blocked, drained, int(brutal.balls[3].drain)],
		[int(brutal.balls[0].max_hp), 0, drained, drained],
		"passive 37 kills, 31 negates and 30 fills the drain pool with the same damage")
	# 被动 59（`Battle_Ready_Set`）：开场逐只掷 `rand()%100 < passives[59]`，命中写
	# `ext[539] = 100` 与 `obj+264`；两条阵营链共用一个「上一只」寄存器，所以只留最后一只。
	var ready_enemies := _battle_enemies()
	var ready_party := _battle_party()
	ready_enemies[0].passives[Battle.PRIORITY_PASSIVE] = 100
	ready_party[2].passives[Battle.PRIORITY_PASSIVE] = 100
	var ready := Battle.new(ready_enemies, ready_party, func(_limit: int) -> int: return 0)
	assert_eq([int(ready.balls[0].priority), int(ready.balls[5].priority),
		int(ready.balls[5].designated_target), ready.actor],
		[0, Battle.PRIORITY_BOOST, 0, 5],
		"passive 59 keeps the first-strike priority only on the last roller")
	# 35／36（`Param_dmg1BASIC` 的 `0x79938`／`0x79ab0`）：受方被普攻打中后把自己的
	# `ext[539]` 置成 35、`obj+264` 指向攻击方（相性不利时再叠加 36，上限 255）。
	var counter := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	counter.balls[0].passives[Battle.COUNTER_PRIORITY_PASSIVE] = 60
	counter._base_damage(counter.balls[3], counter.balls[0], false)
	assert_eq([int(counter.balls[0].priority), int(counter.balls[0].designated_target)],
		[60, 3], "passive 35 makes the defender strike back at whoever hit it")
	# 539 的「跳过延迟」（`Battle_Delay_Proc` 的 `0x34ade`）：清 0 后直接返回，不扣 200 速度。
	var skipping := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var striking: Dictionary = skipping.balls[3]
	striking.priority = Battle.PRIORITY_BOOST
	var before_delay := int(striking.speed)
	skipping._delay(striking)
	var ordinary: Dictionary = skipping.balls[4]
	skipping._delay(ordinary)
	assert_eq([int(striking.speed), int(striking.priority),
		int(ordinary.stats[5]) - int(ordinary.speed)],
		[before_delay, 0, 200],
		"a priority turn skips the native 200-speed delay")
	# 技能侧按属性分档的免疫（40–45）与「倒下后自动复活一次」的 58（`Battle_Position_mRun`）。
	var warded := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	warded.balls[0].passives[40 + int(warded.balls[3].attribute)] = 100
	warded.balls[4].passives[58] = 50
	warded.balls[4].hp = 0
	assert_eq([int(warded._base_damage(warded.balls[3], warded.balls[0], true)),
		int(warded.revive_by_passive()), int(warded.balls[4].hp)],
		[0, 4, int(int(warded.balls[4].max_hp) * 50 / 100)],
		"passive 40-45 negates a skill by the attacker attribute and 58 revives a fainted member")
	# 命中附状态（`Param_dmg1PASSIVE`）：攻击方被动 25 掷中 → 目标中毒，目标被动 48
	# 抗性掷中时把状态反弹回攻击者；本次伤害不小于目标当前 HP（一击必杀）时不附状态。
	# 返回值是这次要报「被动发动」的对象序号（原生两组 `Param_atkPASSIVE`：攻击方的 25–29、
	# 受方抵抗成立时的 48／49／50／53／54）。
	var inflicting := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	inflicting.balls[3].passives[25] = 100
	var poisoned_target: Array = inflicting._passive_status(3, 0, 10)
	inflicting.balls[1].passives[48] = 100
	var rebounded: Array = inflicting._passive_status(3, 1, 10)
	assert_true(poisoned_target == [3] and
		inflicting.balls[0].statuses.has(StatusEffect.Code.POISON_HIGH) and
		rebounded == [3, 1] and inflicting.balls[3].statuses.has(StatusEffect.Code.POISON_HIGH) and
		inflicting._passive_status(3, 2, int(inflicting.balls[2].hp)).is_empty(),
		"passive 25 inflicts poison, the 48 resistance rebounds it, and a lethal hit carries none")
	# 同一份名单要随命中结果交给界面（`battle_view` 据此推 556「发动」）。
	var landing: Dictionary = inflicting._hit(3, 0, false, 100,
		{0: int(inflicting.balls[0].hp) / 2}, false)
	assert_eq(landing.get("activated_passives", []), [3],
		"the landed hit carries the passive owner for the 556 notice")
	# 技能附状态时的反弹（`Param_dmg2SKILL` 的 `case 1`／`0x18–1A`／`case 6`）：受方被动
	# 掷中就改附给施术者，强度档换成攻击方的 `v33`（攻击方相性不利才 +3）；没这条被动就照常附给受方。
	var reflecting := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	reflecting.balls[0].passives[Battle.REFLECT_SKILL_6_PASSIVE] = 100
	var reflected: Dictionary = reflecting._skill_status_hit(3, 0, 6, 6)
	var relation := int(reflecting._strength(reflecting.balls[3], reflecting.balls[0]))
	assert_true(int(reflected.target) == 3 and reflecting.balls[3].statuses.has(6) and
		not reflecting.balls[0].statuses.has(6) and
		int(reflecting.balls[3].statuses[6].remaining) == (3 if relation == -1 else -3),
		"passive 52 sends the skill-6 status back to the caster with the v33 tier")
	reflecting.balls[0].passives[Battle.REFLECT_SKILL_6_PASSIVE] = 0
	reflecting.balls[0].passives[Battle.REFLECT_SKILL_18_PASSIVE] = 100
	assert_eq([int(reflecting._skill_status_hit(3, 0, 6, 6).target),
		int(reflecting._skill_status_hit(3, 0, 25, BattleSpeciesTable.SKILL_CODE_UNRECORDED).target)],
		[0, 0], "without the matching passive, or without a recorded skill code, nothing rebounds")
	assert_eq([BattleSpeciesTable.skill_code(BattleSpeciesTable.segments(90, true)[0]["hits"][0]),
		BattleSpeciesTable.skill_code({})],
		[6, BattleSpeciesTable.SKILL_CODE_UNRECORDED],
		"the export carries the native n0x31 skill code and reports the missing one")
	# 技能码 6 的技能整支不兑现伤害：`Battle_Skill_init` 只把池子预算进 `PINFO`，兑现只发生在
	# `Param_dmg2SKILL` 的 `LABEL_20`／`LABEL_21`，`case 6` 附完状态就 `break`。
	var casting: Dictionary = Battle.make_ball(CATALOG, [49, 66, -1, 0, 0, 0, 0, 0, -1, -1], 0)
	casting["species"] = 90
	var casting_party := _battle_party()
	casting_party[0] = casting
	var cast = Battle.new(_battle_enemies(), casting_party, func(_limit: int) -> int: return 0)
	cast.actor = 3
	var untouched := int(cast.balls[0].hp)
	assert_true(cast.act("skill", 0, {90: {AniAction.Clip.SKILL: 16}}).ok and
		int(cast.balls[0].hp) == untouched and cast.balls[0].statuses.has(6),
		"skill code 6 attaches its slot without touching HP")
	# 中毒（状态码 27／28／29 = 主动效果槽 `球记录 + 60 + 12 × 码`）：`Param_dmgPOISON` 的
	# 伤害 = 强度 × 等级百分比 × 层数 / 100，第一段的等级 1／2／3 分别 10／30／50%；结算后槽的
	# id 递减（3 → 2 → 1 → 清槽），所以同一槽逐回合减弱、第三档结算完就消失。
	var poisoned := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	poisoned.balls[0].statuses = {StatusEffect.Code.POISON_HIGH:
		{"stacks": 2, "remaining": 3, "value": 300}}
	var first: Dictionary = poisoned.settle_poison(0)
	var second: Dictionary = poisoned.settle_poison(0)
	assert_eq([int(first.damage), int(second.damage), int(poisoned.balls[0].hp)],
		[300, 180, int(poisoned.balls[0].max_hp) - 480],
		"poison settles with the native tier table and drops one tier per turn")
	var third: Dictionary = poisoned.settle_poison(0)
	assert_true(int(third.damage) == 60 and
		not poisoned.balls[0].statuses.has(StatusEffect.Code.POISON_HIGH),
		"the last poison tier settles at 10% and then clears the slot")
	# 被动 57（`Battle_Poison_init` 的 `0x385d6`）：毒回合先按上限的 `值%` 回血、再结算毒伤。
	var healing := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var healer: Dictionary = healing.balls[3]
	var heal_percent := 20
	var poison_value := 100
	var poison_tier := 3
	healer.passives.fill(0)
	healer.passives[Battle.POISON_HEAL_PASSIVE] = heal_percent
	healer.statuses = {StatusEffect.Code.POISON_HIGH: {
		"stacks": 1, "remaining": poison_tier, "value": poison_value}}
	healer.hp = int(healer.max_hp) / 2
	var before_heal := int(healer.hp)
	var healed: Dictionary = healing.settle_poison(3)
	var expected_tick := poison_value * \
		int(Battle.POISON_PERCENT[StatusEffect.POISON_CODES.find(StatusEffect.Code.POISON_HIGH)]
			[poison_tier - 1]) / 100
	assert_eq([int(healed.damage), int(healer.hp)],
		[expected_tick, before_heal + int(healer.max_hp) * heal_percent / 100 - expected_tick],
		"passive 57 heals before the poison tick")
	# 主动效果槽的读取（`Param_atk1ACTIVE`／`Param_atk2ACTIVE`／
	# `Param_def1ACTIVE`）：普攻攻击加成读槽 12／13（每层 ×(rand%2+2)／×(rand%3+2)），
	# 技能攻击加成读槽 14–17（每层 +100／150／200／250%），两组都读弱点 21（每层
	# `20 × (1 − |id|) − 10`）；防御读槽 9／10／11（−50／−60／−70 每层）与槽 33 防御（+100 每层）。
	var slotted := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	slotted.balls[3].statuses[12] = {"stacks": 1, "remaining": 3}
	slotted.balls[3].statuses[StatusEffect.Code.WEAKNESS] = {"stacks": 1, "remaining": 3}
	assert_eq([slotted._active_attack(slotted.balls[3], false),
		slotted._active_attack(slotted.balls[3], true)], [200 - 50, 100 - 50],
		"attack slots follow the native atk1/atk2ACTIVE tables")
	slotted.balls[4].statuses[StatusEffect.Code.DEFENCE] = {"stacks": 1, "remaining": 1}
	slotted.balls[4].statuses[9] = {"stacks": 1, "remaining": 3}
	assert_eq(slotted._active_defense(slotted.balls[4]), 100 + 100 - 50,
		"defence and shield slots follow the native def1ACTIVE table")
	# 异常状态治疗道具（`Ball_stdUse` 的索引 8–16）：索引 8 清毒槽 27／29 并返回 7，
	# 没有可治疗的状态时返回 8；索引 16 清全部槽。减速状态 38／39／40 只减速度、不打伤害。
	var curable := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	curable.balls[3].statuses = {
		StatusEffect.Code.POISON_HIGH: {"stacks": 1, "remaining": 3, "value": 200},
		StatusEffect.Code.WEAKNESS: {"stacks": 1, "remaining": 3}}
	var cure := {"id": 1008, "detail_slots": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	assert_eq([int(curable.use_item(cure, 3).get("code", 0)), curable.balls[3].statuses.size()],
		[ItemEffect.Code.CURED, 1], "the curse item clears the poison slots and keeps the weakness")
	assert_eq(int(curable.use_item({"id": 1016, "detail_slots": []}, 3).get("code", 0)),
		ItemEffect.Code.CURED, "index 16 clears every slot")
	var slowed := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var slow_hit: Dictionary = slowed._status_hit(3, 0, 39)
	assert_true(int(slow_hit.damage) == 0 and int(slow_hit.speed_loss) == 50 and
		int(slowed.balls[0].speed) == int(slowed.balls[0].stats[5]) - 50,
		"the slow status takes 50 speed off the target without damage")
	# 状态码 35（原生 `case 0x23`）清目标的 17 个槽（毒／封印／护盾／回复／减伤），不动攻防加成槽；
	# 36／37／49（`LABEL_21`）按目标当前 HP 的百分比打伤害，并对自己再打一次同样的数值。
	var purged := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	purged.balls[0].statuses = {
		StatusEffect.Code.POISON_HIGH: {"stacks": 1, "remaining": 3, "value": 100},
		StatusEffect.Code.SEAL: {"stacks": 1, "remaining": 3}, 12: {"stacks": 1, "remaining": 3}}
	purged._status_hit(3, 0, 35)
	assert_eq(purged.balls[0].statuses.keys(), [12],
		"the purge skill clears exactly the 17 native slots")
	var recoil := Battle.new(_battle_enemies(), _battle_party(),
		func(_limit: int) -> int: return 0)
	var target_hp := int(recoil.balls[0].hp)
	var actor_hp := int(recoil.balls[3].hp)
	var shares: Array = recoil._percent_hp_hit(3, 0, 36, 50)
	assert_eq([shares.size(), target_hp - int(recoil.balls[0].hp),
		actor_hp - int(recoil.balls[3].hp)],
		[2, target_hp / 2, actor_hp / 2],
		"the percent-HP hit damages the target and the caster by the same share")


func _ball(species: int, level: int, equipment: int = -1) -> Dictionary:
	return Battle.make_ball(CATALOG, [species, level, -1, 0, 0, 0, 0, 0, equipment, -1], 0)


func _battle_enemies() -> Array:
	return [_ball(93, 41),
		Battle.make_ball(CATALOG, [99, 41, -1, 0, 0, 1, 0, 0, -1, -1], 0), _ball(13, 41)]


func _battle_party() -> Array:
	return [_ball(49, 66), _ball(62, 60), _ball(86, 62)]
