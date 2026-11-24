extends Control
## 战斗场地：背景、站位、目标光标与受击表现。

signal target_pressed(index: int)
signal target_accepted(index: int)
## 战斗结果阶段：底部友方怪物信息按原生平方序列滑出屏幕后发出。
signal hud_exit_finished

const PoseScene = preload("res://battle/pose/pose.tscn")
const DamageNumberScene = preload("res://battle/damage_number/damage_number.tscn")
const HitEffectScene = preload("res://battle/hit_effect/hit_effect.tscn")
const HitEffect = preload("res://battle/hit_effect/hit_effect.gd")
const TextLayout = preload("res://core/native_text_layout/native_text_layout.gd")
const ItemEffect = preload("res://data/item_effect/item_effect.gd")
const BattlePoses = preload("res://battle/actor/battle-poses.tres")
const MonsterAnimation = preload("res://core/monster_animation/monster_animation.gd")
## 原生站位表 `Battle_objGetPosition` 的 10 个世界坐标槽（rodata 0x97864），
## 选槽规则见 `Battle_objGetPosition2`：我方 8／10／12、敌方 3／5／7，各自减去实际人数，
## 因此 1～2 只在战时会被摆到整列中间。减去战斗镜头偏移后即 400×240 屏幕坐标。
const ACTOR_SLOT_WORLD := [
	Vector2(120, 182), Vector2(120, 203), Vector2(111, 223), Vector2(120, 243),
	Vector2(120, 264), Vector2(283, 182), Vector2(283, 203), Vector2(292, 223),
	Vector2(283, 243), Vector2(283, 264),
]
const ACTOR_SLOT_ENEMY := [3, 5, 7]
const ACTOR_SLOT_PARTY := [8, 10, 12]
const DamageNumber := preload("res://battle/damage_number/damage_number.gd")
## 战斗加载的镜头焦点：`BattleCanvas_load:39-40` 把它写进 `BattleData + 41318／41319`
## 后调 `Battle_mapCAMERA(202, 244, 1)`。全库只有这一处写那份焦点（`probe_ida.writers`），
## `Battle_mapFOCUS:13-16` 固定读它——所以状态 25 POSITION 的镜头回到这个值。
const LOAD_FOCUS := Vector2(202, 244)
## 原生 `BattleCanvas_load` 把焦点设成 (202, 244) 后调用
## `Battle_mapCAMERA(202, 244, 1)`：400×240 下 x 取 `400 - width`、y 取 `320 - height`，
## 末尾再各加 2，得到相机原点 (2, 82)。背景四层与对象共用同一原点，见 `Battle_mapDraw`。
const BATTLE_CAMERA := Vector2(2, 82)
## 阵亡墓碑的物种号：原生 `Battle_Monster_resLOAD` 对所有战斗对象都按
## `mon2/m_b_%03d_1` 拼路径，而 999 号（`mon2/m_b_999_1`）的 ANI 就是「十字墓碑 + 英雄影子」
## 32×40、只有一个动作。战斗代码里没有 999 的立即数（全文扫过），所以「阵亡即换成 999 号」
## 是按这份资源与同一加载路径实现的。墓碑**朝向固定**（十字 + 影子本来就只有一个朝向）：
## 原生 kind 18 对象连 `direction_code` 都不写，memset 后恒 0，不参与 `Object_drawSPRITE` 的镜像。
const GRAVE_SPECIES := 999
## 一次性表现（伤害数字、命中迸发、分身）的固定槽位数。原生每次命中都新建 kind 14 对象
## （`Param_dmgNUMBER`／`Param_atkEFFECT`）、每个敌人各建一具分身（`Object_objCreate`），
## 工程改成**开局建满、运行期只按序循环复用、不新建不销毁**：实例化与释放都会打断该帧的播放，
## 连续命中时表现为技能／攻击抖动（bm-P1-27）。战斗里同时受击的对象最多 6 个，
## 一步之内最多 6 处伤害数字、6 个命中迸发、6 具分身，所以每池 6 个槽。
const TRANSIENT_SLOTS := 6
## 目标横幅文字的抖动（bm-P1-33）：原生 `Battle_Target_mPaint` 把文字基线偏移取成
## `*((_DWORD *)&unk_97C8C + 帧计数字段 + 30)`，帧计数字段是 `BattleData.run_counter` 的 +3 号槽：
## `BattleCanvas_SetNext` 进状态与 `Battle_Target_mKeyPressed` 换目标时清 0，`Battle_Target_mRun`
## 每帧 +1 到 9。表里 `0x97D08／0x97D0C／0x97D10` 三个 int32 是 −2、+2、−1（第 4 帧起不偏移）。
## 关键帧压缩在 `field.tscn` 的 `Hud/TargetShake`（0.05 秒一步，末帧回原位），脚本只在换目标时 `play()`。
const TARGET_SHAKE_OFFSETS: Array[int] = [-2, 2, -1]
const TARGET_SHAKE_CLIP := &"target_shake"
## 目标横幅的淡入（`Battle_Target_mPaint:58-60`）：黑带 alpha 取
## `n128 = 进目标态后的帧计数 <= 2 ? 64 : 128`（256 制），文字 alpha 是 `2 * n128`
## —— 也就是进入后第 1、2 帧带子 25%／文字 50%，第 3 帧起 50%／不透明。
## 帧计数由 `BattleCanvas_mRun` 每帧 +1（先 Run 后 Paint，所以首帧计数是 1）、`BattleCanvas_SetNext`
## 进状态清 0。退出侧原生没有对应分支：全库只有 `Battle_Target_mPaint` 画这条带，退出即消失。
const TARGET_FADE_COUNTER_MAX := 2
const TARGET_BAND_ALPHA_FADING := 64.0 / 256.0
const TARGET_BAND_ALPHA := 128.0 / 256.0
## 目标光标的横向距离：原生 `Battle_Target_mPaint` 传 `n40: 40` 给
## `Battle_objPOS`，我方（`direction_code == 1`）取 `x - 40`、敌方取 `x + 40`。
const TARGET_CURSOR_OFFSET := 40.0
## 原生 `BattleCanvas_mon_DrawUI` 的底部 HUD 滑出：`n²` 超过 50 就整块压出屏幕。
const HUD_EXIT_LIMIT := 50
## 原生 `Battle_Monster_procPosition` 读 ANI frame 层 0 的 `form`（`battle-poses.tres` 的
## `Vector2i(form, code)` 的 x），取值见 `battle_poses.gd` 的 `Form`：1 = 相对受击者摆位
## （`code` 选 a4 = 160／17／0）、2 = 固定槽（212 份 ANI 里没出现过，不实现）、
## 0 = 本帧不写坐标（沿用上一次落点）。
const FORM_TARGET := BattlePoses.Form.TARGET
## `$Effects` 里每个池化姿势当前画的是哪一具分身（`origin/target/action`），换对象时才重播动作。
const CLONE_KEY := &"clone_key"
## 技能态底图压暗的四档：原生 `Battle_mapDraw` 在 `n4 > 0` 时把 `n4` 折成 `v9 = {208, 160, 112, 64}`
## 的一档，交给 `JC_grpSetMODE(GRP_MODE_MULTIPLY_COLOR, 分量 << 16 | 分量 << 8 | 分量)`，只作用在底图
## 那四次 `Object_drawBASIC(…, 15, 0, 动画号, …)` 上——`Battle_objDraw()` 画在两次压暗之间、
## `JC_grpReset()` 之后，所以战斗对象不受影响，HUD 与伤害数字更不在 `Battle_mapDraw` 里。
## `EFC_pixel_MULTIPLY_COLOR_Proc` 逐通道乘 `分量 / 256`（5 位通道 `(分量 >> 3) / 32`、6 位通道
## `(分量 >> 2) / 64`，折算后都是 `/ 256`），所以底图节点的 `modulate` 直接取 `分量 / DIM_SCALE`
## （`modulate` 会乘到三个底图子树里的每个 Sprite2D 上，`self_modulate` 不会）。
## 档位值在这里具名，`field.tscn` 的 `dim` 轨道与它一致。
enum DimLevel {
	NONE = 255, ## 不进 `n4 > 0` 分支：不设 `GRP_MODE_MULTIPLY_COLOR`，等于原亮度
	FIRST = 208, ## `v9[0]`，原生 `n4 = 1`
	SECOND = 160, ## `v9[1]`，原生 `n4 = 2`
	THIRD = 112, ## `v9[2]`，原生 `n4 = 3`
	FOURTH = 64, ## `v9[3]`，原生 `n4 >= 4`（`n4 > 4` 被夹回这一档）
}
## `MULTIPLY_COLOR` 分量的分母（同 `JC_grpSetMODE` / `PixelData.mode_parameter_bits` 的 256 制）。
const DIM_SCALE := 256.0
## `Battle_Skill_mPaint` 的 `n4 = BattleData.run_counter_002c_bits - 2`，而 `run_counter` 由
## `BattleCanvas_mRun` 每帧 +1、技能态从 0 起算，所以第一档落在横幅帧号 3，四档各占 1 帧（0.05 秒）。
const DIM_FIRST_STEP := 3
## `field.tscn` 的 `DimPlayer` 里那条四档压暗动画：`Background`／`Ground`／`Foreground` 三个底图
## 节点的 `modulate` 轨道，脚本只 `play()`／`stop()`，不逐帧算亮度。
const DIM_CLIP := &"dim"

