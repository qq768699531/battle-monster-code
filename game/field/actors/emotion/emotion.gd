extends Node2D
## 头顶叠加层：说话气泡（18 帧循环）、显式表情（优先）、任务图标与 NPC 名字条。
## 任务图标来自 `Field_Emoticon_procDraw`：原生按 NPC 对象最后那个任务码画
## `obj/f_emoticon` 的动作 11／13／12，绘制点与气泡同一个（根节点的 `position = (0, -50)`
## 就是 kind 3 的 `n40 = 50`；怪物走 `use_monster_anchor()` 换成 40）。
## 越过屏幕上边时**不夹取**：原生把 `(x, y − n40)` 直接交给 `Object_drawBASIC`，
## `Object_procDRAW` 只按身体 `draw_bounds` 剔除对象；`Map_posCENTER` 让地图顶端贴屏幕顶，
## 越界部分就由 400×240 帧缓冲裁掉。所以这里不改 Scene 的 `position`，也不要为了
## 「完整显示」把表情夹进屏幕——那会偏离原版。
## 名字条（同一函数的「当前面向对象」分支）：对象 `+264` 相位 1→4 展开、离场 −1→−3 收起；
## 相位 4 是 24 px 高、3／−1 是 12 px、其余 16 px，位置 `(x − 宽/2, y − 53／−55／−59)`。
## 它和气泡／显式表情／任务图标是同一个对象上的互斥分支：对话窗一开走气泡、显式表情优先，
## 只有「当前面向对象 + 消息窗关着」才画名字条并让任务图标让位。

## NPC 头顶任务图标码（`Qst_icoGET` 的返回，`Qst_icoSET` 写进对象 +275）的枚举
## 只有一份：`scripts/data/quest_mark.gd`（HUD 色块也按它选色，生产端同样是 `field_runtime`
## 写进 actor 的 `quest_status`）。0 是「无」，1 原生不产出、与 0 一样不画。
const QuestMark = preload("res://game/field/quests/quest_mark/quest_mark.gd")

@onready var _talking: Node2D = $Talking
@onready var _scripted: Node2D = $Scripted
@onready var _quest: Node2D = $Quest
@onready var _animation: AnimationPlayer = $AnimationPlayer
@onready var _name_plate: Panel = $NamePlate
@onready var _name_label: Label = $NamePlate/Name
var _request: Variant = null
var _quest_action := -1
var _actor: Dictionary = {}
var _name_text := ""
var _name_phase := 0
var _name_wanted := false


func _ready() -> void:
	hide()
	_talking.visible = false
	_name_plate.visible = false
	_scripted.set_manual(true)
	_quest.set_manual(true)
	_scripted.animation_finished.connect(_finish_explicit)


func use_monster_anchor() -> void:
	position += $MonsterOffset.position


func clear_layers() -> void:
	_request = null
	_quest_action = -1
	_name_wanted = false
	_name_phase = 0
	_name_plate.visible = false
	_clear_emote_layers()
	hide()


## 收起气泡／显式表情／任务图标三层，但保留根节点与名字条（名字条是同一对象上的独立层）。
func _clear_emote_layers() -> void:
	_talking.visible = false
	_scripted.visible = false
	_animation.stop()
	_scripted.clear()
	_quest.clear()
	_quest.visible = false


func present(actor: Dictionary, speaking: bool, report: Callable, facing := false,
		name_text := "") -> void:
	_actor = actor
	_name_text = name_text
	var explicit := actor.get("emotion") != null
	# 名字条只在「当前面向对象」、且没有显式表情、也没有打开对话时画（消息窗一开，
	# `Field_Emoticon_procDraw` 走气泡分支；名字条那条分支要求 `EvtRes.dialog.page+216 == 0`）。
	_set_name_wanted(facing and not speaking and not explicit and not name_text.is_empty())
	_present_layers(actor, speaking, explicit, report)
	# 原生先画面部表情再画名字条／任务图标：显式表情进行中、该 NPC 正是当前对话对象
	# （`Field_Basic_Chat` 打开对话时直接把任务码清 0）、或改画名字条时都不画任务图标。
	_sync_quest(actor, not explicit and not speaking and not facing, report)


func _present_layers(actor: Dictionary, speaking: bool, explicit: bool, report: Callable) -> void:
	var request: Variant = [actor.emotion, actor.get("emotionRevision", 0)] if explicit \
		else ["dialogue"] if speaking else null
	if request == _request:
		return
	_request = request
	if request == null:
		_clear_emote_layers()
		if not _name_wanted:
			hide()
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
		if _request == null and not _name_plate.visible:
			hide()
		return
	show()
	if not _quest.present("obj/f_emoticon", action, 0, true):
		report.call(_quest.last_error)
		_quest.visible = false
		_quest_action = -1


func advance(delta: float) -> void:
	_advance_name_plate()
	if not visible:
		return
	if _talking.visible:
		_animation.advance(delta)
	else:
		_scripted.advance(delta)
		_actor["emotionFrame"] = _scripted.frame_index()
	if _quest.visible:
		_quest.advance(delta)


## 名字条相位推进：面向时 1→4 展开、离开时 −1→−3 收起（原生 `+264 += sign(+264)`）。
func _advance_name_plate() -> void:
	if _name_phase > 0 and _name_phase < 4:
		_name_phase += 1
	elif _name_phase < 0 and _name_phase > -4:
		_name_phase -= 1
	_apply_name_plate()
	if _name_phase <= -4 and not _name_wanted and not _talking.visible and \
			not _scripted.visible and not _quest.visible:
		hide()


func _set_name_wanted(wanted: bool) -> void:
	_name_wanted = wanted
	if wanted:
		show()
		if _name_phase <= 0:
			_name_phase = 1
	elif _name_phase > 0:
		_name_phase = -1
	_apply_name_plate()


## 相位 1／2／−2／−3 → 16 px 高、3／−1 → 12 px、4 → 24 px（`Field_Emoticon_procDraw` 的三种
## `Menu_win_Box2_Draw` 高度）；相位 1 与 −3 用 alpha 128。
func _apply_name_plate() -> void:
	var shown := _name_phase != 0 and _name_phase > -4 and not _name_text.is_empty()
	_name_plate.visible = shown
	if not shown:
		return
	var height := 24 if _name_phase >= 4 else 12 if _name_phase == 3 or _name_phase == -1 else 16
	var top := -9.0 if height == 24 else -3.0 if height == 12 else -5.0
	var width := 24
	var font := _name_label.get_theme_font("font")
	if font != null:
		width = maxi(width, ceili(font.get_string_size(_name_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, _name_label.get_theme_font_size("font_size")).x) + 10)
	_name_label.text = _name_text
	_name_plate.size = Vector2(width, height)
	_name_plate.position = Vector2(-width / 2.0, top)
	_name_plate.modulate.a = 0.5 if _name_phase == 1 or _name_phase == -3 else 1.0


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
	if _name_plate.visible:
		return {"name_plate": true}
	return {}
