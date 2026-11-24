extends "res://tests/unit/gut_case.gd"

const Runtime = preload("res://prime/prime_title_runtime/prime_title_runtime.gd")
const StartupRuntime = preload("res://prime/startup_runtime/startup_runtime.gd")
const StartupPreload = preload("res://core/startup_preload/startup_preload.gd")
const StartupFooter = preload("res://prime/startup_footer/startup_footer.tscn")
const Store = preload("res://core/save_store/save_store.gd")
const TouchCode = preload("res://core/touch_code/touch_code.gd")
const Story = preload("res://core/story/story.gd")
const BookMonster = preload("res://menu/book_monster/book_monster.gd")
## 夹具：真实预载只到 25%，远低于 1500／3000 的计时节奏，用来验证填充宽取两者较小值。
const FIXTURE_LOAD_RATIO := 0.25
## 夹具文案：确认键文本不参与断言，只满足 `startup_footer.present` 的入参。
const FIXTURE_LABEL := "OK"

## 一帧的模拟步长（秒）：大于各页最慢的 80 ms 间隔，保证每次 `tick` 都真的分发一次按键。
const STEP_SECONDS := 0.1
## 新游戏＝未占用的存档槽 0：`slot_runtime` 对空槽发 `target 12`（原生 `Game12:Game_New`）。
const NEW_GAME_SLOT := 0
const NEW_GAME_TARGET := 12
## 启动阶段步数上限：欢迎页满 3000 ms（60 步）才认确定键，LOGO 还要 149 帧才换 TITLE。
const STARTUP_STEP_LIMIT := 400
## 剧情推进步数上限：新手三连（事件 0→1→2）含等待、镜头、行走与一场脚本战斗。
const STORY_STEP_LIMIT := 6000
## 新手确认后队伍三只（`Game_Book_Monster_mKeyPressed:84-94`）。
const STARTER_PARTY_SIZE := 3
## 新手剧情的事件号：0（开场）→ 1（营救雷亚＋脚本战斗 60）→ 2（选精灵）；跑完事件 2 才换到 3。
const STARTER_EVENT_AFTER := 3
## 事件 1 末的脚本战斗（`Op.BATTLE` 的 60 号）最长等多少帧；动画按 `BATTLE_TIME_SCALE` 加速。
const BATTLE_FRAME_LIMIT := 3600
const BATTLE_TIME_SCALE := 6.0
## 战斗里每隔几帧按一次确定：原生指令窗默认「攻击」→ 目标 → 确认。
const BATTLE_PRESS_INTERVAL := 4
## 一格手动走位的位移要走几帧（`_advance_motions` 按 `WALK_SPEED` 推进，一格远小于这个数）。
const MOTION_FRAME_LIMIT := 12
## 一段走位最多迈几格（事件 1 的触发矩形要跨 41→42 两张图，整段约 160 格）。
const WALK_PATH_STEP_LIMIT := 400
## 状态日志的采样间隔（步）。
const LOG_INTERVAL := 200
## 固定随机种子：野生遭遇、掉落与昵称都走全局 RNG（`Story._roll` 在未注入 `_random` 时
## 落到 `randi_range`），不固定种子时同一条链路会因遭遇战次数不同而时红时绿。
const DETERMINISTIC_SEED := 20261123


