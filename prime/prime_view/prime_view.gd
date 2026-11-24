extends Node2D
## Prime（标题）页面的装配者：实例化各子页并把自己的 paint 分发给它们。

const Layout = preload("res://prime/layout/layout.gd")
const RuntimeConstants = preload("res://prime/runtime_constants/runtime_constants.gd")
const StartupRuntime = preload("res://prime/startup_runtime/startup_runtime.gd")
const PANEL := Layout.PANEL
const TEXT_CELL_HEIGHT := Layout.TEXT_CELL_HEIGHT
const ICON_WIDTHS := Layout.ICON_WIDTHS
const NUMBER_WIDTHS := Layout.NUMBER_WIDTHS
static var FONT_SIZE: int:
	get: return Layout.FONT_SIZE
static var UI_FONT: Font:
	get: return Layout.UI_FONT

const TitleView = preload("res://prime/title_view/title_view.gd")
const StartupView = preload("res://prime/startup_view/startup_view.gd")
const DialogView = preload("res://prime/dialog_view/dialog_view.gd")
const TextPageView = preload("res://prime/text_page_view/text_page_view.gd")
const NoticeView = preload("res://prime/notice_view/notice_view.gd")
const SlotView = preload("res://prime/slot_view/slot_view.gd")
const NetworkView = preload("res://prime/network_view/network_view.gd")
const BattleZoneView = preload("res://prime/battle_zone_scene/battle_zone_scene.gd")
const SettingsView = preload("res://prime/settings_view/settings_view.gd")
const MarketView = preload("res://prime/market_view/market_view.gd")
const IslandView = preload("res://prime/island_view/island_view.gd")
const MailView = preload("res://prime/mail_view/mail_view.gd")

@onready var title_view: TitleView = $Title
@onready var startup_view: StartupView = $Startup
@onready var dialog_view: DialogView = $Dialogs
@onready var text_page_view: TextPageView = $TextPage
@onready var info_view = $Info
@onready var notice_view: NoticeView = $Notice
@onready var slot_view: SlotView = $Slots
@onready var network_view: NetworkView = $Notice/Network
@onready var battle_zone_view: BattleZoneView = $BattleZone
@onready var settings_view: SettingsView = $Settings
@onready var market_view: MarketView = $Market
@onready var island_view: IslandView = $Island
@onready var mail_view: MailView = $Mail
var last_error := ""
var regions: Array[Dictionary] = []
var messages: Dictionary = {}
var _paint: Dictionary = {}

var _npc_records: Array:
	get: return slot_view._npc_records
	set(value): slot_view._npc_records = value

var slot_progress: Array[Dictionary]:
	get: return slot_view.slot_progress
	set(value): slot_view.slot_progress = value

var _slot_details: Array[Node2D]:
	get: return slot_view._slot_details
	set(value): slot_view._slot_details = value

var _slot_window: Control:
	get: return slot_view._slot_window
	set(value): slot_view._slot_window = value

var _page_number_texture: Texture2D:
	get: return text_page_view._page_number_texture
	set(value): text_page_view._page_number_texture = value

var _battle_headings: Dictionary:
	get: return battle_zone_view._battle_headings
	set(value): battle_zone_view._battle_headings = value


func configure(catalog: Object) -> bool:
	messages = catalog.text_messages(Msg.SOURCE)
	startup_view.configure(messages)
	dialog_view.configure(messages)
	if not notice_view.configure(catalog, messages):
		last_error = "Prime notice footer sprites are unavailable."
		return false
	if not settings_view.configure(catalog, messages):
		last_error = "Prime settings sprites are unavailable."
		return false
	if not slot_view.configure(self, catalog):
		return false
	if not text_page_view.configure(self, catalog):
		return false
	if not info_view.configure(self, catalog):
		return false
	if not battle_zone_view.configure(messages):
		last_error = battle_zone_view.last_error
		return false
	if not market_view.configure(catalog, messages):
		last_error = market_view.last_error
		return false
	if not island_view.configure(catalog, messages):
		last_error = island_view.last_error
		return false
	if not mail_view.configure(catalog, messages):
		last_error = mail_view.last_error
		return false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return true


