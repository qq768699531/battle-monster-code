extends RefCounted

## 公会战（原生 `Game_Guild_Battle_init`，游戏状态 5／6 → `BattleCanvas_load`
## 写进 `BattleData+0x40` 的 `battle.kind` 3／4）的数据侧：对手阵容、开战与胜利回写。
##
## **对手不是随机三只**：`Item_datBasic` 以类型 **28** 取 `item_guild.dat`，组号
## `99 − code % 1000`，`code` 是 `GameCanvas_SetNext` 带过来的转移参数（状态 5 =
## `ParamData.guild_code_bits`、状态 6 = 事件 opcode 33 的参数）。该组三条记录依次
## `Ball_stdSet` 填 `ItemData.online_battle_monsters[0..2]`
## （`wiki\field\guild-pages.md` §5、`wiki\data-format\dat-item-guild.md`）。
##
## 本工程把一组三条记录存成一条 `GameplayData.items` 记录：`type = 28`、`index = 组号`、
## `detail_slots` = 三条 × 5 槽（原生 `item_guild.dat` 的字段顺序）、`name_record` = 三条共用的
## 数字参数（原生 `atoi(首条记录名)`，1–99）。**表里没有这个组就返回 `{ok: false, error}`**，
## 不生成替代阵容。

const Battle = preload("res://battle/combat/battle.gd")
const ItemKind = preload("res://menu/items/item_kind/item_kind.gd")
const MenuModel = preload("res://menu/menu_model/menu_model.gd")
const MonsterAttribute = preload("res://core/monster_animation/monster_attribute/monster_attribute.gd")
const Story = preload("res://core/story/story.gd")

## 状态 5 = 挑战页进（`Field_Guild_Challenge_mKeyPressed` 的
## `GameCanvas_SetNext(GAME_STATE_GUILD_BATTLE_5, guild_code)`）；只有 `kind == 3` 的胜利会在
## `Battle_Win_mRun` 里把公会码 −1（`wiki\field\guild-pages.md` §3.2）。
const KIND_CHALLENGE := 3
## 状态 6 = 事件脚本 opcode 0x21／33 的公会战，不结算名次。
const KIND_EVENT := 4
## `Item_datBasic` 的类型号：28 = `item_guild.dat`（`wiki\data-format\dat-item-guild.md`）。
const GROUP_TYPE := 28
## 组号换算式 `99 − code % 1000` 里的基数；`item_guild.dat` 真实样本有 98 组，所以组号 1–98。
const GROUP_BASE := 99
const GROUP_MIN := 1
const GROUP_MAX := 98
## 每组记录的槽序（原生 `item_guild.dat` 的三条 × 5 字段）。
enum Slot { SPECIES, AWAKENED, PASSIVE, PASSIVE_LEVEL, EQUIPMENT_PLUS_ONE }
const MONSTERS := 3
const SLOTS_PER_MONSTER := 5
## `Ball_stdSet` 的实参个数：`[物种, 等级, 成长, 加成, 觉醒值, 觉醒, 被动, 被动等级, 装备, 昵称]`。
const ARGUMENTS := 10
## 原生被动表是 `extended_state + 468` 起的 66 字节（`Param_passiveSet`）。
const PASSIVE_SLOTS := 66


## `Item_datBasic` 的组号换算：`99 − (code % 1000)`（C 的截断取模，与本实现一致）。
static func group_of(code: int) -> int:
	return GROUP_BASE - (code % ItemKind.ID_SCALE)


