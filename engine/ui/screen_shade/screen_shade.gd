class_name ScreenShade
extends ColorRect
## 屏幕「半透明 + 模糊」层。生命周期只由 `WindowTransition` 统一管理：
## 只要还有一扇窗口显示，这一层就可见；最后一扇窗口收起时它才消失。
##
## 原生 `Field_Basic_Capture`／`Battle_info_Capture` 在第一扇窗口打开前把整帧画面写进
## `MapRes.map_scratch_image`，之后所有窗口层（含嵌套窗口）每帧 `Map_Copy()` 都拷同一张；
## 因此快照由 `WindowTransition` 在第一扇窗口打开时抓取并共享，本脚本只负责显示这张快照。

## 逻辑分辨率 400×240（显示 800×480 的 2 倍）。原生 FillBLUR 在 400×240 缓存上按整像素取点，
## 放大后步长仍是 1 个逻辑像素。
const LOGICAL_SIZE := Vector2i(400, 240)

## 定格快照：窗口存在期间只保留一张，最后一扇窗口收起时释放。
var _snapshot: ImageTexture


func _ready() -> void:
	_apply_pixel_step()
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_snapshot = null
		_apply_snapshot()


## 由 `WindowTransition` 在第一扇窗口打开时设置；之后所有窗口共用同一张。
func set_snapshot(image: Image) -> void:
	_snapshot = ImageTexture.create_from_image(image) \
		if image != null and not image.is_empty() else null
	_apply_snapshot()


func snapshot() -> ImageTexture:
	return _snapshot


func _apply_snapshot() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	if _snapshot == null:
		shader_material.set_shader_parameter("frozen", false)
		return
	shader_material.set_shader_parameter("snapshot", _snapshot)
	shader_material.set_shader_parameter("frozen", true)


func _apply_pixel_step() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("pixel_step",
		Vector2(1.0 / LOGICAL_SIZE.x, 1.0 / LOGICAL_SIZE.y))
