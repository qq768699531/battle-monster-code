extends Control

const MessageStack = preload("res://engine/ui/message_stack/message_stack.gd")
## 管理菜单的展示与导航状态机；进度持久化与运行时接入由 host（field_runtime）负责。
##
## 两层导航：顶部页签（selected_tab）→ 页内层级。每个 `*_open` 标志表示「已进入该页的内层」，
## 内层的 CLR/Up 先退回外层，只有顶层的 CLR 才真正关闭菜单。
## 所有会改动进度的操作都通过 progress_changed 交回 host 校验，菜单本身不写存档。

signal close_requested
signal title_requested
signal shared_page_requested(page: int)
signal save_requested(progress: Dictionary)
signal progress_changed(progress: Dictionary)
signal settings_changed(settings: Dictionary, saved: bool)
signal touch_key_pressed(key: int)
## 第 7 组 16「专家的印章」：道具已扣，宿主须关菜单、开原生 `CHARACTER_SELECT_17` 流派页。
signal mastery_change_requested

const Menu = preload("res://game/menu/screen/menu_model/menu_model.gd")
const TouchControls = preload("res://game/field/runtime/touch_controls/touch_controls.gd")
const PrimeSettingsStore = preload("res://game/prime/settings/prime_settings_store/prime_settings_store.gd")
const FieldActors = preload("res://game/field/runtime/field_actors/field_actors.gd")
const WorldResources = preload("res://engine/data/world_resources/world_resources.gd")
const Box2Prompt = preload("res://game/field/runtime/box2_prompt/box2_prompt.gd")
const SlotFrames = preload("res://game/menu/party/slot_frames/slot_frames.gd")
const SlotGrade = preload("res://game/menu/party/slot_grade/slot_grade.gd")
const TAB_LABELS := ["状态", "道具", "队伍", "任务", "选项", "网络"]
const TAB_LABEL_WIDTHS := [33, 20, 29, 27, 17, 33]
const TAB_NATIVE_INDICES := Menu.TAB_NATIVE_INDICES
const QUEST_LABEL_WIDTHS := [68, 74, 60]
const OPTION_MESSAGE_IDS := [197, 33, 34, 35]
const OPTION_CARD_SELECTED_BORDER := Color("#7bd7ff")
const OPTION_CARD_BORDER := Color("#18557b")
## 选项页「存档」的两段 Box2 弹窗：原生 `Menu_Option_mPaint` 的 `quest_layer`
## 1→2→3——层 1／2 画 `Menu_win_Box2_DrawMessage` 的 msg 199「存档中...」，层 2 里调
## `Game_saveSAVE()`，层 3 换成 `Menu_win_Box2_DrawOk` 的 msg 200「存档完毕」。
## `Menu_Option_mRun:26-29` 在开窗计数到 4 时把层号从 1 推到 2，写盘发生在开窗之后。
enum OptionSavePhase {
	## 没有弹窗，选项页在跑。
	CLOSED,
	## 层 1／2：只画「存档中...」，等开窗动画走完再交给宿主写盘。
	SAVING,
	## 层 3：「存档完毕」的确认框，等确认。
	DONE,
	## 关窗动画中（原生 `Menu_Option_mRun:8-18` 在窗口关到底才把层号写回 0）。
	CLOSING,
}
# Box2 弹窗的几何（`Menu_win_Box2_DrawWindow`）：宽是 `Menu_win_Box2_DrawMessage` 的立即数 0xA0（160），
# 高 `13 × 行数 + 18`（纯消息）／`13 × 行数 + 44`（带确认按钮），在 400×240 里居中。
# 窗宽与窗高都由 `components/box2_prompt` 按 `confirm_layout.gd` 的公式算，本文件不摆窗口几何。
const ITEM_BAG_CAPACITY := 72
## 该袋在原生道具列表里只有一行（袋号 3 本身的含义未确认，这里只记录列表高度差异）。
const ITEM_SINGLE_ROW_BAG := 3
const WINDOW_RULE := Color("#196485")

var story_progress: Dictionary = {}
## 菜单只声明「做了哪个操作」，宿主持活状态用 `MenuModel.replay_operation` 重放对账；
## 随机球／技能书把本次种子一并带出，回放才能得到同一只怪／同一本书。
var last_progress_operation: Dictionary = {}
## 原生 `Menu_Option_mKeyPressed:37-40`：`ParamData.current_event_resource_id <= 2` 时存档项
## 不开窗（层号不置 1），只推一条 `common/msg.fxt` 198「现在无法存档」。本项目事件号推进与
## 原生不等价，宿主按 `field_runtime.story_unsettled()`（没有稳定快照＝剧情／对话／战斗期间）
## 折算成这道门，开菜单时写进本字段。
var option_save_blocked := false
var gameplay_catalog: GameplayData
var text_resource: Variant
var selected_tab := MenuModel.Tab.STATUS
var selected_status_page := 0
var status_navigation_open := false
var status_equipment_open := false
var status_skill_open := false
var selected_status_skill := 0
var status_allocation_open := false
var status_confirmation_open := false
var selected_status_attribute := 0
var selected_status_confirmation := 1
var pending_status_allocation: Array[int] = [0, 0, 0]
var selected_bag_category := ItemKind.Bag.ITEMS
var item_navigation_open := false
var item_focus := 0
var selected_item_index := 0
var item_scroll_start := 0
var item_target_open := false
var item_actions_open := false
var selected_item_action := 0
var selected_item_target_slot := 0
var item_discard_open := false
var item_discard_item: Dictionary = {}
var item_discard_count := 1
var item_discard_step := 0
var selected_item_discard := 1
var selected_party_member_index := 0
var party_navigation_open := false
var party_actions_open := false
var selected_party_action := 0
var party_equip_open := false
var equipment_scroll_start := 0
var party_equipment_display_open := false
var selected_equipment_index := 0
var party_details_open := false
var selected_party_detail_skill := 0
var party_discard_open := false
var party_discard_index := -1
var party_discard_target: Dictionary = {}
var selected_party_discard := 1
var selected_option_index := 0
var option_navigation_open := false
var option_return_open := false
var selected_option_return := 1
var option_return_accepted := false
var option_save_phase := OptionSavePhase.CLOSED
var selected_setting_index := 0
var settings_open := false
var help_open := false
var help_page_index := 0
var help_scroll_line := 0
var quest_detail_open := false
var world_map_open := false
var quest_navigation_open := false
var selected_quest_index := 0
var network_navigation_open := false
var selected_network_index := 0
var network_scroll_start := 0
var settings_path := PrimeSettingsStore.SETTINGS_PATH
var closed := false
var notice := "":
	set(value):
		notice = value
		if option_save_phase == OptionSavePhase.SAVING:
			# 只有非空的回填才是写盘结果；`_menu_notice("")` 这类清状态不能当成结果，
			# 否则弹窗在拿到结果前就被关掉，「存档中...」一闪而过、页面上什么都不留。
			if not value.is_empty():
				_show_option_save_result(value)
			return
		if option_save_phase != OptionSavePhase.CLOSED:
			# 弹窗还开着（DONE／CLOSING）时再写一次同一次写盘的文案是回声，不再推栈：
			# 原生 `Game_saveSAVE` 不推消息，这条文案宿主写 `note` 时已经进过栈。
			return
		if value.is_empty():
			return
		MessageStack.say(value)
