extends "res://field/monster_work_window/monster_work_window.gd"

## 原生 `GAME_STATE_MONSTER_ENCHANT`（23，`GameCanvas` 落点页；精灵管理所游标 1 的 −5 进入）：
## `Game_Monster_Enchant_init` 建显示表（`Game_Monster_SetList(1)`＝含出战精灵的整包）、
## `_SetJewel` 建强化剂表；`_mPaint` → `_Draw`；`_mKeyPressed`
## 的六个子状态；`_mRun` 在相位 −4 时 `GameCanvas_SetNext(GAME_STATE_MONSTER_LIST, 1)`
## （关窗回精灵管理所，游标停在「精灵强化」那一行）。
##
## 窗口 `Menu_win_Box4_DrawWindow(228, 240, …, side 1, header 16)` ⇒ 400×240 下矩形 (86, 0, 228, 240)，
## 两处写回矩形都是**窗口本身**（`Menu_win_Box4_Draw` 的 `JC_rtSET(out, x, y, w, h)`），
## 所以 `_Draw` 里的基准是 `v43 = 86 + 4 = 90`、`v4 = 0 + 20 = 20`、`x = 228 − 8 = 220`：
## - 标题 `msg 121` @ (200, 11)；副标题 `msg 124` @ (x/2 + 90, 27)，只在子状态 0／2／3／4／5 画；
## - 精灵表 `Game_Monster_DrawList` @ (94, 43)，6 列 × 1 行（面板 212×47，底部 12 px 条放
##   持有数与金币），格子 30×30 @ (98 + 32c, 46)；
## - 资料条 `Game_Monster_DrawInfo1` @ (94, 92) 212×29：等级条 (97, 96) 68×7、
##   亲密度条 (97, 110) 68×7、名字 (169, 108)；
## - 确认框（子状态 1）面板 (94, 22) 212×99，两个 112×18 按钮 @ (144, 33)／(144, 66)，
##   分隔线 (97, 93) 206×1，`msg 125` + 概率 @ (106, 102)，`msg 126` + 费用 100 @ (203, 102)；
## - 强化剂表（子状态 2）面板 (94, 43) 212×78，6 格 @ (97 + 32c, 46)，分隔线 (97, 78)，
##   名称 (103, 82)、说明 (106, 95)；
## - 子状态 3／4／5 复用精灵表 + `Game_Monster_DrawInfo2`（`msg 106`／`108`／`110`）。
##
## 关窗（`Game_Monster_Enchant_mRun` 相位 −4）回 `GAME_STATE_MONSTER_LIST`(21) 且 `transition = 1`
## ——关窗只是回上一页，不是回野外。

signal completed

## `GameData.current_state_index_bits + 1`（原生 `current_state_index_bits[1]`）的六个子状态。
enum Phase {
	MONSTER = 0,   ## 精灵表，`48`／−5 选精灵
	CONFIRM = 1,   ## 两个按钮：0 选强化剂、1 强化
	ITEM = 2,      ## 强化剂表
	RUNNING = 3,   ## 强化中（`transition_parameter_bits + 7` 逐帧 +1，> 24 结算）
	FAILED = 4,    ## `_Proc` 返回 0
	SUCCEEDED = 5, ## `_Proc` 返回 1
}

## `transition_parameter_bits + 6`：确认框的游标。
enum Choice { ITEM = 0, RUN = 1 }

## `Game_Monster_Enchant_mKeyPressed` 子状态 1 的金额门槛：`ParamData.money_balance > 0x63`。
const FEE_MINIMUM_MONEY := MonsterGrowth.FEE - 1
## `ParamData.ability_values[1]`：强化成功率加成分片读的槽（合成页读槽 0）。
const ABILITY_VALUE_INDEX := 1

var sub_state := Phase.MONSTER
var choice := Choice.ITEM
## `ItemData.selected_enchant_item_0`：非 −1 表示选了超级强化剂（`kind 7` 的 19 号）。
var selected_super := false
## `ItemData.selected_enchant_item_1` 的定义号，−1 表示没选。
var orb_index := -1


func _ready() -> void:
	super()
	$RunPlayer.animation_finished.connect(_run_finished)
	$Content/Confirm/Option0.pressed.connect(_choose.bind(Choice.ITEM))
	$Content/Confirm/Option1.pressed.connect(_choose.bind(Choice.RUN))
	for slot in range(MONSTER_COLUMNS):
		_ball(slot).pressed.connect(_select_monster.bind(slot))
	for slot in range(VISIBLE_ITEMS):
		_item_cell(slot).pressed.connect(_select_item.bind(slot))