var _species: Dictionary = {}
var _texts: Dictionary = {}
var _assets: Node
var _party_available: Array[bool] = [false, false, false]
var _has_party := false
var _resting_expanded := false
var _requested_expanded := false
var _transition_in_progress := false
var _card_base_offsets: Array[Vector2] = []
## 当前镜头原点（`MapData.camera_origin_*` 的存值口径：真原点 + (2, 2)），
## 背景、地面、前景与所有对象都减它换屏幕坐标。
var camera := BATTLE_CAMERA
var _focus := LOAD_FOCUS
## 最近一次 `present()` 的在场阵容，用来把对象序号换成编队世界坐标（镜头焦点从这里取）。
var _balls: Array = []
## 目标光标当前指向的序号；换怪时按原生 `Battle_Target_mKeyPressed` 把帧计数清 0（重播 appear）。
var _cursor_target := -1
## 上方目标横幅当前显示的序号（−1 = 横幅没开）；换目标或重新进目标态时重播一次抖动。
var _banner_target := -1
## 进目标态后的帧计数（原生 `BattleData.run_counter`）：首帧 1，用于横幅淡入。
var _target_frames := 0
## 底部 HUD 滑出进度：−1 = 未开始／已滑完，否则是进入结果阶段后的帧数。
var _hud_exit_frame := -1
## 底部 HUD 六个节点的场景原始位置（top, height），滑出与复位都从它算。
var _hud_rest: Array[Vector2] = []
## 槽位序号 → `$Actors` 的节点。绘制序按原生规则重排过（见 `_sort_actors()`），
## 所以任何地方都不能再用 `$Actors.get_child(序号)` 当代号。
var _actors: Array = []
## 一次性表现池的循环游标（严格轮转，不扫描空闲槽，见 `TRANSIENT_SLOTS`）。
var _popup_cursor := 0
var _hit_cursor := 0
## 底图是否正被技能态压暗（`DimPlayer` 的 `dim` 已在播），用来避免每帧重复 `play()`。
var _dimmed := false


func _ready() -> void:
	$Hud/TransitionPlayer.animation_finished.connect(_transition_finished)
	# 一次性表现的槽位开局建满：运行期只循环复用，不再临时创建／销毁。
	_fill_slots($Popups, DamageNumberScene, "Number")
	_fill_slots($Hits, HitEffectScene, "Hit")
	_fill_slots($Effects, PoseScene, "Effect")
	for node: Control in [$Hud/Current, $Hud/Skill]:
		_card_base_offsets.append(Vector2(node.offset_top, node.offset_bottom))
	for index in $Actors.get_child_count():
		var actor: Control = $Actors.get_child(index)
		_actors.append(actor)
		var slot := index
		actor.get_node("TargetHit").pressed.connect(func(): target_pressed.emit(slot))
	$Cursor/AnimationPlayer.animation_finished.connect(_cursor_finished)
	for node: Control in _hud_exit_nodes():
		_hud_rest.append(Vector2(node.offset_top, node.offset_bottom - node.offset_top))
	_set_camera(BATTLE_CAMERA)


## 光标自己的动画链（原先挂在各只怪物身上）：appear 播完接循环，确认动作播完才回报选中。
func _cursor_finished(animation: StringName) -> void:
	match AniAction.action_of_clip(animation):
		AniAction.Icon.CURSOR_APPEAR:
			_play_cursor(AniAction.Icon.CURSOR_LOOP)
		AniAction.Icon.CURSOR_CONFIRM:
			target_accepted.emit(_cursor_target)