var _pages: Dictionary = {}

var _tab_buttons: Array[Button] = []
var _tab_icons: Array[Array] = []
var _tab_label_frames: Array[Array] = []
var _status_frames: Array[Texture2D] = []
var _status_attribute_frames: Array[Texture2D] = []
var _status_indicator_frames: Array[Texture2D] = []
var _status_choice_frames: Array[Texture2D] = []
var _status_growth_icon: Texture2D
var _status_attribute_error := ""
var _item_frames: Array[Array] = []
var _party_frames: Array[Texture2D] = []
var _quest_label_slices: Array[Texture2D] = []
var _number_texture: Texture2D
var _quest_labels: Texture2D
var _quest_status_icons: Texture2D
var _window_texture: Texture2D
var _item_texture: Texture2D
var _item_names: Dictionary = {}
var _npc_records: Array = []
var _settings: Dictionary = {}
var _status_portrait_node: Control
var _status_portrait_border_node: Control
var _status_portrait_key := ""
var _status_portrait_path := ""
var _status_portrait_frame_key := ""
var _status_portrait_error := ""
var _native_ui_error := ""
var _assets: Node
var _native_outline_style: StyleBoxFlat


func _ready() -> void:
	for name in ["status", "status_confirmation", "items", "item_target", "item_discard", "party",
			"party_detail", "party_equipment", "party_discard", "quest", "quest_detail",
			"world_map", "options", "network"]:
		_pages[name] = get_node(name)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	_native_outline_style = _rounded_outline_style(WINDOW_RULE, 1)
	_assets = get_node_or_null("/root/AssetCatalog")
	_load_item_names()
	_load_native_ui()
	_load_status_npc_records()
	if not _status_attribute_error.is_empty():
		push_error(_status_attribute_error)
	_status_portrait_node = _pages.status.get_node("Portrait/StatusPortraitLayers")
	_status_portrait_border_node = _pages.status.get_node("Portrait/StatusPortraitBorder")
	_pages.world_map.close_requested.connect(_close_world_map)
	$OptionSaveLayer/Window.transition_finished.connect(_option_save_transition_finished)
	$OptionSaveLayer/Window.confirmed.connect(_finish_option_save)
	if not _native_ui_error.is_empty():
		push_error(_native_ui_error)
		notice = _native_ui_error
	_build_frame()
	_render_content()
	# 进菜单那一刻定格背景（原生 `Evt_chtMENU` 进菜单前调 `Field_Basic_Capture`）：菜单各页与
	# 从任务页开出的世界地图都画这一张模糊快照，背景是静止的。
	var shade := ScreenShade.host_shade(self)
	if shade != null:
		shade.freeze()


func bind(progress: Dictionary, catalog: GameplayData, text: Variant) -> void:
	if settings_open or help_open:
		return
	story_progress = progress
	gameplay_catalog = catalog
	text_resource = text
	selected_status_page = 0
	status_navigation_open = false
	status_equipment_open = false
	status_skill_open = false
	selected_status_skill = 0
	status_allocation_open = false
	status_confirmation_open = false
	selected_status_attribute = 0
	selected_status_confirmation = 1
	pending_status_allocation = [0, 0, 0]
	selected_party_member_index = 0
	party_navigation_open = false
	party_actions_open = false
	selected_party_action = 0
	var party_order := Menu.native_party_order(story_progress)
	if not party_order.is_empty():
		selected_party_member_index = int(party_order[0])
	party_equip_open = false
	equipment_scroll_start = 0
	party_equipment_display_open = false
	selected_equipment_index = 0
	item_navigation_open = false
	item_focus = 0
	item_target_open = false
	item_actions_open = false
	selected_item_action = 0
	selected_item_target_slot = 0
	item_discard_open = false
	item_discard_item = {}
	item_discard_count = 1
	item_discard_step = 0
	selected_item_discard = 1
	party_details_open = false
	selected_party_detail_skill = 0
	party_discard_open = false
	party_discard_index = -1
	party_discard_target = {}
	selected_party_discard = 1
	selected_option_index = 0
	option_navigation_open = false
	option_return_open = false
	selected_option_return = 1
	option_return_accepted = false
	option_save_phase = OptionSavePhase.CLOSED
	selected_setting_index = 0
	settings_open = false
	help_open = false
	quest_detail_open = false
	world_map_open = false
	quest_navigation_open = false
	selected_quest_index = 0
	network_navigation_open = false
	selected_network_index = 0
	network_scroll_start = 0
	notice = ""
	closed = false
	if is_node_ready():
		_render_content()


func open(progress: Dictionary, catalog: GameplayData, text: Variant) -> void:
	bind(progress, catalog, text)
	show()


