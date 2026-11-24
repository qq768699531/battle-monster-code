extends RefCounted
## 栏位格底四帧的唯一来源。原生格底只有一份：`Menu_winDrawIcon16` 取 `common/ui_window` 第 16 行
## （`common/ui_window/frame-016`，`JC_fbmDrawCLIP(..., 30 * a3, 0, MenuRes.window_ui_resource, 16, 0, 0)`），
## 帧序 0／1／2／3 = 有内容常态／有内容选中／空位常态／空位选中（帧号公式见 `slot_frame.gd`）。
##
## 切片本身只在 `assets/ui/slot/` 的四个 `.tres` 里做一次（Scene 也能直接 `[ext_resource]` 引用）；
## 本文件只固定这四帧的顺序，给脚本一个数组入口，避免每个页面各切一遍。
const FILLED = preload("res://core/window_frame/slot/filled.tres")
const FILLED_FOCUSED = preload("res://core/window_frame/slot/filled_focused.tres")
const EMPTY = preload("res://core/window_frame/slot/empty.tres")
const EMPTY_FOCUSED = preload("res://core/window_frame/slot/empty_focused.tres")


## 四帧，顺序即 `SlotFrame.Frame`（FILLED／FILLED_FOCUSED／EMPTY／EMPTY_FOCUSED）。
static func frames() -> Array[Texture2D]:
	var ordered: Array[Texture2D] = []
	ordered.assign([FILLED, FILLED_FOCUSED, EMPTY, EMPTY_FOCUSED])
	return ordered
