extends Node2D
## 原生命中特效：`Param_dmgBASIC` 在受击处新建 kind 14 对象。
## 命中扣血时播 `obj/b_effect` 的 action 0（一般）／1（暴击），伤害取整为 0 时播
## action 39（MISS 闪光，4 帧）。这三条动作只有图层、没有代码绘制，按帧播 ANI 即可。

## 原生 `Param_activeDraw` 的 MISS 分支固定使用动作 39。
const MISS_ACTION := AniAction.Effect.MISS
## 暴击用动作 1，一般用动作 0（`Param_dmgBASIC` 按暴击倍率是否非 0 选择）。
const CRITICAL_ACTION := AniAction.Effect.CRITICAL
const DAMAGE_ACTION := AniAction.Effect.HIT
## 捕获结果的两个动作（`Battle_Capture_Action_mRun` 子状态 3／2 的第 0 帧）：
## 成功 37、失败 38，都属于 `obj/b_effect`。本工程只播成功那条。
const CAPTURE_ACTION := 37
## 复活：`Battle_Die_mKeyPressed` 子状态 4／8 对每只复活对象补一次
## `Param_atkEFFECT(obj.x, obj.y, 1, 29, 0)`，动作 29 同属 `obj/b_effect`。
const REVIVE_ACTION := AniAction.Effect.REVIVE
## 战斗内道具的回复闪光：`Battle_Target_mKeyPressed` 按 `Ball_stdUse` 的返回码选
## 27（HP）／28（SP），HP＋SP 时两个都建。
const ITEM_HP_ACTION := AniAction.Effect.ITEM_HP
const ITEM_SP_ACTION := AniAction.Effect.ITEM_SP
## `Param_atkEFFECT`：特效对象落在 `victim.x ± 36`（`direction_code == 2` 敌方取 −36、
## 我方取 +36）、`victim.y + 4`（动作 0／1／39 在 `CSWTCH.95_0` 都取默认 4）。
## 这 ±36 抵消 `b_effect` 图集重心偏在原点右侧，所以绘制重心仍在受击者身上。
const OFFSET_X := 36.0
const OFFSET_Y := 4.0

@onready var _flash: Node2D = $Flash

## 最近一次播放的动作号，供回归断言使用。
var action := -1


func present(effect_action: int, direction: int) -> void:
	action = effect_action
	visible = true
	if _flash.present("obj/b_effect", effect_action, direction, false):
		_flash.restart()
	else:
		visible = false


func _ready() -> void:
	_flash.animation_finished.connect(func(): visible = false)
	visible = false
