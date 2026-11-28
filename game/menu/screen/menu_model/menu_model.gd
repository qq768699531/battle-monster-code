extends RefCounted
class_name MenuModel

## Pure menu projections over native progress/catalog dictionaries, without scene dependencies.
## Invalid operations return {ok: false, error: ...} instead of throwing.
## Member projections never mutate progress or invent missing individual/resource values.
const Battle = preload("res://game/battle/combat/battle.gd")
const Story = preload("res://engine/data/story/story.gd")
const Book = preload("res://game/menu/book/book_model/book_model.gd")
const MonsterAttribute = preload("res://game/growth/monster_attribute/monster_attribute.gd")
const PlayerData = preload("res://engine/data/player_data/player_data.gd")
const MENU_WINDOW := {"x": 86, "y": 0, "width": 228, "height": 240}
const MENU_TABS := ["status", "items", "party", "quests", "options", "network"]
const TAB_NATIVE_INDICES := [0, 1, 2, 3, 5, 4]
## 顶部页签的页序（`MENU_TABS`／`TAB_NATIVE_INDICES` 的下标）。
enum Tab {
	STATUS = 0,
	ITEMS = 1,
	PARTY = 2,
	QUEST = 3,
	OPTIONS = 4,
	NETWORK = 5,
}
## 页签 → `scenes\menu.tscn` 里那页的节点名。
const TAB_PAGE_NAMES := ["status", "items", "party", "quest", "options", "network"]
const NETWORK_PACKAGES := [
	[0, 1, 0], [0, 6, 1], [1, 3, 1], [1, 7, 2], [2, 2, 1], [2, 5, 2],
	[4, 1, 0], [4, 6, 1], [5, 2, 1], [5, 5, 2], [6, 1, 0], [6, 6, 1],
	[7, 3, 1], [7, 7, 2], [19, 3, 1], [19, 7, 2], [20, 1, 0], [20, 6, 1],
	[23, 7, 1], [9, 1, 0], [10, 2, 1], [11, 2, 2], [12, 1, 2], [13, 3, 1],
	[14, 3, 2], [3, 3, 2], [15, 1, 2], [16, 1, 2], [21, 1, 2], [17, 1, 2],
	[18, 1, 0], [22, 1, 0], [22, 7, 1], [8, 1, 2],
]
const NETWORK_PRICES := [100, 500, 1000, 3000, 4000]
const BALL_ICONS := [153, 152, 154, 157, 156, 155]
## 每只怪占的 PARTY 点（`Ball_stdParty` 读 `CSWTCH.125[n5 + 18]`：1, 2, 4, 7, 8, 9），
## 下标是品级 `kind_specific_84`（本工程 `MonsterDefinition.attribute_entry`，0..5）；
## 超过 5 品级原生返回 0（本工程按资料缺失处理）。
const PARTY_COSTS := [1, 2, 4, 7, 8, 9]
## 每档公会给出的 PARTY 点基数（`Ball_guildPartys` 的栈上表 `v5[0..10]`：
## 4, 5, 7, 9, 11, 13, 14, 15, 16, 17, 27），下标是 `guild_grade()` 的档位号。
const GUILD_GRADE_PARTY_POINTS := [4, 5, 7, 9, 11, 13, 14, 15, 16, 17, 27]
## 标准进度：升一级要 `Param_stdSET` 的 `20 * level`，等级上限取 `MonsterAttribute.LEVEL_MAX`（99，满级）。
const STANDARD_PROGRESS_LEVEL_COST := 20
## PARTY 点上限的等级加成（`Ball_guildPartys`）：`v6.level / 0x14`，满级 99 再 +2。
const PARTY_POINTS_PER_LEVEL_BAND := 20
const PARTY_POINTS_FULL_LEVEL_BONUS := 2
## 出战队伍上限（`ItemData.party_monsters[0..2]`；`Ball_stdIsPartyOn` 第 3 格被占即 −2／`msg 470`）。
const PARTY_MEMBER_MAX := 3
## 组队等级差上限（`Ball_stdIsPartyOn` 的 `n104->level > player_progress.level + 5`，
## 越界即 `msg 559`「不可与比主人公高5级以上的组队」）。
const PARTY_LEVEL_GAP := 5
const STATUS_ATTRIBUTE_MAX := 239
## 动作号即 `common/msg.fxt` 的记录号（`Menu_List_Set`）。
const ITEM_ACTION_USE := 176
const ITEM_ACTION_MIX := 177
const ITEM_ACTION_DISCARD := 178
## 技能书「合成」的固定费用（`Menu_Item_mKeyPressed` 的 `Param_moneySET(-200)`；
## 书本详情页的费用行 `Menu_Item_DrawInfoBook` 画的也是这个数）。
const MIX_FEE := 200
## 配方槽的编码（`Menu_Item_Mix_IsPossible` 的 `LOBYTE`／`BYTE1`）：低字节是材料索引、
## 高字节是需要的数量；整槽为 0 表示这一味不需要。
const MIX_RECIPE_INDEX_MASK := 0xff
const MIX_RECIPE_COUNT_SHIFT := 8
const MIX_RECIPE_COUNT_MASK := 0xff
## 配方读 `detail_values[1]`／`[2]` 两槽（`Menu_Item_DrawInfoBook` 画的是同两槽）。
const MIX_RECIPE_SLOTS := [1, 2]
## 技能书合成走 `ItemEffect`（返回码 31–34 → `msg 504`–`507`）；这里只留兜底提示。
## 原生顺序（先扣 200 再结算）见 `mix_item`。
const MIX_UNSUPPORTED := "该道具的合成效果尚未接通；未扣除金币。"
const UNKNOWN_INDIVIDUAL := "旧槽未记录个体性格，派生属性未知；查看不会随机补值或改变存档。"


static func native_item_explanation(item: Dictionary, text: Callable) -> String:
	if not item.get("type") is int or not item.get("index") is int:
		return ""
	var type: int = item.type
	var index: int = item.index
	match type:
		1:
			if index >= 8 and index <= 16:
				return str(text.call(426)).replace("%s", str(text.call(417 + index - 8)))
			if index in [17, 18]:
				return str(text.call(427)).replace("%d", "10" if index == 17 else "50").replace("%%", "%")
			if index >= 19 and index <= 24:
				return str(text.call(434))
			if index >= 25 and index <= 30:
				return str(text.call(435))
			if index >= 31 and index <= 36:
				return str(text.call(436))
			if index == 37:
				return str(text.call(437))
		3:
			# `Item_stdExplain@0x82F70:116-118` 只置 `n220 = 220`，`:136-138` 再取
			# `JC_fxt2Return(2 * n220)`。
			return str(text.call(Msg.Id.ITEM_EXPLANATION_MATERIAL))
		5:
			if index == 0:
				return str(text.call(438))
			if index > 0 and index <= 6:
				return "%s%s" % [text.call(428 + index - 1), text.call(439)]
		6:
			return str(text.call(441))
		7:
			if index >= 0 and index <= 2:
				return str(text.call(442)).replace("%d", str(10 * (index + 1)))
			if index == 3:
				return str(text.call(443))
			if index in [4, 5]:
				return str(text.call(444)).replace("%d", str(50 * index - 30)).replace("%%", "%")
			if index in [6, 7]:
				return str(text.call(445)).replace("%d", str(60 * index - 140)).replace("%%", "%")
			if index >= 8 and index <= 16:
				return str(text.call([446, 447, 447, 447, 447, 448, 449, 450, 451][index - 8]))
			if index in [17, 18]:
				return str(text.call(452 + index - 17)).replace("%%", "%")
			if index >= 19 and index <= 23:
				return str(text.call(454 + index - 19)).replace("%%", "%")
	return ""


