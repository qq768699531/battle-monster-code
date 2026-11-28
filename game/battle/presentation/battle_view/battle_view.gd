extends Control

const MessageStack = preload("res://engine/ui/message_stack/message_stack.gd")
## The caller supplies the encounter and resources; settlement remains caller-owned.
## Godot players animate poses and schedule display steps; results await confirmation.

signal completed(outcome: Dictionary)
## 逃跑／放弃：结局是回野外地图（`field_runtime._battle_abandoned()`）。边界页只在逃生战
## （`allow_flee`）才走这条；事件战的边界页回标题（`title_requested`）。
## `outcome` 与 `completed` 同形：`items`（道具号 → 个数）是原生在战斗内使用时就已经
## `Item_stdDel`／`Item_stdDels` 写回的东西（`Battle_Capture_Action_IsCapture:123`、
## `Battle_Die_mKeyPressed` 的 `0x31DD0`），`captures` 是捕获成功、原生第 21 帧就
## `Ball_stdAddEx` 入包的个体——逃跑之前的捕获不能因为这条出口就丢掉。
signal abandoned(outcome: Dictionary)
## 原生 `Battle_MainMenu_mRun` 返回码 1 的 `Game_out()`：离开这一战**回标题**，
## 与 `abandoned` 是两条不同结局（`wiki\battle\battle-exit.md`）。`outcome` 与 `completed` 同形：
## 战斗内已经写回的已用道具与已捕获个体都得跟着这条出口交出。
signal title_requested(outcome: Dictionary)
## 战斗内系统菜单的环境设定改值当场生效（原生 `Menu_Setup_mKeyPressed` 的
## `EFC_mdaVOLUME`／`EFC_mdaPlayDATA(123)`／`EFC_mdaVIBRATE`）。音频所有者与总线音量都在启动层，
## 所以本 Scene 只把 `sys_menu` 的请求原样转出去，由 `main.gd` 接（见 `wiki\battle\battle-sysmenu.md`）。
signal setting_changed(settings: Dictionary, key: String, previous_value: int)
## 结算窗口进入 `items` 阶段（原生 `Battle_Win_mRun@0x322F0:173-191` 的子状态 2）：
## 经验与金币已经发完、窗口还开着，掉落该在这一刻入包并各推一条 fxt416 入手提示。
## 调用方在这一刻写回掉落（`story.apply_battle_drops`），确认离开战斗时只写回其余结算。
signal settlement_drops(settlement: RefCounted)

