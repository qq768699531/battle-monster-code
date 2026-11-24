extends "res://field/field_window.gd"

## `Game_Menu_List_Draw` 那一族竖排卡片菜单的共用部分：公会列表（`Field_Guild_List`，状态 6）、
## 精灵管理所（`Game_Monster_List`，状态 21）、商店列表（`Field_Item_List`，状态 12）。
##
## 三页的原生绘制与按键都是同一套：`mPaint` → `Game_Menu_List_Draw` 逐行画 118×20 的框，
## 未选中框与字同色、选中框换成亮色而字写白；`mKeyPressed` 的 −1／−2 循环移游标、−5 按游标分派。
## 差在行表来源、行数与确认后去哪一页——这些由子页的 `row_messages()`／`_confirm()` 决定。

## `JC_grpSetRGB(0x196485)`：未选中框与字色，也是 `Menu_Item_DrawList` 的外框色。
const BORDER := Color("#196485")
## `JC_grpSetRGB(0x7AD0FA)`：选中框色（选中行的字写白色）。
const SELECTED_BORDER := Color("#7ad0fa")

## `FieldData+0x14`／`GameData.transition_parameter_bits` 的那一个游标。
var cursor := 0

var _assets: Node


## 本页的行文案（`msg` 记录号，顺序即 `Content/Option0` 起的卡片）。
func row_messages() -> Array:
	return []


## 子页实现：−5／点当前行要做的事（进下一页、或原生瞬时关页）。
func _confirm() -> void:
	pass


## 输入前置守卫：默认关页中与开合动画中都不接输入。
## `Game_Monster_List` 的 `mRun` 是空壳、没有开合锁定，那一页覆盖成只看关页标志。
func _accepts_input() -> bool:
	return not _closing and not is_transitioning()


func _card(index: int) -> Button:
	return get_node("Content/Option%d" % index) as Button


func _select(index: int) -> void:
	if not _accepts_input():
		return
	if index == cursor:
		_confirm()
		return
	cursor = index
	_render()


## −1／−2：游标按行数循环（原生的 `(游标 ± 1) % 条数`）。
func _move(step: int) -> void:
	var count := row_messages().size()
	if count == 0:
		return
	cursor = posmod(cursor + step, count)
	_render()


func _render() -> void:
	var messages := row_messages()
	for index in range(messages.size()):
		var card := _card(index)
		var chosen: bool = index == cursor
		card.get_node("Label").text = _assets.text_message(Msg.SOURCE, messages[index])
		card.get_node("Label").color = Color.WHITE if chosen else BORDER
		var border: Color = SELECTED_BORDER if chosen else BORDER
		card.get_node("Inner").modulate = border
		card.get_node("Outer").modulate = border
