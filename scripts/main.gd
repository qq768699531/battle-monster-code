extends Node2D
## Main：标题、选档、Prime 页面与 Field/Battle 的宿主。
## 显示倍率只在这里设置；业务状态交给各 runtime 与模型脚本。

const PrimeTitleRuntime = preload("res://scripts/prime_title_runtime.gd")
const PrimeSettingsStore = preload("res://scripts/prime_settings_store.gd")
const LocalServiceClient = preload("res://scripts/local_service_client.gd")
const LocalServiceProcess = preload("res://scripts/local_service_process.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const Story = preload("res://scripts/story.gd")
const WorldResources = preload("res://scripts/world_resources.gd")
const EventScripts = preload("res://scripts/data/event_scripts.gd")
const FIELD_SCENE = preload("res://scenes/field/field_runtime.tscn")
const PrimeView = preload("res://scripts/prime_view.gd")
const TouchControls = preload("res://scripts/components/touch_controls.gd")
const NativeTextLayout = preload("res://scripts/native_text_layout.gd")
const StartupPreload = preload("res://scripts/startup_preload.gd")
## 振动档位 → 时长（毫秒）：档位是 `MdaData.vibration_option` 的 `&3` 取值（0 档不振）。
## `Menu_Setup_mKeyPressed` 行3 改完档位随即 `EFC_mdaVIBRATE()` 按档位振一次。
const SETTING_VIBRATION_MS := [0, 60, 100, 200]
## 音量试听的音效：`Menu_Setup_mKeyPressed` 改音量后调 `EFC_mdaPlayDATA(123)`。
## 编号 123 在 `assets/audio/ogg` 里是 `23_effe9.ogg`；同一编号也是试听绕过声音模式的例外
## （`wiki\index.md`「音量 0–5、声音模式及标题 101／试听 123 的既有模式例外」）。
const VOLUME_PREVIEW_RESOURCE_ID := 123
## 战斗视图由野外运行时自己实例化，启动层按这个场景路径认出它来接设置项即时生效的信号。
const BATTLE_SCENE_PATH := "res://scenes/battle.tscn"
## 调试入口（仅验收用）：Prime 页面下按 F9 回到启动欢迎页，用来核对原生
## `Menu_win_Box2_DrawPROGRESS@0x4AEF8` 的框体、点线与进度条。这一页不是「正常流程无法触发」的
## 死分支——原生每次启动都会经过它（`Prime_Init_mRun@0x6ADDC:3` → `Prime_Beta_init@0x6ADD0:3`
## 无条件进状态 2），这个键只是省掉重跑整轮启动。
const DEBUG_STARTUP_PAGE_KEY := KEY_F9

## 事件脚本总表由本场景声明（`main.tscn` 里指向 `assets/events.tres`），运行时不再按 id 拼路径。
@export var event_scripts: EventScripts

@onready var _title = $Title
@onready var _background = $Background
@onready var _overlay: ColorRect = $Boundary
@onready var _prime_view: Node2D = $PrimeView
@onready var _messages: Control = $MessageStack
@onready var _audio: Node = get_node("/root/AudioManager")

var _runtime: PrimeTitleRuntime
var _startup_preload: StartupPreload
var _launch_time_scale := Engine.time_scale
var _title_sprites: Array[Sprite2D]:
	get: return _title._title_sprites
	set(value): _title._title_sprites = value
var _menu_labels: Array[Label]:
	get: return _title._menu_labels
	set(value): _title._menu_labels = value
var _menu_text: Array[String]:
	get: return _title._menu_text
	set(value): _title._menu_text = value
var _title_textures: Array[Texture2D]:
	get: return _title._title_textures
	set(value): _title._title_textures = value
var _fade_overlay: ColorRect:
	get: return _title._fade_overlay
	set(value): _title._fade_overlay = value
var _startup_error := ""
var _save_store: RefCounted
var _local_service_client: Node
var _local_service_process: Node
var _local_service_credentials := {}
var _pending_local_action := {}
var _local_service_configuration_error := ""
var _service_probe_count := 0
var _service_probe_running := false
var _field: Node2D
var _field_prime_page: bool:
	get:
		return _field != null and _field.menu_open and \
			(_field.menu_view.settings_open or _field.menu_view.help_open)
var _touch_index := -1
var _prime_view_configured := false
var _slot_window_state := 0
var _capture_viewport: SubViewport:
	get: return _title._capture_viewport
	set(value): _title._capture_viewport = value
var _captured_background: Texture2D:
	get: return _title._captured_background
	set(value): _title._captured_background = value
var _rendered_scene := -1
var _last_title_frame: int:
	get: return _title._last_title_frame
	set(value): _title._last_title_frame = value
var _last_title_animation: int:
	get: return _title._last_title_animation
	set(value): _title._last_title_animation = value
var _slot_progress: Array[Dictionary] = []
var _title_flash: Node2D:
	get: return _title._title_flash
	set(value): _title._title_flash = value
var _title_flash_sprite: Sprite2D:
	get: return _title._title_flash_sprite
	set(value): _title._title_flash_sprite = value
var _title_flash_texture: Texture2D:
	get: return _title._title_flash_texture
	set(value): _title._title_flash_texture = value
var _title_flash_phase: int:
	get: return _title._title_flash_phase
	set(value): _title._title_flash_phase = value


func _ready() -> void:
	_launch_time_scale = Engine.time_scale
	_runtime = PrimeTitleRuntime.new()
	_startup_preload = StartupPreload.new()
	_save_store = SaveStore.new()
	_local_service_process = LocalServiceProcess.new()
	add_child(_local_service_process)
	if _local_service_process.configure() != OK:
		_local_service_configuration_error = _local_service_process.last_error
	_local_service_client = LocalServiceClient.new()
	_local_service_client.base_url = "http://127.0.0.1:%d/api/v1" % _local_service_process.port
	_local_service_client.response_received.connect(_on_local_service_response)
	add_child(_local_service_client)
	_refresh_slots()
	_runtime.set_settings(PrimeSettingsStore.load_settings())
	_apply_display_setting(_runtime.settings)
	Engine.time_scale = _launch_time_scale
	_audio.activate(self)
	_audio.apply_settings(self, _runtime.settings)
	_load_resources()
	_prime_view_configured = _prime_view.configure(AssetCatalog)
	if not _prime_view_configured:
		_startup_error = _prime_view.last_error
	else:
		_prime_view.slot_progress = _slot_progress
	if _startup_error.is_empty():
		_load_prime_pages()
		for target in [PrimeTitleRuntime.NETWORK, PrimeTitleRuntime.PRESENT, PrimeTitleRuntime.ZONE]:
			_runtime.set_notice(target, _prime_view.notice_resource(target))
		_runtime.start()
	set_process(true)
	if not _startup_error.is_empty():
		_show_boundary(_startup_error, true)
		return


func _process(delta: float) -> void:
	if not _startup_error.is_empty():
		return
	_advance_startup_preload()
	NativeTouchFeedback.frame_interval_ms = _runtime._interval_ms
	if _field != null and not _field_prime_page:
		_field.advance(delta)
		return
	var tick: Dictionary = _runtime.tick(delta)
	if tick.is_empty():
		return
	_apply_effects(tick.effects)
	if _field != null:
		if not _field_prime_page:
			return
		if _runtime.scene == PrimeTitleRuntime.TITLE:
			_finish_field_page()
			return
		Engine.time_scale = _launch_time_scale * _runtime.speed_scale()
	_render(tick.paint)
	if _runtime.boundary_target >= 0:
		_show_boundary("Prime %d is identified but has not been migrated to Godot yet." % _runtime.boundary_target, false)


## 预载推进：线程化组每帧轮询在飞的请求并提交（实测最坏一帧 4.3 ms），地图组按预算在主线程分帧装
## （实测最坏一帧 27 ms）。等欢迎页首帧画出来（`_rendered_scene` 由 `_render()` 写入）再开始，
## 免得解码负载挤进首帧；之后片头／标题／野外期间继续推进，直到清单走完。详见 `wiki\ui\startup-preload.md`。
func _advance_startup_preload() -> void:
	if _rendered_scene < 0 or _startup_preload.is_finished():
		return
	_startup_preload.advance()
	_runtime.startup_load_ratio = _startup_preload.ratio()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and _field != null and not _field_prime_page:
		if _field.handle_key(event):
			get_viewport().set_input_as_handled()
		return
	# GUI may consume release after a touch opened a different view.
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if _touch_index == -1:
				_touch_index = event.index
		elif event.index == _touch_index:
			var handled := _handle_pointer(event.position, "up")
			_touch_index = -1
			if handled:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _handle_pointer(event.position, "up"):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index != _touch_index:
			return
		var phase := "down" if event.pressed and not event.canceled else "up"
		if phase == "up":
			_touch_index = -1
		if _handle_pointer(event.position, phase):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		if event.index == _touch_index and _handle_pointer(event.position, "move"):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if _handle_pointer(event.position, "down" if event.pressed else "up"):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.device != InputEvent.DEVICE_ID_EMULATION and \
				_handle_pointer(event.position, "move"):
			get_viewport().set_input_as_handled()
		return


func _unhandled_key_input(event: InputEvent) -> void:
	if _handle_prime_key_event(event):
		get_viewport().set_input_as_handled()


func _handle_prime_key_event(event: InputEventKey) -> bool:
	if (_field != null and not _field_prime_page) or _runtime == null or _runtime.paused:
		return false
	if event.pressed and not event.echo and event.keycode == DEBUG_STARTUP_PAGE_KEY:
		_runtime.debug_open_startup_page()
		return true
	var key := _prime_keycode(event.keycode)
	if key == 0:
		return false
	if event.pressed:
		if event.echo:
			return false
		_runtime.key_down(key)
	else:
		_runtime.key_up()
	return true


func _prime_keycode(keycode: int) -> int:
	return PrimeTitleRuntime.keycode_to_native(keycode)


func _handle_pointer(viewport_position: Vector2, phase: String) -> bool:
	if _field != null and not _field_prime_page:
		var field_point := _field.get_global_transform_with_canvas().affine_inverse() * \
			viewport_position
		return _field.handle_touch(field_point, phase)
	if _runtime == null or _runtime.paused:
		return false
	var point := get_global_transform_with_canvas().affine_inverse() * viewport_position
	if _runtime.boundary_target >= 0:
		return true
	_runtime.touch(phase, int(point.x), int(point.y))
	return true


func _notification(what: int) -> void:
	if _runtime == null:
		return
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _startup_preload != null:
			_startup_preload.release()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		_runtime.pause()
		if _field != null:
			_field.set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_runtime.resume()
		if _field != null:
			_field.set_focused(not _field_prime_page)


func _load_resources() -> void:
	if AssetCatalog.load_gameplay_catalog() == null:
		_startup_error = "Prime monster data is unavailable."
		return

	for text_id: int in [383, 384, 385, 386, 387]:
		_menu_text.append(AssetCatalog.text_message(Msg.SOURCE, text_id))

	for index in range(2):
		var path := "res://assets/sprite/prime/title-%d.webp" % index
		var texture: Variant = load(path)
		if not texture is Texture2D:
			_startup_error = "Title menu texture could not be loaded: %s" % path
			return
		_title_textures.append(texture)
	_title_flash_texture = AssetCatalog.load_sprite("common/ui_title2/frame-002")
	if _title_flash_texture == null:
		_startup_error = "Prime title flash sprite is unavailable."
		return


func _load_prime_pages() -> void:
	var font := PrimeView.UI_FONT
	for target in [PrimeTitleRuntime.METHOD, PrimeTitleRuntime.INFO]:
		var path := "skt/method.fxt" if target == PrimeTitleRuntime.METHOD else "common/info.fxt"
		var resource: Variant = AssetCatalog.load_text(path)
		if not resource is Dictionary or not resource.get("records") is Array or \
				resource.records.size() == 0 or resource.records.size() % 2 != 0:
			_startup_error = "Prime page resource is invalid: %s" % path
			return
		var pages: Array[Dictionary] = []
		var records: Array = resource.records
		for index in range(0, records.size(), 2):
			if not records[index] is Dictionary or not records[index].get("text") is String or \
					not records[index + 1] is Dictionary:
				_startup_error = "Prime page record is invalid: %s:%d" % [path, index]
				return
			var body := ""
			if records[index + 1].get("text") is String:
				body = records[index + 1].text
			elif records[index + 1].get("text_status") == "removed-korean":
				push_warning("Prime text was removed in the source: %s:%d" % [path, index + 1])
			else:
				_startup_error = "Prime page text is unavailable: %s:%d" % [path, index + 1]
				return
			if target == PrimeTitleRuntime.INFO and index == 0:
				body += "\n[color=#F0F0F0]V1.0.0[/color]"
			var classification: bool = target == PrimeTitleRuntime.INFO and index == 4
			var title_layout := NativeTextLayout.layout(records[index].text,
				font, PrimeView.FONT_SIZE, 0.0, false, Color("#FFB655"))
			var body_layout := NativeTextLayout.layout(body, font, PrimeView.FONT_SIZE,
				0.0 if classification else 173.0, not classification)
			if not title_layout.error.is_empty() or not body_layout.error.is_empty():
				_startup_error = "Prime text layout failed: %s:%d: %s %s" % [
					path, index, title_layout.error, body_layout.error]
				return
			var lines: Array[String] = []
			for line: Dictionary in body_layout.lines:
				lines.append(line.text)
			pages.append({"title": records[index].text, "lines": lines,
				"title_line": title_layout.lines[0], "rich_lines": body_layout.lines})
		_runtime.set_pages(target, pages)


func _render(paint: Dictionary) -> void:
	if int(paint.scene) != _rendered_scene:
		if _field == null and int(paint.scene) in [11, 12, 13, 14, 15, 16, 17]:
			_capture_title()
		elif _capture_viewport != null:
			_title.release_capture()
		_rendered_scene = int(paint.scene)
	if paint.scene == PrimeTitleRuntime.SAVE_SELECT or \
			(paint.scene == PrimeTitleRuntime.TITLE and (bool(paint.menu_open) or int(paint.frame) > 14)):
		_audio.play_music(self, 101, true)
	_title.present(paint)
	_overlay.visible = false
	if paint.scene == PrimeTitleRuntime.SAVE_SELECT or (paint.scene == PrimeTitleRuntime.NETWORK and paint.get("network_slot_page", false) and not paint.get("network_menu_open", false) and not paint.get("network_detail", false)):
		_slot_window_state = int(paint.get("window_state", 4))
	_background.present(paint.scene, _captured_background, _slot_window_state)
	_prime_view.present(paint)
	if paint.scene == PrimeTitleRuntime.TITLE and bool(paint.menu_open) and not paint.regions.is_empty():
		_runtime._regions.assign(_title.menu_regions(int(paint.selected), self))
	elif paint.scene in [PrimeTitleRuntime.SETTINGS, PrimeTitleRuntime.SAVE_SELECT]:
		_runtime._regions.assign(_prime_view.regions)
	if paint.scene == PrimeTitleRuntime.NETWORK and paint.get("network_battle_zone", false):
		_runtime._regions.assign(_prime_view.regions)
	if paint.get("modal_state", 0) != 0 or paint.get("warning_kind", 0) != 0 or \
			paint.scene in [PrimeTitleRuntime.NOT_MEM, PrimeTitleRuntime.NOT_SPACE,
				PrimeTitleRuntime.NETWORK]:
		_runtime.set_modal_regions(_prime_view.regions)
	queue_redraw()


func _apply_effects(effects: Array) -> void:
	_audio.apply_settings(self, _runtime.settings)
	for effect_value: Variant in effects:
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = effect_value
		match effect.get("kind", ""):
			"startup-storage-check":
				var error: int = _save_store.check_storage()
				if error == OK:
					_runtime.set_settings(PrimeSettingsStore.load_settings())
					_audio.apply_settings(self, _runtime.settings)
					_apply_display_setting(_runtime.settings)
				_runtime.complete_storage_check(error)
			"application-exit":
				get_tree().quit()
			"setting-changed":
				for setting_effect: Dictionary in _setting_effects(_runtime.settings,
						String(effect.setting_key), int(effect.previous_value)):
					_apply_setting_effect(setting_effect, _runtime.settings)
			"audio-request", "audio-volume", "vibrate":
				_apply_setting_effect(effect, _runtime.settings)
			"audio-background":
				_audio.play_music(self, int(effect.resource_id), int(effect.resource_id) == 101)
			"audio-stop-all":
				_audio.stop_all(self, bool(effect.get("release", false)))
			"settings-save":
				_save_settings(effect.settings)
				_apply_display_setting(effect.settings)
			"save-slot-selected":
				_enter_field(effect)
			"save-slot-delete":
				var error: int = _save_store.delete_slot(int(effect.slot))
				_runtime.complete_slot_delete(error)
				if error == OK:
					_refresh_slots()
			"local-account":
				_begin_local_service_action({"action": "profile"})
			"local-service-request":
				_begin_local_service_action(effect)
			"local-service-detail-action":
				_begin_local_service_action({"action": "detail-action",
					"detail": effect.action})


## 三种「设置效果」的落点：`audio-request`（`EFC_mdaPlayDATA`，123 号是音量试听）、
## `audio-volume`（`EFC_mdaVOLUME` 的总线音量）与 `vibrate`（`EX_mdaVibrator(1, 时长)`）。
## Prime 设置页与启动检查追加的效果不带自己的设置，用启动层当前那份；战斗内系统菜单把当场
## 那份一起带过来（`apply_setting_change`）。
func _apply_setting_effect(effect: Dictionary, settings: Dictionary) -> void:
	match effect.get("kind", ""):
		"audio-request":
			_audio.play_effect(self, int(effect.resource_id),
				int(effect.resource_id) == VOLUME_PREVIEW_RESOURCE_ID)
		"audio-volume":
			_audio.apply_settings(self, settings)
		"vibrate":
			Input.vibrate_handheld(int(effect.duration_ms))


## 一行设置改值当场产生的效果（`Menu_Setup_mKeyPressed`）：音量当场作用到总线、非 0 时
## 再试听 123 号音效，振动按档位振一次。速度只存（原生只在该画布是 `CANVAS_GAME` 时才
## `EFC_thrSPEED`）、声音模式与画面只改字节，原生都没有即时调用，所以这里也不产生效果。
## **全工程唯一的一张「哪一行 → 什么效果」映射表**：Prime 设置页（`prime/settings_runtime.gd`
## 只发 `setting-changed`）、战斗内系统菜单（`apply_setting_change`）与野外菜单
## （`_apply_field_settings` 按前后两份设置求差）都落到这里，不要在别处再写一份。
func _setting_effects(settings: Dictionary, setting_key: String, previous_value: int) -> Array:
	var effects: Array = []
	if setting_key == "volume":
		effects.append({"kind": "audio-volume"})
		if int(settings.volume) > 0:
			effects.append({"kind": "audio-request", "resource_id": VOLUME_PREVIEW_RESOURCE_ID})
	elif setting_key == "vibration" and int(settings.vibration) != previous_value:
		var duration_ms := int(SETTING_VIBRATION_MS[int(settings.vibration)])
		if duration_ms > 0:
			effects.append({"kind": "vibrate", "duration_ms": duration_ms})
	return effects


## 进野外、野外菜单保存与战斗结束回地图三处共用的「按当前设置施加」：速度（`EFC_thrSPEED` 在工程里
## 就是 `Engine.time_scale`）与总线音量。原生 `EFC_thrSPEED` 只在该画布是 `CANVAS_GAME` 时才调
## （`Menu_Setup_mKeyPressed` 行0），所以战斗内只存的速度要到离开战斗回地图这一刻才落到实处。
## 画面档不在这里：原生 `ParamRes.menu_choice_4_bits` 只有 `Param_setupGET/SET/INIT` 读写，没有任何
## 绘制路径即时消费（`wiki\battle\battle-sysmenu.md` 第 9 节），本工程只在启动与设置写盘时换纹理过滤。
func _apply_current_settings() -> void:
	Engine.time_scale = _launch_time_scale * _runtime.speed_scale()
	_audio.apply_settings(self, _runtime.settings)


## 战斗结束回到野外画布：`completed`（胜利／败北）与 `abandoned`（逃跑／放弃）都走这里。
## 战斗内改速度只存不立即生效（原生行0 的 `CANVAS_GAME` 分支），到这一刻才落到实处；
## 败北与系统菜单「是」回标题那两条由 `_return_to_title` 复位倍速，那个时间点 `_field` 已经没了。
func _battle_finished(_outcome: Dictionary) -> void:
	if _field == null:
		return
	_apply_current_settings()


## 设置项改值当场生效的唯一入口：Prime 设置页的效果走 `_apply_effects`，战斗内系统菜单
## （`battle_ui/sys_menu.gd` 的 `_adjust_setting` → `battle_view.setting_changed`）转到这里，
## 两边共用 `_setting_effects` 与 `_apply_setting_effect`。写盘不在这里
## （原生 `Param_setupSAVE()` 只在 CLR 调）。
func apply_setting_change(settings: Dictionary, setting_key: String, previous_value: int) -> void:
	# 启动层每帧都会按自己那份 `_runtime.settings` 重放音量，所以改值同时把它同步过来，
	# 否则离开战斗后（回标题或回地图）会被旧值改回去。
	_runtime.set_settings(settings)
	for effect: Dictionary in _setting_effects(settings, setting_key, previous_value):
		_apply_setting_effect(effect, settings)


## 战斗视图由野外运行时自己实例化（`FieldRuntime.begin_battle` 的 `add_child`），启动层在它进入场景树
## 时接上设置项即时生效：音频所有者与总线音量都只在启动层这一份。速度在战斗内只存（原生一致），
## 所以两个战斗结局也要接一次，回地图时按新值重设倍速。
func _on_field_child_added(child: Node) -> void:
	if child.scene_file_path != BATTLE_SCENE_PATH:
		return
	child.connect("setting_changed", apply_setting_change)
	child.connect("completed", _battle_finished)
	child.connect("abandoned", _battle_finished)


func _begin_local_service_action(action: Dictionary) -> void:
	_pending_local_action = action.duplicate(true)
	_service_probe_count = 0
	if not _local_service_configuration_error.is_empty():
		_finish_local_service_error("invalid_service_configuration",
			_local_service_configuration_error)
		return
	if not _local_service_client.request_json("service-health", HTTPClient.METHOD_GET, "/health"):
		_start_local_service()


func _start_local_service() -> void:
	if _service_probe_running:
		return
	if not _local_service_configuration_error.is_empty():
		_finish_local_service_error("invalid_service_configuration",
			_local_service_configuration_error)
		return
	if _service_probe_count >= 12:
		_finish_local_service_error("service_unavailable",
			"本地服务启动失败；请安装 Python 3 或手动启动 script/local_service/local_server.py。")
		return
	if _local_service_process.process_id <= 0 or \
			not OS.is_process_running(_local_service_process.process_id):
		var script_path := ProjectSettings.globalize_path(
			"res://../script/local_service/local_server.py")
		var start_error: int = _local_service_process.start(script_path)
		if start_error != OK:
			var message: String = _local_service_process.last_error
			if start_error == ERR_CANT_CREATE:
				message += " 请安装 Python 3 并加入 PATH。"
			_finish_local_service_error("service_start_failed", message)
			return
	_service_probe_count += 1
	_service_probe_running = true
	_probe_local_service.call_deferred()


func _probe_local_service() -> void:
	await get_tree().create_timer(0.25).timeout
	_service_probe_running = false
	if _runtime.scene == PrimeTitleRuntime.NETWORK and _runtime.network_request_pending:
		if not _local_service_client.request_json("service-health", HTTPClient.METHOD_GET, "/health"):
			_start_local_service()


func _finish_local_service_error(code: String, message: String) -> void:
	_pending_local_action.clear()
	_runtime.complete_network_request("local-service", 0, {
		"error": code, "message": message,
	})
	_render(_runtime._paint())


func _begin_local_service_auth() -> void:
	if not _local_service_client.token.is_empty():
		_send_local_service_action()
		return
	var config := ConfigFile.new()
	var load_error := config.load("user://local-prime-account.cfg")
	if load_error == OK:
		var username: Variant = config.get_value("account", "username", "")
		var password: Variant = config.get_value("account", "password", "")
		if username is String and password is String and not username.is_empty() and \
				not password.is_empty():
			_local_service_credentials = {"username": username, "password": password}
			_local_service_client.login(username, password)
			return
	elif load_error != ERR_FILE_NOT_FOUND:
		_finish_local_service_error("credentials_unavailable",
			"本地账户设置无法读取：%s" % error_string(load_error))
		return
	var random_bytes := Crypto.new().generate_random_bytes(24)
	var random_value := random_bytes.hex_encode()
	_local_service_credentials = {
		"username": "player_" + random_value.substr(0, 12),
		"password": random_value,
	}
	_local_service_client.register(_local_service_credentials.username,
		_local_service_credentials.password)


func _send_local_service_action() -> void:
	if _pending_local_action.is_empty():
		return
	var action := str(_pending_local_action.get("action", "profile"))
	var slot := int(_pending_local_action.get("slot", 0))
	match action:
		"network-time":
			if not _local_service_client.request_json("network-time", HTTPClient.METHOD_GET, "/time"):
				_finish_local_service_error("request_failed", "无法发送服务器时间请求。")
		"profile":
			_local_service_client.request_json("profile", HTTPClient.METHOD_GET, "/profile")
		"upload-save":
			var saved: Dictionary = _save_store.load_slot(slot)
			if saved.get("status") == "error":
				_on_local_service_response("upload-save", 0, {
					"error": "local_save_error",
					"message": "本地存档无法读取：%s" % error_string(int(saved.get("error", ERR_FILE_CANT_READ))),
				})
			else:
				_local_service_client.upload_save(slot, saved.get("progress", {}))
		"download-save":
			_local_service_client.download_save(slot)
		"mail":
			_local_service_client.request_json("mail", HTTPClient.METHOD_GET, "/mail")
		"battle-records":
			_local_service_client.request_json("battle-records", HTTPClient.METHOD_GET,
				"/battles/records")
		"battle-quick", "battle-ranked", "battle-ranking":
			_local_service_client.request_json(action, HTTPClient.METHOD_GET, "/ranking")
		"battle-friendly":
			_local_service_client.request_json(action, HTTPClient.METHOD_GET, "/friends")
		"battle-log":
			_local_service_client.request_json(action, HTTPClient.METHOD_GET, "/battles/records")
		"battle-challenge":
			_on_local_service_response(action, 0, {
				"error": "unsupported_action", "message": "挑战赛后续界面尚未还原。",
			})
		"market":
			_local_service_client.request_json("market", HTTPClient.METHOD_GET, "/market")
		"island":
			_local_service_client.request_json("island", HTTPClient.METHOD_GET, "/islands")
		"island-entry":
			if not _local_service_client.request_json("island-entry", HTTPClient.METHOD_GET, "/island"):
				_finish_local_service_error("request_failed", "无法发送未知岛资料请求。")
		"cash":
			_local_service_client.request_json("cash", HTTPClient.METHOD_GET, "/cash")
		"detail-action":
			_send_local_service_detail_action(_pending_local_action.get("detail", {}))
		_:
			_on_local_service_response(action, 0, {
				"error": "unsupported_action", "message": "此本地服务操作尚未接入。",
			})


func _send_local_service_detail_action(detail: Dictionary) -> void:
	var identifier := str(detail.get("id", ""))
	var username := str(detail.get("username", "")).uri_encode()
	var operation := ""
	var path := ""
	var method := HTTPClient.METHOD_POST
	match str(detail.get("kind", "")):
		"claim-mail":
			operation = "claim-mail"
			path = "/mail/%s" % identifier
		"buy-market":
			operation = "buy-market"
			path = "/market/%s:buy" % identifier
		"visit-island":
			operation = "visit-island"
			path = "/islands/%s" % username
			method = HTTPClient.METHOD_GET
		"like-island":
			operation = "like-island"
			path = "/islands/%s/like" % username
		_:
			_on_local_service_response("detail-action", 0, {
				"error": "unsupported_action", "message": "此本地服务操作尚未接入。",
			})
			return
	if not _local_service_client.request_json(operation, method, path):
		_on_local_service_response(operation, 0, {
			"error": "request_failed", "message": "无法发送本地服务请求。",
		})


func _on_local_service_response(operation: String, status: int, payload: Variant) -> void:
	if operation == "service-health":
		if status == 200 and payload is Dictionary and payload.get("ok", false):
			_service_probe_count = 0
			if _pending_local_action.get("action") == "network-time" or \
					not _local_service_client.token.is_empty():
				_send_local_service_action()
			else:
				_begin_local_service_auth()
		else:
			_start_local_service()
		return
	if operation in ["register", "login"]:
		if status >= 200 and status < 300 and payload is Dictionary and \
				payload.get("token") is String:
			_local_service_client.token = payload.token
			var config := ConfigFile.new()
			config.set_value("account", "username", _local_service_credentials.username)
			config.set_value("account", "password", _local_service_credentials.password)
			var save_error := config.save("user://local-prime-account.cfg")
			if save_error != OK:
				push_error("Could not save local service credentials: %s" % error_string(save_error))
			_send_local_service_action()
			return
		if operation == "login" and int(status) == 401:
			_local_service_client.register(_local_service_credentials.username,
				_local_service_credentials.password)
			return
		operation = str(_pending_local_action.get("action", "local-account"))
	elif operation == "download-save" and status >= 200 and status < 300:
		var save_data: Variant = payload.get("save", {}).get("data") \
			if payload is Dictionary else null
		var slot := int(_pending_local_action.get("slot", -1))
		save_data = Story.normalize_integer_types(save_data)
		if not save_data is Dictionary or not Story.validate_progress(save_data, slot):
			status = 422
			payload = {"error": "invalid_save", "message": "服务器存档格式无效；本地存档未更改。"}
		else:
			var save_error: int = _save_store.save(slot, save_data)
			if save_error != OK:
				status = 500
				payload = {"error": "local_save_error",
					"message": "下载成功，但写入本地存档失败：%s" % error_string(save_error)}
			else:
				_refresh_slots()
				payload = {"slot": slot, "downloaded": true}
	_pending_local_action.clear()
	if _runtime.scene == PrimeTitleRuntime.NETWORK and _runtime.network_request_pending:
		_runtime.complete_network_request(operation, int(status), payload)
		var paint := _runtime._paint()
		_render(paint)


func _refresh_slots() -> void:
	var slots: Array = [_save_store.load_slot(0), _save_store.load_slot(1)]
	_runtime.save_slots = [bool(slots[0].occupied), bool(slots[1].occupied)]
	_slot_progress.clear()
	for slot: Dictionary in slots:
		if slot.status == "error":
			_startup_error = "Prime slot %d could not be loaded: %s" % [slot.slot, error_string(slot.error)]
			push_error(_startup_error)
		_slot_progress.append(slot.get("progress", {}) if slot.occupied else {})
	if _prime_view_configured:
		_prime_view.slot_progress = _slot_progress


func _enter_field(effect: Dictionary) -> bool:
	if _field != null or _runtime.scene != PrimeTitleRuntime.SAVE_SELECT or \
			int(effect.get("slot", -1)) not in [0, 1] or \
			int(effect.get("target", -1)) not in [12, 13] or \
			_runtime.boundary_target != int(effect.target):
		return false
	var resources := WorldResources.new()
	if not resources.initialize(AssetCatalog, event_scripts):
		_show_boundary(resources.last_error, false)
		return false
	_runtime.dismiss_boundary()
	_audio.stop_all(self)
	for child in get_children():
		# 消息提示栈不算 Prime 图层：原生 `GameCanvas_mPaint` 在所有页面回调之后才调
		# `Game_infoDraw`，它是盖在 Field／Battle／Game 之上的浮层，跟着一起收起就一条都看不见。
		if child is CanvasItem and child != _messages:
			child.visible = false
	_field = FIELD_SCENE.instantiate()
	add_child(_field)
	# 消息提示栈（原生 `Game_infoDraw`）是 `GameCanvas` 顶层浮层，交给野外运行时推消息与让位。
	_field.set_messages(_messages)
	_apply_current_settings()
	_field.title_requested.connect(_return_to_title)
	_field.shared_page_requested.connect(_open_field_page)
	_field.settings_changed.connect(_apply_field_settings)
	_field.music_requested.connect(_field_music_requested)
	_field.effect_requested.connect(_field_effect_requested)
	_field.child_entered_tree.connect(_on_field_child_added)
	_field.start_slot(_save_store, int(effect.slot), resources, AssetCatalog)
	queue_redraw()
	return true


func _open_field_page(page: int) -> void:
	_field.set_focused(false)
	_runtime.key_up()
	_runtime._reset_page_state()
	_runtime.scene = page
	_runtime.window_state = 1
	_runtime.modal_state = 0
	_runtime._interval_ms = 80
	if page == PrimeTitleRuntime.SETTINGS:
		_runtime.set_settings(_field.menu_view._settings)
		_runtime.settings_selected = 0
		# 游戏内 OPTION 的环境设定：`EFC_mainTouchSTYLE` 对 `MENU_STATE_OPTION` 的层 4 返回 35，
		# 底部只有半透明摇杆 + OK/CLR（没有窗口内图标）。
		_runtime.settings_touch_style = TouchControls.Style.PAD_KEYS
	_render(_runtime._paint())


func _finish_field_page() -> void:
	_prime_view.hide()
	_background.hide()
	_title.hide()
	_field.menu_view.finish_shared_page(_runtime.settings)
	_field.set_focused(not _runtime.paused)


func _return_to_title() -> void:
	if _field == null:
		return
	_audio.stop_all(self)
	_field.music_requested.disconnect(_field_music_requested)
	_field.effect_requested.disconnect(_field_effect_requested)
	remove_child(_field)
	_field.queue_free()
	_field = null
	_background.visible = true
	_title.visible = true
	Engine.time_scale = _launch_time_scale
	_runtime.key_up()
	_runtime.resume()
	_runtime.scene = PrimeTitleRuntime.TITLE
	_runtime.menu_open = true
	_runtime.selected = 0
	_runtime.opening_frame = 7
	_runtime.highlight_frame = 0
	_refresh_slots()
	_render(_runtime._paint())
	queue_redraw()


func _save_settings(values: Dictionary) -> void:
	var path: String = _field.menu_view.settings_path if _field_prime_page \
		else PrimeSettingsStore.SETTINGS_PATH
	var error := PrimeSettingsStore.save_settings(values, path)
	if error != OK:
		var message := "Could not save Prime settings: %s" % error_string(error)
		push_error(message)
		if _field_prime_page:
			_runtime.window_state = 4
			_field.menu_view.notice = "环境设定保存失败：%s；原设置文件未更改。" % error_string(error)
			_field.menu_view._render_content()
	elif _field_prime_page:
		_field.menu_view.notice = ""
		_field.menu_view._render_content()


func _apply_display_setting(values: Dictionary) -> void:
	if not values.has("display"):
		return
	get_viewport().canvas_item_default_texture_filter = \
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST if int(values.display) == 0 \
		else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR


## 野外菜单保存的设置不带行号（`_field.settings_changed` 只有整份设置与是否已写盘），所以按改前
## 改后两份求差得出哪几行变了，再逐行交给同一张 `_setting_effects` 映射表——改音量同样会试听 123，
## 与 Prime 设置页和战斗内系统菜单一致。
func _apply_field_settings(values: Dictionary, saved: bool) -> void:
	var previous: Dictionary = _runtime.settings.duplicate(true)
	_runtime.set_settings(values)
	for setting_key: String in previous:
		var previous_value := int(previous[setting_key])
		if previous_value == int(_runtime.settings[setting_key]):
			continue
		for effect: Dictionary in _setting_effects(_runtime.settings, setting_key, previous_value):
			_apply_setting_effect(effect, _runtime.settings)
	_apply_current_settings()
	_apply_display_setting(_runtime.settings)
	if saved:
		_save_settings(values)


func _field_music_requested(resource_id: int) -> void:
	if resource_id > 0:
		_audio.play_music(self, resource_id)
	else:
		_audio.stop_music(self)


func _field_effect_requested(resource_id: int) -> void:
	_audio.play_effect(self, resource_id)


func _capture_title() -> void:
	_title._capture_title()

func _render_menu(items: Array) -> void:
	_title._render_menu(items)

func _show_boundary(message: String, fatal: bool) -> void:
	if fatal:
		_startup_error = message
	_overlay.show_message(message)
