extends RefCounted
## 角色数据的唯一入口：背包容量、怪物栏容量、持有数等。
##
## 原生这些值都在 `ParamData`（存档里的 `itemCapacity`／`monsterCapacity`），
## 菜单、商店、战斗结算、剧情共用同一份。模块只从这里按 `progress` 读，
## 不各自写 72／20；**缺键或类型不对就是存档数据错误**，不补任何默认值。

## 原生 `ItemData.bags` 的袋数（0 道具、1 装备、2 素材、3 技能书、4 精灵球、5 特殊球）。
const BAG_COUNT := 6
## 新建角色时写入的初值（原生 `ParamData.itemCapacity` 初值）。
const INITIAL_ITEM_CAPACITY := 72
## 新建角色时写入的初值（原生 `ParamData.monsterCapacity` 初值）。
const INITIAL_MONSTER_CAPACITY := 20
## 装备袋（`Item_bagList` 的 1 号袋）。
const EQUIPMENT_BAG := 1


## 新建角色用的六袋初值；只有角色创建这一处用，读取路径不走它。
static func initial_item_capacities() -> Array[int]:
	var caps: Array[int] = []
	for _bag in BAG_COUNT:
		caps.append(INITIAL_ITEM_CAPACITY)
	return caps


## 六袋上限。必须是长度 6 的非负整数数组；否则报错并返回空数组。
static func item_capacities(progress: Dictionary) -> Array[int]:
	var raw: Variant = progress.get("itemCapacity")
	if not raw is Array or raw.size() != BAG_COUNT:
		push_error("角色数据缺少合法的 itemCapacity[%d]：%s" % [BAG_COUNT, raw])
		return []
	var caps: Array[int] = []
	for bag in BAG_COUNT:
		var value: Variant = raw[bag]
		if not value is int or value < 0:
			push_error("角色数据的 itemCapacity[%d] 不是非负整数：%s" % [bag, value])
			return []
		caps.append(value)
	return caps


static func item_capacity(progress: Dictionary, bag: int) -> int:
	if bag < 0 or bag >= BAG_COUNT:
		return 0
	var caps := item_capacities(progress)
	return caps[bag] if bag < caps.size() else 0


## 怪物栏上限。必须是正整数；否则报错并返回 0。
static func monster_capacity(progress: Dictionary) -> int:
	var raw: Variant = progress.get("monsterCapacity")
	if not raw is int or raw <= 0:
		push_error("角色数据缺少合法的 monsterCapacity：%s" % raw)
		return 0
	return raw


static func inventory(progress: Dictionary) -> Dictionary:
	var raw: Variant = progress.get("inventory")
	if not raw is Dictionary:
		push_error("角色数据缺少 inventory：%s" % raw)
		return {}
	return raw


static func item_count(progress: Dictionary, item_id: int) -> int:
	return int(inventory(progress).get(str(item_id), 0))
