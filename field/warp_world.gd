extends "res://ui/window_transition.gd"
## 飞艇世界地图移动页（原生 `FIELD_STATE_WARP2`，状态 5）。
##
## 窗口就是 `components/window_transition.tscn`（`window_size` 228×208、`side_width` 12、
## `header_height` 12，矩形 (86,16)，与 `Field_Warp2_Draw` 的
## `Menu_win_Box4_DrawWindow(228, 208, …, 12, 12)` 一致）；标题图是同一处的
## `Menu_battleDrawIcon10(rect.x+15, rect.y+7)`（`ui_battle` 第 10 帧，62×5）。
##
## 开合相位按 `Field_Warp2_Draw` 的两段掩码分：`0xC4`（相位 −1／3／4）画标题图、
## 正文与 5 个候选节点，`0x33`（−3／−2／1／2）**只画标题图**。标题位置取
## `Menu_win_Box4_DrawWindow` 的第一个出参（本相位矩形），正文取第二个出参（稳态矩形），
## 所以标题挂在 `Bounds/TitleIcon`（跟开合矩形走、全程可见），正文 `Content` 留在稳态坐标、
## 由动画轨道从相位 3 起才显示（`content_follows_window` 保持关）。详见 `wiki\world-map\warp-world-phases.md`。
##
## 5 个候选来自 `.rodata 0x98a9c` 的静态表 `[地图号, tile_x, tile_y, 图标中心x, 图标中心y]`：
## 下标 3 的三项被 `ParamData.warp_saved_map_id / warp_saved_tile_x / warp_saved_tile_y`
## （上船时由 `Field_Warp1_mKeyPressed` 记下）覆盖。图标中心、连线与 50×50 触控区
## 都写在 Scene 的 `Content/Map` 里，这里只按数据换贴图／灰度／名称。
##
## 本页**不换图**：确认后只把目的地交给宿主（`move_requested`），换图发生在英雄 ANI 10
## 播完之后（`Field_Hero_procNext` 的 `Map_warpProc`）。

## 确认「是」：目的地地图号与落地格（原生 `MapData.warp_target_map_id / _tile_x / _tile_y`）。
signal move_requested(map_id: int, tile_x: int, tile_y: int)
## BACK 请求关窗；宿主据此调 `close()`（同 `world_map.gd` 的分工）。
signal close_requested
## 关窗动画播完。
signal closed

const MessageStack = preload("res://ui/message_stack.gd")
## Box2 确认框的几何／折行只有 `warp_confirm.gd` 一处实现（WARP1／WARP2 的 `Content` 同构）。
const WarpConfirmBox = preload("res://field/warp_confirm.gd")

## 世界地图图标帧号（`Map_worldGET` 返回的 `obj/ui_world` 帧号）。
const ICON_FORMAT := "obj/ui_world/frame-%03d"

## 5 个候选槽：`Field_Warp2_Draw` 的候选数组下标，几何见 Scene 的 `Content/Map/Slots`。
enum Slot { TOP, LEFT, RIGHT, CURRENT, BOTTOM }

## 地图游标的一步（`Field_Warp2_mKeyPressed` 的 −4 右／−3 左／−2 下／−1 上）。
enum Step { UP, DOWN, LEFT, RIGHT }

## `FieldData+0x08`：0 = 地图游标，1 = 确认框。
enum Page { MAP, CONFIRM }

## `Menu_win_Box2_DrawSelect` 的 cursor（0 = 左「是」、1 = 右「否」）只有 `warp_confirm.gd`
## 的 `Answer` 一份：确认框是它的实例，本页写的就是框自己的光标值。

## 一条候选目的地（原生静态表的前三项）。
class Destination:
	var map_id: int
	var tile_x: int
	var tile_y: int

	func _init(p_map_id: int, p_tile_x: int, p_tile_y: int) -> void:
		map_id = p_map_id
		tile_x = p_tile_x
		tile_y = p_tile_y


## 游标表（`Field_Warp2_mKeyPressed`）：`[方向][当前选中项]` = 新选中项。
const SELECTION_AFTER_STEP := {
	Step.UP: [Slot.TOP, Slot.TOP, Slot.TOP, Slot.TOP, Slot.CURRENT],
	Step.DOWN: [Slot.CURRENT, Slot.BOTTOM, Slot.BOTTOM, Slot.BOTTOM, Slot.BOTTOM],
	Step.LEFT: [Slot.LEFT, Slot.LEFT, Slot.CURRENT, Slot.LEFT, Slot.LEFT],
	Step.RIGHT: [Slot.RIGHT, Slot.CURRENT, Slot.RIGHT, Slot.RIGHT, Slot.RIGHT],
}
## 非选中节点注册的方向键（`Field_Warp2_Draw` 的 case 0／1／2／4）。
const NODE_STEPS := {
	Slot.TOP: Step.UP,
	Slot.LEFT: Step.LEFT,
	Slot.RIGHT: Step.RIGHT,
	Slot.BOTTOM: Step.DOWN,
}
## 下标 3 注册的键由当前选中项决定（同函数 case 3）：1→右、0→下、2→左、4→上。
const STEP_TO_CURRENT := {
	Slot.TOP: Step.DOWN,
	Slot.LEFT: Step.RIGHT,
	Slot.RIGHT: Step.LEFT,
	Slot.BOTTOM: Step.UP,
}

