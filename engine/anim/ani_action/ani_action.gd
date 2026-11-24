extends RefCounted
class_name AniAction
## ANI 动作号与原生 `animation_id` 的语义名。
##
## 原生 ANI 不存动作名（`wiki\data-format\ani.md`），只能按数组下标寻址。这里的枚举来自反编译
## 代码里能查到的映射，和导出片段名用的 `script\ani_actions.py` 一一对应；没有证据的
## 动作号（例如战斗动作 2）不登记，按数字照旧使用。

## 战斗怪物 `mon2` 的 ANI 动作号（`Battle_Monster_procAction` 的输出）。
enum Clip {
	IDLE = 0,       ## animation_id 0／19：待机
	DAMAGED = 1,    ## animation_id 12：受击
	ATTACK = 3,     ## animation_id 14：攻击
	SKILL = 4,      ## animation_id 15：技能
	CLONE_A = 5,    ## animation_id 20：分身动作 A
	CLONE_B = 6,    ## animation_id 21：分身动作 B
}

## 原生 `Battle_Monster` 的 `animation_id`（对象 +92 的字段）。
enum AnimationId {
	IDLE = 0,
	DAMAGED = 12,
	EFFECT = 13,    ## → ANI 动作 2，含义未确认，故未命名
	ATTACK = 14,
	SKILL = 15,
	RETURN = 19,    ## 播完回待机
	CLONE_A = 20,
	CLONE_B = 21,
}

## 命中原生命中 `obj/b_effect` 的动作号（`Param_dmgBASIC`）。
enum Effect {
	HIT = 0,
	CRITICAL = 1,
	ITEM_HP = 27,   ## 道具回复 HP（`Battle_Target_mKeyPressed` 的返回码 1／15／16／17）
	ITEM_SP = 28,   ## 道具回复 SP（返回码 3；HP＋SP 时连着建 28 与 27 两个对象）
	REVIVE = 29,    ## `Battle_Die_mKeyPressed` 复活时补的 `Param_atkEFFECT(..., 29, ...)`
	MISS = 39,      ## `Param_activeDraw` 的 MISS 分支固定用 39
}

## 指令图标／目标光标 `obj/b_icon2` 的动作号。
enum Icon {
	IDLE = 0,
	CURSOR_APPEAR = 11,
	CURSOR_LOOP = 12,
	CURSOR_CONFIRM = 13,
}

## 野外怪物 `mon1/m_f_*` 的三个朝向动作（`field_actors.field_artwork` 按 `lastDirection` 选）。
enum FieldMonster {
	DOWN = 0,
	UP = 1,
	SIDE = 2,
}

## 野外 NPC 头顶任务图标 `obj/f_emoticon` 的动作号（`Field_Emoticon_procDraw`）：
## `Qst_icoGET` 的码 2 → `animation_id` 1011、3 → 1013、4／5 → 1012，
## `Object_drawBASIC` 只取 `% 100`。三条动作各 5 帧、按原生 `FieldData.run_counter` 无暂停循环。
## 同一图集的动作 0–10 是说话气泡等普通表情，没有语义证据，保持数字名。
enum Emoticon {
	QUEST_AVAILABLE = 11,    ## 码 2：有可接任务
	QUEST_COMPLETED = 12,    ## 码 4／5：目标达成／事件任务（同一张图）
	QUEST_IN_PROGRESS = 13,  ## 码 3：进行中
}

## 野外主角 `hero/h_f_01`：每组三帧依次是朝下／朝上／朝侧（`field_actors.HERO_ACTION_BASES`）。
enum FieldHero {
	IDLE_DOWN = 0,
	IDLE_UP = 1,
	IDLE_SIDE = 2,
	WALK_DOWN = 3,
	WALK_UP = 4,
	WALK_SIDE = 5,
	RUN_DOWN = 6,
	RUN_UP = 7,
	RUN_SIDE = 8,
}

## 五向指令的原生图标顺序：动作 1–5 是按下反馈，松开是按下 + `COMMAND_PRESS_OFFSET`。
const COMMAND_ORDER := ["attack", "skill", "guard", "flee", "item"]
const COMMAND_PRESS_OFFSET := 5


## 原生 `animation_id` → ANI 动作号（`Battle_Monster_procAction` 的 switch）。
## 其余取值走 `animation_id % 100`，即物种自带的额外动作。
static func action_of(animation_id: int) -> int:
	match animation_id:
		AnimationId.IDLE, AnimationId.RETURN:
			return Clip.IDLE
		AnimationId.DAMAGED:
			return Clip.DAMAGED
		AnimationId.EFFECT:
			return 2
		AnimationId.ATTACK:
			return Clip.ATTACK
		AnimationId.SKILL:
			return Clip.SKILL
		AnimationId.CLONE_A:
			return Clip.CLONE_A
		AnimationId.CLONE_B:
			return Clip.CLONE_B
	return animation_id % 100


## 片段名 → 动作号：`action_003_attack` 只看前三位数字，`RESET` 等非动作片段返回 -1。
static func action_of_clip(clip: StringName) -> int:
	var text := String(clip)
	if not text.begins_with("action_") or text.length() < 10:
		return -1
	var digits := text.substr(7, 3)
	return int(digits) if digits.is_valid_int() else -1


## 动作号 → 该播放器里的片段名。片段名的语义后缀由 `script\ani_actions.py` 生成，
## 这里只按前三位数字匹配，所以未命名的动作（`action_002`）照样取得到。
static func clip_name(player: AnimationPlayer, action: int) -> StringName:
	if action < 0:
		return &""
	for clip: StringName in player.get_animation_list():
		if action_of_clip(clip) == action:
			return clip
	return &""
