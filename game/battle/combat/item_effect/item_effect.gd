extends RefCounted
class_name ItemEffect
## 原生 `Ball_stdUse` 的道具效果分派：战斗（`BattleModel.use_item`）与菜单
## （`MenuModel.use_item`）共用这一处规则，两边只负责把各自的记录适配成 `subject` 字典。
##
## `subject` 的键与战斗球记录一致：`hp`／`max_hp`／`sp`／`max_sp`／`statuses`（状态码 →
## 层数）／`feel`／`food`／`feel_state`／`passives`／`attribute`，觉醒时还要 `native_arguments`
## 与 `nickname`。返回的 `code` 是原生返回码（`n << 16` 后取低半字），`Ball_stdUseEx`
## 用它选 `common/msg.fxt` 的提示，映射见 `message_id()`。

## `Ball_stdUse` 的返回码。11–14 是第 1 组 19–24 的属性技能上升卡；19–34 里
## 除这些与技能书（31–34）外的游标仍未接，`supports()` 不放行。
enum Code {
	FAILED = 0,        ## 没有分支命中（`LABEL_14`）：既不改数值也不扣道具
	HP = 1,            ## 只回了 HP（`Ball_stdUseEx` 拼「HP …恢复」）
	HP_FULL = 2,       ## `unk_9C128[32]`：HP 已满
	SP = 3,            ## 只回了 SP
	SP_FULL = 4,       ## `unk_9C128[48]`：SP 已满
	BOTH = 5,          ## HP 与 SP 一起回
	BOTH_FULL = 6,     ## `unk_9C128[64]`：两者都已满
	CURED = 7,         ## 至少清掉一个异常状态
	CURE_NONE = 8,     ## 没有可治疗的状态（不扣道具）
	REVIVED = 9,       ## 复活并回 HP
	NOT_DOWN = 10,     ## 对象还有 HP，复活道具不适用
	PASSIVE_UPGRADE_WRONG_KIND = 11, ## 卡属性与怪物 kind 不同（`Ball_stdUse:768`）
	PASSIVE_UPGRADE_MAX = 12, ## 有被动但都到 9 级（`:841-859`）
	PASSIVE_UPGRADE_NONE = 13, ## 0–5 槽全空（`:858`）
	PASSIVE_UPGRADE_DONE = 14, ## 至少一个槽升一级并扣卡（`:780-849`）
	FEEL_GOOD = 15,    ## 食物对口（或 7020）：加心情 ＋ 回饱食度
	FEEL_BAD = 16,     ## 食物不对口：只加少量心情 ＋ 回饱食度
	FOOD_RESTORED = 17, ## 只回饱食度
	FOOD_STUFFED = 18, ## `food_value > 99`：吃不下了（不扣道具）
	TARGET_DOWN = 35,  ## `*(_WORD *)(ball + 26) == 0`：对象已倒下，只有复活道具能过
	EXP_BONUS = 28,    ## `Ball_stdUse:1068-1069`（`1835008 >> 16`）：开经验加成窗口并扣道具，无提示
	EXP_BONUS_ACTIVE = 36, ## `Ball_stdUse:1064`（`2359296 >> 16`）：窗口已在生效，不重置也不扣
	BRAIN_UP = 19,     ## 第 7 组 3：`brain_current` 写到 99 并扣道具（`1245184 >> 16`）
	BRAIN_MAX = 20,    ## 第 7 组 3：`+44 > 98`，才能已满，不扣（`1310720 >> 16`）
	ABILITY_RECOVERED = 25, ## 第 7 组 15：`Param_abilRecovery` 退回已分配的成长点并扣道具
	ABILITY_NONE = 26, ## 第 7 组 15：退回后 `ability_points` 仍是 0，不扣
	PASSIVES_CLEARED = 29, ## 第 7 组 21：`1900544 >> 16`，六槽清空并扣道具（提示 502）
	PASSIVES_NONE = 30,    ## 第 7 组 21：`n30 << 16`，本来就没有被动，不扣（提示 503）
	MIX_DONE = 31,       ## 第 4 组（技能书）：写进首个空被动槽并扣材料（`Ball_stdUse:169-185`）
	MIX_DUPLICATE = 32,  ## `LABEL_96`：该球已有同号被动
	MIX_NO_MATERIAL = 33, ## `Ball_stdUse:143`／`:155`：材料不够
	MIX_NO_SLOT = 34,    ## `Ball_stdUse:210`：0–5 槽全占
	RANDOM_BALL_ADDED = 21, ## 第 7 组 9–12：`Ball_stdAddEx` 成功（`1376256 >> 16`），原生无提示
	RANDOM_BALL_FULL = 22, ## 第 7 组 9–12：`Ball_stdAddEx` 返回空（怪包满，`1441792 >> 16`），不扣
	RANDOM_BOOK_ADDED = 23, ## 第 7 组 13–14：`Item_stdAddEx` 成功（`1507328 >> 16`），原生无提示
	RANDOM_BOOK_FULL = 24, ## 第 7 组 13–14：`Item_stdAddEx` 返回 0（书袋满，`1572864 >> 16`），不扣
	MASTERY_SELECT = 27, ## 第 7 组 16：扣一件后开 `CHARACTER_SELECT_17`（`1769472 >> 16`），无提示
}