func _play_cursor(action: int) -> void:
	var player: AnimationPlayer = $Cursor/AnimationPlayer
	player.play(AniAction.clip_name(player, action))
	player.advance(0.0)


## 原生 `Battle_mapCAMERA` 的焦点→原点换算：400 宽视口把焦点 x 夹到 `[200, 200]`，
## 所以横向原点恒为 0；纵向 `clamp(focus_y, 120, 200) − 120`（舞台 320 高、可视 240）。
## 函数末尾统一 `+= 2` 存、读时 `− 2`，因此场上用的存值等于真原点 + (2, 2)。
func camera_target(focus: Vector2) -> Vector2:
	return Vector2(BATTLE_CAMERA.x, clampf(focus.y, 120.0, 200.0) - 118.0)


## a3 = 0 的双半程插值：`v = ((target + cur + half) / 2 + cur + half) / 2`，整数截断后
## 等价于每个游戏帧只走掉 1/4 的误差（20 像素的差第一帧走 5 像素，约 6 帧收敛）。
## `snap` 对应 a3 != 0 的立即定位（战斗加载用 focus (202, 244) 直接落到 (2, 82)）。
func set_focus(focus: Vector2, snap: bool = false) -> void:
	_focus = focus
	var target := camera_target(focus)
	_set_camera(target if snap else Vector2(target.x, floorf(target.y * 0.25 + camera.y * 0.75)))


## 战斗加载：`BattleCanvas_load` 用 focus `LOAD_FOCUS` 立即定位到 (2, 82)。
func reset_camera() -> void:
	set_focus(LOAD_FOCUS, true)


## 加载时的焦点：`Battle_mapFOCUS` 只认这一份，状态 25 POSITION 的镜头要插回它。
func load_focus() -> Vector2:
	return LOAD_FOCUS


func camera_settled() -> bool:
	return is_equal_approx(camera.y, camera_target(_focus).y)


func _set_camera(value: Vector2) -> void:
	camera = value
	$Background.position = -camera
	$Ground.position = -camera
	$Foreground.position = -camera


## 对象在本场战斗里的编队世界坐标（未减镜头），镜头焦点就是从这里取的。
## 选槽规则与 `_place_actors()` 相同：我方 8／10／12、敌方 3／5／7，各减同侧实际人数。
func slot_position(index: int) -> Vector2:
	if index < 0 or index >= _balls.size() or _balls[index].is_empty():
		return LOAD_FOCUS
	var side := 0 if index < 3 else 1
	var bases: Array = ACTOR_SLOT_ENEMY if side == 0 else ACTOR_SLOT_PARTY
	var order := 0
	for other in range(0 if side == 0 else 3, index):
		if other < _balls.size() and not _balls[other].is_empty():
			order += 1
	return ACTOR_SLOT_WORLD[bases[order] - _side_count(_balls, 0 if side == 0 else 3)]


func configure(assets: Node) -> void:
	_species.clear()
	for species: MonsterDefinition in assets.load_gameplay_catalog().monsters:
		_species[species.id] = species
	_texts = assets.text_messages("common/item_mon.dat")
	_assets = assets


## 原生 `Battle_Character_mRun`（状态 11）的后移是**回合开始**的抬手动作，不是行动之后：
## 「轮到这个怪物作指令」时（`Battle_Character_init` 选完行动者）每帧按 `run_counter` 重排行动方一侧，
## `Battle_objGetPosition2(序号, &x, &y, a4)` 给行动者 `a4 = -run_counter`、同侧其余
## `a4 = -5 * run_counter`；`Battle_objGetPosition` 对我方（槽 > 4）取 `x - a4`、
## 敌方取 `x + a4`，所以两边都是**后退**——行动者 1 像素／帧、其余 5 像素／帧，
## 行动者在阵型里凸出、其余让出指令窗口的位置。`run_counter > 5` 切状态 12 POISON，
## 之后 MENU／TARGET／ATTACK 都不再重排。**状态 25 POSITION 才是回位**：每帧
## `x = (编队槽 + 当前x) / 2`、`y = (槽y + 当前y) / 2` 半程收敛（整数除法向 0 截断），
## `run_counter > 10` 才切下一位行动者，所以后移位是「滑」回槽位的（25 → 12 → 6 → 3 → 1 → 0）。
## `animation_id` 13／19 不在场时不参与。
##
## 受击回弹是原生唯一会挪动战斗对象的逐帧位移：`Battle_Monster_procCurr` 只在
## `animation_id == 12`（受击）时先把坐标写回编队槽 `Battle_objGetPosition2(序号, …, a4: 0)`，
## 再按 `n4 = same_animation_request_count * frame_count + frame_index` 查表 `{8,6,4,2,0}`
## 推开：`direction_code == 1`（我方）`x += knock`、`== 2`（敌方）`x -= knock`，所以受击方被
## **打离攻击者**，而且这一步是覆盖式的——回合开始的 1／5 像素后移会被抹掉，回到编队槽；
## 第 5 帧 `knock = 0` 归槽，`n4 > 4` 时回到 `animation_id = 0`。`recoil` 就是这个带符号的
## knock 值（`null` 表示不在受击中），由 `battle_view` 按行动步数（一步 = 原生一帧）算好传进来。
## `dash` 是该段冲刺的累计横向位移（原生 `case 20／21` 的 `x += dash * (n + k)`，
## 见 `BattleModel.dash_offset`）。
func _seat(pose: Control, index: int, actor: int, run_counter: int, recoil = null,
		returning = null, command := Vector2i.ZERO, command_target := -1,
		dash := 0.0) -> void:
	if recoil != null:
		pose.position.x = float(recoil)
		return
	# 状态 25 POSITION 逐帧减半的收敛量优先级最高：动作已经播完，逐帧定位指令不再生效，
	# 但攻击帧留下的位移要跟着一起收回去（原生收敛的是当前坐标）。
	if returning != null:
		pose.position = returning
		return
	# 原生 `Battle_Monster_procPosition` 的逐帧定位：攻击／技能帧把本体搬到受击者身前。
	# form 2（固定槽）在 212 份 ANI 里没出现过，不实现。
	# 冲刺段（`animation_id` 20／21）的位移叠在定位结果上：原生每帧先由 procPosition 摆位、
	# 再由该物种的 `case 20／21` 累加 `dash`。
	if command.x == FORM_TARGET:
		pose.position = _command_position(index, command, command_target) + Vector2(dash, 0.0)
		return
	var steps := 0
	if run_counter > 0 and (index < 3) == (actor < 3):
		steps = run_counter if index == actor else 5 * run_counter
	# 我方在右（+x）、敌方在左（−x），后退方向因此相反。
	pose.position = Vector2(float(steps if index >= 3 else -steps) + dash, 0.0)