func _run() -> void:
	await get_tree().process_frame
	# 预载清单顺序（`wiki\ui\startup-preload.md`）：首组是共用 UI 组件，末组是怪物 ANI。
	var plan: StartupPreload = StartupPreload.new()
	var roots := plan.roots()
	assert_true(roots[0] == StartupPreload.GROUP_COMPONENTS and
		roots[roots.size() - 1] == StartupPreload.GROUP_MONSTERS,
		"预载清单首组应为共用 UI 组件、末组应为怪物 ANI")
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var runtime = main._runtime
	for index in range(62):
		runtime.tick(0.05)
	runtime._dispatch_key(-5)
	runtime.tick(0.05)
	runtime.complete_storage_check(OK)
	assert_true(runtime.scene == Runtime.LOGO)
	# 调试入口（仅验收用）：任意页都能回到欢迎页，进度条从 0 重走（`Prime_NotMem_mPaint@0x6A53C:12`）。
	runtime.debug_open_startup_page()
	var notice: Dictionary = runtime.tick(0.05)
	assert_true(notice.paint.scene == Runtime.NOT_MEM and
		notice.paint.startup_elapsed_ms < StartupRuntime.PROGRESS_FULL_MS)
	var failure := Runtime.new()
	failure.start()
	failure.tick(0.05)
	failure.startup_elapsed_ms = 3001
	failure.key_down(-5)
	failure.tick(0.05)
	var missing := Store.new("user://prime-startup-test-missing-%d" % OS.get_process_id())
	var error: int = missing.check_storage()
	failure.complete_storage_check(error)
	assert_push_error("Prime local save storage check failed")
	var tick: Dictionary = failure.tick(0.05)
	assert_true(tick.paint.scene == Runtime.NOT_SPACE)
	# 进度条填充宽 = 轨道宽 × min(计时 / 3000, 真实预载进度)。
	var footer: Control = StartupFooter.instantiate()
	add_child(footer)
	footer.present(1500, true, FIXTURE_LABEL, FIXTURE_LOAD_RATIO)
	var track: Control = footer.get_node("Progress/Track")
	var fill: Control = footer.get_node("Progress/Fill")
	assert_almost_eq(fill.size.x, track.size.x * FIXTURE_LOAD_RATIO, 1.0)
	footer.queue_free()
	main.queue_free()
	await get_tree().process_frame


func test_legacy_suite() -> void:
	await _run()


## 一条 Prime 帧：等价 `main._process` 的状态推进部分（渲染、后台预载与音频试听不在本用例范围）。
func _prime_frame(main: Node) -> Dictionary:
	var tick: Dictionary = main._runtime.tick(STEP_SECONDS)
	if not tick.is_empty():
		main._apply_effects(tick.effects)
	return tick


## 一次确定键：`key_up` 补一个 0，让 `_held_key` 复位后同一键能再按一次。
func _prime_press(runtime: RefCounted, key: int) -> void:
	runtime.key_down(key)
	runtime.key_up()


func _field_state(field) -> String:
	return "map=%d evt=%d cursor=%d x=%d y=%d party=%d dialogue=%s narration=%s mastery=%s" % [
		int(field.story.progress["mapId"]), int(field.story.progress["eventId"]),
		int(field.story.progress["cursor"]), int(field.story.progress["player"]["x"]),
		int(field.story.progress["player"]["y"]), field.story.progress["monsters"].size(),
		not field.dialogue.is_empty(), not field.narration.is_empty(), not field.mastery.is_empty()]


## 新手剧情里能按确定键推进的门：对话正文、字幕、两级选择。
func _press_story_gate(field) -> bool:
	if field.mastery.is_empty() and field.dialogue.is_empty() and field.narration.is_empty():
		return false
	if int(field.mastery.get("stage", -1)) == Story.MasteryStage.STARTER:
		_select_starter(field)
	else:
		field.press(KEY_ENTER)
	return true


## 二级页是图鉴页形态（`Game_Book_Monster_init`）：光标从第 1 格开始，先右移到第 5 格
## （第一只候选），OK 打开 fxt 101 确认框，框内左移到「是」再 OK 提交。每步只按一次键，
## 靠页面状态决定下一步，开窗动画与确认框动画吃掉的按键不会打乱光标。
func _select_starter(field) -> void:
	var page: Control = field._starter_view
	if page.is_transitioning():
		# 这条 e2e 循环用 `field.advance()` 推进、不产帧，开窗动画不会自己走完；直接落到稳态。
		page.stop_transition()
		return
	if (page.get_node("Confirm") as Control).visible:
		if int(page._answer) == BookMonster.Answer.NO:
			field.press(KEY_LEFT)
		else:
			field.press(KEY_ENTER)
		return
	var cursor := int(page.cursor)
	if cursor != Story.STARTER_FIRST_SLOT:
		field.press(KEY_RIGHT if cursor < Story.STARTER_FIRST_SLOT else KEY_LEFT)
		return
	field.press(KEY_ENTER)


