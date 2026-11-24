extends Control
## 任务详情（菜单内层）：原生 `Menu_Quest_DrawDetail` 的菜单侧。
##
## 页脚两项：左「世界地图」（msg 191），右「放弃」（msg 193，在册时；不在册时同一位置写 msg 192
## 「接受」）。`Menu_Quest_mKeyPressed` 的详情层：只有列表组 2／3（公会／普通槽）时左右键
## 才在两项间切换（`(页 + 1) % 2`），OK 执行选中项，CLR 回列表（把层号置 0）。
##
## 放弃是两层：页脚右键 → `Menu_win_Box2_DrawSelect`（msg 194，初值停在左键「是」）。
## 选「是」清槽并立刻回列表（`Menu_Quest_mKeyPressed` 的清槽分支写 `MenuData+0xC = 0`、
## `MainData+0x3C = -1`）；选「否」或 CLR 只把相位置 −1，层号仍是 3，等 `Menu_Quest_mRun`
## 看到相位 −4 才写回 1——也就是**收回详情层**，不是回列表。
## 收拢中的框仍要画：`Menu_Quest_Draw` 在层号 0 时也走 LABEL_9/LABEL_13，只要相位 < 0
## 就把 `Menu_win_Box2_DrawSelect` 画在列表之上。
## 菜单页没有「接受任务」这条路（那是野外 `Qst_chtDRAW` 的 `field/quest_detail`）。

const TextLayout = preload("res://ui/native_text_layout/native_text_layout.gd")
const UI_THEME = preload("res://ui/theme/ui_theme.tres")

## 页脚选中项（`MenuData` 的 `transition_parameter_bits + 3`）：0 = 世界地图，1 = 接受／放弃。
const PAGE_MAP := 0
const PAGE_ACTION := 1
const PAGE_COUNT := 2

## `Menu_win_Box2_DrawSelect`：`a4 == 0` 高亮左键「是」（msg 85），1 高亮「否」（msg 86）。
const CHOICE_YES := 0
const CHOICE_NO := 1

## 列表组号（原生 `QstData.active_marker`）：1 = 脚本任务，2 = 公会槽，3 = 普通槽；
## 类型条与「放弃」一项都按它分支。
const MAIN_QUEST_CONTAINER := 1

var host: Control

var _quest: Dictionary = {}
var _page := PAGE_MAP
var _confirming := false
var _choice := CHOICE_YES
## 确认框在收拢中（`Menu_win_Box2_DrawWindow` 每帧把相位按符号推进，1→4 稳态、−1→−4 收拢）。
var _closing := false
## 收拢完要回列表（选「是」）：期间列表先画出来，框继续叠在上面收。
var _leaving := false
## 下一次渲染是不是「刚进来」：原生每次进详情层都把页脚选中项置 0（`Menu_Quest_mKeyPressed` 的
## `0x4D008`／`0x4D02A`／`0x4D044` 三处都写 `MenuData+0x20 = 0`）。
var _opening := true


func _ready() -> void:
	hide()
	host = get_parent()
	$Confirm.transition_finished.connect(_on_confirm_transition_finished)
	$Bounds/MapButton.pressed.connect(_on_page_pressed.bind(PAGE_MAP))
	$Bounds/DiscardButton.pressed.connect(_on_page_pressed.bind(PAGE_ACTION))
	$Confirm/Content/Yes.pressed.connect(_choose.bind(CHOICE_YES))
	$Confirm/Content/No.pressed.connect(_choose.bind(CHOICE_NO))
	$Confirm.hide()


## 当前显示的详情数据（`id` 是任务号，脚本任务为 −1；`discardable` 表示列表组 2／3）。
func quest() -> Dictionary:
	return _quest