func present(story: Object, assets: Node) -> void:
	_story = story
	_assets = assets
	sub_state = Phase.MONSTER
	cursor = 0
	item_cursor = 0
	choice = Choice.ITEM
	selected_super = false
	orb_index = -1
	_closing = false
	$Bounds/Title.text = _text(Msg.Id.MONSTER_ENCHANT_TITLE)
	$Content/Subtitle.text = _text(Msg.Id.MONSTER_ENCHANT_SUBTITLE)
	$Content/Confirm/Option0/Label.text = _text(Msg.Id.MONSTER_ENCHANT_ITEM)
	$Content/Confirm/Option1/Label.text = _text(Msg.Id.MONSTER_ENCHANT_RUN)
	$Content/Confirm/PercentLabel.text = _text(Msg.Id.MONSTER_ENCHANT_PERCENT)
	$Content/Confirm/FeeLabel.text = _text(Msg.Id.MONSTER_ENCHANT_FEE)
	$Content/Confirm/Percent.configure(assets)
	$Content/ListCount.configure(assets)
	_monsters = story.progress.get("monsters", [])
	_rebuild_items()
	_refresh()
	show()
	open_window()


func handle_key(key: String) -> bool:
	if _closing or is_transitioning():
		return true
	match sub_state:
		Phase.MONSTER:
			return _key_monster(key)
		Phase.CONFIRM:
			return _key_confirm(key)
		Phase.ITEM:
			return _key_item(key)
		Phase.RUNNING:
			return true
		_:
			# 子状态 4／5：`-16`／`-5` 都只回子状态 0。
			if key == "Enter" or key == "Space" or key == "Escape" or key == "Backspace":
				sub_state = Phase.MONSTER
				_refresh()
				return true
			return false


## 子状态 0：−1 上、−2 下（×6）、−3 左、−4 右、−5／48 选精灵、−16 关页。
func _key_monster(key: String) -> bool:
	var count := _monsters.size()
	match key:
		"ArrowUp":
			return _move_monster(-MONSTER_COLUMNS, count)
		"ArrowDown":
			return _move_monster(MONSTER_COLUMNS, count)
		"ArrowLeft":
			return _move_monster(-1, count)
		"ArrowRight":
			return _move_monster(1, count)
		"Enter", "Space":
			if count > cursor:
				_choose_monster()
			return true
		"Escape", "Backspace":
			close()
			return true
		_:
			return false


## 子状态 1：−1／−2 在两项间循环，−5 按游标走「选强化剂」／「强化」，−16 回子状态 0。
func _key_confirm(key: String) -> bool:
	match key:
		"ArrowUp", "ArrowDown":
			choice = (choice + 1) % CHOICE_COUNT
			_refresh()
			return true
		"Enter", "Space":
			_confirm()
			return true
		"Escape", "Backspace":
			sub_state = Phase.MONSTER
			selected_super = false
			orb_index = -1
			_refresh()
			return true
		_:
			return false


## 子状态 2：−1／−2 换页（×6）、−3／−4 单格、−5 选中／取消、−16 回子状态 1。
func _key_item(key: String) -> bool:
	var span := _item_span()
	match key:
		"ArrowLeft":
			return _move_item(-1, span)
		"ArrowRight":
			return _move_item(1, span)
		"ArrowUp":
			return _move_item(-VISIBLE_ITEMS, span)
		"ArrowDown":
			return _move_item(VISIBLE_ITEMS, span)
		"Enter", "Space":
			_toggle_item()
			return true
		"Escape", "Backspace":
			sub_state = Phase.CONFIRM
			_refresh()
			return true
		_:
			return false


func _move_monster(step: int, count: int) -> bool:
	if count <= 0:
		return true
	cursor = posmod(cursor + step, count)
	_refresh()
	return true


## `48`／−5 选精灵：`brain_current >= brain_limit` 时只弹 `msg 127`，否则进确认框。
func _choose_monster() -> void:
	var monster: Dictionary = _monsters[cursor]
	if int(monster["brainCurrent"]) >= int(monster["brainLimit"]):
		MessageStack.say_record(Msg.Id.MONSTER_ENCHANT_FULL)
		return
	sub_state = Phase.CONFIRM
	choice = Choice.ITEM
	selected_super = false
	orb_index = -1
	_refresh()


