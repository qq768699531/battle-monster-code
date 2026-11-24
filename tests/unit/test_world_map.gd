extends "res://tests/unit/gut_case.gd"

const Fixtures = preload("res://tests/unit/gameplay_fixtures.gd")
const MenuScene = preload("res://game/menu/screen/menu/menu.tscn")
const WorldMapScene = preload("res://game/menu/world_map/world_map/world_map.tscn")
const WindowTransitionScript = preload("res://engine/ui/window_transition/window_transition.gd")
## 「半透明 + 模糊」层用的 shader（`Field_Basic_Capture` 的 `JC_grpFillBLUR`）。
const BLUR_SHADER := "res://shaders/menu_map_blur.gdshader"

## `Map_worldDRAW` 画当前地图用的 `Object_drawBASIC(..., 1026, ...)`，`% 100` = 动作 26。
const HERO_MARKER_ANIMATION_ID := 1026
## 镜头位移是 `world_map.tscn` 的 `CameraMove` 里一条线性 value 轨道（驱动 `CameraRig` 的
## `position`），时长与 `world_map_canvas.gd` 的 `CAMERA_SECONDS` 同值：原生折半在 68 像素差上
## 8 拍收口（20 fps 一拍 0.05 s）。
const CAMERA_CLIP := &"camera_move"
const CAMERA_SECONDS := 0.4

## 四个方向键的几何（400×240 逻辑坐标）。原生 `Menu_world_Draw`：
## 窗口是 `Menu_win_Box4_DrawWindow(228, 208)` → `JC_rtSET((400-228)/2, (240-208)/2, 228, 208)`
## = (86, 16, 228, 208)。每支箭都走 `Menu_battleDrawIcon1(x, y, a3, a4, MIDDLE_CENTER)`：
## a3 = 0 取 `battle_ui` 源 x 0 的 13×8 片（上下），a3 = 1 取源 x 13 的 8×13 片（左右），
## `JC_grpGetANCHOR` 的 MIDDLE_CENTER 扣半宽半高（13>>1 = 6、8>>1 = 4）；
## a4 是镜像位（0 无、1 水平、2 垂直，`JC_imgGetMIRROR` 的 `a2 & 3`）。
## 触控区是随后那行 `EFC_mainTouchSET(key, 1, x, y, 50, 50)`，以图标锚点为中心。
const ARROW_GEOMETRY := {
	# Icon1(w/2 + x = 200, y + 9 = 25, a3 0, a4 0)；touch(x-25 = 175, y-16 = 0)
	"Up": [Rect2i(194, 21, 13, 8), Rect2i(175, 0, 50, 50)],
	# Icon1(200, y + h - 9 = 215, a3 0, a4 2)；touch(x-25 = 175, 底-34 = 190)
	"Down": [Rect2i(194, 211, 13, 8), Rect2i(175, 190, 50, 50)],
	# Icon1(x + 9 = 95, h/2 + y = 120, a3 1, a4 1)；touch(x-16 = 70, 中线-25 = 95)
	"Left": [Rect2i(91, 114, 8, 13), Rect2i(70, 95, 50, 50)],
	# Icon1(x + w - 9 = 305, 120, a3 1, a4 0)；touch(右边-34 = 280, 中线-25 = 95)
	"Right": [Rect2i(301, 114, 8, 13), Rect2i(280, 95, 50, 50)],
}

var viewport: SubViewport
var page: Control


func _frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 整棵树里可见的半透明模糊层数。原生只有 `MapRes.map_scratch_image` 一张快照
## （`Map_Copy` 全屏拷贝），窗口叠几层都还是那一张，所以任何时刻最多一层。
func _visible_blur_layers(node: Node) -> int:
	var total := 0
	var item := node as CanvasItem
	if item != null:
		var material := item.material as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path == BLUR_SHADER and item.is_visible_in_tree():
			total += 1
	for child in node.get_children():
		total += _visible_blur_layers(child)
	return total


func _settle() -> void:
	await get_tree().create_timer(0.2).timeout
	await _frame()


## 按真实的 GUI 命中测试点一次方向箭头（不是直接调 `move_focus`）：按下 + 松开两个事件。
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)


