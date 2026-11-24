extends Node2D
## ANI 场景的展示封装：按 identity/动作/朝向播放分层 Sprite2D。
## 动画库按 identity 只读共享，禁止逐实例改写。

signal animation_finished

const SCENE_ROOT := "res://monsters/"
const GRAYSCALE_SHADER := preload("res://shaders/ani_brightness.gdshader")

# 每个场景只报一次「未实现的混合模式」，避免刷屏。
static var _reported_blends: Dictionary = {}
# 已清掉 resource_local_to_scene 的 PackedScene。
static var _normalized_scenes: Dictionary = {}
# identity → 场景自带的动画库。清理 local_to_scene 后它就是共享只读的，
# 多个实例共用同一份，不再逐实例深拷贝。
static var _scene_libraries: Dictionary = {}
# identity → 全部动作改为 LOOP_NONE 的副本，只有非循环播放的调用方用得到。
static var _non_looping_libraries: Dictionary = {}
# identity → {动作号: 片段名}。片段名形如 `action_003_attack`，语义后缀由
# `script\ani_actions.py` 按原生映射生成；解析只看前三位数字，未命名的动作照样能取到。
static var _clip_names: Dictionary = {}
# identity → {动作号: 帧数}。原生 `Battle_Monster_resLOAD` 一次读出该物种的动作表并常驻，
# 这里同样只读 PackedScene 自己的 `libraries` 状态（`_normalize_scene` 用的就是这一份），
# 不实例化、不 free，所以每场战斗不再按「物种 × 动作」反复扫帧数。
static var _frame_counts: Dictionary = {}

var last_error := ""
var _identity := ""
var _direction := 0
var _action := -1
var _looped := true
var _running := true
var _player: AnimationPlayer
var _source_materials: Dictionary = {}
var _clip_loops: Dictionary = {}
var _gray_materials: Dictionary = {}
var _grayscale := false
var _manual := false


# 旧导出（编辑器保存过）的 ANI 场景给每个 Animation 标了 resource_local_to_scene，
# 使每次 instantiate 都深拷贝整份动画库（obj_f_99 有 80 个动作，单次约 128ms）；
# 当前生成器不再产出该标志。动画库按 identity 只读共享、不再逐实例改动，因此可以
# 安全清掉它；每个 PackedScene 只处理一次。
static func _normalize_scene(packed: PackedScene) -> void:
	if _normalized_scenes.has(packed):
		return
	_normalized_scenes[packed] = true
	var state := packed.get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) != &"libraries":
				continue
			var libraries: Variant = state.get_node_property_value(node, property)
			if not libraries is Dictionary:
				continue
			for key: Variant in libraries:
				var library: Variant = libraries[key]
				if not library is AnimationLibrary:
					continue
				for clip in (library as AnimationLibrary).get_animation_list():
					(library as AnimationLibrary).get_animation(clip).resource_local_to_scene = false


static func scene_path(identity: String) -> String:
	var folder := "monsters/" if identity.begins_with("mon") or \
		identity in ["obj/b_effect", "obj/b_icon2"] else "actors/"
	return "res://" + folder + identity + "/" + identity.get_file() + ".tscn"


## 预读 identity 的 ANI 场景并清掉 `resource_local_to_scene`（见 `_normalize_scene`）。
## 未预读时该场景的**首次** `instantiate()` 会深拷贝整份动画库，而战斗侧
## `battle_view._load_action` 按「物种 × 动作」各实例化一次，所以一场战斗里每只没读过的
## 物种都要付多份深拷贝（实测 6 只的首次开战 ≈0.8 s，预读后 ≈20 ms）。
static func warm(identity: String) -> void:
	var path := scene_path(identity)
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed != null:
		_normalize_scene(packed)
		frame_counts(identity)


## identity 的动作号 → 帧数（只收帧数 >0 的动作）。首次调用从场景状态读，之后命中
## 静态缓存；场景不存在时返回空字典，由调用方决定是否当作错误。
static func frame_counts(identity: String) -> Dictionary:
	if not _frame_counts.has(identity):
		_frame_counts[identity] = _read_frame_counts(identity)
	return _frame_counts[identity]


