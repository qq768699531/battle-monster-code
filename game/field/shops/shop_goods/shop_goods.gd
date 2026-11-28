extends "res://game/field/runtime/item_grid_window/item_grid_window.gd"

## 原生 `Field_Item_Buy_*`（`FieldCanvas` 状态 13）／`Field_Item_Sell_*`（状态 14）共用同一套绘制：
## `Field_Item_Buy_mPaint`／`Field_Item_Sell_mPaint` → `Field_Item_DrawList`。
## 窗口 `Menu_win_Box4_DrawWindow(228, 240, …, side 1, header 16)`，即 (86, 0)：
## - 标题 `msg 71/72`（购买，按 `shop_mode_code` 分道具／装备）、`msg 73/74`（出售）。
## - 列表框 `Menu_Item_DrawList` 左上 `(窗x + 9, 窗y + 52)`、大小 `32 × 6 + 20 = 212` 宽、
##   `32 × 行数 + 15` 高（`#196485` 1 px 圆角框 + 底部 11 px `#0E1B2F` 条）；6 列 × 32 步距，
##   格子左上 `(框x + 4 + 32c, 框y + 3 + 32r)`，格子 30×30。
## - 详情面板 `(窗x + 9, 窗y + 144, 212, 59)`（原生 `Menu_Item_DrawInfoEtc`）。
## - 价格牌 `Field_Item_Buy_DrawPrice` 60×9 在 `(窗x + 158, 210)`、
##   `Field_Item_Sell_DrawPrice` 48×9 在 `(窗x + 170, 210)`，`#024562` 圆角底 + 金币图标。
## - 数量／确认框走 `Field_Item_DrawSelect`（`shop_select.tscn`）。
##
## 货架来源：买页的商品 id 全部来自 `Field_Item_Buy_SetList`（`assets/shops.tres`，
## 由 `script\export_shops.py` 从反编译立即数导出），不在运行时按目录自造；
## 查不到该组／该地图的条目就直接报错而不是回退。原生那时由事件参数填的组（97 号地图）与
## 空货架（`Item_stdSet` 循环 0 次）都照实显示成空列表，原因写在详情行。
##
## 拒绝分支照 `Field_Item_Buy_mKeyPressed` 的消息记录号：单价 ≤ 0 → `msg 80`、
## 钱不够 → `msg 79`、入包失败 → `msg 81`；出售单价 ≤ 0 → `msg 87`。

signal completed   ## 一次成交结束（宿主可刷新 HUD 金钱）

const SlotGrade = preload("res://game/menu/party/slot_grade/slot_grade.gd")

const BUY := 0
const SELL := 1
## `Field_Item_Buy_Get`：道具店（`shop_mode_code` 0）只有 0 号组、装备店（1）1 号组；
## 97 号地图的装备店再追加 3 号组（书）。下标就是 `Field_Item_Buy_SetList` 的实参。
## 其余 `shop_mode_code` 在原生返回 0 组（`v1 = 0`），这里同样返回空表。
static func buy_groups(shop_mode: int, map_id: int) -> Array[int]:
	var groups: Array[int] = []
	if shop_mode == 0:
		groups.append(0)
	elif shop_mode == 1:
		groups.append(1)
		if map_id == 97:
			groups.append(3)
	return groups


## `Field_Item_Sell_Get`：卖页列的是「袋」，道具店 0／2／4、装备店 1／3（与地图无关）。
static func sell_bags(shop_mode: int) -> Array[int]:
	var bags: Array[int] = []
	if shop_mode == 0:
		bags.assign([0, 2, 4])
	elif shop_mode == 1:
		bags.assign([1, 3])
	return bags


## `Field_Item_Buy_SetList` 的货架表（`script\export_shops.py` 从反编译立即数导出）。
const Shops = preload("res://game/field/shops/shop_goods/shops.tres")
const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")
## 原版页签图标：`Menu_winDrawIcon14` 从 `MenuRes.window_ui_resource` 第 14 帧裁 33×30，
## `(33 * 页签号, 30 * (选中 0 / 未选 1))`。页签号就是组号（道具 0、装备 1、书 3）。
const TAB_SHEET := "common/ui_window/frame-014"
## 原版详情面板（`Menu_Item_DrawInfoEtc`／`Equip`）：`item_description.tscn` 就是这份实现
## （标题 `[ 名 X 数量 ]`／品级色、说明箭头、4 行属性、换行说明），菜单道具页与商店共用。
const MenuModel = preload("res://game/menu/screen/menu_model/menu_model.gd")
const PlayerData = preload("res://engine/data/player_data/player_data.gd")