static func native_party_order(progress: Dictionary) -> Array:
	var recorded: Variant = progress.get("partyOrder")
	if recorded is Array:
		return recorded.duplicate()
	var monsters: Array = progress.get("monsters", [])
	var order: Array = []
	for index in range(mini(PARTY_MEMBER_MAX, monsters.size())):
		order.append(index)
	return order


static func move_party_member_last(progress: Dictionary, index: int) -> Dictionary:
	var order := native_party_order(progress)
	if not order.has(index):
		return {"ok": false, "error": "此成员不在当前出战队伍中"}
	var next_order: Array = []
	for member_index: Variant in order:
		if member_index != index:
			next_order.append(member_index)
	next_order.append(index)
	progress["partyOrder"] = next_order
	return {"ok": true}


static func leave_party(progress: Dictionary, index: int) -> Dictionary:
	var order := native_party_order(progress)
	if not order.has(index):
		return {"ok": false, "error": "此成员不在当前出战队伍中"}
	order.erase(index)
	progress["partyOrder"] = order
	return {"ok": true}


static func discard_party_member(progress: Dictionary, index: int) -> Dictionary:
	var monsters: Variant = progress.get("monsters")
	if not monsters is Array or index < 0 or index >= monsters.size() or \
			not monsters[index] is Dictionary:
		return {"ok": false, "error": "此成员不存在"}
	var order := native_party_order(progress)
	if order.has(index):
		return {"ok": false, "error": "请先让成员离开队伍，再丢弃。"}
	var remaining: Array = []
	for member_index: Variant in order:
		if not member_index is int or member_index < 0 or member_index >= monsters.size() \
				or remaining.has(member_index - int(member_index > index)):
			return {"ok": false, "error": "出战队伍记录无效，未丢弃成员。"}
		remaining.append(member_index - int(member_index > index))
	monsters.remove_at(index)
	progress["partyOrder"] = remaining
	return {"ok": true}


static func party_points(progress: Dictionary, catalog: GameplayData, order: Array) -> Variant:
	if order.is_empty():
		return 0
	var monsters: Variant = progress.get("monsters")
	if not monsters is Array:
		return null
	var points := 0
	for index: Variant in order:
		if not index is int or index < 0 or index >= monsters.size() or \
				not monsters[index] is Dictionary:
			return null
		var args: Variant = monsters[index].get("nativeArguments")
		if not _integer_array(args, 5):
			return null
		var record: MonsterDefinition = catalog.monster(int(args[0]))
		if record == null or record.attribute_entry not in range(PARTY_COSTS.size()):
			return null
		points += PARTY_COSTS[record.attribute_entry]
	return points


## 公会档位（`Ball_guildGrade`）：原生是 11 段比较链，**每段都比 `#0x63`（99）**，
## 所以 1..99 的公会码一律落到末档 10（`msg 469`「驯兽圣帝」），> 99 落到 0 档。
## 档位同时决定 `Ball_guildPartys` 的基础点数与 `Ball_guildTitle` 的档位名。
const GUILD_GRADE_MAX := 10


static func guild_grade(code: int) -> int:
	return GUILD_GRADE_MAX if code <= Story.GUILD_CODE_MAX else 0


## 存档里的公会码唯一读点在 `Story.guild_code()`（原生 `ParamData.guild_code_bits`）。
static func guild_code(progress: Dictionary) -> int:
	return Story.guild_code(progress)


## 档位名记录号：`Ball_guildTitle` 的 `JC_fxt2Return(459 + 档位)`。
static func guild_title_record(progress: Dictionary) -> int:
	return Msg.Id.GUILD_TITLE_FIRST + guild_grade(guild_code(progress))


## 原生 `Ball_guildPartys`：`档位基数 + 标准等级 / 20`（满级再 +2）。
static func party_point_limit(progress: Dictionary) -> Variant:
	var level := standard_level(progress)
	if level < 0:
		return null
	return GUILD_GRADE_PARTY_POINTS[guild_grade(guild_code(progress))] + \
		floori(float(level) / PARTY_POINTS_PER_LEVEL_BAND) + \
		(PARTY_POINTS_FULL_LEVEL_BONUS if level == MonsterAttribute.LEVEL_MAX else 0)


## 原生 `Param_stdSET`：标准进度点数按每级 `20 * level` 累计换算成等级（上限 99）。
## 未记录（缺字段／超范围）时返回 -1；捕获率与 PARTY 点上限都用这一个等级。
static func standard_level(progress: Dictionary) -> int:
	var parameter: Variant = progress.get("parameter")
	if not parameter is Dictionary:
		return -1
	var points: Variant = parameter.get("standardProgressPoints", 0)
	if not points is int or points < 0 or points > Story.STANDARD_PROGRESS_POINTS_MAX:
		return -1
	var remaining: int = points
	var level := 1
	while level < MonsterAttribute.LEVEL_MAX and remaining >= level * STANDARD_PROGRESS_LEVEL_COST:
		remaining -= level * STANDARD_PROGRESS_LEVEL_COST
		level += 1
	return level


## 原生 `Ball_stdIsPartyOn`：队伍满（−2／`msg 470`）、PARTY 点超上限（−3／`msg 471`）、
## 等级差超过 5（−4／`msg 559`）三条拒绝分支，其余返回已出战的只数。
static func join_party(progress: Dictionary, catalog: GameplayData, index: int) -> Dictionary:
	var monsters: Variant = progress.get("monsters")
	if not monsters is Array or index < 0 or index >= monsters.size() or \
			not monsters[index] is Dictionary:
		return {"ok": false, "error": "此成员不存在"}
	var args: Variant = monsters[index].get("nativeArguments")
	if not _integer_array(args, 5) or args[1] < 0 or args[1] > MonsterAttribute.LEVEL_MAX:
		return {"ok": false, "error": "成员原始参数不可用"}
	var order := native_party_order(progress)
	if order.has(index):
		return {"ok": false, "error": "此成员已在当前出战队伍中"}
	if order.size() >= PARTY_MEMBER_MAX:
		return {"ok": false, "error": "组队上限是3.", "message": Msg.Id.PARTY_FULL}
	var parameter: Variant = progress.get("parameter")
	if not parameter is Dictionary or not parameter.get("level") is int or \
			parameter.level < 0 or parameter.level > MonsterAttribute.LEVEL_MAX:
		return {"ok": false, "error": "主角等级记录不可用"}
	order.append(index)
	var points: Variant = party_points(progress, catalog, order)
	if points == null:
		return {"ok": false, "error": "成员品级资料缺失，无法确认所需 PARTY 点"}
	var point_limit: Variant = party_point_limit(progress)
	if not point_limit is int:
		return {"ok": false, "error": "标准进度未记录，无法确认 PARTY 点上限"}
	if points > point_limit:
		return {"ok": false, "error": "组队点数不足.", "message": Msg.Id.PARTY_POINTS_SHORT}
	if args[1] > parameter.level + PARTY_LEVEL_GAP:
		return {"ok": false, "error": "不可与比主人公高5级以上的组队",
			"message": Msg.Id.PARTY_LEVEL_GAP}
	progress["partyOrder"] = order
	return {"ok": true}


