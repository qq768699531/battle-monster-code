extends Node
## 常驻音频管理：单个 Music 通道 + 八声部 Polyphonic SFX。
## 页面只发请求，音量与声音模式由这里统一作用到总线。

@onready var _music: AudioStreamPlayer = $Music
@onready var _sfx: AudioStreamPlayer = $SFX
@onready var _assets: Node = get_node("/root/AssetCatalog")
@onready var _music_bus := AudioServer.get_bus_index(&"Music")
@onready var _sfx_bus := AudioServer.get_bus_index(&"SFX")

var music_id := -1
var last_error := ""
var _owner_id := 0
var _volume := -1
var _sound_mode := -1
var _music_preview := false
var _paused := false
var _effects: Dictionary = {}
var _loaded_ids: Dictionary = {}


func _ready() -> void:
	_music.finished.connect(_music_finished)


func activate(owner: Node) -> void:
	var id := owner.get_instance_id()
	if _owner_id == id:
		return
	_stop_all(true)
	_owner_id = id
	owner.tree_exiting.connect(_owner_exited.bind(id), CONNECT_ONE_SHOT)


func apply_settings(owner: Node, settings: Dictionary) -> bool:
	if not _owns(owner):
		return false
	var volume := int(settings.volume)
	var mode := int(settings.sound_mode)
	if volume == _volume and mode == _sound_mode:
		return true
	_volume = volume
	_sound_mode = mode
	AudioServer.set_bus_volume_linear(_music_bus, volume / 5.0)
	AudioServer.set_bus_volume_linear(_sfx_bus, volume / 5.0)
	if volume == 0:
		_music.stop()
		_sfx.stop()
		_effects.clear()
	else:
		_discard_finished_effects()
		if mode == 2 and _sfx.playing:
			var playback: AudioStreamPlaybackPolyphonic = _sfx.get_stream_playback()
			for voice: int in _effects.keys():
				if not _effects[voice].preview:
					playback.stop_stream(voice)
					_effects.erase(voice)
	return _sync_music()


func play_music(owner: Node, resource_id: int, preview: bool = false) -> bool:
	if not _owns(owner):
		return false
	if music_id != resource_id:
		_music.stop()
		_music.stream = null
	music_id = resource_id
	_music_preview = preview
	return _sync_music()


func play_effect(owner: Node, resource_id: int, preview: bool = false) -> bool:
	if not _owns(owner):
		return false
	if _volume == 0 or (_sound_mode == 2 and not preview):
		return true
	last_error = ""
	var stream := _load_stream(resource_id)
	if stream == null:
		return false
	if not _sfx.playing:
		_sfx.play()
		_sfx.stream_paused = _paused
	_discard_finished_effects()
	var playback: AudioStreamPlaybackPolyphonic = _sfx.get_stream_playback()
	var voice := playback.play_stream(stream, 0.0, 0.0, 1.0,
		AudioServer.PLAYBACK_TYPE_DEFAULT, &"SFX")
	if voice == AudioStreamPlaybackPolyphonic.INVALID_ID:
		last_error = "Audio SFX polyphony limit reached: %d" % resource_id
		push_warning(last_error)
		return false
	_effects[voice] = {"resource_id": resource_id, "preview": preview}
	return true


func is_effect_playing(resource_id: int) -> bool:
	_discard_finished_effects()
	for effect: Dictionary in _effects.values():
		if effect.resource_id == resource_id:
			return true
	return false


func stop_music(owner: Node) -> void:
	if _owns(owner):
		_stop_music()


func stop_all(owner: Node, release: bool = true) -> void:
	if _owns(owner):
		_stop_all(release)


func set_paused(value: bool) -> void:
	_paused = value
	_music.stream_paused = value
	_sfx.stream_paused = value


func _sync_music() -> bool:
	if music_id < 0:
		return true
	if _volume == 0 or (_sound_mode == 1 and not _music_preview):
		_music.stop()
		return true
	if _music.playing:
		return true
	last_error = ""
	var stream := _load_stream(music_id)
	if stream == null:
		_stop_music()
		return false
	_music.stream = stream
	_music.play()
	_music.stream_paused = _paused
	return true


func _load_stream(resource_id: int) -> AudioStream:
	var stream: AudioStream = _assets.load_audio(resource_id)
	if stream == null:
		last_error = "Audio resource could not be loaded: %d" % resource_id
		push_error(last_error)
	else:
		_loaded_ids[resource_id] = true
	return stream


func _stop_music() -> void:
	_music.stop()
	_music.stream = null
	music_id = -1
	_music_preview = false


func _stop_all(release: bool) -> void:
	_stop_music()
	_sfx.stop()
	_effects.clear()
	if release:
		for id: int in _loaded_ids:
			_assets.release_audio(id)
		_loaded_ids.clear()


func _discard_finished_effects() -> void:
	if not _sfx.playing:
		_effects.clear()
		return
	var playback: AudioStreamPlaybackPolyphonic = _sfx.get_stream_playback()
	for voice: int in _effects.keys():
		if not playback.is_stream_playing(voice):
			_effects.erase(voice)


func _music_finished() -> void:
	music_id = -1
	_music_preview = false


func _owner_exited(id: int) -> void:
	if _owner_id == id:
		_stop_all(true)
		_owner_id = 0


func _owns(owner: Node) -> bool:
	if owner.get_instance_id() == _owner_id:
		return true
	push_warning("Ignoring audio request from inactive scene: %s" % owner.name)
	return false


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_paused(false)
