extends "res://field/quest_detail/quest_detail.gd"

## 原生 `FieldCanvas` 状态 8（`FIELD_STATE_GUILD_QUEST_DETAIL`）——公会任务页。
##
## 这一页**没有列表**：`Field_Guild_List_mKeyPressed` 的 `case 1`（`msg 52` 公会任务）
## 先 `Qst_stdQuest(npc)` 取任务号，取到才 `Qst_chtINIT(QstData = 2, quest_id)`
## ＋ `FieldCanvas_SetNext(FIELD_STATE_GUILD_QUEST_DETAIL, 0)`。状态 8 自己只 `Map_Copy()` 清屏
## （`Field_Guild_Quest_Detail_init` 载 `common/ui_window.fbm` 并开窗计数置 1，
## `mPaint` 只 `Map_Copy`，`mKeyPressed` 是空函数），窗口与输入全交给
## `GameCanvas` 层的 `Qst_chtDRAW`／`Qst_chtRUN`／`Qst_chtKeyPress`。
##
## 所以本页直接继承 `field/quest_detail.tscn`／`quest_detail.gd`：`qstlist.fxt` 的六段正文、
## 目标行 `0/` 进度替换、接受确认框与「槽满 → `msg 512`」全部复用，本文件只补两件事：
##
## 1. `present_for_npc()` 按公会 NPC 取任务号（`Qst_stdQuest` 的完整语义——在册优先，
##    否则链头记录过前置／档位／事件号三关——已落在 `QuestLog.offered()`），取到就以
##    `QuestLog.CONTEXT_GUILD`（原生 `Qst_chtINIT` 的实参 2）打开，接受即写**专用槽 0**
##    （`Qst_stdEmpty` 模式 2）。
## 2. 取不到任务号时照抄 `Field_Guild_List_mKeyPressed` 的三分支拒绝提示：
##    `guild_code <= 1` → `msg 49`「最高公会排名」；该 NPC 还有未完成任务
##    （`Qst_stdNPC`）→ `msg 47`「可接受公会排名%d以上」，`%d` 是那条记录的档位要求；
##    否则 `msg 48`「没有任务了」。原生走 `Game_infoInit(-1, 正文)` 的野外信息行、不进状态 8，
##    所以这里同样不建窗口，只把记录号与正文交给宿主。
##
## 公会 NPC id 的取证：`Field_Guild_List_mKeyPressed` 里的实参是
## `*(_DWORD *)(*(&ObjData.extended_state_capacity + 2) + 4)`。`ObjData + 2424` 那个全局是
## `Field_Basic_mRun` 每帧用 `Object_objNEAR(n2: 3, 900)` 写下的「当前交互 NPC 对象」，
## `+4` 是该对象的 `resource_id`（`RuntimeObjectType` 的偏移表：0 `object_kind`、4 `resource_id`）。
## 也就是说 NPC id 来自**玩家面前那只 NPC 自己的 id**，本页不自带默认值，由宿主以参数传入。

## 拒绝提示的记录号（原生 `JC_fxt2Return` 的实参）；`-1` 表示本次取到了任务、窗口已打开。
## 同一条提示的正文（`msg 47` 已代入档位要求）；空串表示有任务。
var notice := ""
## 本次查询的公会 NPC id（`Qst_stdQuest` 的实参）。
var npc_id := -1
## `msg 47` 代入的档位要求，即待接任务记录的 `guild_rank`。
var pending_rank := 0


## `context` 必须带 `guild_code`／`event_id`（宿主 `_quest_context()` 的两个量，
## 对应 `ParamData.guild_code_bits` 与 `current_event_resource_id % 1000`）。
## `counts` 是 `goal_kind` 1／2 的现场清点，透传给详情页的目标行。
## 返回 false 表示该 NPC 现在没有可接任务，此时读 `notice_id`／`notice`。
func present_for_npc(assets: Node, table: QuestTable, log: QuestLog, guild_npc_id: int,
		context: Dictionary, counts: Dictionary = {}) -> bool:
	npc_id = guild_npc_id
	notice_id = -1
	notice = ""
	pending_rank = 0
	var ordered := log.offered(table, guild_npc_id, context)
	if ordered >= 0:
		return present(assets, table, log, ordered, QuestLog.CONTEXT_GUILD, counts)
	notice_id = _refusal(table, log, context)
	notice = assets.text_message(Msg.SOURCE, notice_id)
	if notice_id == Msg.Id.GUILD_QUEST_RANK:
		notice = notice % pending_rank
	return false


## `Field_Guild_List_mKeyPressed` 的 `case 1` 拒绝分支，判序与常量一致。
func _refusal(table: QuestTable, log: QuestLog, context: Dictionary) -> int:
	if int(context.get("guild_code", 0)) <= 1:
		return Msg.Id.GUILD_QUEST_TOP
	var pending := _pending_record(table, log)
	if pending.is_empty():
		return Msg.Id.GUILD_QUEST_NONE
	pending_rank = int(pending.get("guild_rank", 0))
	return Msg.Id.GUILD_QUEST_RANK


## `Qst_stdNPC`：按表内顺序取该 NPC 第一条未完成的记录（原生用它取 `msg 47` 的档位）。
func _pending_record(table: QuestTable, log: QuestLog) -> Dictionary:
	for entry: Dictionary in table.entries:
		if int(entry.get("npc", -1)) != npc_id:
			continue
		if log.is_completed(int(entry.get("id", -1))):
			continue
		return entry
	return {}