static func status_page_count(progress: Dictionary) -> int:
	return 1 + mini(PARTY_MEMBER_MAX, native_party_order(progress).size())


static func status_allocation_preview(progress: Dictionary, pending: Array,
		attribute_index: int) -> Dictionary:
	var development := _status_development(progress)
	if development.is_empty():
		return {"ok": false, "error": "角色培养记录不可用"}
	if not _integer_array(pending, 3) or pending.any(
			func(value: int) -> bool: return value < 0):
		return {"ok": false, "error": "待分配点数记录无效"}
	if attribute_index < 0 or attribute_index >= 3:
		return {"ok": false, "error": "能力槽索引无效"}
	var spent := 0
	for value: int in pending:
		spent += value
	if spent >= development["points"]:
		return {"ok": false, "error": "没有可分配点数"}
	if development["allocated"][attribute_index] + pending[attribute_index] >= \
			STATUS_ATTRIBUTE_MAX:
		return {"ok": false, "error": "该能力已达到原生上限"}
	var next_pending := pending.duplicate()
	next_pending[attribute_index] += 1
	return {"ok": true, "pending": next_pending, "remaining": development["points"] - spent - 1}


static func apply_status_allocation(progress: Dictionary, pending: Array) -> Dictionary:
	var development := _status_development(progress)
	if development.is_empty():
		return {"ok": false, "error": "角色培养记录不可用"}
	if not _integer_array(pending, 3) or pending.any(
			func(value: int) -> bool: return value < 0):
		return {"ok": false, "error": "待分配点数记录无效"}
	var spent := 0
	for index in range(3):
		spent += pending[index]
		if development["allocated"][index] + pending[index] > STATUS_ATTRIBUTE_MAX:
			return {"ok": false, "error": "该能力已达到原生上限"}
	if spent <= 0 or spent > development["points"]:
		return {"ok": false, "error": "待分配点数超出可用范围"}
	var updated := progress.duplicate(true)
	var updated_development: Dictionary = updated["parameter"]["development"]
	for index in range(3):
		updated_development["allocated"][index] += pending[index]
	updated_development["points"] -= spent
	return {"ok": true, "progress": updated, "spent": spent}


static func status_allocation_change(before: Dictionary, after: Dictionary) -> Dictionary:
	if before == after:
		return {"ok": true, "changed": false}
	var old_parameter: Variant = before.get("parameter")
	var new_parameter: Variant = after.get("parameter")
	if not old_parameter is Dictionary or not new_parameter is Dictionary:
		return {"ok": false, "error": "角色参数记录不可用"}
	var old_development: Variant = old_parameter.get("development")
	var new_development: Variant = new_parameter.get("development")
	if not old_development is Dictionary or not new_development is Dictionary:
		return {"ok": false, "error": "角色培养记录不可用"}
	var old_parameter_fields: Dictionary = old_parameter.duplicate(true)
	var new_parameter_fields: Dictionary = new_parameter.duplicate(true)
	old_parameter_fields.erase("development")
	new_parameter_fields.erase("development")
	var old_development_fields: Dictionary = old_development.duplicate(true)
	var new_development_fields: Dictionary = new_development.duplicate(true)
	old_development_fields.erase("points")
	old_development_fields.erase("allocated")
	new_development_fields.erase("points")
	new_development_fields.erase("allocated")
	var old_other := before.duplicate(true)
	var new_other := after.duplicate(true)
	old_other.erase("parameter")
	new_other.erase("parameter")
	if old_parameter_fields != new_parameter_fields or \
			old_development_fields != new_development_fields or old_other != new_other:
		return {"ok": false, "error": "状态变更包含未授权字段"}
	if not old_development.get("points") is int or \
			not new_development.get("points") is int or \
			not _integer_array(old_development.get("allocated"), 3) or \
			not _integer_array(new_development.get("allocated"), 3):
		return {"ok": false, "error": "角色培养记录无效"}
	var increments: Array[int] = []
	var spent := 0
	for index in range(3):
		var amount: int = new_development["allocated"][index] - \
				old_development["allocated"][index]
		if amount < 0:
			return {"ok": false, "error": "不能撤回已分配能力点"}
		increments.append(amount)
		spent += amount
	if spent <= 0 or old_development["points"] - new_development["points"] != spent:
		return {"ok": false, "error": "能力点变化不匹配"}
	var expected := apply_status_allocation(before, increments)
	if not expected.get("ok", false) or expected.get("progress") != after:
		return {"ok": false, "error": "能力点变化超出原生范围"}
	return {"ok": true, "changed": true, "increments": increments}


static func _status_development(progress: Dictionary) -> Dictionary:
	var parameter: Variant = progress.get("parameter")
	if not parameter is Dictionary:
		return {}
	var development: Variant = parameter.get("development")
	if not development is Dictionary or not development.get("points") is int or \
			development["points"] < 0 or not _integer_array(development.get("allocated"), 3) or \
			development["allocated"].any(
				func(value: int) -> bool: return value < 0 or value > STATUS_ATTRIBUTE_MAX):
		return {}
	return development


static func equip_party_member(progress: Dictionary, catalog: GameplayData,
		member_index: int, item_id: int) -> Dictionary:
	var monsters: Variant = progress.get("monsters", [])
	if not monsters is Array or \
			member_index < 0 or member_index >= monsters.size() or \
			not monsters[member_index] is Dictionary:
		return {"ok": false, "error": "此成员不存在"}
	var member: Dictionary = monsters[member_index]
	var args: Variant = member.get("nativeArguments")
	if not args is Array or args.size() < 4 or \
			not args.slice(0, 4).all(func(value: Variant) -> bool: return value is int):
		return {"ok": false, "error": "成员原始装备参数不可用"}
	if args[3] >= 0:
		return {"ok": false, "error": "成员已装备；请先卸下当前装备。"}
	var rows := native_inventory_rows(progress, catalog, 1)
	var selected: Dictionary = {}
	for row: Dictionary in rows:
		if row.get("id") == item_id and row.get("type") == ItemKind.Kind.EQUIPMENT:
			selected = row
			break
	if selected.is_empty():
		return {"ok": false, "error": "该装备不在可用背包中"}
	var inventory: Variant = progress.get("inventory", {})
	if not inventory is Dictionary:
		return {"ok": false, "error": "背包数据不可用"}
	var inventory_key := ""
	for key: Variant in inventory:
		if key is String and key.is_valid_int() and key.length() <= 9 and \
				int(key) == item_id and inventory[key] is int and inventory[key] > 0:
			inventory_key = key
			break
	if inventory_key.is_empty():
		return {"ok": false, "error": "装备数量不可用"}
	var entry: ItemDefinition = catalog.item(item_id)
	var item_index := -1
	if entry != null and entry.type == ItemKind.Kind.EQUIPMENT:
		item_index = entry.index
	if item_index < 0:
		return {"ok": false, "error": "原装备索引不可用"}
	var next_args: Array = args.duplicate()
	next_args[3] = item_index
	member["nativeArguments"] = next_args
	inventory[inventory_key] -= 1
	if inventory[inventory_key] == 0:
		inventory.erase(inventory_key)
	progress["inventory"] = inventory
	return {"ok": true, "item": selected}


