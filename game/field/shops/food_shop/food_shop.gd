extends "res://game/field/runtime/item_grid_window/item_grid_window.gd"

## 原生 `Field_Item_Food_*`（`FieldCanvas` 状态 15）：**食物制作**。
## 流程只有「选一份食谱 → 扣三种材料 + 100 金币 → 产品 +1 进背包」，
## 没有选目标怪物、没有喂食、也没有成功提示——见 `Field_Item_Food_Proc`。
##
## `Field_Item_Food_init`：`Item_foodCount()`（`item_food.dat` 的 38 个组）逐个
## `Item_stdSet(&inventory_display_items[n], 27, n, 1)`；`Item_datBasic` 的 case 27 要求
## 「food 组 n 有记录」且「basic 第 1 组 index n 有记录」才返回 1，所以只有带食谱的组进列表，
## 条目数再向上取整到 6 的倍数（`n12 = 12; if (n11 > 11) n12 = 6 * ((n11 + 5) / 6)`）。
##
## `item_food.dat` 实测：25–36 共 12 组各有一条记录（其余 26 组记录数为 0）；记录的 detail 槽
## 0／1／2 是 `<材料索引(u8) | 件数(u8) << 8>`（`Menu_Item_DrawInfoFood` 与
## `Field_Item_Food_Proc` 都按低字节取 basic 第 3 组材料、高字节取件数）。
## 食谱表由 `script\export_food_recipes.py` 从 `item_food.dat` 原字节导成 `assets/food-recipes.tres`
## （`FoodRecipes`），本页只读资源；资源缺失或空表就报错，不回退到任何自造表。
##
## 页面几何（`Field_Item_Food_mPaint` → `Field_Item_DrawList` 的 n6 = 5）：
## 窗口 `Menu_win_Box4_DrawWindow(228, 240, …, side 1, header 16)` 即 (86, 0)；标题 `msg 78`；
## 单档位的类别格 33×30 在 `(窗x + 9, 窗y + 21)`（`Menu_winDrawIcon14` 对 n5 > 5 取 `common/ui_window`
## 第 14 帧的 (0, 30) 格）；格子区 `(窗x + 9, 窗y + 52)`、6 列 × 32 步距、格子 30×30；
## 列表底部 11 px 条画选中名 + 持有金钱；食谱面料板 `(窗x + 9, 窗y + 132, 212, 91)`
## （`Menu_Item_DrawInfoFood`）；价格牌 48×9 在 `(窗x + 170, 窗y + 210)`，
## `Field_Item_Food_DrawPrice` 对可造项恒画 100。

signal completed   ## 制作成功过一次（宿主可刷新 HUD 金钱）

## 原生列表最短 12 格（`Field_Item_Food_init` 的 `n12 = 12`）。
const MINIMUM_SLOTS := 12
## `Field_Item_Food_Proc` 的 `Param_moneySET(-100)`：固定 100，与 `item_food.dat` 无关。
const MONEY_COST := 100
## `Field_Item_Food_mKeyPressed` 的 `money_balance <= 0x63` 拒绝（要留够 100）。
const MINIMUM_MONEY := MONEY_COST - 1
## `Field_Item_Food_Proc` 的 `LOWORD(v9) = 1`：产品写回 basic 第 1 组，索引不变。
const PRODUCT_KIND := 1
## `Menu_Item_DrawInfoFood` 的 `JC_grpSetCHANGE(0, 0, 16711935)`：材料不够时数字换品红。
const INSUFFICIENT_COLOR := Color("#ff00ff")
## `item_food.dat` 的 12 条食谱（`assets/food-recipes.tres`，由 `script\export_food_recipes.py`
## 从原字节导出）；取不到就报错，不在脚本里留第二份表。
const RECIPE_PATH := "res://game/field/shops/food_shop/food-recipes.tres"

## 食谱资源缺失／空表时的原因；非空串时显示在详情面板的提示行。
var load_error := ""

var _recipes: FoodRecipes
var _entries: Array[Dictionary] = []
var _slot_count := MINIMUM_SLOTS


