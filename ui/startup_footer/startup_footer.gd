extends Control
## 启动页页脚（确认/返回）。

const StartupRuntime = preload("res://prime/startup_runtime/startup_runtime.gd")


func present(elapsed: int, loading: bool, label: String, load_ratio: float) -> void:
	$Progress.visible = loading
	$Choice.visible = not loading
	$Choice.present(label, true)
	# 原生 `Menu_win_Box2_DrawPROGRESS@0x4AEF8:77`：已填充宽 = 轨道宽 × 计时 / 3000。
	# 再把真实预载进度当上限（`wiki\ui\startup-preload.md`）：进度条既按原生的 3000 ms 节奏走，
	# 也不会跑在真实加载前面。
	var paced_ratio := float(elapsed) / StartupRuntime.PROGRESS_FULL_MS
	$Progress/Fill.size.x = floorf($Progress/Track.size.x * minf(paced_ratio, load_ratio))
