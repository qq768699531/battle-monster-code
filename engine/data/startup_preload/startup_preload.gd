extends RefCounted
## 启动预载：把「第一次进入才解码」的场景与音频提前加载，消掉战斗入场、图鉴翻页、换图、
## 技能首次播放、菜单首次打开时的首次触发卡顿（条目 bm-P2-323）。
##
## 两种装载方式，按组选（实测见 `wiki\ui\startup-preload.md`）：
## - **线程化**（`THREADED_GROUPS`／`BACKGROUND_GROUPS`）：解码在工作线程，主线程只做状态查询与
##   提交，实测最坏一帧 4.3 ms。同步 `load()` 全量 `monsters/` 要 35420 ms／346 个、
##   `actors/` 6197 ms／49 个，必须走线程。
## - **主线程分帧**（`PACED_GROUPS`）：`field/map_set` 的地形场景要建 `TileMapLayer`＋`TileSet`，
##   在工作线程里慢 15–25 倍（274 个文件：主线程 1187 ms，单请求线程化 36700 ms），而且多张地图
##   并发线程化会各自加载同一份 `TileSet`，实测报
##   `Another resource is loaded from path … (possible cyclic resource inclusion)` 并偶发崩溃
##   （0xC0000005，`_commit_finished` 里 `load_threaded_get`）。所以这一组留在主线程、每帧固定几个。
##
## 线程化的并发数是关键：只挂一个请求时每个资源至少占一帧（855 项 × 16.7 ms ≈ 14 s 下限），
## 纯粹的 UI/ANI 组在 1／8／16 个并发下差别很大，`MAX_IN_FLIGHT` 取 8。
##
## 两档：`*_WELCOME_GROUPS` 是欢迎页（原生状态 2 `Prime_NotMem_*`）期间走完的档，进度条只反映它；
## `BACKGROUND_GROUPS` 是欢迎页之后继续后台走的档，不占用户时间。

## 清单按目录扫描，扩展名不带点（与 `String.get_extension()` 的返回形态一致）。
const SCENE_EXTENSION := "tscn"
const RESOURCE_EXTENSION := "tres"
const AUDIO_STREAM_EXTENSION := "ogg"

## 同时在飞的线程化请求数（实测依据见文件头）。
const MAX_IN_FLIGHT := 8
## 主线程分帧组每帧装几个：地图场景主线程实测 4–8 ms 一个，3 个约 12–24 ms，仍在欢迎页
## （静态画面＋进度条）的可接受范围内。
const MAIN_THREAD_LOADS_PER_FRAME := 3
## 单个线程化请求的看门狗（毫秒）：超过就丢下不管、清单继续走。实测
## `res://battle/field/field.tscn` 单独线程化请求会在 74.9% 自锁；正常启动它已被
## `prime/entry/entry.gd` 的 preload 链缓存、走不到这里，这条是兜底。
const REQUEST_TIMEOUT_MS := 8000

## 共用界面组件：`7fac0bd` 取消 `ui/` 分类后组件按使用方归档，其中 `battle/`、`menu/`、`field/`
## 已由各自的分组覆盖，这一组只负责 `core/`。
const GROUP_COMPONENTS := "res://engine"
## 启动与标题 ANI：`d7d61df` 之后入口是根目录 `main.tscn`，展示与标题模块都在 `prime/`。
const GROUP_ANI := "res://prime"
const GROUP_AUDIO := "res://audio/ogg"
const GROUP_BATTLE_UI := "res://battle"
const GROUP_MENU := "res://menu"
const GROUP_FIELD := "res://game/field"
const GROUP_MAPS := "res://game/field/map/map_set"
const GROUP_ACTORS := "res://actors"
const GROUP_MONSTERS := "res://monsters"