var mode := BUY
var shop_mode_code := 0
## 档位游标（原生 `FieldData+0x20` 的组游标），与 `Field_Item_Buy_Get`／`Field_Item_Sell_Get`
## 的组表下标一一对应；左右键按 `(游标 + 1) % 组数` 循环。
var group_index := 0
## 货架取不到时的原因（`shops.tres` 缺条目／事件参数／目录缺记录）；空串表示正常。
var stock_error := ""
var quantity := 1
## 当前页的「物品栏上限」：卖页取角色 `progress.itemCapacity[袋号]`（原生 `Item_bagList` 的
## `slot_capacity`），买页仍是列表格数。计数与滚动条都按这个上限画，不再写死 18。
var capacity := 0

var _records: Array[ItemDefinition] = []
var _groups: Array[int] = []
var _first := 0
@onready var _detail: Control = $Content/Detail
@onready var _scrollbar: Control = $Content/Scrollbar


func _ready() -> void:
	# 原版买／卖页的装备／道具页签是 3 行 18 格（`Field_Item_DrawList:274-289` 的页签行数表）；
	# 技能书页签 3 才是 2 行。先把可见行数改掉，再连格子信号。
	visible_rows = 3
	cells = COLUMNS * visible_rows
	super()
	for slot in range(cells):
		_cell(slot).pressed.connect(_select_slot.bind(slot))
	$Content/TabHit0.pressed.connect(_select_tab.bind(0))
	$Content/TabHit1.pressed.connect(_select_tab.bind(1))
	$Content/TabHit2.pressed.connect(_select_tab.bind(2))
	$Content/UpHit.pressed.connect(_scroll_row.bind(-1))
	$Content/DownHit.pressed.connect(_scroll_row.bind(1))
	$Select.decided.connect(_decided)
	$Select.cancelled.connect(_cancelled)


func present(story: Object, assets: Node, next_mode: int = BUY, next_shop_mode: int = 0) -> void:
	_story = story
	_assets = assets
	mode = BUY if next_mode == BUY else SELL
	shop_mode_code = 0 if next_shop_mode == 0 else 1
	cursor = 0
	group_index = 0
	_first = 0
	quantity = 1
	notice_id = -1
	stock_error = ""
	_closing = false
	_catalog = assets.load_gameplay_catalog()
	_groups = buy_groups(shop_mode_code, _map_id()) if mode == BUY else sell_bags(shop_mode_code)
	_names.clear()
	for source: String in ["common/item_basic.dat", "common/item_skill.dat"]:
		_names.merge(assets.text_messages(source))
	$Bounds/Title.text = _text(_title_id())
	# 买／卖价格牌的两套原生几何都写在场景：买 60×9 @ (158,210)、卖 48×9 @ (170,210)，
	# 只切可见性，不在代码里改 position／size。
	$Content/BuyPrice.visible = mode == BUY
	$Content/SellPrice.visible = mode != BUY
	_rebuild()
	_refresh_tabs()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if $Select.visible:
		return $Select.handle_key(key)
	if is_transitioning() or _closing:
		return true
	match key:
		"ArrowLeft":
			# 卖页网格与菜单道具页一致：左右移一格，上下移一行；袋（页签）由上方页签点击切换。
			if mode == SELL:
				_move(-1)
			else:
				_horizontal(-1)
		"ArrowRight":
			if mode == SELL:
				_move(1)
			else:
				_horizontal(1)
		"ArrowUp":
			_move(-COLUMNS)
		"ArrowDown":
			_move(COLUMNS)
		"Enter", "Space":
			_open_select()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


func selected_id() -> int:
	return _record().id if _record() != null else -1


## 当前页的档位表（`Field_Item_Buy_Get` 的组号／`Field_Item_Sell_Get` 的袋号）。
func groups() -> Array[int]:
	return _groups.duplicate()


## 当前档位的组号（买页）或袋号（卖页）；没有档位时 −1。
func group_code() -> int:
	return _groups[group_index] if group_index >= 0 and group_index < _groups.size() else -1


