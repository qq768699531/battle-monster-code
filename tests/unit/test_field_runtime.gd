extends "res://tests/unit/gut_case.gd"

const Field = preload("res://field/field_runtime/field_runtime.gd")
const Story = preload("res://engine/data/story/story.gd")
const Book = preload("res://menu/book_model/book_model.gd")
const Store = preload("res://engine/data/save_store/save_store.gd")
const World = preload("res://engine/data/world_resources/world_resources.gd")
const NpcDefinition = preload("res://field/npc_definition/npc_definition.gd")
const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const MapEffectCatalog = preload("res://field/map/map_effect.gd")
const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const MasteryScript = preload("res://field/mastery_view/mastery_view.gd")
const Followers = preload("res://field/party_followers/party_followers.gd")
const StackScene = preload("res://engine/ui/message_stack/message_stack.tscn")
## `item_basic.dat` 第 6 组第 4 号（材料）在原生表里的 `ui_item` 帧号（记录第 133 字节，`gameplay.tres` 同值）。
const MATERIAL_ICON_FRAME := 111
## `qst/qstlist.fxt:0`「捕捉阿软」：野外任务接取提示只读它的标题列。
const QUEST_ID := 0
## `quests.tres` 的 npc 26 任务链头：任务 39（`guild_rank` 0、无前置、`goal_kind` 0 = 进度型），
## 用来驱动 `Qst_chtMENU` 的任务图标门。
const QUEST_GATE_NPC := 26
const QUEST_GATE_ID := 39
## 材料类道具 6004（`item_basic.dat` 第 6 组第 4 号）。
const MATERIAL_ITEM := 6004

class Provider extends RefCounted:
	var world: Dictionary
	var events: Dictionary
	var gameplay: GameplayData = Fixtures.data()

	func load_map(_id: int) -> Dictionary:
		return world

	func load_event(id: int) -> Dictionary:
		return events.get(id, {})

	## 生产侧契约（`world_resources.gd` 同名方法）：事件表里有没有这一号。
	## 缺它时 `story._has_event` 只能按「存在」处理，事件链末端会把「后继事件不存在」
	## 当成「资源缺失」记成边界（原生 `Evt_stdINIT` 那一步只是安静收尾）。
	func has_event(id: int) -> bool:
		return events.has(id)

	func load_gameplay() -> GameplayData:
		return gameplay

	func load_dialogue(_source: String) -> Dictionary:
		return {"groups": [{"records": [{"text": "第一句"}, {"text": "第二句"}]}]}


## 只给「离开战斗」这条出口用的替身：`_back_to_title()` 只读写 `combat`／`paused`，
## `_exit_tree()` 会调 `dispose()`（`story.gd` 自己保存进度用，替身不需要做任何事）；
## `consume_item` 只记下扣了什么，供「回标题前用过的道具」那条断言核对。
class StoryStub extends RefCounted:
	var combat: RefCounted = RefCounted.new()
	var paused := false
	var consumed: Dictionary = {}
	var progress: Dictionary = {}

	func consume_item(item_id: int, quantity: int) -> bool:
		consumed[item_id] = int(consumed.get(item_id, 0)) + quantity
		return true

	func dispose() -> void:
		pass

var directory := ""