const Battle = preload("res://game/battle/combat/battle.gd")
const Resources = preload("res://engine/data/world_resources/world_resources.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const Presentation = preload("res://game/battle/presentation/presentation.gd")
const Settlement = preload("res://game/battle/combat/battle_settlement/battle_settlement.gd")
const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const HitEffect = preload("res://game/battle/presentation/hit_effect/hit_effect.gd")
const Box2Prompt = preload("res://game/field/runtime/box2_prompt/box2_prompt.gd")
const BattlePoses = preload("res://game/battle/combat/battle_poses/battle-poses.tres")
const STEP_SECONDS := 0.05
## 用了道具之后原生状态 21 ITEM2 空跑 16 帧（`Battle_Item2_mRun` 的 `run_counter > 15`）。
const ITEM_FRAMES := 16
## 状态 12 POISON 空跑 16 帧（`Battle_Poison_mRun` 的 `run_counter > 15` 才切 MENU）。
const POISON_FRAMES := 16
## 战斗页触控键（`battle.tscn` 里 `TouchControls` 的子按钮）。键码就是原生 `EFC_mainTouch` 的数值
## （同一个数字在地图页含义不同，所以按本页命名；方向盘与 OK／CLR 沿用负数码）：
## `EFC_mainTouchDRAW:117-123` 画 MON INFO **42** 于 `(25,45)`、CAPTURE **35** 于 `(width−25,45)`；
## `:138-163` 画 AUTO **48** 于 `(n75,n45)`（width>399 时 30／90），`BattleData+24` 置 1 时按
## `GRP_MODE_BRIGHT` 常亮（`BattleCanvas_mKeyPressed:24-27` 也是 48 翻转这个标志）。
enum TouchKey {
	MON_INFO = 42,
	CAPTURE = 35,
	AUTO = 48,
}

## 触控组合（`EFC_mainTouch` 的 style 位掩码）：指令／行动／回位＝方向盘＋OK＋CLR＋三个常驻键，
## 目标／逃跑／入场／道具只留方向盘＋OK＋CLR，说明页只有方向盘＋CLR。
enum TouchStyle {
	COMMAND = 0x63,
	SELECT = 0x23,
	INFO = 0x3,
}

## 战斗提示只有一条文本通道：`Game_infoInit` 推进全局提示栈，`Game_infoDraw` 每条先铺半透明
## 黑底再画字（见 `wiki\ui\message-stack.md`）。战斗侧的调用点见 `Battle_Menu_mKeyPressed`、
## `Battle_Target_mKeyPressed`、`Battle_Capture_Action_mRun`、`Battle_Win_mRun`（饱食度）、
## `Battle_Character_init`（被动／开场）；边界态也走这里，不再单独开浮层。
## 原生状态 28 DIE 的 Box2 页（`Battle_Die_mPaint`）：3「使用%s[%s]复活吗?」、
## 5「使用100元的情报使用费可以复活」、2／6「返回主菜单吗?」、4／8「全部复活了」。
enum DefeatPage { ITEM, FEE, REVIVED, RETURN }
## 原生 `Battle_Monster_procPosition` 的逐帧定位指令（见 `battle_poses.gd`）：
## 攻击／技能帧会把本体摆到「受击者槽 ± 距离」，这就是怪物看起来「走到目标身前」的来源。
func _pose_command(index: int, action: int, frame: int) -> Vector2i:
	if battle == null or index < 0 or index >= battle.balls.size() or battle.balls[index].is_empty():
		return Vector2i.ZERO
	return BattlePoses.command(MonsterAnimation.battle_identity(int(battle.balls[index].species)),
		action, frame)


## 原生 `Battle_Monster_procCurr` 的受击回弹表：`animation_id == 12` 时按受击帧号取值，
## 第 5 帧起回槽（`n4 > 4` → `animation_id = 0`）。我们的一个行动步就是一帧 0.05 秒。
const HIT_RECOIL := [8, 6, 4, 2, 0]
## 原生状态 25 POSITION（`Battle_Position_mRun`）：行动结束后每个对象
## `x = (编队槽 + 当前x) / 2`、`y = (槽y + 当前y) / 2`，即**每帧半程收敛**（整数除法向 0 截断）。
## `run_counter > 10` 才切下一位行动者，所以这段滑回槽位约 11 帧（0.05 秒/帧 ≈ 0.55 秒）。
const RETURN_FRAMES := 11
## 原生 `Battle_Menu_mHide`／`Battle_Taget_mHide` 的淡出帧数上限 7：
## `Object_drawSPRITE` 按 `alpha = 256 − 12 * n` 画，所以最低到 172/256。
const FADE_STEPS := 7
## `common/msg.fxt` 407／408 的正文换色（407 黄 `0xFFFF00`、408 红 `0xF00000`）由翻译资源
## `zh_CN.tres` 内联的 `[color=#RRGGBB]…[/color]` 标记携带（`script\export_text_colors.py`
## 从原生 `#C`／`#P` 的调色板语义展开），所以相克提示直接取记录正文，不再在这里补控制码。
## `Battle._strength`（原生 `Param_attrStrength`）的三档：1 有利、−1 不利、0 无关。
const ATTRIBUTE_ADVANTAGE := 1
const ATTRIBUTE_DISADVANTAGE := -1

## 原生 `Param_atkPASSIVE`（`:87-95`）的「被动发动」提示：先写一行 `"[%s] %s"`
## ——第一个 `%s` 是被动记录名（`Item_datBasic` 类型 31 的 `name_text`，
## 正文在 `common/item_skill.dat` 的 `item_skill.group.<被动号>.name`，与
## `menu/book_skill.gd` 的 `SKILL_TEXT_SOURCE` 同一份文本），第二个是 `JC_fxt2Return(556)` 的正文「发动」。
## 行首 `#P…` 是 `JC_fntSetPALETTE` 的调色板定义、`#C0` 取第 0 号色，两串都由
## `MessageStack.text_segments` 解析。分档看 `v7 = Battle_objINDEX(对象) > 2`：序号 3–5 是我方
## （`Battle_objFIND` 的 `+20650` 链）写 `#PFF0`（`JC_fntSetPALETTE` 的 `(r<<20)|(g<<12)|(16*b)`，
## 即 `0xF0F000` 黄），0–2 的敌方写 `#PF00`（`0xF00000` 红）。
const PASSIVE_NAME_SOURCE := "common/item_skill.dat"
const PASSIVE_NAME_RECORD := "item_skill.group.%d.name"
const PASSIVE_NOTICE_ALLY_COLOR := "#PFF0#C0"
const PASSIVE_NOTICE_ENEMY_COLOR := "#PF00#C0"

var battle: RefCounted
var phase := "loading"
var target := 0
var selected_action := "attack"
var current_step := -1
var _resources: RefCounted
var _assets: Node
var _frame_counts: Dictionary = {}
var _poses: Array[Dictionary] = []
var _auxiliary: Array[Dictionary] = []
## 当前步骤产生的伤害数字；`present` 用过即清，不保留到下一步。
var _pending_popups: Array[Dictionary] = []
## 本次行动已经弹过哪几条相克提示（`Msg.Id.DAMAGE_ADVANTAGE`／`DAMAGE_DISADVANTAGE`）。
## 原生在 `Battle_Skill_init` 里**每个目标**调一次 `Param_dmg2BASIC`、由它推 407／408，
## 而工程把伤害拆到各命中帧上，同一次攻击的多段命中会重复推同一条——这里按「一次行动一条」
## 收住（用户要求：每次攻击只检测并弹出一次）。
var _attribute_reported: Dictionary = {}
## 本次行动已经推过「被动发动」（`Msg.Id.PASSIVE_ACTIVATED`）的对象序号。
## 原生 `Param_atkPASSIVE` 每掷中一次就推一条，工程把一次攻击摊到多个命中帧，
## 同一只的被动在一次行动里只弹一次（与 `_attribute_reported` 同一套收敛）。
var _passive_reported: Dictionary = {}
var _steps: Array = []
var _display_balls: Array = []
var _acting_actor := -1
## 本回合行动真正打的那个目标（原生 `Object_objTARGET` 存进对象的目标号），
## 敌人自动行动时也有效；`Battle_Monster_procPosition` 的落点就用它换算。
var _action_target := -1
var _buttons: Array[Button] = []
## 本次回合的 `Battle_Character_mRun` 的 `run_counter`（0..5）；状态 25 POSITION 收完后归 0。
var _turn_steps := 0
## 状态 25 POSITION 的逐帧收敛：对象序号 → 当前后移量（像素），每个 0.05 秒帧减半。
var _return_offsets: Dictionary = {}
var _return_frame := 0
## 状态 12 POISON 已经空跑的帧数（16 帧后切 MENU）。
var _poison_steps := 0
## 镜头补步的 0.05 秒累计（原生 `Battle_mapCAMERA` 每个游戏帧只走一次）。
var _camera_clock := 0.0
## 受击回弹：目标序号 → 命中发生在第几步。`Field` 每帧按它取 `HIT_RECOIL` 的带符号位移。
var _recoil_start: Dictionary = {}
var _recoil: Dictionary = {}
## 本回合行动里刚被打到 0 的受击者（序号 → true）：原生在命中帧就 `Ball_stdHP`
## 把血扣到 0，但 999 号墓碑要等攻击动作播完（`Battle_Monster_procNext` 收尾切
## POSITION）才换，所以这里先把它们继续按本体绘制。
var _deferred_graves: Dictionary = {}
## 指令／目标窗口期间被淡出的对象（序号 → 原生 `extended_state[541]` 的帧数 0..7）。
var _fade: Dictionary = {}
## 已经写进 `Field` 的步骤，用来避免每帧重复刷新。
var _applied_steps := 0
var _started := false
## 原生 `Battle_Die_mPaint` 的窗口文本取自 `common/msg.fxt`（`Msg.Id`）。
var _closed := false
## 原生 `BattleData + 24`（`BattleCanvas_mKeyPressed:27` 翻转）：**整场战斗持续的 AUTO 开关**，
## 不是一次性的「帮我打一手」。`Battle_Menu_Auto:52-53` 每帧读它（唯一调用点
## `Battle_Menu_mPaint:57`），置 1 时直接替当前行动者选动作，指令菜单因此不再等输入。
var auto_mode := false
## 原生 `BattleData + 25`（`BattleCanvas_mKeyPressed:30-36`）：AUTO 开启提示
## （`Msg.Id.AUTO_BATTLE`）本场只推一次。
var _auto_announced := false
## AUTO／敌方 AI 的轮盘时序：原生 `Battle_Menu_mPaint` 的子状态 0 先把轮盘入场动画完整播完，
## 末尾才调 `Battle_Menu_Auto`；`_auto_pending` 标记「等入场动画结束再选招」，
## `_auto_choice` 暂存选出来的动作与目标。
var _auto_pending := false
var _auto_choice: Dictionary = {}
## 逃跑窗（原生状态 18 RUN）的两段：`_flee_escaped` = 本次判定结果，`_flee_after_close`
## 是关窗后要做的事（`command` 取消回指令窗、`result` 重开窗显示结果、`finish` 成功回地图、
## `position` 失败进回位）。
var _flee_escaped := false
var _flee_after_close := ""
var _pending_command := ""
var selected_item: Dictionary = {}
var _progress: Dictionary = {}
var _presentation: RefCounted
## 胜利结算（原生状态 26）：`Battle_Win_SetResult` 一次算好的经验／金币／掉落，
## 由 `Result` 窗口播放；调用方确认时才用 `apply()` 写回进度。
var settlement: RefCounted
## `Evt_stdSET(3, 物种)` 的事件掉落查询（由 `field_runtime` 接到 `story.event_drop_for`）。
var event_drop: Callable = Callable()
## 本战捕获到的个体（原生 `Ball_stdAddEx` 在战斗内就入包；这里等战斗结束由调用方写回）。
var _captures: Array[Dictionary] = []

## 捕获演出的现场：演出开始前被捕获对象那一整份球（结果窗与 fxt478 提示要它的物种／性格／品级）。
## `_capture_caught` = 本次判定结果；`_capture_result_pending` = 动作播完要开结果窗。
var _capture_ball: Dictionary = {}
var _capture_caught := false
var _capture_result_pending := false
## 原生状态 28 DIE 的 Box2 页（见 `DefeatPage`）；`_defeat_previous` 是「返回主菜单吗?」
## 选「否」时退回的那一页，`_defeat_after_close` 是关窗后要做的事（继续战斗／回标题）。
var _defeat_page := DefeatPage.ITEM
var _defeat_previous := DefeatPage.ITEM
var _defeat_after_close := ""
## 本战用掉的捕获球（原生 `Item_stdDel` 在判定前就扣）。
var _used_items: Dictionary = {}
## 当前步骤要播的捕获特效（`b_effect` 37／38），`present` 用过后清空。
var _pending_effect: Dictionary = {}
## 本步要挂的 `b_effect` 闪光（`{"slot": 槽, "action": 动作}`）：道具的 27／28、复活 29。
var _pending_flashes: Array = []
## 战斗内系统菜单（原生状态 30 CLEAR → 31／32／33）是否建好；建不好就只提示、不开覆盖层。
var _sys_ready := false


func _ready() -> void:
	$ActionTimeline.animation_finished.connect(_action_finished)
	$TouchControls.key_pressed.connect(_touch_command)
	$Flee.chosen.connect(_flee_chosen)
	$Flee.confirmed.connect(_flee_confirmed)
	$Flee.transition_finished.connect(_flee_transition_finished)
	$Actions.command_finished.connect(_command_finished)
	$Actions.intro_finished.connect(_wheel_intro_finished)
	$Field.target_pressed.connect(_target_pressed)
	$Field.target_accepted.connect(_target_accepted)
	$Info.closed.connect(func():
		if phase == "info":
			phase = "target"
			_refresh_display())
	$Items.cancelled.connect(_next)
	$Items.chosen.connect(_item_chosen)
	$CaptureBox.confirmed.connect(_capture_box_confirmed)
	$CaptureBox.transition_finished.connect(_capture_box_finished)
	$Defeat.chosen.connect(_defeat_chosen)
	$Defeat.confirmed.connect(_defeat_confirmed)
	$Defeat.transition_finished.connect(_defeat_transition_finished)
	$SysMenu.closed.connect(_sys_menu_closed)
	$SysMenu.title_requested.connect(_exit_to_title)
	$SysMenu.setting_changed.connect(setting_changed.emit)
	if battle != null and not _started:
		start(battle, _resources, _assets)
	_refresh_display()


func start(model: RefCounted, resources: RefCounted = null, assets: Node = null,
		progress: Dictionary = {}) -> bool:
	battle = model
	_resources = resources
	_assets = assets if assets != null else get_node_or_null("/root/AssetCatalog")
	_progress = progress.duplicate(true)
	$Info.hide()
	$Items.hide()
	$Result.hide()
	$Result.stage = "closed"
	$CaptureBox.hide()
	$Defeat.hide()
	_defeat_page = DefeatPage.ITEM
	_defeat_previous = DefeatPage.ITEM
	_defeat_after_close = ""
	$Actions.show()
	$Field.reset_hud()
	settlement = null
	_captures.clear()
	_used_items.clear()
	_capture_ball.clear()
	_capture_caught = false
	_capture_result_pending = false
	_pending_effect.clear()
	_closed = false
	_auto_announced = false
	_auto_pending = false
	_auto_choice = {}
	# 原生 `Battle_Win_SetResult:373` 把 `BattleData + 24` 起 0x60 字节清零，
	# 所以新一场从手操开始。
	auto_mode = false
	_started = true
	$ActionTimeline.stop()
	phase = "loading"
	# 原生没有「载入本战动作」这类提示（`Game_infoInit` 的战斗调用点里没有加载分支），所以不上屏。
	_frame_counts.clear()
	_poses.clear()
	_auxiliary.clear()
	_steps.clear()
	_display_balls.clear()
	_turn_steps = 0
	_applied_steps = -1
	_poison_steps = 0
	_camera_clock = 0.0
	_recoil_start.clear()
	_recoil.clear()
	_deferred_graves.clear()
	_fade.clear()
	if battle == null or not is_instance_valid(_assets):
		_boundary("世界资源尚未初始化")
		return false
	_presentation = Presentation.new(_assets)
	if _resources == null:
		_resources = Resources.new()
		if not _resources.initialize(_assets):
			_boundary(_resources.last_error)
			return false
	$Field.configure(_assets)
	$Field.reset_camera()
	$SysMenu.reset()
	_sys_ready = $SysMenu.configure(_assets)
	_display_balls = battle.balls.duplicate(true)
	if not battle.support_error().is_empty():
		_boundary(battle.support_error())
		return false
	for index in range(battle.balls.size()):
		var ball: Dictionary = battle.balls[index]
		if ball.is_empty():
			_poses.append({})
			continue
		var species := int(ball.species)
		if not BattleSpeciesTable.has(Battle.combat_species(species)):
			_boundary("本战角色缺少动作分段：%d" % species)
			return false
		ball.direction = 0 if index < 3 else 1
		# 待机／受击必播；攻击段、技能段与分身段按该物种的导出数据取（`battle-species.tres`），
		# 所以 20／21 乃至物种自带的 22、23 都由数据决定，不再按物种写死。
		var actions := [AniAction.Clip.IDLE, AniAction.Clip.DAMAGED]
		for action: int in BattleSpeciesTable.clip_actions(Battle.combat_species(species)):
			actions.append(action)
		for action: int in actions:
			if not _load_action(species, action):
				return false
		_poses.append({"action": AniAction.Clip.IDLE, "frame": 0})
	_display_balls = battle.balls.duplicate(true)
	_next()
	return phase != "boundary"


static func animation_path(species: int) -> String:
	return MonsterAnimation.battle_identity(species)


func _load_action(species: int, action: int) -> bool:
	var identity := animation_path(species)
	var scene_path := MonsterAnimation.scene_path(identity)
	if not ResourceLoader.exists(scene_path):
		_boundary("怪物 Scene 无法加载：%s" % scene_path)
		return false
	# 帧数由 `MonsterAnimation` 从 ANI 场景状态里一次性读出并静态缓存，
	# 不再为「物种 × 动作」各实例化一份场景。
	var count := int(MonsterAnimation.frame_counts(identity).get(action, 0))
	# 动作不在该 ANI 里就不登记帧数：真要用到它时 `act()` 会报「缺少有效动画帧数」，
	# 而不会被这一条无关动作挡住整场战斗（物种 106 的分身动作 22／23 就是原 ANI 里没有的）。
	if count <= 0:
		return true
	if not _frame_counts.has(species):
		_frame_counts[species] = {}
	_frame_counts[species][action] = count
	return true


func _start_timeline() -> void:
	var timeline: AnimationPlayer = $ActionTimeline
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = maxf(STEP_SECONDS, _steps.size() * STEP_SECONDS)
	var track := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(track, NodePath("."))
	for index in _steps.size():
		clip.track_insert_key(track, index * STEP_SECONDS, {"method": "_apply_step", "args": [index]})
	library.add_animation("action", clip)
	_add_return_clip(library)
	timeline.stop()
	if timeline.has_animation_library(&""):
		timeline.remove_animation_library(&"")
	timeline.add_animation_library(&"", library)
	timeline.play("action")


## 状态 25 的滑回片段：`x = (槽 + x) / 2` 每 0.05 s 推一帧，共 `RETURN_FRAMES` 帧。
func _add_return_clip(library: AnimationLibrary) -> void:
	var glide := Animation.new()
	glide.length = RETURN_FRAMES * STEP_SECONDS
	var glide_track := glide.add_track(Animation.TYPE_METHOD)
	glide.track_set_path(glide_track, NodePath("."))
	for index in range(1, RETURN_FRAMES + 1):
		glide.track_insert_key(glide_track, index * STEP_SECONDS,
			{"method": "_apply_return_step", "args": [index]})
	library.add_animation("return", glide)


## 没有动作步的回合（逃跑失败）直接进 25：时间轴里还没有 return 片段，先补一条再播。
func _play_return_timeline() -> void:
	var timeline: AnimationPlayer = $ActionTimeline
	if not timeline.has_animation("return"):
		var library := AnimationLibrary.new()
		_add_return_clip(library)
		if timeline.has_animation_library(&""):
			timeline.remove_animation_library(&"")
		timeline.add_animation_library(&"", library)
	timeline.play("return")


func _apply_step(index: int) -> void:
	if phase == "action" and not _closed and index > current_step:
		current_step = index
		_render_step(_steps[index])


func _action_finished(_name: StringName) -> void:
	if phase == "action" and not _closed:
		_auxiliary.clear()
		_recoil_start.clear()
		_recoil.clear()
		# 攻击动画到此播完（原生 `Battle_Monster_procNext` 收尾 → POSITION 入场），阵亡的受击者现在才换墓碑。
		_deferred_graves.clear()
		_applied_steps = -1
		if _capture_result_pending:
			_open_capture_result()
			return
		_state_25()


## 原生状态 25 POSITION 的入场：`BattleCanvas_SetNext(BATTLE_STATE_POSITION)` →
## `Battle_Position_init` → `Battle_objNextPosition`。
## 入场**不写回槽位**：活着的战斗对象走 `Object_objPOS(obj, obj->x, 0x18 + obj->y, 0, 0)`——
## 保留 x，只把 `Battle_Monster_procPosition` 留下的临时绘制偏移（`a4`=0x14／`a5`=0x18）抹掉；
## 写回槽位的那一支（`Battle_objGetPosition2(槽, 0)` ＋ `Object_objPOS(槽x, 槽y, …)` ＋
## `Object_objANI(obj, 19)`）是按 `extended_state` 里的帧描述符判定的另一支。
## 回槽本身是 `Battle_Position_mRun` 每帧 `x = (槽 + 当前x) / 2`、`y = (槽y + 当前y) / 2`
## （整数除法向 0 截断）的**半程收敛**，`run_counter > 10` 才切下一位——所以是逐帧滑回去的动画，
## 不是瞬移。动作切换由 `Battle_Monster_procNext`（14／15 播完 → `Object_objANI(obj, 0)`）
## 与 `Object_objANI(obj, 19)` 负责，19 映射 ANI 动作 0（待机），于是滑回期间是待机姿势。
func _state_25() -> void:
	_return_offsets.clear()
	_return_frame = 0
	# 原生 `Battle_Position_mRun` 的被动 58 分支：状态 25 时对「HP 0 且还没用过」的队员
	# `Battle_Die_Revival(obj, 2, 值)`（HP = 上限 × 值 / 100、SP 回满）。
	var revived: int = battle.revive_by_passive()
	if revived >= 0:
		_deferred_graves.erase(revived)
	for index in range(mini(6, _display_balls.size())):
		if _display_balls[index].is_empty():
			continue
		# 起点 = 当前画出来的偏移（攻击帧摆到受击者身前的那份也算在内）。
		_return_offsets[index] = $Field.actor_shift(index)
		_poses[index] = {"action": AniAction.Clip.IDLE, "frame": 0}
	phase = "position"
	_play_return_timeline()
	_refresh_display()


## 状态 25 的一帧：`x = (槽 + x) / 2`、`y = (槽y + y) / 2`（原生整数除法，向 0 截断）。
func _apply_return_step(frame_number: int) -> void:
	if phase != "position" or _closed:
		return
	_return_frame = frame_number
	for index: int in _return_offsets.keys():
		var offset: Vector2 = _return_offsets[index]
		_return_offsets[index] = Vector2(float(int(offset.x / 2.0)), float(int(offset.y / 2.0)))
	# 原生要 `run_counter > 10` 才切下一位，所以恰好归零也不提前结束。
	if _return_frame >= RETURN_FRAMES:
		_finish_return()
		return
	_refresh_display()


func _finish_return() -> void:
	$ActionTimeline.stop()
	_return_offsets.clear()
	_return_frame = 0
	# 全部对象已经回到编队槽，下一回合的后移从 0 重新数。
	_turn_steps = 0
	_applied_steps = -1
	if _begin_poison():
		return
	_next()


## 原生顺序是 POSITION → CHARACTER → **POISON** → MENU：`Battle_Poison_init` 先在切进
## MENU 之前结算 `Param_dmgPOISON`（三段毒槽），`Battle_Poison_mRun` 再空跑 16 帧
## （0.8 秒）才 `SetNext(MENU)`。所以中毒的怪轮到它行动时先掉血、再出指令窗口。
func _begin_poison() -> bool:
	if battle == null or battle.result != null or battle.actor < 0:
		return false
	var index := int(battle.actor)
	var response: Dictionary = battle.settle_poison(index)
	var damage := int(response.get("damage", 0))
	if damage <= 0:
		return false
	_display_balls = battle.balls.duplicate(true)
	# `Param_dmgNUMBER` 扣血后给受击方 `Object_objANI(12)`，所以毒发的这一跳也是受击动作。
	_poses[index] = {"action": AniAction.Clip.DAMAGED, "frame": 0, "revision": _poison_steps + 1}
	_pending_popups = [{"target": index, "damage": damage, "critical": false}]
	_poison_steps = 0
	_camera_clock = 0.0
	phase = "poison"
	_clear_buttons()
	# 毒发的这一跳在原生是场上数字（`Battle_Poison_init` → `Param_dmgPOISON` → `Param_dmgNUMBER`
	# 的 kind 14 对象），不进提示栈，也没有对应的文字提示；数字由 `_pending_popups` 画。
	_refresh_display()
	return true


func _finish_poison() -> void:
	_poison_steps = 0
	if _closed:
		return
	if battle.result == null:
		var index := int(battle.actor)
		if index >= 0 and not battle.balls[index].is_empty() and int(battle.balls[index].hp) <= 0:
			# 被毒打倒：原生走 `BattleCanvas_SetNext(POSITION)` 让状态 25 处理阵亡并换下一位。
			battle.select_actor()
	_next()


func _exit_tree() -> void:
	_closed = true


## 回合开始的后移跟指令图标动画同步，需要逐帧重排才会动起来（只在按键时刷新是看不到的）。
func _process(delta: float) -> void:
	if not _started or _closed or battle == null:
		return
	if phase == "command":
		var steps := _run_counter()
		if steps != _applied_steps:
			_applied_steps = steps
			_refresh_display()
			return
	# 状态 26 的进场：底部友方怪物信息按原生平方序列滑出（0.05 秒一帧），滑完才开窗口。
	if phase == "result" and not $Field.hud_exited():
		_camera_clock += delta
		if _camera_clock >= STEP_SECONDS:
			_camera_clock = 0.0
			$Field.advance_hud_exit()
		return
	# 状态 12 POISON：`Battle_Poison_mRun` 每帧只跑 `Object_procRUN` + `Battle_mapFOCUS`，
	# `run_counter > 15` 才切 MENU。
	if phase == "poison":
		_camera_clock += delta
		if _camera_clock >= STEP_SECONDS:
			_camera_clock = 0.0
			_poison_steps += 1
			if _poison_steps >= POISON_FRAMES:
				_finish_poison()
		return
	# 行动期间镜头跟着 ActionTimeline 的每一步走；POSITION 的滑回也由时间轴逐帧驱动；
	# 其余阶段按原生的 0.05 秒一帧补步，让焦点与淡出都走到自己该在的位置。
	if phase in ["action", "position"] or ($Field.camera_settled() and _fade_settled()):
		return
	_camera_clock += delta
	if _camera_clock < STEP_SECONDS:
		return
	_camera_clock = 0.0
	_refresh_display()


func _next() -> void:
	phase = "command"
	_auto_pending = false
	_auto_choice = {}
	for index in range(battle.balls.size()):
		if battle.balls[index].is_empty():
			continue
		battle.balls[index].direction = 0 if index < 3 else 1
		_poses[index] = {"action": AniAction.Clip.IDLE, "frame": 0}
	_display_balls = battle.balls.duplicate(true)
	_clear_buttons()
	if battle.result != null:
		phase = "result"
		if battle.result == "won":
			# 先按真实阵容摆好 HUD（原生进 WIN 时 HUD 画的是真实队伍），再开始滑出。
			_refresh_display()
			_begin_victory()
			return
		if battle.result == "lost":
			# 原生状态 28 DIE：`Battle_Die_init` 按复活道具决定第一页（子状态 1／5），
			# 之后 3／2 或 5／7／6、4／8 在同一个 Box2 窗口里换页；确认「返回主菜单吗?」
			# 走 `Game_out()` 回标题，复活则 `SetNext(POSITION)` 继续打。
			_open_defeat()
			return
		elif battle.result == "escaped":
			_set_note(_assets.text_message(Msg.SOURCE, Msg.Id.FLEE_SUCCEEDED) + " · 确认返回地图")
			_button(200, "确认结果", _finish)
		else:
			_set_note("战斗结束 · 确认结果")
			_button(200, "确认结果", _finish)
	elif not battle.get_manual() or auto_mode:
		# 原生 `Battle_Menu_mPaint` 子状态 0：轮盘先完整播入场（7 帧），末尾才 `Battle_Menu_Auto`。
		# 所以 AUTO／敌方 AI 也先摆出轮盘，等入场动画结束后再选招，之后同样走
		# 接受（1–5）／退出（6–10）动画与淡出。
		_auto_pending = true
		_command_buttons()
	else:
		phase = "command"
		_command_buttons()
	_refresh_display()


## 原生状态 26 的进场顺序：胜利判定后战斗对象不再更新（`Battle_Win_mPaint` 只 blit 冻结底图），
## 底部友方怪物信息按 `BattleCanvas_mon_DrawUI` 的平方序列滑出并隐藏，右侧常驻触控键
## （OK／MON INFO／AUTO／CAPTURE／CLR）由 `EFC_mainTouchINIT` 全部撤掉，滑完才开 228×240 窗口。
func _begin_victory() -> void:
	_clear_buttons()
	$Actions.hide()
	$Field.freeze_scene(true)
	$Field.hud_exit_finished.connect(_open_result, CONNECT_ONE_SHOT)
	$Field.start_hud_exit()
	if $Field.hud_exited():
		_open_result()


## 原生状态 26 WIN：`Battle_Win_init` 先 `Battle_Win_SetResult` 算好经验／金币／掉落，
## 再载入 `common/ui_window.fbm` 开 228×240 窗口；标题按 `Battle_Win_Draw` 取
## `JC_fxt2Return(13)`（一般战斗）或 `(14)`（`GameState == GAME_STATE_FIELD`，即剧情事件战）。
## 掉落在窗口进入 `items` 阶段时才交给调用方（原生子状态 2），不是开窗那一刻。
func _open_result() -> void:
	if phase != "result" or battle == null or battle.result != "won" or settlement != null:
		return
	settlement = Settlement.new(battle, _progress, _presentation.catalog,
		battle._random, auto_mode, event_drop)
	$Result.finished.connect(_finish, CONNECT_ONE_SHOT)
	$Result.items_reached.connect(_result_items_reached, CONNECT_ONE_SHOT)
	if not $Result.open(settlement, _presentation, _progress,
			13 if battle.allow_flee else 14):
		_boundary("战斗结算窗口无法打开")


func _result_items_reached() -> void:
	if settlement == null:
		return
	settlement_drops.emit(settlement)


func _command_buttons() -> void:
	for command: Array in [[57, "攻击", "attack"], [153, "技能", "skill"],
			[249, "防御 ↑", "guard"], [345, "逃跑", "flee"], [200, "道具", "item"]]:
		_button(command[0], command[1], _request_command.bind(command[2]))


func _request_command(action: String) -> void:
	if phase != "command":
		return
	# 原生 `Battle_Menu_mKeyPressed` 只在子状态 1（入场动画已播完）接受按键；AUTO／敌方 AI
	# 的入场动画期间由 `_wheel_intro_finished` 选招，这里不再让手动输入插队。
	if _auto_pending:
		return
	if action == "skill" and not Battle.skill_available(battle.balls[battle.actor]):
		_choose(action)
		return
	if action == "flee" and not battle.allow_flee:
		_unsupported("此事件战逃跑")
		return
	_pending_command = action
	_auto_pending = false
	_auto_choice = {}
	phase = "command_exit"
	$Actions.select_command(action)
	_refresh_display()


func _command_finished() -> void:
	if phase != "command_exit" or _closed:
		return
	var action := _pending_command
	_pending_command = ""
	phase = "command"
	# AUTO／敌方 AI 的选招在入场结束时就已经定了目标（原生随后照常进 TARGET 并由 AUTO 确认），
	# 这里直接把那份目标交给行动解析；轮盘的接受／退出／淡出已经播完。
	if not _auto_choice.is_empty():
		var choice := _auto_choice
		_auto_choice = {}
		_run(String(choice.action), int(choice.target))
		return
	if action == "item":
		_open_items("item")
	elif action == "flee":
		_choose_flee()
	else:
		_choose(action)


## 轮盘入场动画（`obj/b_icon2` 动作 0）播完：原生 `Battle_Menu_mPaint` 的子状态 0 在这一刻
## 调 `Battle_Menu_Auto`，所以 AUTO／敌方 AI 与玩家看到的是同一套轮盘与退场动画。
func _wheel_intro_finished() -> void:
	if not _auto_pending or phase != "command" or _closed:
		return
	if battle == null or battle.result != null:
		return
	_auto_pending = false
	_auto_choice = battle.auto_action()
	var action := String(_auto_choice.action)
	_pending_command = action
	phase = "command_exit"
	$Actions.select_command(action)
	_refresh_display()


func _choose(action: String) -> void:
	if phase != "command":
		return
	var ball: Dictionary = battle.balls[battle.actor]
	if action == "skill" and not Battle.skill_available(ball):
		# 指令窗里的不可用提示：原生同类反馈经 `Game_infoInit` 进栈
		# （`Battle_Menu_mKeyPressed` 是它的调用点之一），所以走提示栈而不是战斗面板。
		_set_note("SP不足。" if ball.sp <= 0 else "技能被封印。" if
			ball.statuses.has(7) else "技能冷却尚未结束。")
		_refresh_display()
		return
	selected_action = action
	if action == "guard" or (action == "skill" and Battle.combat_species(int(ball.species)) == 62):
		_run(action, battle.targets()[0])
		return
	phase = "target"
	target = _target_candidates()[0]
	_clear_buttons()
	_refresh_display()


func _unsupported(feature: String) -> void:
	# 这些分支在原生流程里已实现，没有对应的 `Game_infoInit` 调用点；提示仍需可见，
	# 所以沿用全局提示栈（面板只留给边界态）。
	_set_note("%s尚未接通；未消耗行动、物品或保存。" % feature)
	_refresh_display()


## 原生 `Battle_Menu_mKeyPressed` 的 `case 0`（CLR，`a1 == -16`）：子状态 1 → 2、
## 菜单动作码置 8，`Battle_Menu_mRun` 随即 `SetNext(BATTLE_STATE_CLEAR, 0)`——
## 也就是 CLR 在指令菜单里开出「设定」4 项列表（状态 30），再由它进 31／32／33。
func _open_sys_menu() -> void:
	if phase != "command" or _closed:
		return
	if not _sys_ready:
		_unsupported("战斗内系统菜单")
		return
	phase = "sys"
	_clear_buttons()
	$Actions.hide()
	$SysMenu.open()
	_refresh_display()


## 覆盖层关窗动画结束后交回控制权：原生 `Battle_Clear_mRun` 的返回码 0
## （`SetNext(BATTLE_STATE_MENU, 0)`）回到的是指令菜单，`Battle_Menu_init` 重新摆好图标。
func _sys_menu_closed() -> void:
	if _closed:
		return
	phase = "command"
	$Actions.show()
	_command_buttons()
	_refresh_display()


func _touch_command(key: int) -> void:
	var keys := {TouchCode.Key.OK: "Enter", TouchCode.Key.BACK: "Escape",
		TouchCode.Pad.UP: "ArrowUp", TouchCode.Pad.DOWN: "ArrowDown",
		TouchCode.Pad.LEFT: "ArrowLeft", TouchCode.Pad.RIGHT: "ArrowRight"}
	if keys.has(key):
		press(keys[key])
	elif key == TouchKey.AUTO and phase in ["command", "action", "target"]:
		# 原生 `BattleCanvas_mKeyPressed:27` 在任意战斗状态下都翻转 `BattleData + 24`，
		# 所以 AUTO 从指令窗、行动中、目标窗都能开／关；开着时下一手由 `_next()` 直接替玩家出招。
		auto_mode = not auto_mode
		if auto_mode:
			if not _auto_announced:
				_auto_announced = true
				MessageStack.say_record(Msg.Id.AUTO_BATTLE)
			if phase in ["command", "target"]:
				_next()
			else:
				_refresh_display()
		else:
			_auto_pending = false
			_refresh_display()
	elif phase == "command":
		if key == TouchKey.MON_INFO:
			selected_action = "info"
			_open_target()
		elif key == TouchKey.CAPTURE:
			if battle.allow_flee:
				_open_items("capture")
			else:
				_unsupported("此事件战捕获")


func _change_target(change: int) -> void:
	var candidates: Array = _target_candidates()
	target = candidates[posmod(candidates.find(target) + change, candidates.size())]
	_refresh_display()


func press(key: String) -> void:
	if _closed:
		return
	if phase == "sys":
		$SysMenu.handle_key(key)
		return
	var confirm := key in ["Enter", "Space"]
	if phase == "items":
		$Items.handle_key(key)
	elif phase == "info":
		$Info.handle_key(key)
	elif phase == "encounter" and (confirm or key == "Escape"):
		_abandon()
	elif phase == "defeat":
		# 原生状态 28 DIE：方向盘左右换是／否，OK 落键（确定页只有一颗键）。
		if key in ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]:
			$Defeat.move_selection(-1 if key in ["ArrowLeft", "ArrowUp"] else 1)
		elif confirm:
			$Defeat.accept()
	elif phase == "flee":
		if $Flee.is_transitioning():
			return
		if key == "Escape":
			$Flee.cancel()
		elif key in ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]:
			$Flee.move_selection(-1 if key in ["ArrowLeft", "ArrowUp"] else 1)
		elif confirm:
			$Flee.accept()
	elif phase == "boundary" and (confirm or key == "Escape"):
		_boundary_exit()
	elif phase == "capture_result":
		# 原生 `Battle_Capture_Action_mKeyPressed`：只有结果窗稳态时 OK 才关窗（相位 4 → -1）。
		if confirm and not $CaptureBox.is_transitioning():
			$CaptureBox.close_window()
	elif phase == "result":
		if settlement != null:
			$Result.handle_key(key)
		elif not $Field.hud_exited():
			# 原生状态 26 子状态 0（开窗前）不响应确认：滑出动画期间按确认不能直接回地图。
			pass
		elif confirm:
			# 结算模型没建起来（`_open_result` 的前置条件不成立，或 `$Result.open()` 被拒收）：
			# 原生状态 26 没有「不结算就离开」这一支，所以显式落到边界页，不许静默 `_finish()`
			# 把这一战的奖励吞掉——那会让「结算窗口没出现」变成「什么都没发生就回了野外」。
			_boundary("战斗结算窗口未打开")
	elif phase == "command":
		if key == "Escape":
			_open_sys_menu()
		elif confirm:
			_request_command("attack")
		elif key == "ArrowLeft":
			_request_command("skill")
		elif key == "ArrowUp":
			_request_command("guard")
		elif key == "ArrowRight":
			_request_command("flee")
		elif key == "ArrowDown":
			_request_command("item")
	elif phase == "target":
		if key in ["ArrowLeft", "ArrowUp"]:
			_change_target(-1)
		elif key in ["ArrowRight", "ArrowDown"]:
			_change_target(1)
		elif confirm:
			_confirm_target()
		elif key == "Escape":
			if selected_action in ["item", "capture"]:
				_open_items(selected_action, $Items.playback_state())
			else:
				_next()


