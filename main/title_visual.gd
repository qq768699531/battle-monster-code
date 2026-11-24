extends Node2D
## 标题画面：开机 LOGO、标题动画与白闪都在 Scene 的 AnimationPlayer 里，脚本只切状态与绑定数据。

const Runtime = preload("res://prime/prime_title_runtime.gd")
## 标题入场动画的长度：菜单在此之前打开就直接进循环动作。
const TITLE_SETTLED := 1.3
## `obj/title.ani` 的动作号：0 是入场，1 是标题循环，2 是细节循环（动作 1／2 的语义未在
## 反编译代码里单独出现，这里按播放器角色命名）。
const TITLE_LOOP_ACTION := 1
const TITLE_DETAIL_ACTION := 2
const ANI_PLAYERS := ["Logo/ElLogo/AnimationPlayer", "Logo/EnsOny/AnimationPlayer",
	"TitleGroup/Idle/AnimationPlayer", "TitleGroup/Loop/AnimationPlayer",
	"TitleGroup/Detail/AnimationPlayer"]
var _title_sprites: Array[Sprite2D] = []
var _menu_labels: Array[Label] = []
var _menu_text: Array[String] = []
var _title_textures: Array[Texture2D] = []
var _title_flash_texture: Texture2D
var _title_flash_phase := -1
var _capture_viewport: SubViewport
var _captured_background: Texture2D
var _last_title_frame := 17
var _last_title_animation := 0
var _scene := -1
var _menu_open := false
var _playing := ""
var _shown_frame := 0
@onready var _fade_overlay: ColorRect = $Fade
@onready var _title_flash: Node2D = $Flash
@onready var _flash_backing: Control = $Flash/Backing
@onready var _title_flash_sprite: Sprite2D = $Flash/Sprite
@onready var _player: AnimationPlayer = $Player
@onready var _logo: Node2D = $Logo
@onready var _title_group: Node2D = $TitleGroup

func _ready() -> void:
	for item in $Menu.get_children():
		_title_sprites.append(item.get_node("Image"))
		_menu_labels.append(item.get_node("Label"))
	_stop_ani_players()


## 子 ANI 的 AnimationPlayer 自带 autoplay，先停住，等 Scene 动画在指定时刻把它们叫起来。
func _stop_ani_players() -> void:
	for path: String in ANI_PLAYERS:
		(get_node(path) as AnimationPlayer).stop()


func reset() -> void:
	_scene = -1
	_menu_open = false
	_playing = ""
	_shown_frame = 0
	_player.stop()
	_stop_ani_players()
	_logo.hide()
	_title_group.hide()
	for image in _title_sprites: image.hide()
	for label in _menu_labels: label.hide()
	for item in $Menu.get_children(): item.hide()
	_fade_overlay.visible = false
	_title_flash.visible = false
	_title_flash_phase = -1


func present(paint: Dictionary) -> void:
	var scene := int(paint.scene)
	if scene != Runtime.LOGO and scene != Runtime.TITLE:
		if _scene != scene:
			reset()
			_scene = scene
		return
	var menu_open := bool(paint.get("menu_open", false))
	if scene != _scene or menu_open != _menu_open:
		reset()
	_scene = scene
	_menu_open = menu_open
	if scene == Runtime.LOGO:
		_logo.show()
		if _playing != "logo":
			_player.play("logo")
			_playing = "logo"
		return
	_last_title_frame = int(paint.frame)
	_last_title_animation = int(paint.title_animation_frame)
	_title_group.show()
	if _playing != "title" or int(paint.frame) < _shown_frame:
		_player.play("title")
		_playing = "title"
		_shown_frame = int(paint.frame)
	if menu_open:
		_settle_title()
		_fade_overlay.color = Color(0, 0, 0, mini(16 * int(paint.opening_frame), 128) / 256.0)
		_fade_overlay.visible = true
	_render_menu(paint.items)
	_shown_frame = int(paint.frame)