static func _read_frame_counts(identity: String) -> Dictionary:
	var counts := {}
	var path := scene_path(identity)
	if not ResourceLoader.exists(path):
		return counts
	var packed := load(path) as PackedScene
	if packed == null:
		return counts
	var state := packed.get_state()
	for node in range(state.get_node_count()):
		for property in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) != &"libraries":
				continue
			var libraries: Variant = state.get_node_property_value(node, property)
			if not libraries is Dictionary:
				continue
			for key: Variant in libraries:
				var library: Variant = libraries[key]
				if not library is AnimationLibrary:
					continue
				for clip: StringName in (library as AnimationLibrary).get_animation_list():
					var action := AniAction.action_of_clip(clip)
					if action < 0 or counts.has(action):
						continue
					var count := int((library as AnimationLibrary).get_animation(clip).get_meta("frame_count", 0))
					if count > 0:
						counts[action] = count
	return counts


static func battle_identity(species: int) -> String:
	var normal := "mon2/m_b_%03d_1" % (species % 1000)
	var awakened := "mon2/m_b_%03d_2" % (species % 1000)
	# Battle_Monster_resLOAD retries the base resource when the awakened ANI is absent.
	return awakened if species > 999 and ResourceLoader.exists(
		SCENE_ROOT + awakened + "/" + awakened.get_file() + ".tscn") else normal


## 动作号 → 当前 identity 的片段名；这个 identity 没有该动作时返回空名。
func _clip(action: int) -> StringName:
	return _clip_names.get(_identity, {}).get(action, &"")


func _ready() -> void:
	add_to_group("monster_animation")
	visibility_changed.connect(_sync_active)
	_sync_active()


## 把 identity 的指定动作摆到当前帧并播放。
## 只有身份变化才重建 ANI 场景树；朝向、动作、循环标志的变化都复用已有节点。
## fallback 对应原生 Object_drawBASIC 在请求动作无帧时回退到默认动作的行为。
func present(identity: String, action: int = 0, direction: int = 0, looped: bool = true,
		preserve_phase: bool = false, fallback: int = -1) -> bool:
	last_error = ""
	if identity != _identity or _player == null:
		if not _enter_scene(identity, looped):
			return false
	elif looped != _looped:
		_attach_library(identity, looped)
	_direction = direction
	# Object_drawSPRITE 的镜像位：只翻转内容容器，不重建实例也不重播动作。
	$Content.scale.x = -1.0 if direction == BattleSide.Code.PLAYER else 1.0
	if frame_count(action) == 0 and fallback >= 0:
		action = fallback if frame_count(fallback) > 0 else 0
	var name := _clip(action)
	if name == &"" or frame_count(action) == 0:
		return _fail("Monster scene has no nonempty action %d: %s" % [action, identity])
	if action == _action and looped == _looped:
		return true
	var phase := 0.0
	if preserve_phase and _action >= 0:
		phase = _player.current_animation_position / _player.current_animation_length
	_action = action
	_looped = looped
	_player.play(name)
	_player.advance(0.0)
	if preserve_phase:
		_player.seek(phase * _player.current_animation_length, true)
	return true


# 按 identity 重建 ANI 场景树，并挂上只读共享的动画库。
func _enter_scene(identity: String, looped: bool) -> bool:
	clear()
	var path := scene_path(identity)
	var packed := load(path) as PackedScene
	if packed == null:
		return _fail("Monster scene is unavailable: " + path)
	_normalize_scene(packed)
	var scene := packed.instantiate() as Node2D
	$Content.add_child(scene)
	_player = scene.get_node("AnimationPlayer")
	_player.animation_finished.connect(func(_name: StringName): animation_finished.emit())
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL \
		if _manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_attach_library(identity, looped)
	_identity = identity
	for mode: int in scene.get_meta("unapplied_blend_modes", []):
		var warning_key := "%s:%d" % [identity, mode]
		if not _reported_blends.has(warning_key):
			_reported_blends[warning_key] = true
			push_warning("ANI special blend mode %d remains unapplied: %s." % [mode, identity])
	# 记录各层原始材质，供 set_grayscale 切回原样。
	for node in scene.get_children():
		if node is Sprite2D:
			_source_materials[node] = node.material
	_sync_active()
	return true


func clear() -> void:
	for node in $Content.get_children():
		$Content.remove_child(node)
		node.free()
	_player = null
	_action = -1
	_source_materials.clear()
	_clip_loops.clear()
	_gray_materials.clear()
	# 新场景的材质是原件，灰度状态必须重新从关开始。
	_grayscale = false


