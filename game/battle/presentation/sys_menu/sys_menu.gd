extends Control
## 战斗内系统菜单：原生状态 30 CLEAR 的 4 项「设定」列表，以及它分派到的
## 31 SETUP（环境设定）／32 METHOD（帮助）／33 MAINMENU（主菜单）。
##
## 入口是原生的：指令菜单按 CLR（`a1 == -16`）——`Battle_Menu_mKeyPressed` 的
## `case 0` 把子状态置 2、把菜单动作码置 8，`Battle_Menu_mRun` 随即
## `BattleCanvas_SetNext(BATTLE_STATE_CLEAR, 0)`。CLEAR 的 4 项列表就是本覆盖层的根页，
## 它的游标被 `Battle_Clear_mKeyPressed` 写进 `current_state_index+2`，
## `Battle_Clear_mRun` 再按这个返回码分派 MENU／SETUP／METHOD／MAINMENU（`ReturnCode`）。
## 三个子页关窗时各自 `SetNext(BATTLE_STATE_CLEAR, 1／2／3)`，所以「返回」会回到列表、
## 并把游标停在自己那一行（本页的 `cursor`）。
##
## 环境设定与帮助两页直接复用 Prime 侧的实现（`prime/settings_view.tscn`、
## `prime/text_page_view.tscn`）：原生这两个状态（`Battle_Setup_mPaint` →
## `Menu_Setup_Draw`、`Battle_Method_mPaint` → `Menu_info1_Draw`）与 Prime 的
## 环境设定／方式页画的是同一套 Box4 窗框、同一批行与正文。

signal closed
## 主菜单的「是」：原生 `Battle_MainMenu_mRun` 返回码 1 调 `Game_out()`，
## 单机战斗在那里只做 `EFC_mainSetNEXT(CANVAS_PRIME, PRIME_STATE_TITLE)`——回标题，
## 不经过野外地图、不结算、不写存档。见 `wiki\battle\battle-exit.md`。
signal title_requested
## 环境设定改值当场生效的请求（`Menu_Setup_mKeyPressed`：音量行 `EFC_mdaVOLUME` 之后
## `EFC_mdaPlayDATA(123)` 试听、振动行 `EFC_mdaVIBRATE`）。哪一行要产生什么效果由启动层的
## `main.gd.apply_setting_change` 决定（与 Prime 设置页同一处），本覆盖层只报「哪一行从多少改到多少」。
## 落盘不在这里：CLR 才 `Param_setupSAVE()`。
signal setting_changed(settings: Dictionary, key: String, previous_value: int)

const Layout = preload("res://game/prime/ui/layout/layout.gd")
const PrimeConstants = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const SettingsStore = preload("res://game/prime/settings/prime_settings_store/prime_settings_store.gd")
const TextLayout = preload("res://engine/ui/native_text_layout/native_text_layout.gd")
const BattleView = preload("res://game/battle/presentation/battle_view/battle_view.gd")
## 帮助页正文源（`Battle_Method_init` 的 `EFC_fsLoadRES("skt/method.fxt")`）。
const HELP_SOURCE := "skt/method.fxt"
## 帮助页正文的原生折行宽度（`Menu_info1_Draw` 的正文框；Prime 方式页同样是 173）。
const HELP_TEXT_WIDTH := 173.0
## 帮助页正文源两两成对（标题、正文）：条目数就是 `JC_fxtCOUNT(...) / 2`
## （`Battle_Method_init`）。
const HELP_RECORD_STRIDE := 2
## 帮助页正文的可视行数，与 `page_navigation.tscn` 的 `visible_lines` 一致。
const HELP_VISIBLE_LINES := 12
## 未选中行的框色与字色（`Game_Menu_List_Draw` 的 `JC_grpSetRGB`）。
const BORDER := Color("#196485")
const SELECTED_BORDER := Color("#7ad0fa")

## 覆盖层内部的页。`CLEAR` 是入口列表（原生状态 30），其余三页对应原生 31／32／33。
enum Page {
	CLEAR,
	SETUP,
	METHOD,
	MAINMENU,
}