func _target_candidates() -> Array[int]:
	if selected_action not in ["info", "item", "capture"]:
		return battle.targets()
	var output: Array[int] = []
	for index in battle.balls.size():
		var ball: Dictionary = battle.balls[index]
		if ball.is_empty():
			continue
		if selected_action == "item" and index < 3:
			continue
		if selected_action == "capture" and index >= 3:
			continue
		# 道具要能对倒下的同伴用（复活道具就是索引 17／18 那两件，`Ball_stdUse` 对它们的
		# 「HP 非 0」检查是反过来用的），所以只有情报／捕获跳过倒下的对象。
		if selected_action != "item" and int(ball.hp) <= 0:
			continue
		output.append(index)
	return output


func _open_target() -> void:
	var candidates := _target_candidates()
	if candidates.is_empty():
		_next()
		_unsupported("当前指令没有可选目标")
		return
	target = candidates[0]
	phase = "target"
	_clear_buttons()
	_refresh_display()


func _target_pressed(index: int) -> void:
	if phase != "target" or not _target_candidates().has(index):
		return
	if target == index:
		_confirm_target()
	else:
		target = index
		_refresh_display()


func _confirm_target() -> void:
	phase = "target_exit"
	_refresh_display()
	$Field.accept_target(target)


func _target_accepted(index: int) -> void:
	if phase != "target_exit" or _closed or index != target:
		return
	phase = "target"
	if selected_action == "info":
		phase = "info"
		$Info.open_monster(battle.balls[target], _presentation)
		_refresh_display()
	elif selected_action == "capture":
		_run_capture()
	elif selected_action == "item":
		_use_item()
	else:
		_run(selected_action, target)


