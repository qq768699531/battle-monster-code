class_name QuestLog
extends RefCounted
## 运行时任务槽（原生 `ParamData.quests`，`QuestEntryType[11]`，每槽 40 字节）＋完成位图。
##
## 槽区不是「12 个随便用的槽」：`Qst_stdEmpty` 的模式参数就是区间选择器——
## 模式 2 只认 `quests[0]`（公会任务，一次一条），模式 3 在 `quests[1..10]` 里找第一个空槽
## （普通 NPC 任务）。两种模式互不通用，`Qst_stdRemove` 也只把 1..10 往前压实。
## 存档同理（`Game_saveSET` 侧）：槽 0 单独走流，`quests[1..10]` 一次性 `memcpy` 400 字节。
##
## `QuestEntryType` 的字段偏移（IDA 类型库，与 `Qst_datFindINDEX` 写入基址 +4 对齐）：
##   +0  `active_marker` 1 字节：0 = 空槽，非 0 = 接取时的上下文。`Qst_stdSET` 写
##       `QstData.context_parameter_bits`，只有 2（公会任务页）与 3（NPC 任务页）两种来源。
##   +4  `npc_id` 1 字节（`Qst_datFindINDEX` 的 `out[0]`，`Qst_stdQuest` 靠它找「这个 NPC 的任务」）。
##   +5  `quest_id` 1 字节（`out[1]`，`Qst_stdFind` 只比这一个字节）。
##   +14 `goal_kind`、+15..16 `goal_target`（uint16，其中高字节被 `Qst_stdCHECK` 当数量用，
##       也就是 qstlist 的 `goal_target`／`goal_count` 两个字节）。
##   +32 `progress_value`（int，**只在 `goal_kind == 0` 时是进度**；1／2 的原生现场清点背包）。
##   +36 `text_resource`（`qst/qstlist.fxt` 拷贝，不进存档）。
## 完成标记不在槽里：`Qst_stdIsComplete` 读 `ParamData.skill_book_first_bits[22 + id / 8]`
## 的第 `id % 8` 位，即 55 个任务号共用 7 字节位图（quest 0–55）。

const SLOT_COUNT := 11
## `Qst_stdEmpty(2)` 的唯一目标槽：公会任务。
const SLOT_GUILD := 0
## `Qst_stdEmpty(3)` 的扫描区间：普通 NPC 任务。
const SLOT_FIRST_NORMAL := 1
const SLOT_LAST_NORMAL := 10

## `active_marker` 的取值（=`Qst_stdEmpty`／`Qst_stdSET` 的上下文）。
const CONTEXT_GUILD := 2
const CONTEXT_NPC := 3

## 完成位图能覆盖的最大任务号（7 字节 × 8 − 1）。
const COMPLETED_MAX := 55

const SLOT_KEYS := ["marker", "npc", "quest", "goal_kind", "goal_target", "goal_count", "progress"]

## 与 `progress["quests"]` 共用的那一份字典：`slots`（11 条，空槽是 `{}`）+ `completed`（升序）。
var data: Dictionary

var slots: Array:
	get:
		return data["slots"]
var completed_ids: Array:
	get:
		return data["completed"]


func _init(payload: Variant = null) -> void:
	if payload == null:
		data = empty_dict()
		return
	if not payload is Dictionary or not validate(payload):
		push_error("QuestLog: 任务槽数据损坏，拒绝载入")
		data = empty_dict()
		return
	data = payload


static func empty_dict() -> Dictionary:
	var rows: Array = []
	for _index in SLOT_COUNT:
		rows.append({})
	return {"slots": rows, "completed": []}