func select_tab(index: int) -> void:
	if index < 0 or index >= Menu.MENU_TABS.size() or closed or \
			status_allocation_open or status_confirmation_open or party_actions_open or party_equip_open \
			or item_actions_open or item_discard_open or party_details_open or party_discard_open or quest_detail_open \
			or option_return_open:
		return
	if settings_open or help_open:
		return
	if selected_tab == MenuModel.Tab.QUEST and index != 3:
		quest_detail_open = false
	if selected_tab == MenuModel.Tab.PARTY and index != 2:
		party_equip_open = false
		party_details_open = false
		party_equipment_display_open = false
	if selected_tab == MenuModel.Tab.ITEMS and index != 1:
		item_target_open = false
	selected_tab = index
	option_navigation_open = false
	network_navigation_open = false
	quest_navigation_open = false
	party_navigation_open = false
	selected_status_page = 0
	status_navigation_open = false
	status_equipment_open = false
	status_skill_open = false
	selected_status_skill = 0
	status_allocation_open = false
	status_confirmation_open = false
	selected_status_attribute = 0
	pending_status_allocation = [0, 0, 0]
	item_navigation_open = false
	item_focus = 0
	selected_item_index = 0
	item_scroll_start = 0
	help_open = false
	settings_open = false
	notice = ""
	_render_content()


func select_tab_at(x: float, y: float) -> bool:
	for index in range(_tab_buttons.size()):
		if _tab_buttons[index].get_rect().has_point(Vector2(x, y)):
			select_tab(index)
			return true
	return false


func select_bag_category(category: int) -> void:
	if category < 0 or category >= ItemKind.BAG_COUNT or closed or item_actions_open or \
			item_discard_open:
		return
	selected_bag_category = category
	item_navigation_open = true
	item_focus = 0
	selected_item_index = 0
	item_scroll_start = 0
	_render_content()


func _on_touch_key_pressed(key: int) -> void:
	touch_key_pressed.emit(key)
	press({-1: "ArrowUp", -2: "ArrowDown", -3: "ArrowLeft",
		-4: "ArrowRight", -5: "Enter", -16: "Escape"}[key])


func set_touch_key(key: int) -> void:
	var style: int = TouchControls.Style.PAD_KEYS
	if help_open:
		style = TouchControls.Style.NONE
	elif selected_tab == MenuModel.Tab.STATUS and status_skill_open or selected_tab == MenuModel.Tab.PARTY and party_details_open:
		style = TouchControls.Style.ARROWS_BACK
	$TouchControls.present(style, key)


func request_save() -> void:
	if not closed:
		save_requested.emit(story_progress.duplicate(true))


func close_menu() -> void:
	if closed:
		return
	if settings_open or help_open:
		return
	status_navigation_open = false
	status_skill_open = false
	item_navigation_open = false
	status_allocation_open = false
	status_confirmation_open = false
	pending_status_allocation = [0, 0, 0]
	closed = true
	quest_navigation_open = false
	quest_detail_open = false
	network_navigation_open = false
	hide()
	close_requested.emit()


func move_selected_party_member_last() -> bool:
	var order: Array = Menu.native_party_order(story_progress)
	if order.is_empty():
		notice = "当前没有可调整的出战成员"
		_render_content()
		return false
	var index := selected_party_member_index
	if not order.has(index):
		notice = "此成员不在当前出战队伍中"
		_render_content()
		return false
	var result: Dictionary = Menu.move_party_member_last(story_progress, index)
	if not result.get("ok", false):
		notice = str(result.get("error", "队伍调整不可用"))
		_render_content()
		return false
	notice = "已调整队伍顺序"
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	return true


func leave_selected_party_member() -> bool:
	var result: Dictionary = Menu.leave_party(story_progress, selected_party_member_index)
	if not result.ok:
		notice = result.error
		_render_content()
		return false
	party_actions_open = false
	notice = "已离开队伍"
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	return true


func join_selected_party_member() -> bool:
	var result: Dictionary = Menu.join_party(story_progress, gameplay_catalog,
		selected_party_member_index)
	if not result.ok:
		notice = _menu_text(result.message) if result.has("message") else result.error
		_render_content()
		return false
	party_actions_open = false
	notice = "已设定出战队伍"
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	return true


func open_party_detail() -> void:
	if selected_tab != MenuModel.Tab.PARTY or party_details_open or party_equip_open \
			or selected_party_member_index >= _party_display_members().size():
		return
	party_actions_open = false
	party_details_open = true
	selected_party_detail_skill = 0
	notice = ""
	_render_content()
	_pages.party_detail.open_window()


func open_party_discard() -> void:
	if selected_tab != MenuModel.Tab.PARTY or party_discard_open or party_details_open or party_equip_open:
		return
	var index := selected_party_member_index
	var preview: Dictionary = story_progress.duplicate(true)
	var result := Menu.discard_party_member(preview, index)
	if not result.ok:
		notice = result.error
		_render_content()
		return
	party_actions_open = false
	party_discard_open = true
	party_discard_index = index
	party_discard_target = story_progress.monsters[index].duplicate(true)
	selected_party_discard = 1
	notice = "丢弃会同时销毁身上的装备，不返还背包。" \
		if int(party_discard_target.nativeArguments[3]) >= 0 else ""
	_render_content()
	_pages.party_discard.get_node("Window").open_window()


func open_party_equipment() -> void:
	if party_equip_open:
		return
	var monsters: Variant = story_progress.get("monsters", [])
	if not monsters is Array or selected_party_member_index < 0 or \
			selected_party_member_index >= monsters.size():
		return
	var details := Menu.native_member_details(story_progress, gameplay_catalog,
		selected_party_member_index)
	var equipment: Variant = details.get("member", {}).get("nativeArguments", [])
	if equipment is Array and equipment.size() >= 4 and equipment[3] is int and \
			equipment[3] >= 0:
		notice = "成员已装备；请先卸下当前装备。"
		_render_content()
		return
	party_equip_open = true
	party_actions_open = false
	selected_equipment_index = 0
	equipment_scroll_start = 0
	notice = ""
	_render_content()
	_pages.party_equipment.get_node("Window").open_window()