## 原生 `Battle_Monster_procPosition` 的落点：`Battle_objGetPosition2(受击者序号, a4)`——
## 我方槽（> 4）取 `x − a4`、敌方槽取 `x + a4`，y 取受击者槽 y；随后 `Object_objPOS(本体, x, y + 1, 0, -1)`。
## code 0 → a4 = 160（≈ 自己那一列，等于原地打）、1 → 17（贴到受击者身前）、2 → 0（压在受击者身上）。
## 返回**世界坐标**（未减镜头），本体与分身共用这一处换算。
func _command_anchor(target: int, command: Vector2i) -> Vector2:
	var distance := 160.0 if command.y == 0 else (17.0 if command.y == 1 else 0.0)
	var victim := slot_position(target)
	var side := 1.0 if target < 3 else -1.0
	return Vector2(victim.x + side * distance, victim.y + 1.0)


## 同上，但换算成相对自己编队槽的偏移（`_seat` 写 `Pose.position` 用）。
func _command_position(index: int, command: Vector2i, command_target: int) -> Vector2:
	if command_target < 0 or command_target >= _balls.size() or _balls[command_target].is_empty():
		return Vector2.ZERO
	return _command_anchor(command_target, command) - slot_position(index)


## 分身的位置：原生生成时 `Object_objPOS(分身, 本体 x, 本体 y + 1, 0, -1)` 贴在本体当前位置，
## 之后每帧 `Battle_Monster_procPosition` 按**该分身自己动作**的 form／code 把它摆到
## 「自己的目标那一槽 ± a4」——`all` 段（每个敌人各建一具）因此各自贴到自己那个敌人身前，
## 不再全叠在攻击者槽位上。冲刺量（`case 20／21` 的累计 `dash`）再叠在落点上；
## `offset` 的 y（原生 `y + 1`）只在第一种落点用得上，procPosition 的落点自己带 `y + 1`。
func _clone_position(balls: Array, aux: Dictionary) -> Vector2:
	var origin := int(aux.get("origin", -1))
	if origin < 0 or origin >= balls.size() or balls[origin].is_empty():
		return Vector2.ZERO
	var offset: Vector2 = aux.get("offset", Vector2.ZERO)
	var command: Vector2i = BattlePoses.command(
		MonsterAnimation.battle_identity(int(balls[origin].species)),
		int(aux.action), int(aux.frame))
	var target := int(aux.get("target", -1))
	if command.x == FORM_TARGET and target >= 0 and target < _balls.size() \
			and not _balls[target].is_empty():
		return _command_anchor(target, command) - camera + Vector2(offset.x, 0.0)
	return actor_render_position(origin) + offset


## 本体冲刺的位移：原生 `Battle_Monster_00NN_procCurr` 的 `case 20／21` 每帧把 x 推
## `dash * (n + k)`。系数与 k 只取决于 (物种, `animation_id`)——同一物种的该段在攻击与技能两条
## 时间轴上共用同一份 `case`——所以按当前动作号反查分段即可。`frame` 是原生那个**绝对**帧号 `n`。
func _body_dash(ball: Dictionary, action: int, frame: int) -> float:
	for skill: bool in [false, true]:
		for segment: Dictionary in BattleSpeciesTable.segments(int(ball.species), skill):
			if AniAction.action_of(int(segment["animation"])) != action:
				continue
			return BattleModel.dash_offset(int(ball.direction), frame, int(segment["dash"]),
				int(segment["dash_addend"]))
	return 0.0


## 本体在该动作里的**绝对帧号** n（原生 `n = same_animation_request_count * frame_count +
## frame_index`）：`poses[index]["frame"]` 只有段内帧号（`frame % count`），而动作 5／6 的片段常常
## 只有 1 帧（`mon2/m_b_069_1` 的 `action_005_clone_a`），命中帧却在它之后；
## `battle_view._render_step` 把时间轴步号一并放进姿势字典，这里直接取用。
func _body_frame(state: Dictionary) -> int:
	return int(state.get("counter", 0))