## 子状态 1 的 `-5`：选项 0 → 强化剂表；选项 1 先查钱（`> 99`）再查强化剂（`_IsProc`）。
func _confirm() -> void:
	var monster: Dictionary = _monsters[cursor]
	if choice == Choice.ITEM:
		sub_state = Phase.ITEM
		item_cursor = 0
		_rebuild_items()
		_refresh()
		return
	if _money() <= FEE_MINIMUM_MONEY:
		MessageStack.say_record(Msg.Id.SHOP_NOT_ENOUGH_MONEY)
		return
	if not _ready_to_enhance(monster):
		MessageStack.say_record(Msg.Id.MONSTER_ENCHANT_SHORTAGE)
		return
	sub_state = Phase.RUNNING
	_refresh()
	$RunPlayer.play("run")


## `transition_parameter_bits + 7 > 24` 才调 `Game_Monster_Enchant_Proc`；原生按 paint 帧计数，
## 这里用 0.05 秒一帧的 `RunPlayer`（`run`，25 帧）复刻（`wiki\growth\game-monster-list.md` §7.3）。
func _run_finished(animation: StringName) -> void:
	if animation != &"run" or sub_state != Phase.RUNNING:
		return
	_resolve()


## `Game_Monster_Enchant_Proc`：掷骰加成 → 扣强化剂 → 扣钱 → 判定 → `Ball_stdBrain` → 存档。
func _resolve() -> void:
	var monster: Dictionary = _monsters[cursor]
	var species: MonsterDefinition = _catalog().monster(int(monster["species"]))
	var percent := MonsterGrowth.percent(int(monster["brainCurrent"]),
		orb_index if orb_index >= 0 else -1)
	var bonus := MonsterGrowth.ability_bonus(_ability(), MonsterGrowth.grade_of(species),
		randi() % MonsterGrowth.ROLL_MODULUS)
	if bonus > 0:
		percent += bonus
		MessageStack.say_record(Msg.Id.MONSTER_ENCHANT_BONUS, [bonus])
	var need := MonsterGrowth.enhancer_requirement(species, int(monster["brainCurrent"]),
		_super_ready())
	_story.consume_item(int(need["id"]), int(need["count"]))
	if orb_index >= 0 and _orb_item_id() >= 0:
		_story.consume_item(_orb_item_id(), 1)
	_story.progress["parameter"]["moneyBalance"] = maxi(0, _money() - MonsterGrowth.FEE)
	selected_super = false
	orb_index = -1
	var success := MonsterGrowth.is_success(percent,
		randi() % MonsterGrowth.ROLL_MODULUS)
	MonsterGrowth.apply_brain(monster, success)
	sub_state = Phase.SUCCEEDED if success else Phase.FAILED
	completed.emit()
	_rebuild_items()
	_refresh()


## `Game_Monster_Enchant_GetJewel` 的槽 0：超级强化剂还在包里才算选中，否则回默认强化剂。
func _super_ready() -> bool:
	return selected_super and _owned(ItemKind.id_of(ItemKind.Kind.GROUP_7,
		MonsterGrowth.SUPER_ENHANCER_INDEX)) > 0


## `Game_Monster_Enchant_IsProc`：槽 0 够不够这一只的消耗。
func _ready_to_enhance(monster: Dictionary) -> bool:
	var species: MonsterDefinition = _catalog().monster(int(monster["species"]))
	return MonsterGrowth.is_ready(_inventory(), species, int(monster["brainCurrent"]),
		_super_ready())


## 子状态 2 的 `-5`：超级强化剂进槽 0，其余进槽 1（同名再按一次取消）。
func _toggle_item() -> void:
	if item_cursor >= _items.size():
		sub_state = Phase.CONFIRM
		_refresh()
		return
	var item_id := _items[item_cursor]
	if MonsterGrowth.is_super_enhancer(item_id):
		selected_super = not selected_super
	else:
		var index := ItemKind.index_of(item_id)
		orb_index = -1 if orb_index == index else index
	_refresh()


func _select_monster(slot: int) -> void:
	if _closing or is_transitioning() or slot >= _monsters.size():
		return
	if sub_state != Phase.MONSTER:
		return
	cursor = slot
	_choose_monster()


func _select_item(slot: int) -> void:
	if _closing or is_transitioning() or sub_state != Phase.ITEM:
		return
	# 空道具格现在也画出来（原生照画空位格底），点它不应切换选中道具。
	if slot >= _items.size():
		return
	item_cursor = slot
	_toggle_item()


func _choose(index: int) -> void:
	if _closing or is_transitioning() or sub_state != Phase.CONFIRM:
		return
	choice = index
	_confirm()