## `Battle_Clear_mRun` 分派用的返回码：取值就是 CLEAR 列表的游标，
## `MENU` 表示回战斗指令菜单（`BattleCanvas_SetNext(BATTLE_STATE_MENU, 0)`）。
enum ReturnCode {
	MENU = 0,
	SETUP = 1,
	METHOD = 2,
	MAINMENU = 3,
}

## 主菜单 是／否 的游标（`Menu_win_Box2_DrawSelect` 里的 msg 85／86 两个按钮）。
enum PromptChoice {
	YES = 0,
	NO = 1,
}

## CLEAR 列表的文案记录走 `Msg.Id.BATTLE_CLEAR_*`（`Battle_Clear_mPaint`：标题
## `JC_fxt2Return(31)`、四行 `JC_fxt2Return(32..35)`）。
## 列表行序＝游标＝返回码：`Battle_Clear_mKeyPressed` 直接把游标当返回码。
const ITEM_IDS: Array[int] = [Msg.Id.BATTLE_CLEAR_CONTINUE, Msg.Id.BATTLE_CLEAR_SETTINGS,
	Msg.Id.BATTLE_CLEAR_HELP, Msg.Id.BATTLE_CLEAR_MAIN_MENU]
const ROW_NAMES: Array[String] = ["Option0", "Option1", "Option2", "Option3"]
## 关窗后没有下一页：整层收回，把控制权交还战斗。
const NO_PAGE := -1

var page := Page.CLEAR
## CLEAR 列表的游标（原生 `BattleData.transition_parameter_bits`）。
var cursor := 0
## 环境设定的行游标（原生 `Battle_Setup_init` 的 `transition_parameter_bits`）。
var settings_selected := 0
## 环境设定的当前值，键与 `PrimeSettingsStore.DEFAULTS` 一致。
var settings: Dictionary = {}
## `text_page_view.configure` 需要的正文资源表与错误位。Godot 侧用属性传递，不必再建中间对象。
var messages: Dictionary = {}
var last_error := ""

var _assets: Node
var _help_pages: Array = []
var _help_index := 0
var _help_scroll := 0
var _prompt_selected := PromptChoice.NO
var _opened := false
var _presenting := false
## 关窗动画结束后要进的页；`NO_PAGE` 表示关闭整个覆盖层回战斗。
var _pending_page := NO_PAGE
## 回到 CLEAR 时的游标（原生 `SetNext(BATTLE_STATE_CLEAR, n)` 的 n）。
var _pending_cursor := 0
var _exit_after_close := false


func _ready() -> void:
	$List.hide()
	$Prompt.hide()
	for window: Node in [$List, $Prompt, $Settings, $Method/Frame]:
		window.transition_finished.connect(_transition_finished)
	$Settings.phase_changed.connect(_phase_changed)
	$Method/Frame.phase_changed.connect(_phase_changed)
	$List/Content/Option0.pressed.connect(_select.bind(0))
	$List/Content/Option1.pressed.connect(_select.bind(1))
	$List/Content/Option2.pressed.connect(_select.bind(2))
	$List/Content/Option3.pressed.connect(_select.bind(3))
	$Prompt.chosen.connect(_on_prompt_choice)


## 建档：正文表、设置项、帮助页与两个复用页的图元。返回 false 时本覆盖层不开放。
func configure(assets: Node) -> bool:
	_assets = assets
	messages = assets.text_messages(Msg.SOURCE)
	settings = SettingsStore.load_settings()
	if not _load_help_pages():
		push_error("战斗系统菜单：skt/method.fxt 无法解析为标题／正文对。")
		return false
	if not $Settings.configure(assets, messages):
		return false
	if not $Method.configure(self, assets):
		return false
	_render_list()
	return true


## `Battle_Clear_init`：进入列表页，游标沿用调用方给的返回码。
func open(position: int = ReturnCode.MENU) -> void:
	if _opened:
		return
	_opened = true
	show()
	_pending_page = NO_PAGE
	_pending_cursor = 0
	_exit_after_close = false
	cursor = position
	_enter(Page.CLEAR)