## 阵亡换墓碑的时序：`Ball_stdHP` 在命中帧就把血扣到 0，但攻击动作要等
## `Battle_Monster_procNext` 收尾才切 POSITION，所以墓碑等动画播完再换。
func present(balls: Array, poses: Array[Dictionary],
		auxiliary: Array[Dictionary], acting_actor: int, phase: String,
		actor: int, target: int, candidates: Array = [], popups: Array = [],
		run_counter: int = 0, recoil: Dictionary = {}, fade: Dictionary = {},
		shifts: Dictionary = {}, command_target: int = -1,
		_deferred_graves: Dictionary = {}, effect: Dictionary = {},
		flashes: Array = [], action_step: int = -1) -> void:
	_place_actors(balls)
	for index in range(_actors.size()):
		var display: Control = _actors[index]
		display.visible = index < balls.size() and not balls[index].is_empty()
		display.get_node("TargetHit").visible = phase == "target" and candidates.has(index)
		if display.visible:
			var shown: Dictionary = balls[index]
			var pose_state: Dictionary = poses[index] if index < poses.size() else {}
			if int(shown.get("hp", 1)) <= 0 and not _deferred_graves.has(index):
				shown = shown.duplicate()
				shown["species"] = GRAVE_SPECIES
				# 墓碑朝向固定，不跟受击方自己的 direction 镜像。
				shown["direction"] = 0
				pose_state = {"action": AniAction.Clip.IDLE, "frame": 0}
			display.present(shown, pose_state)
			var pose: Control = display.get_node("Pose")
			# 原生 `Object_drawSPRITE` 用 `alpha = 256 − 12 * extended_state[541]`。
			pose.modulate.a = float(256 - 12 * int(fade.get(index, 0))) / 256.0
			_seat(pose, index, actor, run_counter, recoil.get(index, null), shifts.get(index, null),
				pose_state.get("command", Vector2i.ZERO), command_target,
				_body_dash(shown, int(pose_state.get("action", AniAction.Clip.IDLE)),
					_body_frame(pose_state)))
	_sort_actors(balls)
	_place_target_cursor(balls, phase, target)
	for index in range($Effects.get_child_count()):
		var pooled: Node = $Effects.get_child(index)
		pooled.visible = index < auxiliary.size()
		if not pooled.visible:
			# 槽位空出来时清掉身份，下次占槽要重新从头播（见下面的 `fresh`）。
			pooled.set_meta(CLONE_KEY, "")
			continue
		var aux: Dictionary = auxiliary[index]
		pooled.position = _clone_position(balls, aux)
		# 原生每个分身都是独立对象（`Object_procCURR` 每游戏帧推进一帧 ANI），所以只在它**首次占住
		# 这个槽**的那一步从动作头播起，之后交给 AnimationPlayer 按真实时间推进；每步都重播会让
		# 分身永远停在第 1 帧（帧序列就不再是 clones 段给的那一段了）。
		var key := "%d/%d/%d" % [int(aux.get("origin", -1)), int(aux.get("target", -1)),
			int(aux.action)]
		var fresh: bool = pooled.get_meta(CLONE_KEY, "") != key
		pooled.set_meta(CLONE_KEY, key)
		pooled.present(balls[acting_actor], int(aux.action), 1.0, true, fresh)
	_show_popups(popups, balls)
	_show_capture_effect(effect, balls)
	_show_action_effects(flashes, balls)
	_present_skill_banner(balls, poses, acting_actor, action_step)
	# 结果阶段（原生状态 26）不再画战斗 HUD：友方信息正在按平方序列滑出，顶部血条已经收掉。
	if _hud_exit_frame >= 0 or not $Hud.visible:
		return
	for index in mini(3, balls.size()):
		var enemy: Control = $Hud.get_node("Enemy%d" % index)
		enemy.visible = not balls[index].is_empty()
		if enemy.visible:
			enemy.present(balls[index], index == (target if phase == "target" else actor))
	_has_party = false
	for index in 3:
		var card: Control = $Hud.get_node("Party%d" % index)
		_party_available[index] = index + 3 < balls.size() and not balls[index + 3].is_empty()
		if _party_available[index]:
			_has_party = true
			card.present(balls[index + 3], _species[int(balls[index + 3].species) % 1000])
			_present_food(card, int(balls[index + 3].get("food", ItemEffect.FOOD_MAX)))
	var expanded: bool = phase == "command" and actor >= 3 and actor < balls.size() \
		and not balls[actor].is_empty()
	if not _has_party:
		_set_neutral_pose()
	else:
		_request_pose(expanded)
	_apply_layer_visibility()
	if expanded:
		var ball: Dictionary = balls[actor]
		$Hud/Current.present(ball, _species[int(ball.species) % 1000])
		_present_food($Hud/Current, int(ball.get("food", ItemEffect.FOOD_MAX)))
		var skill := _skill_text(ball)
		$Hud/Skill/Name.text = skill[0]
		$Hud/Skill/Description.text = skill[1] if skill.size() > 1 else ""
	$Hud/TargetInfo.visible = phase == "target"
	if phase == "target":
		# 原生 `BattleCanvas_mRun` 先 +1 再画，所以首帧计数是 1；`<= 2` 的两帧是淡入段。
		_target_frames += 1
		var band_alpha: float = TARGET_BAND_ALPHA_FADING \
			if _target_frames <= TARGET_FADE_COUNTER_MAX else TARGET_BAND_ALPHA
		$Hud/TargetInfo.color = Color(0, 0, 0, band_alpha)
		var ball: Dictionary = balls[target]
		var nickname := int(ball.nickname)
		var prefix: String = _assets.text_message(Msg.SOURCE, Msg.Id.NICKNAME_PREFIX + nickname) + " " if nickname > 0 else ""
		var level := "Lv.%d " % ball.level
		# 1 像素黑描边在场景里声明（`Hud/TargetInfo/Shake/Name` 的 `outline`）：原生
		# `Battle_Target_mPaint` 先用 `#P000#P000` 调色板配 `JC_fntSetBOLD(1)` 画一遍文字，
		# 而 `JC_fntDrawBUFF` 的 bold=1 把字模区域四周各扩 1 像素（`x-1, y-1, w+2, h+2`）。
		var label: Control = $Hud/TargetInfo/Shake/Name
		label.text = level + "%s%s" % [prefix,
			_texts["item_mon.group.%d.name" % (int(ball.species) % 1000)]]
		var level_color := Color.WHITE if int(balls[actor].level) == int(ball.level) else \
			Color.RED if int(ball.level) > int(balls[actor].level) else Color.GREEN
		var arguments: Array = ball.get("native_arguments", [])
		var name_color := Color.YELLOW if arguments.size() == 10 and arguments[5] == 1 else Color.WHITE
		var markup := "[color=#%s]%s[/color][color=#%s]%s[/color]" % [level_color.to_html(false),
			level, name_color.to_html(false), label.text.substr(level.length())]
		var layout := TextLayout.layout(markup, label.theme.default_font,
			label.theme.default_font_size)
		if not layout.error.is_empty():
			push_error(layout.error)
			return
		label.set_line(layout.lines[0])
		# 文字 alpha 是 `2 * n128`（`Battle_Target_mPaint:105`）：淡入期 50%，之后不透明。
		$Hud/TargetInfo/Shake.modulate.a = minf(1.0, band_alpha * 2.0)
		if _banner_target != target:
			_banner_target = target
			$Hud/TargetShake.play(TARGET_SHAKE_CLIP)
	else:
		_banner_target = -1
		_target_frames = 0


## 原生 `Game_monDraw@0x41360:22` 给每张友方卡片画的第一项是底部 FOOD 条：
## `Game_monDrawGage(x + 2, y + 34, 75, 3, food_value, 100, 0, 0xFFFF55, 0xE1B2F)`。
## `Game_monDrawGage@0x4116C` 用 1 像素黑框（行 y+34／y+36）包一行填充：亮黄 `0xFFFF55`
## 按 `food_value / 100` 占满 73 像素，其余是底色 `0xE1B2F`。卡片 77×37 时条落在
## 400×240 屏幕的第 236～238 行、x+2 起 75 像素宽，正好在血条下方、底边留 1 像素。
func _present_food(card: Control, food: int) -> void:
	var track: Control = card.get_node("Food/Track")
	var fill: Control = track.get_node("Fill")
	fill.offset_right = float(int(track.size.x) * food / ItemEffect.FOOD_MAX)


