extends Node2D
## 头顶叠加层：说话气泡（18 帧循环）、显式表情（优先）与任务图标。
## 任务图标来自 `Field_Emoticon_procDraw`：原生按 NPC 对象最后那个任务码画
## `obj/f_emoticon` 的动作 11／13／12，绘制点与气泡同一个（根节点的 `position = (0, -50)`
## 就是 kind 3 的 `n40 = 50`；怪物走 `use_monster_anchor()` 换成 40）。

## NPC 头顶任务图标码（`Qst_icoGET` 的返回，`Qst_icoSET` 写进对象 +275）的枚举
## 只有一份：`scripts/data/quest_mark.gd`（HUD 色块也按它选色，生产端同样是 `field_runtime`
## 写进 actor 的 `quest_status`）。0 是「无」，1 原生不产出、与 0 一样不画。
const QuestMark = preload("res://data/quest_mark/quest_mark.gd")

@onready var _talking: Node2D = $Talking
@onready var _scripted: Node2D = $Scripted
@onready var _quest: Node2D = $Quest
@onready var _animation: AnimationPlayer = $AnimationPlayer
var _request: Variant = null
var _quest_action := -1
var _actor: Dictionary = {}


func _ready() -> void:
	hide()
	_talking.visible = false
	_scripted.set_manual(true)
	_quest.set_manual(true)
	_scripted.animation_finished.connect(_finish_explicit)


func use_monster_anchor() -> void:
	position += $MonsterOffset.position


func clear_layers() -> void:
	hide()
	_request = null
	_quest_action = -1
	_talking.visible = false
	_scripted.visible = false
	_animation.stop()
	_scripted.clear()
	_quest.clear()
	_quest.visible = false


func present(actor: Dictionary, speaking: bool, report: Callable) -> void:
	_actor = actor
	var explicit := actor.get("emotion") != null
	_present_layers(actor, speaking, explicit, report)
	# 原生先画面部表情再画名字条／任务图标：显式表情进行中，以及该 NPC 正是当前对话对象
	# （`Field_Emoticon_procDraw` 对它改画名字条；`Field_Basic_Chat` 打开对话时
	# 直接把任务码清 0）都不画任务图标。
	_sync_quest(actor, not explicit and not speaking, report)


func _present_layers(actor: Dictionary, speaking: bool, explicit: bool, report: Callable) -> void:
	var request: Variant = [actor.emotion, actor.get("emotionRevision", 0)] if explicit \
		else ["dialogue"] if speaking else null
	if request == _request:
		return
	_request = request
	if request == null:
		clear_layers()
		return
	show()
	_talking.visible = not explicit
	_scripted.visible = explicit
	if explicit:
		_animation.stop()
		if not _scripted.present("obj/f_emoticon", int(actor.emotion), 0, false):
			report.call(_scripted.last_error)
			hide()
			return
		_scripted.restart()
		_scripted.seek_frame(int(actor.get("emotionFrame", 0)))
	else:
		_scripted.clear()
		_animation.play(&"talk")
		_animation.advance(0.0)


## 任务图标码 → `obj/f_emoticon` 动作号；0／1 与未知值不画（返回 −1）。
static func quest_action(status: int) -> int:
	if status == QuestMark.Code.ACCEPTABLE:
		return AniAction.Emoticon.QUEST_AVAILABLE
	if status == QuestMark.Code.IN_PROGRESS:
		return AniAction.Emoticon.QUEST_IN_PROGRESS
	if status == QuestMark.Code.GOAL_REACHED or status == QuestMark.Code.EVENT:
		return AniAction.Emoticon.QUEST_COMPLETED
	return -1


func _sync_quest(actor: Dictionary, allowed: bool, report: Callable) -> void:
	var action := quest_action(int(actor.get("quest_status", QuestMark.Code.NONE))) if allowed else -1
	if action == _quest_action:
		return
	_quest_action = action
	_quest.visible = action >= 0
	if action < 0:
		_quest.clear()
		if _request == null:
			hide()
		return
	show()
	if not _quest.present("obj/f_emoticon", action, 0, true):
		report.call(_quest.last_error)
		_quest.visible = false
		_quest_action = -1


func advance(delta: float) -> void:
	if not visible:
		return
	if _talking.visible:
		_animation.advance(delta)
	else:
		_scripted.advance(delta)
		_actor["emotionFrame"] = _scripted.frame_index()
	if _quest.visible:
		_quest.advance(delta)


func _finish_explicit() -> void:
	_actor["emotionFrame"] = 0
	_actor["emotionRepeats"] = int(_actor.get("emotionRepeats", 1)) - 1
	if _actor.emotionRepeats > 0:
		_scripted.restart()
	else:
		_actor["emotion"] = null


func drawing() -> Dictionary:
	if not visible:
		return {}
	if _talking.visible:
		var clip := _animation.get_animation(&"talk")
		return {"path": "obj/f_emoticon", "action": 0, "frames": clip.get_meta("frame_count"),
			"frame": floori(_animation.current_animation_position / clip.length *
				int(clip.get_meta("frame_count")))}
	if _scripted.visible:
		return {"path": "obj/f_emoticon", "action": _scripted.playback_state().action,
			"frames": _scripted.frame_count(_scripted.playback_state().action),
			"frame": _scripted.frame_index()}
	if _quest.visible:
		return {"path": "obj/f_emoticon", "action": _quest_action,
			"frames": _quest.frame_count(_quest_action), "frame": _quest.frame_index()}
	return {}