## 菜单提前打开时标题 logo 不再播入场，直接进入循环动作并收掉白闪。
func _settle_title() -> void:
	if _playing == "menu":
		return
	_player.seek(TITLE_SETTLED, true)
	_start_title_loop()
	_playing = "menu"


func _start_title_loop() -> void:
	var loop_player := _title_group.get_node("Loop/AnimationPlayer") as AnimationPlayer
	var detail_player := _title_group.get_node("Detail/AnimationPlayer") as AnimationPlayer
	loop_player.play(AniAction.clip_name(loop_player, TITLE_LOOP_ACTION))
	detail_player.play(AniAction.clip_name(detail_player, TITLE_DETAIL_ACTION))


func release_capture() -> void:
	if _capture_viewport != null:
		_capture_viewport.queue_free()
		_capture_viewport = null
		_captured_background = null


func _capture_title() -> void:
	if _capture_viewport != null:
		_capture_viewport.queue_free()
	_capture_viewport = $CaptureTemplate.duplicate() as SubViewport
	_capture_viewport.world_2d = World2D.new()
	_capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_capture_viewport)
	for group: Node2D in [_logo, _title_group]:
		if not group.visible:
			continue
		var copy := group.duplicate() as Node2D
		_capture_viewport.get_node("Layers").add_child(copy)
		_copy_animation_state(group, copy)
	_captured_background = _capture_viewport.get_texture()
	_freeze_title_capture(_capture_viewport)


## 复制出来的子树要从源节点抄一次动画位置，否则会从 autoplay 的第一帧开始画。
func _copy_animation_state(source: Node, copy: Node) -> void:
	for player: AnimationPlayer in source.find_children("*", "AnimationPlayer", true, false):
		var target := copy.get_node_or_null(source.get_path_to(player)) as AnimationPlayer
		if target == null:
			continue
		if player.current_animation.is_empty():
			target.stop()
			continue
		target.play(player.current_animation)
		target.seek(player.current_animation_position, true)
		target.pause()


func _freeze_title_capture(viewport: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _render_menu(items: Array) -> void:
	_title_flash.visible = false
	_title_flash_phase = -1
	if not _menu_open:
		return
	for item_value: Variant in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var index := int(item.index)
		if index < 0 or index >= _menu_labels.size():
			continue
		var image_index := int(item.image)
		var display := $Menu.get_child(index)
		display.present(item, _menu_text[index], _title_textures[image_index])
		var phase := int(item.get("flash_phase", -1))
		if phase >= 0:
			_title_flash_phase = phase
			_title_flash.position = display.position
			_title_flash.visible = true
			_flash_backing.visible = phase in [1, 2]
			var phase_marker := $Flash/Phases.get_child(phase)
			_flash_backing.position = _title_flash.to_local(phase_marker.get_node("Backing").global_position)
			var texture: Texture2D = _title_flash_texture
			if phase in [0, 3]:
				var crop := AtlasTexture.new()
				crop.atlas = _title_flash_texture
				crop.region = Rect2(8, 0, 20, 21)
				texture = crop
			_title_flash_sprite.texture = texture
			_title_flash_sprite.position = _title_flash.to_local(phase_marker.global_position)
			_title_flash_sprite.flip_h = phase >= 2
			_title_flash_sprite.flip_v = phase >= 2


func menu_regions(selection: int, coordinate_space: Node2D = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range($Menu.get_child_count() - 1, -1, -1):
		var item := $Menu.get_child(index)
		if not item.visible:
			continue
		var rect: Rect2 = item.hit_rect()
		rect.position = (coordinate_space if coordinate_space != null else self).to_local(rect.position)
		result.append({"x": int(rect.position.x), "y": int(rect.position.y),
			"width": int(rect.size.x), "height": int(rect.size.y),
			"key": TouchCode.Key.OK if index == selection else (
				TouchCode.Pad.UP if index < selection else TouchCode.Pad.DOWN),
			"repeats": 1 if index == selection else absi(index - selection)})
	return result
