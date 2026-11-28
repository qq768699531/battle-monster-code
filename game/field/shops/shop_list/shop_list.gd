extends "res://game/field/runtime/list_menu_window/list_menu_window.gd"

## 原生 `Field_Item_List_*`（`FieldCanvas` 状态 12）：
## `Field_Item_List_init`（条数 2、开窗计数置 1）／`mRun`（关窗计数到 −4 回
## `FIELD_STATE_BASIC`）／`mKeyPressed`（−1／−2 循环移游标、−5 按游标进
## `ITEM_BUY`／`ITEM_SELL`／`ITEM_FOOD`、−16 关窗）／`mPaint` → `Game_Menu_List_Draw`。
##
## 窗口 `Menu_win_Box4_DrawWindow(228, 208, …, side 1, header 16)` 即 (86, 16)；标题按
## `shop_mode_code` 取 `msg 62`（道具商店）／`63`（装备商店），行 118×20 取 `msg 64/65`
## （道具商店）或 `66/67`（装备商店）、`x = 窗x + 55`。**行距按条数算**
## （`(208 − 36) / (条数 + 1)`）：2 行 ⇒ 57、首行顶 `y = 窗y + 10 + 57 = 83`，即 83／140；
## 3 行 ⇒ 43、69／112／155。未选中框 `#196485` + 同色字、选中框 `#7AD0FA` + 白字。
##
## `Field_Item_List_init` 的条数在**地图 148 且 `shop_mode_code == 0`** 时是 3（多一行
## `msg 70` 食物制作），否则 2；`mKeyPressed` 的 −5 按游标进 BUY／SELL／**ITEM_FOOD**
## （状态 15），而 `Field_Item_Food_mRun` 关窗后回 `SetNext(ITEM_LIST, 2)`——参数 2 就是
## 「光标停在第三行」。所以本页只管发 `food_requested`，切页与回位由宿主接。
##
## 持有金钱在原生该页不画，移植按需求补在窗口下部（`Field_Item_DrawList` 的金钱条同款组件）。

signal completed       ## 商店里成交过一次（宿主可刷新 HUD）
signal food_requested  ## 第三行（食物制作）确认：宿主切到食物制作页，本页保持打开

const ITEM_ENTRIES := [Msg.Id.SHOP_BUY_ITEM, Msg.Id.SHOP_SELL_ITEM]
const FOOD_ENTRY := Msg.Id.SHOP_FOOD
const EQUIPMENT_ENTRIES := [Msg.Id.SHOP_BUY_EQUIPMENT, Msg.Id.SHOP_SELL_EQUIPMENT]
## 原生 `Field_Item_List_init` 的三行特判：只有 148 号地图的道具商店有「食物制作」。
const FOOD_SHOP_MAP := 148
const MAX_ROWS := 3
## 行在窗口里的位置：`x = 窗x + 55`、`y = 窗y + 10 + (208 − 36) / (条数 + 1) × (序号 + 1)`。
const ROW_OFFSET_X := 55
const ROW_OFFSET_Y := 10
const ROW_SIZE := Vector2i(118, 20)

var shop_mode_code := 0
## 当前页的行（`present()` 按 `shop_mode_code` + 地图号算，见 `_entries()`）。
var entries: Array = []

var _story: Object


func _ready() -> void:
	super()
	for index in range(MAX_ROWS):
		_card(index).pressed.connect(_select.bind(index))
	$Content/AcceptHit.pressed.connect(_confirm)
	$Content/BackHit.pressed.connect(close)
	$Goods.closed.connect(_close_goods)
	$Goods.completed.connect(func() -> void: completed.emit())


