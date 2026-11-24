extends Resource
## 原生战斗 ANI 每帧的「本体定位指令」。
##
## 战斗怪物（kind 12）的 `decode_frame_callback_address` 是 `Battle_Monster_procPosition`
## （由 `Mon_Link` 写进 `ObjLink[207 + species]`），每帧读 frame 层 0 的两个附加字节
## （旧解析里叫 `unknown_x`／`unknown_y`）：
##   form = `unknown_y`：1 = 相对受击者、2 = 固定槽（`Battle_objGetPosition(7／2, …, a4 = 20)`）、
##                       0 = 不动——伪代码在 `layer_count != 0` 的分支里对 form 0 直接 `return`，
##                       **不调 `Object_objPOS`**，所以该帧沿用上一次写入的落点；
##   code = `unknown_x`：form 1 时 0 → `a4 = 160`（≈ 自己那一列，原地打）、1 → `a4 = 17`（贴到受击者身前）、
##                       2 → `a4 = 0`（压在受击者身上）。
## 落点写进 `Object_objPOS(本体, 受击者槽 x ± a4, 受击者槽 y + 1, 0, -1)`，
## 其中“我方槽取 `x − a4`、敌方槽取 `x + a4`”。
##
## 212 份 `assets\assets\mon2\*.ani` 实测：动作 0–2 全是 form 0；动作 3（攻击）210/212 是 form 1、
## 其中 code 1（贴脸）只有 22 份，其余 code 0（原地）；动作 4（技能）181 份、动作 5／6（分身）同理。
## 由 `script\export_battle_poses.py` 生成，动作号是 ANI 动作下标（3 = `animation_id` 14 攻击）。
@export var poses: Dictionary = {}


## `Battle_Monster_procPosition` 从 frame 附加字节读到的 form（`unknown_y`）。
## `NONE` 不是「回编队槽」，而是「本帧不写坐标、沿用上一次落点」。
enum Form { NONE, TARGET, SLOT }


## 该 ANI 动作第 `frame` 帧生效的指令 `Vector2i(form, code)`；没有指令返回 `(0, 0)`。
##
## 变化点是 `[帧号, form, code]` 三元组。form 0 的变化点按原生语义**不写坐标**（见文件头），
## 跳过它、继续沿用上一条非零 form 的指令——把它当成 `(0, 0)` 会让本体瞬回编队槽。
func command(identity: String, action: int, frame: int) -> Vector2i:
	var by_action: Dictionary = poses.get(identity, {})
	var current := Vector2i.ZERO
	for change: Array in by_action.get(action, []):
		if int(change[0]) > frame:
			break
		if int(change[1]) == Form.NONE:
			continue
		current = Vector2i(int(change[1]), int(change[2]))
	return current
