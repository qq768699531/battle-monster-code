extends "res://tests/unit/gut_case.gd"

const Battle = preload("res://game/battle/combat/combat/battle.gd")
const Resources = preload("res://engine/data/world_resources/world_resources.gd")
const ViewScene = preload("res://game/battle/combat/combat/battle.tscn")
const SysMenuScript = preload("res://game/battle/presentation/sys_menu/sys_menu.gd")
const StackScene = preload("res://engine/ui/message_stack/message_stack.tscn")
const StackScript = preload("res://engine/ui/message_stack/message_stack.gd")
const Story = preload("res://engine/data/story/story.gd")
const Msg = preload("res://engine/ui/msg/msg.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const BattlePoses = preload("res://game/battle/combat/battle_poses/battle-poses.tres")
const FieldScript = preload("res://game/battle/arena/field/field.gd")
## 原生状态 26 的窗口：`Battle_Win_Draw:49` 的 `Menu_win_Box4_DrawWindow(…, 228, 240, …, 1, 16)`
## 把正文 228×240 在 400×240 屏幕里居中，所以左上角是 ((400−228)/2, (240−240)/2) = (86, 0)。
const RESULT_WINDOW_SIZE := Vector2i(228, 240)
const RESULT_WINDOW_ORIGIN := Vector2i(86, 0)
## AUTO 键常亮呼吸的上限与峰值时刻：原生 `EFC_mainTouchDRAW:138-162` 在 0 与 128 之间来回，
## 一轮 8 帧（20 fps 即 0.4 秒），所以峰值在 0.2 秒。
const BRIGHT_UPPER_BOUND := 128
const BRIGHT_PEAK_SECONDS := 0.2

var _outcomes: Array = []
var _assets: Node
var _resources: RefCounted


func _ball(species: int, speed: int = 100, attribute: int = 0) -> Dictionary:
	var passives: Array[int] = []
	passives.resize(66)
	passives.fill(0)
	return {"species": species, "level": 60, "nickname": 0, "attribute": attribute, "kind": 0,
		"stats": [350, 100, 360, 100, 1000, speed], "percentages": [0, 0, 0, 0],
		"passives": passives, "hp": 1000, "max_hp": 1000, "sp": 5, "max_sp": 5,
		"speed": speed, "cooldown": 0, "direction": 0, "grade": 0,
		"native_arguments": [species, 60, -1, 0, 0, 0, 0, 0, -1, -1]}


func _battle(actor: int = 3) -> RefCounted:
	var model := Battle.new([_ball(93), _ball(1099), _ball(13)],
		[_ball(49, 900), _ball(62, 800), _ball(86, 700)],
		func(_limit: int) -> int: return 0)
	model.actor = actor
	return model


func _view(model: RefCounted, progress: Dictionary = {}) -> Control:
	var view: Control = ViewScene.instantiate()
	get_tree().root.add_child(view)
	view.set_process(false)
	view.get_node("ActionTimeline").callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view.get_node("Actions/Commands/Art/AnimationPlayer").callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view.get_node("Field/Cursor/AnimationPlayer").callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view.get_node("Field/Hud/TargetShake").callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view.get_node("Flee/AnimationPlayer").callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for window in ["List", "Prompt", "Settings", "Method/Frame"]:
		view.get_node("SysMenu/" + window + "/AnimationPlayer").callback_mode_process = \
			AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	view.completed.connect(func(outcome: Dictionary): _outcomes.append(outcome))
	view.start(model, _resources, _assets, progress)
	return view


func _key(view: Control, code: Key) -> void:
	var commands := {KEY_ENTER: "Enter", KEY_SPACE: "Space", KEY_LEFT: "ArrowLeft",
		KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_ESCAPE: "Escape"}
	view.press(commands[code])
	_complete_command(view)
	_complete_target(view)


func _complete_command(view: Control) -> void:
	if view.phase != "command_exit":
		return
	var player: AnimationPlayer = view.get_node("Actions/Commands/Art/AnimationPlayer")
	player.advance(0.21)
	player.advance(0.16)


func _complete_target(view: Control) -> void:
	if view.phase == "target_exit":
		view.get_node("Field/Cursor/AnimationPlayer").advance(0.11)


## 结算窗口的 OK 页脚是透明按钮：按真实的 GUI 命中测试点一次（不是直接 emit pressed）。
func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event)


## 触控按下的三段分开推：`touch_controls.gd` 只认真实 GUI 命中，且「按住时抖动」要单独模拟。
func _touch_down(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	event.global_position = at
	get_viewport().push_input(event)


func _touch_move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event)


