extends Control
## 原生 `Field_Item_DrawSelect` 的通用数量／确认框：道具买卖、丢弃共用同一套交互。
##
## 窗口 `Menu_win_Box2_DrawWindow(160, …)`，正文取 `fxt 82/83/84`（要扔掉吗?／要购买吗?／要出售吗?），
## 提示行居中；底部两个 44×16 的确认键固定是 `fxt 85/86`（是／否），选中的那只用 `#FF9200` 底 + 黑字。
## 先选数量（数字嵌在橙色底上），再切是／否（数字改黑底白字）。
##
## 具体宿主（商店买卖、道具页丢弃）只负责提供名称、图标、格底、品级色与确认后的副作用，
## 数量步进、是／否、开合、小号数字和居中提示都在这里，避免两份实现走偏。

const ConfirmLayout = preload("res://engine/ui/confirm_layout/confirm_layout.gd")

const BOX_WIDTH := 160

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
var _frame_texture: Texture2D = null
var _grade_color: Variant = null


func _ready() -> void:
	visible = false
	$Window.transition_finished.connect(_transition_finished)
	$Window.chosen.connect(_on_confirm_choice)
	for hit: String in ["MinusHit", "PlusHit"]:
		var button: Button = get_node_or_null("Window/Content/%s" % hit) as Button
		if button != null:
			button.pressed.connect(_step_quantity.bind(-1 if hit == "MinusHit" else 1))


## `prompt`／`yes`／`no` 是宿主取好的 `msg.fxt` 正文；`limit` 是可选数量上限（至少 1）。
## `frame_texture`／`grade_color` 是 32×32 道具格的实时边框与品级色。
func present(prompt: String, yes: String, no: String, icon: Texture2D, limit: int,
		kind: int = ConfirmLayout.ItemSelect.DISCARD, unit_price := 0,
		frame_texture: Texture2D = null, grade_color: Variant = null) -> void:
	present_item(prompt, yes, no, icon, limit, 1, 0, kind, unit_price, frame_texture, grade_color)


## 丢弃时从宿主已有的数量／相位进入；买／卖走 `present()` 的 1／数量步进。
func present_item(prompt: String, yes: String, no: String, icon: Texture2D, limit: int,
		start_quantity: int, start_step: int, kind: int, unit_price: int,
		frame_texture: Texture2D = null, grade_color: Variant = null) -> void:
	step = clampi(start_step, 0, 1)
	maximum = maxi(1, limit)
	quantity = clampi(start_quantity, 1, maximum)
	selected = 0
	_decided = false
	_kind = kind
	_unit_price = unit_price
	_yes = yes
	_no = no
	_frame_texture = frame_texture
	_grade_color = grade_color
	_render_item(icon)
	$Window.set_direct_choice(true)
	$Window.present_neutral(prompt)
	$Window.set_body_alignment(1)
	_apply_window_size(kind)
	_render()
	show()
	# `Window` 在场景里是 `visible = false`（`confirm_box` 自己不会在 `open_window` 里 show），
	# 不显式打开的话根节点可见、窗口本身仍然隐藏。
	$Window.show()
	$Window.open_window()


func handle_key(key: String) -> bool:
	if $Window.is_transitioning():
		return true
	# 三个可选中项：数量、是、否。上下在「数量」与「是/否」之间换焦点，
	# 左右在数量上改数值、在是/否上切换；−/＋ 不参与焦点，只接鼠标点击。
	if key in ["ArrowUp", "ArrowDown"]:
		step = 1 - step
		_step_changed()
		_render()
		return true
	if step == 0:
		match key:
			"ArrowLeft":
				_step_quantity(-1)
			"ArrowRight":
				_step_quantity(1)
			"Enter", "Space":
				step = 1
				_step_changed()
				_render()
			"Escape", "Backspace":
				_close()
			_:
				return false
		return true
	match key:
		"ArrowLeft", "ArrowRight":
			selected = 1 - selected
			_step_changed()
			_render()
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			step = 0
			_step_changed()
			_render()
		_:
			return false
	return true