func present(paint: Dictionary) -> void:
	_paint = paint
	title_view.present(paint)
	startup_view.present(paint)
	settings_view.present(paint)
	dialog_view.present(paint)
	text_page_view.present(paint)
	info_view.present(paint)
	notice_view.present(paint)
	var request_visible: bool = paint.scene == 15 and (
		paint.get("network_entry_request", false) or paint.get("network_result", {}).get("entry_error", false) or
		(paint.get("network_battle_zone", false) and not paint.get("network_detail", false) and
		paint.get("network_request_pending", false)))
	$Request.visible = request_visible
	if request_visible:
		$Request.present(paint, NetworkView.network_message_layout(paint), messages[138])
	slot_view.present(self)
	battle_zone_view.present(paint)
	market_view.present(paint)
	island_view.present(paint)
	mail_view.present(paint)
	regions.clear()
	if paint.scene in [RuntimeConstants.NOT_MEM, RuntimeConstants.NOT_SPACE]:
		if paint.scene == RuntimeConstants.NOT_SPACE or \
				paint.startup_elapsed_ms > StartupRuntime.PROGRESS_FULL_MS:
			regions.append(Layout._region(TouchCode.Key.OK, startup_view.okay_rect(paint)))
	if paint.scene in [13, 14]:
		if paint.scene == 13:
			regions.assign(text_page_view.live_regions(paint))
		else:
			regions.assign(info_view.live_regions(paint))
	elif paint.scene in [16, 17]:
		regions.assign(notice_view.live_regions(paint))
	elif paint.scene == 15:
		var layout_paint := paint.duplicate()
		var button_rects: Array[Rect2i] = []
		for button: Control in network_view.get_node("Buttons").get_children():
			button_rects.append(Rect2i(button.get_global_rect()))
		layout_paint.network_button_rects = button_rects
		if paint.get("network_market_open", false) and not paint.get("network_detail", false):
			layout_paint.network_market_geometry = market_view.layout_geometry()
		if paint.get("network_island_open", false) and not paint.get("network_detail", false):
			layout_paint.network_island_geometry = island_view.layout_geometry()
		if paint.get("network_mail_open", false) and not paint.get("network_detail", false):
			layout_paint.network_mail_geometry = mail_view.layout_geometry()
		if paint.get("network_battle_zone", false) and not paint.get("network_detail", false):
			layout_paint.network_battle_button_rects = battle_zone_view.button_rects()
		regions.assign(NetworkView.network_regions(layout_paint))
		for region: Dictionary in regions:
			if region.get("footer", false):
				var footer: Control = notice_view.get_node(
					"Accept" if region.key == TouchCode.Key.OK else "Back")
				if slot_view.visible:
					footer = slot_view.get_node(
						"Accept" if region.key == TouchCode.Key.OK else "Back")
				region.merge(Layout._region(region.key, Rect2i(footer.get_global_rect())), true)
	if paint.scene == 11 and paint.get("slot_substate", 0) == 0:
		regions.assign(slot_view.live_regions(paint))
	if paint.scene == 12:
		regions.assign(settings_view.live_regions(paint))
	if paint.get("modal_state", 0) != 0:
		regions = dialog_view._modal_regions(paint)
	if paint.get("warning_kind", 0) != 0:
		regions.clear()
		if paint.warning_state in [-1, 2, 3, 4]:
			var layout := warning_layout(paint)
			regions.append(Layout._region(TouchCode.Key.OK,
				dialog_view.get_node("Warning").button_rects(layout, true)[0]))
	visible = paint.scene in [2, 3, 10, 11, 12, 13, 14, 15, 16, 17]
	if paint.get("warning_kind", 0) != 0:
		visible = true


static func window_rect(rect: Rect2i, state: int, title_height: int = 16) -> Rect2i:
	return Layout.window_rect(rect, state, title_height)


static func text_position(font: Font, text: String, at: Vector2, anchor: int = 0) -> Vector2:
	return Layout.text_position(font, text, at, anchor)


static func wrap_text(text: String, width: float, font: Font) -> Array[String]:
	return Layout.wrap_text(text, width, font)


static func box4_window_rect(rect: Rect2i, state: int) -> Rect2i:
	return Layout.box4_window_rect(rect, state)


static func box4_footer_rect(panel: Rect2i, icon: int) -> Rect2i:
	return Layout.box4_footer_rect(panel, icon)


static func box4_footer_regions(panel: Rect2i) -> Array[Dictionary]:
	return Layout.box4_footer_regions(panel)


func startup_layout(paint: Dictionary) -> Dictionary:
	return startup_view.startup_layout(paint)


func modal_layout(paint: Dictionary) -> Dictionary:
	return dialog_view.modal_layout(paint)


func warning_layout(paint: Dictionary) -> Dictionary:
	return dialog_view.warning_layout(paint)


static func page_regions(paint: Dictionary) -> Array[Dictionary]:
	return TextPageView.page_regions(paint)


static func page_scroll_origin(scene: int) -> Vector2i:
	return TextPageView.page_scroll_origin(scene)


static func notice_regions(paint: Dictionary) -> Array[Dictionary]:
	return NoticeView.notice_regions(paint)


func notice_resource(target: int) -> Dictionary:
	return notice_view.notice_resource(target)


func slot_card_data(progress: Dictionary) -> Dictionary:
	return slot_view.slot_card_data(progress)


static func network_panel(paint: Dictionary) -> Rect2i:
	return NetworkView.network_panel(paint)


static func network_regions(paint: Dictionary) -> Array[Dictionary]:
	return NetworkView.network_regions(paint)


static func network_message_layout(paint: Dictionary) -> Dictionary:
	return NetworkView.network_message_layout(paint)


static func battle_zone_button_rect(index: int) -> Rect2i:
	return BattleZoneView.battle_zone_button_rect(index)
