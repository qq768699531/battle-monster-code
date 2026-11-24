extends RefCounted
## Prime 运行时状态的基类（设置、提示、输入等共享字段）。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const LOGO := C.LOGO
const INIT := C.INIT
const NOT_MEM := C.NOT_MEM
const NOT_SPACE := C.NOT_SPACE
const NET_DSP := C.NET_DSP
const TITLE := C.TITLE
const SAVE_SELECT := C.SAVE_SELECT
const SETTINGS := C.SETTINGS
const METHOD := C.METHOD
const INFO := C.INFO
const NETWORK := C.NETWORK
const PRESENT := C.PRESENT
const ZONE := C.ZONE
const TITLE_TARGETS := C.TITLE_TARGETS
const TITLE_TEXT_IDS := C.TITLE_TEXT_IDS
const SPEED_INTERVALS_MS := C.SPEED_INTERVALS_MS
const LOGICAL_SIZE := C.LOGICAL_SIZE

const TitleRuntime = preload("res://game/prime/title/title_runtime/title_runtime.gd")
const StartupRuntime = preload("res://game/prime/startup/startup_runtime/startup_runtime.gd")
const SettingsRuntime = preload("res://game/prime/settings/settings_runtime/settings_runtime.gd")
const SlotRuntime = preload("res://game/prime/slots/slot_runtime/slot_runtime.gd")
const TextPageRuntime = preload("res://game/prime/pages/text_page_runtime/text_page_runtime.gd")
const NoticeRuntime = preload("res://game/prime/network/notice_runtime/notice_runtime.gd")
const NetworkRuntime = preload("res://game/prime/network/network_runtime/network_runtime.gd")
const BattleZoneRuntime = preload("res://game/prime/title/battle_zone_runtime/battle_zone_runtime.gd")

var title_runtime := TitleRuntime.new()
var startup_runtime := StartupRuntime.new()
var settings_runtime := SettingsRuntime.new()
var slot_runtime := SlotRuntime.new()
var text_page_runtime := TextPageRuntime.new()
var notice_runtime := NoticeRuntime.new()
var network_runtime := NetworkRuntime.new()
var battle_zone_runtime := BattleZoneRuntime.new()

var save_slot_selected: int:
	get: return slot_runtime.save_slot_selected
	set(value): slot_runtime.save_slot_selected = value

var _notices: Dictionary:
	get: return notice_runtime._notices
	set(value): notice_runtime._notices = value

var selected: int:
	get: return title_runtime.selected
	set(value): title_runtime.selected = value

var _held_key := 0

var network_battle_zone: bool:
	get: return battle_zone_runtime.network_battle_zone
	set(value): battle_zone_runtime.network_battle_zone = value

var boundary_target := -1

var _regions: Array[Dictionary] = []

var frame := 0

var network_menu_open: bool:
	get: return network_runtime.network_menu_open
	set(value): network_runtime.network_menu_open = value

var settings: Dictionary:
	get: return settings_runtime.settings
	set(value): settings_runtime.settings = value

var warning_text := ""

var settings_selected: int:
	get: return settings_runtime.settings_selected
	set(value): settings_runtime.settings_selected = value

var menu_open: bool:
	get: return title_runtime.menu_open
	set(value): title_runtime.menu_open = value

var opening_frame: int:
	get: return title_runtime.opening_frame
	set(value): title_runtime.opening_frame = value

var modal_selection := 1

var window_state := 0

var warning_state := 0

var page_scroll: int:
	get: return text_page_runtime.page_scroll
	set(value): text_page_runtime.page_scroll = value

var scene := LOGO

var _touches: Array[Vector2i] = []

var title_animation_frame: int:
	get: return title_runtime.title_animation_frame
	set(value): title_runtime.title_animation_frame = value

var network_entry_request: bool:
	get: return network_runtime.network_entry_request
	set(value): network_runtime.network_entry_request = value

var _last_touch := Vector2i(-1000, -1000)

var startup_elapsed_ms: float:
	get: return startup_runtime.startup_elapsed_ms
	set(value): startup_runtime.startup_elapsed_ms = value

## 欢迎页进度条读的真实预载进度（0–1）：`main.gd` 每帧从 `StartupPreload.ratio()` 写入。
## 原生 `Menu_win_Box2_DrawPROGRESS@0x4AEF8:77` 只有计时，这里多留一份真实进度当上限，
## 见 `wiki\ui\startup-preload.md`。
var startup_load_ratio := 0.0

var save_slots: Array[bool]:
	get: return slot_runtime.save_slots
	set(value): slot_runtime.save_slots = value

var network_detail: bool:
	get: return network_runtime.network_detail
	set(value): network_runtime.network_detail = value

var _accumulated_ms := 0.0

var _interval_ms := 50

var modal_state := 0

var network_result: Dictionary:
	get: return network_runtime.network_result
	set(value): network_runtime.network_result = value

var network_detail_action: Dictionary:
	get: return network_runtime.network_detail_action
	set(value): network_runtime.network_detail_action = value

var network_slot_page: bool:
	get: return network_runtime.network_slot_page
	set(value): network_runtime.network_slot_page = value

var slot_animation_phase: int:
	get: return slot_runtime.slot_animation_phase
	set(value): slot_runtime.slot_animation_phase = value

var slot_substate: int:
	get: return slot_runtime.slot_substate
	set(value): slot_runtime.slot_substate = value

var warning_kind := 0

var network_selected: int:
	get: return network_runtime.network_selected
	set(value): network_runtime.network_selected = value

var network_server_time_delta_seconds: int:
	get: return network_runtime.network_server_time_delta_seconds
	set(value): network_runtime.network_server_time_delta_seconds = value

var deletion_pending: bool:
	get: return slot_runtime.deletion_pending
	set(value): slot_runtime.deletion_pending = value

var network_battle_stats: Dictionary:
	get: return battle_zone_runtime.network_battle_stats
	set(value): battle_zone_runtime.network_battle_stats = value

var _keys: Array[int] = []

var network_battle_selected: int:
	get: return battle_zone_runtime.network_battle_selected
	set(value): battle_zone_runtime.network_battle_selected = value

var storage_check_pending: bool:
	get: return startup_runtime.storage_check_pending
	set(value): startup_runtime.storage_check_pending = value

var highlight_frame: int:
	get: return title_runtime.highlight_frame
	set(value): title_runtime.highlight_frame = value

var paused := false

var _pending_effects: Array[Dictionary] = []

var network_request_pending: bool:
	get: return network_runtime.network_request_pending
	set(value): network_runtime.network_request_pending = value

var network_action_confirming: bool:
	get: return network_runtime.network_action_confirming
	set(value): network_runtime.network_action_confirming = value

var page_index: int:
	get: return text_page_runtime.page_index
	set(value): text_page_runtime.page_index = value

var _pages: Dictionary:
	get: return text_page_runtime._pages
	set(value): text_page_runtime._pages = value
