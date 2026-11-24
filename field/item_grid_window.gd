extends "res://field/field_window.gd"

## `Field_Item_DrawList` 那一族道具格的共用部分：食物制作（`Field_Item_Food`，状态 15）、
## 购买／出售（`Field_Item_Buy`／`Field_Item_Sell`，状态 13／14）。
##
## 三页的格子区都是 6 列 × 2 行、30×30 的 `Menu_winDrawIcon16` 格（空位照画格底，`a6` 是
## 「在条目范围内」），底部 11 px 条画选中名与持有金钱；失败与异常提示走 `Game_infoInit`
## （`notice_id` + 提示栈），关页到相位 −4 时清掉。格子内容与详情面板各页自己的。

const MessageStack = preload("res://ui/message_stack.gd")
const SlotFrame = preload("res://data/slot_frame.gd")

## `Field_Item_DrawList` 的 6 列 × 2 行（`32 × 6 + 20` 宽、`32 × 行数 + 15` 高）。
const COLUMNS := 6
const VISIBLE_ROWS := 2
const CELLS := COLUMNS * VISIBLE_ROWS

## 格子背景（`Menu_winDrawIcon16` 的 30×30 四帧，与其它页面共用 `assets/ui/slot/`，顺序见 `SlotFrame.Frame`）。
@export var cell_frames: Array[Texture2D] = []

var cursor := 0
## 原生 `Game_infoInit(fxt …)` 的记录号；−1 表示当前没有提示。
var notice_id := -1

var _assets: Node
var _story: Object
var _catalog: GameplayData
## 背包持有数（道具号 → 件数），页打开与每次成交后重算。
var _owned: Dictionary = {}
## `common/item_basic.dat`／`common/item_skill.dat` 的名字表（记录号 → 文本）。
var _names: Dictionary = {}


func money() -> int:
	var parameter: Variant = _story.progress.get("parameter", {})
	return int(parameter.get("moneyBalance", 0)) if parameter is Dictionary else 0


func _cell(slot: int) -> ItemCell:
	return get_node("Content/Cell%d" % slot) as ItemCell


func _text(message_id: int) -> String:
	return _assets.text_message(Msg.SOURCE, message_id)


## 成交失败：原生在这一步用 `Game_infoInit` 弹一行，所以记录号直接进提示栈；
## `notice_id` 仍然保留（宿主/测试读它），但页面不再把它画成静态文本。
func _note(message_id: int) -> int:
	notice_id = message_id
	MessageStack.say_record(message_id)
	_refresh()
	return notice_id


func _inventory_counts() -> Dictionary:
	var counts := {}
	var inventory: Variant = _story.progress.get("inventory", {})
	if not inventory is Dictionary:
		return counts
	for key: Variant in inventory:
		var text := str(key)
		if text.is_valid_int():
			counts[int(text)] = int(inventory[key])
	return counts


func _owned_count(item_id: int) -> int:
	return int(_owned.get(item_id, 0))


func _item_name(record: ItemDefinition) -> String:
	if record == null:
		return ""
	if _names.has(record.name_record):
		return str(_names[record.name_record])
	return "原道具 %d:%d" % [record.type, record.index]


## 子页实现：重画格子、条与详情面板（成交／换档／换游标后都会调）。
func _refresh() -> void:
	pass


## 原生关页到相位 −4 时清掉 `Game_infoInit` 的记录号，下次开页不带旧提示。
func _on_window_finished(opened: bool) -> void:
	if not opened:
		notice_id = -1
	super(opened)