## `MonsterState.feel_state_code`：`Ball_stdSet` 写 `3 × 觉醒档`，`Ball_stdFeel`
## 在心情到顶且当前为 0 时写 3（其余函数只读它判断「已觉醒」）。
enum FeelState {
	NORMAL = 0,
	AWAKENED = 3,
}

## 道具记录里 HP／SP 效果值的位置（`Ball_stdUse` 的 `v104.detail_values[6..9]`）：
## `Ball_stdHP`／`Ball_stdSP` 按 `当前值 + 固定值 + 上限 × 百分比 / 100` 截到上限。
const ITEM_HP_FLAT := 6
const ITEM_SP_FLAT := 7
const ITEM_HP_PERCENT := 8
const ITEM_SP_PERCENT := 9
## 效果值槽数下限：HP／SP／复活的四个值都在 6–9，槽不够就无法判效果。
const DETAIL_SLOT_COUNT := 10
## `Ball_stdPassive` 的槽数：球状态 `+8+2n`（等级）／`+9+2n`（被动号），0–5 共 6 槽。
const PASSIVE_SLOT_COUNT := 6

## 复活道具：`Ball_stdUse` 在「对倒下对象不可用」的检查**之前**跳到 `LABEL_25`，
## 所以只有它们能对 HP 0 的对象使用；HP 非 0 时返回 10。
const ITEM_FIRST_REVIVE := 17
const ITEM_LAST_REVIVE := 18

## 异常状态治疗道具（索引 8–15 各清一组槽，索引 16 清全部）。原生 `Ball_stdUse` 的常量块
## 是 `1907739/6/8/1/723465/84148994/7/1710360` 这 8 个 dword，逐字节为
## `[27,29,29,0] [6,0,0,0] [8,0,0,0] [1,0,0,0] [73,10,11,0] [2,4,4,5] [7,0,0,0] [24,26,26,0]`——
## 重复的 29／4／26 与缺失的 28／3／25 是原生数据本身的笔误，73 超出 34 槽范围，这里只留有效槽号。
const ITEM_FIRST_CURE := 8
const CURE_SLOTS := [[27, 29], [6], [8], [1], [10, 11], [2, 4, 5], [7], [24, 26]]
const CURE_ALL := 16

## 食物／心情道具（`Ball_stdUse` 的 `n16_1 <= 36`／`== 37` 与第 7 组第 20 号三支）：
## 31–36 按物种属性判口味，37 只回饱食度。
const ITEM_FIRST_FOOD := 31
const ITEM_LAST_FOOD := 37
## 经验 +20% 窗口道具：`Ball_stdUse:1060-1070` 的 `SHIWORD(n4) == 18` 一支。它在第 7 组
## （同一张分派表里第 20 号就是超级大理石），不是第 1 组——第 1 组的 17／18 号在
## `Ball_stdUse:120-121` 就直接跳去复活分支了。HUD 图标也用这件道具
## （`Field_Basic_hero_DrawUI:66` 的 `Menu_Item_DrawItem(60, 9, {1, 0x120007})`：
## 低字 7 是组、高字 18 是索引）。
const EXP_BONUS_INDEX := 18
## 第 7 组 3：`Ball_stdUse:916-926` 把 `*(char *)(ball + 44)`（`brain_current`）写 99；
## 已经 > 98 时返回 20 且不扣。
const BRAIN_BOOST_INDEX := 3
const BRAIN_BOOSTED := 99
## 第 7 组 15：`Ball_stdUse:1039-1049` 先 `Param_abilRecovery`（`ParamData.ability_values[0..2]`
## 退回 `ability_points` 并清零），点数仍为 0 时返回 26，否则 25 并扣道具。
const ABILITY_RECOVERY_INDEX := 15
## 第 7 组 16「专家的印章」：扣一件后开原生 `CHARACTER_SELECT_17` 流派选择页；返回码 27。
const MASTERY_CHANGE_INDEX := 16
## 第 7 组 17：原生没有效果分支，`Ball_stdUse` 返回 0 且不扣；`Ball_stdUseEx` 取默认文案 510。
const UNUSABLE_INDEX := 17
## 第 7 组 21「去除被动」：`Ball_stdUse:1092-1117` 逐槽看等级，> 0 才
## `Ball_stdPassive(球, 槽, 0, 0)` 清零，六个槽走完再 `Ball_stdBasic` 重算；
## 清过至少一条返回 29，六槽本来就空返回 30 且不扣道具。
const CLEAR_PASSIVES_INDEX := 21
## 第 7 组 9–12「随机球」：`Ball_stdUse:930-986` 在 `Item_datBasic` 的物种表里按
## `kind_specific_84_bits`（记录第 132 字节＝品级，本工程 `MonsterDefinition.attribute_entry`）
## 等于 `index − 9` 过滤，再用 `Ball_stdSet` 建球（等级＝主角等级、`brain_current`＝
## `rand % 标准等级 + 1`、0 号被动槽随机一个被动 1 级）。
const ITEM_FIRST_RANDOM_BALL := 9
const ITEM_LAST_RANDOM_BALL := 12
## 第 7 组 13–14「技能书」：`:988-1037` 在书表里按 `kind_specific_84_bits`（＝`grade_index`）
## 等于 `index − 13` 过滤，再 `Item_stdAddEx` 随机一本。两件都不看目标 HP。
const ITEM_FIRST_RANDOM_BOOK := 13
const ITEM_LAST_RANDOM_BOOK := 14
## 31–36 号食物各对口一个物种属性（原生把 6 个值拆进 `LevelProgressPartialType` 与相邻栈变量，
## 按 `*(&v91 + index − 31)` 取 dword，合起来就是 `[1, 0, 4, 2, 3, 5]`）。
const FOOD_ATTRIBUTES := [1, 0, 4, 2, 3, 5]
## 第 1 组 19–24「属性技能上升卡」：索引 → 怪物 kind（0 水、1 火、2 木、3 风、4 光、5 暗）。
## 原生 `Ball_stdUse:759-768` 把 `v91` 的六个 dword 与 `kind_specific_86_bits` 比较，值即
## `[1, 0, 2, 5, 4, 3]`；对不上返回 11。
const ITEM_FIRST_PASSIVE_UPGRADE := 19
const ITEM_LAST_PASSIVE_UPGRADE := 24
const PASSIVE_UPGRADE_KINDS := [1, 0, 2, 5, 4, 3]
## `Ball_stdPassivePlus` 的上限：`n9_1 <= 9` 才写，否则保留 9。
const PASSIVE_LEVEL_MAX := 9
## `Ball_stdFood` 把 `food_value` 夹在 0–100，`Ball_stdFeel` 把 `feel_value` 夹到 999。
const FOOD_MAX := 100
const FEEL_MAX := 999
## `Ball_stdUse` 用 `food_value > 30` 判「已经很饱」：饱了口味加成减半（30 → 10）。
const FOOD_SATIATED := 30
## 被动 21（`extended_state + 489`）只在吃食物时加心情：`Ball_stdUse` 先把整张被动表
## 重算进本地 66 字节副本（`0x86ec2`／`0x8716c` 的 `Param_passiveSet`），再
## `if ((char)v106[21] > 0) n10 += (char)v106[21];`（`0x86ed6`／`0x87178`），之后才 `Ball_stdFeel`。
const FEEL_PASSIVE := 21
## 觉醒时清空的标准被动槽：`Ball_stdFeel` 依次 `Ball_stdPassive(a1, 2..5, 0, 0)`。
const AWAKENING_CLEARED_PASSIVES := [2, 3, 4, 5]

