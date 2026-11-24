extends "res://tests/unit/gut_case.gd"

var _checks := 0
var _failures := 0


func _run() -> void:
	await get_tree().process_frame
	var audio: Node = get_tree().root.get_node("AudioManager")
	var music: AudioStreamPlayer = audio.get_node("Music")
	var sfx: AudioStreamPlayer = audio.get_node("SFX")
	var first := Node.new()
	first.name = "FirstScene"
	get_tree().root.add_child(first)
	audio.activate(first)
	audio.set_paused(false)
	audio.apply_settings(first, {"volume": 2, "sound_mode": 0})
	_check(audio.play_music(first, 102) and music.playing, "scene starts music")
	_check(audio.play_effect(first, 123) and audio.play_effect(first, 124) and
		audio.is_effect_playing(123) and audio.is_effect_playing(124),
		"different sound effects overlap without replacing one another")
	var second := Node.new()
	second.name = "SecondScene"
	get_tree().root.add_child(second)
	audio.activate(second)
	audio.play_effect(second, 123)
	second.free()
	_check(not music.playing and music.stream == null and not sfx.playing and
		audio._effects.is_empty() and audio._loaded_ids.is_empty(),
		"active scene destruction stops and releases all loaded audio")
	print("Audio manager: %d checks, %d failures" % [_checks, _failures])


func _check(condition: bool, message: String) -> void:
	assert_true(condition, message)
	_checks += 1
	if not condition:
		_failures += 1
		printerr(message)


func test_legacy_suite() -> void:
	await _run()