# 循环播放直接用场景自带库（共享只读）；不循环时才取按 identity 缓存的 LOOP_NONE 变体。
# 注意：共享库不可被任何实例改写，否则会污染同 identity 的其他实例。
func _attach_library(identity: String, looped: bool) -> void:
	if not _scene_libraries.has(identity):
		_scene_libraries[identity] = _player.get_animation_library(&"")
	var target: AnimationLibrary = _scene_libraries[identity]
	if not _clip_names.has(identity):
		var names := {}
		for clip: StringName in target.get_animation_list():
			var index := AniAction.action_of_clip(clip)
			if index >= 0:
				names[index] = clip
		_clip_names[identity] = names
	if not looped:
		if not _non_looping_libraries.has(identity):
			var copy := target.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as AnimationLibrary
			for clip in copy.get_animation_list():
				copy.get_animation(clip).loop_mode = Animation.LOOP_NONE
			_non_looping_libraries[identity] = copy
		target = _non_looping_libraries[identity]
	if _player.get_animation_library(&"") != target:
		_player.remove_animation_library(&"")
		_player.add_animation_library(&"", target)
	_clip_loops.clear()
	for clip_name in _player.get_animation_list():
		_clip_loops[clip_name] = _player.get_animation(clip_name).loop_mode


func frame_count(action: int) -> int:
	var name := _clip(action)
	return int(_player.get_animation(name).get_meta("frame_count")) if _player.has_animation(name) else 0


func bounds() -> Rect2:
	var rectangle: Rect2 = _player.get_animation(_clip(_action)).get_meta("bounds")
	return $Content.transform * rectangle


func set_running(value: bool, reset_pose: bool = false) -> void:
	_running = value
	if reset_pose and _player != null and _player.current_animation_position != 0.0:
		_player.seek(0.0, true)
	_sync_active()


func set_manual(value: bool) -> void:
	_manual = value
	if _player != null:
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL \
			if value else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


func advance(delta: float) -> void:
	if _player != null and _running and is_visible_in_tree():
		_player.advance(delta)


## 按实际位移推进步态。只有走跑片段声明了 cycle_distance；待机与剧情动作没有步态，
## 位移照常由调用方处理，这里不推进动画（原生 Field_Hero_procMOVE 同款前提）。
func advance_motion(distance: float) -> void:
	if _player == null or _action < 0:
		return
	var clip := _player.get_animation(_clip(_action))
	if clip == null or not clip.has_meta("cycle_distance"):
		return
	var cycle := float(clip.get_meta("cycle_distance"))
	if cycle <= 0.0:
		return
	_player.advance(distance / cycle * clip.length)


# 原生按当前帧可见图层绘制：眨眼等叠加层只在特定帧出现，隐藏层不参与渲染。
func visible_sprites() -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	if _player == null:
		return result
	for node in _player.get_parent().get_children():
		if node is Sprite2D and node.visible:
			result.append(node)
	return result


func frame_index() -> int:
	if _player == null:
		return 0
	if _player.get_parent().has_meta("frame_index"):
		return int(_player.get_parent().get_meta("frame_index"))
	return mini(floori(_player.current_animation_position / _player.current_animation_length *
		frame_count(_action)), frame_count(_action) - 1)


func seek_frame(frame: int) -> void:
	_player.seek(float(frame) / frame_count(_action) * _player.current_animation_length, true)


func restart() -> void:
	_player.stop()
	_player.play(_clip(_action))
	_player.advance(0.0)


func _sync_active() -> void:
	if _player != null:
		_player.active = _running and is_visible_in_tree()


func set_grayscale(value: bool) -> void:
	if value == _grayscale:
		return
	_grayscale = value
	for sprite: Sprite2D in _source_materials:
		if value and not _gray_materials.has(sprite):
			var source: ShaderMaterial = _source_materials[sprite]
			var material := source.duplicate() as ShaderMaterial if source != null else ShaderMaterial.new()
			material.shader = source.shader if source != null else GRAYSCALE_SHADER
			material.set_shader_parameter("grayscale", true)
			_gray_materials[sprite] = material
		sprite.material = _gray_materials[sprite] if value else _source_materials[sprite]


func playback_state() -> Dictionary:
	return {"identity": _identity, "direction": _direction, "action": _action,
		"looped": _looped, "time": _player.current_animation_position} if _player != null else {}


func restore_playback(state: Dictionary) -> bool:
	if state.is_empty():
		return true
	if not present(state.identity, state.action, state.direction, state.looped):
		return false
	_player.seek(float(state.time), true)
	var gray := _grayscale
	_grayscale = false
	set_grayscale(gray)
	return true


func _fail(message: String) -> bool:
	clear()
	last_error = message
	push_error(message)
	return false

