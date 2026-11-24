extends "res://tests/unit/gut_case.gd"

const Store = preload("res://game/prime/settings/prime_settings_store/prime_settings_store.gd")
const TEST_PATH := "user://prime-settings-store-test.cfg"
const DEFAULTS := {
	"speed": 4,
	"sound_mode": 0,
	"volume": 1,
	"vibration": 1,
	"display": 1,
}


func test_legacy_suite() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute_path)

	assert_true(Store.load_settings(TEST_PATH) == DEFAULTS)
	var saved := {
		"speed": 2,
		"sound_mode": 1,
		"volume": 0,
		"vibration": 3,
		"display": 0,
	}
	Store.save_settings(saved, TEST_PATH)
	assert_true(Store.load_settings(TEST_PATH) == saved)
	assert_true(Store.save_settings({"speed": 5}, TEST_PATH) == ERR_INVALID_DATA)
	DirAccess.remove_absolute(absolute_path)