func equip_selected_party_member() -> bool:
	if not party_equip_open or _pages.party_equipment.get_node("Window").is_transitioning():
		return false
	var rows := Menu.native_inventory_rows(story_progress, gameplay_catalog, 1)
	if selected_equipment_index < 0 or selected_equipment_index >= rows.size():
		return false
	var result := Menu.equip_party_member(story_progress, gameplay_catalog,
		selected_party_member_index,
		int(rows[selected_equipment_index].id))
	if not result.get("ok", false):
		notice = str(result.get("error", "装备不可用"))
		_render_content()
		return false
	notice = "已装备 %s" % _native_item_name(result.item)
	_pages.party_equipment.get_node("Window").close_window()
	progress_changed.emit(story_progress.duplicate(true))
	return true


func unequip_selected_party_member() -> bool:
	var result := Menu.unequip_party_member(story_progress, gameplay_catalog,
		selected_party_member_index)
	if not result.get("ok", false):
		notice = str(result.get("error", "卸下装备不可用"))
		_render_content()
		return false
	party_actions_open = false
	notice = "已卸下 %s" % _native_item_name(result.item)
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	return true


func press(key: String) -> void:
	if closed:
		return
	if option_save_phase != OptionSavePhase.CLOSED:
		_option_save_press(key)
		return
	var page: Control = _pages[Menu.TAB_PAGE_NAMES[selected_tab]]
	if page.handle_key(key):
		return
	if key in ["Escape", "Backspace"]:
		close_menu()
	elif key in ["ArrowLeft", "ArrowRight"]:
		var native_index: int = TAB_NATIVE_INDICES[selected_tab]
		select_tab(TAB_NATIVE_INDICES.find(posmod(native_index +
			(-1 if key == "ArrowLeft" else 1), Menu.MENU_TABS.size())))


func _process(_delta: float) -> void:
	if visible and not closed:
		_pages.status._sync_status_portrait()
		queue_redraw()
		for page in _pages.values():
			page.queue_redraw()


func _load_native_ui() -> void:
	_window_texture = _load_window_frame(0, Vector2(210, 70))
	var tab_label_strip := _load_window_frame(1, Vector2(159, 10))
	var status_sheet := _load_window_frame(2, Vector2(330, 30))
	var status_indicator_sheet := _load_window_frame(7,
		Vector2(29, 50))
	var status_choice_sheet := _load_window_frame(3,
		Vector2(41, 26))
	var status_growth_sheet := _load_window_frame(5, Vector2(49, 7))
	for index in range(6):
		var frame := _slice_sprite(status_indicator_sheet,
			Rect2i(0, index * 5, 29, 5))
		if frame == null:
			_native_ui_error = "Native status indicator slicing failed at index %d." % index
			break
		_status_indicator_frames.append(frame)
	for index in range(2):
		var frame := _slice_sprite(status_choice_sheet,
			Rect2i(0, index * 13, 41, 13))
		if frame == null:
			_native_ui_error = "Native status choice slicing failed at index %d." % index
			break
		_status_choice_frames.append(frame)
	_status_growth_icon = _slice_sprite(status_growth_sheet, Rect2i(0, 0, 11, 5))
	if _status_growth_icon == null:
		_native_ui_error = "Native status growth marker slicing failed."
	var status_attribute_sheet: Variant = _assets.call("load_sprite",
		"common/ui_battle/frame-000") if _assets != null and \
		_assets.has_method("load_sprite") else null
	if status_attribute_sheet is Texture2D and \
			status_attribute_sheet.get_width() >= 78 and status_attribute_sheet.get_height() >= 13:
		for index in range(6):
			var frame := _slice_sprite(status_attribute_sheet,
				Rect2i(index * 13, 0, 13, 13))
			if frame == null:
				_status_attribute_error = "Native status attribute icon slicing failed at index %d." % index
				break
			_status_attribute_frames.append(frame)
	else:
		_status_attribute_error = "Native status attribute icon sheet is unavailable or too small."
	_quest_labels = _load_window_frame(13, Vector2(202, 6))
	_item_texture = _load_window_frame(14, Vector2(198, 60))
	_quest_status_icons = _load_window_frame(17, Vector2(51, 17))
	_number_texture = _load_ui_sprite("common/ui_number/frame-000", Vector2(87, 28))
	if not _native_ui_error.is_empty():
		return
	if _native_ui_error.is_empty():
		for index in range(Menu.MENU_TABS.size()):
			_tab_icons.append([
				_slice_sprite(_window_texture, Rect2i(index * 35, 0, 35, 35)),
				_slice_sprite(_window_texture, Rect2i(index * 35, 35, 35, 35)),
			])
			var label_x := 0
			for previous_index in range(index):
				label_x += TAB_LABEL_WIDTHS[previous_index]
			var label_width: int = TAB_LABEL_WIDTHS[index]
			_tab_label_frames.append([
				_slice_sprite(tab_label_strip, Rect2i(label_x, 0, label_width, 5)),
				_slice_sprite(tab_label_strip, Rect2i(label_x, 5, label_width, 5)),
			])
			_item_frames.append([
				_slice_sprite(_item_texture, Rect2i(index * 33, 0, 33, 30)),
				_slice_sprite(_item_texture, Rect2i(index * 33, 30, 33, 30)),
			])
			if _tab_icons[index].has(null) or _tab_label_frames[index].has(null) or \
					_item_frames[index].has(null):
				_native_ui_error = "Native menu frame slicing failed at index %d." % index
				return
		for index in range(10):
			var frame: Texture2D = _slice_sprite(status_sheet, Rect2i(index * 33, 0, 33, 30))
			if frame == null:
				_native_ui_error = "Native menu status frame slicing failed at index %d." % index
				return
			_status_frames.append(frame)
		_party_frames = SlotFrames.frames()
		var label_x := 0
		for label_width: int in QUEST_LABEL_WIDTHS:
			var label: Texture2D = _slice_sprite(_quest_labels,
					Rect2i(label_x, 0, label_width, 6))
			if label == null:
				_native_ui_error = "Native menu quest label slicing failed."
				return
			_quest_label_slices.append(label)
			label_x += label_width


func _load_item_names() -> void:
	for source in ["common/item_basic.dat", "common/item_skill.dat"]:
		_item_names.merge(_assets.text_messages(source))