static func unequip_party_member(progress: Dictionary, catalog: GameplayData,
		member_index: int) -> Dictionary:
	var monsters: Variant = progress.get("monsters", [])
	if not monsters is Array or \
			member_index < 0 or member_index >= monsters.size() or \
			not monsters[member_index] is Dictionary:
		return {"ok": false, "error": "此成员不存在"}
	var member: Dictionary = monsters[member_index]
	var args: Variant = member.get("nativeArguments")
	if not args is Array or args.size() < 4 or \
			not args.slice(0, 4).all(func(value: Variant) -> bool: return value is int):
		return {"ok": false, "error": "成员原始装备参数不可用"}
	var equipment: int = args[3]
	if equipment < 0 or equipment > 999:
		return {"ok": false, "error": "成员没有有效装备索引"}
	var inventory: Variant = progress.get("inventory", {})
	if not inventory is Dictionary:
		return {"ok": false, "error": "背包数据不可用"}
	var occupied := 0
	var inventory_key := ""
	var item_id := 2000 + equipment
	for key: Variant in inventory:
		if not key is String or not key.is_valid_int() or key.length() > 9:
			continue
		var id := int(key)
		var quantity: Variant = inventory[key]
		if id >= 2000 and id < 3000 and quantity is int and quantity > 0:
			occupied += quantity
			if id == item_id and inventory_key.is_empty():
				inventory_key = key
	if occupied >= PlayerData.item_capacity(progress, PlayerData.EQUIPMENT_BAG):
		return {"ok": false, "error": "装备背包已满，未卸下装备"}
	var next_args: Array = args.duplicate()
	next_args[3] = -1
	member["nativeArguments"] = next_args
	if inventory_key.is_empty():
		inventory[str(item_id)] = 1
	else:
		inventory[inventory_key] += 1
	progress["inventory"] = inventory
	var item: ItemDefinition = catalog.item(item_id)
	return {"ok": true, "item": item_row(item) if item != null else {}}


static func native_member_details(progress: Dictionary, catalog: GameplayData, index: int) -> Dictionary:
	var monsters: Array = progress.get("monsters", [])
	if index < 0 or index >= monsters.size() or not monsters[index] is Dictionary:
		return {"ok": false, "error": "成员不存在"}
	var member: Dictionary = monsters[index]
	var args: Variant = member.get("nativeArguments")
	# 旧存档的 8 项参数在 6／7 号位置带被动号与等级（见 `_member_passive_slots`），
	# 这里只要求前 5 项仍是原生 `Ball_stdSet` 的参数。
	if not args is Array or args.size() < 5 or not args.slice(0, 5).all(
			func(element: Variant) -> bool: return element is int):
		return {"ok": false, "error": "成员原始参数不可用"}
	var equipment: int = args[3]
	var item: ItemDefinition = catalog.item(2000 + equipment) if equipment >= 0 else null
	var ball: Variant = null
	var unavailable := UNKNOWN_INDIVIDUAL
	if member.has("nickname"):
		var resource_error := _ball_resource_error(catalog, args, member["nickname"], item)
		if resource_error.is_empty():
			# 第三参数是 `Ball_stdBasic` 的 `brain_current`（+0x2B），计入六项数值。
			ball = Battle.make_ball(catalog,
				[args[0], args[1], -1, int(member.get("brainCurrent", Battle.BRAIN_CURRENT_INITIAL)),
				0, args[2], 0, 0, equipment, -1], member["nickname"],
				_member_passive_slots(member))
		else:
			unavailable = "原属性资源不可用：%s；未生成替代数值。" % resource_error
	var hp: Variant = member.get("hp")
	var sp: Variant = member.get("sp")
	if ball != null:
		if hp == null:
			hp = ball["max_hp"]
		if sp == null:
			sp = ball["max_sp"]
	return {"ok": true, "member": member, "ball": ball, "unavailable": unavailable,
		"hp": hp, "sp": sp, "equipment": item_row(item) if item != null else {}}


static func _integer_array(value: Variant, size: int) -> bool:
	return value is Array and value.size() == size and value.all(
		func(element: Variant) -> bool: return element is int)


## BattleModel uses assertions for malformed resources; preflight permits a safe read-only
## unavailable projection (the original host caught constructor errors) rather than a crash.
static func _ball_resource_error(catalog: GameplayData, args: Array, nickname: Variant,
		item: ItemDefinition) -> String:
	if not nickname is int or nickname < 0 or nickname >= Battle.NICKNAMES.size():
		return "个体性格无效"
	var species: MonsterDefinition = catalog.monster(int(args[0]))
	if species == null or not _integer_array(species.ability_inputs, 6) or \
			not _integer_array(species.attribute_inputs, 6):
		return "缺少有效原怪兽属性资源"
	if args[3] >= 0:
		if item == null:
			return "缺少原装备资源"
		var slots := item.detail_slots
		if not slots is Array or slots.size() < 14 or not slots.all(
				func(value: Variant) -> bool: return value is int):
			return "原装备属性无效"
	return ""


## 原生选「使用」后进状态 9 的门：动作列表里得先有「使用」这一条（`Menu_Item_SetMenuList`），
## 且 `Ball_stdUse` 的这一支已经接通（`ItemEffect.supports`）。两者问的不是同一件事：
## 前者是**原生长不长得出这个条目**，后者是本工程**实现没实现**（例如第 1 组 25–30 原生有
## 「使用」，但其余被动强化还没还原，这里就仍然拒绝）。
## 原生第二层状态号：`Menu_Item_SetMenuList` 给第 7 组 9–18 填 5（直用，不选精灵），
## 第 1 组与第 7 组 {3, 20, 21} 填 9（`Menu_Party_Set` 选目标）。
static func item_needs_target(item: Dictionary) -> bool:
	return ItemEffect.needs_target(item)


static func item_use_supported(item: Dictionary) -> bool:
	return item_actions(item).has(ITEM_ACTION_USE) and ItemEffect.supports(item)


