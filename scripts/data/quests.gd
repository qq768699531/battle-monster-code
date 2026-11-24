extends Resource
class_name QuestTable
## 原生任务表（`assets/assets/qst/qstlist.sub`，由 `script/parse_qstlist.py` 生成）。
##
## `Qst_Load` 只是把整份文件读进 `QstRes.quest_list_resource`，真正的解析散在三处：
## `Qst_datFindINDEX`（按任务号找记录）、`Qst_datFindNPC`（按 NPC 枚举它提供的
## 任务）、`Qst_datGET`（读 21 字节块里的 20 字节字段）。格式不是定长表：
## int32 记录条数 + 每条 NPC 记录的绝对偏移，记录 = `npc_id` 1 字节 + `quest_count` uint16 +
## `quest_count` 个 21 字节块（块首是任务号，其后 20 字节按 `Qst_datGET` 的读序）。
## 字段偏移与语义见 `parse_qstlist.py` 的常量表；任务正文不在本文件，`Qst_stdSET`
## 按任务号去 `qst/qstlist.fxt` 取（`JC_fxtCOPY(RES, quest_id)`）。
##
## 一条记录一个任务号（任务号 0–54，按 NPC 分组，同一 NPC 按数据顺序给出任务链）。
@export var entries: Array[Dictionary] = []

## `goal_kind` 的取值（`Qst_stdCHECK`／`Qst_stdQuest` 的 `quest_id + 9`）。
const GOAL_PROGRESS := 0
const GOAL_MONSTER := 1
const GOAL_MATERIAL := 2

## `prereq_kind`／`prereq2_kind` 的取值：1 = 已接或已完成，2 = 必须已完成。
const PREREQ_ACCEPTED := 1
const PREREQ_COMPLETED := 2

var _index: Dictionary = {}


func size() -> int:
	return entries.size()


## 按任务号取一条只读记录；越界返回空表（外部边界集中校验，不在此处兜底未知 id）。
func record(id: int) -> Dictionary:
	if _index.size() != entries.size():
		for entry in entries:
			_index[int(entry.get("id", -1))] = entry
	var found: Variant = _index.get(id)
	if not found is Dictionary:
		push_error("QuestTable: 任务 %d 不在表内" % id)
		return {}
	return found


## 该任务的要求是否按「累计进度」判定（`Qst_stdCHECK` 读 `progress_value`），
## 而不是清点背包里的精灵／素材。
func tracks_progress(id: int) -> bool:
	return int(record(id).get("goal_kind", GOAL_PROGRESS)) == GOAL_PROGRESS