## 战斗（脚本战与野怪遭遇战）：真实 `battle_view` 逐帧跑，确定键即原生指令窗的「攻击 → 目标 → 确认」。
func _finish_battle(field) -> bool:
	var frames := 0
	Engine.time_scale = BATTLE_TIME_SCALE
	while field.battle_view != null and frames < BATTLE_FRAME_LIMIT:
		if frames % BATTLE_PRESS_INTERVAL == 0:
			field.battle_view.press("Enter")
		await get_tree().process_frame
		frames += 1
	Engine.time_scale = 1.0
	print("[new-game] 战斗 %d 帧后 battle_view=%s" % [frames, field.battle_view != null])
	return field.battle_view == null


## 事件首记录的矩形触发（`Story.Trigger.RECT`，原生 `Evt_stdIsPROC:44-57`）：要走到的那张图与那一格。
## `p[1]` 是「x * 100 + y」、`p[2]` 是「宽 * 100 + 高」（`StoryRuntime._trigger` 的取法）。
func _trigger_target(field) -> Dictionary:
	var records: Array = field.story._records(int(field.story.progress["eventId"]))
	if records.is_empty() or not records[0].get("params") is Array:
		return {}
	var params: Array = records[0]["params"]
	if params.size() != 5 or int(records[0].get("opcode", -1)) != Story.Trigger.RECT:
		return {}
	var corner := int(params[1])
	var size := int(params[2])
	var origin := Vector2i(int(corner / 100.0), corner % 100)
	var extent := Vector2i(int(size / 100.0), size % 100)
	return {"map": int(params[0]), "tile": origin + extent / 2}


## 当前地图上通往 `map_id` 的传送点（`move_player` 的换图分支读 `story.map.info.warps` 同一份）。
func _warp_to(field, map_id: int) -> Dictionary:
	for warp: Dictionary in field.story.map.info.get("warps", []):
		if int(warp.get("destination_map_id", -1)) == map_id:
			return warp
	return {}


## 迈一格并等位移走完：`_motions` 空即角色停在新格上、`story.after_move` 已写回 `progress.player`。
func _walk_one(field, direction: Vector2i) -> bool:
	if not field.move_player(direction):
		return false
	for _frame in range(MOTION_FRAME_LIMIT):
		field.advance(STEP_SECONDS)
		if field._motions.is_empty():
			break
	return true


## 朝目标的下一格方向：按 `tile_blocked`（地形标志＋事件走位矩形）与实体占位做反向广度优先。
func _next_direction(field, here: Vector2i, goal: Vector2i, blocked: Dictionary) -> Vector2i:
	var terrain: Dictionary = field.story.map.terrain
	var width := int(terrain.width_tiles)
	var height := int(terrain.height_tiles)
	var previous := {}
	var queue: Array[Vector2i] = [goal]
	var seen := {goal: true}
	while not queue.is_empty():
		var point: Vector2i = queue.pop_front()
		if point == here:
			return previous[here] - here
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next := point + offset
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if seen.has(next) or blocked.has(next) or field.story.tile_blocked(next.x, next.y):
				continue
			seen[next] = true
			previous[next] = point
			queue.append(next)
	return Vector2i.ZERO


## 当前触发条件的走位目标格：跨图时先走本图通往目标图的传送点（`_warp_to`），否则直接是矩形里那一格。
## 踩上传送点会立刻换图（原生 `Map_warpProc` 脚点刚与传送格相交就换，不等走完这一格）。
func _route_goal(field, target: Dictionary) -> Vector2i:
	if int(field.story.progress["mapId"]) != int(target.map):
		var warp := _warp_to(field, int(target.map))
		if warp.is_empty():
			return Vector2i(-1, -1)
		return Vector2i(int(warp.tile_x), int(warp.tile_y))
	return target.tile