## 原生 `Battle_Target_mKeyPressed` 的确认分支：`Ball_stdUseEx`（内部 `Ball_stdUse`）
## 先算效果与扣道具，再按返回码选 `b_effect` 动作：1／15／16／17 → 27、3 → 28、5 → 27＋28、
## 9 → 先 `Battle_Die_Revival(obj, 1, 0)` 再 29。返回 0／2／4／6／… 的那几支不推进状态，
## 所以「HP 已满」这类结果只是显示 msg.fxt 482／483／484，道具不消耗、仍停在选目标。
func _use_item() -> void:
	phase = "target"
	var response: Dictionary = battle.use_item(selected_item, target)
	if not response.get("ok", false):
		# 未接通的效果分支只提示、不动战场（原生这些分支也不会消耗道具）。
		_unsupported(str(response.get("error", "道具使用")))
		return
	var code := int(response.get("code", 0))
	# 原生 `Battle_Target_mKeyPressed` 是 `Game_infoInit` 的调用点之一：道具结果的记录
	# （msg.fxt 482／483／484 等）由 `_item_message` 取出后进提示栈。
	_set_note(_item_message(code))
	# 扣道具只看 `Ball_stdUse` 的 `v6`：经验窗口、随机生成等分支也要扣，并不止会播特效的那几种。
	var item_id := int(selected_item.get("id", -1))
	if bool(response.get("consumed", false)) and item_id >= 0:
		_used_items[item_id] = int(_used_items.get(item_id, 0)) + 1
	# 原生 switch 只处理 0..17；18（吃不下了）不推进状态，只弹 495，仍停在选目标。
	if not [ItemEffect.Code.HP, ItemEffect.Code.SP, ItemEffect.Code.BOTH, ItemEffect.Code.REVIVED,
			ItemEffect.Code.CURED, ItemEffect.Code.FEEL_GOOD, ItemEffect.Code.FEEL_BAD,
			ItemEffect.Code.FOOD_RESTORED].has(code):
		_refresh_display()
		return
	_begin_item_action(code)