## `Ball_stdUse` 的四个标志位（`n16`）：1／2 = HP／SP 已回复，0x10／0x20 = HP／SP 已满。
const FLAG_HP := 1
const FLAG_SP := 2
const FLAG_HP_FULL := 0x10
const FLAG_SP_FULL := 0x20


static func super_marble_id() -> int:
	return ItemKind.id_of(ItemKind.Kind.GROUP_7, ItemKind.SUPER_MARBLE_INDEX)


## 道具记录里的效果值槽；不合法时返回空数组。食物分支不读槽，所以允许为空。
static func slots_of(item: Dictionary) -> Array:
	var slots: Variant = item.get("detail_slots")
	if not slots is Array or not slots.all(func(value: Variant) -> bool: return value is int):
		return []
	return slots


## `Ball_stdUse` 覆盖到的种类：第 1 组索引 0–18、19–24 与 31–37，以及第 7 组的 3、9–18、20、21。
## 第 1 组 25–30 是强化剂（走 `MonsterGrowth` 的强化页，不在道具使用里）；第 7 组 16 扣一件后由
## 菜单宿主开原生 `CHARACTER_SELECT_17` 页（返回码 27）；17 原生落 `LABEL_11` 返回 0 且不扣
## （`Ball_stdUseEx` 默认 510「无法使用」）。19 没有「使用」动作，`item_actions` 不会放行。
static func supports(item: Dictionary) -> bool:
	var item_id: Variant = item.get("id")
	if not item_id is int:
		return false
	var kind := ItemKind.kind_of(item_id)
	var index := ItemKind.index_of(item_id)
	if kind == ItemKind.Kind.SKILL_BOOK:
		# `Ball_stdUse:128` 只有 kind 4 一支：组内索引就是被动号，材料在记录里。
		return index > 0
	if kind == ItemKind.Kind.GROUP_7:
		return index in [BRAIN_BOOST_INDEX, ABILITY_RECOVERY_INDEX, CLEAR_PASSIVES_INDEX,
			EXP_BONUS_INDEX, ItemKind.SUPER_MARBLE_INDEX, MASTERY_CHANGE_INDEX,
			UNUSABLE_INDEX] or (index >= ITEM_FIRST_RANDOM_BALL and index <= ITEM_LAST_RANDOM_BOOK)
	if kind != ItemKind.Kind.CONSUMABLE:
		return false
	if index >= ITEM_FIRST_PASSIVE_UPGRADE and index <= ITEM_LAST_PASSIVE_UPGRADE:
		return true
	if index <= ITEM_LAST_REVIVE:
		# 治疗类（8–16）查的是固定的槽表，不读道具记录里的效果值。
		if index >= ITEM_FIRST_CURE:
			return true
		var slots := slots_of(item)
		if slots.size() < DETAIL_SLOT_COUNT or slots.slice(ITEM_HP_FLAT, DETAIL_SLOT_COUNT).any(
				func(value: int) -> bool: return value < 0):
			return false
		if index >= ITEM_FIRST_REVIVE:
			return true
		return slots[ITEM_HP_FLAT] > 0 or slots[ITEM_SP_FLAT] > 0 or \
			slots[ITEM_HP_PERCENT] > 0 or slots[ITEM_SP_PERCENT] > 0
	return index >= ITEM_FIRST_FOOD and index <= ITEM_LAST_FOOD


