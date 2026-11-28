extends RefCounted
## 存档数据的唯一入口：角色、物品栏、怪物栏、持有数等所有可变数据。
##
## 原生这些值都在 `ParamData`（存档里的 `itemCapacity`／`monsterCapacity`／`monsters`／
## `inventory` 等），菜单、商店、战斗结算、剧情共用同一份。模块只从这里按 `progress` 读，
## 不各自写 72／20，也不在读取时补默认数组；**缺键或类型不对就是存档数据错误**。
## 静态的种族／图鉴数值不属于存档，仍走 `content/` 与 `AssetCatalog`。

## 原生 `ItemData.bags` 的袋数（0 道具、1 装备、2 素材、3 技能书、4 精灵球、5 特殊球）。
const BAG_COUNT := 6
## 新建角色时写入的初值（原生 `ParamData.itemCapacity` 初值）。
const INITIAL_ITEM_CAPACITY := 72
## 新建角色时写入的初值（原生 `ParamData.monsterCapacity` 初值）。
const INITIAL_MONSTER_CAPACITY := 20
## 装备袋（`Item_bagList` 的 1 号袋）。
const EQUIPMENT_BAG := 1
## 出战位上限（`ItemData.party_monsters[0..2]`）。
const PARTY_SIZE := 3


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
		push_error("存档缺少合法的 itemCapacity[%d]：%s" % [BAG_COUNT, raw])
		return []
	var caps: Array[int] = []
	for bag in BAG_COUNT:
		var value: Variant = raw[bag]
		if not value is int or value < 0:
			push_error("存档的 itemCapacity[%d] 不是非负整数：%s" % [bag, value])
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
		push_error("存档缺少合法的 monsterCapacity：%s" % raw)
		return 0
	return raw


## 全部怪物实例（存档 `monsters`，含出战与仓库）。返回记录引用，写字段会落到存档。
static func monsters(progress: Dictionary) -> Array[Dictionary]:
	var raw: Variant = progress.get("monsters")
	if not raw is Array:
		push_error("存档缺少 monsters：%s" % raw)
		return []
	var result: Array[Dictionary] = []
	for member: Variant in raw:
		if not member is Dictionary:
			push_error("存档 monsters 里出现非字典记录：%s" % member)
			return []
		result.append(member)
	return result


static func monster_count(progress: Dictionary) -> int:
	return monsters(progress).size()


static func monster_at(progress: Dictionary, index: int) -> Dictionary:
	var all := monsters(progress)
	return all[index] if index >= 0 and index < all.size() else {}


## 出战顺序（存档 `partyOrder` 的下标表）。该字段允许缺省（没有出战队伍），
## 缺省就是空数组；出现但不是合法下标数组则报错。
static func party_order(progress: Dictionary) -> Array[int]:
	if not progress.has("partyOrder"):
		return []
	var raw: Variant = progress["partyOrder"]
	if not raw is Array:
		push_error("存档 partyOrder 不是数组：%s" % raw)
		return []
	var result: Array[int] = []
	for index: Variant in raw:
		if not index is int or index < 0:
			push_error("存档 partyOrder 含非法下标：%s" % index)
			return []
		result.append(index)
	return result


## 出战队伍（按 `partyOrder` 映射到 `monsters` 的记录）。
static func party_monsters(progress: Dictionary) -> Array[Dictionary]:
	var all := monsters(progress)
	var result: Array[Dictionary] = []
	for index in party_order(progress):
		if index >= all.size():
			push_error("存档 partyOrder 下标越界：%d / %d" % [index, all.size()])
			return []
		result.append(all[index])
	return result


## 入队；容量满或记录非法返回 false，不静默改存档。
static func add_monster(progress: Dictionary, monster: Dictionary) -> bool:
	if monster.is_empty():
		return false
	var all := monsters(progress)
	if all.size() >= monster_capacity(progress):
		return false
	all.append(monster)
	progress["monsters"] = all
	return true


static func inventory(progress: Dictionary) -> Dictionary:
	var raw: Variant = progress.get("inventory")
	if not raw is Dictionary:
		push_error("存档缺少 inventory：%s" % raw)
		return {}
	return raw


static func item_count(progress: Dictionary, item_id: int) -> int:
	return int(inventory(progress).get(str(item_id), 0))