func _rebuild_items() -> void:
	# 原生 `Item_bagList(0)` 的袋内顺序就是道具号升序（见 `shop_goods.gd` 的卖页说明）。
	_items = _owned_item_ids(MonsterGrowth.is_enhancer)
	item_cursor = clampi(item_cursor, 0, maxi(0, _items.size() - 1))


func _refresh() -> void:
	$Content/Subtitle.visible = sub_state != Phase.CONFIRM
	$Content/ListFrame.visible = sub_state != Phase.CONFIRM and sub_state != Phase.ITEM
	$Content/ListStrip.visible = $Content/ListFrame.visible
	$Content/ListMoney.visible = $Content/ListFrame.visible
	$Content/ListCount.visible = $Content/ListFrame.visible
	$Content/Info.visible = sub_state != Phase.CONFIRM and sub_state != Phase.ITEM
	$Content/Confirm.visible = sub_state == Phase.CONFIRM
	$Content/Items.visible = sub_state == Phase.ITEM
	$Content/Confirm/Option0/Inner.modulate = Color.WHITE if choice == Choice.ITEM \
		else Color("#186385")
	$Content/Confirm/Option0/Outer.modulate = $Content/Confirm/Option0/Inner.modulate
	$Content/Confirm/Option1/Inner.modulate = Color.WHITE if choice == Choice.RUN \
		else Color("#186385")
	$Content/Confirm/Option1/Outer.modulate = $Content/Confirm/Option1/Inner.modulate
	$Content/Confirm/Percent.present(str(MonsterGrowth.percent(_brain_current(),
		orb_index if orb_index >= 0 else -1)))
	$Content/Confirm/Fee/Number.present(str(MonsterGrowth.FEE))
	$Content/ListMoney/Number.present(str(_money()))
	$Content/ListCount.present("%d/%d" % [mini(_monsters.size(), MONSTER_COLUMNS),
		_monsters.size()])
	_refresh_monster_cells()
	_refresh_info()
	_refresh_item_cells()


## 出战位（`partyOrder` 里的下标）画角标。
func _monster_marked(slot: int, _entry: Dictionary) -> bool:
	var order: Array = _story.progress.get("partyOrder", [])
	return order.has(slot)


## `equipment_code > 0`；工程里装备索引用 −1 表示没有，所以判 `>= 0`。
func _monster_equipped(_slot: int, entry: Dictionary) -> bool:
	var arguments: Variant = entry.get("nativeArguments", [])
	return arguments is Array and arguments.size() > 3 and int(arguments[3]) >= 0


func _refresh_info() -> void:
	var monster: Dictionary = _monsters[cursor] if cursor < _monsters.size() else {}
	var species: MonsterDefinition = _catalog().monster(int(monster.get("species", -1))) \
		if not monster.is_empty() else null
	var name := ""
	if species != null:
		name = _monster_name(species, int(monster.get("nickname", -1)))
	$Content/Info/Name.text = name
	$Content/Info/Level/Number.present(str(int(monster.get("level", 0))))
	$Content/Info/Brain/Number.present("%d/%d" % [int(monster.get("brainCurrent", 0)),
		int(monster.get("brainLimit", 0))])
	var result := ""
	match sub_state:
		Phase.RUNNING:
			result = _text(Msg.Id.MONSTER_ENCHANT_RUNNING)
		Phase.FAILED:
			result = _text(Msg.Id.MONSTER_ENCHANT_FAILED)
		Phase.SUCCEEDED:
			result = _text(Msg.Id.MONSTER_ENCHANT_SUCCEEDED)
	$Content/Info/Result.text = result
	$Content/Info/Result.visible = not result.is_empty()
	for node: Control in [$Content/Info/Name, $Content/Info/Level, $Content/Info/Brain]:
		node.visible = result.is_empty()


func _marked_item(item_id: int) -> bool:
	if MonsterGrowth.is_super_enhancer(item_id):
		return selected_super
	return orb_index >= 0 and ItemKind.index_of(item_id) == orb_index


func _orb_item_id() -> int:
	return ItemKind.id_of(ItemKind.Kind.GROUP_7, orb_index) if orb_index >= 0 else -1


## `ParamData.ability_values[1]`：与 `wild_encounters.gd` 的 `allocated[2]`（捕获）同一组下标。
func _ability() -> int:
	return _allocated_value(ABILITY_VALUE_INDEX)


func _brain_current() -> int:
	return int(_monsters[cursor]["brainCurrent"]) if cursor < _monsters.size() else 0
