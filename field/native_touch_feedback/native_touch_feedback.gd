extends CanvasLayer
## 触控按下反馈的共用节拍与状态源。

const LOGICAL_RECT := Rect2(0, 0, 400, 240)
const EFFECT_CAPACITY := 4
const TOUCH_SCENE: PackedScene = preload("res://prime/ui_touch/ui_touch.tscn")
const EFFECT_SCENE = preload("res://field/touch_effect/touch_effect.tscn")

## 基准 50ms；Main 会按速度档位改写（120/100/80/60/50），退出时不再还原。
const DEFAULT_FRAME_INTERVAL_MS := 50

var frame_interval_ms := DEFAULT_FRAME_INTERVAL_MS
var _frames: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _elapsed_ms := 0.0
var _touch_index := -1
## 没有触控落点时的哨兵值（屏幕坐标恒为正）。
const NO_POSITION := Vector2i(-1000, -1000)
var _last_position := NO_POSITION


func _ready() -> void:
	var probe := TOUCH_SCENE.instantiate()
	add_child(probe)
	var player: AnimationPlayer = probe.get_node("AnimationPlayer")
	var clip := AniAction.clip_name(player, 0)
	var animation := player.get_animation(clip)
	if animation == null or int(animation.get_meta("frame_count")) != 5:
		push_error("Native touch animation has invalid frame data.")
		probe.queue_free()
		return
	for index in range(5):
		player.play(clip)
		player.seek(index * animation.step, true)
		var layer: Sprite2D = probe.get_node("Layer000")
		if layer.texture == null:
			push_error("Native touch animation frame %d is unresolved." % index)
			probe.queue_free()
			return
		var material := layer.material as ShaderMaterial
		if material == null:
			push_error("Native touch animation has an unsupported blend mode.")
			probe.queue_free()
			return
		# Scene 的原点已经烘进图层变换，取反即原「精灵原点 + 图层偏移」。
		_frames.append({"texture": layer.texture,
			"origin": -layer.transform.origin,
			"mode": int(material.get_shader_parameter("native_mode"))})
	probe.queue_free()


func _input(event: InputEvent) -> void:
	if _frames.size() != 5:
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if event.index == _touch_index:
				_touch_index = -1
				_last_position = NO_POSITION
		elif _touch_index == -1:
			_touch_index = event.index
			_accept_position(event.position, false)
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_accept_position(event.position, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed:
			_accept_position(event.position, false)
		else:
			_last_position = NO_POSITION
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_accept_position(event.position, true)


func _accept_position(viewport_position: Vector2, dragging: bool) -> void:
	var point := Vector2i(transform.affine_inverse() * viewport_position)
	if dragging and absi(point.x - _last_position.x) <= 7 and \
			absi(point.y - _last_position.y) <= 7:
		return
	_last_position = point
	if not LOGICAL_RECT.has_point(Vector2(point)):
		return
	for effect: Dictionary in _effects:
		for sprite: Sprite2D in effect.sprites:
			sprite.hide()
		for copy: BackBufferCopy in effect.copies:
			copy.hide()
	if _effects.size() == EFFECT_CAPACITY:
		var oldest: Dictionary = _effects.pop_front()
		oldest.node.queue_free()
	var effect := EFFECT_SCENE.instantiate()
	$Effects.add_child(effect)
	_effects.append({"position": Vector2(point), "frame": 0,
		"sprites": effect.sprites, "copies": effect.copies, "node": effect})
	_elapsed_ms = 0.0
	_draw_native_frame()


func _process(delta: float) -> void:
	if _effects.is_empty() or _effects.back().frame > _frames.size():
		return
	_elapsed_ms += delta * 1000.0
	while _elapsed_ms >= frame_interval_ms:
		_elapsed_ms -= frame_interval_ms
		_draw_native_frame()


func _draw_native_frame() -> void:
	var effect: Dictionary = _effects.back()
	if effect.frame >= _frames.size():
		for sprite: Sprite2D in effect.sprites:
			sprite.hide()
		for copy: BackBufferCopy in effect.copies:
			copy.hide()
		effect.frame = _frames.size() + 1
		return
	# 0x3A7D4 reloads the same ring index for all four draws, not four different slots.
	for index in range(effect.sprites.size()):
		var sprite: Sprite2D = effect.sprites[index]
		var copy: BackBufferCopy = effect.copies[index]
		if effect.frame >= _frames.size():
			sprite.hide()
			copy.hide()
			continue
		var frame: Dictionary = _frames[effect.frame]
		sprite.texture = frame.texture
		sprite.position = effect.position + sprite.texture.get_size() / 2.0 - frame.origin
		(sprite.material as ShaderMaterial).set_shader_parameter("native_mode", frame.mode)
		copy.show()
		sprite.show()
		effect.frame += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		_last_position = NO_POSITION
		for effect: Dictionary in _effects:
			effect.node.queue_free()
		_effects.clear()
		_elapsed_ms = 0.0