func _load_status_npc_records() -> void:
	if not is_instance_valid(_assets):
		push_error("Native status NPC name catalog is unavailable.")
		return
	var world := WorldResources.new()
	if not world.initialize(_assets):
		push_error(world.last_error)
		return
	var records: Variant = world.npc_bindings()
	if not records is Array:
		push_error(world.last_error)
		return
	_npc_records = records


func _native_item_name(item: Dictionary) -> String:
	var name_record: Variant = item.get("name_record")
	if name_record is String and _item_names.has(name_record):
		return str(_item_names[name_record])
	var name: Variant = item.get("name")
	return str(name) if name is String and not name.is_empty() else \
		"原道具 %d:%d" % [int(item.get("type", -1)), int(item.get("index", -1))]


func _load_ui_sprite(sprite_id: String, expected_size: Vector2) -> Texture2D:
	if _assets == null or not _assets.has_method("load_sprite"):
		_native_ui_error = "Native menu asset catalog is unavailable."
		return null
	var texture: Variant = _assets.call("load_sprite", sprite_id)
	if not texture is Texture2D or texture.get_size() != expected_size:
		_native_ui_error = "Native menu sprite is unavailable or has invalid size: %s" % sprite_id
		return null
	return texture


func _load_window_frame(index: int, expected_size: Vector2) -> Texture2D:
	if _assets == null or not _assets.has_method("load_window_frame"):
		_native_ui_error = "Native menu asset catalog is unavailable."
		return null
	var texture: Variant = _assets.call("load_window_frame", index)
	if not texture is Texture2D or texture.get_size() != expected_size:
		_native_ui_error = "Native window frame is unavailable or has invalid size: %d" % index
		return null
	return texture


func _slice_sprite(texture: Texture2D, region: Rect2i) -> Texture2D:
	if texture == null or region.position.x < 0 or region.position.y < 0 or \
			region.end.x > texture.get_width() or region.end.y > texture.get_height():
		return null
	var sliced := AtlasTexture.new()
	if texture is AtlasTexture:
		var source := texture as AtlasTexture
		sliced.atlas = source.atlas
		sliced.region = Rect2i(Vector2i(source.region.position) + region.position, region.size)
	else:
		sliced.atlas = texture
		sliced.region = region
	return sliced


func _build_frame() -> void:
	for index in range(TAB_LABELS.size()):
		var button: Button = get_node("Tab%d" % index)
		button.pressed.connect(func(): select_tab(index))
		_tab_buttons.append(button)


## 统一刷新：决定「当前显示哪一页／哪一层弹窗」，再让该页用自己的 _render_* 绑定数据。
## 固定布局由各页 Scene 决定，这里不改动任何控件的位置或尺寸。
func _render_content() -> void:
	if not is_node_ready():
		return
	# 存档弹窗期间整层吞掉鼠标（选项页仍画在下面，与 `Menu_Option_mPaint` 一致）。
	$OptionSaveLayer.visible = option_save_phase != OptionSavePhase.CLOSED
	# 模态层会盖住页签与底框，避免与下面的页面同时可见。
	var option_modal := selected_tab == MenuModel.Tab.OPTIONS and (help_open or settings_open)
	# 环境设定是从菜单开出的 Prime 页（`main._open_field_page`）：原生 style 35 把半透明方向盘
	# 与 OK／CLR 留在 228×208 窗口外的两侧（`EFC_mainTouchDRAW`），所以只收菜单 chrome、
	# 不收触控面板；命中判据在 Prime 侧（`settings_view.live_regions`），面板本身交出输入。
	var option_settings := selected_tab == MenuModel.Tab.OPTIONS and settings_open
	var status_modal := selected_tab == MenuModel.Tab.STATUS and (status_allocation_open or status_confirmation_open)
	var party_modal := selected_tab == MenuModel.Tab.PARTY and (party_equip_open or party_details_open)
	# `Menu_Quest_mPaint`：overlay 2（世界地图）连 `Menu_win_DrawBasic` 都不调，
	# 菜单窗框、六个页签与页脚键提示整段不画，只剩 `Map_Copy` 的背景与世界地图窗口。
	var world_map_modal := selected_tab == MenuModel.Tab.QUEST and world_map_open
	var chrome_visible := not option_modal and not party_modal and not world_map_modal
	$Frame.visible = chrome_visible
	for index in range(_tab_buttons.size()):
		var button := _tab_buttons[index]
		button.visible = chrome_visible
		button.disabled = status_modal or party_actions_open or party_modal or item_actions_open \
			or item_discard_open or party_discard_open or quest_detail_open or option_return_open
		var native_index: int = TAB_NATIVE_INDICES[index]
		button.get_node("Icon").texture = _tab_icons[native_index][0 if index == selected_tab else 1]
		button.get_node("Caption").texture = _tab_label_frames[native_index][0 if index == selected_tab else 1]
	_update_tab_focus()
	set_touch_key($TouchControls.held_key)
	$TouchControls.visible = not option_modal or option_settings
	$TouchControls.set_interactive(not option_settings)
	# Prime 页（帮助／环境设定）由 `main._open_field_page` 打开，命中判点在 Prime 侧的
	# `live_regions`：菜单这一层不再收触控（原生此时只有 Prime 画布判点，见 `EFC_mainTouch`）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE if option_modal else Control.MOUSE_FILTER_STOP
	for page in _pages.values():
		page.hide()
	var name: String = Menu.TAB_PAGE_NAMES[selected_tab]
	if selected_tab == MenuModel.Tab.PARTY and party_details_open:
		name = "party_detail"
	var page: Control = _pages[name]
	page.show()
	page.call("_render_" + name)
	if option_modal:
		page.hide()
	if item_target_open and selected_tab == MenuModel.Tab.ITEMS:
		_pages.item_target.show()
	if party_equip_open and selected_tab == MenuModel.Tab.PARTY and not party_details_open:
		_pages.party.hide()
		_pages.party_equipment.show()
	if quest_detail_open and selected_tab == MenuModel.Tab.QUEST:
		_pages.quest_detail.show()
	if world_map_open and selected_tab == MenuModel.Tab.QUEST:
		_pages.world_map.show()
	if party_discard_open and selected_tab == MenuModel.Tab.PARTY:
		_pages.party_discard.render()
	if item_discard_open and selected_tab == MenuModel.Tab.ITEMS:
		_pages.item_discard.render()
	# 静态提示行已退役：`notice` 的 setter 会把非空值推到提示栈（原生 `Game_infoInit`），
	# 菜单页脚不再承载提示文本。
	$Notice.visible = false
	if selected_tab == MenuModel.Tab.STATUS and status_confirmation_open:
		_pages.status_confirmation.show()
		_pages.status_confirmation._render_confirmation()
	_pages.status._sync_status_portrait()
	queue_redraw()
	for child in _pages.values():
		child.queue_redraw()


