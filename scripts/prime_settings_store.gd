extends RefCounted
## 设置项默认值、校验与持久化。

const SETTINGS_PATH := "user://setup.cfg"

const DEFAULTS := {
	"speed": 4,
	"sound_mode": 0,
	"volume": 1,
	"vibration": 1,
	"display": 1,
}

const RANGES := {
	"speed": Vector2i(0, 4),
	"sound_mode": Vector2i(0, 2),
	"volume": Vector2i(0, 5),
	"vibration": Vector2i(0, 3),
	"display": Vector2i(0, 1),
}


static func load_settings(path: String = SETTINGS_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return DEFAULTS.duplicate(true)
	if error != OK:
		push_error("Could not load Prime settings from %s: %s" % [path, error_string(error)])
		return DEFAULTS.duplicate(true)

	var values: Dictionary = {}
	for key: String in DEFAULTS:
		var value: Variant = config.get_value("prime", key, DEFAULTS[key])
		var limits: Vector2i = RANGES[key]
		if not value is int or value < limits.x or value > limits.y:
			push_error("Prime settings file contains an unsupported value for %s." % key)
			return DEFAULTS.duplicate(true)
		values[key] = value
	return values


static func save_settings(values: Dictionary, path: String = SETTINGS_PATH) -> int:
	for key: String in DEFAULTS:
		if not values.has(key) or not values[key] is int:
			return ERR_INVALID_DATA
		var limits: Vector2i = RANGES[key]
		if values[key] < limits.x or values[key] > limits.y:
			return ERR_INVALID_DATA

	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value("prime", key, values[key])
	return config.save(path)
