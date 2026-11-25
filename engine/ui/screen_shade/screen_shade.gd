class_name ScreenShade
extends ColorRect
## 屏幕「半透明 + 模糊」的唯一一层（原生 `Field_Basic_Capture`／
## `Battle_info_Capture` 里的 `JC_grpFillBLUR`）。
##
## 原生只在开窗那一刻把画面写进 `MapRes.map_scratch_image` 并模糊一次，之后所有窗口层与
## 嵌套窗口（`Map_Copy`）都画同一张快照——所以整棵树最多只能有一层可见：
## `show_shade()` 会收起同组其它层，`acquire()` 已经有可见层时直接复用、不再新建。
##
## 材质、模糊 shader 与铺满全屏的锚点都在 `screen_shade.tscn` 里，脚本只做状态与像素步长。
##
## 「静止 + 模糊 + 半透明」是同一张快照上的三件事：原生 `Field_Basic_Capture`／
## `Battle_info_Capture` 在开窗前把画面写进 `MapRes.map_scratch_image`（先用
## `JC_grpSetMODE(GRP_MODE_ALPHA, 128)` 盖半透明黑，再 `JC_grpFillBLUR` 模糊一次），
## 之后各窗口层每帧 `Map_Copy()` 都拷这同一张，所以背景是定格的。`acquire_frozen()` 按这个
## 时机抓一次 viewport 快照并让 shader 只采样它；战斗捕获等其余用法继续采样实时屏幕。

const GROUP := &"screen_shade"
## 逻辑分辨率 400×240（显示 800×480 的 2 倍）。原生 FillBLUR 在 400×240 缓存上按整像素取点，
## 放大后步长仍是 1 个逻辑像素。
const LOGICAL_SIZE := Vector2i(400, 240)
## 场景按路径读，避免 `screen_shade.tscn` 与本脚本互相 preload 成环。
const SCENE_PATH := "res://engine/ui/screen_shade/screen_shade.tscn"

## 定格快照：本层可见期内只抓一次（原生一次 `Field_Basic_Capture` 之后全部 `Map_Copy()`）。
var _snapshot: ImageTexture
## 本层是否属于「以快照为背景」的窗层：请求之后每个可见期开始都抓一次。
var _freeze_requested := false


func _ready() -> void:
	add_to_group(GROUP)
	_apply_pixel_step()
	visibility_changed.connect(_on_visibility_changed)
	_capture_if_pending()


## 变成可见的那一层把同组其它层收起：后出现的那一层接管背景，画面里永远只有一层。
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		show_shade()
		_capture_if_pending()
	else:
		# 可见期结束（关窗）：快照作废，同一层下次被复用时重抓一次，免得还画着上一段背景。
		_snapshot = null
		_apply_snapshot()


## 让本层成为整棵树唯一可见的一层。
func show_shade() -> void:
	for other: ScreenShade in shades(self):
		if other != self:
			other.hide()
	show()


## 开窗前取「唯一的一层」：`host` 自己已有层就复用（每个宿主最多一层，关窗后父节点 `hide()` 会让它
## 一起不可见，再开窗必须复用同一个，否则反复开关会不断往 `host` 下挂新层）；`host` 没有自己的层时
## 复用树上其它可见层（例如菜单整体那一层，从任务页开图时世界地图不再叠第二层）；都没有才在 `host`
## 最底层建一层，压在本窗口的框与正文之下。
static func acquire(host: Node) -> ScreenShade:
	var owned := host_shade(host)
	if owned != null:
		owned.show_shade()
		return owned
	var current := visible_shade(host)
	if current != null:
		return current
	var shade: ScreenShade = load(SCENE_PATH).instantiate()
	host.add_child(shade)
	host.move_child(shade, 0)
	shade.show_shade()
	return shade


## 开窗前取「唯一的一层」并把当前画面定格：原生 `Field_Basic_Capture` 在窗口出现之前抓一次
## `MapRes.map_scratch_image`，世界地图（`Menu_world_Draw`）与野外 HUD 的 MAP 键都走这一条。
static func acquire_frozen(host: Node) -> ScreenShade:
	var shade := acquire(host)
	shade.freeze()
	return shade


## 把当前已画完的那一帧抓成快照并让 shader 只采样它。已有快照的层不再重抓——从任务页开出
## 世界地图时复用的就是菜单那一层、那一张（原生 `Map_Copy()` 每帧拷的是同一张 scratch）。
func freeze() -> void:
	_freeze_requested = true
	if _snapshot != null:
		_apply_snapshot()
		return
	_capture_if_pending()


## 抓的必须是「本层还没画上去」的那一帧：可见的第一刻读回的是上一帧，里面既没有本层也没有宿主窗。
func _capture_if_pending() -> void:
	if not _freeze_requested or _snapshot != null or not is_visible_in_tree():
		return
	_snapshot = _grab_viewport()
	_apply_snapshot()


func snapshot() -> ImageTexture:
	return _snapshot


## 用调用方已经抓好的一帧替换快照。开窗脚本在 `show()` 之前读回上一帧完整画面，
## 这样不会把「本层刚可见、场景还没重新绘制」的空帧或半帧冻进背景（树木等
## `z_index` 较高的地图物件会因此消失）。
func set_snapshot(image: Image) -> void:
	_freeze_requested = true
	_snapshot = ImageTexture.create_from_image(image) \
		if image != null and not image.is_empty() else null
	_apply_snapshot()


func _grab_viewport() -> ImageTexture:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var image := viewport.get_texture().get_image()
	# 首帧还没画完时读回是空图，保持实时采样，等下一次可见再抓。
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _apply_snapshot() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	if _snapshot == null:
		shader_material.set_shader_parameter("frozen", false)
		return
	shader_material.set_shader_parameter("snapshot", _snapshot)
	shader_material.set_shader_parameter("frozen", true)


## `host` 自己挂的层，不看可见性：关窗后它跟着父节点一起不可见，`visible_shade()` 找不到。
static func host_shade(host: Node) -> ScreenShade:
	for child in host.get_children():
		var shade := child as ScreenShade
		if shade != null:
			return shade
	return null


static func visible_shade(from: Node) -> ScreenShade:
	for shade: ScreenShade in shades(from):
		if shade.is_visible_in_tree():
			return shade
	return null


static func shades(from: Node) -> Array[ScreenShade]:
	var found: Array[ScreenShade] = []
	if from == null or not from.is_inside_tree():
		return found
	for node in from.get_tree().get_nodes_in_group(GROUP):
		var shade := node as ScreenShade
		if shade != null:
			found.append(shade)
	return found


func _apply_pixel_step() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("pixel_step",
		Vector2(1.0 / LOGICAL_SIZE.x, 1.0 / LOGICAL_SIZE.y))