## 第一档线程化部分（欢迎页期间走完，进度条反映它）：共用组件、开场 ANI、音乐、战斗 UI、
## 菜单、野外。顺序即优先级。
const THREADED_WELCOME_GROUPS := [
	GROUP_COMPONENTS,
	GROUP_ANI,
	GROUP_AUDIO,
	GROUP_BATTLE_UI,
	GROUP_MENU,
	GROUP_FIELD,
]

## 第一档主线程分帧部分：地形与地图（含 125 份 `TileSet`，由地形场景带进来）。
const PACED_WELCOME_GROUPS := [
	GROUP_MAPS,
]

## 第二档（欢迎页之后继续后台走，不占用户时间）：角色与怪物 ANI。
## 怪物 ANI 不能从清单里删——图鉴翻页与技能首次播放靠它。
const BACKGROUND_GROUPS := [
	GROUP_ACTORS,
	GROUP_MONSTERS,
]

var _roots := PackedStringArray()
var _paths := PackedStringArray()
## 已装载的资源必须**留着强引用**：Godot 的资源缓存只是弱引用，取回后立刻丢掉引用的话资源会被释放、
## 缓存条目一起消失，等于没预载。实测（`ResourceLoader.has_cached`）不保留时地图／ANI／音频全部 false。
var _retained: Array[Resource] = []
var _threaded_welcome_total := 0
var _welcome_total := 0
var _index := 0
var _finished := 0
var _welcome_finished := 0
var _inflight := PackedStringArray()
var _progress: Dictionary = {}
var _issue_index: Dictionary = {}
var _requested_ms: Dictionary = {}
var _planned := false


## 清单顺序（测试与 `wiki\ui\startup-preload.md` 的回归点：首组是共用 UI 组件，末组是怪物 ANI）。
func roots() -> PackedStringArray:
	_build()
	return _roots


func total() -> int:
	_build()
	return _paths.size()


func finished_count() -> int:
	_build()
	return _finished


func is_finished() -> bool:
	_build()
	return _finished >= _paths.size()


## 欢迎页进度条的进度（0–1）：只算第一档，第一档走完后恒为 1.0。
## 第二档在欢迎页之后才走，不反馈给进度条（否则进度条会停在三成左右，看起来像卡住）。
func ratio() -> float:
	_build()
	if _welcome_total == 0:
		return 1.0
	var in_flight := 0.0
	for path in _inflight:
		if int(_issue_index[path]) < _threaded_welcome_total:
			in_flight += clampf(float(_progress[path][0]), 0.0, 1.0)
	return clampf((_welcome_finished + in_flight) / float(_welcome_total), 0.0, 1.0)


## 每帧调一次：补满在飞的线程化请求、轮询提交，然后按预算在主线程装分帧组。
## 请求的 `use_sub_threads` 取 false：既然已经挂 `MAX_IN_FLIGHT` 个并发请求，再开子线程没有收益
## （全量完成 6029 ms vs 5948 ms），但会在强制终止时报几十到上百个 `ObjectDB` 泄漏实例（见 doc）。
func advance() -> void:
	_build()
	_request_more()
	_commit_finished()
	_load_paced()


func _request_more() -> void:
	while _inflight.size() < MAX_IN_FLIGHT and _index < _threaded_welcome_total:
		var path := _paths[_index]
		_issue_index[path] = _index
		_index += 1
		if ResourceLoader.has_cached(path):
			_count_done(path)
			continue
		var error := ResourceLoader.load_threaded_request(path, "", false)
		if error != OK:
			push_error("Startup preload request failed for %s: %s" % [path, error_string(error)])
			_count_done(path)
			continue
		_inflight.append(path)
		_progress[path] = [0.0]
		_requested_ms[path] = Time.get_ticks_msec()