## 原生使用了道具之后进状态 21 ITEM2：`Battle_Item2_mRun` 空跑 `Object_procRUN`
## ＋`Battle_mapFOCUS` 16 帧（0.8 秒，特效在这段时间里播完），然后 `SetNext(POSITION)`；
## `Battle_Item2_mPaint` 只画场地，不画窗口。这里用同样的 16 步空步驱动，
## 第 0 步把 `b_effect` 挂在目标身上。
func _begin_item_action(code: int) -> void:
	phase = "action"
	_clear_buttons()
	_acting_actor = battle.actor
	_action_target = target
	_steps = []
	for step in ITEM_FRAMES:
		var frame: Dictionary = {"actor": battle.actor, "action": AniAction.Clip.IDLE,
			"frame": 0, "hits": []}
		if step == 0:
			# code 5（HP＋SP 一起回）在原生是连着建两个特效对象（28 与 27）。
			frame["flash"] = []
			if code in [ItemEffect.Code.HP, ItemEffect.Code.BOTH, ItemEffect.Code.FEEL_GOOD,
					ItemEffect.Code.FEEL_BAD, ItemEffect.Code.FOOD_RESTORED]:
				frame["flash"].append({"slot": target, "action": HitEffect.ITEM_HP_ACTION})
			if code in [ItemEffect.Code.SP, ItemEffect.Code.BOTH]:
				frame["flash"].append({"slot": target, "action": HitEffect.ITEM_SP_ACTION})
			# code 5（HP＋SP 一起回）在原生是连着建两个特效对象（28 与 27）；治疗异常状态
			# （`Ball_stdUse` 返回 7）在 `Battle_Target_mKeyPressed` 里走 `LABEL_25`，与复活同为动作 29。
			if code in [ItemEffect.Code.REVIVED, ItemEffect.Code.CURED]:
				frame["flash"].append({"slot": target, "action": HitEffect.REVIVE_ACTION})
			if code == ItemEffect.Code.REVIVED:
				# 原生状态 21 之后进 POSITION 时 `Battle_objANI(obj, 0)` 把复活的对象切回待机，
				# 所以这里直接把显示动作换成待机，不留墓碑。
				_deferred_graves.erase(target)
		_steps.append(frame)
	_display_balls = battle.balls.duplicate(true)
	current_step = 0
	_recoil_start.clear()
	_recoil.clear()
	_fade.clear()
	selected_item = {}
	_render_step(_steps[0])
	_start_timeline()


## `Ball_stdUseEx` 的返回码 → 提示文本。拼装规则（HP／SP 前缀、481 的百分比）与其他
## 调用方共用 `ItemEffect.describe`，这里只把记录号接到本视图的文本源。
func _item_message(code: int) -> String:
	return ItemEffect.describe(code, selected_item.get("detail_slots", []),
		func(id: int) -> String: return _assets.text_message(Msg.SOURCE, id))


## 捕获执行：原生 MENU → CAPTURE_ITEM（bag 4）→ CAPTURE_HIDE → CAPTURE_ACTION。
## 判定与步骤都在 `battle.capture`，这里只管扣球、演出与把入包记录带给调用方。
## 原生在 `Battle_Capture_Action_IsCapture` 里先 `Item_stdDel(item, 1, 1)`，判定失败也照样消耗。
func _run_capture() -> void:
	if phase in ["action", "result", "boundary"] or _closed:
		return
	phase = "action"
	_clear_buttons()
	_acting_actor = battle.actor
	_action_target = target
	# 捕获成功时敌人在结果帧才消失，所以这 0.05 秒一步的演出从动作前的快照开始。
	var shown: Array = _display_balls.duplicate(true)
	# 目标可能在判定成功时就被 `battle.capture` 清掉，所以球要先把整份快照存下来：
	# 入包提示（fxt478）与结果窗都要它的物种、性格与品级。
	_capture_ball = shown[target].duplicate(true) if target >= 0 and target < shown.size() else {}
	var response: Dictionary = battle.capture(selected_item, target)
	if not response.get("ok", false):
		_boundary(str(response.get("error", "原捕获不受支持")))
		return
	_steps = response.steps
	_capture_caught = bool(response.get("caught", false))
	_capture_result_pending = true
	_display_balls = shown
	current_step = 0
	_recoil_start.clear()
	_recoil.clear()
	_deferred_graves.clear()
	_attribute_reported.clear()
	_passive_reported.clear()
	_fade.clear()
	if not response.record.is_empty():
		_captures.append(response.record)
	var item_id := int(selected_item.get("id", -1))
	if item_id >= 0:
		_used_items[item_id] = int(_used_items.get(item_id, 0)) + 1
	selected_item = {}
	MonsterAnimation.warm("hero/h_b_01")
	$Field.capture_begin(target)
	_render_step(_steps[0])
	_start_timeline()


func _open_items(kind: String, previous: Dictionary = {}) -> void:
	selected_action = kind
	phase = "items"
	_clear_buttons()
	$Items.open_items(kind, _progress, _presentation, previous)
	_refresh_display()


func _item_chosen(item: Dictionary) -> void:
	if phase != "items" or _closed:
		return
	selected_item = item
	_open_target()