func open_selected_item_actions() -> bool:
	if _selected_inventory_item().is_empty():
		return false
	selected_item_action = 0
	item_actions_open = true
	item_discard_open = false
	notice = ""
	_render_content()
	return true


## 原生状态 11 选「使用」：消耗类进入出战成员选择（状态 9），其余道具没有可选目标。
func use_selected_item() -> bool:
	var item := _selected_inventory_item()
	if item.is_empty():
		return false
	item_actions_open = false
	if not Menu.item_use_supported(item):
		# 原生 `Ball_stdUseEx` 的 default 分支：只提示 510，不扣道具。
		notice = _menu_text(Msg.Id.ITEM_UNUSABLE)
		_render_content()
		return false
	var order := Menu.native_party_order(story_progress)
	if order.is_empty():
		notice = "当前没有可选择的出战成员。"
		_render_content()
		return false
	selected_item_target_slot = 0
	item_target_open = true
	notice = ""
	_render_content()
	return true


## 原生状态 11 选「丢弃」：数量从持有总数起算，堆叠上限为 1 的道具跳过数量选择。
func open_item_discard() -> bool:
	var item := _selected_inventory_item()
	if item.is_empty():
		return false
	item_actions_open = false
	item_discard_item = item
	item_discard_step = 1 if Menu.item_stack_limit(item) == 1 else 0
	item_discard_count = 1 if item_discard_step == 1 else maxi(1, int(item.get("quantity", 1)))
	selected_item_discard = 1
	item_discard_open = true
	notice = ""
	_render_content()
	_pages.item_discard.get_node("Window").open_window()
	return true


## 原生状态 7 的确认（`Item_stdDels`）：扣除后回到道具列表。
func discard_selected_item() -> bool:
	var result := Menu.discard_inventory_item(story_progress, item_discard_item,
		item_discard_count)
	if not result.get("ok", false):
		notice = str(result.get("error", "道具丢弃失败"))
		_render_content()
		return false
	notice = "已丢弃 %s ×%d" % [_native_item_name(item_discard_item), item_discard_count]
	last_progress_operation = {"kind": "discard", "item_id": int(item_discard_item.id),
		"count": item_discard_count, "category": selected_bag_category}
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	return true


func _selected_inventory_item() -> Dictionary:
	var rows := Menu.native_inventory_rows(story_progress, gameplay_catalog,
		selected_bag_category)
	if selected_item_index < 0 or selected_item_index >= rows.size():
		return {}
	return rows[selected_item_index]


func use_selected_item_on_target() -> bool:
	if not item_target_open:
		return false
	var rows := Menu.native_inventory_rows(story_progress, gameplay_catalog,
		selected_bag_category)
	var order := Menu.native_party_order(story_progress)
	if selected_item_index < 0 or selected_item_index >= rows.size() or order.is_empty():
		notice = "道具或出战成员已不可用。"
		_render_content()
		return false
	var member_index := int(order[posmod(selected_item_target_slot, order.size())])
	var item: Dictionary = rows[selected_item_index]
	var random_seed := randi()
	var result := Menu.use_item(story_progress, gameplay_catalog, int(item.id), member_index,
		random_seed)
	if not result.get("ok", false):
		notice = str(result.get("error", "道具使用失败"))
		_render_content()
		return false
	# 原生 `Ball_stdUseEx` 用返回码选 `common/msg.fxt`；拼装与战斗侧共用 `ItemEffect.describe`。
	var code := int(result.get("code", 0))
	notice = ItemEffect.describe(code, item.get("detail_slots", []),
		func(id: int) -> String: return _menu_text(id))
	# 原生无提示的返回码（随机球／书、经验窗口、换流派等）保持静默，不再补占位文案。
	if not bool(result.get("consumed", false)):
		# 原生这几支返回码不扣道具（HP 已满／没有可治疗的异常状态……），停在选目标。
		_render_content()
		return false
	item_target_open = false
	last_progress_operation = {"kind": "use", "item_id": int(item.id),
		"member": member_index, "seed": random_seed}
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()
	if code == ItemEffect.Code.MASTERY_SELECT:
		mastery_change_requested.emit()
	return true


## 宿主取走本轮的菜单操作令牌；取过即清，避免下一轮按钮刷新时被重放。
func take_progress_operation() -> Dictionary:
	var operation := last_progress_operation
	last_progress_operation = {}
	return operation


func _native_item_explanation(item: Dictionary) -> String:
	return Menu.native_item_explanation(item, _menu_text)


## 书本详情页的材料状态行。判定本身只在 `MenuModel.material_recipe_possible` 一处
## （`Menu_Item_Mix_IsPossible`），这里只按配方槽是否存在分三档文案。
func _native_item_mix_status(item: Dictionary) -> String:
	var slots: Variant = item.get("detail_slots")
	if not slots is Array or slots.size() <= Menu.MIX_RECIPE_SLOTS.back():
		return "合成配方不可用"
	return "合成材料齐全" if Menu.material_recipe_possible(story_progress, item) \
		else "合成材料不足"


func _native_catalog_item_name(item_type: int, index: int) -> String:
	var entry: ItemDefinition = gameplay_catalog.item(ItemKind.id_of(item_type, index)) \
		if gameplay_catalog != null else null
	if entry != null and entry.type == item_type and entry.index == index:
		return _native_item_name(Menu.item_row(entry))
	return "原材料 %d" % index


func _member_caption(member: Variant) -> String:
	if not member is Dictionary:
		return "成员记录不可用"
	var args: Variant = member.get("nativeArguments", [])
	var species := "未知"
	var level := "未知"
	if args is Array and args.size() > 0:
		species = str(args[0])
	if args is Array and args.size() > 1:
		level = str(args[1])
	var nickname := str(member["nickname"]) if member.has("nickname") else "未记录"
	return "个体 %s · Lv%s · 性格 %s" % [species, level, nickname]


