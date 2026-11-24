extends Node2D
## 野外全屏特效层（原生 `Map_eft*` 一族）。
##
## 原生 `Map_eftDRAW` 每次都用当前的绘制组模式整屏填充，槽 1 还会让
## `Map_Proc` 跳掉地图绘制；本层固定在 `World/MapView` 之后、`Actors` 之前，
## 所以黑场盖住地块、角色照常画在上面（与原生分开缓冲一致）。
## 档位与颜色在 `scripts\data\map_effect.gd`，5 帧爬坡轨道在 `map_effect.tscn`；
## 这里只负责「切哪一档、播哪段、播完回报」。

signal settled(effect_id: int)

const Catalog = preload("res://data/map_effect/map_effect.gd")

@onready var _blend: ColorRect = $Blend
@onready var _player: AnimationPlayer = $AnimationPlayer

var _tier := Catalog.Kind.BLANK
var _effect_id := -1


func _ready() -> void:
	_player.animation_finished.connect(_on_animation_finished)
	_apply(Catalog.blank())


## 套用一个 `map-effect` 场景效果。静态档位立刻生效并回报完成；分级档位播完
## 5 帧爬坡（`Map_eftPROC` 逐帧推进）后才落到终态并回报完成。
func present(effect: Dictionary) -> void:
	_tier = int(effect.get("tier", Catalog.Kind.BLANK))
	_effect_id = int(effect.get("id", -1))
	_player.stop()
	if Catalog.is_graded(_tier):
		_blend.visible = true
		_set_blend(Catalog.ramp_blend(_tier))
		_player.play(Catalog.grade_clip(_tier))
		return
	_apply(Catalog.static_state(_tier))
	settled.emit(_effect_id)


func clear() -> void:
	_tier = Catalog.Kind.BLANK
	_effect_id = -1
	_player.stop()
	_apply(Catalog.blank())


func _on_animation_finished(name: StringName) -> void:
	if not Catalog.is_graded(_tier) or String(name) != Catalog.grade_clip(_tier):
		return
	var state := Catalog.target_state(_tier)
	_tier = int(state["tier"])
	_apply(state)
	settled.emit(_effect_id)


func _apply(state: Dictionary) -> void:
	_blend.visible = int(state["tier"]) != Catalog.Kind.BLANK
	_set_blend(int(state["blend"]))
	_set_tint(int(state["color"]))


func _set_blend(mode: int) -> void:
	(_blend.material as ShaderMaterial).set_shader_parameter("mode", mode)


func _set_tint(rgb: int) -> void:
	(_blend.material as ShaderMaterial).set_shader_parameter("tint", Color(
		float((rgb >> 16) & 255) / 255.0, float((rgb >> 8) & 255) / 255.0,
		float(rgb & 255) / 255.0))