func _touch_up(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	event.global_position = at
	get_viewport().push_input(event)


func _stack_texts(stack: Control) -> Array:
	var texts: Array = []
	for index in stack.count():
		texts.append(stack.slot_at(index).text)
	return texts


## 相克提示（`common/msg.fxt` 407／408）的正文带 `[color=#RRGGBB]` 段色标记，比较前两侧都取可见文本。
func _is_attribute_notice(text: String) -> bool:
	var visible := StackScript.visible_text(text)
	return visible == StackScript.visible_text(
			_assets.text_message(Msg.SOURCE, Msg.Id.DAMAGE_ADVANTAGE)) or \
		visible == StackScript.visible_text(
			_assets.text_message(Msg.SOURCE, Msg.Id.DAMAGE_DISADVANTAGE))


## 只推进到本手动画播完（停在状态 25 的滑回里）：下一手的敌方 AI 一旦开打就会换掉 `_steps`
## 并可能再往提示栈推东西，断言相克提示的条数时必须停在这里。
func _advance_action(view: Control) -> void:
	var safety := 0
	while view.phase == "action" and safety < 500:
		view.get_node("ActionTimeline").advance(view.STEP_SECONDS)
		safety += 1


func _complete_action(view: Control) -> void:
	var safety := 0
	while view.phase == "action" and safety < 500:
		view.get_node("ActionTimeline").advance(view.STEP_SECONDS)
		safety += 1
	safety = 0
	while view.phase == "position" and safety < 64:
		view.get_node("ActionTimeline").advance(view.STEP_SECONDS)
		safety += 1


## 池里当前仍可见（正在播放）的一次性表现节点数。
func _visible_children(pool: Node) -> int:
	var visible := 0
	for child: Node in pool.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			visible += 1
	return visible


func test_legacy_suite() -> void:
	_assets = get_tree().root.get_node("AssetCatalog")
	_resources = Resources.new()
	_resources.initialize(_assets)
	var model := _battle()
	var view := _view(model, {"inventory": {"5001": 2}})
	assert_true(view.phase == "command" and view._buttons.size() == 5,
		"the native battle scene loads its atlas art and offers five commands")
	# 绘制序（`Object_procLIST`）：`draw_order_key` 恒 0 → y 升序 → 同 y 时对象池序
	# （先建我方、后建敌方 ⇒ 敌方在上）。编队槽让两侧同一排的 y 相同，所以同一排里我方先画。
	var field: Control = view.get_node("Field")
	var front_enemy: int = field._actors[0].get_index()
	var front_party: int = field._actors[3].get_index()
	var back_enemy: int = field._actors[2].get_index()
	assert_true(front_party < front_enemy and front_enemy < back_enemy,
		"actors draw by row and the enemy of a row sits above its party counterpart")
	# 友方信息条底部的 FOOD 条：原生 `Game_monDraw@0x41360:22` 把它画在卡片 `(x + 2, y + 34, 75 × 3)`，
	# 77×37 的卡片底边留 1 像素；条内一行 `0xFFFF55` 按 `food_value / 100` 填满 73 像素。
	var food_bar: Control = field.get_node("Hud/Party0/Food")
	assert_true(food_bar.position == Vector2(2, 34) and food_bar.size == Vector2(75, 3) and
		food_bar.get_node("Track/Fill").color.is_equal_approx(Color(1, 1, 85.0 / 255.0)),
		"the party card paints the native FOOD bar at x+2, y+34, 75x3 in #FFFF55")
	field._present_food(field.get_node("Hud/Party0"), 50)
	assert_eq(field.get_node("Hud/Party0/Food/Track/Fill").offset_right, 36.0,
		"the FOOD bar keeps the native 73-pixel track ratio (73 * 50 / 100)")
	# 伤害数字各自独立（bm-P1-24）：原生每次命中都新建一个 kind 14 对象、各自计时各自消失，
	# 所以后出现的数字不能把仍在上升的前一个数字顶掉。
	var popups_pool: Node = field.get_node("Popups")
	field._show_popups([{"target": 0, "damage": 12}, {"target": 1, "damage": 34}],
		view._display_balls)
	var after_batch: int = _visible_children(popups_pool)
	field._show_popups([{"target": 2, "damage": 56}], view._display_balls)
	assert_eq([after_batch, _visible_children(popups_pool)], [2, 3],
		"each damage number keeps its own pooled instance until its animation ends")
	# 目标横幅（bm-P1-33）：原生 `Battle_Target_mPaint` 先用 `#P000#P000` 配 `JC_fntSetBOLD(1)`
	# 画一遍文字（`JC_fntDrawBUFF` 的 bold=1 把字模四周各扩 1 像素）再画真实颜色，所以文字带
	# 1 像素黑描边；换目标时按 `unk_97C8C` 的三个 int32（−2／+2／−1）抖 3 帧后回原位。
	var brief_view := _view(_battle())
	var brief_name: Control = brief_view.get_node("Field/Hud/TargetInfo/Shake/Name")
	assert_gt(brief_name.outline.a, 0.0, "the target banner keeps the native black outline")
	brief_view._open_target()
	var brief_shake: AnimationPlayer = brief_view.get_node("Field/Hud/TargetShake")
	var brief_first: int = brief_view.target
	brief_view._change_target(1)
	brief_shake.advance(0.05)
	assert_eq([brief_shake.current_animation, brief_shake.is_playing(),
		brief_view.target != brief_first,
		brief_view.get_node("Field/Hud/TargetInfo/Shake").position.y],
		[&"target_shake", true, true, float(FieldScript.TARGET_SHAKE_OFFSETS[1])],
		"switching the target replays the native 3-frame shake (-2 / +2 / -1)")
	# 淡入（`Battle_Target_mPaint:58-60,105`）：进入后第 1、2 帧带子 alpha 64/256、文字 2*n128；
	# 第 3 帧起 128/256 与不透明。帧计数由 `BattleCanvas_mRun` 每帧 +1、`SetNext` 进状态清 0。
	var brief_band: ColorRect = brief_view.get_node("Field/Hud/TargetInfo")
	var brief_text: CanvasItem = brief_view.get_node("Field/Hud/TargetInfo/Shake")
	assert_eq([brief_band.color.a, brief_text.modulate.a],
		[FieldScript.TARGET_BAND_ALPHA_FADING, FieldScript.TARGET_BAND_ALPHA_FADING * 2.0],
		"the banner fades in: first frames keep the native 25% band and 50% text")
	for _frame in FieldScript.TARGET_FADE_COUNTER_MAX:
		brief_view._refresh_display()
	assert_eq([brief_band.color.a, brief_text.modulate.a],
		[FieldScript.TARGET_BAND_ALPHA, 1.0],
		"after the fade frames the band sits at the native 50% and the text is opaque")
	brief_view.free()
	var before := int(model.balls[0].hp)
	view._buttons[0].pressed.emit()
	_complete_command(view)
	_key(view, KEY_SPACE)
	_complete_action(view)
	assert_true(model.turns == 1 and int(view._display_balls[0].hp) < before and
		view.phase == "command",
		"a confirmed attack resolves one turn, damages the target and returns to command")
	# 捕获：CAPTURE 触控键 → bag 4 的道具窗 → 目标确认 → `battle.capture` 判定并移出敌人。
	model.allow_flee = true
	view._touch_command(view.TouchKey.CAPTURE)
	var items: Control = view.get_node("Items")
	assert_true(view.phase == "items" and items.rows.size() == 1,
		"the capture command lists the ball bag (bag 4)")
	items.chosen.emit(items.rows[0].duplicate(true))
	_key(view, KEY_SPACE)
	_complete_action(view)
	assert_true(model.balls[0].is_empty() and view._captures.size() == 1 and
		int(view._used_items.get(5001, 0)) == 1 and view.phase == "command",
		"a capture removes the enemy, consumes the ball and records the individual")
	view.free()
	# 战斗内道具（原生 `Battle_Item1_init` 的过滤：第 1 组索引 0–18／31+ 与 7020）：
	# MENU → 道具 → 选 1000（`detail_values[8]` = 30，即 30% 上限）→ 选目标 →
	# `Ball_stdUse` 返回 5（HP 与 SP 各回一段）→ 扣 1 个并进状态 21 的 16 帧，再回 POSITION。
	var healed := _battle()
	healed.balls[3].hp = 10
	healed.balls[3].sp = 0
	var item_view := _view(healed, {"inventory": {"1000": 2}})
	var item_before := int(healed.balls[3].hp)
	item_view._buttons[4].pressed.emit()
	_complete_command(item_view)
	var item_window: Control = item_view.get_node("Items")
	item_window.chosen.emit(item_window.rows[0].duplicate(true))
	_key(item_view, KEY_SPACE)
	_complete_action(item_view)
	assert_true(item_view.phase == "command" and int(healed.balls[3].hp) > item_before and
		int(item_view._used_items.get(1000, 0)) == 1 and
		_visible_children(item_view.get_node("Field/Hits")) == 1,
		"an item command heals the chosen member, spends one item and shows its 27/28 flash")
	# 回标题这条出口（`Game_out()`）要把本战用掉的道具一并交出：原生是在战斗内使用时就已经
	# `Item_stdDel` 写回，没有「离开战斗时再结算」那一步。
	var used_titles: Array = []
	item_view.title_requested.connect(func(items: Dictionary): used_titles.append(items))
	item_view._exit_to_title()
	assert_true(used_titles.size() == 1 and int(used_titles[0].get(1000, 0)) == 1 and item_view._closed,
		"asking for the title hands over the items spent in this battle")
	item_view.free()
	# 败北（原生状态 28 DIE）：背包里有复活道具（组 7 索引 23 → 7023）就先问
	# 「使用[道具名]复活吗?」（msg.fxt 23），确认后 `Battle_Die_Revival` 回满、这场继续打。
	var down := _battle()
	for index in range(3, 6):
		down.balls[index].hp = 0
	down.result = "lost"
	down.select_actor()
	var revived := _view(down, {"inventory": {"7023": 1}})
	var prompt: String = revived.get_node("Flee/Content/Prompt").text
	assert_true(revived.phase == "revive" and revived.get_node("Flee").visible and
		prompt.contains("[妖姬之眼]") and revived._revive_available(),
		"defeat with the revival item asks before returning to the title")
	# 光标先落在「否」上（原生 `Battle_Die_mPaint` 子状态 3 的 cursor 初值），要按两次才确认；
	# 开窗动画（0.15 秒）播完前 `_confirm_choice` 会拒绝输入。
	revived.get_node("Flee/AnimationPlayer").advance(0.2)
	revived._confirm_choice(0)
	revived._confirm_choice(0)
	revived.get_node("Flee/AnimationPlayer").advance(0.2)
	assert_true(revived.phase == "command" and int(down.balls[3].hp) == int(down.balls[3].max_hp)
		and int(revived._used_items.get(7023, 0)) == 1,
		"the confirmed revival refills the party, spends one item and resumes the battle")
	revived.free()
	# 状态 12 POISON（`Battle_Poison_init` → `Param_dmgPOISON`）：中毒的怪轮到它
	# 行动时先掉血，`Battle_Poison_mRun` 空跑 16 帧才出指令窗口。
	var poisoned := _battle()
	poisoned.balls[3].statuses = {StatusEffect.Code.POISON_HIGH:
		{"stacks": 1, "remaining": 3, "value": 400}}
	var poison_view := _view(poisoned)
	var hp_before := int(poisoned.balls[3].hp)
	assert_true(poison_view._begin_poison() and poison_view.phase == "poison" and
		int(poisoned.balls[3].hp) == hp_before - 400 * 50 / 100,
		"poison settles its tier before the command window opens")
	for frame in poison_view.POISON_FRAMES:
		poison_view._process(poison_view.STEP_SECONDS)
	assert_true(poison_view.phase == "command" and poison_view._buttons.size() == 5,
		"the poison state hands over to the command window after 16 frames")
	poison_view.free()
	var terminal_model := _battle()
	for index in range(3):
		terminal_model.balls[index].hp = 0
	terminal_model.select_actor()
	var terminal := _view(terminal_model)
	var in_result: bool = terminal.phase == "result"
	for frame in 11:
		terminal.get_node("Field").advance_hud_exit()
	var window: Control = terminal.get_node("Result")
	window.get_node("AnimationPlayer").advance(0.2)
	# 掉落只在窗口进入 `items` 阶段时才入包（原生 `Battle_Win_mRun` 子状态 2：经验与金币发完、
	# 窗口还开着才逐件 `Item_stdAddEx`）；开窗与经验金币阶段背包必须原样、提示一条都不加。
	var story = Story.new(_resources, Story.initial_progress(0, 2))
	var delivered: Array = []
	terminal.settlement_drops.connect(func(model: RefCounted) -> void:
		delivered.append(model)
		story.apply_battle_drops(model))
	assert_true(in_result and window.stage == "gain" and delivered.is_empty() and
		story.progress["inventory"].is_empty() and story.take_effects().is_empty(),
		"the result window opens without touching the bag or pushing an obtained notice")
	# 窗口得真的在屏上、而且是原生那张 228×240 的 Box4（`Battle_Win_Draw:49`），不是只剩一条头带的
	# 开窗首帧。
	assert_eq([window.is_visible_in_tree(), Rect2i(window.get_node("Bounds").get_global_rect())],
		[true, Rect2i(RESULT_WINDOW_ORIGIN, RESULT_WINDOW_SIZE)],
		"the settlement window is on screen as the native 228×240 Box4 frame")
	# 等级数字是 `Battle_Win_DrawGage:26` 的 `Menu_numDrawNumber(0, x + 165, …, TOP_LEFT)`：
	# 左对齐、且整块落在列表圆框内（右对齐会把数字推到窗口右缘之外）。
	var frame_right: float = window.get_node("Content/ListFrame").get_global_rect().end.x
	var levels_inside := true
	for row: String in ["Row0", "Row1", "Row2", "Row3"]:
		var level: Control = window.get_node("Content/%s/Gage/Level" % row)
		levels_inside = levels_inside and int(level.alignment) == BoxContainer.ALIGNMENT_BEGIN \
			and level.get_global_rect().end.x <= frame_right
	assert_true(levels_inside,
		"every row's level number is left-aligned and stays inside the list frame")
	# 书类道具的名字记录键在 `common/item_skill.dat`（`ItemDefinition.name_source`）；结算行
	# 只查 `item_basic.dat` 时会退回 `--`，而同一件的入手提示（消息栈）却是正确名字。
	assert_ne(window._presentation.item_name(
		{"name_record": "item_skill.group.0.entry.0.name"}), "--",
		"a skill book row resolves its name from the skill text source")
	_key(terminal, KEY_ENTER)
	var drops: Array = terminal.settlement.items
	var obtained: Array = story.take_effects()
	assert_true(window.stage == "items" and delivered.size() == 1 and
		delivered[0] == terminal.settlement and not drops.is_empty() and
		obtained.size() == drops.size() and
		obtained.all(func(effect: Dictionary) -> bool: return effect.kind == "item-obtained") and
		story.progress["inventory"].size() > 0,
		"the items stage adds every drop to the bag and pushes one obtained notice per item")
	# 涨数停在终值：快进后经验与金币的剩余量全部归零（原生子状态 2 才允许离开）。
	assert_true(terminal.settlement.is_finished() and
		int(terminal.settlement.money_left) == 0 and
		terminal.settlement.rows.all(func(row: Dictionary) -> bool:
			return int(row.experience_left) == 0),
		"the experience and money counters stop at their final values")
	_click(window.get_node("Content/Confirm"))
	var bag: Dictionary = story.progress["inventory"].duplicate(true)
	story.apply_battle_settlement(terminal.settlement)
	assert_true(_outcomes.size() == 1 and
		_outcomes.back().result == "won" and _outcomes.back().has("settlement") and
		story.progress["inventory"] == bag and story.take_effects().is_empty(),
		"victory awaits confirmation, writes back the remaining settlement and never re-adds a drop")
	terminal.free()
	# 战斗内系统菜单（原生状态 30 CLEAR 的 4 项设定列表，及其分派到的 31／32／33）：
	# 指令菜单的 CLR（`Battle_Menu_mKeyPressed` 的 case 0，a1 = -16）开出列表。
	var sys_model := _battle()
	var sys_view := _view(sys_model)
	var menu: Control = sys_view.get_node("SysMenu")
	# 主菜单「是」的结局是回标题（`Game_out()`），与逃跑／放弃的 `abandoned` 分开统计。
	var titles: Array = []
	var abandonments: Array = []
	sys_view.title_requested.connect(func(_items: Dictionary): titles.append(true))
	sys_view.abandoned.connect(func(_items: Dictionary): abandonments.append(true))
	sys_view.press("Escape")
	menu.get_node("List/AnimationPlayer").advance(0.2)
	assert_true(sys_view.phase == "sys" and menu.is_open() and
		menu.page == SysMenuScript.Page.CLEAR and menu.cursor == SysMenuScript.ReturnCode.MENU and
		menu.get_node("List/Content/Option3").is_visible_in_tree(),
		"CLR in the command menu opens the native four-item settings list")
	# 游标 1 → 返回码 1 → 原生状态 31 环境设定（`Menu_Setup_Draw`）；关窗后回到列表时
	# `SetNext(BATTLE_STATE_CLEAR, 1)` 把游标停回环境设定那一行。游标 2 → 返回码 2 →
	# 原生状态 32 帮助页（`Menu_info1_Draw` + `skt/method.fxt`），返回同样停回自己那行。
	menu.handle_key("ArrowDown")
	menu.handle_key("Enter")
	menu.get_node("List/AnimationPlayer").advance(0.2)
	menu.get_node("Settings/AnimationPlayer").advance(0.2)
	var settings_open: bool = menu.page == SysMenuScript.Page.SETUP and \
		menu.get_node("Settings/Content/Row0").is_visible_in_tree()
	# 环境设定改值当场生效（`Menu_Setup_mKeyPressed`）：音量行右移一格立刻报出
	# 「哪一行从多少改到多少」，启动层据此 `EFC_mdaVOLUME` + `EFC_mdaPlayDATA(123)` 试听；
	# 落盘仍只在 CLR（`Param_setupSAVE`），所以这里只看请求与页面值。
	var applied: Array = []
	sys_view.setting_changed.connect(
		func(values: Dictionary, key: String, previous: int) -> void:
			applied.append([key, previous, int(values.volume)]))
	menu.handle_key("ArrowDown")
	menu.handle_key("ArrowDown")
	var volume_before: int = int(menu.settings.volume)
	menu.handle_key("ArrowRight")
	assert_true(applied.size() == 1 and applied[0][0] == "volume" and
		applied[0][1] == volume_before and int(menu.settings.volume) != volume_before,
		"changing the volume row reports the native volume effect right away")
	menu.handle_key("Escape")
	menu.get_node("Settings/AnimationPlayer").advance(0.2)
	menu.get_node("List/AnimationPlayer").advance(0.2)
	menu.handle_key("ArrowDown")
	menu.handle_key("Enter")
	menu.get_node("List/AnimationPlayer").advance(0.2)
	menu.get_node("Method/Frame/AnimationPlayer").advance(0.2)
	var method_open: bool = menu.page == SysMenuScript.Page.METHOD and \
		menu.get_node("Method/Body").is_visible_in_tree()
	menu.handle_key("Escape")
	menu.get_node("Method/Frame/AnimationPlayer").advance(0.2)
	assert_true(settings_open and method_open and menu.page == SysMenuScript.Page.CLEAR and
		menu.cursor == SysMenuScript.ReturnCode.METHOD,
		"both subpages open from the list and return with their own return code")
	# 返回码 3 → 原生状态 33 主菜单：两项确认窗，游标初值在「否」，按「是」= `Game_out()`。
	menu.get_node("List/AnimationPlayer").advance(0.2)
	menu.handle_key("ArrowDown")
	menu.handle_key("Enter")
	menu.get_node("List/AnimationPlayer").advance(0.2)
	menu.get_node("Prompt/AnimationPlayer").advance(0.2)
	var prompt_open: bool = menu.page == SysMenuScript.Page.MAINMENU and \
		menu.get_node("Prompt/Content/Yes").is_visible_in_tree()
	menu.handle_key("ArrowRight")
	menu.handle_key("Enter")
	menu.get_node("Prompt/AnimationPlayer").advance(0.2)
	assert_true(prompt_open and sys_view._closed and titles.size() == 1 and abandonments.is_empty(),
		"the main-menu page asks before leaving and its yes asks the caller to return to the title")
	sys_view.free()
	# 边界页（`_boundary`，加载失败／原战斗未支持时那条）：文案与确认出口同一判据——事件战
	# （`allow_flee` 假，文案「返回标题」）走 `Game_out()` 那条回标题，逃生战（`allow_flee` 真，
	# 文案「返回地图」）走 `_abandon()`。
	var event_model := _battle()
	var event_view := _view(event_model)
	var event_titles: Array = []
	var event_abandons: Array = []
	event_view.title_requested.connect(func(items: Dictionary): event_titles.append(items))
	event_view.abandoned.connect(func(_items: Dictionary): event_abandons.append(true))
	event_view._boundary("测试边界")
	event_view.press("Enter")
	var wild_model := _battle()
	wild_model.allow_flee = true
	var wild_view := _view(wild_model)
	var wild_titles: Array = []
	var wild_abandons: Array = []
	wild_view.title_requested.connect(func(_items: Dictionary): wild_titles.append(true))
	wild_view.abandoned.connect(func(_items: Dictionary): wild_abandons.append(true))
	wild_view._boundary("测试边界")
	wild_view.press("Enter")
	assert_true(event_titles.size() == 1 and event_abandons.is_empty() and
		wild_abandons.size() == 1 and wild_titles.is_empty(),
		"the boundary page dispatches by the same rule its caption uses: event battles to the title, escape battles to the map")
	# 「用时就扣」的替代实现：两条离开战斗的结局都要把本战用掉的道具交出去
	# （`Battle_Capture_Action_IsCapture:123`、`Battle_Die_mKeyPressed` 的 `0x31DD0`）。
	var spent_model := _battle()
	spent_model.allow_flee = true
	var spent_view := _view(spent_model)
	var spent_items: Array = []
	spent_view.abandoned.connect(func(items: Dictionary): spent_items.append(items))
	spent_view._used_items[ItemEffect.super_marble_id()] = 1
	spent_view._abandon()
	assert_true(spent_items.size() == 1 and
		int(spent_items[0].get(ItemEffect.super_marble_id(), 0)) == 1,
		"leaving through the map also hands the used items to the caller")
	spent_view.free()
	event_view.free()
	wild_view.free()
	# AUTO 是整场持续的开关（原生 `BattleData + 24`：`BattleCanvas_mKeyPressed:27` 翻转、
	# `Battle_Menu_Auto:53` 每帧读），不是「帮我打一手」。触控按住时的抖动不能再发一次
	# 同一个键——`_refresh_display()` 每帧都 `present()`，过去把「当前按住的键」传成 0 会冲掉锁存，
	# 一次按住就变成开→关，表现成「按一次只走一手」。
	var auto_model := _battle()
	var auto_view := _view(auto_model)
	var auto_taps: Array = []
	auto_view.get_node("TouchControls").key_pressed.connect(
		func(key: int) -> void: auto_taps.append(key))
	var auto_at: Vector2 = auto_view.get_node("TouchControls/Auto").get_global_rect().get_center()
	_touch_down(auto_at)
	_touch_move(auto_at + Vector2(1, 0))
	_touch_up(auto_at + Vector2(1, 0))
	assert_true(auto_view.auto_mode and auto_taps == [auto_view.TouchKey.AUTO],
		"one tap with a held-finger jitter flips AUTO once and leaves it on")
	var auto_turns := int(auto_model.turns)
	for hand in 2:
		_complete_action(auto_view)
	assert_true(int(auto_model.turns) == auto_turns + 2 and
		auto_view.phase in ["action", "position", "result"] and
		auto_view.get_node("TouchControls/Auto").get_node("AnimationPlayer").current_animation == &"bright",
		"AUTO on keeps auto-advancing hand after hand and pulses the key bright")
	# 常亮期间按钮仍是 idle 那层半透明，变化只在亮度：原生 `EFC_mainTouchDRAW:138-162` 把
	# `v18`（0 与 128 之间来回）交给 `GRP_MODE_BRIGHT`，四档只是按帧号取样的量化痕迹。
	var auto_button := auto_view.get_node("TouchControls/Auto")
	var auto_player: AnimationPlayer = auto_button.get_node("AnimationPlayer")
	auto_player.seek(BRIGHT_PEAK_SECONDS, true)
	var bright_material: ShaderMaterial = auto_button.get_node("Anchor/Visuals/Base").material
	assert_eq([auto_button.get_node("Anchor/Visuals").modulate.a,
		int(bright_material.get_shader_parameter("native_brightness"))], [0.5, BRIGHT_UPPER_BOUND],
		"AUTO keeps the semi-transparent key and breathes up to the native brightness bound")
	auto_player.seek(0.0, true)
	assert_eq(int(bright_material.get_shader_parameter("native_brightness")), 0,
		"the breathing brightness returns to the native lower bound")
	auto_view._touch_command(auto_view.TouchKey.AUTO)
	var safety := 0
	while auto_view.phase not in ["command", "result"] and safety < 12:
		_complete_action(auto_view)
		safety += 1
	assert_true(not auto_view.auto_mode and auto_view.phase == "command" and
		auto_view._buttons.size() == 5,
		"turning AUTO off hands the next hand back to the command window")
	# 常驻三键的键码与命中区按原生：`EFC_mainTouchDRAW:117-123` 画 MON INFO 42 于 `(25,45)`、CAPTURE 35 于
	# `(width−25,45)`；`:138-163` 画 AUTO 48 于 `(n75,n45)`＝width>399 时的 `(30,90)`。命中区一律是
	# `EFC_mainTouchBUTTON2` 里的 `EFC_mainTouchSET(key, 1, a2−20, a3−20, 40, 40)`，即中心各减 20 的 40×40。
	var resident: Node2D = auto_view.get_node("TouchControls")
	assert_eq([
		resident.get_node("MonsterInfo").key, resident.get_node("MonsterInfo").get_rect(),
		resident.get_node("Auto").key, resident.get_node("Auto").get_rect(),
		resident.get_node("Capture").key, resident.get_node("Capture").get_rect(),
	], [
		auto_view.TouchKey.MON_INFO, Rect2(5, 25, 40, 40),
		auto_view.TouchKey.AUTO, Rect2(10, 70, 40, 40),
		auto_view.TouchKey.CAPTURE, Rect2(355, 25, 40, 40),
	], "the resident battle keys carry the native codes and 40×40 hit rects")
	auto_view.free()
	# 伤害信息进栈消息：原生 `Param_dmg2BASIC` 的 `0x79056` 在本次伤害 > 0、相性有利／
	# 不利时推 `JC_fxt2Return(407／408)`（「属性相克导致技能伤害上升／下降」）。
	# 消息栈现在是 autoload：先确认全局那份在战斗推送前就挂好了，再换成用例自己的实例。
	var global_stack: Control = get_node_or_null("/root/Messages") as Control
	assert_true(global_stack != null and global_stack.count() > 0,
		"the message stack mounts before the battle pushes anything")
	global_stack.clear_all()
	var stack: Control = StackScene.instantiate()
	add_child_autofree(stack)
	stack.set_process(false)
	# 只有技能推这条：`Param_dmg2BASIC` 的唯一调用点是 `Battle_Skill_init`，
	# 普攻走 `Param_dmg1BASIC`，一条都不推。物种 49 的普攻正好有两段命中帧
	# （`battle-species.tres`：第 5 帧 50%／第 9 帧 100%），以前每段推一条，玩家看到的就是
	# 「一次相克输出两遍」；相反，物种 49 的技能只有第 10 帧一段，正好一条。
	var physical_model := Battle.new([_ball(93, 900, 1), _ball(62, 800), _ball(86, 700)],
		[_ball(49, 100, 0), _ball(1099), _ball(13)],
		func(_limit: int) -> int: return 0)
	physical_model.actor = 3
	var physical_view := _view(physical_model)
	stack.clear_all()
	var enemy_hp := int(physical_model.balls[0].hp)
	physical_view._buttons[0].pressed.emit()
	_complete_command(physical_view)
	_key(physical_view, KEY_SPACE)
	_advance_action(physical_view)
	assert_true(int(physical_model.balls[0].hp) < enemy_hp and
		not _stack_texts(stack).any(_is_attribute_notice),
		"a two-hit physical attack lands both hits but pushes no attribute notice")
	physical_view.free()
	var strong_model := Battle.new([_ball(93, 900, 1), _ball(62, 800), _ball(86, 700)],
		[_ball(49, 100, 0), _ball(1099), _ball(13)],
		func(_limit: int) -> int: return 0)
	strong_model.actor = 3
	var strong_view := _view(strong_model)
	stack.clear_all()
	strong_view._buttons[1].pressed.emit()
	_complete_command(strong_view)
	_key(strong_view, KEY_SPACE)
	_advance_action(strong_view)
	var notices: Array = _stack_texts(stack).filter(_is_attribute_notice)
	assert_eq(notices.size(), 1,
		"one advantaged skill hit pushes the attribute notice exactly once")
	# 同一次行动的多段命中只推一条：原生在 `Battle_Skill_init` 阶段就把每个目标的相性判定完，
	# 工程把伤害摊到各命中帧上，不收敛会在一次攻击里连弹好几条（用户要求「每次攻击只弹一次」）。
	stack.clear_all()
	strong_view._attribute_reported.clear()
	var strength := int(strong_view.ATTRIBUTE_ADVANTAGE)
	for frame in [1, 2]:
		strong_view._render_step({"actor": 3, "action": AniAction.Clip.SKILL, "frame": frame,
			"hits": [{"target": 0, "damage": 1, "skill": true, "strength": strength}]})
	assert_eq(_stack_texts(stack).filter(_is_attribute_notice).size(), 1,
		"two skill hits in one action push the attribute notice only once")
	# 换色来自翻译资源的段色标记：`msg.fxt:407` 的正文以 `[color=#FFFF00]` 开头（黄）。
	var segments: Array = []
	if notices.size() == 1:
		segments = StackScript.text_segments(notices[0])
	assert_true(segments.size() == 1 and
		StackScript.rgb_color(int(segments[0].rgb)) == Color8(0xFF, 0xFF, 0x00),
		"the advantage notice keeps the native yellow of msg.fxt:407")
	# 不利相性（`msg.fxt:408`）走同一条路径取到红色段色。
	stack.clear_all()
	strong_view._attribute_reported.clear()
	strong_view._render_step({"actor": 3, "action": AniAction.Clip.SKILL, "frame": 1,
		"hits": [{"target": 0, "damage": 1, "skill": true,
			"strength": int(strong_view.ATTRIBUTE_DISADVANTAGE)}]})
	var disadvantage_notices: Array = _stack_texts(stack).filter(_is_attribute_notice)
	var disadvantage_segments: Array = []
	if disadvantage_notices.size() == 1:
		disadvantage_segments = StackScript.text_segments(disadvantage_notices[0])
	assert_true(disadvantage_segments.size() == 1 and
		StackScript.rgb_color(int(disadvantage_segments[0].rgb)) == Color8(0xF0, 0x00, 0x00),
		"the disadvantage notice keeps the native red of msg.fxt:408")
	# 被动发动（原生 `Param_atkPASSIVE` 的 `0x789C2` → `JC_fxt2Return(556)`）：`Param_dmg1PASSIVE`
	# 掷中后模型把发动者序号带进命中结果，界面拼「[被动记录名] 发动」推栈（记录名来自
	# `common/item_skill.dat` 的 `item_skill.group.<号>.name`，也就是 `Item_datBasic` 类型 31 的
	# `name_text`）。同一次行动里每只只弹一次——原生一次攻击只调一次 `Param_dmg1PASSIVE`，
	# 工程把伤害摊到多个命中帧，多段命中会重复推同一条。
	stack.clear_all()
	strong_view._passive_reported.clear()
	var passive_owner := 3
	var passive_text := "[%s] %s" % [
		_assets.text_message("common/item_skill.dat",
			"item_skill.group.%d.name" % Battle.passive_id_of(strong_view.battle.balls[passive_owner])),
		StackScript.visible_text(_assets.text_message(Msg.SOURCE, Msg.Id.PASSIVE_ACTIVATED))]
	var passive_step := {"actor": passive_owner, "action": AniAction.Clip.ATTACK, "frame": 1,
		"hits": [{"target": 0, "damage": 1, "activated_passives": [passive_owner]}]}
	strong_view._render_step(passive_step)
	strong_view._render_step(passive_step)
	var passive_notices: Array = _stack_texts(stack).filter(func(text: String) -> bool:
		return StackScript.visible_text(text) == passive_text)
	var passive_segments: Array = []
	if passive_notices.size() == 1:
		passive_segments = StackScript.text_segments(passive_notices[0])
	assert_true(passive_notices.size() == 1 and passive_segments.size() == 1 and
		StackScript.rgb_color(int(passive_segments[0].rgb)) == Color8(0xF0, 0xF0, 0x00),
		"a landed passive pushes the 556 notice once per hand, in the native ally palette colour")
	# 逐次伤害本身是场上数字（`Param_dmgNUMBER` 的 kind 14 对象），**不进提示栈**。
	assert_false(_stack_texts(stack).any(func(text: String) -> bool: return text.contains("HP")),
		"per-hit damage text never reaches the message stack")
	# 其余战斗反馈在原生是 `Game_infoInit` 的提示栈消息（`Game_infoDraw` 每条先铺半透明黑底），
	# 战斗窗自己的 `$Message` 只剩边界态面板，不再有一块承载普通反馈的裸标签。
	stack.clear_all()
	strong_view._set_note("SP不足。")
	assert_true(_stack_texts(stack).has("SP不足。"),
		"ordinary battle feedback goes to the global message stack that draws the black plate")
	assert_null(strong_view.get_node_or_null("Message/Note"),
		"the battle window keeps no bare label for ordinary feedback")
	strong_view._set_note("原战斗边界", strong_view.NoteChannel.BOUNDARY)
	assert_true(strong_view.get_node("Message/Boundary").visible,
		"the boundary panel still shows boundary text on the battle window")
	strong_view.free()
	# 技能横幅（`Battle_Skill_mPaint`）：技能态头 16 帧在画面上方画一条半透明黑带、写技能名、
	# 两侧各一个 8×8 装饰，并把施术者精灵画在黑带自己那一侧；普攻的 `Battle_Attack_mPaint`
	# 没有这一段。黑带高度、文字横向偏移与立绘横向偏移是原生常量区（`0x97C8C + 0x5c` 起
	# 32 字节）里的按帧表，alpha 是 `JC_grpSetMODE(GRP_MODE_ALPHA, 128)` 的 128/256。
	var banner_model := _battle()
	var banner_view := _view(banner_model)
	var banner: Control = banner_view.get_node("Field/SkillBanner")
	var band: ColorRect = banner.get_node("Band")
	banner_view._buttons[1].pressed.emit()
	_complete_command(banner_view)
	_key(banner_view, KEY_SPACE)
	var skill_shown: bool = banner.visible and banner_view.phase == "action"
	# 进入 → 保持 → 收起：物种 49 的技能动作只有 14 帧，收带段的后两帧落在状态 25 POSITION
	# 里，所以这条同时钉住「动作一收尾就 clear()」不会把退出段整段切掉。
	var seen: Array = []
	var still_open := false
	var guard := 0
	while banner_view.phase in ["action", "position"] and guard < 400:
		guard += 1
		if banner_view.phase == "position" and not still_open:
			still_open = banner.visible
		banner_view.get_node("ActionTimeline").advance(banner_view.STEP_SECONDS)
		if banner.visible and (seen.is_empty() or seen[-1] != int(band.size.y)):
			seen.append(int(band.size.y))
	assert_eq([seen, still_open, banner.visible], [[2, 48, 40, 38, 48, 38, 2], true, false],
		"the skill banner grows, holds and closes even after the skill action itself ends")
	banner_view._render_step({"actor": 3, "action": AniAction.Clip.ATTACK, "frame": 0, "hits": []})
	assert_eq([skill_shown, banner.visible], [true, false],
		"the skill banner shows on skill steps and stays away on a plain attack")
	var skill_name: String = banner_view.get_node("Field")._skill_text(banner_model.balls[3])[0]
	banner.show_skill(banner_model.balls[3], 0, skill_name)
	var heights: Array = []
	for step in 16:
		heights.append(banner.BAND_HEIGHTS[banner.phase_for_step(step)])
	assert_eq([band.size, band.modulate.a, heights],
		[Vector2(400, 2), 0.5, [2, 2, 2, 48, 40, 38, 38, 38, 38, 38, 38, 38, 38, 48, 38, 2]],
		"the skill banner keeps a 400-wide band, alpha 128/256 and its native per-frame heights")
	var clip: Control = banner.get_node("Clip")
	banner.show_skill(banner_model.balls[3], 5, skill_name)
	assert_eq(clip.get_global_rect(), band.get_global_rect(),
		"the caster portrait is clipped to exactly the band rectangle")
	var label: Control = banner.get_node("Name")
	var text_center_x: float = band.get_global_rect().position.x + band.size.x / 2.0 + \
		banner.TEXT_OFFSETS[banner.HOLD_PHASE]
	assert_eq([banner.get_node("DecoLeft").get_global_rect().get_center().x,
		banner.get_node("DecoRight").get_global_rect().get_center().x],
		[text_center_x - label.size.x / 2.0 - banner.DECORATION_GAP,
			text_center_x + label.size.x / 2.0 + banner.DECORATION_GAP],
		"the two 8x8 decorations sit ten pixels outside the skill name")
	# 立绘按施术者所在侧画：原生 `x = (立绘偏移 + 48) * v13 + 视口宽 / 2`，敌方 `v13 = -1`，
	# 所以我方在右半边、敌方在左半边，两者关于视口中心镜像，且都裁在横带里。
	var portrait: Node2D = banner.get_node("Clip/Portrait")
	var player_x: float = clip.position.x + portrait.position.x
	var player_clipped: bool = clip.get_global_rect() == band.get_global_rect()
	banner.show_skill(banner_model.balls[0], 5, skill_name)
	var enemy_x: float = clip.position.x + portrait.position.x
	assert_eq([player_x > band.size.x / 2.0, enemy_x < band.size.x / 2.0, player_x + enemy_x,
		player_clipped, clip.get_global_rect() == band.get_global_rect()],
		[true, true, band.size.x, true, true],
		"the caster portrait sits on its own side of the band and stays clipped to it")
	# 技能态底图压暗（`Battle_mapDraw`）：`v9 = {208, 160, 112, 64}` 四档、每档 1 帧（0.05 秒），
	# 只乘底图那四次 `Object_drawBASIC`。四档关键帧写在 `Field/DimPlayer` 的 `dim` 里，
	# `_dim_backdrop()` 只切动画状态；分量按 `EFC_pixel_MULTIPLY_COLOR_Proc` 的 `/256` 折算。
	var dim_field: Control = banner_view.get_node("Field")
	var dim_player: AnimationPlayer = dim_field.get_node("DimPlayer")
	dim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var dim_clip: Animation = dim_player.get_animation(FieldScript.DIM_CLIP)
	var dim_keys: Array = []
	for key in dim_clip.track_get_key_count(0):
		dim_keys.append(roundi(dim_clip.track_get_key_value(0, key).r * FieldScript.DIM_SCALE))
	var per_frame: bool = is_equal_approx(dim_clip.track_get_key_time(0, 1), banner_view.STEP_SECONDS)
	dim_field._dim_backdrop(FieldScript.DIM_FIRST_STEP)
	dim_player.seek(0.0, true)
	var dimmed: Array = []
	for backdrop in ["Background", "Ground", "Foreground"]:
		dimmed.append(roundi(dim_field.get_node(backdrop).modulate.r * FieldScript.DIM_SCALE))
	dim_field._dim_backdrop(-1)
	var restored: Array = []
	for backdrop in ["Background", "Ground", "Foreground"]:
		restored.append(dim_field.get_node(backdrop).modulate)
	assert_eq([dim_keys, per_frame, dimmed, restored],
		[[FieldScript.DimLevel.FIRST, FieldScript.DimLevel.SECOND, FieldScript.DimLevel.THIRD,
			FieldScript.DimLevel.FOURTH], true, [FieldScript.DimLevel.FIRST,
			FieldScript.DimLevel.FIRST, FieldScript.DimLevel.FIRST],
			[Color.WHITE, Color.WHITE, Color.WHITE]],
		"the skill banner dims the backdrop through the four native levels and restores it")
	banner_view.free()
	# 战斗对象的位置：原生把坐标只交给 `Object_objPOS` 的几处调用点（见
	# `wiki\battle\battle-performance.md`「战斗站位、镜头与底部说明框」）。这三条钉住「回合开始后移、
	# 攻击帧摆到受击者身前、状态 25 滑回编队槽并把镜头插回加载焦点」，任何一处被改坏都会在这里响。
	var pose_model := _battle()
	var pose_view := _view(pose_model)
	var pose_field: Control = pose_view.get_node("Field")
	# 状态 11 CHARACTER：`Battle_Character_mRun` 行动者 `a4 = -run_counter`、同侧其余
	# `a4 = -5 * run_counter`，`Battle_objGetPosition` 两侧都是后退（我方 x +、敌方 x −）。
	pose_view.get_node("Actions/Commands/Art/AnimationPlayer").advance(0.3)
	pose_view._refresh_display()
	assert_eq([pose_field.actor_shift(3), pose_field.actor_shift(4), pose_field.actor_shift(0)],
		[Vector2(5, 0), Vector2(25, 0), Vector2.ZERO],
		"the acting monster steps back 5px and its row 25px while the enemy side holds")
	# 状态 15 ATTACK：`Battle_Monster_procPosition` 对 form 1／code 1 的帧给
	# `Battle_objGetPosition2(受击者, a4: 17)` ＋ `y + 1`；物种 93 的攻击在 `battle-poses.tres` 里
	# 正是第 0 帧 `(form 1, code 1)`，受击者是敌方第一行 (120, 182)、自己是我方第一行 (283, 182)。
	pose_view._buttons[0].pressed.emit()
	_complete_command(pose_view)
	_key(pose_view, KEY_SPACE)
	assert_eq(pose_field.actor_shift(3), Vector2(-146, 1),
		"an attack frame puts the body 17px in front of the victim's slot, one pixel lower")
	# 原生 `Battle_Monster_procPosition` 只给 form 1／2 的帧算落点（form 0 直接返回、不写坐标），
	# 所以表中「form 1 之后又出现 form 0」的变化点必须沿用上一条指令。物种 41 的技能是
	# 第 0 帧 `(form 1, code 0)`、第 9 帧回到 `form 0`：第 9 帧应与第 8 帧同一条指令，
	# 而不是被当成 `(0, 0)` 让本体瞬回编队槽。
	var held_command: Vector2i = BattlePoses.command(
		MonsterAnimation.battle_identity(41), AniAction.Clip.SKILL, 8)
	assert_eq([held_command != Vector2i.ZERO,
		BattlePoses.command(MonsterAnimation.battle_identity(41), AniAction.Clip.SKILL, 9)],
		[true, held_command],
		"a form 0 change point keeps the previous offset instead of snapping the body to (0, 0)")
	# 状态 25 POSITION：`Battle_Position_mRun` 每帧半程收敛回编队槽（-146 → -73 → … → 0），
	# 镜头由同函数的 `Battle_mapFOCUS` 插回 `BattleCanvas_load` 存下的焦点
	# (202, 244)——不是下一位行动者的槽位，否则滑回期间整幅画面多偏 18 像素。
	var pose_timeline: AnimationPlayer = pose_view.get_node("ActionTimeline")
	var pose_guard := 0
	while pose_view.phase == "action" and pose_guard < 500:
		pose_timeline.advance(pose_view.STEP_SECONDS)
		pose_guard += 1
	pose_timeline.advance(pose_view.STEP_SECONDS)
	var return_focus: Vector2 = pose_view._camera_focus(3)
	var half_way: Vector2 = pose_field.actor_shift(3)
	_complete_action(pose_view)
	assert_true(half_way == Vector2(-73, 0) and
		is_zero_approx(pose_field.actor_shift(3).x) and is_zero_approx(pose_field.actor_shift(3).y) and
		return_focus == pose_field.load_focus(),
		"state 25 halves the offset back to the formation slot and refocuses the load focus")
	# 本体段也要吃同一份 dash（`bm-P2-319`）：物种 69 的攻击由 `Battle_Monster_0069_procNext`
	# 接到 20 段，那段 `case 20` 写 `x += 32 * ~n`（= −(n + 1)，我方 −x），首帧本体就该走 32px。
	assert_eq(pose_field._body_dash({"species": 69, "direction": BattleSide.Code.PLAYER},
		AniAction.Clip.CLONE_A, 0), -32.0,
		"the body's chained dash segment feeds its native first-frame displacement to `_seat`")
	pose_view.free()
	# 分身冲刺（`Battle_Monster_00NN_procCurr` 的 `case 20／21`：`x += 32 * (n + 1)`，我方
	# `32 * ~n`）：这段只做位移、不带命中，`dash` 一旦算成 0，分身就停在攻击者身上不动——
	# 技能／攻击的「冲出去」表现全靠它。物种 49 技能第 7 帧的分身、物种 2 攻击第 4 帧的分身。
	var skill_clone: Dictionary = BattleSpeciesTable.segments(49, true)[0]["clones"][0]
	var attack_clone: Dictionary = BattleSpeciesTable.segments(2, false)[0]["clones"][0]
	assert_true(int(skill_clone["dash"]) == 32 and int(attack_clone["dash"]) == 32,
		"clone segments keep the native 32px-per-frame dash coefficient")
	# 相位：物种 49 的 `case 21` 写 `x += 32 * ~n`（= −(n + 1)），首帧就走 32px；物种 92 的
	# `case 20` 写 `x -= 32 * n`，首帧位移必须仍是 0（`bm-P2-320` 那 32 像素差）。
	var phased_clone: Dictionary = BattleSpeciesTable.segments(92, false)[0]["clones"][0]
	assert_eq([BattleModel.dash_offset(BattleSide.Code.PLAYER, 0, 32,
			int(skill_clone["dash_addend"])),
		BattleModel.dash_offset(BattleSide.Code.PLAYER, 0, 32, int(phased_clone["dash_addend"]))],
		[-32.0, 0.0], "the dash phase follows the native `(n + 1)` / `n` form of the segment")
	# 每个敌人各建一具（`Battle_Monster_0062_procCurr` 按 `BattleData + 20706` 的循环建分身）：
	# `all` 的分身按目标序号逐个展开，不再只产出一具、全叠在攻击者槽位上（`bm-P2-321`）。
	# 物种 62「巨鳄镜像」的分身就是 `all`。
	var mirror: Dictionary = BattleSpeciesTable.segments(62, true)[0]["clones"][0]
	var mirror_plan: Array = [{"start": 6, "action": AniAction.Clip.CLONE_B, "frames": 12,
		"dash": int(mirror["dash"]), "dash_addend": int(mirror["dash_addend"]),
		"all": bool(mirror["all"])}]
	var mirror_steps: Array = model._clone_steps(mirror_plan, 7, BattleSide.Code.PLAYER, 3, 0,
		[0, 1, 2])
	assert_eq(mirror_steps.map(func(step: Dictionary) -> Array: return [step["origin"],
		step["target"]]), [[3, 0], [3, 1], [3, 2]],
		"an `all` clone is drawn once per enemy, each hung on its own target index")