## 菜单侧使用道具：菜单记录与战斗球的字段形状不同，这里先把记录适配成 `ItemEffect` 的 `subject`，
## 再走与战斗相同的一份 `Ball_stdUse` 分派（战斗侧是 `BattleModel.use_item`），
## 最后把 HP／SP／心情／饱食度与觉醒档写回记录。原始返回码与提示记录号一并带出去。
## `random_seed` 只给宿主的回放校验用：同一种子重算随机球／技能书的抽取结果。
static func use_item(progress: Dictionary, catalog: GameplayData,
		item_id: int, member_index: int, random_seed: int = -1) -> Dictionary:
	# 原生二级选择是 `Menu_Party_Draw` 的 `Ball_bagList`：全部持有精灵都能当目标，
	# 不限于 `partyOrder` 的三只出战队伍。
	var monsters: Variant = progress.get("monsters")
	# `member_index < 0` = 原生第二层状态 5 的 `Ball_stdUseEx(0, 0, record)`：不选精灵。
	var direct := member_index < 0
	if not monsters is Array or (not direct and (member_index >= monsters.size() or \
			not monsters[member_index] is Dictionary)):
		return {"ok": false, "error": "此精灵不在当前队伍中"}
	var rows := native_inventory_rows(progress, catalog, 0)
	var selected: Dictionary = {}
	for row: Dictionary in rows:
		if row.get("id") == item_id and ItemEffect.supports(row):
			selected = row
			break
	if selected.is_empty():
		return {"ok": false, "error": "该道具的原效果尚未接通"}
	var inventory: Variant = progress.get("inventory")
	if not inventory is Dictionary:
		return {"ok": false, "error": "背包数据不可用"}
	var inventory_key := ""
	for key: Variant in inventory:
		if not key is String or not key.is_valid_int() or int(key) != item_id:
			continue
		if not inventory[key] is int or inventory[key] <= 0 or not inventory_key.is_empty():
			return {"ok": false, "error": "道具数量不可用"}
		inventory_key = key
	if inventory_key.is_empty():
		return {"ok": false, "error": "背包中没有该道具"}
	var ball: Dictionary = {}
	var member: Dictionary = {}
	if not direct:
		var details := native_member_details(progress, catalog, member_index)
		var resolved: Variant = details.get("ball")
		if not details.get("ok", false) or not resolved is Dictionary:
			return {"ok": false, "error": str(details.get("unavailable", "原成员属性不可用"))}
		ball = resolved
		member = monsters[member_index]
		# 记录上的运行时值灌进 `Ball_stdBasic` 算出的球：HP／SP 没记就是满，心情与饱食度恒有值。
		ball["hp"] = int(details["hp"])
		ball["sp"] = int(details["sp"])
		ball["feel"] = int(member.get("feel", 0))
		ball["food"] = int(member.get("food", ItemEffect.FOOD_MAX))
		# 第 7 组 3 写 `Ball_stdSet` 的 `brain_current`（+0x2B），菜单记录存在 `brainCurrent`。
		ball["brain_current"] = int(member.get("brainCurrent", Battle.BRAIN_CURRENT_INITIAL))
		# 菜单记录不带状态表：原生这一段状态也在记录里，本工程只有战斗球持有（见 beads `bm-P1-4`）。
		ball["statuses"] = {}
	var parameter: Variant = progress.get("parameter", {})
	var standard := standard_level(progress)
	var context := {"catalog": catalog, "standard_level": standard if standard > 0 else 1,
		"level": int(parameter.get("level", 1)) if parameter is Dictionary else 1}
	if random_seed >= 0:
		context["random_seed"] = random_seed
	var result := ItemEffect.apply(ball, selected,
		func(target: Dictionary) -> String: return Battle.awaken_ball(target, catalog), context)
	if not result.get("ok", false):
		return result
	# 第 7 组 9–12：原生 `Ball_stdAddEx` 成功才 `v6 = 1` 扣道具；怪包满时返回 22、不扣。
	var generated_monster: Variant = result.get("generated_monster")
	if generated_monster is Dictionary:
		if monsters.size() >= PlayerData.monster_capacity(progress):
			return _generated_failure(selected, member_index, ItemEffect.Code.RANDOM_BALL_FULL)
		var species := int(generated_monster.get("species", 0))
		monsters.append(_generated_monster_record(generated_monster, random_seed))
		Book.discover_monster(progress, species)
	# 第 7 组 13–14：书袋满时 `Item_stdAddEx` 返回 0 → 24、不扣。
	var generated_item: Variant = result.get("generated_item")
	if generated_item is int:
		if not _add_generated_item(progress, int(generated_item)):
			return _generated_failure(selected, member_index, ItemEffect.Code.RANDOM_BOOK_FULL)
		Book.discover_item(progress, int(generated_item))
	if bool(result.get("consumed", false)):
		inventory[inventory_key] -= 1
		if inventory[inventory_key] == 0:
			inventory.erase(inventory_key)
		progress["inventory"] = inventory
	if not direct and int(result.get("code", ItemEffect.Code.FAILED)) in [
			ItemEffect.Code.PASSIVE_UPGRADE_DONE, ItemEffect.Code.PASSIVES_CLEARED]:
		member["passiveSlots"] = ball["passive_slots"]
	if not direct:
		if bool(result.get("evolved", false)) and member.get("nativeArguments") is Array:
			# 与战后写回同一条规则：觉醒档存在 `nativeArguments[2]`
			# （`Ball_stdFeel` 的 `definition_id + 1000`）。
			member["nativeArguments"][2] = int(ball["native_arguments"][5])
		member["hp"] = int(ball["hp"])
		member["sp"] = int(ball["sp"])
		member["feel"] = int(ball["feel"])
		member["food"] = int(ball["food"])
		member["brainCurrent"] = int(ball["brain_current"])
		progress["monsters"] = monsters
	var code := int(result.get("code", ItemEffect.Code.FAILED))
	# 随机球生成的那只（原生 `Ball_stdAddEx` 入包后要推 fxt 478「%s获得」）。
	var generated_species := -1
	var generated_grade := -1
	var generated_nickname := 0
	if generated_monster is Dictionary:
		generated_species = int(generated_monster.get("species", -1))
		# 随机球的品级＝球的档位（第 7 组 9–12 → 0–3），性格由 _generated_monster_record 掷。
		generated_grade = ItemKind.index_of(item_id) - ItemEffect.ITEM_FIRST_RANDOM_BALL
		generated_nickname = int(monsters.back().get("nickname", 0)) \
			if not monsters.is_empty() and monsters.back() is Dictionary else 0
	return {"ok": true, "item": selected, "member_index": member_index, "code": code,
		"generated_species": generated_species, "generated_grade": generated_grade,
		"generated_nickname": generated_nickname,
		"message_id": ItemEffect.message_id(code),
		"consumed": bool(result.get("consumed", false)),
		"hp_restored": int(result.get("hp_restored", 0)),
		"sp_restored": int(result.get("sp_restored", 0)),
		"evolved": bool(result.get("evolved", false))}