## 单笔上限：买受钱与堆叠限制，卖受持有数与堆叠限制；0 表示这一步不能成交。
func max_quantity() -> int:
	var record := _record()
	if record == null:
		return 0
	var stack := ItemKind.max_stack(record.type, record.index)
	if mode == SELL:
		return mini(_owned_count(record.id), stack)
	var unit := StoryRuntime.shop_buy_price(record, 1)
	if unit <= 0:
		return 0
	return mini(money() / unit, stack)


## 原生 `Field_Item_Buy_mKeyPressed`／`Field_Item_Sell_mKeyPressed` 的成交与拒绝分支。
## 返回写进 `notice_id` 的记录号（−1 表示成功）。
func trade(count: int) -> int:
	notice_id = -1
	var record := _record()
	if record == null:
		return -1
	var reason := ""
	if mode == BUY:
		var unit := StoryRuntime.shop_buy_price(record, 1)
		if unit <= 0:
			return _note(Msg.Id.SHOP_CANNOT_BUY)
		if StoryRuntime.shop_buy_price(record, count) > money():
			return _note(Msg.Id.SHOP_NOT_ENOUGH_MONEY)
		reason = _story.buy_item(record.id, count)
		if not reason.is_empty():
			return _note(Msg.Id.SHOP_BAG_FULL)
	else:
		if StoryRuntime.shop_sell_price(record, 1) <= 0:
			return _note(Msg.Id.SHOP_CANNOT_SELL)
		reason = _story.sell_item(record.id, count)
		if not reason.is_empty():
			return _note(Msg.Id.SHOP_CANNOT_SELL)
	var bought_name := _item_name(record) if mode == BUY else ""
	var bought_icon := record.icon
	var bought_grade := record.grade_index
	_rebuild()
	completed.emit()
	# 原生 `Item_stdAddEx` 成功后走 `Game_infoInit` 的「获得道具」栈消息（与捡道具同一套），
	# 不是商店自己的静态提示行。
	if mode == BUY:
		MessageStack.push_item(bought_name, count, bought_icon, bought_grade)
	return -1


func _title_id() -> int:
	if mode == BUY:
		return Msg.Id.SHOP_ITEM_BUY_PAGE if shop_mode_code == 0 else Msg.Id.SHOP_EQUIPMENT_BUY_PAGE
	return Msg.Id.SHOP_ITEM_SELL_PAGE if shop_mode_code == 0 else Msg.Id.SHOP_EQUIPMENT_SELL_PAGE


func _record() -> ItemDefinition:
	return _records[cursor] if cursor >= 0 and cursor < _records.size() else null


## 买页按 `Field_Item_Buy_SetList` 的货架取商品；卖页按 `Field_Item_Sell_Get` 的袋列背包。
func _rebuild() -> void:
	_owned = _inventory_counts()
	quantity = 1
	_records.clear()
	stock_error = ""
	var map_id := _map_id()
	if mode == BUY:
		_load_shelf(map_id)
		capacity = cells
	else:
		_load_bag()
		capacity = _bag_capacity(group_code())
		# 买页保持原生 `Item_stdSet` 的货架顺序；卖页按 id 排（同一袋里 `Item_bagList` 就是这个序）。
		_records.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.id < b.id)
	cursor = clampi(cursor, 0, maxi(0, _records.size() - 1))
	_scroll_to_cursor()
	_refresh()


## 原生 `Field_Item_Buy_init` 一开始就 `SetList(0)`，即第一个档位；左右切档同
## `Field_Item_Buy_mKeyPressed` 的列表子状态 0；卖页同 `Field_Item_Sell_mKeyPressed`。
func _load_shelf(map_id: int) -> void:
	var group := group_code()
	if not Shops.has(group, map_id):
		_fail_stock("shops.tres 缺少 %d 号组（地图 %d）的货架" % [group, map_id])
		return
	var dynamic := Shops.dynamic_source(group, map_id)
	if not dynamic.is_empty():
		# 原生这里按 `ParamData.event_map_npc_count` 逐条 `Item_stdSet`，参数为 0 时循环 0 次；
		# 本工程没有这条剧情通道，所以照实显示空货架，只在详情行说明原因。
		stock_error = "%d 号组货架由事件参数 %s 提供，本工程未建模" % [group, dynamic]
		return
	for item_id: int in Shops.stock(group, map_id):
		var record: ItemDefinition = _catalog.item(item_id)
		if record == null:
			_fail_stock("原道具目录缺少货架上的 %d" % item_id)
			return
		_records.append(record)


