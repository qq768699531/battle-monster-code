extends RefCounted
## 环境设定页的状态机。

const C = preload("res://prime/runtime_constants/runtime_constants.gd")
# 默认值与取值范围以 prime_settings_store 为唯一来源，避免两处各写一份后失配。
const Store = preload("res://prime/prime_settings_store/prime_settings_store.gd")

var settings_selected := 0
var settings := Store.DEFAULTS.duplicate(true)


## 先整体校验、再整体写入：保证失败时不留下部分生效的设置。
func set_settings(values: Dictionary) -> void:
	for key: String in settings:
		if not values.has(key) or not values[key] is int:
			push_error("Missing or invalid Prime setting: %s" % key)
			return
		var limits: Vector2i = Store.RANGES[key]
		var candidate := int(values[key])
		if candidate < limits.x or candidate > limits.y:
			push_error("Prime setting %s is outside its supported range." % key)
			return
	for key: String in settings:
		settings[key] = int(values[key])


func speed_scale() -> float:
	return 50.0 / float(C.SPEED_INTERVALS_MS[int(settings.speed)])


func select_setting(index: int) -> void:
	if index < 0 or index >= Store.DEFAULTS.size():
		push_error("Prime settings row is outside the selectable range.")
		return
	settings_selected = index


func _dispatch_settings_key(context: RefCounted, key: int) -> void:
	if key == TouchCode.Key.BACK:
		context._pending_effects.append({"kind": "settings-save", "settings": settings.duplicate(true)})
		if context.window_state > 0:
			context.window_state = -1
	elif key == TouchCode.Pad.UP or key == TouchCode.Pad.DOWN:
		var step := -1 if key == TouchCode.Pad.UP else 1
		settings_selected = posmod(settings_selected + step, Store.DEFAULTS.size())
	elif key == TouchCode.Pad.LEFT:
		_adjust_setting(context, -1)
	elif key == TouchCode.Pad.RIGHT or key == TouchCode.Key.OK:
		_adjust_setting(context, 1)


## 行的值按 `prime_settings_store.RANGES` 轮回（行序就是 `DEFAULTS` 的声明顺序，与原生
## `Menu_Setup_mKeyPressed` 的 n5 一致：速度 5 档、声音模式 3、音量 6、振动 4、画面 2）。
## 改值当场产生什么效果不在这里决定，只把「哪一行变了」交给启动层那张唯一的映射表
## （`main.gd::_setting_effects`），所以这里没有试听音效号、也没有振动时长表。
func _adjust_setting(context: RefCounted, direction: int) -> void:
	var setting_key: String = String(Store.DEFAULTS.keys()[settings_selected])
	var limits: Vector2i = Store.RANGES[setting_key]
	var previous_value := int(settings[setting_key])
	settings[setting_key] = limits.x + posmod(previous_value - limits.x + direction,
		limits.y - limits.x + 1)
	context._pending_effects.append({"kind": "setting-changed", "setting_key": setting_key,
		"previous_value": previous_value})


func paint_page(context: RefCounted, paint: Dictionary) -> void:
	paint.settings = settings.duplicate(true)
	paint.settings_selected = settings_selected
	paint["window_state"] = context.window_state


func run(context: RefCounted) -> void:
	if context.scene == C.SETTINGS and context.window_state == -4:
		context._return_to_title(1)
