extends Node2D
## 标题画面：开机 LOGO、标题动画与白闪都在 Scene 的 AnimationPlayer 里，脚本只切状态与绑定数据。

const Runtime = preload("res://game/prime/title/prime_title_runtime/prime_title_runtime.gd")
## 子 ANI 的 AnimationPlayer 自带 autoplay，先停住，等 Scene 动画在指定时刻把它们叫起来。
const ANI_PLAYERS := ["Logo/ElLogo/AnimationPlayer", "Logo/EnsOny/AnimationPlayer",
	"TitleGroup/Loop/AnimationPlayer", "TitleGroup/Detail/AnimationPlayer"]
## 原生 `Prime_Title_Draw` 的动作 1/2 从 `run_counter+5` 帧起画；这里用动作 1 的稳定帧
## （1.1 s，脸部完整、眼部红光已亮）作为循环起点，避免动作 1 开头几帧的暗帧/半张脸。
const TITLE_LOOP_SETTLE := 1.1
var _title_sprites: Array[Sprite2D] = []
var _menu_labels: Array[Label] = []
var _menu_text: Array[String] = []
var _title_textures: Array[Texture2D] = []
var _capture_viewport: SubViewport
var _captured_background: Texture2D
var _last_title_frame := 17
var _last_title_animation := 0
var _scene := -1
var _menu_open := false
var _playing := ""
var _shown_frame := 0
## 菜单打开过的压黑一旦触发就不再取消（标题页回退/重进仍保持 50% 半透明）。
var _menu_dimmed := false
@onready var _fade_overlay: ColorRect = $Fade
@onready var _menu_dim: ColorRect = $MenuDim
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
	$MenuDim.hide()
	_fade_overlay.visible = false


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
	if menu_open:
		_menu_dimmed = true
	if scene == Runtime.LOGO:
		_logo.show()
		if _playing != "logo":
			_player.play("logo")
			_playing = "logo"
		return
	_last_title_frame = int(paint.frame)
	_last_title_animation = int(paint.title_animation_frame)
	_title_group.show()
	# 入场（菜单未开）和菜单打开后的循环／压黑都走 Scene 里的动画：`title` / `menu_open`。
	var animation := "menu_open" if menu_open else "title"
	if _playing != animation or (animation == "title" and int(paint.frame) < _shown_frame):
		_player.play(animation)
		_playing = animation
		_shown_frame = int(paint.frame)
	_render_menu(paint.items)
	_shown_frame = int(paint.frame)
	# 半透明压黑：菜单一点开就是 50%，之后一直保持（不随菜单关闭/重进被取消）。
	if _menu_dimmed:
		_menu_dim.visible = true
		_menu_dim.color = Color(0, 0, 0, 0.5)


## 入场动作 0 播完、闪光结束后（或菜单打开时）进入动作 1/2：动作 1 从稳定帧开始，
## 动作 2（logo）从第 0 帧开始；两者都是原生 `Prime_Title_Draw` 的那两条动作。
func _enter_title_loop() -> void:
	var loop_player: AnimationPlayer = _title_group.get_node("Loop/AnimationPlayer")
	loop_player.play("action_001")
	loop_player.seek(TITLE_LOOP_SETTLE, true)
	var detail_player: AnimationPlayer = _title_group.get_node("Detail/AnimationPlayer")
	detail_player.play("action_002")


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
	if not _menu_open:
		return
	for item_value: Variant in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var index := int(item.index)
		if index < 0 or index >= _menu_labels.size():
			continue
		var display := $Menu.get_child(index)
		display.present(item, _menu_text[index], _title_textures[int(item.image)])


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
