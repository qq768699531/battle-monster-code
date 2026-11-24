extends RefCounted
## 启动流程（阈值提示、转场）的状态机。

const C = preload("res://scripts/prime/runtime_constants.gd")

## 欢迎页进度条的满格时长（毫秒）：`Prime_NotMem_mPaint@0x6A53C:12,20` 的 `3000`。
## 超过它改画 `Menu_win_Box2_DrawOk@0x4B11C`，`Prime_NotMem_mKeyPressed@0x6ADA0:3` 也在这之后才认确定键。
const PROGRESS_FULL_MS := 3000

var startup_elapsed_ms := 0.0
var storage_check_pending := false


func start(context: RefCounted) -> void:
	context.scene = C.INIT
	context.frame = 0
	context.window_state = 0
	context.modal_state = 0
	startup_elapsed_ms = 0.0
	storage_check_pending = false
	context.boundary_target = -1
	context._interval_ms = 50
	context._accumulated_ms = 0.0
	context._clear_input()


func complete_storage_check(context: RefCounted, error: int) -> void:
	if context.scene != C.NET_DSP or not storage_check_pending:
		push_error("Prime storage result arrived outside the local startup check.")
		return
	storage_check_pending = false
	context.scene = C.LOGO if error == OK else C.NOT_SPACE
	context.frame = 0
	context._interval_ms = 50
	context._accumulated_ms = 0.0
	context._clear_input()
	if error != OK:
		push_error("Prime local save storage check failed: %s" % error_string(error))


## 调试入口（仅验收用）：把 Prime 拉回欢迎页，进度条从 0 重新走一遍。
## 这一页正常启动本来就会经过（见 `run()` 的 INIT 分支与 `Prime_Beta_init@0x6ADD0:3`），
## 这个函数只是省掉重跑整轮启动，便于反复核对 `Menu_win_Box2_DrawPROGRESS@0x4AEF8`
## 的框体、点线与进度条；不进任何正常流程。
func debug_return_to_notice(context: RefCounted) -> void:
	context.scene = C.NOT_MEM
	context.frame = 0
	context.boundary_target = -1
	startup_elapsed_ms = 0.0
	context._interval_ms = 50
	context._accumulated_ms = 0.0
	context._clear_input()


func run(context: RefCounted, effects: Array[Dictionary]) -> bool:
	if context.scene == C.INIT:
		# 原生没有「内存分配失败才进这一页」的分支：`Prime_Init_mRun@0x6ADDC:3` 进状态 1，
		# 状态 1 的 `Prime_Beta_init@0x6ADD0:3` 无条件 `PrimeCanvas_SetNext(2, 0)` 进状态 2
		# （`Prime_NotMem_*`，文案 562／563 是汉化组名单），计时满 3 秒按确定键才进状态 4（NetDsp）。
		# 所以这条跳转保持无条件。
		context.scene = C.NOT_MEM
		startup_elapsed_ms = 0.0
		context._clear_input()
	if context.scene == C.NET_DSP and not storage_check_pending:
		storage_check_pending = true
		effects.append({"kind": "startup-storage-check"})
	if context.scene == C.LOGO:
		if context.frame == 31:
			effects.append({"kind": "audio-request", "resource_id": 152})
		if context.frame > 148:
			effects.append({"kind": "audio-stop-all", "release": true})
			context.scene = C.TITLE
			context._interval_ms = 80
			context.frame = 0
			context._keys.clear()
			effects.append({"kind": "scene-change", "from": C.LOGO, "to": C.TITLE})
			return true
	return false