func handle_key(key: String) -> bool:
	if host.world_map_open:
		return host._pages.world_map.handle_key(key)
	if _closing:
		return true
	if _confirming:
		match key:
			"ArrowLeft", "ArrowRight":
				_choice = CHOICE_NO if _choice == CHOICE_YES else CHOICE_YES
				_render_confirm()
			"Enter", "Space":
				_resolve_confirm()
			"Escape", "Backspace":
				# CLR 与「否」同路：相位 −1，层号留在 3，收拢完回详情层。
				_start_confirm_close(false)
		return true
	if key in ["Escape", "Backspace"]:
		_close_to_list()
		return true
	if key in ["Enter", "Space"]:
		_activate_page()
		return true
	if key in ["ArrowLeft", "ArrowRight"]:
		if bool(_quest.get("discardable", false)):
			_page = (_page + 1) % PAGE_COUNT
			_render_pages()
		return true
	return false


func _render_quest_detail(data: Dictionary) -> void:
	var quest_id := int(data.get("id", -1))
	if _opening or quest_id != int(_quest.get("id", -1)):
		_page = PAGE_MAP
		_reset_confirm()
	_opening = false
	_quest = data
	_render_type(int(data.get("container", MAIN_QUEST_CONTAINER)))
	$Bounds/Title.text = "[ %s ]" % str(data.get("title", ""))
	var description := TextLayout.layout(str(data.get("description", "")),
		UI_THEME.default_font, UI_THEME.default_font_size, $Bounds/DescriptionClip.size.x)
	if not description.error.is_empty():
		push_error(description.error)
		return
	var lines: Array[String] = []
	for line: Dictionary in description.lines:
		lines.append(line.text)
	$Bounds/DescriptionClip/Description.present(lines, description.lines)
	var regions := PackedStringArray()
	for id: int in data.get("region_ids", []):
		regions.append(host._assets.text_message("map/m%d.mif" % id, "name"))
	$Bounds/Regions.visible = not regions.is_empty()
	$Bounds/Regions/Caption.text = host._menu_text(Msg.Id.QUEST_REGION_LABEL)
	$Bounds/Regions/Names.text = "/".join(regions)
	$Bounds/MapButton/Caption.text = host._menu_text(Msg.Id.QUEST_WORLD_MAP)
	var discardable := bool(data.get("discardable", false))
	# `Menu_Quest_DrawDetail` 的右按钮整段包在 `if (n2 > 1)` 里（`n2` = 详情上下文，
	# 脚本任务那一层是 1），所以只有公会／普通槽才有右按钮。
	$Bounds/DiscardButton.visible = discardable
	if discardable:
		var owned: bool = host._pages.quest.quest_log().is_active(quest_id)
		$Bounds/DiscardButton/Caption.text = host._menu_text(
			Msg.Id.QUEST_ABANDON if owned else Msg.Id.QUEST_ACCEPT)
	_render_pages()
	# `Menu_Quest_Draw` 的 overlay 2 分支只 `Menu_world_Draw`（画世界地图窗口），详情层整段
	# 不画；关窗后 `menu_view._render_content` 会重新走到这里，所以开／关两边都靠这一句切换。
	$Bounds.visible = not host.world_map_open


## 页脚两项的选中态：`Menu_winDrawIcon18` 按 `a3` 取 `common/ui_window` 第 18 帧的横向切片
## `49 * a3`，`a3 = 0` 是选中／按下的那一张（`Menu_Quest_DrawDetail` 里选中项传 0、另一项传 1）。
func _render_pages() -> void:
	$Bounds/MapButton.set_pressed_no_signal(_page == PAGE_MAP)
	$Bounds/DiscardButton.set_pressed_no_signal(_page == PAGE_ACTION)


## 类型条：`Menu_winDrawIcon13(x, y + 54, a3 = QstData - 1)` 按列表组取 `ui_window.frame-013`
## 的第 1／2／3 段（MAIN／GUID／SUB quest，宽 68／74／60，切片由 `menu_view` 备好）。
func _render_type(container: int) -> void:
	var slices: Array[Texture2D] = host._quest_label_slices
	var strip: TextureRect = $Bounds/QuestType
	strip.texture = slices[container - 1] \
		if container >= 1 and container <= slices.size() else null
	if strip.texture != null:
		strip.size.x = float(strip.texture.get_width())