func _open_quest_detail() -> void:
	if selected_tab != MenuModel.Tab.QUEST or not quest_navigation_open or selected_quest_index != 0 \
			or quest_detail_open:
		return
	quest_detail_open = true
	notice = ""
	_render_content()


## 任务详情里的「世界地图」：原生是同一张 228x208 窗口盖在菜单上（`Menu_world_Draw`），
## 由 `Menu_Quest_mKeyPressed` 把按键转给 `Map_worldKEY`。`focus_map_id` 是任务的第一个
## 关联地域（同一处 `Map_worldINIT(JC_fxtQINDEX(res, 3, 0), 1)`），`-1` 表示用角色所在地图；
## `quest_pages` 是这份任务文本资源的分页，交给 `Map_worldDRAW` 画 mark 1／2。
func _open_world_map(focus_map_id := -1, quest_pages: Variant = null) -> void:
	if selected_tab != MenuModel.Tab.QUEST or not quest_detail_open or world_map_open:
		return
	var data: Variant = _assets.call("load_world_map") \
		if _assets != null and _assets.has_method("load_world_map") else null
	if data == null:
		notice = "世界地图节点表缺失；未打开世界地图。"
		_render_content()
		return
	var progress: Dictionary = story_progress if story_progress is Dictionary else {}
	var player_map := int(progress.get("mapId", 0))
	if not _pages.world_map.open(_assets, data, player_map, progress.get("warpEnabled", {}),
			progress.get("warpPassed", {}), quest_pages,
			focus_map_id if focus_map_id > 0 else player_map):
		return
	world_map_open = true
	notice = ""
	_render_content()


func _close_world_map() -> void:
	if not world_map_open:
		return
	world_map_open = false
	# 关窗动画播完再刷新回详情页，避免动画被 hide() 截断。
	_pages.world_map.closed.connect(_finish_world_map_close, CONNECT_ONE_SHOT)
	_pages.world_map.close()


func _finish_world_map_close() -> void:
	_render_content()


func _menu_text(message_id: int) -> String:
	return _assets.text_message(Msg.SOURCE, message_id)


func _activate_option(index: int) -> void:
	match index:
		0:
			_begin_option_save()
		1:
			_settings = PrimeSettingsStore.load_settings(settings_path)
			selected_setting_index = 0
			settings_open = true
			notice = ""
		2:
			help_open = true
			help_page_index = 0
			help_scroll_line = 0
			notice = ""
		3:
			option_return_open = true
			selected_option_return = 1
			option_return_accepted = false
			notice = ""
			_pages.options.get_node("ReturnWindow").open_window()
	_render_content()
	if index in [1, 2]:
		shared_page_requested.emit(12 if index == 1 else 13)


func finish_shared_page(values: Dictionary) -> void:
	_settings = values.duplicate(true)
	settings_open = false
	help_open = false
	notice = ""
	_render_content()


## 选项页「存档」第一步：开 `Menu_win_Box2_DrawMessage` 的「存档中...」，不写盘。
## 写盘要等开窗动画走完（`Menu_Option_mRun:26-29` 的层 1 → 层 2）。
func _begin_option_save() -> void:
	if option_save_blocked:
		MessageStack.say_record(Msg.Id.OPTION_SAVE_UNAVAILABLE)
		return
	option_save_phase = OptionSavePhase.SAVING
	$OptionSaveLayer.show()
	$OptionSaveLayer/Window.present(_menu_text(Msg.Id.SAVE_IN_PROGRESS), Box2Prompt.Form.MESSAGE)
	$OptionSaveLayer/Window.open_window()
	_render_content()


## 宿主把写盘结果写回 `notice`（`field_runtime._menu_save_requested` → `_menu_notice`）。
## 成功那一条的正文就是 msg 200，换成 `Menu_win_Box2_DrawOk` 的确认框（原生层 3）。
## 失败文案原生没有形态（`Menu_Option_mPaint:41-43` 只有层 1／2／3，`Game_saveSAVE` 的返回码
## 从不被读取），所以照样用同一个 `DrawOk` 句柄和同一个确认键收尾，只把窗宽按实测正文宽撑开
## （`Box2Prompt.present_fitted`），失败原因整句留在框里——不再关窗把它让给提示栈。
func _show_option_save_result(message: String) -> void:
	option_save_phase = OptionSavePhase.DONE
	var window: Control = $OptionSaveLayer/Window
	if message == _menu_text(Msg.Id.SAVE_DONE):
		window.present(message, Box2Prompt.Form.OK)
	else:
		window.present_fitted(message, Box2Prompt.Form.OK)
	_render_content()


## 弹窗打开期间只有层 3 的确认键生效（原生 DrawOk 只注册 `EFC_mainTouchSET(-5, …)` 那一个矩形）。
func _option_save_press(key: String) -> void:
	if option_save_phase != OptionSavePhase.DONE or \
			$OptionSaveLayer/Window.is_transitioning():
		return
	if key in ["Enter", "Space"]:
		_finish_option_save()


func _finish_option_save() -> void:
	if option_save_phase != OptionSavePhase.DONE or \
			$OptionSaveLayer/Window.is_transitioning():
		return
	option_save_phase = OptionSavePhase.CLOSING
	$OptionSaveLayer/Window.close_window()


## 开窗动画走完才写盘（原生 `Menu_Option_mRun:26-29` 把层 1 推到层 2）。
func _option_save_transition_finished(opened: bool) -> void:
	if opened:
		if option_save_phase == OptionSavePhase.SAVING:
			request_save()
		return
	option_save_phase = OptionSavePhase.CLOSED
	$OptionSaveLayer.hide()
	_render_content()


func _recorded(source: Dictionary, key: String) -> String:
	return str(source[key]) if source.has(key) and source[key] != null else "未记录"


func _rounded_outline_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.draw_center = false
	style.set_border_width_all(1)
	style.border_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = false
	return style