## 原生 `EFC_mainTouchKEY2` 从**最后登记**的触控区往回扫，后登记的先命中；对应 Godot 侧
## 「后出现的控件先收事件」。这里按绘制顺序返回最上层且会吞事件（`mouse_filter` 不是 IGNORE）的控件。
func _swallowing_control(node: Node, point: Vector2) -> Control:
	var hit: Control = null
	for child: Node in node.get_children():
		var picked := _swallowing_control(child, point)
		if picked != null:
			hit = picked
	var control := node as Control
	if hit == null and control != null and control.is_visible_in_tree() \
			and control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and control.get_global_rect().has_point(point):
		hit = control
	return hit


func test_legacy_suite() -> void:
	var catalog: Node = get_node("/root/AssetCatalog")
	var data: Variant = catalog.load_world_map()
	assert_not_null(data, "世界地图节点表应在资源目录里")
	assert_eq(data.count(), 149, "mini.mmi 的 149 条记录全部导出")
	assert_true(data.interior(105), "列 > 99 的记录属于室内层")
	assert_false(data.interior(41))
	assert_eq(data.column(41), 7)
	assert_eq(data.row(41), 0)
	assert_eq(data.links(41), [38], "基连神殿1 只连布罗土之森2")
	assert_eq(data.links(36), [35, 37, 43], "耶迪思城连思伊土之森2、布罗土之森1 与海岸")
	assert_eq(data.extents(false), Vector2i(12, 14), "主层 12 列 14 行（(99,99) 占位不算）")
	assert_eq(data.extents(true), Vector2i(6, 5))

	viewport = SubViewport.new()
	viewport.size = Vector2i(400, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	page = WorldMapScene.instantiate()
	viewport.add_child(page)
	assert_true(page.open(catalog, data, 41, {}, {}), "打开世界地图")
	assert_true(page.is_transitioning() and page.phase == WindowTransitionScript.BoxPhase.BAR_FADED,
		"打开时从原生条形相位开始动画")
	assert_eq(_visible_blur_layers(get_tree().root), 1,
		"单个世界地图窗口只自带一层半透明模糊底")
	# `Menu_world_Draw` 的标题在每个相位都画：相位 1／2 的条形是
	# `Menu_win_Box4_DrawWindow` 的 `height_2 + 6`（头部 12 + 6 = 18 高、`y = (240-18)/2 = 111`），
	# 标题落在 `rect.x+15, rect.y+7`。开窗第一帧就要在，不能等到相位 4。
	var title: Control = page.get_node("Bounds/TitleIcon")
	assert_eq(Rect2i(title.get_global_rect()), Rect2i(101, 118, 62, 5),
		"开窗第一帧标题就在条形头部")
	# 相位 3 是 `y-6`／`height+12` 的条文：原生箭头相对 `out1` 摆位，上／下随上下沿走 6 像素，
	# 左右在竖直中线上不动（`0xC4` 掩码里 3 与 4 同组）。
	page.get_node("AnimationPlayer").advance(0.1)
	var strip := {}
	for name: String in ARROW_GEOMETRY:
		strip[name] = Rect2i(page.get_node("Content/%s" % name).get_global_rect())
	assert_eq([Rect2i(title.get_global_rect()), strip], [Rect2i(101, 17, 62, 5),
		{"Up": Rect2i(175, -6, 50, 50), "Down": Rect2i(175, 196, 50, 50),
			"Left": Rect2i(70, 95, 50, 50), "Right": Rect2i(280, 95, 50, 50)}],
		"相位 3 的箭头与标题跟着开合矩形一起偏移")
	var canvas: Control = page.get_node("Content/Viewport/Canvas")
	# 相机以当前地图为中心：68*7 - 196/2 + 34 = 412，纵向被夹到 0。
	assert_eq(canvas.focus_id(), 41, "刚打开时浏览焦点在角色所在地图")
	assert_eq(canvas.focus_cell(), Vector2i(7, 0))
	assert_eq(canvas.node_center(41), Vector2(98, 24), "基连神殿1 在视口中央")
	assert_eq(canvas.node_center(38), Vector2(98, 82))
	assert_eq(canvas.node_center(37), Vector2(166, 82))
	assert_eq(canvas.node_center(36), Vector2(166, 140))
	# 右上角总览（`Map_worldDRAW` 583–588／916–923）：3 像素一格、2×2 点，右对齐到视口
	# 右上角（`视口宽 − 3*列数 − 3`）；10×10 视口框 `x = 视口宽 − 3*列数 − 4 + 3*(焦点列 − 1)`、
	# `y = 3*(焦点行 − 1) + 3`。视口 196×176、主层 12×14，焦点格 (7,0) 的行 0 在 DRAW 里被夹到 1。
	assert_eq(canvas.overview_dot(Vector2i.ZERO), Vector2i(196 - 3 * 12 - 3, 4),
		"总览点阵右对齐到视口右上角，点阵左上角是 (视口宽 − 3*列数 − 3, 4)")
	assert_eq(canvas.overview_box(), Rect2i(196 - 3 * 12 - 4 + 3 * (7 - 1), 3, 10, 10),
		"10×10 视口框跟着夹取后的焦点格")
	assert_true(canvas.get_index()
		< page.get_node("Content/Viewport/Overview").get_index(),
		"总览点排在画布与名称之后（原生第三段循环在名称之后画点）")
	assert_eq(canvas.get_child_count(), 72, "1 个动画小人 + 主层每格一个名称标签")
	var names := []
	for child: Node in canvas.get_children():
		if child is Control and "text" in child:
			names.append(child.text)
	assert_true(names.has("基连神殿1"), "名称取自 map/m41.mif:name 的翻译")
	assert_true(names.has("布罗土之森2"))
	var marker: Node2D = canvas.get_node("Marker")
	assert_true(marker.visible, "当前地图由单独的动画小人标记")
	assert_eq(marker.position, Vector2(98, 24), "小人脚点落在节点中心")

	await _settle()
	assert_false(page.is_transitioning() and page.phase != WindowTransitionScript.BoxPhase.STABLE,
		"开窗动画结束在最终相位")
	assert_eq(page.get_node("Bounds").size, Vector2(228, 208))
	# 方向键属固定 UI，稳态逐个量：视觉片与 50×50 触控区都要等于 `Menu_world_Draw` 的值。
	var measured: Array = []
	var centered := true
	for name: String in ARROW_GEOMETRY:
		var touch := Rect2i(page.get_node("Content/%s" % name).get_global_rect())
		var icon := Rect2i(page.get_node("Content/%s/Icon" % name).get_global_rect())
		measured.append([icon, touch])
		centered = centered and touch.get_center() == icon.get_center()
	assert_eq(measured, ARROW_GEOMETRY.values(), "四个方向键的视觉矩形与触控矩形")
	assert_true(centered, "四个方向键的 50×50 触控区都以图标锚点为中心")
	# 小人固定播动作 26：两层就是 `frame-083`（17×8）与 `frame-082`（25×22），不是整段待机循环。
	var hero_player: AnimationPlayer = marker.get_node("AnimationPlayer")
	assert_eq(AniAction.action_of_clip(hero_player.current_animation),
		AniAction.action_of(HERO_MARKER_ANIMATION_ID), "当前地图画的是动作 26")
	assert_true(marker.get_node("Layer000").texture.resource_path.ends_with("h_f_01/frame-083.webp")
		and marker.get_node("Layer001").texture.resource_path.ends_with("h_f_01/frame-082.webp"),
		"角色图标只有 frame-083／frame-082 两层")
	var image: Image = viewport.get_texture().get_image()
	var header := image.get_pixel(100, 25)
	assert_true(header.r > 0.9 and header.g > 0.9 and header.b > 0.9, "窗口头部是原生白条")
	var body := image.get_pixel(105, 180)
	assert_true(body.r < 0.06 and body.g < 0.06 and body.b < 0.06,
		"视口底是 70% 黑（`Menu_win_Box4_Draw` 的 179/256）")
	var border := image.get_pixel(90, 100)
	assert_true(border.r > 0.9 and border.g > 0.9 and border.b > 0.9,
		"世界地图窗框 12 像素白边（`Menu_win_Box4_Draw(..., 12, 12)`）")

	# 方向键每次只动一格焦点（原生 `Map_worldKEY` 对 `reserved_0x152[26]`／`[28]` 做 ±1）。
	var start_cell: Vector2i = canvas.focus_cell()
	page.handle_key("ArrowDown")
	assert_eq(canvas.focus_cell() - start_cell, Vector2i.DOWN, "下移一格")
	assert_eq(canvas.focus_id(), 38, "下移到布罗土之森2")
	page.handle_key("ArrowDown")
	assert_eq(canvas.focus_cell() - start_cell, Vector2i.DOWN * 2, "连按第二次也只走一格")
	page.handle_key("ArrowUp")
	page.handle_key("ArrowRight")
	assert_eq(canvas.focus_id(), 37, "右移到布罗土之森1")
	# 切焦点只改焦点与轨道端点，当拍镜头还停在 41 的格上；位移由 Scene 里的线性动画走完
	# （`world_map.tscn` 的 `CameraMove` 驱动 `CameraRig` 的 `position`），中途改向从当前
	# 实际位置续接。落点是夹紧后的居中值，与原折半收敛的终点相同。
	var camera_41: Vector2i = canvas.centered_camera(41)
	var target_37: Vector2i = canvas.centered_camera(37)
	var camera_player: AnimationPlayer = page.get_node("Content/Viewport/CameraMove")
	var camera_rig: Node2D = page.get_node("Content/Viewport/CameraRig")
	var camera_curve: Animation = camera_player.get_animation(CAMERA_CLIP)
	assert_eq([camera_player.is_playing(), camera_curve.track_get_path(0),
		is_equal_approx(camera_curve.length, CAMERA_SECONDS)],
		[true, NodePath("CameraRig:position"), true],
		"方向键启动 Scene 里的线性 value 轨道（CameraRig:position，0.4 s）")
	assert_true(canvas.camera() == camera_41 and canvas.camera() != target_37,
		"切焦点当拍镜头还停在 41 的格上，没有瞬移")
	camera_player.advance(CAMERA_SECONDS)
	canvas.advance()
	assert_eq(canvas.camera(), canvas.centered_camera_cell(canvas.focus_cell()),
		"动画播完镜头落在聚焦格夹紧后的居中值")
	await _frame()
	# 途中改向：轨道起点必须是镜头当前实际位置（不是这次移动的起点），落点跟新焦点格。
	page.handle_key("ArrowLeft")
	camera_player.advance(CAMERA_SECONDS / 2)
	canvas.advance()
	var mid: Vector2i = canvas.camera()
	var mid_position := camera_rig.position
	page.handle_key("ArrowRight")
	var last_key: int = camera_curve.track_get_key_count(0) - 1
	assert_eq([mid.x > canvas.centered_camera_cell(Vector2i(7, 1)).x and mid.x < target_37.x,
		camera_curve.track_get_key_value(0, 0), camera_curve.track_get_key_value(0, last_key)],
		[true, mid_position, Vector2(target_37)],
		"途中再按方向键从当前实际位置续接，落点仍是新焦点格的居中值")
	camera_player.advance(CAMERA_SECONDS)
	canvas.advance()
	page.handle_key("ArrowLeft")
	assert_eq(canvas.focus_cell(), start_cell + Vector2i.DOWN, "左移一格回到布罗土之森2 的格")
	page.handle_key("Enter")
	# `Map_worldKEY` 的 `case -5`：`Map_worldINIT(reserved_0x152[18], 0)`——焦点格重设回
	# **开图地图** 41 的格，镜头不瞬移，由线性动画走回去。
	assert_eq(canvas.focus_cell(), start_cell, "OK 把焦点格重设回开图地图 41 的格")
	assert_eq(canvas.focus_id(), 41, "同格多条记录时取开图那张（41）")
	camera_player.advance(CAMERA_SECONDS)
	canvas.advance()
	assert_eq(canvas.camera(), canvas.centered_camera(41), "线性动画收敛回开图地图")
	watch_signals(page)
	page.handle_key("Escape")
	assert_signal_emitted(page, "close_requested", "BACK 请求关闭")
	page.close()
	assert_true(page.closing(), "关闭先播关窗动画")
	await _settle()
	assert_false(page.visible, "关窗动画结束后隐藏")

	# 焦点只在有地图的格子上走：原生 `Map_worldKEY` 对 `[26]`／`[28]` 是 ±1，但空格上
	# `Map_worldDRAW` 没有节点可画，镜头跟过去之后视口里只剩边缘零散节点——鼠标点方向箭头报的
	# 「地图内容消失」就是这个。地图 3 在 (0,2)，行内它左边没有别的图，所以左移不动。
	assert_true(canvas.present(catalog, data, 3, {}, {}), "以边缘地图 3 重新打开")
	assert_eq(canvas.focus_cell(), Vector2i(0, 2), "开图按 `Map_worldINIT` 写原始格，不夹取")
	page.handle_key("ArrowLeft")
	assert_eq([canvas.focus_cell(), canvas.focus_id()], [Vector2i(0, 2), 3],
		"左边没有别的图：焦点不动、镜头不跟")
	page.handle_key("ArrowLeft")
	assert_eq(canvas.focus_cell(), Vector2i(0, 2), "再左移仍不动")

	# 空格被跳过：38 在 (7,1)，左边最近的有地图格是 (1,1) 的 1 号。
	canvas.present(catalog, data, 38, {}, {})
	await _frame()
	page.handle_key("ArrowLeft")
	assert_eq([canvas.focus_cell(), canvas.focus_id()], [Vector2i(1, 1), 1],
		"左移落到最近的有地图格")
	assert_gt(canvas.node_at(canvas.focus_cell()), 0, "焦点永远落在有地图的格子上")

	# 任务详情 → 世界地图（`Menu_Quest_mKeyPressed` 把按键交给 `Map_worldKEY`）。
	var menu: Control = MenuScene.instantiate()
	viewport.add_child(menu)
	menu.bind({"monsters": [], "inventory": {}, "parameter": {}, "mapId": 41,
		"warpEnabled": {}, "warpPassed": {}}, Fixtures.data(), "标题")
	menu.select_tab(3)
	menu.quest_detail_open = true
	# `Menu_Quest_mKeyPressed`：初始焦点取任务文本资源 page 3 第 0 项，不是角色所在地图。
	menu._open_world_map(36, ["标题", "说明", "目标", "41,38", "36"])
	assert_true(menu.world_map_open, "任务详情打开世界地图")
	assert_true(menu._pages.world_map.visible)
	# `Menu_Quest_mPaint`：overlay 2 连 `Menu_win_DrawBasic` 都不画——菜单窗框与
	# 六个页签整段消失。页签在 `menu.tscn` 里排在 `world_map` 之后，留着就会盖住地图窗的顶边框。
	assert_false(menu.get_node("Frame").visible, "世界地图开着时不画菜单窗框")
	for button: Button in menu._tab_buttons:
		assert_false(button.visible, "世界地图开着时不画页签 %s" % button.name)
	# 列表三个框与详情框都让开（`Menu_Quest_Draw` 的 overlay 2 只画世界地图窗口）。
	for panel_name: String in ["Panel0", "Panel1", "Panel2"]:
		assert_false(menu._pages.quest.get_node(panel_name).is_visible_in_tree(),
			"世界地图开着时不画列表 %s" % panel_name)
	assert_false(menu._pages.quest_detail.get_node("Bounds").is_visible_in_tree(),
		"世界地图开着时不画详情框")
	assert_true(menu._pages.world_map.get_index() > menu._pages.quest_detail.get_index(),
		"世界地图窗口排在详情层之后")
	var menu_canvas: Control = menu._pages.world_map.get_node("Content/Viewport/Canvas")
	assert_true(menu_canvas.focus_id() == 36 and menu_canvas.mark_of(36) == QuestMark.MapMark.TARGET,
		"初始焦点是任务地域 36（角色在 41），page 4 的目标标记随之出现")
	await _settle()
	# 底部触控条（`TouchControls`）排在 `world_map` 之后，是唯一可能吞掉 Down 的 50×50 下沿的东西：
	# `Menu_world_Draw` 每帧最后才登记四支箭（−1／−2／−3／−4），后登记者优先，所以下沿必须仍归箭头。
	var down: Control = menu._pages.world_map.get_node("Content/Down")
	assert_eq(_swallowing_control(menu, down.get_global_rect().position + Vector2(25, 49)), down,
		"Down 的下沿仍归箭头，没被底部触控条截走")
	menu._close_world_map()
	assert_false(menu.world_map_open)
	await _settle()
	assert_false(menu._pages.world_map.visible)

	# 任务标记（`Map_worldDRAW`）：page 3 的地图号是 mark 1（绿），page 4 第 0 项是 mark 2（黄）。
	assert_true(canvas.present(catalog, data, 41, {}, {},
		["标题", "说明", "目标", "41,38", "36"]), "带任务页打开世界地图")
	assert_eq([canvas.mark_of(41), canvas.mark_of(36), canvas.mark_of(37)],
		[QuestMark.MapMark.RELATED, QuestMark.MapMark.TARGET, QuestMark.MapMark.NONE],
		"page 3 → mark 1、page 4 → mark 2，没列到的地图没有标记")
	var mark_delta: Vector2i = canvas.mark_icon_origin(41) - Vector2i(canvas.node_center(41))
	assert_true(mark_delta.x == 15 - 21 / 2 and mark_delta.y >= -10 - 25 / 2
		and mark_delta.y <= -10 - 25 / 2 + 5,
		"标记中心 = 节点中心 + (15, -10 + 三角波 0–5)，锚点扣半宽半高")

	# 角色站在同格的次级记录上也要画小人：`Map_worldDRAW:322-364` 比的是格坐标（列／行），
	# 不是地图号；基连神殿2（42）与基连神殿1（41）同格 (7,0)，但 42 没有连线，被 `layer_ids` 去重掉。
	assert_true(canvas.present(catalog, data, 42, {}, {}), "角色站在基连神殿2 上打开世界地图")
	assert_true(marker.visible, "同格的次级记录上照样画小人")
	assert_eq(marker.position, Vector2(98, 24), "小人脚点落在本格节点中心")

	# 方向箭头（鼠标／触摸）与键盘是**同一条**路径：原生 `Menu_world_Draw` 给四支箭登记的就是
	# `EFC_mainTouchSET(-4／-3／-2／-1, 1, …)` 这组键码，键盘方向键经 `JC_keyMODIFY` 归一成同一组，
	# 两者都进 `Menu_Quest_mKeyPressed` → `Map_worldKEY`（`world_map.gd::_press_arrow`）。
	# 核对两点：一次点击只产生一次焦点变更（结果与按一次键完全相同），且镜头当拍不瞬移、
	# 由 Scene 的 `CameraMove` 动画走完。
	# 上一段把 `menu.tscn` 实例加在同一个 SubViewport 里，它排在页面之后会先收点击，先摘掉。
	viewport.remove_child(menu)
	menu.queue_free()
	await _frame()
	assert_true(page.open(catalog, data, 41, {}, {}), "重新打开世界地图验证 UI 方向箭头")
	await _settle()
	var opening: Array = [canvas.focus_cell(), canvas.centered_camera_cell(canvas.focus_cell())]
	var arrow: Control = page.get_node("Content/Down")
	_click(arrow.get_global_rect().get_center())
	assert_eq([canvas.focus_cell(), canvas.camera()],
		[opening[0] + Vector2i.DOWN, opening[1]],
		"一次箭头点击只移一格焦点，镜头当拍还停在原处")
	_click(arrow.get_global_rect().get_center())
	var by_click: Vector2i = canvas.centered_camera_cell(canvas.focus_cell())
	assert_eq([canvas.focus_cell(), canvas.camera(), camera_player.is_playing()],
		[opening[0] + Vector2i.DOWN * 2, opening[1], true],
		"两次点击各走一格（没有双重触发），镜头由 CameraMove 动画推过去而不是瞬移")
	camera_player.advance(CAMERA_SECONDS)
	canvas.advance()
	assert_eq(canvas.camera(), by_click, "箭头点击的镜头落在焦点格的居中值")
	# 键盘从同一格出发：焦点与镜头目标都要与点击完全一致（同一处 `Map_worldKEY`）。
	canvas.present(catalog, data, 41, {}, {})
	await _frame()
	assert_eq([canvas.focus_cell(), canvas.centered_camera_cell(canvas.focus_cell())], opening,
		"重新开图回到同一初始状态")
	page.handle_key("ArrowDown")
	page.handle_key("ArrowDown")
	assert_eq([canvas.focus_cell(), canvas.centered_camera_cell(canvas.focus_cell())],
		[opening[0] + Vector2i.DOWN * 2, by_click],
		"键盘两次下移得到与两次点击相同的焦点与镜头目标")