## `Menu_Quest_DrawDetail:187-221`：页脚两项各自只登记一个 49×22 触控区——**未选中的那一项发
## −3／−4（只换焦点），选中的那一项才发 −5（执行）**。所以点没选中的那一项只换选中，再点一次才执行。
func _on_page_pressed(target: int) -> void:
	if _confirming or _closing:
		return
	if _page != target:
		# 右项只在 `discardable`（列表组 2／3）时存在（`DrawDetail:207` 的 `n2 > 1`）。
		if not bool(_quest.get("discardable", false)):
			return
		_page = target
		_render_pages()
		return
	_activate_page()


func _activate_page() -> void:
	if _page == PAGE_ACTION and bool(_quest.get("discardable", false)):
		_open_confirm()
		return
	_open_map()


func _open_map() -> void:
	# overlay 3（放弃确认）期间 `Menu_Quest_mKeyPressed` 只认 -5／−16，左按钮的 -3 不会开图。
	if _confirming or _closing:
		return
	var regions: Array = _quest.get("region_ids", [])
	if regions.is_empty():
		host.notice = host._menu_text(Msg.Id.QUEST_NO_REGION_INFO)
		return
	# `Menu_Quest_mKeyPressed`（0x4D080–0x4D086）：`Map_worldINIT(JC_fxtQINDEX(res, 3, 0), 1)`，
	# 初始焦点是任务的第一个关联地域；同一份文本资源的分页交给 `Menu_world_Draw(quests, …)` 画标记。
	host._open_world_map(int(regions[0]), _quest.get("pages", []))


func _open_confirm() -> void:
	if _confirming or _closing or int(_quest.get("id", -1)) < 0:
		return
	_confirming = true
	_choice = CHOICE_YES
	$Confirm/Content/Prompt.text = host._menu_text(Msg.Id.QUEST_ABANDON_PROMPT)
	_render_confirm()
	$Confirm.show()
	$Confirm.open_window()


func _render_confirm() -> void:
	$Confirm/Content/Yes/Choice.present(host._menu_text(Msg.Id.ANSWER_YES), _choice == CHOICE_YES)
	$Confirm/Content/No/Choice.present(host._menu_text(Msg.Id.ANSWER_NO), _choice == CHOICE_NO)


func _choose(choice: int) -> void:
	if not _confirming or _closing:
		return
	if _choice == choice:
		_resolve_confirm()
		return
	_choice = choice
	_render_confirm()


## `0x4D096`：光标 0（是）清槽并回列表；其余只收框，`Menu_Quest_mRun` 之后把层号写回 1（详情）。
func _resolve_confirm() -> void:
	if _choice != CHOICE_YES:
		_start_confirm_close(false)
		return
	var quest_id := int(_quest.get("id", -1))
	# 原生先清槽再置层号 0，列表重画时该槽已经不在（`Menu_Quest_mKeyPressed` 的清槽分支）。
	host._pages.quest.discard_quest(quest_id)
	_start_confirm_close(true)


## 收拢：相位 −1 起，`_on_confirm_transition_finished` 收到 opened = false 才算收完。
func _start_confirm_close(leaving: bool) -> void:
	if _closing:
		return
	_closing = true
	_leaving = leaving
	if leaving:
		# 清槽后层号立刻置 0：列表先画出来，收拢中的框叠在上面（`Menu_Quest_Draw` 的 LABEL_9）。
		$Bounds.hide()
		host.quest_detail_open = false
		host.notice = ""
		host._pages.quest.show()
		host._pages.quest._render_quest()
	$Confirm.close_window()


func _on_confirm_transition_finished(opened: bool) -> void:
	if opened:
		return
	$Confirm.hide()
	_closing = false
	_confirming = false
	if not _leaving:
		return
	_leaving = false
	_opening = true
	$Bounds.show()
	host._render_content()


## 换任务／离开详情层时把确认框直接复位（不走动画）。
func _reset_confirm() -> void:
	_confirming = false
	_closing = false
	_leaving = false
	$Confirm.hide()


## 详情层与确认层的 CLR 都回列表（`Menu_Quest_mKeyPressed` 把层号 `MenuData+0xC` 置 0）。
func _close_to_list() -> void:
	_reset_confirm()
	_opening = true
	host.quest_detail_open = false
	host.notice = ""
	host._render_content()