## 卖页按当前袋号（`Field_Item_Sell_Get` 的袋表）列这一袋里能卖的东西。
func _load_bag() -> void:
	var bag := group_code()
	for item_id: int in _owned.keys():
		var record: ItemDefinition = _catalog.item(int(item_id))
		if record == null or ItemKind.bag_of(record.type, record.index) != bag:
			continue
		if StoryRuntime.shop_sell_price(record, 1) > 0:
			_records.append(record)


## 货架缺失（组表没登记该组／原道具目录缺记录）时响亮失败：控制台报错 + 详情行显示原因，
## 不回退到任何自造货架。
func _fail_stock(message: String) -> void:
	_records.clear()
	stock_error = message
	push_error("野外商店：" + message)
	# 数据缺失对玩家也是一条要看见的反馈（原生此时会弹信息行），所以同时进提示栈。
	MessageStack.say(message)


func _map_id() -> int:
	return int(_story.progress.get("mapId", -1))


func _bag_capacity(bag: int) -> int:
	return PlayerData.item_capacity(_story.progress, bag)


func _refresh() -> void:
	for slot in range(cells):
		var index := _first + slot
		var cell := _cell(slot)
		var chosen := index == cursor
		# 空位也用普通帧（原生 `a6` 是「在条目范围内」，见 `SlotFrame`）。
		cell.present_frame(SlotFrame.frame_of(cell_frames, true, chosen), chosen)
		cell.set_grade(null)
		var quantity_label: Control = cell.get_node("QuantityNumber")
		quantity_label.hide()
		var icon: Control = cell.get_node("Icon")
		if index >= _records.size():
			icon.texture = null
			continue
		var record: ItemDefinition = _records[index]
		icon.texture = _assets.item_icon(record.icon) if record.icon >= 0 else null
		var owned := _owned_count(record.id)
		if mode == SELL and owned > 1:
			quantity_label.show()
			quantity_label.present(str(owned))
	$Content/Money/Number.present(str(money()))
	$Content/Count.present("%d/%d" % [mini(_records.size(), capacity), capacity])
	var record := _record()
	if record == null:
		_detail.present_item({}, 0, "", "", null, _text)
	else:
		var row := MenuModel.item_row(record)
		row["quantity"] = maxi(1, _owned_count(record.id)) if mode == SELL else 1
		var explanation := MenuModel.native_item_explanation(row, _text)
		_detail.present_item(row, 1 if record.type == ItemKind.Kind.EQUIPMENT else 0, _item_name(record),
			explanation, null, _text)
	var price: Control = $Content/BuyPrice if mode == BUY else $Content/SellPrice
	price.get_node("Number").present(str(_unit_price(record) * maxi(1, quantity)))
	_refresh_scrollbar()


func _detail_text(record: ItemDefinition) -> String:
	if record == null:
		return ""
	var unit := _unit_price(record)
	return ("单价 %d" % unit) if mode == BUY else ("出售价 %d" % unit)


func _unit_price(record: ItemDefinition) -> int:
	if record == null:
		return 0
	return StoryRuntime.shop_buy_price(record, 1) if mode == BUY else \
		StoryRuntime.shop_sell_price(record, 1)


func _index_of(slot: int) -> int:
	return _first + slot


func _select_slot(slot: int) -> void:
	if _closing or is_transitioning() or $Select.visible:
		return
	var index := _index_of(slot)
	if index >= _records.size():
		return
	if index == cursor:
		_open_select()
		return
	cursor = index
	_refresh()


## 原生列表子状态 0 的左右键切档；只有一档时沿用格子内左右移格（`_move`）。
func _horizontal(step: int) -> void:
	if _groups.size() > 1:
		_switch_group(step)
	else:
		_move(step)


## `Field_Item_Buy_mKeyPressed` 的 `-4`／`-3`：`游标 = (游标 + 1) % 组数`／
## `(游标 + 组数 − 1) % 组数`，随后 `Field_Item_Buy_SetList(游标)` 重取货架并把格子光标与滚动清零。
## 卖页的 `-4`／`-3` 是同一公式，只是换的是袋表。
func _switch_group(step: int) -> void:
	group_index = posmod(group_index + step, _groups.size())
	cursor = 0
	_first = 0
	quantity = 1
	notice_id = -1
	_rebuild()
	_refresh_tabs()