## 菜单宿主只认「菜单自己声明的操作」而不信任提交上来的快照：用活状态重放同一操作，
## 结果必须逐字段等于快照。随机球／技能书带 `seed`，重抽结果才能对齐（`ItemEffect._roll`）。
## kind：`use`（`item_id`／`member`／`seed`）、`mix`（`item_id`／`member`）、
## `discard`（`item_id`／`count`／`category`）。
static func replay_operation(progress: Dictionary, catalog: GameplayData,
		operation: Dictionary) -> Dictionary:
	var candidate: Dictionary = progress.duplicate(true)
	var kind := str(operation.get("kind", ""))
	var item_id := int(operation.get("item_id", -1))
	var member := int(operation.get("member", -1))
	if kind == "use":
		var used := use_item(candidate, catalog, item_id, member,
			int(operation.get("seed", -1)))
		return {"ok": bool(used.get("ok", false)), "progress": candidate,
			"result": used}
	if kind == "network-buy":
		var bought := buy_network_offer(candidate, {"id": item_id, "quantity":
			int(operation.get("count", 1))})
		return {"ok": bool(bought.get("ok", false)), "progress": candidate, "result": bought}
	var category := int(operation.get("category", ItemKind.Bag.ITEMS))
	var row := _inventory_row(candidate, catalog, item_id, category)
	if row.is_empty():
		return {"ok": false, "progress": candidate, "result": {"error": "背包中没有该道具"}}
	if kind == "mix":
		var mixed := mix_item(candidate, row, member)
		return {"ok": bool(mixed.get("ok", false)), "progress": candidate,
			"result": mixed}
	if kind == "discard":
		var dropped := discard_inventory_item(candidate, row, int(operation.get("count", 1)))
		return {"ok": bool(dropped.get("ok", false)), "progress": candidate,
			"result": dropped}
	return {"ok": false, "progress": candidate, "result": {"error": "未知的道具操作"}}


static func _inventory_row(progress: Dictionary, catalog: GameplayData,
		item_id: int, category: int) -> Dictionary:
	for row: Dictionary in native_inventory_rows(progress, catalog, category):
		if int(row.get("id", -1)) == item_id:
			return row
	return {}


static func native_main_quest(progress: Dictionary, text: Variant) -> Dictionary:
	var source := "evt/evtlist.fxt #%s" % progress.get("quest", 0)
	var pages := PackedStringArray()
	if text is String:
		var colors := RegEx.new()
		colors.compile("#C[0-9A-Fa-f]")
		pages = colors.sub(text, "", true).split("\t", true)
	var values: Array[String] = []
	var labels := ["标题", "说明"]
	for index in range(2):
		values.append(pages[index] if pages.size() > index and not pages[index].strip_edges().is_empty()
			else "【%s · %s待转换】" % [source, labels[index]])
	var region_ids: Array[int] = []
	if pages.size() > 3:
		var regions := pages[3].split(",", true)
		for index in range(mini(10, regions.size())):
			var value := regions[index].strip_edges()
			if not value.is_valid_int():
				push_error("Invalid quest region index in %s: %s" % [source, value])
				continue
			var region := int(value)
			if region >= 0:
				region_ids.append(region)
	return {"source": source, "title": values[0], "description": values[1],
		# 分页原样带出去：世界地图要 page 3／page 4 画标记（`Map_worldDRAW`）。
		"pages": pages, "region_ids": region_ids, "status": "进行中"}


static func menu_tab_at(x: float, y: float) -> Variant:
	var left: int = MENU_WINDOW["x"] + 4
	if y < 4 or y >= 46 or x < left or x >= left + 6 * 37:
		return null
	var native_index := int(floor((x - left) / 37))
	return TAB_NATIVE_INDICES.find(native_index)


static func native_network_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for package: Array in NETWORK_PACKAGES:
		var index: int = package[0]
		offers.append({"id": 7000 + index, "type": 7, "index": index,
			"quantity": package[1], "cash_tag": package[2], "cash_price": NETWORK_PRICES[package[2]],
			"name_record": "item_basic.group.7.entry.%d.name" % index})
	return offers


## NET 商店的一单购买（原生 `Menu_NET_*` 的购买流程）：付款阶段尚未接通，先只入包、不扣金币。
## 返回 `{"ok": true, "id": …, "count": …}` 或 `{"ok": false, "error": …}`。
static func buy_network_offer(progress: Dictionary, offer: Dictionary) -> Dictionary:
	var item_id := int(offer.get("id", 0))
	var count := int(offer.get("quantity", 0))
	if item_id <= 0 or count <= 0:
		return {"ok": false, "error": "NET 商品数据不完整"}
	if not _add_generated_item(progress, item_id, count):
		return {"ok": false, "error": "背包放不下这些道具"}
	return {"ok": true, "id": item_id, "count": count}


## 同一条入包规则的试算：NET 页开付款确认前先核对背包放不放得下（原生 `Item_stdIsAdd`）。
static func can_buy_network_offer(progress: Dictionary, offer: Dictionary) -> bool:
	return bool(buy_network_offer(progress.duplicate(true), offer).get("ok", false))


static func menu_footer_at(x: float, y: float) -> Variant:
	if y < 220 or y >= 240:
		return null
	if x >= MENU_WINDOW["x"] + 4 and x < MENU_WINDOW["x"] + 52:
		return "confirm"
	if x >= MENU_WINDOW["x"] + 176 and x < MENU_WINDOW["x"] + 224:
		return "back"
	return null


## 背包归属：原生 ``Menu_Item_*`` 的袋号，同一套规则也用在事件与结算里（见 `ItemKind`）。
static func menu_item_bag(type: int, index: int) -> int:
	return ItemKind.bag_of(type, index)


## `Menu_Item_SetMenuList`（按袋号组动作表）＋`Menu_List_Set`（参数 → 文案记录号：
## 5／9 → 176 使用、10 → 177 合成、6 → 178 丢弃）。
## 原生给「使用」的是：第 1 组索引 ≤ 7、19–24、31–37；第 7 组 3、9–18、20、21。
## 注意第 1 组的 8–18（治疗异常状态／复活）**没有**「使用」条目——那些只在战斗里用。
## 袋 3（技能书）的 `case 3` 无条件 `Menu_List_Set(10)` + `Menu_List_Set(6)`，即「合成」＋「丢弃」。
static func item_actions(item: Dictionary) -> Array[int]:
	if not item.get("type") is int or not item.get("index") is int:
		return [ITEM_ACTION_DISCARD]
	var type: int = item.type
	var index: int = item.index
	var bag := menu_item_bag(type, index)
	if bag == ItemKind.Bag.SKILL_BOOKS:
		return [ITEM_ACTION_MIX, ITEM_ACTION_DISCARD]
	if bag == ItemKind.Bag.ITEMS:
		if type == ItemKind.Kind.CONSUMABLE and \
				(index <= 7 or (index >= 19 and index <= 24) or (index >= 31 and index <= 37)):
			return [ITEM_ACTION_USE, ITEM_ACTION_DISCARD]
		if type == ItemKind.Kind.GROUP_7 and \
				(index in [3, 20, 21] or (index >= 9 and index <= 18)):
			return [ITEM_ACTION_USE, ITEM_ACTION_DISCARD]
	return [ITEM_ACTION_DISCARD]