## `Ball_stdHP`／`Ball_stdSP` 的回复公式：`当前值 + 固定值 + 上限 × 百分比 / 100`，截到 `[0, 上限]`。
static func restored(maximum: int, current: int, flat: int, percent: int) -> int:
	return clampi(current + flat + maximum * percent / 100, 0, maximum)


## 返回码 → `common/msg.fxt` 记录号（`Ball_stdUseEx` 的 switch）。HP／SP 两码的提示前缀
## 由调用方按效果值拼，正文仍是 `Msg.Id.ITEM_RECOVER`。没有提示时返回 0。
static func message_id(code: int) -> int:
	match code:
		Code.HP, Code.SP:
			return Msg.Id.ITEM_RECOVER
		Code.BOTH:
			return Msg.Id.ITEM_RECOVER_HP_SP
		Code.HP_FULL:
			return Msg.Id.ITEM_HP_FULL
		Code.SP_FULL:
			return Msg.Id.ITEM_SP_FULL
		Code.BOTH_FULL:
			return Msg.Id.ITEM_BOTH_FULL
		Code.CURED:
			return Msg.Id.ITEM_STATUS_CURED
		Code.CURE_NONE:
			return Msg.Id.ITEM_NO_STATUS
		Code.REVIVED:
			return Msg.Id.ITEM_REVIVED
		Code.NOT_DOWN:
			return Msg.Id.ITEM_ONLY_DOWN
		Code.PASSIVE_UPGRADE_WRONG_KIND:
			return Msg.Id.ITEM_PASSIVE_UPGRADE_WRONG_KIND
		Code.PASSIVE_UPGRADE_MAX:
			return Msg.Id.ITEM_PASSIVE_UPGRADE_MAX
		Code.PASSIVE_UPGRADE_NONE:
			return Msg.Id.ITEM_PASSIVE_UPGRADE_NONE
		Code.PASSIVE_UPGRADE_DONE:
			return Msg.Id.ITEM_PASSIVE_UPGRADE_DONE
		Code.FEEL_GOOD, Code.FEEL_BAD:
			return Msg.Id.ITEM_FEEL_FOOD
		Code.FOOD_RESTORED:
			return Msg.Id.ITEM_FOOD_RESTORED
		Code.FOOD_STUFFED:
			return Msg.Id.ITEM_FOOD_STUFFED
		Code.TARGET_DOWN:
			return Msg.Id.ITEM_TARGET_DOWN
		# `Ball_stdUseEx:205-208` 的 `case 36` 弹 509「已在使用中.」；28（成功开窗）原生无提示。
		Code.EXP_BONUS_ACTIVE:
			return Msg.Id.ITEM_BONUS_ACTIVE
		Code.BRAIN_UP:
			return Msg.Id.ITEM_BRAIN_UP
		Code.BRAIN_MAX:
			return Msg.Id.ITEM_BRAIN_MAX
		Code.ABILITY_RECOVERED:
			return Msg.Id.ITEM_ABILITY_RECOVERED
		Code.ABILITY_NONE:
			return Msg.Id.ITEM_ABILITY_NONE
		Code.PASSIVES_CLEARED:
			return Msg.Id.ITEM_PASSIVES_CLEARED
		Code.PASSIVES_NONE:
			return Msg.Id.ITEM_PASSIVES_NONE
		Code.FAILED:
			return Msg.Id.ITEM_UNUSABLE
		Code.MIX_DONE:
			return Msg.Id.ITEM_MIX_DONE
		Code.MIX_DUPLICATE:
			return Msg.Id.ITEM_MIX_DUPLICATE
		Code.MIX_NO_MATERIAL:
			return Msg.Id.ITEM_MIX_NO_MATERIAL
		Code.MIX_NO_SLOT:
			return Msg.Id.ITEM_MIX_NO_SLOT
		# `Ball_stdUseEx:153-165`：21／23（成功）与 27／28 一样只返回码；22／24 才弹提示。
		Code.RANDOM_BALL_FULL:
			return Msg.Id.ITEM_MONSTER_STORAGE_FULL
		Code.RANDOM_BOOK_FULL:
			return Msg.Id.ITEM_SKILL_BOOK_STORAGE_FULL
	return 0


## `Ball_stdUseEx` 的提示拼装：HP／SP 两码先在 `msg.fxt` 480 之前拼「HP 20」这样的前缀，
## BOTH 用 481 的 `%d%%`（取 HP／SP 百分比较大者），其余直接用 `message_id()` 的正文。
## `text_of` 是「记录号 → 正文」的解析器，战斗与菜单各自接自己的文本源。无提示时返回空串。
static func describe(code: int, slots: Array, text_of: Callable) -> String:
	if code == Code.HP:
		return "HP %s%s" % [_amount(slots, ITEM_HP_FLAT, ITEM_HP_PERCENT),
			String(text_of.call(Msg.Id.ITEM_RECOVER))]
	if code == Code.SP:
		return "SP %s%s" % [_amount(slots, ITEM_SP_FLAT, ITEM_SP_PERCENT),
			String(text_of.call(Msg.Id.ITEM_RECOVER))]
	if code == Code.BOTH:
		return String(text_of.call(Msg.Id.ITEM_RECOVER_HP_SP)) % maxi(
			int(slots[ITEM_HP_PERCENT]), int(slots[ITEM_SP_PERCENT]))
	var message_id := message_id(code)
	return "" if message_id == 0 else String(text_of.call(message_id))