## 5 个候选目的地（下标同 `Slot`）；下标 3 用 `open()` 传入的上船位置。
var candidates: Array[Destination] = []
## 原生 `FieldData.transition_parameter_bits`（`Field_Warp2_init` 置 3）。
var selected := Slot.CURRENT
var page := Page.MAP

var _catalog: Object
var _data: Variant
var _enabled: Dictionary = {}
var _passed: Dictionary = {}
## 灰阶材质由 Scene 声明在 `Disabled` 叠加帧上，图标复用同一份。
var _gray_material: Material
var _closing := false


func _ready() -> void:
	super()
	hide()
	_gray_material = _slot(Slot.TOP).get_node("Disabled").material
	for index in range($Content/Map/Slots.get_child_count()):
		_slot(index).get_node("Touch").pressed.connect(_press_candidate.bind(index))
	transition_finished.connect(_on_transition_finished)
	# 确认框是 `warp_confirm.tscn` 的实例：正文、光标与两只键都由它自己画，
	# 本页只接它的「是／否／收完」三个信号（`Field_Warp2_mPaint:11-19` 与 WARP1 同一个
	# `Menu_win_Box2_DrawSelect`）。
	$Confirm.managed = true
	$Confirm.transition_finished.connect(_on_confirm_finished)
	$Confirm.board_requested.connect(_decide)
	$Confirm.close_requested.connect(_cancel_confirm)


## `saved_map_id / saved_tile_*` 是 `ParamData.warp_saved_*`（上船位置，即候选下标 3）。
func open(catalog: Object, data: Variant, saved_map_id: int, saved_tile_x: int,
		saved_tile_y: int, enabled: Dictionary, passed: Dictionary) -> bool:
	if catalog == null or data == null or not data.has_method("count") or data.count() <= 0:
		push_error("世界地图节点表缺失：不能打开飞艇世界地图。")
		return false
	candidates = _static_candidates()
	candidates[Slot.CURRENT] = Destination.new(saved_map_id, saved_tile_x, saved_tile_y)
	for destination: Destination in candidates:
		if data.node(destination.map_id).is_empty():
			push_error("世界地图里没有 %d 号地图：不能打开飞艇世界地图。" % destination.map_id)
			return false
	_catalog = catalog
	_data = data
	_enabled = enabled
	_passed = passed
	_closing = false
	page = Page.MAP
	selected = Slot.CURRENT
	# 确认框回到稳态再藏起来：`warp_confirm.gd::open()` 会拒绝在动画中的框上开窗。
	$Confirm.stop_transition()
	$Confirm.hide()
	_present_candidates()
	_apply_selection()
	show()
	open_window()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	close_window()


func closing() -> bool:
	return _closing


func handle_key(key: String) -> bool:
	if _closing:
		return true
	if page == Page.CONFIRM:
		return _handle_confirm_key(key)
	match key:
		"ArrowUp":
			_step(Step.UP)
		"ArrowDown":
			_step(Step.DOWN)
		"ArrowLeft":
			_step(Step.LEFT)
		"ArrowRight":
			_step(Step.RIGHT)
		"Enter", "Space":
			_accept()
		"Escape", "Backspace":
			close_requested.emit()
		_:
			return false
	return true


## 原生 `.rodata 0x98a9c` 的 `[地图号, tile_x, tile_y]`（名称即 `map/m<id>.mif:name`）；
## 下标 3 的三项在 `Field_Warp2_Draw:44-46` 里一律被 `ParamData.warp_saved_*` 覆盖
## （唯一写入点是 `Field_Warp1_mKeyPressed:17-19`；原生新档由 `Param_saveINIT`
## memset 成 0，`Param_stdInit` 不碰）。占位值取本工程的同一个初值（`StoryRuntime`），
## 不在这一页另写一份数字。
static func _static_candidates() -> Array[Destination]:
	var result: Array[Destination] = [
		Destination.new(6, 15, 15),    # 雷因城
		Destination.new(36, 21, 15),   # 耶迪思城
		Destination.new(66, 17, 19),   # 卡林胡城
		Destination.new(StoryRuntime.WARP_SAVED_MAP_INITIAL,     # 上船位置占位
			StoryRuntime.WARP_SAVED_TILE_INITIAL, StoryRuntime.WARP_SAVED_TILE_INITIAL),
		Destination.new(97, 15, 13),   # 未知岛1
	]
	return result


func _slot(index: int) -> Control:
	return $Content/Map/Slots.get_child(index)