func is_open() -> bool:
	return _opened


## 新的战斗开始时复位（`battle_view.start()` 会调）：停掉残留的开合动画并整层收回。
func reset() -> void:
	for window: Node in [$List, $Prompt, $Settings, $Method/Frame]:
		window.get_node("AnimationPlayer").stop()
	_leave()


## `EFC_mainTouchSTYLE` 的 `BATTLE_STATE_CLEAR`／`SETUP`（0x1803，方向盘＋CLR＋确认）
## 与 `BATTLE_STATE_METHOD`（0x1003，方向盘＋CLR）。MAINMENU 在原生里返回 0，但
## `Menu_win_Box2_DrawSelect` 自己 `EFC_mainTouchSET` 了是／否两块，所以这里给 SELECT。
func touch_style() -> int:
	match page:
		Page.METHOD:
			return BattleView.TouchStyle.INFO
		Page.CLEAR, Page.SETUP, Page.MAINMENU:
			return BattleView.TouchStyle.SELECT
	return 0


func handle_key(key: String) -> bool:
	if not _opened:
		return false
	if _busy():
		return true
	match page:
		Page.CLEAR:
			_list_key(key)
		Page.SETUP:
			_setup_key(key)
		Page.METHOD:
			_method_key(key)
		Page.MAINMENU:
			_prompt_key(key)
	return true


## `Battle_Clear_mKeyPressed`：−1／−2 移动游标（`±1 mod 4`）、−5 用游标当返回码、
## −16 回返回码 0。列表只有上下，没有左右。
func _list_key(key: String) -> void:
	match key:
		"ArrowUp":
			cursor = posmod(cursor - 1, ITEM_IDS.size())
			_render_list()
		"ArrowDown":
			cursor = posmod(cursor + 1, ITEM_IDS.size())
			_render_list()
		"Enter", "Space":
			_dispatch(cursor)
		"Escape", "Backspace":
			_dispatch(ReturnCode.MENU)


## `Battle_Clear_mRun`：返回码 0 回战斗，1／2／3 进 SETUP／METHOD／MAINMENU。
func _dispatch(code: int) -> void:
	if code == ReturnCode.MENU:
		_close_to(NO_PAGE)
		return
	_close_to(_page_of(code))


## `Battle_Setup_mKeyPressed` + `Menu_Setup_mKeyPressed`：
## −1／−2 由页面自己移动行游标，−3／−4／−5 改当前行的值，−16 先 `Param_setupSAVE()` 再关窗。
func _setup_key(key: String) -> void:
	match key:
		"ArrowUp":
			settings_selected = posmod(settings_selected - 1, Layout.SETTINGS_ROW_COUNT)
			_refresh_pages()
		"ArrowDown":
			settings_selected = posmod(settings_selected + 1, Layout.SETTINGS_ROW_COUNT)
			_refresh_pages()
		"ArrowLeft":
			_adjust_setting(-1)
		"ArrowRight", "Enter", "Space":
			_adjust_setting(1)
		"Escape", "Backspace":
			SettingsStore.save_settings(settings)
			_close_to(Page.CLEAR, ReturnCode.SETUP)


## 行的值按 `PrimeSettingsStore.RANGES` 轮回；原生每行的取值范围与它一致
## （`ThreadData.speed_index` %5、`MdaData[232]` %3、音量 6 档、`vibration_option` &3、
## `ParamRes.menu_choice_4_bits` &1）。行序沿用 `DEFAULTS` 的声明顺序，与
## `settings_content` 的标题 202..206（速度／声音／音量／震动／画面）一致。
func _adjust_setting(direction: int) -> void:
	var key: String = String(SettingsStore.DEFAULTS.keys()[settings_selected])
	var limit: Vector2i = SettingsStore.RANGES[key]
	var span := limit.y - limit.x + 1
	var previous := int(settings[key])
	settings[key] = limit.x + posmod(previous - limit.x + direction, span)
	_refresh_pages()
	setting_changed.emit(settings.duplicate(true), key, previous)