func _commit_finished() -> void:
	for slot in range(_inflight.size() - 1, -1, -1):
		var path := _inflight[slot]
		var status := ResourceLoader.load_threaded_get_status(path, _progress[path])
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if Time.get_ticks_msec() - int(_requested_ms[path]) <= REQUEST_TIMEOUT_MS:
				continue
			# 自锁的请求取不回来（`load_threaded_get` 会一直等），只能丢掉、清单继续走。
			push_error("Startup preload timed out for %s." % path)
			_drop(path, slot)
			continue
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("Startup preload failed for %s (status %d)." % [path, status])
		# 成功要取回资源并留住强引用，否则缓存条目随对象一起消失（见 `_retained`）；
		# 失败也要取一次，把请求从加载器里清掉。
		_retain(ResourceLoader.load_threaded_get(path))
		_drop(path, slot)


## 线程化那一档全部提交完，才开始主线程分帧那一档：避免主线程 `load()` 与工作线程同时读同一份
## 地形／图集（缓存里同路径并发装载是实测会崩的那种组合）。
func _load_paced() -> void:
	if _finished < _threaded_welcome_total:
		return
	var limit := mini(_index + MAIN_THREAD_LOADS_PER_FRAME, _welcome_total)
	while _index < limit:
		var path := _paths[_index]
		_issue_index[path] = _index
		_index += 1
		_retain(load(path))
		_count_done(path)
	if _index >= _welcome_total:
		_request_background()


func _request_background() -> void:
	while _inflight.size() < MAX_IN_FLIGHT and _index < _paths.size():
		var path := _paths[_index]
		_issue_index[path] = _index
		_index += 1
		if ResourceLoader.has_cached(path):
			_count_done(path)
			continue
		var error := ResourceLoader.load_threaded_request(path, "", false)
		if error != OK:
			push_error("Startup preload request failed for %s: %s" % [path, error_string(error)])
			_count_done(path)
			continue
		_inflight.append(path)
		_progress[path] = [0.0]
		_requested_ms[path] = Time.get_ticks_msec()


func _drop(path: String, slot: int) -> void:
	_inflight.remove_at(slot)
	_progress.erase(path)
	_requested_ms.erase(path)
	_count_done(path)


## 留住强引用（`_retained` 的说明见字段定义）；空资源（加载失败）不入表。
func _retain(resource: Resource) -> void:
	if resource != null:
		_retained.append(resource)


## 退出时放掉强引用：强制终止（`--quit-after`）不会走资源缓存回收，留着会报 ObjectDB 泄漏。
func release() -> void:
	_retained.clear()
	_inflight.clear()


func _count_done(path: String) -> void:
	if int(_issue_index[path]) < _welcome_total:
		_welcome_finished += 1
	_finished += 1
	_issue_index.erase(path)


## 扫描扩展到目录里。音频只扫流文件，地图目录同时扫地形场景与资源；其余目录只扫场景。
static func _extensions_of(root: String) -> PackedStringArray:
	match root:
		GROUP_AUDIO:
			return PackedStringArray([AUDIO_STREAM_EXTENSION])
		GROUP_MAPS:
			return PackedStringArray([SCENE_EXTENSION, RESOURCE_EXTENSION])
		_:
			return PackedStringArray([SCENE_EXTENSION])


func _build() -> void:
	if _planned:
		return
	_planned = true
	for root in THREADED_WELCOME_GROUPS:
		_append_group(root)
	_threaded_welcome_total = _paths.size()
	for root in PACED_WELCOME_GROUPS:
		_append_group(root)
	_welcome_total = _paths.size()
	for root in BACKGROUND_GROUPS:
		_append_group(root)


func _append_group(root: String) -> void:
	_roots.append(root)
	var found := PackedStringArray()
	_collect(root, _extensions_of(root), found)
	# 排序保证清单确定：`DirAccess` 的枚举顺序不保证稳定。
	found.sort()
	_paths.append_array(found)


func _collect(root: String, extensions: PackedStringArray, found: PackedStringArray) -> void:
	if DirAccess.open(root) == null:
		push_error("Startup preload directory is missing: %s" % root)
		return
	for file_name in DirAccess.get_files_at(root):
		if extensions.has(file_name.get_extension()):
			found.append(root.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(root):
		_collect(root.path_join(directory_name), extensions, found)
