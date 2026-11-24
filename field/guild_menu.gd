extends "res://field/list_menu_window.gd"

## 原生 `Field_Guild_List_*`（`FieldCanvas` 状态 6）：
## `Field_Guild_List_init`（`FieldData+0x18 = 3`、开窗计数置 1）／
## `mRun`（关窗计数到 −4 才 `SetNext(FIELD_STATE_BASIC)`）／
## `mKeyPressed`（上 `+2 % 3`、下 `+1 % 3`、OK 按 `FieldData+0x14` 分派、CLR 关窗）／
## `mPaint` → `Game_Menu_List_Draw`。
##
## 窗口 228×208 @ (86, 16)、侧白边 1、header 16，标题 `msg 50`；三行 118×20、x = 窗x+55、
## 行距 `(208 − 36) / (3 + 1) = 43`，首行顶 `y = 窗y + 10 + 43`，即 y = 69／112／155。
## 未选中框 `#196485` + 同色字，选中框 `#7AD0FA` + 白字。
##
## 游标 `FieldData+0x14` 同时是 `FieldCanvas_SetNext` 的 transition 参数（任务页回列表给 1、
## 资料页回列表给 2），所以 `present()` 收 `position`。
##
## 「公会名录／人数／任务计数」在原生里不存在：这三行是固定菜单，行内判定（`msg` 45–49 的
## 不可用提示、`guild_code` 与任务图标）属于挑战页与公会任务页，不在这里。

signal selected(action: String)

## `JC_fxt2Return(51/52/53)`：公会排名挑战／公会任务／会长的建议。
const ACTIONS := ["challenge", "quest", "info"]
const MESSAGES := [Msg.Id.GUILD_CHALLENGE, Msg.Id.GUILD_QUEST, Msg.Id.GUILD_INFO]


func _ready() -> void:
	super()
	for index in range(ACTIONS.size()):
		var card: Button = get_node("Content/Option%d" % index)
		card.pressed.connect(_select.bind(index))
	$Content/AcceptHit.pressed.connect(_confirm)
	$Content/BackHit.pressed.connect(close)


## `position` = 进入本页时的 transition 参数（原生 6→6 时由任务／资料页带回来）。
func present(assets: Node, position: int = 0) -> void:
	_assets = assets
	cursor = clampi(position, 0, ACTIONS.size() - 1)
	_closing = false
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.GUILD_LIST_TITLE)
	$Content/Accept.configure(assets, 0)
	$Content/Back.configure(assets, 1)
	_render()
	show()
	open_window()


func handle_key(key: String) -> bool:
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


## 原生确认直接 `SetNext(7 / 8 / 9)`，不播关窗；新页自己重播开窗动画。
func _confirm() -> void:
	if not _accepts_input():
		return
	hide()
	selected.emit(ACTIONS[cursor])


func row_messages() -> Array:
	return MESSAGES