func _ready() -> void:
	super()
	for slot in range(CELLS):
		_cell(slot).pressed.connect(_select_slot.bind(slot))
	$Content/AcceptHit.pressed.connect(craft)
	$Content/BackHit.pressed.connect(close)


## 原生该页由列表页 `FieldCanvas_SetNext(15)` 直接进入，没有参数。
func present(story: Object, assets: Node) -> void:
	_story = story
	_assets = assets
	cursor = 0
	notice_id = -1
	_closing = false
	_catalog = assets.load_gameplay_catalog()
	_names = assets.text_messages("common/item_basic.dat")
	_recipes = load(RECIPE_PATH) as FoodRecipes
	$Bounds/Title.text = _text(Msg.Id.FOOD_CRAFT_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	_build_entries()
	_refresh()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if is_transitioning() or _closing:
		return true
	match key:
		"ArrowLeft":
			_move(-1)
		"ArrowRight":
			_move(1)
		"ArrowUp":
			_move(-COLUMNS)
		"ArrowDown":
			_move(COLUMNS)
		"Enter", "Space":
			craft()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


## 真正进了列表的食谱数（`Item_datBasic` case 27 有记录的那些组）。
func entry_count() -> int:
	return _entries.size()


## 光标所在的产品 id（`type * 1000 + index` 的 1000 号段），越过列表返回 −1。
func selected_id() -> int:
	var entry := _entry()
	return int(entry.product_id) if not entry.is_empty() else -1


## 原生 `Field_Item_Food_mKeyPressed` 的 −5 分支 → `Field_Item_Food_Proc`。
## 返回写进 `notice_id` 的记录号（−1 表示没有提示，即成功或空槽）。
func craft() -> int:
	notice_id = -1
	var entry := _entry()
	if entry.is_empty():
		_refresh()
		return -1
	if money() <= MINIMUM_MONEY:
		return _note(Msg.Id.SHOP_NOT_ENOUGH_MONEY)
	if not _has_materials(entry):
		return _note(Msg.Id.FOOD_CRAFT_NO_MATERIAL)
	var product_id := int(entry.product_id)
	# 原生顺序：先 `Item_stdAddEx`（不管返回值）→ `Param_moneySET(-100)` → 递归那一趟才扣材料。
	# 本工程把入包失败当成中止（原生会静默丢材料），不编造提示。
	if not _story._add_inventory_item(product_id, int(entry.product_count), false):
		push_error("食物制作：%d 放不进背包，本次不扣材料也不扣钱。" % product_id)
		_refresh()
		return notice_id
	_story.progress["parameter"]["moneyBalance"] = money() - MONEY_COST
	for material: Dictionary in entry.materials:
		_story.consume_item(int(material.id), int(material.count))
	_refresh()
	completed.emit()
	return -1


func _build_entries() -> void:
	_entries.clear()
	load_error = ""
	MessageStack.say(load_error)
	if _recipes == null or _recipes.size() == 0:
		load_error = "食物制作：%s 缺失或没有食谱。" % RECIPE_PATH
		push_error(load_error)
		_slot_count = MINIMUM_SLOTS
		return
	for recipe: Dictionary in _recipes.entries:
		var product_id := int(recipe.product_id)
		var product: ItemDefinition = _catalog.item(product_id) if _catalog != null else null
		if product == null or product.type != PRODUCT_KIND or product.index != ItemKind.index_of(product_id):
			push_error("食物制作：原道具目录缺少产品 %d（`item_food.dat` 组 %d）。" \
				% [product_id, ItemKind.index_of(product_id)])
			continue
		_entries.append({"product_id": product_id, "product": product,
			"product_count": int(recipe.product_count), "materials": recipe.materials})
	_slot_count = _padded_count(_entries.size())
	if _entries.size() > CELLS:
		push_error("食物制作：%d 条食谱超过单页 %d 格，本页没有滚动。" % [_entries.size(), CELLS])
		_entries = _entries.slice(0, CELLS)


## 原生 `n12 = 12; if (n11 > 11) n12 = 6 * ((n11 + 5) / 6)`。
func _padded_count(count: int) -> int:
	if count < MINIMUM_SLOTS:
		return MINIMUM_SLOTS
	return COLUMNS * int((count + COLUMNS - 1) / COLUMNS)


func _entry() -> Dictionary:
	return _entries[cursor] if cursor >= 0 and cursor < _entries.size() else {}


## `Field_Item_Food_Proc` 的 a2 = 0 那一趟：逐槽 `Item_fndCount >= 件数`，**分别**检查不合计。
func _has_materials(entry: Dictionary) -> bool:
	for material: Dictionary in entry.materials:
		if _owned_count(int(material.id)) < int(material.count):
			return false
	return true


func _refresh() -> void:
	_owned = _inventory_counts()
	_refresh_cells()
	_refresh_strip()
	_refresh_materials()
	$Content/Price/Number.present(str(MONEY_COST))


func _refresh_cells() -> void:
	for slot in range(CELLS):
		var cell := _cell(slot)
		var chosen := slot == cursor
		# 空位也用普通帧（原生 `a6` 是「在条目范围内」，见 `SlotFrame`）。
		cell.present_frame(SlotFrame.frame_of(cell_frames, true, chosen), chosen)
		cell.set_grade(null)
		cell.get_node("QuantityNumber").hide()
		var icon: Control = cell.get_node("Icon")
		if slot >= _entries.size():
			icon.texture = null
			continue
		var record: ItemDefinition = _entries[slot].product
		icon.texture = _assets.item_icon(record.icon) if record.icon >= 0 else null


## `Menu_Item_DrawListInfo`：选中名在条左侧、持有金钱在右侧。
func _refresh_strip() -> void:
	var entry := _entry()
	$Content/Name.text = _item_name(entry.get("product")) if not entry.is_empty() else ""
	$Content/Money/Number.present(str(money()))


## `Menu_Item_DrawInfoFood`：标题是 `[ 产品名 X 件数 ]`（原生前面还带
## `Item_stdGradeINDEX` 的颜色控制码 `#C6`，本工程不画控制码），下面三行材料：
## 图标 → 名称 → `持有/需要`（不够时用红色，原生 `Menu_numDrawNumber` 样式 3）。
func _refresh_materials() -> void:
	var entry := _entry()
	var materials: Array = entry.get("materials", [])
	$Content/Panel/Title.text = "" if entry.is_empty() else \
		"[ %s X %d ]" % [_item_name(entry.get("product")), int(entry.get("product_count", 0))]
	# 静态提示行已退役：结果与失败都走提示栈（原生 `Game_infoInit`），面板不再承载提示文本。
	$Content/Panel/Notice.text = ""
	for slot in range(3):
		var row := get_node("Content/Panel/Row%d" % slot)
		var material: ItemDefinition = null
		var need := 0
		var have := 0
		if slot < materials.size():
			var material_id := int(materials[slot].id)
			material = _catalog.item(material_id) if _catalog != null else null
			need = int(materials[slot].count)
			have = _owned_count(material_id)
		row.get_node("Icon").texture = _assets.item_icon(material.icon) \
			if material != null and material.icon >= 0 else null
		row.get_node("Name").text = _item_name(material) if material != null else ""
		row.get_node("Count").text = "" if slot >= materials.size() else "%d/%d" % [have, need]
		row.get_node("Count").color = Color.WHITE if have >= need else INSUFFICIENT_COLOR


func _select_slot(slot: int) -> void:
	if _closing or is_transitioning():
		return
	if slot >= _slot_count:
		return
	if slot == cursor:
		craft()
		return
	cursor = slot
	notice_id = -1
	_refresh()


## 原生 `Field_Item_Food_mKeyPressed` 的 12／13／14／15（−4／−3／−2／−1）：
## `+1`、`−1+6*rows`、`+6`、`−6+6*rows`，都按补齐后的格数取模。
func _move(step: int) -> void:
	cursor = posmod(cursor + step, _slot_count)
	notice_id = -1
	_refresh()