## 正文是 fxt 82／83／84 的中心对齐单行（`:135-138`），不参与定高；买／卖多 12 px 价格行。
## 所以正文、点线、确认键整体下移 `ITEM_SELECT_PRICE_ROW`。
func _apply_window_size(kind: int) -> void:
	$Window.window_size = ConfirmLayout.item_select_size(BOX_WIDTH, kind)
	$Window.header_offset = ConfirmLayout.ITEM_SELECT_PRICE_ROW \
		if kind != ConfirmLayout.ItemSelect.DISCARD else 0
	var plate: Control = get_node_or_null("Window/Content/Price") as Control
	if plate != null:
		plate.position = Vector2(ConfirmLayout.ITEM_SELECT_PRICE_PLATE.position)
		plate.size = Vector2(ConfirmLayout.ITEM_SELECT_PRICE_PLATE.size)
		plate.visible = kind != ConfirmLayout.ItemSelect.DISCARD


func _step_quantity(direction: int) -> void:
	# 鼠标点 −/＋ 时把焦点移回数量；键盘左右在数量焦点上走同一条路径。
	step = 0
	_step_changed()
	quantity = quantity + direction
	if quantity > maximum:
		quantity = 1
	elif quantity < 1:
		quantity = maximum
	_quantity_changed()
	_render()


func _confirm() -> void:
	if step != 1 or $Window.is_transitioning():
		return
	if selected != 0:
		_close()
		return
	var count := quantity
	_decided = true
	_close()
	_accept(count)


## 触控：鼠标/触控单击是／否就直接选中；数量阶段也可以直接点（用当前数量），
## 键盘 OK 仍走数量阶段 → 是/否阶段的两次确认。
func _on_confirm_choice(accepted: bool) -> void:
	if $Window.is_transitioning():
		return
	if step == 0:
		step = 1
		_step_changed()
	selected = 0 if accepted else 1
	_step_changed()
	_confirm()


func _close() -> void:
	$Window.close_window()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	hide()
	if _decided:
		_decided = false
		return
	_cancel()


## 宿主可覆写：买／卖发 `decided`，丢弃把数量交给宿主并执行丢弃。
func _accept(count: int) -> void:
	decided.emit(count)


## 宿主可覆写：CLR 取消时恢复宿主状态。
func _cancel() -> void:
	cancelled.emit()


## 宿主可覆写：数量／相位变化时同步宿主字段。
func _quantity_changed() -> void:
	pass


func _step_changed() -> void:
	pass


## 未选中那只确认键是灰字、没有底色（`Menu_win_Box2_DrawSelect` 的 0x808080 分支）。
func _render() -> void:
	var choosing := step == 0
	var quantity_plate: Panel = $Window/Content/QuantityBackground
	var plate_style: StyleBoxFlat = quantity_plate.get_theme_stylebox("panel") as StyleBoxFlat
	if plate_style != null:
		plate_style.bg_color = Color("#ff9600") if choosing else Color.BLACK
	$Window/Content/Quantity.modulate = Color.BLACK if choosing else Color.WHITE
	# 数量本身用字体（仅这一处；价格、计数仍走原生数字图集）。
	$Window/Content/Quantity.text = str(quantity)
	if choosing:
		$Window.present_neutral($Window.body_text())
	else:
		$Window.present_select($Window.body_text(), selected)
	# 是/否可随时鼠标直选；键盘 OK 的两次确认由 `handle_key` 保证。
	$Window.set_choices_enabled(true)
	# 原生数量框的提示行是居中；`present_*` 会重造行，所以每次重画后都要再设。
	$Window.set_body_alignment(1)
	var plate: Control = get_node_or_null("Window/Content/Price") as Control
	if plate != null and _kind != ConfirmLayout.ItemSelect.DISCARD:
		plate.get_node("Number").present(str(_unit_price * quantity))


## 道具格：格底、图标、品级都走通用 `ItemCell.present_cell`。
func _render_item(icon: Texture2D) -> void:
	var cell: Control = $Window/Content/Item
	cell.present_cell(icon, _frame_texture, false, _grade_color, 0)
