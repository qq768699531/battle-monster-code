extends "res://tests/unit/gut_case.gd"

const Scene = preload("res://game/field/dialogue/chat_view/chat_view.tscn")


## 立绘淡入是场景动画（`enter` 剪辑），位置与透明度必须线性插值，否则就是 5 档跳变。
func test_entry_clip_is_linear() -> void:
	var view: Control = Scene.instantiate()
	add_child_autofree(view)
	var player: AnimationPlayer = view.get_node("PortraitEntry")
	var clip: Animation = player.get_animation(&"enter")
	assert_eq(clip.track_get_interpolation_type(2), Animation.INTERPOLATION_LINEAR, "透明度播放入场用线性")
	assert_eq(clip.track_get_interpolation_type(1), Animation.INTERPOLATION_LINEAR, "位移也线性")
	var layers: Node2D = view.get_node("PortraitLayers")
	player.play(&"enter")
	player.advance(0.16)
	var middle := layers.modulate.a
	player.advance(0.16)
	assert_true(middle > 0.05 and middle < 0.95, "中段透明度在 0–1 之间（%f）" % middle)
	assert_almost_eq(layers.modulate.a, 1.0, 0.01, "播完不透明")


## 淡出同样是场景动画：`exit` 把透明度从 1 拉到 0，并把立绘往左挪 16px。
func test_exit_clip_fades_out() -> void:
	var view: Control = Scene.instantiate()
	add_child_autofree(view)
	var player: AnimationPlayer = view.get_node("PortraitEntry")
	var clip: Animation = player.get_animation(&"exit")
	assert_not_null(clip, "有 exit 剪辑")
	var layers: Node2D = view.get_node("PortraitLayers")
	var offset: Node2D = view.get_node("PortraitEntryOffset")
	player.play(&"enter")
	player.advance(1.0)
	player.play(&"exit")
	player.advance(0.1)
	assert_true(layers.modulate.a < 0.9, "中段已经在变透明（%f）" % layers.modulate.a)
	player.advance(0.2)
	assert_almost_eq(layers.modulate.a, 0.0, 0.02, "播完完全透明")
	assert_almost_eq(offset.position.x, -16.0, 0.5, "同时向左退 16px")