func _run(action: String, chosen_target: int) -> void:
	if phase in ["action", "result", "boundary"] or _closed:
		return
	phase = "action"
	_clear_buttons()
	_acting_actor = battle.actor
	_action_target = chosen_target
	var before: Array = battle.balls.duplicate(true)
	var response: Dictionary = battle.act(action, chosen_target, _frame_counts)
	if not response.get("ok", false):
		_boundary(str(response.get("error", "原行动不受支持")))
		return
	_steps = response.steps
	_display_balls = battle.balls.duplicate(true)
	for index in range(before.size()):
		if before[index].is_empty():
			continue
		_display_balls[index].hp = before[index].hp
		_display_balls[index].statuses = before[index].statuses.duplicate(true)
		_display_balls[index].direction = before[index].direction
		_display_balls[index].speed = before[index].speed if index != _acting_actor else battle.balls[index].speed
	current_step = 0
	_recoil_start.clear()
	_recoil.clear()
	_deferred_graves.clear()
	_attribute_reported.clear()
	_passive_reported.clear()
	# 离开 MENU／TARGET 时原生用 `mHide(0)` 把所有人清零。
	_fade.clear()
	_render_step(_steps[0])
	_start_timeline()


func _render_step(step: Dictionary) -> void:
	_poses[int(step.actor)] = {"action": int(step.action), "frame": int(step.frame),
		"counter": current_step,
		"command": _pose_command(int(step.actor), int(step.action), int(step.frame))}
	_auxiliary.assign(step.get("auxiliary", []).duplicate(true))
	_pending_popups.clear()
	for hit: Dictionary in step.hits:
		var index := int(hit.target)
		_poses[index] = {"action": AniAction.Clip.DAMAGED, "frame": 0, "revision": current_step + 1}
		# 受击回弹从这个命中步重新计时（原生重播受击动作会让 `same_animation_request_count` 进位）。
		_recoil_start[index] = current_step
		_display_balls[index].hp = maxi(0, int(_display_balls[index].hp) - int(hit.damage))
		if int(_display_balls[index].hp) <= 0:
			_deferred_graves[index] = true
		_display_balls[index].speed -= int(hit.get("speed_loss", 0))
		var damage := int(hit.damage)
		# 原生 `Param_dmg2BASIC` 的 `0x79056`：本次伤害 > 0 且相性有利／不利时，把
		# `JC_fxt2Return(407／408)` 推进提示栈（`Game_infoInit(-1, …)`）。**只有技能会推**——
		# `Param_dmg2BASIC` 的唯一调用点是 `Battle_Skill_init`，普攻走
		# `Param_dmg1BASIC`，一次伤害推一条；带两段命中帧的普攻（如物种 49 的第 5／9 帧）
		# 因此一条都不该推。同一次行动里同一条记录只推一次：原生在 `Battle_Skill_init` 阶段
		# 就按目标逐个判定完，工程把伤害摊到各命中帧，不收敛会在一次攻击里弹好几条。
		var strength := int(hit.get("strength", 0))
		if damage > 0 and bool(hit.get("skill", false)) and \
				(strength == ATTRIBUTE_ADVANTAGE or strength == ATTRIBUTE_DISADVANTAGE) and \
				not _attribute_reported.has(strength):
			_attribute_reported[strength] = true
			# 记录正文自带段色标记（`zh_CN.tres` 的 `[color=#…]`），颜色由 `MessageStack` 解析。
			MessageStack.say_record(Msg.Id.DAMAGE_ADVANTAGE
				if strength == ATTRIBUTE_ADVANTAGE else Msg.Id.DAMAGE_DISADVANTAGE)
		# 被动发动（原生 `Param_dmg1PASSIVE` 的两处 `Param_atkPASSIVE`）：模型把掷中的对象序号
		# 带在命中结果里，这里按「一次行动每只一条」推 `Msg.Id.PASSIVE_ACTIVATED`。
		for owner: int in hit.get("activated_passives", []):
			if _passive_reported.has(owner):
				continue
			_passive_reported[owner] = true
			_say_passive_activated(owner)
		# 中毒的即时一跳（`Param_dmgPOISON` → `Param_dmgNUMBER`）也出红色数字，所以带 `status`
		# 的命中只在它是中毒结算时画数字。
		if damage >= 0 and (not hit.has("status") or bool(hit.get("poison", false))):
			_pending_popups.append({"target": index, "damage": damage,
				"critical": bool(hit.get("critical", false))})
			# 抖动只属于「暴击且真掉血」：原生在 `v9 > 0` 且暴击倍率非 0 时才置计数，
			# MISS（`v9 <= 0`）那一支从不设，所以 MISS 不抖。
			if damage > 0 and bool(hit.get("critical", false)):
				_shake_hit()
		if hit.has("statuses"):
			_display_balls[index].statuses = hit.statuses.duplicate(true)
		var later_hit := false
		for later in range(current_step + 1, _steps.size()):
			for other: Dictionary in _steps[later].hits:
				if int(other.target) == index:
					later_hit = true
		if not later_hit:
			_display_balls[index].direction = battle.balls[index].direction
		# 逐次伤害只是场上数字（原生 `Param_dmgNUMBER` 的 kind 14 对象）：既不进提示栈，
		# 也不画在战斗面板上（面板只留给边界态）。
	_refresh_recoil()
	# 捕获演出的每个分镜（原生 `Battle_Capture_Hide_*`／`Battle_Capture_Action_*`）：
	# 退场位移、淡入淡出、主角投球都交给 `$Field.capture_frame`；结果帧才在目标身上放
	# `b_effect` 37／38，成功第 21 帧才清对象并推 fxt478 入包提示。
	var capture: Dictionary = step.get("capture", {})
	_pending_effect.clear()
	if not capture.is_empty():
		_show_capture_stage(capture)
	if step.has("flash"):
		_pending_flashes.assign(step["flash"])
	_refresh_display()


## 原生 `Param_atkPASSIVE` 的「被动发动」提示（`"[%s] %s"` 的第一个 `%s` 是被动记录名、
## 第二个是 `JC_fxt2Return(556)` 的正文「发动」），行首调色板码按「敌方 / 我方」分档。
func _say_passive_activated(owner: int) -> void:
	var passive_name: String = _assets.text_message(PASSIVE_NAME_SOURCE,
		PASSIVE_NAME_RECORD % Battle.passive_id_of(battle.balls[owner]))
	var color := PASSIVE_NOTICE_ENEMY_COLOR if owner < Battle.ENEMY_SLOTS \
		else PASSIVE_NOTICE_ALLY_COLOR
	MessageStack.say("%s[%s] %s" % [color, passive_name,
		_assets.text_message(Msg.SOURCE, Msg.Id.PASSIVE_ACTIVATED)])


## 捕获演出的一个分镜：位移／淡入淡出／主角投球都由 `$Field.capture_frame` 按原生帧序做，
## 这里只接结果帧（`b_effect` 37／38）与成功第 21 帧的入包（原生 `Object_objRemove` + `Ball_stdAddEx`）。
func _show_capture_stage(capture: Dictionary) -> void:
	var stage := int(capture.get("stage", Battle.CaptureStage.RESULT))
	var target := int(capture.get("target", -1))
	$Field.capture_frame(stage, int(capture.get("frame", 0)))
	if stage == Battle.CaptureStage.RESULT and capture.has("effect"):
		_pending_effect = {"target": target, "effect": int(capture.effect)}
	elif stage == Battle.CaptureStage.OBTAINED:
		if target >= 0 and target < _display_balls.size():
			_display_balls[target] = {}
		_say_monster_obtained()


## 原生 `Ball_stdAddEx@0x85310`：捕获成功入包后推一条提示——图标帧是球记录的
## `kind_specific_85_bits`（`Item_datBasic` 类型 29 的 `表[属性] − 104` 存成无符号字节，
## 即 `common/ui_item` 的 152–157，与 `MenuModel.BALL_ICONS` 同一套属性球图标），正文是
## `Ball_stdGradeINDEX` 的品级色 + 性格名（`Ball_stdNickText` 的 fxt472..477，性格 0 是空串）
## + fxt478「%s获得」。
func _say_monster_obtained() -> void:
	if _capture_ball.is_empty() or _assets == null or _presentation == null:
		return
	# 原生 `Ball_stdAdd` 在怪物背包满时返回空指针，`Ball_stdAddEx` 也就不推这条提示；
	# 本工程的入包推迟到战斗结束，所以用同一条容量规则先判一次（`_captures` 已含本次）。
	var capacity := int(_progress.get("monsterCapacity", 0))
	var monsters: Variant = _progress.get("monsters")
	if capacity > 0 and monsters is Array and monsters.size() + _captures.size() > capacity:
		return
	var species := int(_capture_ball.get("species", 0))
	var grade := int(_capture_ball.get("grade", 0))
	var nickname := int(_capture_ball.get("nickname", 0))
	var names: Dictionary = _assets.text_messages("common/item_mon.dat")
	var name_text := "#%d" % Battle.combat_species(species)
	var definition: MonsterDefinition = _presentation.catalog.monster(
		Battle.combat_species(species))
	if definition != null and not definition.name_record.is_empty():
		name_text = str(names.get(definition.name_record, name_text))
	# 图标与品级色都由 `message_stack` 决定：这里只把球记录里的属性号交出去。
	MessageStack.push_monster(name_text, grade, nickname, int(_capture_ball.get("attribute", -1)))


## 原生 `Battle_Capture_Action_mPaint`：演出收尾后开 Box2 结果窗（`Menu_win_Box2_DrawOk`），
## 正文是 msg.fxt 12「抓捕成功」／11「抓捕失败」；按下 OK 收窗后才切 POSITION。
func _open_capture_result() -> void:
	_capture_result_pending = false
	phase = "capture_result"
	$CaptureBox.present(_assets.text_message(Msg.SOURCE,
		Msg.Id.CAPTURE_SUCCEEDED if _capture_caught else Msg.Id.CAPTURE_FAILED),
		Box2Prompt.Form.OK)
	$CaptureBox.show()
	$CaptureBox.open_window()
	_refresh_display()


func _capture_box_confirmed() -> void:
	if phase == "capture_result" and not $CaptureBox.is_transitioning():
		$CaptureBox.close_window()


## 结果窗收完（原生 `MainData` 的窗口相位回到 -4）：移除主角对象、退场偏移复位，再切 POSITION。
func _capture_box_finished(opened: bool) -> void:
	if opened or phase != "capture_result" or _closed:
		return
	$CaptureBox.hide()
	$Field.capture_end()
	_state_25()