## `Battle_Method_mKeyPressed`：−3／−4 换条目（并把滚动归 0）、−1／−2 滚正文、
## −16 关窗；确认键在这一页是空操作（`case 11` 直接 return）。
func _method_key(key: String) -> void:
	match key:
		"ArrowRight":
			_help_index = posmod(_help_index + 1, _help_pages.size())
			_help_scroll = 0
			_refresh_pages()
		"ArrowLeft":
			_help_index = posmod(_help_index - 1, _help_pages.size())
			_help_scroll = 0
			_refresh_pages()
		"ArrowDown":
			_help_scroll = clampi(_help_scroll + 1, 0, _help_scroll_limit())
			_refresh_pages()
		"ArrowUp":
			_help_scroll = clampi(_help_scroll - 1, 0, _help_scroll_limit())
			_refresh_pages()
		"Escape", "Backspace":
			_close_to(Page.CLEAR, ReturnCode.METHOD)


## `Battle_MainMenu_mKeyPressed`：只有两项（是／否），−3／−4 都是 `(游标 + 1) % 2`；
## −5 按游标写返回码（是 → `Game_out()`，否 → 回 CLEAR 并把游标停在主菜单那行）；−16 同「否」。
func _prompt_key(key: String) -> void:
	match key:
		"ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown":
			$Prompt.move_selection(-1)
			_prompt_selected = $Prompt.selection()
		"Enter", "Space":
			$Prompt.accept()
		"Escape", "Backspace":
			$Prompt.cancel()


func _on_prompt_choice(accepted: bool) -> void:
	if _busy():
		return
	_prompt_selected = PromptChoice.YES if accepted else PromptChoice.NO
	if accepted:
		_close_to(NO_PAGE, 0, true)
		return
	_close_to(Page.CLEAR, ReturnCode.MAINMENU)


func _select(index: int) -> void:
	if _busy() or page != Page.CLEAR:
		return
	if index == cursor:
		_dispatch(cursor)
		return
	cursor = index
	_render_list()


## 关窗：`next < 0` 表示回战斗；`next_cursor` 是落回 CLEAR 时的游标。
## `exit_after` 表示关窗之后不再进任何页，而是把「离开这一战回标题」交给调用方
## （主菜单「是」＝原生 `Game_out()`，见 `wiki\battle\battle-exit.md`）。
func _close_to(next: int, next_cursor: int = 0, exit_after := false) -> void:
	if _busy():
		return
	_pending_page = next
	_pending_cursor = next_cursor
	_exit_after_close = exit_after
	match page:
		Page.CLEAR:
			$List.close_window()
		Page.SETUP:
			$Settings.close_window()
		Page.METHOD:
			$Method/Frame.close_window()
		Page.MAINMENU:
			$Prompt.close_window()


## `Battle_Setup_mRun`／`Battle_Method_mRun`／`Battle_MainMenu_mRun`
## 与 `Battle_Clear_mRun` 都在相位收拢到 -4 之后才切页，这里是同一步。
func _transition_finished(opened: bool) -> void:
	if opened:
		_refresh_pages()
		return
	if _exit_after_close:
		_exit_after_close = false
		_leave()
		title_requested.emit()
		return
	if _pending_page == NO_PAGE:
		_leave()
		closed.emit()
		return
	var next := _pending_page
	_pending_page = NO_PAGE
	cursor = _pending_cursor
	_enter(next)


func _enter(next: int) -> void:
	page = next
	match next:
		Page.CLEAR:
			$List.show()
			_render_list()
			$List.open_window()
		Page.SETUP:
			# `BattleCanvas_SetNext` 进新状态时把 transition_parameter 及其 +1..+5 清零，
			# 所以每次进环境设定都从第 0 行开始。
			settings_selected = 0
			$Settings.open_window()
		Page.METHOD:
			_help_index = 0
			_help_scroll = 0
			$Method/Frame.open_window()
		Page.MAINMENU:
			# `Battle_MainMenu_init` 把游标置 1（＝「否」）。
			_prompt_selected = PromptChoice.NO
			$Prompt.show()
			_render_prompt()
			$Prompt.open_window()