func _step(step: Step) -> void:
	selected = SELECTION_AFTER_STEP[step][selected]
	_apply_selection()


func _press_candidate(index: int) -> void:
	if _closing or page != Page.MAP:
		return
	# 原生给每个 50×50 触控区注册的键：选中项是 OK，其余是「朝它走一步」的方向键。
	if index == selected:
		_accept()
	elif index == Slot.CURRENT:
		_step(STEP_TO_CURRENT[selected])
	else:
		_step(NODE_STEPS[index])


## 原生子状态 0 的 `−5`：`Map_warpIsPASS` 与 `Map_warpIsEnable` 都通过才进确认框，否则 fxt 43。
func _accept() -> void:
	var destination := candidates[selected]
	if not (_is_passed(destination.map_id) and _is_enabled(destination.map_id)):
		MessageStack.say_record(Msg.Id.WARP_CANNOT_MOVE)
		return
	page = Page.CONFIRM
	# WARP2 的正文是 fxt 44（`Field_Warp2_mPaint:13`）；折行、摆位与两只键都由确认框自己的
	# `_render()` 一次算完，本页不再二次重排。
	if not $Confirm.open(_catalog, Msg.Id.WARP_CONFIRM_MOVE):
		page = Page.MAP


func _handle_confirm_key(key: String) -> bool:
	match key:
		"ArrowLeft", "ArrowRight":
			$Confirm.select(WarpConfirmBox.Answer.NO
				if $Confirm.cursor == WarpConfirmBox.Answer.YES else WarpConfirmBox.Answer.YES)
		"Enter", "Space":
			_decide()
		"Escape", "Backspace":
			_cancel_confirm()
		_:
			return false
	return true


## 原生子状态 1 的 `−5`：游标 0（是）→ `Object_objDIRECT(obj, 32)` + `Object_objANI(obj, 10)` 后关窗；
## 换图由宿主在 ANI 10 播完后做，这里只把目的地交出去。
func _decide() -> void:
	if _closing or page != Page.CONFIRM:
		return
	if $Confirm.cursor != WarpConfirmBox.Answer.YES:
		_cancel_confirm()
		return
	var destination := candidates[selected]
	# 确认框随整页一起消失（`Field_Warp2_mKeyPressed:26` 只把整页相位写 −1），
	# 不再让两个 `AnimationPlayer` 同帧收尾。
	$Confirm.hide()
	move_requested.emit(destination.map_id, destination.tile_x, destination.tile_y)
	close()


func _cancel_confirm() -> void:
	if _closing or page != Page.CONFIRM:
		return
	# 取消只收确认框：原生这里整页相位不动，收完（−4）由 `_on_confirm_finished` 回到地图层。
	$Confirm.close()


func _present_candidates() -> void:
	for index in range(candidates.size()):
		var destination := candidates[index]
		var slot := _slot(index)
		slot.get_node("Name").text = _catalog.text_message(
			"map/m%d.mif" % destination.map_id, "name")
		var icon: TextureRect = slot.get_node("Icon")
		var texture: Texture2D = _catalog.load_sprite(ICON_FORMAT % _data.icon(destination.map_id))
		icon.texture = texture
		if texture != null:
			var icon_size := Vector2i(texture.get_size())
			icon.size = Vector2(icon_size)
			icon.position = Vector2((Vector2i(slot.size) - icon_size) / 2)
		# `Map_warpIsPASS == 0` 时原生整帧用 `GRP_MODE_GRAY` 画，这里换成灰阶材质。
		icon.material = null if _is_passed(destination.map_id) else _gray_material
		slot.get_node("Disabled").visible = not _is_enabled(destination.map_id)


## 选中项由飞艇小人标出（原生 `Object_drawBASIC(icon_x, icon_y, …, 1026, run_counter, 1)`）。
func _apply_selection() -> void:
	var slot := _slot(selected)
	$Content/Map/Marker.position = slot.position + slot.size / 2.0


## `Map_warpIsPASS`：没去过的地图图标整帧灰。
func _is_passed(map_id: int) -> bool:
	return bool(_passed.get(str(map_id), false))


## `Map_warpIsEnable`：缺省视为开放（与 `world_map_canvas.gd` 的 `_is_enabled` 同口径）。
func _is_enabled(map_id: int) -> bool:
	return _enabled.get(str(map_id)) != false


func _on_transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	_closing = false
	# 宿主在 `closed` 里做 `remove_child` + `queue_free`（`field_runtime._free_warp_world`）。
	# 这条 `closed` 是从 `AnimationPlayer.animation_finished` 的回调栈里发出的，在那一层里拆树
	# 会让引擎崩（鼠标点过确认键后实测 signal 11），所以推到空闲队列再发。
	closed.emit.call_deferred()


func _on_confirm_finished(opened: bool) -> void:
	if opened or page != Page.CONFIRM:
		return
	$Confirm.hide()
	page = Page.MAP
