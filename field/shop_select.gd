extends Control
## 原生 `Field_Item_DrawSelect`：道具列表选中后的数量／确认框。
##
## 窗口 `Menu_win_Box2_DrawWindow(160, …)`，正文取 `fxt 82/83/84`（要扔掉吗?／要购买吗?／要出售吗?），
## 底部两个 44×16 的确认键固定是 `fxt 85/86`（是／否），选中的那只用 `#FF9200` 底 + 黑字。
## 本体沿用道具页丢弃窗（`scenes/menu/item_discard.tscn`）在同一份原生函数上的分工：
## 先选数量（数字嵌在橙色底上），再切是／否（数字改黑底白字）。


const ConfirmLayout = preload("res://ui/confirm_layout.gd")

## 原生 `Field_Item_DrawSelect(n2, 160, …)` 的窗宽（`Field_Item_Buy_mPaint` 等传 160）。
const BOX_WIDTH := 160


## 窗高只按原生常量表（`Field_Item_DrawSelect:60-62` 的 `n42 = 表[n2] + 33`），道具行已含在表值里。



signal decided(count: int)
signal cancelled

## 原生 `n4`：0 = 数量步进，1 = 是／否。
var step := 0
var quantity := 1
var maximum := 1
var selected := 0

var _yes := ""
var _no := ""
var _decided := false
## 原生 `n2`（`ConfirmLayout.ItemSelect`）与单价；买／卖才画价格行。
var _kind := ConfirmLayout.ItemSelect.DISCARD
var _unit_price := 0


func _ready() -> void:
	visible = false
	$Window.transition_finished.connect(_transition_finished)
	$Window/Content/Yes.pressed.connect(_choose.bind(0))
	$Window/Content/No.pressed.connect(_choose.bind(1))


## `prompt`／`yes`／`no` 是宿主取好的 `msg.fxt` 正文；`limit` 是可选数量上限（至少 1）。
func present(prompt: String, yes: String, no: String, icon: Texture2D, limit: int,
		kind: int = ConfirmLayout.ItemSelect.DISCARD, unit_price := 0) -> void:
	step = 0
	quantity = 1
	maximum = maxi(1, limit)
	selected = 0
	_decided = false
	$Window/Content/Item.get_node("Icon").texture = icon
	$Window/Content/Prompt.text = prompt
	_kind = kind
	_unit_price = unit_price
	_apply_window_size(kind)
	_yes = yes
	_no = no
	_render()
	show()
	$Window.open_window()


func handle_key(key: String) -> bool:
	if $Window.is_transitioning():
		return true
	if step == 0:
		match key:
			"ArrowLeft":
				_step_quantity(-1)
			"ArrowRight":
				_step_quantity(1)
			"Enter", "Space":
				step = 1
				_render()
			"Escape", "Backspace":
				_close()
			_:
				return false
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			selected = 1 - selected
			_render()
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			step = 0
			_render()
		_:
			return false
	return true


## 窗高只按原生常量表：丢弃 75、买／卖 87（`Field_Item_DrawSelect:60-62`）。


## 正文是 fxt 82／83／84 的中心对齐单行（`:135-138`），不参与定高；买／卖多 12 px 价格行。
## 所以正文、点线、确认键整体下移 `ITEM_SELECT_PRICE_ROW`。
func _apply_window_size(kind: int) -> void:
	$Window.window_size = ConfirmLayout.item_select_size(BOX_WIDTH, kind)
	var price_row := ConfirmLayout.ITEM_SELECT_PRICE_ROW \
		if kind != ConfirmLayout.ItemSelect.DISCARD else 0
	var content: Control = $Window/Content
	(content.get_node("Prompt") as Control).position.y = ConfirmLayout.ITEM_SELECT_TEXT_TOP + price_row
	(content.get_node("Rule") as Control).position.y = ConfirmLayout.ITEM_SELECT_RULE_TOP + price_row
	for node_name in ["Yes", "No"]:
		(content.get_node(node_name) as Control).position.y = ConfirmLayout.ITEM_SELECT_CHOICE_TOP + price_row
	var plate: Control = content.get_node("Price")
	plate.position = Vector2(ConfirmLayout.ITEM_SELECT_PRICE_PLATE.position)
	plate.size = Vector2(ConfirmLayout.ITEM_SELECT_PRICE_PLATE.size)
	plate.visible = kind != ConfirmLayout.ItemSelect.DISCARD



func _step_quantity(direction: int) -> void:
	quantity = quantity + direction
	if quantity > maximum:
		quantity = 1
	elif quantity < 1:
		quantity = maximum
	_render()


func _confirm() -> void:
	if $Window.is_transitioning():
		return
	if selected != 0:
		_close()
		return
	var count := quantity
	_decided = true
	_close()
	decided.emit(count)


func _choose(index: int) -> void:
	if $Window.is_transitioning():
		return
	if selected == index:
		_confirm()
		return
	selected = index
	_render()


func _close() -> void:
	$Window.close_window()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	if _decided:
		_decided = false
		return
	cancelled.emit()


## 未选中那只确认键是灰字、没有底色（`Menu_win_Box2_DrawSelect` 的 0x808080 分支）。
func _render() -> void:
	var choosing := step == 0
	$Window/Content/QuantityBackground.color = Color("#ff9600") if choosing else Color.BLACK
	$Window/Content/Quantity.modulate = Color.BLACK if choosing else Color.WHITE
	$Window/Content/Quantity.present(str(quantity))
	$Window/Content/Yes/Choice.present(_yes, not choosing and selected == 0)
	$Window/Content/No/Choice.present(_no, not choosing and selected == 1)
	if _kind != ConfirmLayout.ItemSelect.DISCARD:
		$Window/Content/Price/Number.present(str(_unit_price * quantity))