## `Menu_Item_Mix_IsPossible`：`Item_datBasic` 解得记录后按 `detail_values[1]`／`[2]`
## 核材料——每槽用 `Item_fndCount(IK_METERIAL = 3, 低字节索引)` 比高字节数量，整槽为 0（或数量为 0）
## 就算这一味不需要。原生日志解析不出来时返回 0，这里按「配方不可用」处理。
static func material_recipe_possible(progress: Dictionary, item: Dictionary) -> bool:
	var slots: Variant = item.get("detail_slots")
	if not slots is Array or slots.size() <= MIX_RECIPE_SLOTS.back():
		return false
	var inventory: Variant = progress.get("inventory", {})
	if not inventory is Dictionary:
		return false
	for slot: int in MIX_RECIPE_SLOTS:
		var encoded: Variant = slots[slot]
		if not encoded is int or encoded < 0:
			return false
		var recipe: int = encoded
		if recipe == 0:
			continue
		var required := (recipe >> MIX_RECIPE_COUNT_SHIFT) & MIX_RECIPE_COUNT_MASK
		var material_id := ItemKind.id_of(ItemKind.Kind.MATERIAL,
			recipe & MIX_RECIPE_INDEX_MASK)
		var owned: Variant = inventory.get(str(material_id), 0)
		if not owned is int or owned < required:
			return false
	return true


## 技能书「合成」的成员确认（`Menu_Item_mKeyPressed` 的 `quest_layer == 10` 分支）：
## 原生先查余额（`money_balance <= 0xC7` 即 199 时 `Game_infoInit` 报 `msg 79` 且**不**扣钱），
## 再 `Param_moneySET(-200)`，最后 `Ball_stdUseEx(ball, 0, record)`。材料够不够在选动作那一步
## 已经查过（`Menu_Item_Mix_IsPossible`），原生这里不再查。
## 已登记偏差：第 4 组的合成效果还没落地，原生是「先扣钱再见效果」，这里在扣钱之前先问
## `ItemEffect.supports`，不支持就直接返回提示、不扣钱，避免白扣 200。
static func mix_item(progress: Dictionary, item: Dictionary, member_index: int) -> Dictionary:
	var monsters: Variant = progress.get("monsters")
	if not monsters is Array or member_index < 0 or member_index >= monsters.size() or \
			not monsters[member_index] is Dictionary:
		return {"ok": false, "error": "此精灵不在当前队伍中"}
	var parameter: Variant = progress.get("parameter")
	var balance: Variant = parameter.get("moneyBalance") if parameter is Dictionary else null
	if not balance is int:
		return {"ok": false, "error": "当前进度未记录金币余额"}
	if balance < MIX_FEE:
		return {"ok": false, "error": "金币不足", "message_id": Msg.Id.SHOP_NOT_ENOUGH_MONEY}
	if not ItemEffect.supports(item):
		return {"ok": false, "error": MIX_UNSUPPORTED}
	# 原生 `Menu_Item_mKeyPressed:0xA`：`Param_moneySET(-200)` 紧在 `Ball_stdUseEx` 之前，
	# 所以「重复被动(32)／空槽不足(34)」是先付钱再报；材料在 `Ball_stdUse:140-166` 里再核一次（33）。
	parameter["moneyBalance"] = balance - MIX_FEE
	if not material_recipe_possible(progress, item):
		return {"ok": true, "code": ItemEffect.Code.MIX_NO_MATERIAL,
			"message_id": ItemEffect.message_id(ItemEffect.Code.MIX_NO_MATERIAL)}
	var member: Dictionary = monsters[member_index]
	var passive_slots := _member_passive_slots(member)
	var result := ItemEffect.apply({"passive_slots": passive_slots}, item)
	if not result.get("ok", false):
		return result
	if int(result["code"]) == ItemEffect.Code.MIX_DONE:
		member["passiveSlots"] = passive_slots
		_deduct_mix_materials(progress, item)
	return {"ok": true, "code": int(result["code"]), "slot": int(result.get("slot", -1)),
		"message_id": ItemEffect.message_id(int(result["code"]))}


## 成员的 0–5 号被动槽；旧存档没有 `passiveSlots` 时按 `nativeArguments[6]`／`[7]` 落到 0 号槽。
static func _member_passive_slots(member: Dictionary) -> Array:
	var stored: Variant = member.get("passiveSlots")
	if stored is Array and stored.size() == ItemEffect.PASSIVE_SLOT_COUNT:
		return stored.duplicate(true)
	var slots: Array = []
	for _slot: int in range(ItemEffect.PASSIVE_SLOT_COUNT):
		slots.append([0, 0])
	var args: Variant = member.get("nativeArguments")
	if args is Array and args.size() > ItemEffect.PASSIVE_SLOT_COUNT + 1:
		slots[0] = [int(args[6]), int(args[7])]
	return slots


## `Ball_stdUse:176-181`：合成成功时按 `detail_values[1]`／`[2]` 各扣一次材料。
static func _deduct_mix_materials(progress: Dictionary, item: Dictionary) -> void:
	var slots: Variant = item.get("detail_slots")
	var inventory: Variant = progress.get("inventory")
	if not slots is Array or not inventory is Dictionary:
		return
	for slot: int in MIX_RECIPE_SLOTS:
		var recipe: int = int(slots[slot])
		if recipe == 0:
			continue
		var required := (recipe >> MIX_RECIPE_COUNT_SHIFT) & MIX_RECIPE_COUNT_MASK
		var key := str(ItemKind.id_of(ItemKind.Kind.MATERIAL, recipe & MIX_RECIPE_INDEX_MASK))
		var left := int(inventory.get(key, 0)) - required
		if left > 0:
			inventory[key] = left
		else:
			inventory.erase(key)


## 第 7 组 9–12 的 `Ball_stdSet` 记录：`nativeArguments` 与捕获记录同形
## `[物种, 等级, 觉醒档, 装备, 成长]`，0 号被动槽写随机被动 1 级；`brain_limit` 恒 99、
## `feel_value` 0、`food_value` 100（`Ball_stdSet@0x85E20:29-47`）。
## `random_seed` 同时决定随机球那只新个体的性格；宿主回放用同一种子复现整条记录。
static func _generated_monster_record(generated: Dictionary, random_seed: int = -1) -> Dictionary:
	var nickname_rng := RandomNumberGenerator.new()
	if random_seed >= 0:
		nickname_rng.seed = random_seed
	var species := int(generated.get("species", 0))
	var level := int(generated.get("level", 1))
	var passive_slots: Array = []
	for _slot: int in range(ItemEffect.PASSIVE_SLOT_COUNT):
		passive_slots.append([0, 0])
	passive_slots[0] = [int(generated.get("passive_id", 0)), 1]
	return {"species": species, "level": level,
		"nativeArguments": [species, level, 0, -1, -1],
		"nickname": Battle.roll_nickname(func(count: int) -> int: return (
			nickname_rng.randi() if random_seed >= 0 else randi()) % count),
		"experience": 0, "feel": 0, "food": ItemEffect.FOOD_MAX,
		"brainCurrent": int(generated.get("brain_current", Battle.BRAIN_CURRENT_INITIAL)),
		"brainLimit": Battle.BRAIN_LIMIT, "passiveSlots": passive_slots}