## `Game_Guild_Battle_init` 的敌方三只。返回
## `{ok: true, code, group, level, constructors: [[10 个整数] × 3]}` 或 `{ok: false, error}`。
static func enemy_constructors(catalog: GameplayData, code: int) -> Dictionary:
	if catalog == null:
		return _failure("缺少玩法数据，公会战读不出对手阵容。")
	var group := group_of(code)
	if group < GROUP_MIN or group > GROUP_MAX:
		return _failure("公会码 %d 换算出的组号 %d 不在 item_guild.dat 的 %d–%d 里。" %
			[code, group, GROUP_MIN, GROUP_MAX])
	var record: ItemDefinition = catalog.item(ItemKind.id_of(GROUP_TYPE, group))
	if record == null or record.type != GROUP_TYPE:
		return _failure("缺少公会战对手数据：道具类型 %d 的组 %d（组号 = 99 − code%%1000，code = %d）。" %
			[GROUP_TYPE, group, code])
	var slots: Array[int] = record.detail_slots
	if slots.size() != MONSTERS * SLOTS_PER_MONSTER:
		return _failure("组 %d 的原始记录不是 %d 条 × %d 槽（实际 %d 个整数）。" %
			[group, MONSTERS, SLOTS_PER_MONSTER, slots.size()])
	var level := record.name_record.to_int()
	if level < MonsterAttribute.LEVEL_MIN or level > MonsterAttribute.LEVEL_MAX:
		return _failure("组 %d 的共用等级参数「%s」不在 %d–%d。" %
			[group, record.name_record, MonsterAttribute.LEVEL_MIN, MonsterAttribute.LEVEL_MAX])
	var constructors: Array = []
	for index in range(MONSTERS):
		var base := index * SLOTS_PER_MONSTER
		var species_id: int = slots[base + Slot.SPECIES]
		var species: MonsterDefinition = catalog.monster(species_id)
		# `MonsterDefinition.kind` 不进这里：原生建球链 `Ball_stdSet` → `Item_stdSet` →
		# `Item_datBasic` 只按「物种 % 1000」查 `item_mon`，没有物种种类闸门（`kind` 只参与
		# 被动 0／1、31／32、37／38 的选取，见 `battle.gd` 顶部）。与 `story.gd` 的 `_constructor_valid`
		# 同一条证据（`bm-P0-8`）。
		if species == null or species.ability_inputs.size() != 6 or \
				species.attribute_inputs.size() != 6:
			return _failure("组 %d 第 %d 只的物种 %d 没有可用的原始属性。" % [group, index + 1, species_id])
		var passive_id: int = slots[base + Slot.PASSIVE]
		var passive_level: int = slots[base + Slot.PASSIVE_LEVEL]
		if passive_level > 0:
			var passive: PassiveDefinition = catalog.passive(passive_id)
			if passive == null or passive.effect < 0 or passive.effect >= PASSIVE_SLOTS:
				return _failure("组 %d 第 %d 只的被动 %d 没有可用的原始记录。" %
					[group, index + 1, passive_id])
		var equipment: int = slots[base + Slot.EQUIPMENT_PLUS_ONE] - 1
		if equipment >= 0:
			var item: ItemDefinition = catalog.item(
				ItemKind.id_of(ItemKind.Kind.EQUIPMENT, equipment))
			if item == null or item.detail_slots.size() < 14:
				return _failure("组 %d 第 %d 只的装备 %d 没有可用的原装备属性。" %
					[group, index + 1, equipment])
		# 成长 -1、加成 0、觉醒值 0：`item_guild.dat` 只存这 5 个槽，其余实参与我方
		# `nativeArguments` 走同一档缺省（`menu_model.native_member_details` 亦然）。
		constructors.append([species_id, level, -1, 0, 0,
			slots[base + Slot.AWAKENED], passive_id, passive_level, equipment, -1])
	return {"ok": true, "code": code, "group": group, "level": level, "constructors": constructors}


## 用挑战页给出的构造实参开一场公会战：对手在前、我方出战队在后（`BattleCanvas_load`
## 先建 `party_monsters` 再建 `online_battle_monsters`，`Battle.new` 的球序同样是敌 3 后我 3）。
## 我方按 `Game_Ready_Battle_mRun` 进战前的 `Param_ballFULL(1)` 补满 HP/SP。
## 返回 `{ok: true, battle, order}` 或 `{ok: false, error}`。
static func create_battle(catalog: GameplayData, progress: Dictionary, constructors: Array,
		roll := Callable()) -> Dictionary:
	if constructors.size() != MONSTERS:
		return _failure("公会战对手必须是 %d 只，实际 %d 只。" % [MONSTERS, constructors.size()])
	var enemies: Array = []
	for args: Variant in constructors:
		if not args is Array or args.size() != ARGUMENTS:
			return _failure("公会战对手的构造实参不是 %d 个整数。" % ARGUMENTS)
		enemies.append(Battle.make_ball(catalog, args,
			Battle.roll_nickname(roll) if roll.is_valid() else 0))
	var order: Array = MenuModel.native_party_order(progress)
	if order.size() != MONSTERS:
		return _failure("公会战需要 %d 名出战队员，当前是 %d 名。" % [MONSTERS, order.size()])
	var party: Array = []
	for index: int in order:
		var details := MenuModel.native_member_details(progress, catalog, index)
		if details.ball == null:
			return _failure("出战成员 %d 的原始参数不可用：%s" % [index, details.unavailable])
		var ball: Dictionary = details.ball
		ball.hp = int(ball.max_hp)
		ball.sp = int(ball.max_sp)
		ball.feel = int(details.member.get("feel", 0))
		ball.food = int(details.member.get("food", ItemEffect.FOOD_MAX))
		party.append(ball)
	var battle: RefCounted = Battle.new(enemies, party, roll)
	battle.catalog = catalog
	battle.hero_level = int(progress.get("parameter", {}).get("level", 0))
	return {"ok": true, "battle": battle, "order": order}


## 胜利回写：原生 `Battle_Win_mRun` 只对 `kind == 3` 结算名次——`guild_code > 1` 时自减。
## `kind 4`（事件公会战）什么都不写。档位（`Ball_guildGrade`）在本移植里恒为 10
## （`menu_model.guild_grade`），所以不会出现 `msg 15／16` 的档位升级文案。
static func apply_win(progress: Dictionary, kind: int) -> Dictionary:
	var before := Story.guild_code(progress)
	if before < Story.GUILD_CODE_MIN or before > Story.GUILD_CODE_MAX:
		return _failure("存档里的公会码记录无效（%s）。" % str(progress.get(Story.GUILD_CODE_KEY)))
	if kind != KIND_CHALLENGE:
		return {"ok": true, "changed": false, "code": before}
	if before <= Story.GUILD_CODE_MIN:
		return {"ok": true, "changed": false, "code": before}
	progress[Story.GUILD_CODE_KEY] = before - 1
	return {"ok": true, "changed": true, "code": before - 1}


static func _failure(detail: String) -> Dictionary:
	return {"ok": false, "error": detail}