## 点页签：原版 `Field_Item_Buy_mKeyPressed` 页签行的 `-5` 是「换到该页并把焦点移进网格」。
func _select_tab(index: int) -> void:
	if _closing or is_transitioning() or index < 0 or index >= _groups.size() or \
			index == group_index:
		return
	group_index = index
	cursor = 0
	_first = 0
	quantity = 1
	notice_id = -1
	_rebuild()
	_refresh_tabs()


## 页签行：组数 1～2，选中行 0 / 未选中行 1；图标从 `ui_window` 第 14 帧切 33×30。
func _refresh_tabs() -> void:
	var sheet: Variant = _assets.load_sprite(TAB_SHEET) if _assets != null else null
	for index in range(3):
		var tab: TextureRect = $Content.get_node("Tab%d" % index)
		var hit: Button = $Content.get_node("TabHit%d" % index)
		var visible_tab: bool = index < _groups.size() and sheet is AtlasTexture
		tab.visible = visible_tab
		hit.visible = visible_tab
		if not visible_tab:
			continue
		var code := _groups[index]
		var row := 0 if index == group_index else 1
		var atlas := AtlasTexture.new()
		atlas.atlas = (sheet as AtlasTexture).atlas
		atlas.region = Rect2(33 * code, 30 * row, 33, 30)
		tab.texture = atlas


func _move(step: int) -> void:
	if _records.is_empty():
		return
	cursor = posmod(cursor + step, _records.size())
	notice_id = -1
	_scroll_to_cursor()
	_refresh()


func _scroll_to_cursor() -> void:
	var row := cursor / COLUMNS
	var first_row := _first / COLUMNS
	if row < first_row:
		first_row = row
	elif row > first_row + visible_rows - 1:
		first_row = row - visible_rows + 1
	var last_row := maxi(0, (_records.size() - 1) / COLUMNS - visible_rows + 1)
	_first = clampi(first_row, 0, last_row) * COLUMNS


func _open_select() -> void:
	if _closing or is_transitioning() or $Select.visible:
		return
	var limit := max_quantity()
	var record := _record()
	if record == null:
		return
	if limit <= 0:
		# 原生在校验单价与余额时就拦下，直接把 `msg 79／80` 显示在详情行。
		trade(1)
		return
	quantity = 1
	var frame: Texture2D = SlotFrame.frame_of(cell_frames, true, false) if not cell_frames.is_empty() else null
	var grade: Variant = SlotGrade.of(int(record.grade_index), false)
	$Select.present(_text(Msg.Id.SHOP_BUY_PROMPT if mode == BUY else Msg.Id.SHOP_SELL_PROMPT),
		_text(Msg.Id.ANSWER_YES), _text(Msg.Id.ANSWER_NO),
		_assets.item_icon(record.icon) if record.icon >= 0 else null, limit,
		ConfirmLayout.ItemSelect.BUY if mode == BUY else ConfirmLayout.ItemSelect.SELL,
		_unit_price(record), frame, grade)


func _decided(count: int) -> void:
	quantity = count
	trade(count)


## 页脚滚动条：`Menu_Item_DrawScroll(x=291, y=56, a3=32*行数-4, 首行, 页数)`。
## 拇指高度 `3*(1-页数) + 轨道`（最小 3），位置按首行在轨道内分页；只有一页时整条隐藏。
func _refresh_scrollbar() -> void:
	var pages := maxi(1, visible_rows)
	if mode == SELL:
		pages = maxi(1, ceili(float(capacity) / float(COLUMNS)))
	var shown := pages > 1
	_scrollbar.visible = shown
	$Content/UpHit.visible = shown
	$Content/DownHit.visible = shown
	if not shown:
		return
	# 滑块几何属于滚动条组件（`scrollbar.set_page`），商店页只给首行与页数，不碰 position／size。
	_scrollbar.call("set_page", _first / COLUMNS, pages)


## 滚动条上/下箭头：原生 `Menu_Item_DrawScroll` 登记 -1／-2；页内就是游标上下移一行。
func _scroll_row(step: int) -> void:
	if _closing or is_transitioning() or $Select.visible:
		return
	_move(step * COLUMNS)


func _cancelled() -> void:
	quantity = 1
	_refresh()