func _cleanup() -> void:
	if directory.is_empty():
		return
	for filename in ["native-slot-0.cfg", "native-slot-1.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _record(opcode: int, params: Array = [0, 0, 0, 0, 0]) -> Dictionary:
	return {"opcode": opcode, "params": params}


static func _npc(id: int, interaction_code: int) -> NpcDefinition:
	var record: NpcDefinition = NpcDefinition.new()
	record.id = id
	record.field_sprite_id = 2
	record.interaction_code = interaction_code
	return record


func test_legacy_suite() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-runtime-check-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var store := Store.new(directory)
	var provider := Provider.new()
	# NPC 对白结束后的交互码分派读 `NpcDefinition.interaction_code`（`npc_bindings` 是它的投影），
	# 记录号必须从 0 连续：0 = 无服务（default）、1 = 未移植页、2 = 商店路由。
	provider.gameplay.npcs = [_npc(0, 0), _npc(1, 5), _npc(2, 3)]
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	provider.world.terrain.cell_flags[8][6] = 0
	provider.events = {
		0: {"records": [_record(0), _record(9, [0, 708, 1, 0, 0]),
			_record(20), _record(15, [2, 0, 0, 0, 0])]},
		1: {"records": [_record(1, [99, 0, 0, 0, 0]), _record(21)]},
	}
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	assert_true(field.start_slot(store, 0, provider, assets) and
		field._map_view.tile_count > 0 and not field._actors.snapshot().is_empty(),
		"a new-game slot starts the story and renders its map and hero")
	for _tick in range(600):
		if not field.story.stable_state().is_empty() and field.dialogue.is_empty():
			break
		if not field.dialogue.is_empty():
			field.confirm_dialogue()
		field.advance(0.08)
	var saved: bool = field.save_game() == OK
	field.free()
	var continued := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(continued)
	var resumed: bool = continued.start_slot(store, 0, provider, assets) and \
		continued.story.trace[0].contains("Game_Continue") and \
		continued.story.progress.player == {"x": 7, "y": 8} and continued.dialogue.is_empty()
	assert_true(saved and resumed,
		"a stable slot saves and continues at the stored player without replaying the script")
	# 触控面板样式为 0 时面板上的按钮／方向摇杆整体隐藏、走位也一并被挡（`_refresh()` 与
	# `_begin_walk()` 都以它为准），稳定在地图上时必须非 0。
	assert_true(continued._field_touch_style() != 0,
		"稳定在地图上时触控面板样式非 0（按钮与方向摇杆可见）")
	# MAP 键（原生 35 = Field_MiniMap）打开世界地图，BACK（Escape）播完关窗动画后释放。
	continued._press_field_key(Field.FieldKey.MAP)
	assert_true(continued.world_map_view != null, "MAP 键打开世界地图")
	continued.press(KEY_ESCAPE)
	assert_true(continued.world_map_view != null and continued.world_map_view.closing(),
		"BACK 先播关窗动画")
	await get_tree().create_timer(0.25).timeout
	assert_true(continued.world_map_view == null, "关窗动画结束后释放世界地图")
	# 新手剧情门槛：原生 `ParamData.current_event_resource_id <= 2` 时存档被拒
	# （`Field_Basic_mKeyPressed:62` 的 else 分支回 38、`Menu_Option_mKeyPressed:37-40` 回 198）。
	# 本项目的事件号推进与原生不等价，等价条件是「没有可写的稳定快照」（`story_unsettled()`）：
	# 事件脚本正在跑时不进存档页、不开飞艇登船页，各推原生那条提示；紧接其后的两条既有断言
	# （HELP 开存档页、触控键 48 开飞艇页）就是稳定态恢复的证据。
	var stack: Control = StackScene.instantiate()
	get_tree().root.add_child(stack)
	continued.set_messages(stack)
	continued.story.running = true
	continued._press_field_key(TouchCode.Key.HELP)
	var last_text: String = str(stack.call("slot_at", int(stack.call("count")) - 1).get("text", ""))
	var save_gated: bool = not continued.save_open and \
		last_text == assets.text_message(Msg.SOURCE, Msg.Id.FIELD_SAVE_UNAVAILABLE)
	# 原生 key 48 没有剧情门（`Field_Basic_mKeyPressed:88-103` 只按 game mode／分组），
	# 所以剧情跑动中飞艇页照开、也不推 37；37 只归分组 `& 0x14`。
	var group_before: int = int(continued.story.map.info.get("map_group", -1))
	var stack_before_warp := int(stack.call("count"))
	var warp_opened: bool = continued._open_warp_confirm() and continued.warp_confirm_view != null
	var warp_silent: bool = int(stack.call("count")) == stack_before_warp
	continued._close_warp_confirm()
	continued.story.map.info["map_group"] = 2
	var blocked_before := int(stack.call("count"))
	var blocked_group: bool = not continued._open_warp_confirm() and \
		int(stack.call("count")) == blocked_before + 1 and \
		str(stack.call("slot_at", blocked_before).get("text", "")) == \
			assets.text_message(Msg.SOURCE, Msg.Id.WARP_UNAVAILABLE)
	continued.story.map.info["map_group"] = group_before
	continued.story.running = false
	assert_true(save_gated and warp_opened and warp_silent and blocked_group and
		not continued.story_unsettled(),
		"剧情跑动中只拦存档页；飞艇页按原生分组打开，分组 & 0x14 仍回消息 37")
	# 存档页（原生 `Field_Basic_mKeyPressed` 的 HELP = -10 → FIELD_STATE_SAVE）：开窗后写当前槽，
	# 停在「已存档」，确认关窗后回到行走。
	continued._press_field_key(TouchCode.Key.HELP)
	assert_true(continued.save_open and continued._save_view.substate() == 1,
		"HELP 打开野外存档页")
	await get_tree().create_timer(0.3).timeout
	var save_texts: Dictionary = assets.text_messages(Msg.SOURCE)
	assert_true(continued._save_view.substate() == 3 and
		continued._save_view.get_node("Window").body_text() == save_texts[41],
		"开窗结束后写盘并换成「已存档」")
	continued.press(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	assert_true(not continued.save_open and continued._save_view.substate() == 0,
		"确认后关窗回到行走")
	# 图鉴入口：BOOK（42）读存档里的获得记录；`show_book(知识表)` 可以换成指定收录范围。
	continued._press_field_key(Field.FieldKey.BOOK)
	assert_true(continued.book_view != null and
		continued.book_view._knowledge[Book.BOOK_MONSTERS] ==
			Book.records(continued.story.progress)[Book.BOOK_MONSTERS],
		"BOOK 触控键打开图鉴并沿用存档的获得记录")
	continued._close_book()
	assert_true(continued.show_book(Book.all_records()) and
		continued.book_view._knowledge[Book.BOOK_MONSTERS].size() == Book.MONSTER_TOTAL,
		"show_book 注入指定知识表（调试全开），不改存档")
	# 宝箱（原生 `Field_Basic_mKeyPressed` 的 `Object_objHIT` case 176 → `Field_Box_*`）：
	# 面前那一格有 176 物件时 CONFIRM 换成 177 并把该地图记为已开。
	continued._close_book()
	continued.story.map.info.map_objects.append({"frame_id": 176, "tile_x": 7, "tile_y": 7})
	continued._actors.set_map_objects(continued.story.map.info, [],
		continued._map_object_state(int(continued.story.map.get("id", -1))))
	continued.story.progress.player = {"x": 7, "y": 8}
	continued._actor(0).lastDirection = 16
	assert_true(continued.interact_map_object() and
		continued.story.box_opened(int(continued.story.map.get("id", -1))) and
		not continued._actors.has_unopened_box(Vector2i(7, 7)),
		"CONFIRM opens the chest in front of the hero and records the map")
	assert_true(not continued.interact_map_object(),
		"an opened chest does not open a second time")
	# 物件帧 152（原生 `Field_Basic_mKeyPressed` 的 `Object_objHIT` case 152 → `Object_objANI(hero, 3)`）：
	# 确认键只让英雄原地播一次动作 3（结束方式 2 → 播完回待机），物件帧号不变、不入包也不存档。
	continued.story.map.info.map_objects = [
		{"frame_id": Field.MAP_OBJECT_INTERACT_FRAME, "tile_x": 7, "tile_y": 7}]
	continued._actors.set_map_objects(continued.story.map.info, [],
		continued._map_object_state(int(continued.story.map.get("id", -1))))
	var acted: bool = continued.interact_map_object()
	assert_true(acted and
		int(continued._actor(0).action) == FieldAction.Hero.OBJECT_152_INTERACT and
		continued._actors.object_action_at(Vector2i(7, 7)) == Field.MAP_OBJECT_INTERACT_FRAME,
		"物件帧 152：英雄原地播一次性动作 3，物件帧号不变")
	continued._on_actor_animation_finished(0)
	assert_eq(int(continued._actor(0).action), FieldAction.Hero.IDLE,
		"一次性动作播完回待机（结束方式 2）")
	# 物件帧 0／5／10（原生 `Field_Basic_mKeyPressed:26-49`）：这三帧的物件只有第 0 组地图被
	# `Map_objCREATE:88-100` 置成可命中，命中后英雄播一次性动作 4。
	continued.story.map.info.map_objects = [
		{"frame_id": Field.MAP_OBJECT_GROUP_0_FRAMES[0], "tile_x": 7, "tile_y": 7}]
	continued.story.map.info.map_group = Field.MAP_OBJECT_GROUP_0
	continued._actors.set_map_objects(continued.story.map.info, [],
		continued._map_object_state(int(continued.story.map.get("id", -1))))
	assert_true(continued.interact_map_object() and
		int(continued._actor(0).action) == FieldAction.Hero.GROUP_0_OBJECT_INTERACT,
		"第 0 组地图上帧 0 物件：英雄播一次性动作 4")
	continued._on_actor_animation_finished(0)
	continued.story.map.info.map_group = Field.MAP_OBJECT_GROUP_0 + 1
	assert_true(not continued.interact_map_object() and
		int(continued._actor(0).action) == FieldAction.Hero.IDLE,
		"非第 0 组地图上同一帧物件不响应")
	# NPC 对白关闭后的交互码分派（`Evt_chtDESTROY` → `Evt_chtMENU` → `FieldCanvas_SetNext`）：
	# 绑定记录 2 的 NPC 站在面前，逐档改交互码验证路由表。
	continued.story.progress.actors.append(continued.story._new_actor(2, 7, 7))
	continued.story.progress.player = {"x": 7, "y": 8}
	# 对白源由地图节点自己声明（`metadata/npc_dialogue`），运行时不再按 id 拼路径。
	continued.story.map.info.npcs = [{"tile_x": 7, "tile_y": 7, "resource_id": 2,
		"direction_code": 0, "npc_dialogue": "npc/npc0002.cht"}]
	var binding: Dictionary = continued._npc_binding(2)
	binding.interaction_code = 0
	var opened: bool = continued.interact_npc()
	var source: Variant = continued.dialogue.get("source")
	continued.cancel_dialogue()
	var recorded_bindings: Array = continued.story.map.info.npc_bindings
	continued.story.map.info.npc_bindings = []
	var unbound_failed: bool = not continued.interact_npc() and not continued.boundary.is_empty()
	continued.story.map.info.npc_bindings = recorded_bindings
	continued.boundary = ""
	continued.story.paused = false
	assert_true(opened and source == "npc/npc0002.cht" and continued.dialogue.is_empty() and
		not continued.service_open() and unbound_failed,
		"对白源取自地图节点的 npc_dialogue 元数据；交互码 0 关闭后仍在野外；缺绑定记录时显式报错")
	binding.interaction_code = 5
	continued.interact_npc()
	continued.cancel_dialogue()
	assert_true(continued.service_page == Field.ServicePage.INN and continued.inn_view != null and
		continued.boundary.is_empty(), "交互码 5 打开旅店页（状态 16）")
	continued._close_inn()
	continued.story.paused = false
	binding.interaction_code = 3
	continued.interact_npc()
	# 自然播完的分支（`confirm_dialogue` 走到底）与 CLR 退出共用同一处收尾。
	for _page in range(8):
		if continued.dialogue.is_empty():
			break
		continued.confirm_dialogue()
	assert_true(continued.dialogue.is_empty() and continued.boundary.is_empty() and
		continued.service_page == Field.ServicePage.SHOP and continued.shop_view != null,
		"交互码 3 打开商店页（买）")
	continued._close_shop()
	continued.boundary = ""
	continued.story.paused = false
	binding.interaction_code = 1
	continued.interact_npc()
	continued.cancel_dialogue()
	var guild_opened: bool = continued.service_page == Field.ServicePage.GUILD and \
		continued.guild_menu_view != null
	continued._close_guild()
	assert_true(guild_opened and continued.guild_menu_view == null and not continued.service_open() and
		not continued.story.paused, "交互码 1 打开公会菜单（状态 6），关窗后释放并解除冻结")
	# 子页 CLR 回列表：原生是 `SetNext(FIELD_STATE_GUILD_LIST)` 一次状态切换，中途没有「无服务页」的一帧。
	# 本工程若在重开菜单前没清服务页登记，页面会被全部释放而登记留着，野外从此无法交互（永久冻结）。
	assert_true(continued._open_guild_menu(0) and continued._open_guild_info(0), "公会菜单进「会长的建议」子页")
	continued._close_guild_info()
	assert_true(continued.guild_menu_view != null and continued.guild_info_view == null and
		continued.service_page == Field.ServicePage.GUILD,
		"资料页 CLR 回公会菜单：页面重建、服务页登记还在、野外不会永久冻结")
	continued._close_guild()
	# 服务页登记表自洽：`ServicePage` 的每一页都在表里，且每行都能解析出视图、按键与关页方法。
	var table_ok := Field.SERVICE_PAGES.size() == Field.ServicePage.size() - 1
	for page: int in Field.SERVICE_PAGES:
		var row: Dictionary = Field.SERVICE_PAGES[page]
		if str(row.key_map.get(KEY_ESCAPE, "")).is_empty() or not continued.has_method(str(row.close)):
			table_ok = false
		for member: String in row.views:
			if not (member in continued):
				table_ok = false
	assert_true(table_ok, "服务页登记表覆盖每一页，且每行都能解析出视图、按键与关页方法")
	# 触控键 48 → 原生 `Field_Basic_mKeyPressed` 的 key==48 分支 → `FIELD_STATE_WARP1`(4)：
	# 只有 `map_group ∈ {0,1,3,5}`（`& 0x2B`）才开页；m123 的分组是 5。
	continued._press_field_key(Field.FieldKey.NETWORK)
	assert_true(continued.warp_confirm_view != null and continued.service_open(),
		"触控键 48 打开飞艇登船确认页（状态 4）")
	await get_tree().create_timer(0.4).timeout
	continued.warp_confirm_view.handle_key("Enter")
	var boarded: bool = int(continued.story.progress.parameter.warp_saved_map_id) == \
			int(continued.story.map.id) and \
		int(continued.story.progress.parameter.warp_saved_tile_x) == 7 and \
		int(continued.story.progress.parameter.warp_saved_tile_y) == 8 and \
		int(continued._pending_warp.get("map_id", -1)) == Field.AIRSHIP_MAP_ID and \
		int(continued._actor(0).action) == FieldAction.Hero.WARP
	# 换图发生在英雄 ANI 10 播完之后（`Field_Hero_procNext` 的 ANI 10 分支 → `Map_warpProc`）。
	# 测试里没有 `_process` 驱动 `advance()`，所以手动收掉页面并直接触发动画完成。
	provider.world = resources.load_map(Field.AIRSHIP_MAP_ID)
	continued._close_warp_confirm()
	continued._on_actor_animation_finished(0)
	assert_true(boarded and int(continued.story.map.id) == Field.AIRSHIP_MAP_ID and
		int(continued._actor(0).action) == FieldAction.Hero.ARRIVE and continued.boundary.is_empty(),
		"登船记下上船位置，航程结束后换成飞艇内部地图 148 并播落地动作")
	# 交互码 4 → `FIELD_STATE_WARP2`(5)：门口这只 NPC 的分派走 `_open_warp_world()`。
	continued._open_warp_world()
	var world_open: bool = continued.warp_world_view != null and continued.service_open()
	continued._free_warp_world()
	assert_true(world_open and continued.warp_world_view == null and not continued.service_open(),
		"交互码 4 打开飞艇世界地图（状态 5），释放后守卫解除")
	# 禁用传送点：原生 `Map_warpProc:17` 通过、`:59-60` 走 `Game_msgInit(0, fxt404)`。
	# 404 落 index 0 消息条，不新增 `Game_infoInit` 的提示栈槽（两套是不同通道）。
	var flags: Variant = continued.story.map.terrain.cell_flags
	var blocked_dir := Vector2i.ZERO
	var blocked_tile := Vector2i.ZERO
	for candidate: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var tile: Vector2i = Vector2i(int(continued.story.progress.player.x),
			int(continued.story.progress.player.y)) + candidate
		if tile.x < 0 or tile.y < 0 or tile.y >= flags.size() or tile.x >= flags[tile.y].size():
			continue
		flags[tile.y][tile.x] = 0
		if continued._step_blocker(candidate).is_empty():
			blocked_dir = candidate
			blocked_tile = tile
			break
	continued.story.map.info["warps"] = [{"tile_x": blocked_tile.x, "tile_y": blocked_tile.y,
		"destination_map_id": 2, "destination_tile_x": 0, "destination_tile_y": 0}]
	continued.story.progress.warpEnabled["2"] = false
	var stack_before_bar := int(stack.call("count"))
	var warp_blocked: bool = blocked_dir != Vector2i.ZERO and not continued.move_player(blocked_dir)
	var bar: Control = continued._warp_blocked_bar
	assert_true(warp_blocked and int(stack.call("count")) == stack_before_bar and bar.visible and
		str(bar.get("map_name")) == assets.text_message(Msg.SOURCE, Msg.Id.MAP_BLOCKED),
		"禁用传送点的 404 只走 index 0 消息条，不推提示栈")
	# 交互码 2 → `GAME_STATE_MONSTER_LIST`(21) 精灵管理所：游标 0 进合成页（22）、
	# 游标 1 进强化页（23）；关窗都回精灵管理所并停在进入时那一行。
	continued._open_monster_menu()
	var office_open: bool = continued.monster_menu_view != null and continued.service_open()
	continued.monster_menu_view.handle_key("Enter")
	var mix_open: bool = office_open and continued.monster_mix_view != null and \
		continued.monster_menu_view == null and continued.service_open()
	# 正常路径由窗框 `animation_finished` 触发 `closed`，这里直接走同一个回调。
	continued._close_monster_mix()
	var mix_back: bool = continued.monster_menu_view != null and \
		int(continued.monster_menu_view.get("cursor")) == 0
	var mix_frozen: bool = continued.story.paused
	continued._close_monster_menu()
	# 关页落点是 `GAME_STATE_MONSTER_LIST`（`Game_Monster_List_mRun` 是空壳），不是野外，
	# 所以回管理所这一刻野外仍冻结；只有管理所自己 CLR 才回 `FIELD_STATE_BASIC`。
	assert_true(mix_open and mix_frozen and mix_back,
		"交互码 2 打开精灵管理所（状态 21），游标 0 的 −5 进合成页（状态 22），" +
		"关窗回精灵管理所（野外仍冻结）且游标停在合成那一行")
	continued.boundary = ""
	continued.story.paused = false
	continued._refresh()
	continued._open_monster_menu()
	# 按键走 `press()` → `SERVICE_PAGES` 的登记表（精灵管理所只认上下与确认／返回）。
	continued.press(KEY_DOWN)
	continued.press(KEY_ENTER)
	var enchant_open: bool = continued.monster_enchant_view != null and \
		continued.monster_menu_view == null and continued.service_open()
	# 正常路径由窗框 `animation_finished` 触发 `closed`，这里直接走同一个回调。
	continued._close_monster_enchant()
	var office_back: bool = continued.monster_menu_view != null and \
		int(continued.monster_menu_view.get("cursor")) == 1
	var enchant_frozen: bool = continued.story.paused
	continued._close_monster_menu()
	assert_true(enchant_open and office_back and enchant_frozen,
		"游标 1 的 −5 进强化页（状态 23），关窗回精灵管理所（野外仍冻结）且游标停在强化那一行")
	# 关页只走 `_restore_field_pause()`：边界文本未清时野外照样冻结，也不会重建精灵管理所。
	continued._open_monster_menu()
	continued.monster_menu_view.handle_key("Enter")
	continued.boundary = "未接通分支"
	continued._close_monster_mix()
	assert_true(continued.monster_menu_view == null and continued.story.paused,
		"边界文本未清时关合成页：不重建精灵管理所，野外保持冻结")
	continued.boundary = ""
	continued.story.paused = false
	continued._refresh()
	# 任务图标码 5（`Qst_icoGET:15-17`）：事件停在首记录、且这一步是「等与该交互号对象对话」
	# （`step_kind == 4`、参数 == 交互号）时，只有被等的那一个 NPC 拿 5；`step_index > 0`（正在执行记录）
	# 时整段抑制，连任务表的 2／3／4 都不画。
	provider.events[2] = {"records": [_record(Story.Trigger.INTERACT_LATCH, [1, 0, 0, 0, 0])]}
	continued.story.progress["eventId"] = 2
	continued.story.progress["cursor"] = Story.STEP_INDEX_TRIGGER
	continued.story._step_index_idle = false
	var step: Dictionary = continued.story.event_step()
	var awaited: int = continued._quest_icon_code(1, step)
	var unrelated: int = continued._quest_icon_code(2, step)
	continued.story.progress["cursor"] = 1
	var suppressed: int = continued._quest_icon_code(1, continued.story.event_step())
	assert_true(awaited == QuestMark.Code.EVENT and unrelated != QuestMark.Code.EVENT and
		suppressed == QuestMark.Code.NONE,
		"事件停在「等与该对象对话」的首记录时只有被等的 NPC 拿码 5，事件执行记录期间整段抑制")
	# 原生 `Object_procRUN:13`：事件执行中（`EvtData.step_index > 0`）且暂停位（`EvtData+12`）为 1 时
	# 整轮对象池推进被跳过，帧位移（`Object_procCURR` → `Object_procMOVE`）与逐帧动画一起冻结，
	# 恢复后从同一帧／同一格继续（bm-P2-75）。
	continued.story._step_index_idle = true
	continued.story.progress["cursor"] = Story.STEP_INDEX_TRIGGER
	var walk_direction := Vector2i.ZERO
	for candidate: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if continued.move_player(candidate):
			walk_direction = candidate
			break
	var frozen_at := Vector2(continued._actor(0).x, continued._actor(0).y)
	# 事件停在一行上（`cursor = 1`）＋暂停位 1 就是原生的冻结条件；`paused` 让事件本身也停住，
	# 免得恢复位移时顺手执行下一条记录。暂停位只经 `story.gd` 的唯一写点（opcode 22）设置。
	continued.story.progress["cursor"] = 1
	continued.story._set_pause_objects(Story.PAUSE_OBJECTS_ON)
	continued.story.paused = true
	continued.advance(0.05)
	continued.advance(0.05)
	var paused_at := Vector2(continued._actor(0).x, continued._actor(0).y)
	continued.story._set_pause_objects(0)
	for _tick in range(40):
		if continued._motions.is_empty():
			break
		continued.advance(0.05)
	var resumed_at := Vector2(continued._actor(0).x, continued._actor(0).y)
	assert_true(walk_direction != Vector2i.ZERO and paused_at == frozen_at and
		continued._motions.is_empty() and resumed_at != frozen_at,
		"暂停对象期间英雄的逐格位移不推进，解除后从同一格继续走完")
	continued.free()
	var file := FileAccess.open(store.slot_path(0), FileAccess.WRITE)
	file.store_string('[save]\nformat="bad"\n')
	file.close()
	var corrupt := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(corrupt)
	assert_true(not corrupt.start_slot(store, 0, provider, assets) and corrupt.story == null,
		"a corrupt occupied slot never silently becomes a new game")
	corrupt.free()
	_cleanup()


## 战斗内系统菜单的「是」＝原生 `Game_out()`（`EFC_mainSetNEXT(CANVAS_PRIME, PRIME_STATE_TITLE)`）：
## 收到 `battle_view.title_requested` 时回标题，不回野外地图（回地图那条会发 `music_requested`）。
func test_battle_exit_to_title() -> void:
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	var stub := StoryStub.new()
	field.story = stub
	field._battle_id = 7
	field._encounter = {"key": 0}
	var titles: Array = []
	var music: Array = []
	field.title_requested.connect(func(): titles.append(true))
	field.music_requested.connect(func(resource_id: int): music.append(resource_id))
	# 这条出口也要把战斗内用掉的道具一并落实（原生是在战斗内 `Item_stdDel` 使用时直接写回）。
	field._battle_title_requested({1000: 2, 7023: 1})
	assert_true(titles.size() == 1 and music.is_empty() and field._battle_id == -1 and
		stub.combat == null and stub.paused and field._encounter.is_empty() and
		int(stub.consumed.get(1000, 0)) == 2 and int(stub.consumed.get(7023, 0)) == 1,
		"系统菜单的「是」请求回标题，不回野外地图，并扣掉本战用掉的道具")
	field.free()


## 全屏地图特效层（原生 `Map_eft*`）：静态档位立刻铺满，分级档位走 Scene 的爬坡片段。
func test_map_effect_layer() -> void:
	var layer: Node2D = load("res://field/map/map_effect.tscn").instantiate()
	get_tree().root.add_child(layer)
	var blend := layer.get_node("Blend") as ColorRect
	var timeline := layer.get_node("AnimationPlayer") as AnimationPlayer
	var shader_material := blend.material as ShaderMaterial
	layer.present({"tier": MapEffectCatalog.Kind.BLACK, "id": 1})
	var filled: bool = blend.visible and \
		int(shader_material.get_shader_parameter("mode")) == MapEffectCatalog.Blend.NORMAL
	layer.present({"tier": MapEffectCatalog.Kind.GRADE_WHITE, "id": 2})
	assert_true(filled and blend.visible and timeline.assigned_animation == "grade_white" and
		timeline.is_playing(), "整屏黑档位立刻铺满，分级档位改播 Scene 里的爬坡片段（脚本不自己计时）")
	layer.free()


## 事件镜头的逐帧推进（`Map_posFOCUS`，见 `wiki\event\event-camera.md`）：
## 模式 2／3 是 `Map_posMOVE` 的每帧 7／4 px，模式 4 是 `Map_posCENTER` 的
## 保留 3/4 距离。一帧按 `CAMERA_FRAME_SECONDS` 算，所以每帧位移是常数。
func test_camera_pan_step() -> void:
	var start := Vector2(0, 0)
	var target := Vector2(400, 0)
	assert_eq(Field.camera_step(start, target, Story.CameraMode.PAN_FAST, Field.CAMERA_FRAME_SECONDS),
		Vector2(Field.CAMERA_PAN_FAST_STEP, 0), "模式 2 每帧前进 7px")
	assert_eq(Field.camera_step(start, target, Story.CameraMode.PAN_SLOW, Field.CAMERA_FRAME_SECONDS),
		Vector2(Field.CAMERA_PAN_SLOW_STEP, 0), "模式 3 每帧前进 4px")
	assert_eq(Field.camera_step(start, target, Story.CameraMode.HALF_CONVERGE,
		Field.CAMERA_FRAME_SECONDS).x, 100.0, "模式 4 每帧保留 3/4 距离")


## 换图保留镜头中心（bm-75）：原生换图链路 `Map_warpProc:21-22` → `GameCanvas_mapLOAD:10-14`
## 只重载 mif／mdt 与对象，从不写 `MapData.camera_origin`；清零只在 `Map_Init`，调用者只有
## `GameCanvas_load:10`（开局）与 `Map_Initialize:7`（引擎初始化）。所以事件镜头模式 2／3
## 的起点是换图前的视口中心，首帧仍由 `Map_posMOVE` 按 7 px 平移。
func test_map_switch_keeps_camera_origin() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-map-camera-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var store := Store.new(directory)
	var provider := Provider.new()
	provider.gameplay = assets.load_gameplay_catalog()
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	provider.events = {0: {"records": [_record(Story.Trigger.ALWAYS)]}}
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	assert_true(field.start_slot(store, 0, provider, assets), "空脚本的存档能开档：%s" % field.boundary)
	var origin := Vector2(64, 48)
	field._camera_center = origin
	field._camera_initialized = true
	field.story._emit("map", {"mapId": int(field.story.map.id), "map": field.story.map})
	field._drain_effects()
	assert_true(field._camera_initialized and field._camera_center == origin,
		"换图不清镜头中心（`Map_load` 系列不写 `camera_origin`）")
	field.story.progress["camera"] = {"x": 10, "y": 8}
	field._camera_pan = {"id": 1, "mode": Story.CameraMode.PAN_FAST}
	field._position_camera(Field.CAMERA_FRAME_SECONDS)
	assert_almost_eq(field._camera_center.distance_to(origin), Field.CAMERA_PAN_FAST_STEP, 0.01,
		"换图后的模式 2 从旧中心起算，首帧只前进 7px")
	field.free()
	_cleanup()


## 出战怪物跟随的冻结判据（`Field_procCurr:143`、`Field_procNext:10`，见 bm-P2-86）：
## 事件执行记录期间（原生 `EvtData.step_index > 0`，本工程 `progress["cursor"] > 0`）跟随者
## 留在原位、不沿轨迹走；事件链结束后也不因为「离主角太远」整队聚拢，位置保持连续。
func test_follower_freeze_during_event_motion() -> void:
	var progress := {"cursor": 1, "partyOrder": [0, 1, 2],
		"monsters": [{"species": 49}, {"species": 62}, {"species": 86}]}
	var hero := {"id": 0, "x": 8.0, "y": 8.0, "direction": 32, "lastDirection": 32, "action": 0}
	var state := {}
	var at_feet := _follower_positions(Followers.sync(state, progress, hero))
	assert_eq(at_feet.size(), 3, "队伍三只出战怪物各建一个跟随者")
	# `Evt_stdPROC` case 9 的脚本走位（`Object_objARRIVE`）：主角走 6 格，跟随者不跟。
	var from := Vector2(hero.x, hero.y)
	for _step in 6:
		var to := from + Vector2(0, 1)
		Followers.advance(state, from, to, false, false)
		from = to
	hero["x"] = from.x
	hero["y"] = from.y
	assert_eq(_follower_positions(Followers.sync(state, progress, hero)), at_feet,
		"剧情位移 6 格后跟随者仍停在原格（`Field_procCurr:143` 直接返回）")
	progress["cursor"] = 0
	assert_eq(_follower_positions(Followers.sync(state, progress, hero)), at_feet,
		"事件链结束后不聚拢到主角脚下：聚拢只在换图／建对象时发生")


static func _follower_positions(actors: Array) -> Array:
	var positions := []
	for actor: Dictionary in actors:
		positions.append(Vector2(actor.x, actor.y))
	return positions


## 跟随精灵的消失时机（bm-P2-103）：原生在事件里照常绘制跟随对象（`Field_Basic_mPaint:11` 的
## `Object_procDRAW` 只按 `active_state > 0` 收集，`Field_procCurr:144` 只跳过演算），换掉它们的是
## 黑屏之后的 `Op.LOAD_MAP`／`Op.CLEAR_ACTORS`。所以淡黑期间照常画，第一次整屏黑之后到事件结束
## 都不画，步号回 0 再按原规则恢复。
func test_follower_hidden_after_event_screen_black() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-followers-check-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var provider := Provider.new()
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	# 首记录是永不满足的物品计数触发，所以手动改写步号不会被 pump 立刻推回 >0；
	# 第二条是淡到黑（`Op.FADE` 模式 1），第三条长等待把事件留在运行中。
	provider.events = {0: {"records": [
		_record(Story.Trigger.ITEM_COUNT, [MATERIAL_ITEM, 9999, 0, 0, 0]),
		_record(Story.Op.FADE, [1, 0, 0, 0, 0]),
		_record(Story.Op.WAIT, [60, 0, 0, 0, 0])]}}
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	assert_true(field.start_slot(Store.new(directory), 0, provider, assets), "field starts")
	field.story.progress.monsters = [{"species": 49}, {"species": 62}]
	field.story.progress.partyOrder = [0, 1]
	field._sync_actors()
	var idle := _actor_ids(field)
	field.story.progress.cursor = 1
	field.advance(0.01)
	var fading := _actor_ids(field)
	# 淡黑分 9 拍（原生一帧 `FramePacing.NATIVE_FRAME_SECONDS` 一拍），最后一拍才到不透明。
	for _tick in 10:
		field.advance(FramePacing.NATIVE_FRAME_SECONDS)
	var black := _actor_ids(field)
	field.story.progress.cursor = 0
	field.advance(0.08)
	assert_true(idle.size() > 2 and fading == idle,
		"淡黑期间跟随精灵照常画（`Object_procDRAW` 不看事件步号）")
	assert_true(black.size() == idle.size() - 2,
		"第一次黑屏之后不再画跟随精灵（原生这时才重建／清场跟随对象）")
	assert_eq(_actor_ids(field), idle, "步号回到 0 后跟随精灵按原规则恢复")
	field.free()
	_cleanup()


static func _actor_ids(field: Object) -> Array:
	var ids := []
	for entry: Dictionary in field._actors.snapshot():
		ids.append(int(entry.actor))
	return ids


## 战斗 ANI 场景要先在等待帧里读进缓存：`battle_view._load_action` 对没读过的物种按
## 「物种 × 动作」各 `instantiate()` 一次，而 PackedScene 的首次实例化会深拷贝整份动画库
## （实测 6 只的首次开战 0.90 s，预读后 0.14 s，与同进程第二场持平）。
func test_battle_animation_warmup() -> void:
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	field._queue_battle_animations([{"species": 93}, {"species": 93}, {}, {"species": 49}])
	assert_eq(field._battle_warmup.size(), 2, "同一物种只排一次，空球跳过")
	field._advance_battle_warmup()
	assert_eq(field._battle_warmup[0], MonsterAnimation.battle_identity(49),
		"每帧只读队首一个，其余留到下一帧")
	# 脚本战／公会战没有遇敌转场：开战前 `_flush_battle_warmup()` 必须把余下的读完。
	field._flush_battle_warmup()
	assert_eq(field._battle_warmup.size(), 0, "开战前一次读空队列")
	field.free()


## 初始选择（opcode 32）：鼠标／触屏点非光标格只移光标，点光标格只开 Box2 确认框
## （原生 `Menu_CharacterSelect_Draw:156/168/203` 给每格登记 −4／−3、光标格 −5），
## 确认后才入队三只（bm-P1-20）。
func test_mastery_touch() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-mastery-check-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var store := Store.new(directory)
	var provider := Provider.new()
	provider.gameplay = assets.load_gameplay_catalog()
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	provider.events = {0: {"records": [_record(Story.Trigger.ALWAYS), _record(Story.Op.MASTERY_SELECT)]}}
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	assert_true(field.start_slot(store, 0, provider, assets) and not field.mastery.is_empty(),
		"opcode 32 打开初始选择的事件门")
	var view: Control = field._mastery_view
	var row: Control = view.get_node("Content/MasteryPage/Row2")
	field.handle_touch(row.get_global_rect().get_center(), "down")
	field.handle_touch(row.get_global_rect().get_center(), "up")
	assert_eq(view.selected(), 2, "点非光标格只把光标移过去（原生 −4 的 press_count）")
	field.handle_touch(row.get_global_rect().get_center(), "down")
	field.handle_touch(row.get_global_rect().get_center(), "up")
	assert_true(not field.mastery.is_empty() and view.selected() == 2 and
		view._confirm == MasteryScript.ConfirmState.OPEN,
		"点光标格等于按 OK：只开确认框，不提交")
	field.submit_mastery()
	# 一级确认后是 `GameCanvas_SetNext(GAME_STATE_BOOK_MONSTER_16, 流派)`：换成图鉴页的初始精灵形态。
	var starter: Control = field._starter_view
	for _frame in range(200):
		if not starter.is_transitioning():
			break
		await get_tree().process_frame
	assert_true(starter.visible and field._mastery_stage == Story.MasteryStage.STARTER,
		"一级确认后换成图鉴页（`Game_Book_Monster_init`）")
	# 光标从第 1 格开始（`Game_Book_Monster_Load` 清 transition+0），第 4…8 格才是候选。
	starter.handle_key("Enter")
	assert_false(starter.get_node("Confirm").visible,
		"第 1 格不可选：OK 不开确认框（`Param_bookIsMonster` = 0）")
	for _step in range(Story.STARTER_FIRST_SLOT):
		starter.handle_key("ArrowRight")
	starter.handle_key("Enter")
	assert_true(starter.get_node("Confirm").visible,
		"第 5 格是第一只候选：OK 打开 fxt 101 确认框")
	field.submit_mastery()
	assert_true(field.story.progress["monsters"].size() == 3 and
		field.story.progress["partyOrder"] == [0, 1, 2] and field.mastery.is_empty(),
		"两级确认后入队三只并关掉事件门")
	field.free()
	_cleanup()


## 原生 `Game_infoInit` 的两类图标提示：任务接取（`Qst_chtKeyPress@0x943A0:87` 传 `0x94`）
## 与道具入手（`Item_stdAddEx@0x85BE4:76` 传道具记录第 133 字节＝`ui_item` 帧号）。
func test_message_icons() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-message-check-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var store := Store.new(directory)
	var provider := Provider.new()
	provider.gameplay = assets.load_gameplay_catalog()
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	provider.events = {0: {"records": [_record(Story.Trigger.ALWAYS)]}}
	var stack: Control = StackScene.instantiate()
	get_tree().root.add_child(stack)
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	var started: bool = field.start_slot(store, 0, provider, assets)
	assert_true(started, "空脚本的存档能开档：%s" % field.boundary)
	field.set_messages(stack)
	# 任务接取：`Qst_chtKeyPress@0x943A0:87` → `Qst_stdSET` 的
	# `Game_infoInit(0x94, "#C5"+任务标题+"(接受)")`。
	var quest_title: String = assets.text_message("qst/qstlist.fxt", QUEST_ID) \
		.split("\t")[0].strip_edges()
	var suffix: String = assets.text_message(Msg.SOURCE, Msg.Id.QUEST_ACCEPT_SUFFIX)
	field._quest_accepted(QUEST_ID, 0)
	var accepted: Dictionary = stack.call("slot_at", int(stack.call("count")) - 1)
	assert_eq([accepted.get("icon", -1), accepted.get("text", "")],
		[Field.QUEST_ICON_FRAME, "%s%s%s" % [Field.MESSAGE_HIGHLIGHT_CODE, quest_title, suffix]],
		"任务接取提示带任务图标帧（`Qst_stdSET@0x93B34:41-43`）")
	# 伪道具（`Item_stdAddEx@0x85BE4:47-59`）：组 26 金币、组 25 经验值各推一条无图标提示，
	# 文案是 `Item_datBasic` 的 fxt413／414 套 fxt415。走非阻塞的掉落入口，不推进事件链。
	for pseudo_case: Array in [[ItemKind.Pseudo.MONEY, Msg.Id.MONEY_LABEL, 2000],
			[ItemKind.Pseudo.EXPERIENCE, Msg.Id.EXPERIENCE_LABEL, 200]]:
		var pseudo_id: int = ItemKind.id_of(int(pseudo_case[0]), 0)
		assert_true(field.story._add_battle_drop(pseudo_id, int(pseudo_case[2])), "伪道具入账成功")
		field._drain_effects()
		var pseudo: Dictionary = stack.call("slot_at", int(stack.call("count")) - 1)
		var pseudo_text: String = assets.text_message(Msg.SOURCE,
			Msg.Id.PSEUDO_ITEM_OBTAINED) % [assets.text_message(Msg.SOURCE,
			int(pseudo_case[1])), int(pseudo_case[2])]
		assert_eq([int(pseudo.get("icon", 0)), str(pseudo.get("text", ""))], [-1, pseudo_text],
			"组 %d 推「获得… 数量」提示且不带图标" % int(pseudo_case[0]))
	# 道具入手：`Item_stdAddEx` 的 `Game_infoInit(kind_specific_85_bits, fxt416)`。
	var record: ItemDefinition = provider.gameplay.item(MATERIAL_ITEM)
	assert_true(field.story._add_inventory_item(MATERIAL_ITEM, 2), "材料入袋成功")
	field._drain_effects()
	var obtained: Dictionary = stack.call("slot_at", int(stack.call("count")) - 1)
	var item_name: String = assets.text_message("common/item_basic.dat", record.name_record)
	var expected: String = assets.text_message(Msg.SOURCE, Msg.Id.ITEM_OBTAINED) % \
		[Field.ITEM_GRADE_COLOR_CODES[int(record.grade_index)], item_name, 2]
	assert_true(int(obtained.get("icon", -1)) == MATERIAL_ICON_FRAME and
		str(obtained.get("text", "")) == expected,
		"道具入手提示带 ui_item 帧号与「获得… X 数量」正文（`Item_stdAddEx@0x85BE4:76`）")
	field.free()
	_cleanup()


## 野外任务页（`ServicePage.QUEST`）与任务图标门：原生 `Evt_chtMENU` 的六条交互码分支里没有
## 一条切 `FIELD_STATE_QUEST_DETAIL`(10)／`FIELD_STATE_QUEST_COMPLETE`(11)，`field_state` 表里
## 也没有「任务列表」这一档——两页只由 `Qst_chtMENU` 切进。进门后的两条路：
## 状态 4（`Qst_icoGET` 目标达成）→ 完成页；状态 2（可接）且交互码不是 1 → 详情页。
func test_quest_gate() -> void:
	await get_tree().process_frame
	directory = "res://tests/.field-quest-gate-%d" % OS.get_process_id()
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory))
	var assets: Node = get_tree().root.get_node("AssetCatalog")
	var resources := World.new()
	resources.initialize(assets)
	var store := Store.new(directory)
	var provider := Provider.new()
	provider.gameplay = assets.load_gameplay_catalog()
	provider.world = resources.load_map(123)
	provider.world.id = 0
	provider.world.info.npcs = []
	provider.world.info.monster_spawns = []
	provider.events = {0: {"records": [_record(Story.Trigger.ALWAYS)]}}
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	assert_true(field.start_slot(store, 0, provider, assets), "空脚本的存档能开档：%s" % field.boundary)
	# 任务页没有交互码路由：`SERVICE_ROUTES` 的每一行都不指向它。
	var routed: Array[int] = []
	for code: int in Field.SERVICE_ROUTES:
		if Field.SERVICE_ROUTES[code].page == Field.ServicePage.QUEST:
			routed.append(code)
	assert_true(routed.is_empty(), "任务页没有交互码路由（`Evt_chtMENU` 六条分支都不切它）")
	# 状态 2：交互码 1 不切页（`Qst_chtMENU` 的 `a2 == 1` 分支），其余交互码进详情页。
	var guild_gate: bool = field._quest_gate(Field.InteractionCode.GUILD, QUEST_GATE_NPC)
	var opened_detail: bool = field._quest_gate(Field.InteractionCode.NONE, QUEST_GATE_NPC)
	assert_true(not guild_gate and opened_detail and
		field.service_page == Field.ServicePage.QUEST and field.quest_view != null,
		"状态 2（可接）且交互码不是 1 → 任务详情页（`FIELD_STATE_QUEST_DETAIL`）")
	field._close_quest()
	# 状态 4：接取后把进度推满（`Qst_stdCHECK` 的 goal_kind 0 那一支），交互码 0 进完成页。
	var log: QuestLog = field.story.quest_log()
	var table: QuestTable = field._quest_table_resource()
	var accepted: bool = log.accept(table, QUEST_GATE_ID)
	var advanced: Array[Dictionary] = []
	if accepted:
		var slot: Dictionary = log.slot_at(log.slot_of(QUEST_GATE_ID))
		advanced = log.advance(int(slot["goal_kind"]), int(slot["goal_target"]), int(slot["goal_count"]))
	var opened_complete: bool = field._quest_gate(Field.InteractionCode.NONE, QUEST_GATE_NPC)
	assert_true(accepted and advanced.size() == 1 and opened_complete and
		field.service_page == Field.ServicePage.QUEST and field.quest_view != null,
		"状态 4（目标达成）→ 任务完成页（`FIELD_STATE_QUEST_COMPLETE`）")
	field._close_quest()
	field.free()
	_cleanup()