## 目标光标是**单独一层**（`$Cursor` 排在 `$Actors`／`$Foreground` 之后、`$Hud` 之前）：
## 原生 `Battle_Target_mPaint` 也是先 `Battle_mapDraw(0)` 画完场地与所有对象、
## 再 `Object_drawBASIC(...)` 画光标，所以它不会被任何怪物或前景挡住。
## 位置取 `Battle_objPOS(obj, &x, &y, n40: 40)`：`direction_code == 1`（我方，见
## `Battle_objNextDirect` 给我方表 +20650 写 1）取 `obj.x - 40`、敌方取 `obj.x + 40`，
## 即永远落在怪物**朝屏幕中心那一侧** 40 像素处；`obj.x` 已含回合开始的后移量
## （`Battle_Character_mRun` 直接写 obj->x），所以锚 `actor_render_position()`。
## 换怪时原生把 `run_counter_002c_bits` 清 0，光标重播 appear（`AniAction.Icon.CURSOR_APPEAR`）。
func _place_target_cursor(balls: Array, phase: String, target: int) -> void:
	var shown: bool = phase == "target" and target >= 0 and target < balls.size() and \
		not balls[target].is_empty()
	$Cursor.visible = shown
	if not shown:
		_cursor_target = -1
		return
	var direction := int(balls[target].get("direction", 0))
	$Cursor.position = actor_render_position(target) + Vector2(
		-TARGET_CURSOR_OFFSET if direction == BattleSide.Code.PLAYER else TARGET_CURSOR_OFFSET, 0.0)
	if _cursor_target != target:
		_cursor_target = target
		_play_cursor(AniAction.Icon.CURSOR_APPEAR)


func accept_target(index: int) -> void:
	_cursor_target = index
	_play_cursor(AniAction.Icon.CURSOR_CONFIRM)


func _request_pose(expanded: bool) -> void:
	_requested_expanded = expanded
	if _transition_in_progress or expanded == _resting_expanded:
		return
	_start_transition(expanded)


## 原生 `BattleCanvas_mon_DrawUI`：状态 19..33 里 `0x788B` 这些状态（含 26 WIN）
## 每次绘制都按「进入本状态的帧数平方」把底部 HUD 往下推——`destination_y = height − 23 + n²`，
## `n² > 50` 之后直接把底部条压到 `height + 27`，即整块友方怪物信息滑出屏幕。
## 顶部敌方血条不进这段滑出：状态 26 的 `Battle_Win_mPaint` 只画冻结底图与窗口，
## 所以这里一进结果阶段就收掉。
func start_hud_exit() -> void:
	if _hud_exit_frame >= 0:
		return
	_hud_exit_frame = 0
	for index in 3:
		$Hud.get_node("Enemy%d" % index).hide()
	$Hud/TopShade.hide()
	$Hud/TransitionPlayer.stop()
	_apply_hud_exit(0)


## 每 0.05 秒一帧（原生每个游戏帧调用一次 `mon_DrawUI`），滑到位后整块 HUD 隐藏。
func advance_hud_exit() -> void:
	if _hud_exit_frame < 0:
		return
	_hud_exit_frame += 1
	_apply_hud_exit(_hud_exit_frame)
	if _hud_exit_frame * _hud_exit_frame <= HUD_EXIT_LIMIT:
		return
	_hud_exit_frame = -1
	$Hud.hide()
	hud_exit_finished.emit()


func hud_exited() -> bool:
	return _hud_exit_frame < 0


## 新的一场战斗要回到战斗 HUD 的原位（原生重进 BASIC 状态会重新画 HUD）。
func reset_hud() -> void:
	_hud_exit_frame = -1
	var nodes := _hud_exit_nodes()
	if _hud_rest.is_empty():
		for node: Control in nodes:
			_hud_rest.append(Vector2(node.offset_top, node.offset_bottom - node.offset_top))
	for index in nodes.size():
		nodes[index].offset_top = _hud_rest[index].x
		nodes[index].offset_bottom = _hud_rest[index].x + _hud_rest[index].y
	$Hud.show()
	$Hud/TopShade.show()
	for index in 3:
		$Hud.get_node("Enemy%d" % index).show()
	freeze_scene(false)


func _hud_exit_nodes() -> Array[Control]:
	return [$Hud/BottomShade, $Hud/Party0, $Hud/Party1, $Hud/Party2, $Hud/Current, $Hud/Skill]


func _apply_hud_exit(frame: int) -> void:
	var offset := frame * frame
	var nodes := _hud_exit_nodes()
	for index in nodes.size():
		var rest: Vector2 = _hud_rest[index]
		# 平方序列推下去；`n²` 超过 50 后原生直接把底部条放到 height + 27。
		var shift: float = (240.0 - rest.x + 27.0) if offset > HUD_EXIT_LIMIT else float(offset)
		nodes[index].offset_top = rest.x + shift
		nodes[index].offset_bottom = rest.x + shift + rest.y


## 状态 26 里原生不再重画战斗对象（只 blit 冻结底图），所以进场后停住动画并收掉目标光标。
func freeze_scene(value: bool) -> void:
	for index in _actors.size():
		var monster: Node = _actors[index].get_node("Pose/Monster")
		monster.set_running(not value)
	$Cursor.visible = not value
	$Hits.visible = not value
	$Effects.visible = not value


func _start_transition(expanded: bool) -> void:
	_transition_in_progress = true
	_apply_layer_visibility()
	var player: AnimationPlayer = $Hud/TransitionPlayer
	player.play("expand" if expanded else "collapse")
	player.advance(0.0)


func _transition_finished(animation: StringName) -> void:
	if animation == &"expand":
		_resting_expanded = true
	else:
		_resting_expanded = false
		_reset_card_offsets()
	_transition_in_progress = false
	_apply_layer_visibility()
	if _requested_expanded != _resting_expanded and _has_party:
		_start_transition(_requested_expanded)


func _apply_layer_visibility() -> void:
	var transitional := _transition_in_progress
	for index in 3:
		$Hud.get_node("Party%d" % index).visible = _party_available[index] \
			and (transitional or not _resting_expanded)
	$Hud/Current.visible = _has_party and (transitional or _resting_expanded)
	$Hud/Skill.visible = _has_party and (transitional or _resting_expanded)


func _reset_card_offsets() -> void:
	for index in _card_base_offsets.size():
		var node: Control = $Hud/Current if index == 0 else $Hud/Skill
		node.offset_top = _card_base_offsets[index].x
		node.offset_bottom = _card_base_offsets[index].y


