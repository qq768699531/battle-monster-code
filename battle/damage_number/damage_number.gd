extends Control
## 原生命中伤害数字：`Param_dmgNUMBER` 在受击怪物处新建 kind 14 对象并播 ANI 40／41
## （`obj/b_effect.ani` 里这两条动作各 10 帧、无图层，只用来计时）。数字本身由
## `Param_activeDraw` 从 `obj/b_number.fbm` 逐位绘制：
## 受击 ANI 41 按 `occlusion_fade_steps` 取普通 0–9／暴击 10–19，治疗 ANI 40 取 20–29，
## 数值不大于 0 时改画 30–32 的 MISS。逐位定位见 `Param_activeNumber`：
## 每位以帧内 `(宽/2, 高/2)` 为中心绘制，落点为 `(槽位中心, 基准 y - 上升量)`。

## 原生图集每帧一个独立文件，数字组固定为 0／10／20，MISS 固定 30–32。
const SPRITE_IDENTITY := "obj/b_number/frame-%03d"
const GROUP_OFFSET := {&"damage": 0, &"critical": 10, &"heal": 20}
const MISS_FRAMES: Array[int] = [30, 31, 32, 32]
## `n12 = 6 * (group & 1) + 12`：暴击组步距 18，普通／治疗组 12。
const ADVANCE := 12
const CRITICAL_ADVANCE := 18
## `Param_activeNumber` 的逐帧上升量，第 4 帧起固定 48。
const RISE: Array[int] = [39, 52, 46, 48]

static var _frames_cache: Array[Texture2D] = []

@onready var _digits: Node2D = $Digits
@onready var _player: AnimationPlayer = $AnimationPlayer

## 最近一次显示的数值与分档，供回归断言使用。
var value := 0
var kind: StringName = &"damage"
var digit_count := 0


func present(at: Vector2, amount: int, display_kind: StringName = &"damage") -> void:
	value = maxi(0, amount)
	kind = display_kind
	var frames := _frames_for(display_kind, value)
	digit_count = frames.size()
	var advance := CRITICAL_ADVANCE if kind == &"critical" else ADVANCE
	var start := -((advance * digit_count) >> 1)
	while _digits.get_child_count() < digit_count:
		var glyph := Sprite2D.new()
		glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_digits.add_child(glyph)
	for index in range(_digits.get_child_count()):
		var glyph: Sprite2D = _digits.get_child(index)
		glyph.texture = _frame_texture(frames[index]) if index < digit_count else null
		glyph.position.x = start + advance * index
	position = at
	visible = true
	_advance_digits(0)
	_player.stop()
	_player.play(&"damage")
	_player.advance(0.0)


func _ready() -> void:
	_player.animation_finished.connect(func(_name: StringName): visible = false)
	visible = false


func _process(_delta: float) -> void:
	if _player.is_playing():
		var clip := _player.get_animation(&"damage")
		_advance_digits(int(_player.current_animation_position / clip.step))


## 原生逐位错开出场：第 i 位在 `frame_index >= i` 之后才画，且各自从自己的第 0 帧开始上升。
func _advance_digits(age: int) -> void:
	var clip := _player.get_animation(&"damage")
	var played := mini(age, int(clip.get_meta("frame_count")) - 1)
	for index in range(_digits.get_child_count()):
		var glyph: Sprite2D = _digits.get_child(index)
		var local := played - index
		glyph.visible = index < digit_count and local >= 0
		if glyph.visible:
			glyph.position.y = -RISE[mini(local, RISE.size() - 1)]


func _frames_for(display_kind: StringName, amount: int) -> Array[int]:
	if amount <= 0 or display_kind == &"miss":
		return MISS_FRAMES
	var frames: Array[int] = []
	var base: int = GROUP_OFFSET.get(display_kind, 0)
	for character in str(amount):
		frames.append(base + character.unicode_at(0) - 48)
	return frames


func _frame_texture(frame: int) -> Texture2D:
	if _frames_cache.is_empty():
		for index in 33:
			_frames_cache.append(AssetCatalog.load_sprite(SPRITE_IDENTITY % index))
	return _frames_cache[frame]
