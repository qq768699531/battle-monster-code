extends "res://scripts/components/window_transition.gd"

## 野外服务页的共用关页生命周期。
##
## 原生这一族页各有自己的 `mKeyPressed` −16 分支与 `mRun` 相位 −4 收尾
## （`Field_Guild_List`／`Field_Item_List`／`Field_Item_Buy`／`Game_Monster_List` 等），
## 但三件事处处相同：关页只进一次、收拢动画播完才算关完、关完由宿主摘页（`closed`）。
## 所以本页只留三条路径：
## - `close()`：同一帧只走一次，`_closing` 同时是各页输入处理的前置守卫；
## - `_begin_close()`：默认播收拢动画（`Menu_win_Box4` 相位 −1…−4），原生瞬时关页的页覆盖成
##   `_finish_close()`；
## - `_on_window_finished()`：`transition_finished(false)` 后隐藏本页、复位标志并发 `closed`。

signal closed

## 关页已开始（也是输入处理的前置守卫）。
var _closing := false


func _ready() -> void:
	super()
	transition_finished.connect(_on_window_finished)


## 关页入口（原生 −16／CLR）。
func close() -> void:
	if _closing:
		return
	_closing = true
	_begin_close()


func closing() -> bool:
	return _closing


## 开始关页：播收拢动画，播完才走 `_on_window_finished(false)`。
func _begin_close() -> void:
	close_window()


## 收拢播完：`opened`（开窗结束）什么也不做；关窗走稳态收尾。
## 需要额外复位（提示行等）的页覆盖后先做自己的复位再 `super(opened)`。
func _on_window_finished(opened: bool) -> void:
	if opened:
		return
	_finish_close()


## 关页稳态：隐藏本页、复位标志、通知宿主摘页（瞬时关页也走这一条）。
func _finish_close() -> void:
	hide()
	_closing = false
	closed.emit()