func _set_neutral_pose() -> void:
	var player: AnimationPlayer = $Hud/TransitionPlayer
	player.stop()
	_transition_in_progress = false
	_resting_expanded = false
	_requested_expanded = false
	_reset_card_offsets()
	for index in 3:
		$Hud.get_node("Party%d" % index).visible = _party_available[index]
	$Hud/Current.hide()
	$Hud/Skill.hide()


## 怪物在画面上的实际位置 = 编队槽 + `Battle_Character_mRun` 给的偏移（`Pose.position`）。
func actor_render_position(index: int) -> Vector2:
	var display: Control = _actors[index]
	return display.position + display.get_node("Pose").position


## 当前横向偏移（`Battle_Character_mRun` 的回合后移量）；状态 25 POSITION 会把它逐帧减半收回去。
## 状态 25 POSITION 的起点：对象**当前画出来的偏移**（本回合后移量，或攻击帧把本体摆到受击者
## 身前留下的位移）。原生 `Battle_Position_init` 只调 `Battle_objNextPosition`
## 抹掉 `Object_objPOS` 那份临时绘制偏移（`a4`／`a5` → `Object_objPOS(obj, obj->x, 0x18 + obj->y, 0, 0)`，
## **保留 x**），真正回槽是随后 `Battle_Position_mRun` 每帧
## `x = (槽 + 当前x) / 2`、`y = (槽y + 当前y) / 2` 的半程收敛。
## 所以这里读渲染后的实际位置，不能重算后移量。
func actor_shift(index: int) -> Vector2:
	return _actors[index].get_node("Pose").position


## 怪物当前帧的实际绘制范围（含朝向翻转）。命中特效、伤害数字都按它定位，
## 这样不管物种原图偏移多少，都落在「被击中的怪物」身上。
func actor_bounds(index: int) -> Rect2:
	var display: Control = _actors[index]
	var pose: Control = display.get_node("Pose")
	var local: Rect2 = pose.get_node("Monster").bounds()
	return Rect2(display.position + pose.position + local.position, local.size)


## 命中表现一律以【被击中的怪物】为准，不用攻击者的位置。
## 原生 `Param_atkEFFECT` 新建 kind 14 特效对象时写的是
## `x = victim.x + (direction_code == 2 ? -36 : +36)`、`y = victim.y + y_offset`，
## 其中 y_offset 查 `CSWTCH.95_0`（0x9B738，下标 = 动作号 − 25）：25／26 → 5、27–39 → 4、40／41 → 6；
## 命中迸发用动作 0／1、MISS 闪光用 39，都落在默认的 4。这 ±36 是为了抵消 `b_effect` 图集
## 偏在原点右侧的 34 像素（配合我方的水平翻转），所以迸发绘制重心仍在受击者身上；
## 伤害数字由 `Param_activeDraw` 显式把这 ±36 减回去，同样以受击者为水平中心。
func _show_popups(popups: Array, balls: Array) -> void:
	for popup: Dictionary in popups:
		var index := int(popup.target)
		if index < 0 or index >= balls.size():
			continue
		var damage := int(popup.damage)
		var critical: bool = popup.get("critical", false) and damage > 0
		var direction := int(balls[index].get("direction", 0))
		var bounds := actor_bounds(index)
		var center := bounds.get_center()
		# 数字以受击怪物为水平中心，底边贴在怪物上方；`damage_number` 内部按 RISE 逐帧上浮。
		var number := _next_popup()
		number.present(Vector2(center.x, bounds.position.y + DamageNumber.RISE[0]), damage,
			&"critical" if critical else (&"damage" if damage > 0 else &"miss"))
		# 命中迸发 / MISS 闪光：原生 `Param_atkEFFECT` 把 kind 14 对象放在 `victim.x ± 36`——
		# `direction_code == 2`（敌方）取 −36、其余（我方）取 +36。`b_effect` 图集重心偏在原点
		# 右侧 +34，我方又会按 `direction == 1` 水平翻转，所以这 ±36 正好把迸发压回受击者身上。
		var effect := _next_hit()
		var anchor := actor_render_position(index)
		var offset_x := HitEffect.OFFSET_X if direction == BattleSide.Code.PLAYER else -HitEffect.OFFSET_X
		effect.position = Vector2(anchor.x + offset_x, anchor.y + HitEffect.OFFSET_Y)
		effect.present(HitEffect.MISS_ACTION if damage <= 0 else
			(HitEffect.CRITICAL_ACTION if critical else HitEffect.DAMAGE_ACTION),
			direction)


## 复活／道具闪光：原生 `Battle_Die_mKeyPressed` 的 4／8 段与 `Battle_Target_mKeyPressed`
## 都用 `Param_atkEFFECT(obj.x, obj.y, 1, 动作, 0)` 在受术对象身上建一个 kind 14 对象，
## 动作 27 = HP 回复、28 = SP 回复、29 = 复活，y 偏移都落在 `CSWTCH.95_0` 的默认 4。
func _show_action_effects(flashes: Array, balls: Array) -> void:
	for flash: Dictionary in flashes:
		var slot := int(flash.get("slot", -1))
		if slot < 0 or slot >= balls.size() or balls[slot].is_empty():
			continue
		var direction := int(balls[slot].get("direction", 0))
		var anchor := actor_render_position(slot)
		var offset_x := HitEffect.OFFSET_X if direction == BattleSide.Code.PLAYER else -HitEffect.OFFSET_X
		var effect := _next_hit()
		effect.position = Vector2(anchor.x + offset_x, anchor.y + HitEffect.OFFSET_Y)
		effect.present(int(flash.get("action", 0)), direction)


## 捕获演出：原生 `Battle_Capture_Action_mRun` 在结果子状态第 0 帧调
## `Param_atkEFFECT(受击方 x, y, 1, 37／38, 0)`，也就是 `b_effect` 的 37（成功）／38（失败），
## 锚点与命中迸发同一套（`victim.x ± 36`、`victim.y + 4`，我方按 direction 镜像）。
func _show_capture_effect(effect: Dictionary, balls: Array) -> void:
	if effect.is_empty():
		return
	var index := int(effect.get("target", -1))
	if index < 0 or index >= balls.size() or balls[index].is_empty():
		return
	var direction := int(balls[index].get("direction", 0))
	var anchor := actor_render_position(index)
	var offset_x := HitEffect.OFFSET_X if direction == BattleSide.Code.PLAYER else -HitEffect.OFFSET_X
	var flash := _next_hit()
	flash.position = Vector2(anchor.x + offset_x, anchor.y + HitEffect.OFFSET_Y)
	flash.present(int(effect.get("effect", HitEffect.CAPTURE_ACTION)), direction)