## 原生 `Battle_Menu_mHide`／`Battle_Taget_mHide`：指令窗口（MENU）盯行动者、
## 目标窗口（TARGET）盯当前光标，把**主体后面那一号**对象（`n2 = 主体 + 1`，主体 ∈ {0,1,3,4}
## 时才算；2／5 是最前排，没有遮挡所以不动）的 `extended_state[541]` 每帧 +1 到 7，
## `Object_drawSPRITE` 按 `alpha = 256 - 12 * n` 画；其余对象一律归 0。
## `Battle_Menu_destroy`／`Battle_Target_destroy` 会以 `mHide(0)` 把所有人清零，所以淡出只在
## 这两个状态里存在。
##
## 原生实测（`rec3.mp4`，菜单态 vs 目标态同一帧比对）：淡出的只有**一只**，亮度比 0.66–0.70
## ≒ 172/256，其余同伴亮度比 1.00。本项目按表现要求把**行动方除行动者以外的所有怪物**一起淡出
## （原生那一只在其中），并同样以每 0.05 秒 +1 的节奏走到 7 帧。
func _refresh_fade() -> void:
	var targets := _fade_targets()
	for index: int in _fade.keys():
		if not targets.has(index):
			_fade.erase(index)
	for index: int in targets:
		_fade[index] = mini(int(_fade.get(index, 0)) + 1, FADE_STEPS)


## 指令窗口：行动方除行动者之外的所有在场怪物；目标窗口：原生那一只（`主体 + 1`）。
func _fade_targets() -> Array:
	var targets: Array = []
	if battle == null:
		return targets
	if phase in ["command", "command_exit"]:
		var actor := int(battle.actor)
		for index in _display_balls.size():
			if index == actor or _display_balls[index].is_empty():
				continue
			if (index < 3) == (actor < 3):
				targets.append(index)
		return targets
	if phase in ["target", "target_exit"]:
		var faded := target + 1 if target in [0, 1, 3, 4] else -1
		if faded >= 0 and faded < _display_balls.size() and not _display_balls[faded].is_empty():
			targets.append(faded)
	return targets


func _fade_settled() -> bool:
	for index: int in _fade_targets():
		if int(_fade.get(index, 0)) < FADE_STEPS:
			return false
	return true


## 受击回弹（原生 `Battle_Monster_procCurr`）：`HIT_RECOIL[n4]` 按受击帧号递减。
## 原生是 `n38->x = 编队槽` 之后再按 `direction_code` 加减——1（我方）`x += knock`、
## 2（敌方）`x -= knock`——所以受击方会被**打离攻击者**、并且丢掉回合开始的后移量（回编队槽），
## 第 5 帧（`n4 > 4`）`Object_objANI(obj, 0)` 回待机。
func _refresh_recoil() -> void:
	_recoil.clear()
	for raw_index: int in _recoil_start.keys():
		var age := current_step - int(_recoil_start[raw_index])
		if age >= HIT_RECOIL.size():
			_recoil_start.erase(raw_index)
			# 原生 `Battle_Monster_procCurr` 的 `n4 > 4` 分支 `Object_objANI(obj, 0)`：受击动作播完
			# 必须回待机。停在受击帧会让怪物一直保持挨打姿势，而受击图帧本身带画内偏移，看起来就像站歪了。
			if not _deferred_graves.has(raw_index):
				_poses[raw_index] = {"action": AniAction.Clip.IDLE, "frame": 0}
			continue
		_recoil[raw_index] = int(HIT_RECOIL[maxi(age, 0)]) * (1 if raw_index >= 3 else -1)


## 原生把 `BattleData + 0x44` 置 6（`Param_dmgBASIC` 的暴击分支），`BattleCanvas_mRun`
## 每帧按 `(计数 − 1) & 3` 给整屏加 `(±3, ±3)` 的四相位偏移，帧末 `EFC_mainDRAW` 再清零。
## 所以只有暴击命中会抖，幅度 3 像素、共 6 帧，且连 UI 一起抖。
func _shake_hit() -> void:
	var player: AnimationPlayer = $Shake
	player.stop()
	player.play(&"hit")
	player.advance(0.0)


func _choose_flee() -> void:
	if phase != "command":
		return
	if not battle.allow_flee:
		_unsupported("此事件战逃跑")
		return
	phase = "flee"
	_flee_escaped = false
	_flee_after_close = ""
	_clear_buttons()
	$Flee.present_select(_assets.text_message(Msg.SOURCE, Msg.Id.FLEE_PROMPT))
	$Flee.show()
	$Flee.open_window()
	_refresh_display()


## 原生状态 28 DIE（`Battle_Die_init`）：有复活道具先出子状态 3 的「使用%s[%s]复活吗?」，
## 没有就出子状态 5 的「使用100元的情报使用费可以复活」；两页的「否／确定」都落到
## 子状态 2／6 的「返回主菜单吗?」。整屏先 `Battle_info_Capture()` 拍成模糊半透明底
## （`$Defeat` 的 `screen_shade`），再在这个 Box2 窗口里逐页换文。
func _open_defeat() -> void:
	if phase == "defeat" or _closed:
		return
	phase = "defeat"
	_clear_buttons()
	$Field.freeze_scene(true)
	$Defeat.show()
	_show_defeat_page(DefeatPage.ITEM if _revive_available() else DefeatPage.FEE)
	$Defeat.open_window()
	_refresh_display()


## 换一页：窗口保持开着，只换正文形态（原生状态 28 的子状态切换就是在同一个窗口里换绘制入口）。
func _show_defeat_page(page: int) -> void:
	_defeat_page = page
	match page:
		DefeatPage.ITEM:
			$Defeat.present_select(_assets.text_message(Msg.SOURCE,
				Msg.Id.REVIVE_PROMPT) % ["", _revive_item_name()], 1)
		DefeatPage.FEE:
			$Defeat.present_message(_assets.text_message(Msg.SOURCE, Msg.Id.REVIVE_INFO_FEE))
		DefeatPage.REVIVED:
			$Defeat.present_message(_assets.text_message(Msg.SOURCE, Msg.Id.REVIVE_DONE))
		DefeatPage.RETURN:
			$Defeat.present_select(_assets.text_message(Msg.SOURCE, Msg.Id.RETURN_TO_MENU), 1)
	_refresh_display()


## 选择页落键：是／否。
func _defeat_chosen(accepted: bool) -> void:
	if phase != "defeat" or _closed:
		return
	match _defeat_page:
		DefeatPage.ITEM:
			if accepted:
				_defeat_revive()
			else:
				_defeat_previous = DefeatPage.ITEM
				_show_defeat_page(DefeatPage.RETURN)
		DefeatPage.RETURN:
			if accepted:
				_defeat_exit("title")
			else:
				_show_defeat_page(_defeat_previous)


## 确定页落键。
func _defeat_confirmed() -> void:
	if phase != "defeat" or _closed:
		return
	match _defeat_page:
		DefeatPage.FEE:
			# 原生子状态 7 是 `Game_Cash` 的现金购买（`JB_sysPurchase`，真实货币）。离线工程没有
			# 这条支付通道，与其余现金功能同口径：只提示，然后落到「返回主菜单吗?」。
			_set_note("情报使用费需要现金商店，离线工程无法支付；请用复活道具或返回主菜单。")
			_defeat_previous = DefeatPage.FEE
			_show_defeat_page(DefeatPage.RETURN)
		DefeatPage.REVIVED:
			_defeat_exit("resume")


## 原生子状态 3 的「是」：扣 1 个复活道具（`Item_stdDels(7, 23, 1, 1)`）→ 全队
## `Battle_Die_Revival` 回满 → 子状态 4「全部复活了」；确定后 `SetNext(POSITION)` 继续战斗。
func _defeat_revive() -> void:
	if not battle.revive():
		_boundary("战斗已不在败北状态，无法复活")
		return
	var item_id := Battle.revive_item_id()
	_used_items[item_id] = int(_used_items.get(item_id, 0)) + 1
	_deferred_graves.clear()
	_poses.clear()
	_display_balls = battle.balls.duplicate(true)
	for index in range(_display_balls.size()):
		_poses.append({"action": AniAction.Clip.IDLE, "frame": 0}
			if not _display_balls[index].is_empty() else {})
	_show_defeat_page(DefeatPage.REVIVED)


## 关窗后再做收尾：`resume` 回战斗（复活成功），`title` 走 `completed` 的败北出口（`Game_out`）。
func _defeat_exit(after: String) -> void:
	_defeat_after_close = after
	$Defeat.close_window()


func _defeat_transition_finished(opened: bool) -> void:
	if opened or phase != "defeat" or _closed:
		return
	$Defeat.hide()
	var after := _defeat_after_close
	_defeat_after_close = ""
	if after == "resume":
		$Field.freeze_scene(false)
		_next()
	elif after == "title":
		# `_finish()` 只接受结果相位（它会再读一次 `battle.result`）。
		phase = "result"
		_finish()


## 背包里还剩几个复活道具：`_progress.inventory` 的键可能是数字或数字字符串
## （`Story` 的背包校验接受两种写法），本场已经用掉的要从库存里扣掉。
func _revive_available() -> bool:
	var item_id := Battle.revive_item_id()
	return _inventory_count(item_id) - int(_used_items.get(item_id, 0)) > 0


func _inventory_count(item_id: int) -> int:
	var inventory: Variant = _progress.get("inventory", {})
	if not inventory is Dictionary:
		return 0
	var total := 0
	for key: Variant in inventory:
		if key is int and int(key) == item_id and inventory[key] is int:
			total += int(inventory[key])
		elif key is String and key.is_valid_int() and int(key) == item_id and \
				inventory[key] is int:
			total += int(inventory[key])
	return total


## 复活道具的显示名：优先取背包行的名字（与道具窗口同一套记录），拿不到再按道具记录取。
func _revive_item_name() -> String:
	var item_id := Battle.revive_item_id()
	var rows: Array = Menu.native_inventory_rows(_progress, _presentation.catalog, ItemKind.Bag.ITEMS)
	for row: Dictionary in rows:
		if int(row.get("id", -1)) == item_id:
			return _presentation.item_name(row)
	var entry: ItemDefinition = _presentation.catalog.item(item_id)
	if entry == null:
		return "--"
	return _assets.text_message("common/item_basic.dat", entry.name_record)


func _flee_chosen(accepted: bool) -> void:
	if phase != "flee" or _closed:
		return
	if not accepted:
		_flee_after_close = "command"
		$Flee.close_window()
		return
	# 原生 `Battle_Run_mKeyPressed` 在关窗之前就掷 `Param_atkIsRUNAWAY()`，把结果写进
	# 答案字段；关窗（相位 −4）后 `Battle_Run_mRun` 才重开窗显示 msg 8／9。
	var response: Dictionary = battle.flee()
	if not response.ok:
		_boundary(str(response.error))
		return
	_flee_escaped = bool(response.escaped)
	_flee_after_close = "result"
	$Flee.close_window()


