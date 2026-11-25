extends "res://game/battle/presentation/result/result.gd"

## 原生 `Field_Quest_Complete_*`（`FieldCanvas` 状态 11，任务结算）：
## `Field_Quest_Complete_init`（清 `online_battle_monsters` → `SetResult(quest_id)` →
## 载 `common/ui_window.fbm`），之后整页由战斗结算窗画：`paint = Battle_Win_mPaint`、
## `run = Battle_Win_mRun`、`key = Battle_Win_mKeyPressed`（窗口 228×240）。
##
## 所以本页直接继承 `battle_ui/result.tscn`／`result.gd`：几何、经验条、金钱带、掉落行与
## 开窗／发奖／确认三段子状态全部复用，只把数值来源换成 `QuestReward`（任务记录）。
## 标题 `Battle_Win_Draw` 取 `JC_fxt2Return(13)`［战斗结果］，`GameState == GAME_STATE_FIELD`
## （事件战）时取 14［任务结束］；任务页没有对方的 `GameState` 镜像，由调用方传 `title_id`。

## 交任务时的发奖载荷：`rewarded` 带的是 `QuestReward`（`battle_ui/result.gd` 的 `settlement`），
## 宿主用 `Story.grant_quest_reward(model)` 入账。
signal rewarded(quest_id: int, model: RefCounted)

const QuestReward = preload("res://game/field/quests/quest_reward/quest_reward.gd")
const Presentation = preload("res://game/battle/presentation/presentation.gd")

## `common/msg.fxt:14`［任务结束］。
const MESSAGE_QUEST_END := 14

var quest_id := -1


## `Battle_Win_mKeyPressed` 只认确认键（子状态 1 快进、2 离开）；任务页在本移植里给 CLR
## 一个「直接返回」的语义（不等发奖动画跑完），免得玩家卡在只有一个键的窗口里。
func handle_key(key: String) -> void:
	if key in ["Escape", "Backspace", "Cancel"]:
		if stage in ["closed", "opening"]:
			return
		stage = "closed"
		finished.emit()
		return
	super(key)


## `log` 是 `story.quest_log()`。原生 `Qst_stdFind` 命中才发奖，所以任务不在册时什么也不做。
func present_quest(assets: Node, table: QuestTable, log: QuestLog, id: int,
		progress: Dictionary, title_id: int = MESSAGE_QUEST_END) -> bool:
	if not log.is_active(id):
		push_error("任务 %d 不在册，完成页没有奖励可发。" % id)
		return false
	var record := table.record(id)
	if record.is_empty():
		return false
	var model: RefCounted = QuestReward.new(record, progress)
	if not open(model, Presentation.new(assets), progress, title_id):
		return false
	quest_id = id
	# `Field_Quest_Complete_SetResult` 末尾的 `Qst_stdComplete(quest_id)`：置完成位并清槽。
	log.complete(id)
	rewarded.emit(id, model)
	return true