## 技能横幅：原生 `Battle_Skill_mPaint`。技能态期间（`action_step` = 原生 `run_counter`）在画面上方
## 画一条半透明黑带 + 技能名 + 两侧装饰，并把施术者精灵画在黑带里；普攻的
## `Battle_Attack_mPaint` 没有这一段，横幅随即收起。
func _present_skill_banner(balls: Array, poses: Array, acting_actor: int, step: int) -> void:
	var banner: Control = $SkillBanner
	if step < 0 or acting_actor < 0 or acting_actor >= balls.size() \
			or acting_actor >= poses.size() or balls[acting_actor].is_empty():
		banner.clear()
		_dim_backdrop(-1)
		return
	# 技能动作比横幅表短时，动作一收尾 `poses` 就回待机；原生这 16 帧本来就全落在 SKILL
	# 状态里，所以这里只要横幅还开着就继续按同一个帧计数走完关闭段（否则退出段整段看不到）。
	if int(poses[acting_actor].get("action", -1)) != AniAction.Clip.SKILL and not banner.visible:
		banner.clear()
		_dim_backdrop(-1)
		return
	banner.show_skill(balls[acting_actor], step, _skill_text(balls[acting_actor])[0])
	_dim_backdrop(step)


## 技能态底图压暗：原生在 `Battle_Skill_mPaint` 里把 `run_counter - 2` 交给 `Battle_mapDraw`，
## 后者按四档 `MULTIPLY_COLOR` 压暗底图那四次 `Object_drawBASIC`。四档关键帧在 `field.tscn` 的
## `DimPlayer/dim`（每档 1 帧），这里只切状态：横幅跨过第一档帧号后 `play()`，横幅收起时
## `stop()` 并把三个底图节点复位到原亮度（`DimLevel.NONE` 那支：原生根本不设
## `GRP_MODE_MULTIPLY_COLOR`）。原生状态 25 还有 4 帧回亮（`Battle_Position_mPaint` 的
## `n4 = 5 - run_counter`），按本轮口径（横幅结束即复位）不实现。
func _dim_backdrop(step: int) -> void:
	if step >= DIM_FIRST_STEP:
		if not _dimmed:
			_dimmed = true
			$DimPlayer.play(DIM_CLIP)
		return
	if not _dimmed:
		return
	_dimmed = false
	$DimPlayer.stop()
	# 原生 `else` 分支连 `GRP_MODE_MULTIPLY_COLOR` 都不设，底图保持原亮度。
	for backdrop: CanvasItem in [$Background, $Ground, $Foreground]:
		backdrop.modulate = Color.WHITE


## 该物种当前技能的文本：原生 `Ball_datBasic`（记录类型 4 → `ItemRes.skill_definitions`）
## 把技能记录的 `detail_text` 填成「技能名/说明」，`Battle_Skill_mPaint` 再把 `/` 换成换行、
## 用 `JC_fntGetPage(…, 0, 1, 1)` 只取第一行 ⇒ 第一段就是技能名。没有技能记录的物种原生画空串。
func _skill_text(ball: Dictionary) -> PackedStringArray:
	return str(_texts.get("item_mon.group.%d.entry.0.name" % (int(ball.species) % 1000), "")) \
		.split("/", true, 1)


## 开局把池子建满（见 `TRANSIENT_SLOTS`）：运行期只循环复用，不再实例化／释放。
func _fill_slots(pool: Node, scene: PackedScene, prefix: String) -> void:
	while pool.get_child_count() < TRANSIENT_SLOTS:
		var slot: Node = scene.instantiate()
		slot.name = "%s%d" % [prefix, pool.get_child_count()]
		pool.add_child(slot)


## 下一个伤害数字槽：严格轮转，不扫描空闲、不新建。
func _next_popup() -> Control:
	var slot: Control = $Popups.get_child(_popup_cursor)
	_popup_cursor = (_popup_cursor + 1) % $Popups.get_child_count()
	return slot


## 下一个命中迸发／闪光槽：与数字分开轮转，同一步的迸发不会顶掉同一步的数字。
func _next_hit() -> Node2D:
	var slot: Node2D = $Hits.get_child(_hit_cursor)
	_hit_cursor = (_hit_cursor + 1) % $Hits.get_child_count()
	return slot


## 按实际在场人数取原生槽位；空槽保持 Scene 里的参考位置，不参与站位。
func _place_actors(balls: Array) -> void:
	_balls = balls
	for index in range(mini(6, _actors.size())):
		var display: Control = _actors[index]
		if index >= balls.size() or balls[index].is_empty():
			continue
		display.position = slot_position(index) - camera


## 原生 `Object_procLIST` 的插入序就是绘制序：`draw_order_key`（`Object_objHigh` 才写，
## 战斗里恒 0）→ **y 升序** → 同 y 时 `object_kind == 1` 靠后 → 其余保持对象池顺序
## （`BattleCanvas_load` 先建我方再建敌方 ⇒ 同 y 时敌方画在我方之上）。
## 这里只重排 `$Actors` 内部的子节点顺序（`move_child`），不动 `$Actions`／`$Hud` 兄弟层的层级，
## 所以不会像 `z_index` 那样把指令按钮压到怪物下面。
func _sort_actors(balls: Array) -> void:
	var order: Array = []
	for index in range(mini(_actors.size(), balls.size())):
		if balls[index].is_empty() or not _actors[index].visible:
			continue
		# `side` 是「同 y 时的次序」：原生对象池先建我方再建敌方，所以同 y 时敌方在上。
		order.append({"index": index, "y": _actors[index].position.y,
			"side": 1 if index < 3 else 0})
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["y"], b["y"]):
			return a["y"] < b["y"]
		if a["side"] != b["side"]:
			return a["side"] < b["side"]
		return a["index"] < b["index"])
	for position in order.size():
		var actor: Control = _actors[int(order[position]["index"])]
		if actor.get_index() != position:
			$Actors.move_child(actor, position)


## 同侧在场的对象数：`Battle_objGetPosition2` 用「槽号 − 人数」换算真实槽位。
func _side_count(balls: Array, first: int) -> int:
	var count := 0
	for index in range(first, mini(first + 3, balls.size())):
		if not balls[index].is_empty():
			count += 1
	return count


