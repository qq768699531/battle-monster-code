extends Control

## 图鉴总装：目录页（`Game_Book_List`）→ 怪物图鉴（`Game_Book_Monster`）／
## 技能书（`Game_Book_Skill`）。
##
## 原生是三个独立状态，各自开自己的窗口并重播开窗动画（`Game_Book_*_init` 都把开窗计数
## 置 1），所以这里不合并成一张表：切页先播当前页的关窗，结束后再 `present()` 下一页。
## 依据 `Game_Book_List_mKeyPressed`（OK 进图鉴、CLR 回地图）、
## `Game_Book_Monster_mKeyPressed` 与 `Game_Book_Skill_mKeyPressed`（CLR 回目录）。

signal closed

const Book = preload("res://menu/book_model/book_model.gd")
const PAGES := ["BookList", "BookMonster", "BookSkill"]

## -1 表示关窗后离开图鉴；其余是关窗后要打开的页号。
var _pending := -1
var _page := 0
var _closing := false

var _assets: Node
var _catalog: GameplayData
var _knowledge: Dictionary = {}


func _ready() -> void:
	for page_name in PAGES:
		var page: Control = get_node(page_name)
		page.hide()
		page.transition_finished.connect(_transition_finished)
	$BookList.page_requested.connect(_open)
	$BookList.back_requested.connect(close)
	$BookMonster.back_requested.connect(_back_to_list)
	$BookSkill.back_requested.connect(_back_to_list)


## `knowledge` 是图鉴的「知识表」（`Book.records()` 同形）；留空就用存档里的获得记录，
## 换一份表即可只显示指定收录范围（调试全开见 `Book.all_records()`）。
func open(assets: Node, catalog: GameplayData, progress: Dictionary,
		knowledge: Dictionary = {}) -> bool:
	if catalog == null:
		return false
	_assets = assets
	_catalog = catalog
	_knowledge = knowledge if not knowledge.is_empty() else Book.records(progress)
	_pending = -1
	_closing = false
	_page = 0
	_show_page(0)
	show()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	_pending = -1
	get_node(PAGES[_page]).close_window()


func press(key: String) -> void:
	if _closing or _pending >= 0:
		return
	get_node(PAGES[_page]).handle_key(key)


## 目录页的两个选项：原生 `Game_Book_List_mKeyPressed` 的 `transition_parameter_bits`
## 0 = 怪物图鉴、1 = 技能书。
func _open(page: int) -> void:
	if _closing:
		return
	var target := 1 if page == 0 else 2
	if target == _page:
		return
	_pending = target
	get_node(PAGES[_page]).close_window()


## 怪物图鉴／技能书的 CLR 回目录页（原生 `GameCanvas_SetNext(GAME_STATE_BOOK_LIST)`）。
func _back_to_list() -> void:
	if _closing:
		return
	_pending = 0
	get_node(PAGES[_page]).close_window()


func _transition_finished(opened: bool) -> void:
	if opened:
		return
	if _pending < 0:
		_closing = false
		hide()
		closed.emit()
		return
	get_node(PAGES[_page]).hide()
	_page = _pending
	_pending = -1
	_show_page(_page)


func _show_page(index: int) -> void:
	var page: Control = get_node(PAGES[index])
	if index == 0:
		page.present(_assets)
	else:
		page.present(_assets, _catalog, _knowledge)