## 原生按 `detail_values` 拼「固定值」「百分比」两段，两个都非 0 时直接相接（不插分隔符）。
static func _amount(slots: Array, flat: int, percent: int) -> String:
	var parts := ""
	if int(slots[flat]) > 0:
		parts += str(int(slots[flat]))
	if int(slots[percent]) > 0:
		parts += "%d%%" % int(slots[percent])
	return parts


## `Ball_stdUse` 的主分派。`subject` 就地改写，返回 `code`／`consumed`（原生 `v6 == 1`
## 的那几支会 `Game_saveSAVE` 并进 `LABEL_21` 扣道具）与本次的 `hp_restored`／`sp_restored`。
## `on_awaken` 在心情到顶且未觉醒时调用（原生 `Ball_stdFeel` 的 `LABEL_5`），
## 返回空串表示成功；战斗与菜单各自传入按物种重算的入口。
static func apply(subject: Dictionary, item: Dictionary,
		on_awaken: Callable = Callable(), context: Dictionary = {}) -> Dictionary:
	if not supports(item):
		return {"ok": false, "error": "道具 %d 的原效果尚未接通" % int(item.get("id", -1))}
	var index := ItemKind.index_of(int(item["id"]))
	var slots := slots_of(item)
	if ItemKind.kind_of(int(item["id"])) == ItemKind.Kind.SKILL_BOOK:
		return _mix(subject, index)
	var hp := int(subject.get("hp", 0))
	if ItemKind.kind_of(int(item["id"])) == ItemKind.Kind.GROUP_7:
		# `Ball_stdUse:123-127` 的「倒下对象」守卫在整张分派表之前，第 7 组全部适用。
		if hp <= 0:
			return {"ok": true, "code": Code.TARGET_DOWN, "consumed": false}
		if index == CLEAR_PASSIVES_INDEX:
			return _clear_passives(subject)
		if index == BRAIN_BOOST_INDEX or index == ABILITY_RECOVERY_INDEX:
			if hp <= 0:
				return {"ok": true, "code": Code.TARGET_DOWN, "consumed": false}
			return _brain_boost(subject) if index == BRAIN_BOOST_INDEX else \
				_ability_recovery(item)
		if index == EXP_BONUS_INDEX:
			return _exp_bonus(item, hp)
		if index >= ITEM_FIRST_RANDOM_BALL and index <= ITEM_LAST_RANDOM_BOOK:
			return _random_grant(index, context)
		# 第 7 组 16：原生先扣一件再 `SetNext(CHARACTER_SELECT_17)`；页面由菜单宿主打开。
		if index == MASTERY_CHANGE_INDEX:
			return {"ok": true, "code": Code.MASTERY_SELECT, "consumed": true}
		# 第 7 组 17：原生走 `LABEL_11`，返回 0 且不扣道具（`Ball_stdUseEx` 默认提示 510）。
		if index == UNUSABLE_INDEX:
			return {"ok": true, "code": Code.FAILED, "consumed": false}
		# `SHIWORD(n4) == 20`：超级大理石。原生在「对象已倒下」的检查之后，加心情前叠加被动 21。
		if hp <= 0:
			return {"ok": true, "code": Code.TARGET_DOWN, "consumed": false}
		var sated := int(subject.get("food", FOOD_MAX)) > FOOD_SATIATED
		return _feed(subject, 70 if sated else 140, Code.FEEL_GOOD, on_awaken)
	if index >= ITEM_FIRST_REVIVE and index <= ITEM_LAST_REVIVE:
		# `LABEL_25`：先把 34 个状态槽全部 `Param_activeInit` 清空，再按道具值回 HP。
		if hp > 0:
			return {"ok": true, "code": Code.NOT_DOWN, "consumed": false}
		subject["statuses"] = {}
		subject["hp"] = restored(int(subject["max_hp"]), 0, int(slots[ITEM_HP_FLAT]),
			int(slots[ITEM_HP_PERCENT]))
		return {"ok": true, "code": Code.REVIVED, "consumed": true,
			"hp_restored": int(subject["hp"]) - hp}
	if hp <= 0:
		return {"ok": true, "code": Code.TARGET_DOWN, "consumed": false}
	if index >= ITEM_FIRST_PASSIVE_UPGRADE and index <= ITEM_LAST_PASSIVE_UPGRADE:
		return _upgrade_passives(subject, index)
	if index >= ITEM_FIRST_FOOD:
		return _food(subject, index, on_awaken)
	if index >= ITEM_FIRST_CURE:
		return _cure(subject, index)
	return _heal(subject, slots)