func _update_tab_focus() -> void:
	for index in range(_tab_buttons.size()):
		var material: ShaderMaterial = _tab_buttons[index].get_node("Icon").material
		material.set_shader_parameter("focused", index == selected_tab and
			not (selected_tab == MenuModel.Tab.STATUS and status_navigation_open) and
			not (selected_tab == MenuModel.Tab.ITEMS and item_navigation_open) and
			not (selected_tab == MenuModel.Tab.PARTY and party_navigation_open) and
			not (selected_tab == MenuModel.Tab.QUEST and quest_navigation_open) and
			not (selected_tab == MenuModel.Tab.OPTIONS and option_navigation_open) and
			not (selected_tab == MenuModel.Tab.NETWORK and network_navigation_open))


func _item_visible_rows() -> int:
	return 1 if selected_bag_category == ITEM_SINGLE_ROW_BAG else 2


func _party_display_members() -> Array[int]:
	var monsters: Variant = story_progress.get("monsters", [])
	var members: Array[int] = []
	if monsters is Array:
		for index in range(monsters.size()):
			members.append(index)
	return members


func _party_icon(member: Variant) -> Texture2D:
	if not member is Dictionary:
		return null
	var args: Variant = member.get("nativeArguments")
	if not args is Array or args.size() < 1 or not args[0] is int:
		return null
	var species: MonsterDefinition = _party_species_record(int(args[0]))
	if species == null:
		return null
	var icon_id: Variant = Menu.menu_ball_icon(species.attribute_group)
	if icon_id == null:
		return null
	return _assets.call("load_sprite", "common/ui_item/frame-%03d" % int(icon_id))


func _party_grade_color(member: Variant) -> Variant:
	if not member is Dictionary:
		return null
	var args: Variant = member.get("nativeArguments")
	if not args is Array or args.size() < 1 or not args[0] is int:
		return null
	var species: MonsterDefinition = _party_species_record(int(args[0]))
	if species == null:
		return null
	return _native_grade_color(species.attribute_entry, true)


func _party_species_record(species_id: int) -> MonsterDefinition:
	return gameplay_catalog.monster(species_id) if gameplay_catalog != null else null


func _native_grade_color(grade_index: int, party_member: bool) -> Variant:
	return SlotGrade.of(grade_index, party_member)


func _status_page_count() -> int:
	return Menu.status_page_count(story_progress)


func _member_attribute_group(member: Variant) -> int:
	if not member is Dictionary:
		return -1
	var args: Variant = member.get("nativeArguments")
	if not args is Array or args.is_empty() or not args[0] is int:
		return -1
	var species: MonsterDefinition = gameplay_catalog.monster(int(args[0])) \
		if gameplay_catalog != null else null
	return species.attribute_group if species != null else -1


## 图标帧号随物品记录登记，按物品 id 查询。
func _item_icon_id(item_id: int) -> int:
	if gameplay_catalog == null:
		return -1
	var record: ItemDefinition = gameplay_catalog.item(item_id)
	return record.icon if record != null else -1


## 立绘偏移是原生菜单按物种登记的位移，缺省为 `Vector2.ZERO`；
## `variant` 为 0 普通形态、1 变异形态。
func portrait_offset(species_id: int, variant: int) -> Vector2:
	if gameplay_catalog == null:
		return Vector2.ZERO
	var record: MonsterDefinition = gameplay_catalog.monster(species_id)
	if record == null or variant < 0 or variant >= record.portrait_offset.size():
		return Vector2.ZERO
	return record.portrait_offset[variant]


func _select_status_page(index: int) -> void:
	if status_allocation_open or status_confirmation_open:
		return
	if index < 0 or index >= _status_page_count():
		return
	selected_status_page = index
	status_navigation_open = true
	status_skill_open = false
	selected_status_skill = 0
	notice = ""
	_render_content()


func _select_status_attribute(index: int) -> void:
	if index < 0 or index >= 3 or status_confirmation_open:
		return
	selected_status_attribute = index
	if status_navigation_open and not status_allocation_open:
		if selected_status_page != 0:
			notice = "成员状态为只读"
		else:
			status_allocation_open = true
			pending_status_allocation = [0, 0, 0]
			notice = ""
	_render_content()


func _stage_status_attribute(index: int) -> void:
	_select_status_attribute(index)
	if status_allocation_open:
		_stage_status_allocation()


func _stage_status_allocation() -> void:
	var result := Menu.status_allocation_preview(story_progress,
		pending_status_allocation, selected_status_attribute)
	if not result.get("ok", false):
		notice = str(result.get("error", "能力点暂不可分配"))
	else:
		pending_status_allocation = result["pending"]
		notice = ""
	_render_content()


func _resolve_status_confirmation() -> void:
	if selected_status_confirmation != 0:
		status_confirmation_open = false
		notice = "继续分配能力点"
		_render_content()
		return
	var result := Menu.apply_status_allocation(story_progress,
		pending_status_allocation)
	if not result.get("ok", false):
		status_confirmation_open = false
		notice = str(result.get("error", "能力点应用失败"))
		_render_content()
		return
	story_progress = result["progress"]
	status_confirmation_open = false
	status_allocation_open = false
	status_navigation_open = false
	pending_status_allocation = [0, 0, 0]
	notice = "已分配 %d 点能力" % int(result["spent"])
	progress_changed.emit(story_progress.duplicate(true))
	_render_content()


func _select_inventory_item(index: int) -> void:
	if item_actions_open or item_discard_open or index < 0 or index >= ITEM_BAG_CAPACITY:
		return
	selected_item_index = index
	item_navigation_open = true
	item_focus = 1
	notice = ""
	_render_content()


func _select_party_slot(index: int) -> void:
	if party_actions_open or party_equip_open or party_details_open or party_discard_open \
			or index < 0 or index >= _pages.party.slot_count():
		return
	party_navigation_open = true
	selected_party_member_index = index
	notice = ""
	_render_content()


func _select_party_equipment(index: int) -> void:
	if not party_equip_open or _pages.party_equipment.get_node("Window").is_transitioning() \
			or index < 0 or index >= _pages.party_equipment.slot_count():
		return
	selected_equipment_index = index
	notice = ""
	_render_content()