## 外部边界的唯一校验入口（存档、老档补齐都走这里）。
static func validate(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var rows: Variant = value.get("slots")
	if not rows is Array or rows.size() != SLOT_COUNT:
		return false
	var seen := {}
	for index in SLOT_COUNT:
		var slot: Variant = rows[index]
		if not slot is Dictionary:
			return false
		if slot.is_empty():
			continue
		for key: String in SLOT_KEYS:
			if not slot.get(key) is int:
				return false
		if slot["marker"] != (CONTEXT_GUILD if index == SLOT_GUILD else CONTEXT_NPC):
			return false
		if slot["quest"] < 0 or slot["quest"] > 255 or seen.has(slot["quest"]):
			return false
		seen[slot["quest"]] = true
		if slot["npc"] < 0 or slot["npc"] > 255:
			return false
		if slot["goal_kind"] < 0 or slot["goal_kind"] > QuestTable.GOAL_MATERIAL:
			return false
		if slot["goal_target"] < 0 or slot["goal_target"] > 65535:
			return false
		if slot["goal_count"] < 0 or slot["goal_count"] > 255:
			return false
	var done: Variant = value.get("completed")
	if not done is Array or done.size() > COMPLETED_MAX + 1:
		return false
	var previous := -1
	for entry: Variant in done:
		if not entry is int or entry < 0 or entry > COMPLETED_MAX or entry <= previous:
			return false
		previous = entry
	return true


func to_dict() -> Dictionary:
	return data


## `Qst_datFindINDEX`／`Qst_stdSET` 的槽内容：空槽返回 `{}`。
func slot_at(index: int) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT:
		push_error("QuestLog: 槽序号 %d 越界" % index)
		return {}
	return slots[index]


func slot_of(quest_id: int) -> int:
	for index in SLOT_COUNT:
		var slot: Dictionary = slots[index]
		if not slot.is_empty() and int(slot["quest"]) == quest_id:
			return index
	return -1


## 在册任务的遍历顺序照抄原生：`quests[1..10]` 之后才是 `quests[0]`
## （`Qst_stdFind`／`Qst_stdQuest` 的 `i == 10` 回绕）。
func active() -> Array[int]:
	var result: Array[int] = []
	for index in SLOT_COUNT:
		var order := (index + 1) % SLOT_COUNT
		var slot: Dictionary = slots[order]
		if not slot.is_empty():
			result.append(int(slot["quest"]))
	return result


func completed() -> Array[int]:
	var result: Array[int] = []
	for entry: int in completed_ids:
		result.append(entry)
	return result


func is_active(quest_id: int) -> bool:
	return slot_of(quest_id) >= 0


## `Qst_stdIsComplete`：完成位图，与「当前在册」无关，卖掉／放弃都不清除。
func is_completed(quest_id: int) -> bool:
	return quest_id >= 0 and quest_id <= COMPLETED_MAX and completed_ids.has(quest_id)


## `Qst_stdQuest` 的第一段：在册且 `npc_id` 相同的槽直接返回它的任务号。
func active_for(npc_id: int) -> int:
	for index in SLOT_COUNT:
		var slot: Dictionary = slots[index]
		if not slot.is_empty() and int(slot["npc"]) == npc_id:
			return int(slot["quest"])
	return -1


func progress_of(quest_id: int) -> int:
	var index := slot_of(quest_id)
	return 0 if index < 0 else int(slots[index]["progress"])


## 完成任务时要交出去的量（`Qst_stdRemove` 的 `a2 == 1` 分支按它扣精灵／素材）。
func goal_of(quest_id: int) -> Dictionary:
	var index := slot_of(quest_id)
	if index < 0:
		return {}
	var slot: Dictionary = slots[index]
	return {"kind": int(slot["goal_kind"]), "target": int(slot["goal_target"]),
		"count": int(slot["goal_count"])}


## 接取：按上下文分配区间（`Qst_stdEmpty` 模式 2／3），并把任务表里的
## `goal_kind`／`goal_target`／`goal_count` 抄进槽（原生 `Qst_stdSET` → `Qst_datFindINDEX` → `Qst_datGET`）。
func accept(table: QuestTable, quest_id: int, context: int = CONTEXT_NPC) -> bool:
	if context not in [CONTEXT_GUILD, CONTEXT_NPC]:
		push_error("QuestLog: 未知的接取上下文 %d" % context)
		return false
	if is_active(quest_id):
		return false
	var record := table.record(quest_id)
	if record.is_empty():
		return false
	if int(record["goal_kind"]) < QuestTable.GOAL_PROGRESS or \
			int(record["goal_kind"]) > QuestTable.GOAL_MATERIAL:
		push_error("QuestLog: 任务 %d 的 goal_kind 越界" % quest_id)
		return false
	var index := _free_slot(context)
	if index < 0:
		return false
	slots[index] = {"marker": context, "npc": int(record["npc"]), "quest": quest_id,
		"goal_kind": int(record["goal_kind"]), "goal_target": int(record["goal_target"]),
		"goal_count": int(record["goal_count"]), "progress": 0}
	return true


## 模式 2／3 的区间选择：公会任务只认槽 0，普通任务只认 1..10 的第一个空槽。
func _free_slot(context: int) -> int:
	if context == CONTEXT_GUILD:
		if not slots[SLOT_GUILD].is_empty():
			push_error("QuestLog: 公会任务槽已被占用")
			return -1
		return SLOT_GUILD
	for index in range(SLOT_FIRST_NORMAL, SLOT_LAST_NORMAL + 1):
		if slots[index].is_empty():
			return index
	push_error("QuestLog: %d 个普通任务槽已满" % (SLOT_LAST_NORMAL - SLOT_FIRST_NORMAL + 1))
	return -1


## `Qst_stdCHECK`：`goal_kind` 0 时把 `progress_value` 加满到 `goal_count`；
## 1／2 原生现场数背包（`Ball_bagFindCount`／`Item_fndCount`），`amount` 就是那个现数，
## **不写回 `progress_value`**。返回每个真正推进过的槽
## `{"quest": 任务号, "count": 显示数, "goal": 目标数, "reached": 是否达标}`（原生 `v31` → `Qst_icoSET`，
## 不自动完成）。未推进的槽不返回，也不该提示：
##   • 0：已到 `goal_count` 的槽直接跳过（`Qst_stdCHECK@0x94004:111-113`）；
##   • 1：现数为 0 或超过目标时跳过（`:50`、`:99-100`）；
##   • 2：现数为 0 时跳过（`:57`、`:106-107`）。
## 显示数夹到 `goal_count`（原生 `v33 >= 目标` 时取目标值）。
func advance(goal_kind: int, target: int, amount: int = 1) -> Array[Dictionary]:
	if goal_kind < QuestTable.GOAL_PROGRESS or goal_kind > QuestTable.GOAL_MATERIAL:
		push_error("QuestLog: 未知的 goal_kind %d" % goal_kind)
		return []
	if amount < 0:
		push_error("QuestLog: 进度增量不能为负（%d）" % amount)
		return []
	var reports: Array[Dictionary] = []
	for index in SLOT_COUNT:
		var slot: Dictionary = slots[index]
		if slot.is_empty() or int(slot["goal_kind"]) != goal_kind or \
				int(slot["goal_target"]) != target:
			continue
		var goal := int(slot["goal_count"])
		var count := amount
		if goal_kind == QuestTable.GOAL_PROGRESS:
			if int(slot["progress"]) >= goal:
				continue
			slot["progress"] = mini(int(slot["progress"]) + amount, goal)
			count = int(slot["progress"])
		elif count <= 0 or (goal_kind == QuestTable.GOAL_MONSTER and count > goal):
			continue
		reports.append({"quest": int(slot["quest"]), "count": mini(count, goal), "goal": goal,
			"reached": count >= goal})
	return reports


## `Qst_stdComplete`：置完成位后调 `Qst_stdRemove`（`a2 = 1` 顺手清槽）。
func complete(quest_id: int) -> bool:
	if not is_active(quest_id):
		return false
	if quest_id < 0 or quest_id > COMPLETED_MAX:
		push_error("QuestLog: 任务号 %d 超出完成位图范围" % quest_id)
		return false
	if not completed_ids.has(quest_id):
		completed_ids.append(quest_id)
		completed_ids.sort()
	return remove(quest_id)


## `Qst_stdRemove`：清槽后把后面的普通槽往前压实（槽 0 不动）。
func remove(quest_id: int) -> bool:
	var index := slot_of(quest_id)
	if index < 0:
		return false
	slots[index] = {}
	if index >= SLOT_FIRST_NORMAL:
		for move in range(index, SLOT_LAST_NORMAL):
			slots[move] = slots[move + 1]
		slots[SLOT_LAST_NORMAL] = {}
	return true


## `Qst_stdQuest` 的完整语义：在册优先，否则按 NPC 的任务链判定，返回 -1 表示没任务。
func offered(table: QuestTable, npc_id: int, context: Dictionary) -> int:
	var active_quest := active_for(npc_id)
	if active_quest >= 0:
		return active_quest
	var record := _chain_head(table, npc_id)
	if record.is_empty() or not _eligible(record, context):
		return -1
	return int(record["id"])


## `Qst_stdQuest` 的表判定部分：这个 NPC 现在能给你的任务（链头，0 或 1 条）。
## 原生只评估**第一个**「可重复或未完成」的记录，它不满足条件就整条链都不给，不再往后找。
func available(table: QuestTable, npc_id: int, context: Dictionary) -> Array[int]:
	var record := _chain_head(table, npc_id)
	if record.is_empty() or not _eligible(record, context):
		return []
	return [int(record["id"])]


## `Qst_icoGET` 的 0/2/3/4。原生的返回式是
## `(held >= goal) + (held >> 31) + 3`：负进度时 `>> 31 == -1`，结果压成 **2**（可接）。
## 正常流程 `progress_value` 只增不减（`Qst_stdCHECK` 上界是 goal），负值只可能来自手改存档，
## 这里照这个兜底。码 5（事件任务）要求 `EvtData.step_kind == 4 且 item_condition_parameter == npc`，
## 工程还没有事件步类型建模，**不是静默返回 0**，而是没有入口。
## `counts` 用于 `goal_kind` 1／2 的现场清点（任务号 → 当前持有量），0 走 `progress_value`。
func status(table: QuestTable, npc_id: int, context: Dictionary, counts: Dictionary = {}) -> int:
	# `Qst_icoGET:19-45`：先扫普通槽 1..10，最后才扫公会槽 0；同一 NPC 同时挂在两类槽时，
	# 原版显示普通任务的状态，公会槽不抢先。
	var order: Array[int] = []
	for index in range(SLOT_FIRST_NORMAL, SLOT_LAST_NORMAL + 1):
		order.append(index)
	order.append(SLOT_GUILD)
	for index: int in order:
		var slot: Dictionary = slots[index]
		if slot.is_empty() or int(slot["npc"]) != npc_id:
			continue
		var quest_id := int(slot["quest"])
		var count := int(slot["progress"])
		if int(slot["goal_kind"]) != QuestTable.GOAL_PROGRESS:
			count = int(counts.get(quest_id, 0))
		if count < 0:
			return 2
		return 4 if count >= int(slot["goal_count"]) else 3
	var record := _chain_head(table, npc_id)
	if record.is_empty() or not _eligible(record, context):
		return 0
	return 2


## `Qst_stdNPC`：该 NPC 是否还有没完成的任务（公会页用它决定挑战／提示）。
func npc_pending(table: QuestTable, npc_id: int) -> bool:
	for entry: Dictionary in table.entries:
		if int(entry.get("npc", -1)) == npc_id and not is_completed(int(entry.get("id", -1))):
			return true
	return false


## `Qst_datFindNPC` 的遍历：按表内顺序取该 NPC 的第一条「可重复或未完成」记录。
func _chain_head(table: QuestTable, npc_id: int) -> Dictionary:
	for entry: Dictionary in table.entries:
		if int(entry.get("npc", -1)) != npc_id:
			continue
		if int(entry.get("repeatable", 0)) != 0 or not is_completed(int(entry.get("id", -1))):
			return entry
	return {}


## 前置／公会档／事件号三组比较，逐字对应 `Qst_stdQuest` 的 LABEL_14 到返回处。
func _eligible(record: Dictionary, context: Dictionary) -> bool:
	if not context.has("guild_code") or not context.has("event_id"):
		push_error("QuestLog: 判定上下文缺少 guild_code／event_id")
		return false
	for pair: Array in [["prereq_kind", "prereq_quest"], ["prereq2_kind", "prereq2_quest"]]:
		var kind := int(record.get(pair[0], 0))
		var other := int(record.get(pair[1], 0))
		if kind == QuestTable.PREREQ_ACCEPTED:
			if not is_completed(other) and not is_active(other):
				return false
		elif kind == QuestTable.PREREQ_COMPLETED:
			if not is_completed(other):
				return false
	var rank := int(record.get("guild_rank", 0))
	if rank != 0 and int(context["guild_code"]) > rank:
		return false
	var event_id := int(context["event_id"]) % 1000
	var low := int(record.get("event_low", 0))
	var high := int(record.get("event_high", 0))
	if low >= high:
		return event_id >= low
	return event_id >= low and event_id <= high