func test_new_game_chain() -> void:
	await get_tree().process_frame
	# 同一条链路要可复现：固定全局 RNG，野生遭遇战次数与掉落才不会每次不同。
	seed(DETERMINISTIC_SEED)
	var directory := "user://prime-newgame-check-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	# 真实 user:// 存档不参与本用例：换成本次的空目录，未占用槽位才是新游戏入口。
	main._save_store = Store.new(directory)
	main._refresh_slots()
	var runtime = main._runtime
	var ok_sent := false
	var steps := 0
	while runtime.scene != Runtime.TITLE and steps < STARTUP_STEP_LIMIT:
		if runtime.scene == Runtime.NOT_MEM and not ok_sent and \
				runtime.startup_elapsed_ms > StartupRuntime.PROGRESS_FULL_MS:
			_prime_press(runtime, TouchCode.Key.OK)
			ok_sent = true
		_prime_frame(main)
		steps += 1
	print("[new-game] 启动 %d 步 → scene=%d（TITLE=%d）" % [steps, runtime.scene, Runtime.TITLE])
	assert_eq(runtime.scene, Runtime.TITLE, "欢迎页满 3 秒按 OK → LOGO → TITLE")
	if runtime.scene != Runtime.TITLE:
		main.queue_free()
		return
	# 标题页：第一次 OK 开菜单（未开菜单时任意键都只开菜单），第二次 OK 选第 0 项「新游戏」。
	_prime_press(runtime, TouchCode.Key.OK)
	_prime_frame(main)
	assert_true(runtime.menu_open, "标题页按 OK 打开菜单")
	_prime_press(runtime, TouchCode.Key.OK)
	_prime_frame(main)
	print("[new-game] 菜单 OK → scene=%d（SAVE_SELECT=%d）" % [runtime.scene, Runtime.SAVE_SELECT])
	assert_eq(runtime.scene, Runtime.SAVE_SELECT, "标题第 0 项「新游戏」进存档页")
	# 存档页：空槽按 OK → `save-slot-selected`（target 12）→ 启动层实例化野外运行时。
	assert_eq(runtime.save_slot_selected, NEW_GAME_SLOT, "存档页光标停在空槽")
	_prime_press(runtime, TouchCode.Key.OK)
	var slot_tick := _prime_frame(main)
	var selected := {}
	for effect: Dictionary in slot_tick.get("effects", []):
		if effect.get("kind") == "save-slot-selected":
			selected = effect
	assert_eq([int(selected.get("slot", -1)), int(selected.get("target", -1))],
		[NEW_GAME_SLOT, NEW_GAME_TARGET],
		"空槽确认发 save-slot-selected（槽 0 → Game12:Game_New）")
	print("[new-game] 空槽 OK → boundary=%d field=%s" % [
		runtime.boundary_target, main._field != null])
	assert_true(main._field != null and runtime.boundary_target == -1,
		"空槽确认后进野外（boundary_target=%d）" % runtime.boundary_target)
	if main._field == null:
		main.queue_free()
		return
	var field = main._field
	print("[new-game] 进野外：%s" % _field_state(field))
	var steps_field := 0
	var battles := 0
	var route_map := -1
	var route_blocked := {}
	var stages := {}
	var walk_steps := 0
	while steps_field < STORY_STEP_LIMIT:
		steps_field += 1
		field.advance(STEP_SECONDS)
		if field.battle_view != null:
			battles += 1
			print("[new-game] 第 %d 步进战斗：%s" % [steps_field, _field_state(field)])
			await _finish_battle(field)
			if main._field == null or not is_instance_valid(main._field):
				print("[new-game] 战斗内落败回标题（`Battle_Die_mRun` → `Game_out`）")
				break
			print("[new-game] 战斗结束：%s" % _field_state(field))
			continue
		if not field._encounter.is_empty():
			# 遇敌转场要真实帧（`_capture_encounter` 等 `RenderingServer.frame_post_draw`）。
			await get_tree().process_frame
			continue
		if not field.boundary.is_empty():
			print("[new-game] 第 %d 步落边界：%s" % [steps_field, field.boundary])
			break
		if not field.mastery.is_empty():
			stages[int(field.mastery.get("stage", -1))] = true
			print("[new-game] 第 %d 步选择页（stage=%d）：%s" % [
				steps_field, int(field.mastery.get("stage", -1)), _field_state(field)])
		if _press_story_gate(field):
			continue
		if int(field.story.progress["eventId"]) >= STARTER_EVENT_AFTER:
			break
		if not field.story.stable_state().is_empty():
			# 事件停在首记录等触发条件：RECT（事件 1）要真的走过去；战斗返回由战斗置锁存（事件 2）。
			var target := _trigger_target(field)
			if target.is_empty():
				print("[new-game] 第 %d 步停在未知触发条件：%s" % [steps_field, _field_state(field)])
				break
			var goal := _route_goal(field, target)
			if goal.x < 0:
				print("[new-game] 当前地图没有通往 %d 的传送点：%s" % [
					int(target.map), _field_state(field)])
				break
			if route_map != int(field.story.progress["mapId"]):
				route_map = int(field.story.progress["mapId"])
				route_blocked = {}
			var here := Vector2i(int(field.story.progress["player"]["x"]),
				int(field.story.progress["player"]["y"]))
			if here != goal:
				walk_steps += 1
				if walk_steps > WALK_PATH_STEP_LIMIT:
					print("[new-game] 走位超出 %d 格：%s" % [WALK_PATH_STEP_LIMIT,
						_field_state(field)])
					break
				var direction := _next_direction(field, here, goal, route_blocked)
				if direction == Vector2i.ZERO:
					print("[new-game] 走位无路可走：%s → %s（%s）" % [here, goal,
						_field_state(field)])
					break
				if not _walk_one(field, direction):
					# 地形标志之外的占位（实体）才记成绕行点；遇敌／位移这类瞬时拦截下一轮重试。
					if not field._step_blocker(direction).is_empty():
						route_blocked[here + direction] = true
			continue
		if steps_field % LOG_INTERVAL == 0:
			print("[new-game] 第 %d 步：%s" % [steps_field, _field_state(field)])
	print("[new-game] 剧情 %d 步（含 %d 场战斗）结束：%s" % [
		steps_field, battles, _field_state(field)])
	print("[new-game] trace 末尾：%s" % str(field.story.trace.slice(-8)))
	assert_true(field.boundary.is_empty(), "剧情没有落边界：%s" % field.boundary)
	assert_true(stages.get(Story.MasteryStage.MASTERY, false) and
		stages.get(Story.MasteryStage.STARTER, false),
		"属性选择（Game_Character_Select）与精灵选择（Game_Book_Monster）两级都走到：%s" % str(stages))
	assert_eq(field.story.progress["monsters"].size(), STARTER_PARTY_SIZE,
		"新手确认后队伍三只")
	var mastery := int(field.story.progress["parameter"].get("preferredMastery", -1))
	var candidates: Array[int] = field.story.starter_candidates(mastery)
	assert_true(mastery >= 0 and mastery < Story.MASTERY_SPECIES.size() and
		not candidates.is_empty() and
		int(field.story.progress["monsters"][0]["species"]) == candidates[0] and
		field.story.progress["partyOrder"] == [0, 1, 2],
		"队伍成员就是二级页确认的主精灵与两只同伴（流派 %d）" % mastery)
	var start := Vector2i(int(field.story.progress["player"]["x"]),
		int(field.story.progress["player"]["y"]))
	var terrain: Dictionary = field.story.map.terrain
	assert_true(start.x >= 0 and start.y >= 0 and
		start.x < int(terrain.width_tiles) and start.y < int(terrain.height_tiles),
		"回到野外时玩家坐标在地图 %d 范围内：%s" % [int(field.story.progress["mapId"]), start])
	# 事件在 break 的那一帧才结束：暂停位与在飞的位移要等后续帧才复位（真实运行每帧都在推进）。
	for _step in range(MOTION_FRAME_LIMIT):
		if field._motions.is_empty() and not field.story.paused:
			break
		field.advance(STEP_SECONDS)
	var walked := false
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if not field.move_player(direction):
			continue
		for _step in range(MOTION_FRAME_LIMIT):
			field.advance(STEP_SECONDS)
		walked = Vector2i(int(field.story.progress["player"]["x"]),
			int(field.story.progress["player"]["y"])) != start
		break
	print("[new-game] 野外走位：起点 %s → 终点 %s" % [start,
		Vector2i(int(field.story.progress["player"]["x"]),
			int(field.story.progress["player"]["y"]))])
	assert_true(walked, "回到野外后能走一格")
	main.queue_free()
	await get_tree().process_frame
	var folder := DirAccess.open(directory)
	if folder != null:
		for filename: String in folder.get_files():
			folder.remove(filename)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