## 第 4 组（技能书）：`Ball_stdUse:189-310` 的槽扫描。等级 > 0 且被动号相同判 32，
## 首个「等级 0 且号 0」的槽判 31 并写入，六槽全占判 34；材料够不够由菜单侧按
## `Menu_Item_Mix_IsPossible` 先核（33），`Ball_stdPassive(球, 槽, 被动号, 1)` 只写槽。
static func _mix(subject: Dictionary, passive_id: int) -> Dictionary:
	var slots: Variant = subject.get("passive_slots")
	if not slots is Array or slots.size() != PASSIVE_SLOT_COUNT:
		return {"ok": false, "error": "成员记录没有 0–5 号被动槽"}
	for slot: int in range(PASSIVE_SLOT_COUNT):
		var entry: Variant = slots[slot]
		if not entry is Array or entry.size() != 2:
			return {"ok": false, "error": "被动槽 %d 数据损坏" % slot}
		if int(entry[1]) > 0:
			if int(entry[0]) == passive_id:
				return {"ok": true, "code": Code.MIX_DUPLICATE, "consumed": false}
			continue
		slots[slot] = [passive_id, 1]
		return {"ok": true, "code": Code.MIX_DONE, "slot": slot, "consumed": true}
	return {"ok": true, "code": Code.MIX_NO_SLOT, "consumed": false}


## 第 1 组 19–24（`Ball_stdUse:759-860`）：先按卡属性核怪物 kind，再把 0–5 号槽里
## 等级 1–8 的被动各升一级；全空返回 13，有槽但都已到 9 级返回 12。
static func _upgrade_passives(subject: Dictionary, index: int) -> Dictionary:
	var expected_kind: int = PASSIVE_UPGRADE_KINDS[index - ITEM_FIRST_PASSIVE_UPGRADE]
	if int(subject.get("kind", -1)) != expected_kind:
		return {"ok": true, "code": Code.PASSIVE_UPGRADE_WRONG_KIND, "consumed": false}
	var slots: Variant = subject.get("passive_slots")
	if not slots is Array or slots.size() != PASSIVE_SLOT_COUNT:
		return {"ok": false, "error": "成员记录没有 0–5 号被动槽"}
	var occupied := 0
	var upgraded := 0
	for slot: int in range(PASSIVE_SLOT_COUNT):
		var entry: Variant = slots[slot]
		if not entry is Array or entry.size() != 2:
			return {"ok": false, "error": "被动槽 %d 数据损坏" % slot}
		var level := int(entry[1])
		if level <= 0:
			continue
		occupied += 1
		if level >= PASSIVE_LEVEL_MAX:
			continue
		slots[slot] = [int(entry[0]), level + 1]
		upgraded += 1
	if upgraded > 0:
		return {"ok": true, "code": Code.PASSIVE_UPGRADE_DONE, "consumed": true,
			"upgraded": upgraded}
	if occupied > 0:
		return {"ok": true, "code": Code.PASSIVE_UPGRADE_MAX, "consumed": false}
	return {"ok": true, "code": Code.PASSIVE_UPGRADE_NONE, "consumed": false}


## 第 7 组 21（`Ball_stdUse:1092-1117`）：等级 > 0 的槽写回 `[0, 0]`，本来空的槽不动；
## 清过至少一条返回 29 并扣道具，六槽本来就空返回 30 且不扣。重算基础值由
## `Battle.passive_effect_table` 在取用成员时按槽表重做，记录里不存派生表。
static func _clear_passives(subject: Dictionary) -> Dictionary:
	var slots: Variant = subject.get("passive_slots")
	if not slots is Array or slots.size() != PASSIVE_SLOT_COUNT:
		return {"ok": false, "error": "成员记录没有 0–5 号被动槽"}
	var cleared := 0
	for slot: int in range(PASSIVE_SLOT_COUNT):
		var entry: Variant = slots[slot]
		if not entry is Array or entry.size() != 2:
			return {"ok": false, "error": "被动槽 %d 数据损坏" % slot}
		if int(entry[1]) <= 0:
			continue
		slots[slot] = [0, 0]
		cleared += 1
	if cleared == 0:
		return {"ok": true, "code": Code.PASSIVES_NONE, "consumed": false}
	return {"ok": true, "code": Code.PASSIVES_CLEARED, "consumed": true, "cleared": cleared}


## 第 7 组 9–14：`Ball_stdUse:930-1037` 的选择与返回码。生成物本身由调用方写入
## （菜单侧走 `MenuModel.use_item` 的怪物／背包路径）；`context` 带 `catalog`、主角等级、
## 标准等级与可选 `rng`，与原生 `Item_datBasic`／`Param_stdSET` 的输入一一对应。
static func _random_grant(index: int, context: Dictionary) -> Dictionary:
	var catalog: Variant = context.get("catalog")
	if not catalog is GameplayData:
		return {"ok": false, "error": "缺少原生物种／技能书目录，无法按 Ball_stdUse 生成"}
	if index <= ITEM_LAST_RANDOM_BALL:
		return _random_ball(index, catalog, context)
	return _random_book(index, catalog, context)


## `Ball_stdUse:937-978`：物种按品级过滤后 `rand % 候选数` 取一只；随后 `rand % 被动数`
## 取 0 号槽的被动、`rand % 标准等级 + 1` 取 `brain_current`。等级直接用主角等级。
static func _random_ball(index: int, catalog: GameplayData, context: Dictionary) -> Dictionary:
	var grade := index - ITEM_FIRST_RANDOM_BALL
	var candidates: Array = catalog.monsters.filter(func(record: MonsterDefinition) -> bool:
		return record.attribute_entry == grade)
	if candidates.is_empty():
		return {"ok": false, "error": "原生物种表里没有品级 %d 的候选" % grade}
	var species := int(candidates[_roll(context) % candidates.size()].id)
	var passive_id := 0
	if not catalog.passives.is_empty():
		passive_id = int(catalog.passives[_roll(context) % catalog.passives.size()].id)
	var standard := maxi(1, int(context.get("standard_level", 1)))
	var brain := _roll(context) % standard + 1
	return {"ok": true, "code": Code.RANDOM_BALL_ADDED, "consumed": true,
		"generated_monster": {"species": species, "level": int(context.get("level", 1)),
			"brain_current": brain, "passive_id": passive_id}}