## `shop_mode_code` 来自 NPC 记录第 18 字节的交互码：3（装备店）→ 1、6（道具店）→ 0，
## 见 `Evt_chtMENU` 的两处 `ItemData.shop_mode_code` 赋值。
##
## `position` 是宿主从食物制作页回来时的落位（原生 `SetNext(ITEM_LIST, 2)` 的 2 = 第三行），
## 默认 0 保持原有两行商店的行为。
func present(story: Object, assets: Node, next_shop_mode: int = 0,
		position: int = 0) -> void:
	_story = story
	_assets = assets
	shop_mode_code = 0 if next_shop_mode == 0 else 1
	entries = _entries()
	cursor = clampi(position, 0, maxi(0, entries.size() - 1))
	_closing = false
	$Goods.hide()
	$Bounds.visible = true
	$Content.visible = true
	$Bounds/Title.text = assets.text_message(Msg.SOURCE,
		Msg.Id.SHOP_ITEMS_TITLE if shop_mode_code == 0 else Msg.Id.SHOP_EQUIPMENT_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	_layout()
	_render()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if $Goods.visible:
		return $Goods.handle_key(key)
	if is_transitioning() or _closing:
		return true
	match key:
		"ArrowUp":
			_move(-1)
		"ArrowDown":
			_move(1)
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


func money() -> int:
	var parameter: Variant = _story.progress.get("parameter", {})
	return int(parameter.get("moneyBalance", 0)) if parameter is Dictionary else 0


func row_messages() -> Array:
	return entries


## 原生确认直接 `SetNext(13 / 14 / 15)`，不播关窗；新页自己重播开窗动画。
## 第三行是食物制作：原生切到状态 15，本页保持打开、由宿主接 `food_requested` 切页。
func _confirm() -> void:
	if not _accepts_input() or entries.is_empty():
		return
	if entries[cursor] == FOOD_ENTRY:
		food_requested.emit()
		return
	_open_goods(cursor)


func _open_goods(mode: int) -> void:
	# 原生 `SetNext(ITEM_BUY／SELL)` 是换页：列表页整页不再画，所以连 `Content` 一起收起，
	# 否则行卡片与页脚 OK／CLR 的命中区会留在买页下面（可见或可点）。
	$Bounds.visible = false
	$Content.visible = false
	$Goods.present(_story, _assets, mode, shop_mode_code)


func _close_goods() -> void:
	$Goods.hide()
	$Bounds.visible = true
	$Content.visible = true
	_render()


## 行内容与条数：装备店恒 2 行；道具店只有 148 号地图多一行「食物制作」。
##
## 地图号取 `story.map`（`ResourceCatalog.load_map@0x…` 返回的 `{"id": map_id, …}`，
## 与 `field_runtime` 里 `story.map.get("id", -1)` 同源）。取不到地图号时**不能默默当 2 行**——
## 那会把 148 号地图的三行商店画少一行——所以直接报错并且一行都不摆。
func _entries() -> Array:
	if shop_mode_code == 1:
		return EQUIPMENT_ENTRIES
	var map_id: Variant = _story.map.get("id") if _story.map is Dictionary else null
	if not map_id is int:
		push_error("野外商店：story.map 没有地图号，无法判断是否有「食物制作」行")
		return []
	if int(map_id) == FOOD_SHOP_MAP:
		return ITEM_ENTRIES + [FOOD_ENTRY]
	return ITEM_ENTRIES


## `(208 − 36) / (条数 + 1)`：2 行 ⇒ 57（83／140）、3 行 ⇒ 43（69／112／155）。
## `Content` 已设 `content_follows_window`，所以这里的偏移是**相对窗口左上角**的（原生 `rect.x + 55`）。
func _layout() -> void:
	var spacing := (window_size.y - 36) / (entries.size() + 1) if not entries.is_empty() else 0
	for index in range(MAX_ROWS):
		var card := _card(index)
		card.visible = index < entries.size()
		if not card.visible:
			continue
		card.offset_left = ROW_OFFSET_X
		card.offset_right = ROW_OFFSET_X + ROW_SIZE.x
		card.offset_top = ROW_OFFSET_Y + spacing * (index + 1)
		card.offset_bottom = card.offset_top + ROW_SIZE.y


## 行绘制走 `list_menu_window`，本页只补窗口下部的金钱条。
func _render() -> void:
	super()
	$Content/Money.present(money())