## 结果页的确定键：成功回野外地图（原生 `GameCanvas_SetNext(GAME_STATE_FIELD)`），
## 失败进状态 25 POSITION 收尾这一回合（原生 `Battle_Target_Next` 的 case 4）。
func _flee_confirmed() -> void:
	if phase != "flee" or _closed:
		return
	_flee_after_close = "finish" if _flee_escaped else "position"
	$Flee.close_window()


func _flee_transition_finished(opened: bool) -> void:
	if opened or _closed or phase != "flee":
		return
	var after := _flee_after_close
	_flee_after_close = ""
	match after:
		"result":
			$Flee.present_message(_assets.text_message(Msg.SOURCE,
				Msg.Id.FLEE_SUCCEEDED if _flee_escaped else Msg.Id.FLEE_FAILED))
			$Flee.open_window()
		"command":
			$Flee.hide()
			_next()
		"finish":
			$Flee.hide()
			# `_finish()` 只接受结果相位（它会再读一次 `battle.result == "escaped"`）。
			phase = "result"
			_finish()
		"position":
			$Flee.hide()
			_state_25()


func _finish() -> void:
	if phase != "result" or battle.result == null or _closed:
		return
	_closed = true
	phase = "loading"
	_clear_buttons()
	$Result.hide()
	var outcome := {"result": battle.result, "party": battle.balls.slice(3).duplicate(true)}
	if settlement != null:
		outcome["settlement"] = settlement
	if not _captures.is_empty():
		outcome["captures"] = _captures.duplicate(true)
	if not _used_items.is_empty():
		outcome["items"] = _used_items.duplicate()
	completed.emit(outcome)


func _abandon() -> void:
	if _closed:
		return
	_closed = true
	abandoned.emit(_exit_payload())


## 系统菜单主菜单的「是」（`Battle_MainMenu_mRun` 返回码 1 → `Game_out()`）：
## 单机战斗只切回 Prime 标题，不回地图、不结算，也不替原生补存档写入。
func _exit_to_title() -> void:
	if _closed:
		return
	_closed = true
	title_requested.emit(_exit_payload())


## 非结算出口（逃跑／放弃、系统菜单回标题）要交出的东西：原生在战斗内就已经写回了
## `Item_stdDel` 与 `Ball_stdAddEx`，所以已用道具与已捕获个体都得跟着走。
func _exit_payload() -> Dictionary:
	return {"items": _used_items.duplicate(), "captures": _captures.duplicate(true)}


func _boundary(message: String) -> void:
	phase = "boundary"
	$Info.hide()
	$Items.hide()
	# 胜利进场已经收掉指令条（`_begin_victory` 的 `$Actions.hide()`），而边界页的出口按钮挂在
	# `$Actions` 上；不亮回来这颗按钮就看不见，只剩 Enter／Escape 能走。
	$Actions.show()
	_steps.clear()
	_auxiliary.clear()
	_clear_buttons()
	var destination := "地图" if not _boundary_exits_to_title() else "标题"
	_set_note("原战斗边界：%s\n返回%s不会结算或推进战斗。" % [message, destination])
	_button(200, "返回" + destination, _boundary_exit)
	_refresh_display()


## 边界页的文案与确认出口共用这一条判据：逃生战（`allow_flee`，`wild_encounters.gd` 只给野外战
## 打开）回地图，事件战回标题——原生那条是 `Game_out()` 的 `EFC_mainSetNEXT(CANVAS_PRIME, 10)`。
func _boundary_exits_to_title() -> bool:
	return battle == null or not battle.allow_flee


func _boundary_exit() -> void:
	if _boundary_exits_to_title():
		_exit_to_title()
	else:
		_abandon()


## 战斗里的文字提示统一走原生全局提示栈（`Game_infoInit` / `Game_infoDraw`，
## 见 `wiki\ui\message-stack.md`）：原生给每条消息先铺半透明黑底再画字，战斗窗不再自己
## 持有一块边界浮层。逐次伤害（`Param_dmgNUMBER` 的场上数字）与加载占位两条通道都不走，
## 见各自的调用点注释。
func _set_note(text: String) -> void:
	# 空串由 `MessageStack.notify` 自己忽略（原生不会推空消息）。
	MessageStack.say(text)


func _clear_buttons() -> void:
	$Actions.clear()
	_buttons.clear()


func _button(x: float, text: String, callback: Callable, enabled := true) -> void:
	$Actions.add_button(x, text, callback, enabled)
	_buttons.assign($Actions.buttons)


func _position(index: int) -> Vector2:
	return $Field.actor_render_position(index)


## 原生每个状态的 `mRun` 每帧都把镜头焦点送到 `Battle_objGetPosition2(行动者, …, a4: 70)`
## （MENU／TARGET／RUN／CHARACTER 都是这一条；a4 只改 x，而 400 宽下 x 恒被夹住），
## ATTACK／SKILL 换成 `Battle_objPOS(行动者)` 与 `Battle_objPOS(目标)` 的中点 x + 目标 y
## （`Battle_Attack_mRun`、`Battle_Skill_mRun`）。状态 25 POSITION 回到
## `BattleCanvas_load` 存的焦点 (202, 244)，之后又会被下一位行动者拉回自己的槽位。
func _camera_focus(seat_actor: int) -> Vector2:
	# 状态 25 走 `Battle_Position_mRun` 的 `0x36E3A` → `Battle_mapFOCUS`，而那份焦点
	# 全库只在 `BattleCanvas_load:39-40` 写过一次，所以要插回的是**加载时的焦点**，不是下一位
	# 行动者的槽位——跟着下一位走会让滑回期间整幅画面（背景与所有战斗对象）多偏 18 像素。
	if phase == "position":
		return $Field.load_focus()
	if phase in ["action", "result"]:
		if seat_actor < 0 or target < 0:
			return $Field.load_focus()
		var actor_slot: Vector2 = $Field.slot_position(seat_actor)
		var target_slot: Vector2 = $Field.slot_position(target)
		return Vector2((actor_slot.x + target_slot.x) / 2.0, target_slot.y)
	if seat_actor < 0 or battle == null or seat_actor >= battle.balls.size() \
			or battle.balls[seat_actor].is_empty():
		return $Field.load_focus()
	return $Field.slot_position(seat_actor)


## 原生状态 11 CHARACTER 的 `run_counter`：轮到这个怪物作指令时每帧 +1（0.05 秒/帧），`> 5` 切
## POISON→MENU。它和「指令窗口图标出现」是同一时刻开始的，所以直接跟指令图标的 `action_000`
## （7 帧 / 0.35 秒）同步，保证「其他己方怪物后移」与「选项按钮出现」同步。
## 同一回合里只增不减（取消目标选择会重播图标动画，但原生 CHARACTER 一回合只跑一次），
## 位置一直保持到行动结束，再由状态 25 POSITION 的入场帧直接写回编队槽（见 `_state_25`）。
func _run_counter() -> int:
	if phase == "command":
		var player: AnimationPlayer = $Actions/Commands/Art/AnimationPlayer
		if not player.current_animation.is_empty():
			_turn_steps = maxi(_turn_steps,
				mini(int(player.current_animation_position / STEP_SECONDS), 5))
	return _turn_steps


## 技能横幅的帧计数：原生是技能状态自己的 `run_counter`（`Battle_Skill_mPaint` 用
## `run_counter - 2` 折算横幅帧）。行动期间就是时间轴步号；动作比横幅表短的技能在状态 25
## POSITION 里接着数——原生的横幅 16 帧本来就都落在 SKILL 状态里，工程把收带段接到 POSITION
## 的逐帧刷新上，否则技能动作一收尾横幅就整条消失、看不到收起。
func _banner_step() -> int:
	if phase == "action":
		return current_step
	if phase == "position":
		return current_step + _return_frame
	return -1


func _refresh_display() -> void:
	$Flee.visible = phase == "flee"
	# 行动期间 `battle.actor` 已经指向下一个行动者，站位要按本回合记下的行动者算。
	var seat_actor := _acting_actor if phase in ["action", "result", "capture_result"] else \
		(int(battle.actor) if battle != null else -1)
	$Field.set_focus(_camera_focus(seat_actor))
	_refresh_fade()
	$Field.present(_display_balls, _poses, _auxiliary, _acting_actor,
		"command" if phase == "command_exit" else "target" if phase == "target_exit" else phase,
		seat_actor, target,
		_target_candidates() if phase == "target" else [], _pending_popups, _run_counter(), _recoil,
		_fade, _return_offsets if phase == "position" else {}, _action_target, _deferred_graves,
		_pending_effect, _pending_flashes, _banner_step())
	_pending_popups.clear()
	_pending_effect.clear()
	_pending_flashes.clear()
	if battle != null and battle.actor >= 0:
		$Actions.place_commands(_position(int(battle.actor)))
	if is_node_ready():
		# 第二参是「当前按住的键」：`present()` 会把它记成 `held_key`，用来挡掉同一次按住里的重复
		# 命中。过去这里恒传 0，每帧刷新都把 `held_key` 冲掉，按住 AUTO 时的轻微抖动／拖动会再发
		# 一次同一个键——AUTO 于是被连按两次（开一次、关一次），表现成「按一次只走一手」。
		# 战斗里任何相位都要留着底部操作界面：出手动画、结算、捕获这些相位原来落到 `0`
		# （= 不画），玩家在看演出时手上没有任何键。原生 `EFC_mainTouchDRAW` 对战斗状态
		# 始终给出档位，所以这里最后一档统一落到 `COMMAND`，不再传 0。
		$TouchControls.present($SysMenu.touch_style() if phase == "sys" else
			TouchStyle.SELECT if phase in ["target", "flee", "encounter", "items"] else
			TouchStyle.INFO if phase == "info" else
			TouchStyle.COMMAND, $TouchControls.held_key)
		# 原生 `EFC_mainTouchDRAW:138-162`：自动战斗开着时 AUTO 键按 `GRP_MODE_BRIGHT` 画，亮度
		# 取样成 64／0／64／128，即在 0 与 128 之间来回。那四档是按帧号取样的量化痕迹，本工程在
		# `bright` 动画里做 0→128→0 的线性呼吸（0.4 秒一轮），按钮保持半透明，这里只切状态。
		$TouchControls/Auto.set_bright(auto_mode)