## `Ball_stdUse:990-1030`：技能书按 `grade_index == index − 13` 过滤后随机一本。
static func _random_book(index: int, catalog: GameplayData, context: Dictionary) -> Dictionary:
	var grade := index - ITEM_FIRST_RANDOM_BOOK
	var candidates: Array = catalog.items.filter(func(record: ItemDefinition) -> bool:
		return record.type == ItemKind.Kind.SKILL_BOOK and record.grade_index == grade)
	if candidates.is_empty():
		return {"ok": false, "error": "原生技能书表里没有品级 %d 的候选" % grade}
	return {"ok": true, "code": Code.RANDOM_BOOK_ADDED, "consumed": true,
		"generated_item": int(candidates[_roll(context) % candidates.size()].id)}


## 原生 `EFC_mainGetRAND()`；测试可传固定 `RandomNumberGenerator` 复现同一次抽取。
## 菜单侧另传 `random_seed`：宿主回放同一操作时用同一种子重抽，随机道具的结果才能逐字段对账。
static func _roll(context: Dictionary) -> int:
	var rng: Variant = context.get("rng")
	if rng is RandomNumberGenerator:
		return rng.randi()
	if context.has("random_seed"):
		var replay: Variant = context.get("_replay_rng")
		if not replay is RandomNumberGenerator:
			replay = RandomNumberGenerator.new()
			replay.seed = int(context["random_seed"])
			context["_replay_rng"] = replay
		return (replay as RandomNumberGenerator).randi()
	return randi()


## 第 7 组第 18 号：开「经验 +20%」窗口（`Ball_stdUse:1060-1070`）。窗口已在生效时返回 36
## 且**不重置**、不扣道具；否则把存档的 `standard_progress + 7` 写成 3600000 并返回 28。
## 参数表由 `MenuModel.native_inventory_rows` 按引用挂在道具行上（原生是直接写 `ParamData`）。
static func _exp_bonus(item: Dictionary, hp: int) -> Dictionary:
	# `Ball_stdUse:123-127`：目标已倒下时先返回 35，走不到开窗那一段。
	if hp <= 0:
		return {"ok": true, "code": Code.TARGET_DOWN, "consumed": false}
	var parameter: Variant = item.get("parameter")
	if not parameter is Dictionary:
		return {"ok": false, "error": "道具行没有存档参数表，无法记录经验加成窗口"}
	if StoryRuntime.exp_bonus_remaining(parameter) > 0:
		return {"ok": true, "code": Code.EXP_BONUS_ACTIVE, "consumed": false}
	parameter[StoryRuntime.EXP_BONUS_KEY] = StoryRuntime.EXP_BONUS_MILLISECONDS
	return {"ok": true, "code": Code.EXP_BONUS, "consumed": true}


## 第 7 组 3：只有 `brain_current > 98` 的守卫，没有 `brain_limit` 检查——原生直接写 99。
static func _brain_boost(subject: Dictionary) -> Dictionary:
	if int(subject.get("brain_current", 0)) > BRAIN_BOOSTED - 1:
		return {"ok": true, "code": Code.BRAIN_MAX, "consumed": false}
	subject["brain_current"] = BRAIN_BOOSTED
	return {"ok": true, "code": Code.BRAIN_UP, "consumed": true}


## 第 7 组 15：`Param_abilRecovery` 把三项已分配点数退回 `points` 并清零 `allocated`；
## 参数表按引用挂在道具行上（`MenuModel.native_inventory_rows`），这里就地改写。
static func _ability_recovery(item: Dictionary) -> Dictionary:
	var parameter: Variant = item.get("parameter")
	if not parameter is Dictionary or not parameter.get("development") is Dictionary:
		return {"ok": false, "error": "道具行没有存档成长分配表，无法退回能力点"}
	var development: Dictionary = parameter["development"]
	var allocated: Variant = development.get("allocated")
	if not development.get("points") is int or not allocated is Array or \
			allocated.size() != 3 or not allocated.all(
				func(value: Variant) -> bool: return value is int):
		return {"ok": false, "error": "存档成长分配表无效"}
	var recovered := 0
	for index in range(allocated.size()):
		recovered += int(allocated[index])
		allocated[index] = 0
	development["points"] = int(development["points"]) + recovered
	if int(development["points"]) == 0:
		return {"ok": true, "code": Code.ABILITY_NONE, "consumed": false}
	return {"ok": true, "code": Code.ABILITY_RECOVERED, "consumed": true}


## 索引 8–15 各清一组状态槽、16 清全部（`LABEL_40`）：清到至少一个返回 7 并扣道具，
## 一个都没清返回 8 且不扣。
static func _cure(subject: Dictionary, index: int) -> Dictionary:
	var statuses: Variant = subject.get("statuses")
	if not statuses is Dictionary:
		return {"ok": false, "error": "记录里没有异常状态表，无法按 Ball_stdUse 结算治疗"}
	var codes: Array = CURE_SLOTS[index - ITEM_FIRST_CURE] if index < CURE_ALL else \
		statuses.keys()
	var cleared := 0
	for code: Variant in codes:
		if statuses.erase(int(code)):
			cleared += 1
	if cleared == 0:
		return {"ok": true, "code": Code.CURE_NONE, "consumed": false}
	return {"ok": true, "code": Code.CURED, "consumed": true, "cleared": cleared}


