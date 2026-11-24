extends RefCounted
## 栏位格底（30×30）的帧号。`Menu_winDrawIcon16` 取 `common/ui_window.fbm` 第 16 行，
## 帧序 0／1 = 在条目范围内的常态／选中（空格也是这两帧），2／3 = 超出范围的空位常态／选中（`Menu_winDrawIcon16` 的
## `JC_fbmDrawCLIP(..., 30 * a3, 0, MenuRes.window_ui_resource, 16, 0, 0)`）。
## 原生只有一条公式 `index = (在范围内 ? 0 : 2) + (选中 ? 1 : 0)`：
## `Menu_Item_DrawItem@0x55238:17-25`（选中 `n3 = 3; if (a6 != 0) n3 = 1`，未选中 `2 * (a6 == 0)`）
## 与 `Menu_Party_DrawBall@0x513E8:13-21`（选中 `a5 != 0 ⇒ 1`／否则 `3`，未选中 `2 * (a5 == 0)`）一致。
##
## **`a6` 不是「有没有道具」，而是「这一格在条目范围内」**：`Menu_Item_DrawList@0x55360:139-155` 先用
## `if (n2 > n3_3)`（格号 < 上限）分岔，范围内不论有无道具都传 `a6 = 1`（普通帧），超出上限才传
## `a6 = 0`（带 X 的空位帧）；`Game_Monster_Enchant_DrawItem@0x43548:32` 对空道具格也直接传 1。

enum Frame {
	IN_RANGE,         ## 帧 0：在条目范围内·常态
	IN_RANGE_FOCUSED, ## 帧 1：在条目范围内·选中
	OUT_OF_RANGE,     ## 帧 2：超出条目范围的空位·常态
	OUT_OF_RANGE_FOCUSED, ## 帧 3：超出条目范围的空位·选中
}

## 选中帧比常态帧后移一帧（`n3 = 3; if (a6 != 0) n3 = 1`：空位 3、有内容 1）。
const FOCUSED_STEP := 1


## 唯一的帧号公式：`(在范围内 ? Frame.IN_RANGE : Frame.OUT_OF_RANGE) + (选中 ? FOCUSED_STEP : 0)`。
static func index(in_range: bool, focused: bool) -> int:
	return (Frame.IN_RANGE if in_range else Frame.OUT_OF_RANGE) + (FOCUSED_STEP if focused else 0)


## 按帧号从四帧表取图；`frames` 的顺序必须是
## IN_RANGE／IN_RANGE_FOCUSED／OUT_OF_RANGE／OUT_OF_RANGE_FOCUSED（见 `SlotFrames.frames()`）。
static func frame_of(frames: Array[Texture2D], in_range: bool, focused: bool) -> Texture2D:
	return frames[index(in_range, focused)]
