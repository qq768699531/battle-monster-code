extends RefCounted

## Box2 确认框／消息框的窗高：`Menu_win_Box2_DrawSelect`／`DrawOk`／`DrawMessage` 三个绘制入口
## 共用的唯一实现。
##
## 三个函数都是「先用 `JC_fntGetPage(&page_, &text_slot_, width − 16, 2, 1)` 把正文按可用宽度折成
## `page_.page_count` 页，再把 `13 × page_count + 固定留白 = n16` 当窗口高交给
## `Menu_win_Box2_DrawWindow`」，差别只在固定留白与 `n11`（有无标题）。所以高度公式只在本文件出现
## 一次，各页只传自己的窗宽与实际折行数（折行由 `Layout.wrap_text` 用同一个 10px 点阵字体算出）。
##
## 用法：`const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")`，
## 再 `window_size = ConfirmLayout.select_size(160, lines.size())`。

## 每行 13 px：`Menu_win_Box2_DrawSelect@0x4B630:44` 的 `13 * page_.page_count`
## （`Menu_win_Box2_DrawMessage@0x4B918:24`、`Menu_win_Box2_DrawOk@0x4B11C:39` 同）。
const LINE_STEP := 13
## 正文左右留白：三个绘制入口都用 `JC_fntGetPage(&page_, &text_slot_, width − 16, 2, 1)`
## 折行（`Menu_win_Box2_DrawSelect@0x4B630:41`、`Menu_win_Box2_DrawMessage@0x4B918:22`）。
const WRAP_INSET := 16
## 正文到点线／确认键那一段的固定留白：`Menu_win_Box2_DrawSelect@0x4B630:44` 的 `+ 33`。
const BODY_PADDING := 33
## 无标题时的 `n11`：`Menu_win_Box2_DrawSelect@0x4B630:42-43`（标题参数为 nullptr 或空串 → `n11 = 11`）。
const PLAIN_ROWS := 11
## 有标题文本时的 `n11`：`Menu_win_Box2_DrawSelect@0x4B630:42` 的 `n11 = 29`。
const TITLE_ROWS := 29
## 纯消息窗（无点线、无确认键）的固定留白：`Menu_win_Box2_DrawMessage@0x4B918:24` 的 `+ 18`。
const MESSAGE_PADDING := 18
## 正文相对窗口左上角的位置：三个绘制入口都画在 `(窗x + 8, 窗y + 11)`
## （`Menu_win_Box2_DrawSelect@0x4B630:52-54`、`Menu_win_Box2_DrawMessage@0x4B918:34-35`、
## `Menu_win_Box2_DrawOk@0x4B11C:49-50`）。
const TEXT_INSET := Vector2i(8, 11)
## 按实测正文宽撑开窗宽时的上限：逻辑屏宽 400（`prime/layout.gd` 的 Box4／Box2 居中基准）
## 减去正文左右各一份窗内留白（`TEXT_INSET.x`），撑开后窗框仍不贴屏幕边缘。
const FIT_MAX_WIDTH := 400 - 2 * TEXT_INSET.x
## 点线从窗口左端 + 4 起、长 `宽度 − 8`
## （`Menu_win_Box2_DrawSelect@0x4B630:63-65`、`Menu_win_Box2_DrawOk@0x4B11C:65-74`）。
const RULE_INSET := 4
## 正文末行 → 点线、点线 → 按键的两段间隔都是 5 px
## （`Menu_win_Box2_DrawSelect@0x4B630:47`、`Menu_win_Box2_DrawOk@0x4B11C:65`／`:78`）。
const RULE_GAP := 5
## 点线高度 1 px（`Menu_win_Box2_DrawOk@0x4B11C:74` 的 1 px 亮线）。
const RULE_HEIGHT := 1
## 确认键尺寸 44×16（`Menu_win_Box2_DrawSelect@0x4B630:60`、`Menu_win_Box2_DrawOk@0x4B11C:79-80`）。
const CHOICE_SIZE := Vector2i(44, 16)
## `Field_Item_DrawSelect:118-133` 的 `n2`：0 丢弃、1 买、2 卖。
enum ItemSelect { DISCARD = 0, BUY = 1, SELL = 2 }
## `Field_Item_DrawSelect:60-62` 的常量表（`C.54.10866 + 4 * (n2 + 20)`，二进制实测
## 0x98A30+80..104 = 48／60／60／2／3／3／2）：丢弃 48、买／卖 60（比丢弃多 12 px 价格行）。
## 窗口高再加 `BODY_PADDING`（+33）：丢弃 81、买／卖 93。
const ITEM_SELECT_BODY := [48, 60, 60]
## 价格行高：买／卖比丢弃多出的那 12 px（`Field_Item_DrawSelect:121-126` 的 `y_2 + 44`）。
const ITEM_SELECT_PRICE_ROW := 12
## 正文顶：丢弃 `y_2 + 32`、买／卖 `y_2 + 44`（`Field_Item_DrawSelect:117-133`）。
const ITEM_SELECT_TEXT_TOP := 38
## 点线顶：正文顶 + 15（`Field_Item_DrawSelect:139`）；确认键顶再 + 5（`:165-169`）。
const ITEM_SELECT_RULE_TOP := 53
const ITEM_SELECT_CHOICE_TOP := 58
## 价格牌 48×9 摆在 `(窗x + 93, 窗y + 37)`（`Field_Item_DrawSelect:121/125` 的 `p_x - 63 + n239`）。
const ITEM_SELECT_PRICE_PLATE := Rect2i(93, 37, 48, 9)


## `Menu_win_Box2_DrawSelect@0x4B630:41-44`（`Menu_win_Box2_DrawOk@0x4B11C:36-39` 逐字相同）：
## 高 = `13 × 折行数 + 33 + n11`，`n11` 有标题 29、无标题 11。
static func select_size(width: int, lines: int, with_title := false) -> Vector2i:
	var extra := TITLE_ROWS if with_title else PLAIN_ROWS
	return Vector2i(width, LINE_STEP * lines + BODY_PADDING + extra)


## `Menu_win_Box2_DrawMessage@0x4B918:22-24`：高 = `13 × 折行数 + 18`（没有点线与按键区）。
static func message_size(width: int, lines: int) -> Vector2i:
	return Vector2i(width, LINE_STEP * lines + MESSAGE_PADDING)


## `Menu_win_Box2_DrawOk@0x4B11C`：与 `DrawSelect` 同一个公式；本工程各页的标题参数都是 `nullptr`，
## 所以等价于 `select_size(width, lines)` 的无标题形态。
static func ok_size(width: int, lines: int) -> Vector2i:
	return select_size(width, lines, false)


## `Field_Item_DrawSelect:60-62`：`n42 = 表[n2] + 33`，窗口高只由 `n2` 定，与正文折行无关。
static func item_select_size(width: int, kind: int) -> Vector2i:
	return Vector2i(width, ITEM_SELECT_BODY[kind] + BODY_PADDING)