func _leave() -> void:
	_opened = false
	_pending_page = NO_PAGE
	cursor = ReturnCode.MENU
	$List.hide()
	$Prompt.hide()
	$Settings.hide()
	$Method.hide()
	hide()


func _busy() -> bool:
	return $List.is_transitioning() or $Prompt.is_transitioning() or \
		$Settings.is_transitioning() or $Method/Frame.is_transitioning()


func _phase_changed(_value: int) -> void:
	_refresh_pages()


func _refresh_pages() -> void:
	if _presenting:
		return
	_presenting = true
	match page:
		Page.SETUP:
			$Settings.present({"scene": PrimeConstants.SETTINGS,
				"window_state": $Settings.phase, "settings": settings,
				"settings_selected": settings_selected})
		Page.METHOD:
			$Method.present({"scene": PrimeConstants.METHOD,
				"window_state": $Method/Frame.phase, "page": _help_pages[_help_index],
				"page_index": _help_index, "page_count": _help_pages.size(),
				"page_scroll": _help_scroll, "modal_state": 0})
	_presenting = false


func _render_list() -> void:
	$List/Bounds/Title.text = _text(Msg.Id.BATTLE_CLEAR_TITLE)
	for index in range(ITEM_IDS.size()):
		var card: Button = $List/Content.get_node(ROW_NAMES[index])
		var chosen: bool = index == cursor
		card.get_node("Label").text = _text(ITEM_IDS[index])
		card.get_node("Label").color = Color.WHITE if chosen else BORDER
		var border: Color = SELECTED_BORDER if chosen else BORDER
		card.get_node("Inner").modulate = border
		card.get_node("Outer").modulate = border


func _render_prompt() -> void:
	$Prompt.present_select(_text(Msg.Id.RETURN_TO_MENU), _prompt_selected)


func _text(id: int) -> String:
	return _assets.text_message(Msg.SOURCE, id)


func _page_of(code: int) -> int:
	match code:
		ReturnCode.SETUP:
			return Page.SETUP
		ReturnCode.METHOD:
			return Page.METHOD
		ReturnCode.MAINMENU:
			return Page.MAINMENU
	return Page.CLEAR


func _help_scroll_limit() -> int:
	if _help_pages.is_empty():
		return 0
	var lines: int = _help_pages[_help_index].lines.size()
	return maxi(0, lines - HELP_VISIBLE_LINES)


## 帮助页：`skt/method.fxt` 的记录两两成对（标题、正文），与 Prime 方式页同一份排版。
func _load_help_pages() -> bool:
	var resource: Variant = _assets.load_text(HELP_SOURCE)
	if not resource is Dictionary or not resource.get("records") is Array:
		return false
	var records: Array = resource.records
	if records.is_empty() or records.size() % HELP_RECORD_STRIDE != 0:
		return false
	var pages: Array = []
	for index in range(0, records.size(), HELP_RECORD_STRIDE):
		var heading: Dictionary = records[index]
		var body: Dictionary = records[index + 1]
		if not heading.get("text") is String:
			return false
		var text := String(body.get("text", "")) if body.get("text") is String else ""
		var title_layout := TextLayout.layout(heading.text, Layout.UI_FONT, Layout.FONT_SIZE,
			0.0, false, Color("#FFB655"))
		var body_layout := TextLayout.layout(text, Layout.UI_FONT, Layout.FONT_SIZE,
			HELP_TEXT_WIDTH, true)
		if not title_layout.error.is_empty() or not body_layout.error.is_empty():
			push_error("战斗系统菜单：%s:%d %s%s" % [HELP_SOURCE, index,
				title_layout.error, body_layout.error])
			return false
		var lines: Array[String] = []
		for line: Dictionary in body_layout.lines:
			lines.append(line.text)
		pages.append({"title": heading.text, "lines": lines,
			"title_line": title_layout.lines[0], "rich_lines": body_layout.lines})
	_help_pages = pages
	return true
