extends "res://scripts/field/list_menu_window.gd"

## 原生 `GAME_STATE_MONSTER_LIST`（21，`GameCanvas` 的落点页）：
## `Game_Monster_List_init`（条目数 2、相位从 1 起）／
## `mPaint` → `Game_Menu_List_Draw`（标题 msg 102、两行 msg 103／104）／
## `mKeyPressed`（−1／−2 都是 `(游标 + 1) % 2`、−5 按游标进 22／23、−16 立刻回野外）／
## `mRun` 与 `destroy` 都是空壳。
##
## 窗口 228×208 @ (86, 16)、侧白边 1、header 16；两行 118×20、x = 141、行距 57、行顶 83／140。
## 未选中框 `0x196485` + 同色字，选中框 `0x7AD0FA` + 白字（`Game_Menu_List_Draw` 的
## `JC_grpSetRGB`／`JC_fntSetRGB`）。行几何与文本节点都在 `.tscn`，脚本只切选中态。
## 行样式也是原生的：`JC_grp*RoundRECT` 收 style 1（四角各切 1px）＋填充 `0xE1B2F`，所以
## `.tscn` 覆盖了 `option_card` 实例三层的样式（`RowBorder`／`RowFill`），取证见
## `wiki\growth\game-monster-list.md` §9。

signal selected(action: String)

## `Game_Monster_List_mPaint` 的两个条目记录号，顺序即
## 游标 0 → `GAME_STATE_MONSTER_MIX`(22)、游标 1 → `GAME_STATE_MONSTER_ENCHANT`(23)。
const ACTIONS := ["mix", "enchant"]
const MESSAGES := [Msg.Id.MONSTER_MIX, Msg.Id.MONSTER_ENCHANT]


func _ready() -> void:
	super()
	for index in range(ACTIONS.size()):
		var card: Button = get_node("Content/Option%d" % index)
		card.pressed.connect(_select.bind(index))
	$Content/CancelHit.pressed.connect(close)


## `position` = 进入本页时的 transition 参数（`Evt_chtMENU` 给 0）。
func present(assets: Node, position: int = 0) -> void:
	_assets = assets
	cursor = position
	_closing = false
	$Bounds/Title.text = assets.text_message(Msg.SOURCE, Msg.Id.MONSTER_OFFICE)
	_render()
	show()
	# `Menu_win_Box4_DrawWindow` 每帧把相位按符号推进 1→2→3→4，标题与两行
	# 只在相位 ∈ {−1, 3, 4} 时绘制，所以开窗有动画；`open` 轨道的相位序列与之一致。
	open_window()


## `Game_Monster_List_mRun` 是空壳、`mKeyPressed` 的 −16 直接
## `GameCanvas_SetNext(GAME_STATE_FIELD, 1)`，所以关页瞬时、不播关窗动画：
## 野外由 `Field_Basic_init` 重新初始化并重绘，不需要额外的淡出。
func _begin_close() -> void:
	_finish_close()


func handle_key(key: String) -> bool:
	if _closing:
		return true
	match key:
		"ArrowUp", "ArrowDown":
			_move(1)
		"Enter", "Space":
			_confirm()
		"Escape", "Backspace":
			close()
		_:
			return false
	return true


## `Game_Monster_List` 没有开合锁定（`mRun` 是空壳），只有关页中才拦输入。
func _accepts_input() -> bool:
	return not _closing


## `Game_Monster_List_mKeyPressed` 的 −5：游标 0 → `SetNext(22, 0)`、
## 游标 1 → `SetNext(23, 0)`，同样不播关窗。
func _confirm() -> void:
	if not _accepts_input():
		return
	_closing = true
	hide()
	selected.emit(ACTIONS[cursor])


func row_messages() -> Array:
	return MESSAGES