## 入包失败仍算「使用成功」，但返回码是 22／24 且不扣道具（`Ball_stdUse` 在这之前 return）。
static func _generated_failure(item: Dictionary, member_index: int, code: int) -> Dictionary:
	return {"ok": true, "item": item, "member_index": member_index, "code": code,
		"message_id": ItemEffect.message_id(code), "consumed": false}


## `Item_stdAddEx` 的背包写入：按 `Item_stdMax` 折算格数并核 `itemCapacity[袋号]`。
## 技能书走袋 3，与剧情／宝箱的 `_add_inventory_item` 同一套堆叠与容量规则。
static func _add_generated_item(progress: Dictionary, item_id: int, count := 1) -> bool:
	var inventory: Variant = progress.get("inventory")
	if not inventory is Dictionary or count <= 0:
		return false
	var type := ItemKind.kind_of(item_id)
	var index := ItemKind.index_of(item_id)
	var bag := ItemKind.bag_of(type, index)
	if bag < 0:
		return false
	var key := str(item_id)
	var current := int(inventory.get(key, 0))
	var capacity := PlayerData.item_capacity(progress, bag)
	var occupied := _generated_stack_slots(current + count, ItemKind.max_stack(type, index))
	for other: Variant in inventory:
		var other_key := str(other)
		if other_key == key or not other_key.is_valid_int():
			continue
		var other_id := int(other_key)
		var other_type := ItemKind.kind_of(other_id)
		var other_index := ItemKind.index_of(other_id)
		if ItemKind.bag_of(other_type, other_index) == bag:
			occupied += _generated_stack_slots(int(inventory[other]),
				ItemKind.max_stack(other_type, other_index))
	if occupied > capacity:
		return false
	inventory[key] = current + count
	progress["inventory"] = inventory
	return true


## `Item_stdMax` 的堆叠上限 → 占几格（向上取整；0 个不占格）。
static func _generated_stack_slots(count: int, limit: int) -> int:
	return 0 if count <= 0 or limit <= 0 else (count + limit - 1) / limit

## `Item_stdMax`：该道具的单格堆叠上限；等于 1 时原生跳过丢弃数量选择。
static func item_stack_limit(item: Dictionary) -> int:
	if not item.get("type") is int or not item.get("index") is int:
		return 1
	return ItemKind.max_stack(item.type, item.index)


## `Item_stdDels`（`a4 = 1`）：跨同种堆叠扣掉 count 个，随后重排该袋。
static func discard_inventory_item(progress: Dictionary, item: Dictionary, count: int) -> Dictionary:
	if count <= 0:
		return {"ok": false, "error": "丢弃数量无效"}
	if not item.get("id") is int:
		return {"ok": false, "error": "道具记录不可用"}
	var inventory: Variant = progress.get("inventory")
	if not inventory is Dictionary:
		return {"ok": false, "error": "背包数据不可用"}
	var key := str(item["id"])
	if not inventory.get(key) is int:
		return {"ok": false, "error": "背包中没有该道具"}
	var owned: int = inventory[key]
	if count > owned:
		return {"ok": false, "error": "丢弃数量超过持有数量"}
	inventory[key] = owned - count
	if inventory[key] <= 0:
		inventory.erase(key)
	progress["inventory"] = inventory
	return {"ok": true, "remaining": owned - count}


static func item_row(entry: ItemDefinition) -> Dictionary:
	var row := {"id": entry.id, "type": entry.type, "index": entry.index,
		"name": "原道具 %d:%d" % [entry.type, entry.index],
		"grade_index": entry.grade_index, "icon": entry.icon}
	if not entry.name_record.is_empty():
		row["name_record"] = entry.name_record
	if not entry.result_name_record.is_empty():
		row["result_name_record"] = entry.result_name_record
	if not entry.result_description_record.is_empty():
		row["result_description_record"] = entry.result_description_record
	if entry.purchase_price >= 0:
		row["purchase_price"] = entry.purchase_price
	if not entry.detail_slots.is_empty():
		row["detail_slots"] = entry.detail_slots.duplicate()
	return row


static func native_inventory_rows(progress: Dictionary, catalog: GameplayData,
		category: int) -> Array[Dictionary]:
	var inventory: Variant = progress.get("inventory", {})
	if not inventory is Dictionary:
		inventory = {}

	var quantities := {}
	for key: Variant in inventory:
		if not key is String or not key.is_valid_int() or key.length() > 9:
			continue
		var quantity: Variant = inventory[key]
		if not quantity is int or quantity <= 0:
			continue
		var item_id := int(key)
		quantities[item_id] = quantities.get(item_id, 0) + quantity

	var rows: Array[Dictionary] = []
	# 经验加成道具（`Ball_stdUse:1060-1070`）要按引用改写存档的 `standard_progress + 7`，
	# 而 `ItemEffect.apply` 只拿得到道具行，所以行里带上参数表这一份引用（战斗与菜单同源）。
	var parameter: Variant = progress.get("parameter")
	for entry: ItemDefinition in catalog.items:
		var item_id: int = entry.id
		var type: int = entry.type
		var index: int = entry.index
		if item_id != ItemKind.id_of(type, index) or menu_item_bag(type, index) != category or \
				not quantities.has(item_id):
			continue
		var row := item_row(entry)
		row["quantity"] = quantities[item_id]
		if parameter is Dictionary:
			row["parameter"] = parameter
		rows.append(row)
		quantities.erase(item_id)

	var unknown_ids: Array = quantities.keys()
	unknown_ids.sort()
	for item_id: Variant in unknown_ids:
		var type := ItemKind.kind_of(item_id)
		var index := ItemKind.index_of(item_id)
		if menu_item_bag(type, index) != category:
			continue
		rows.append({"id": item_id, "type": type, "index": index,
			"quantity": quantities[item_id], "name": "未解析原道具 %d" % item_id})
	return rows


static func menu_ball_icon(attribute_group: int) -> Variant:
	if attribute_group < 1 or attribute_group > BALL_ICONS.size():
		return null
	return BALL_ICONS[attribute_group - 1]


static func menu_visible_start(index: int, count: int, columns: int, rows: int) -> int:
	if columns <= 0 or rows <= 0:
		return 0
	var total_rows := int(ceil(float(count) / columns))
	var selected_row := int(floor(float(index) / columns))
	return maxi(0, mini(selected_row - rows + 1, total_rows - rows)) * columns
