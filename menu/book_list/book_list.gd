extends "res://core/window_transition/window_transition.gd"

## 原生 `Game_Book_List`（GAME_STATE_BOOK_LIST）：228×208 窗口、标题「图鉴」，
## 两个 118×20 选项「精灵」／「技能书」。
##
## 依据：`Game_Book_List_init`（把选项数 2 与开窗计数 1 写进 GameData）、
## `Game_Book_List_mPaint` → `Game_Menu_List_Draw`（窗口 228×208、
## 按钮 x = (宽-118)/2、行距 (高-36)/(n+1)、选中边框 0x7AD0FA／未选中 0x196485、填充 0xE1B2F）、
## `Game_Book_List_mKeyPressed`（上／下在两个选项间切换，OK 进图鉴，
## CLR 回地图）。

signal page_requested(page: int)
signal back_requested

## `JC_fxt2Return(98)`／`(99)`：精灵／技能书。
const PAGE_MESSAGES := [Msg.Id.BOOK_MONSTER_PAGE, Msg.Id.BOOK_SKILL_PAGE]
const SELECTED_BORDER := Color("#7ad7ff")
const BORDER := Color("#196485")

var selected := 0

var _assets: Node


func _ready() -> void:
	super()
	for index in range(PAGE_MESSAGES.size()):
		var card: Button = get_node("Content/Option%d" % index)
		card.pressed.connect(_select.bind(index))
	$Content/AcceptHit.pressed.connect(_confirm)
	$Content/BackHit.pressed.connect(func(): back_requested.emit())


func present(assets: Node) -> void:
	_assets = assets
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.BOOK_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	selected = 0
	_render()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if is_transitioning():
		return true
	match key:
		"ArrowUp", "ArrowDown":
			selected = 1 - selected
			_render()
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			back_requested.emit()
		_:
			return false
	return true


func _confirm() -> void:
	page_requested.emit(selected)


func _select(index: int) -> void:
	if is_transitioning():
		return
	if index == selected:
		_confirm()
		return
	selected = index
	_render()


func _render() -> void:
	for index in range(PAGE_MESSAGES.size()):
		var card: Button = get_node("Content/Option%d" % index)
		var chosen: bool = index == selected
		card.get_node("Label").text = _assets.text_message(Msg.SOURCE, PAGE_MESSAGES[index])
		card.get_node("Label").color = Color.WHITE if chosen else BORDER
		var border: Color = SELECTED_BORDER if chosen else BORDER
		card.get_node("Inner").modulate = border
		card.get_node("Outer").modulate = border