## `GameCanvas_mPaint:29-40` 与 `Field_Basic_hero_DrawUI:64-73`：经验加成窗口按本帧耗时递减、
## 到点清零；HUD 用 `(剩余 + 59999) / 60000` 显示剩余分钟。
func test_exp_bonus_countdown_and_hud() -> void:
	var field := load("res://field/field_runtime/field_runtime.tscn").instantiate() as Field
	get_tree().root.add_child(field)
	var stub := StoryStub.new()
	stub.progress = {"parameter": {Story.EXP_BONUS_KEY: Story.EXP_BONUS_MILLISECONDS}}
	field.story = stub
	field._advance_exp_bonus(60.0)
	field._sync_exp_bonus_hud(1)
	assert_eq([int(stub.progress["parameter"][Story.EXP_BONUS_KEY]),
		field._exp_bonus_shown_minutes, field._exp_bonus_hud.visible],
		[Story.EXP_BONUS_MILLISECONDS - 60000, 59, true],
		"窗口按 elapsed 递减，HUD 显示取整到分钟的剩余时间")
	stub.progress["parameter"][Story.EXP_BONUS_KEY] = 30000
	field._advance_exp_bonus(60.0)
	field._sync_exp_bonus_hud(1)
	assert_eq([int(stub.progress["parameter"][Story.EXP_BONUS_KEY]),
		field._exp_bonus_hud.visible], [0, false],
		"本帧耗时不小于剩余值时清零，HUD 同时隐藏")
	field.free()