## 索引 0–7：`v25 = n16 & 3` 的四种组合决定返回码，两个都满时查 `unk_9C128` 的 32／48／64 项。
static func _heal(subject: Dictionary, slots: Array) -> Dictionary:
	var flags := 0
	var restored_hp := 0
	var restored_sp := 0
	if int(slots[ITEM_HP_FLAT]) > 0 or int(slots[ITEM_HP_PERCENT]) > 0:
		if int(subject.get("hp", 0)) < int(subject["max_hp"]):
			var before := int(subject["hp"])
			subject["hp"] = restored(int(subject["max_hp"]), before, int(slots[ITEM_HP_FLAT]),
				int(slots[ITEM_HP_PERCENT]))
			restored_hp = int(subject["hp"]) - before
			flags |= FLAG_HP
		else:
			flags |= FLAG_HP_FULL
	if int(slots[ITEM_SP_FLAT]) > 0 or int(slots[ITEM_SP_PERCENT]) > 0:
		if int(subject.get("sp", 0)) < int(subject["max_sp"]):
			var before := int(subject["sp"])
			subject["sp"] = restored(int(subject["max_sp"]), before, int(slots[ITEM_SP_FLAT]),
				int(slots[ITEM_SP_PERCENT]))
			restored_sp = int(subject["sp"]) - before
			flags |= FLAG_SP
		else:
			flags |= FLAG_SP_FULL
	var healed := flags & (FLAG_HP | FLAG_SP)
	var code := Code.FAILED
	match healed:
		FLAG_HP | FLAG_SP:
			code = Code.BOTH
		FLAG_HP:
			code = Code.HP
		FLAG_SP:
			code = Code.SP
		_:
			match flags & (FLAG_HP_FULL | FLAG_SP_FULL):
				FLAG_HP_FULL:
					code = Code.HP_FULL
				FLAG_SP_FULL:
					code = Code.SP_FULL
				FLAG_HP_FULL | FLAG_SP_FULL:
					code = Code.BOTH_FULL
	if code == Code.FAILED:
		return {"ok": false, "error": "道具没有可用的 HP／SP 效果值"}
	return {"ok": true, "code": code, "consumed": healed != 0,
		"hp_restored": restored_hp, "sp_restored": restored_sp}


## 索引 31–36 按口味加心情，37 只回饱食度（`food > 99` 时返回 18 且不扣）。
static func _food(subject: Dictionary, index: int, on_awaken: Callable) -> Dictionary:
	var food := int(subject.get("food", FOOD_MAX))
	if index == ITEM_LAST_FOOD:
		if food > FOOD_MAX - 1:
			return {"ok": true, "code": Code.FOOD_STUFFED, "consumed": false}
		var gained := FOOD_MAX - food
		subject["food"] = FOOD_MAX
		return {"ok": true, "code": Code.FOOD_RESTORED, "consumed": true, "food_restored": gained}
	var matched := int(FOOD_ATTRIBUTES[index - ITEM_FIRST_FOOD]) == int(
		subject.get("attribute", -1))
	return _feed(subject, (10 if food > FOOD_SATIATED else 30) if matched else 5,
		Code.FEEL_GOOD if matched else Code.FEEL_BAD, on_awaken)


## `Ball_stdFeel` ＋ `Ball_stdFood(ball, 100)`。心情到顶那一步：未觉醒就交给
## `on_awaken` 按新物种重算（原生 `LABEL_5`），已觉醒只把 `feel_value` 夹到 999。
static func _feed(subject: Dictionary, feel_gain: int, code: int,
		on_awaken: Callable) -> Dictionary:
	var passives: Variant = subject.get("passives")
	# `Ball_stdUse` 是 `if ((char)v106[21] > 0) n10 += (char)v106[21];`：只有正值才加，
	# 负的被动 21 不参与心情累加（`0x86ed6`／`0x87178`）。
	if passives is Array and FEEL_PASSIVE < passives.size() and int(passives[FEEL_PASSIVE]) > 0:
		feel_gain += int(passives[FEEL_PASSIVE])
	var feel := int(subject.get("feel", 0))
	var evolved := false
	if feel + feel_gain >= FEEL_MAX and \
			int(subject.get("feel_state", FeelState.NORMAL)) == FeelState.NORMAL:
		if not on_awaken.is_valid():
			return {"ok": false, "error": "缺少觉醒重算入口，心情到顶时无法按新物种重算数值"}
		var failure: String = on_awaken.call(subject)
		if not failure.is_empty():
			return {"ok": false, "error": failure}
		evolved = true
	elif feel + feel_gain >= FEEL_MAX:
		subject["feel"] = FEEL_MAX
	else:
		# `Ball_stdFeel` 的 `n999 < 0` 支把 `feel_value` 写 0。
		subject["feel"] = maxi(0, feel + feel_gain)
	subject["food"] = mini(FOOD_MAX, int(subject.get("food", FOOD_MAX)) + 100)
	return {"ok": true, "code": code, "consumed": true, "evolved": evolved,
		"feel": int(subject["feel"]), "food": int(subject["food"])}
