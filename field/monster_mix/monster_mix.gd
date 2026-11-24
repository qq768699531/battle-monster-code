extends "res://field/monster_work_window/monster_work_window.gd"

## 原生 `GAME_STATE_MONSTER_MIX`（22，精灵管理所游标 0 的 −5 进入）：
## `Game_Monster_Mix_init` 清四个选中槽 → `Game_Monster_SetList(0)`（**排除**出战三只）
## → `Mix_SetJewel` → 相位 1；`Game_Monster_Mix_mPaint` → `_Draw`；
## `_mKeyPressed` 的六个子状态；`_Proc` 结算；`_mRun` 相位 −4 →
## `GameCanvas_SetNext(GAME_STATE_MONSTER_LIST, 0)`（关窗回精灵管理所，游标停在「精灵合成」）。
##
## 窗口 `Menu_win_Box4_DrawWindow(228, 240, …, side 1, header 16)` ⇒ 400×240 下矩形 (86, 0, 228, 240)，
## 所以 `_Draw` 的基准是 `v51 = 86 + 4 = 90`、`v4 = 0 + 20 = 20`、`x = 228 − 8 = 220`：
## - 标题 `msg 111` @ (200, 11)；副标题 `msg 114` @ (200, 27)，除子状态 1 之外都画；
## - 精灵表 `Game_Monster_DrawList` @ (94, 43)，6 列 × 1 行；格子 30×30 @ (98 + 32c, 46)；
## - 资料条 `Game_Monster_DrawInfo1` @ (94, 92) 212×29；
## - 两只立绘 `Game_Monster_Mix_DrawMonster` @ (130, 204)／(270, 204)（合成机 `Object_drawBASIC`
##   的 kind 22 没有导出 ANI，本轮不画），已选合成石图标 @ (185, 157)；
## - 确认框（子状态 1）面板 (94, 22) 212×99，两个 112×18 按钮 @ (144, 33)／(144, 66)，分隔线
##   (97, 93) 206×1，`msg 115` + 概率 @ (106, 102)（右对齐到 x = 171）、`msg 116` + 200 @ (203, 102)；
## - 合成石表（子状态 2）面板 (94, 43) 212×78，6 格 @ (97 + 32c, 46)，分隔线 (97, 78)；
## - 子状态 3／4／5 复用精灵表 + `Game_Monster_DrawInfo2`（22 号页是 `msg 105`／`107`／`109`），
##   结果精灵 @ (200, 204)、爆点 `obj/b_effect` @ (164, 212)，名字与两条数值在 (246, 141)／(212, 181)／(212, 195)。
##
## 合成动画（子状态 3）：原生按 paint 帧把相位 `transition_parameter_bits + 7` 逐帧 +1，
## `v12 = min(59, 相位²)` 把两只向中间推并淡出，相位 > 24 时调 `_Proc`。移植侧用 0.05 秒一帧的
## `RunPlayer`「run」轨道复刻（与强化页同一做法），脚本只切状态、不自己计时。
##
## 关窗（`Game_Monster_Mix_mRun` 相位 −4）回 `GAME_STATE_MONSTER_LIST`(21) 且 transition 0
## （关窗回精灵管理所，游标停在「精灵合成」那一行）。

signal completed

const MonsterAnimation = preload("res://engine/anim/monster_animation/monster_animation.gd")
const Battle = preload("res://battle/combat/battle.gd")

## `GameData.current_state_index_bits + 1`（原生 `current_state_index_bits[1]`）的六个子状态。
enum Phase {
	MONSTER = 0,   ## 精灵表，−5／48 选两只
	CONFIRM = 1,   ## 两个按钮：0 选合成石、1 合成
	STONE = 2,     ## 合成石表
	RUNNING = 3,   ## 合成中（`transition_parameter_bits + 7` 逐帧 +1，> 24 结算）
	FAILED = 4,    ## `_Proc` 返回 0（品级降一级）
	SUCCEEDED = 5, ## `_Proc` 返回 1（品级升一级）
}

## `transition_parameter_bits + 6`：确认框的游标。
enum Choice { STONE = 0, RUN = 1 }
## `_Draw` 第 644–645 行：`++transition+7`，`> 24` 才调 `_Proc`——25 帧 × 0.05 秒的步长写在
## Scene 的「run」动画里（同强化页），脚本只切状态、不自己计时。
## `_mKeyPressed` case 11：`a1.kind_specific_84_bits == 5` 直接弹 `msg 117`。
const REFUSED_GRADE := MonsterMixTable.GRADE_MAX
## `_DrawMonster` 的朝向参数：主位传 2、副位传 1（`Object_drawSPRITE` 只把 1 当镜像档）。
const PRIMARY_DIRECTION := 2
const SECONDARY_DIRECTION := 1
## `_Draw` 第 562／568 行的爆点：失败固定用动作 34（`0x22`，语义未确认，按动作号），
## 成功那条把 `destination_y` 置 1，即 `obj/b_effect` 的动作 1。
const FAILED_EFFECT_ACTION := 34
const SUCCEEDED_EFFECT_ACTION := AniAction.Effect.CRITICAL

var sub_state := Phase.MONSTER
var choice := Choice.STONE
## `ItemData.mix_primary_monster`／`mix_secondary_monster`：存档 `monsters` 数组的下标，−1 表示空。
var primary_index := -1
var secondary_index := -1
## `ItemData.selected_enchant_item_0` 的定义号（4／5），−1 表示没选。
var stone_index := -1

var _outcome_record: Dictionary = {}
var _primary_home := 0.0
var _secondary_home := 0.0


func _ready() -> void:
	super()
	$RunPlayer.animation_finished.connect(_run_finished)
	$Content/Confirm/Option0.pressed.connect(_choose.bind(Choice.STONE))
	$Content/Confirm/Option1.pressed.connect(_choose.bind(Choice.RUN))
	for slot in range(MONSTER_COLUMNS):
		_ball(slot).pressed.connect(_select_monster.bind(slot))
	for slot in range(VISIBLE_ITEMS):
		_item_cell(slot).pressed.connect(_select_stone.bind(slot))
	_primary_home = $Content/Portraits/Primary.position.x
	_secondary_home = $Content/Portraits/Secondary.position.x


func present(story: Object, assets: Node) -> void:
	_story = story
	_assets = assets
	sub_state = Phase.MONSTER
	cursor = 0
	item_cursor = 0
	choice = Choice.STONE
	primary_index = -1
	secondary_index = -1
	stone_index = -1
	_outcome_record = {}
	_closing = false
	$Bounds/Title.text = _text(Msg.Id.MONSTER_MIX_TITLE)
	$Content/Subtitle.text = _text(Msg.Id.MONSTER_MIX_SUBTITLE)
	$Content/Confirm/Option0/Label.text = _text(Msg.Id.MONSTER_MIX_ITEM)
	$Content/Confirm/Option1/Label.text = _text(Msg.Id.MONSTER_MIX_RUN)
	$Content/Confirm/PercentLabel.text = _text(Msg.Id.MONSTER_MIX_PERCENT)
	$Content/Confirm/FeeLabel.text = _text(Msg.Id.MONSTER_MIX_FEE)
	$Content/Confirm/Percent.configure(assets)
	$Content/ListCount.configure(assets)
	_rebuild_monsters()
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
		Phase.STONE:
			return _key_stone(key)
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
	match key:
		"ArrowUp":
			return _move_cursor(-MONSTER_COLUMNS)
		"ArrowDown":
			return _move_cursor(MONSTER_COLUMNS)
		"ArrowLeft":
			return _move_cursor(-1)
		"ArrowRight":
			return _move_cursor(1)
		"Enter", "Space":
			_press_ok()
			return true
		"Escape", "Backspace":
			close()
			return true
		_:
			return false


## 子状态 1：−1／−2 在两项间循环，−5 按游标走「选合成石」／「合成」，−16 回子状态 0。
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
			stone_index = -1
			_refresh()
			return true
		_:
			return false


## 子状态 2：−1／−2 换页（×6）、−3／−4 单格、−5 选中／取消、−16 回子状态 1。
func _key_stone(key: String) -> bool:
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
			_toggle_stone()
			return true
		"Escape", "Backspace":
			sub_state = Phase.CONFIRM
			_refresh()
			return true
		_:
			return false


func _move_cursor(step: int) -> bool:
	if _monsters.is_empty():
		return true
	cursor = posmod(cursor + step, _monsters.size())
	_refresh()
	return true


## 子状态 0 的 −5：品级 5 弹 `msg 117`；按已选主位再按一次是「主位 ← 副位、副位清空」；
## 主位为空时置主位（带装备弹 `msg 118`）；否则置副位。
## 原生把 −5（键盘 OK）与 48（触控 OK）分成两条，48 只在两只都选好后才进确认框；
## 移植侧把两者都映射到 `Enter`：先走 −5，两只齐了再走 48（与强化页合并两键的做法一致）。
func _press_ok() -> void:
	if cursor >= _monsters.size():
		return
	var entry: Dictionary = _monsters[cursor]
	var species: MonsterDefinition = _catalog().monster(int(entry["species"]))
	if species == null:
		return
	if int(species.attribute_entry) >= REFUSED_GRADE:
		MessageStack.say_record(Msg.Id.MONSTER_MIX_REFUSED)
		return
	var index := int(entry["index"])
	if index == primary_index:
		primary_index = secondary_index
		secondary_index = -1
	elif primary_index < 0:
		primary_index = index
		if _has_equipment(entry):
			MessageStack.say_record(Msg.Id.MONSTER_MIX_EQUIPMENT)
	else:
		secondary_index = index
	_refresh()
	if primary_index >= 0 and secondary_index >= 0:
		sub_state = Phase.CONFIRM
		choice = Choice.STONE
		_refresh()


## 子状态 1 的 −5：选项 0 → 合成石表；选项 1 先查钱（`> 199`）再进合成。
func _confirm() -> void:
	if choice == Choice.STONE:
		sub_state = Phase.STONE
		item_cursor = 0
		_rebuild_items()
		_refresh()
		return
	if _money() <= MonsterMix.FEE_MINIMUM_MONEY:
		MessageStack.say_record(Msg.Id.SHOP_NOT_ENOUGH_MONEY)
		return
	sub_state = Phase.RUNNING
	_refresh()
	$RunPlayer.play("run")


## 子状态 2 的 −5：选中／取消合成石；该格没有道具时回确认框（原生递归 −16）。
func _toggle_stone() -> void:
	if item_cursor >= _items.size():
		sub_state = Phase.CONFIRM
		_refresh()
		return
	var index := ItemKind.index_of(_items[item_cursor])
	stone_index = MonsterMixTable.NO_STONE if stone_index == index else index
	_refresh()


func _run_finished(animation: StringName) -> void:
	if animation != &"run" or sub_state != Phase.RUNNING:
		return
	_resolve()


## `Game_Monster_Mix_Proc`：掷骰加成 → 扣合成石 → 成功率判定 → 品级 ±1 →
## 属性组之和 → 候选判定树 → 删两只、扣 200、按 `Ball_stdSet` 建新记录 → 存档。
func _resolve() -> void:
	var primary: Dictionary = _monster_record(primary_index)
	var secondary: Dictionary = _monster_record(secondary_index)
	var primary_species := _catalog().monster(int(primary.get("species", -1)))
	var secondary_species := _catalog().monster(int(secondary.get("species", -1)))
	if primary_species == null or secondary_species == null:
		sub_state = Phase.MONSTER
		_refresh()
		return
	var grade := int(primary_species.attribute_entry)
	var percent := MonsterMixTable.percent(grade, stone_index)
	var bonus := MonsterMix.ability_bonus(_ability(), grade, randi() % MonsterGrowth.ROLL_MODULUS)
	if bonus > 0:
		percent += bonus
		MessageStack.say_record(Msg.Id.MONSTER_MIX_BONUS, [bonus])
	if stone_index >= 0:
		_story.consume_item(ItemKind.id_of(ItemKind.Kind.GROUP_7, stone_index), 1)
		stone_index = MonsterMixTable.NO_STONE
	var success := MonsterMix.is_success(percent, randi() % MonsterGrowth.ROLL_MODULUS)
	var result := MonsterMix.resolve(_catalog(), int(primary_species.id), int(secondary_species.id),
		success)
	var record := _child_record(result, primary, secondary)
	var removed := [primary_index, secondary_index]
	removed.sort()
	removed.reverse()
	var failure := ""
	for index: int in removed:
		var dropped: Dictionary = Menu.discard_party_member(_story.progress, index)
		if not dropped.get("ok", false):
			failure = str(dropped.get("error", "成员不存在"))
	var added_index: int = int(_story.progress["monsters"].size())
	if failure.is_empty():
		failure = _story.capture_monster(record)
		_outcome_record = record
	else:
		_outcome_record = {}
	_charge_fee()
	primary_index = -1
	secondary_index = -1
	sub_state = Phase.SUCCEEDED if success else Phase.FAILED
	_rebuild_monsters()
	_rebuild_items()
	cursor = maxi(0, _position_of(added_index)) if failure.is_empty() else 0
	completed.emit()
	_refresh()
	if not failure.is_empty():
		MessageStack.say(failure)


## `Ball_stdSet(&r0_, v15, r2_0, -1, brain, feel, v51, 0, 0, -1, nickname)` 的记录映射：
## 等级／brain／feel 取两只的平均，觉醒只有两只都觉醒才置 1，昵称按原生取一只或随机掷。
func _child_record(result: Dictionary, primary: Dictionary, secondary: Dictionary) -> Dictionary:
	var level := (int(primary.get("level", 0)) + int(secondary.get("level", 0))) / 2
	var brain := (int(primary.get("brainCurrent", 0)) + int(secondary.get("brainCurrent", 0))) / 2
	var feel := (int(primary.get("feel", 0)) + int(secondary.get("feel", 0))) / 2
	var awakened := Battle.record_awakened(primary) and Battle.record_awakened(secondary)
	var species := int(result["species"])
	return {"species": species, "level": level,
		"nativeArguments": [species, level, int(awakened), -1, 0],
		"nickname": _child_nickname(primary, secondary), "experience": 0,
		"feel": feel, "food": ItemEffect.FOOD_MAX,
		"brainCurrent": brain, "brainLimit": Battle.BRAIN_LIMIT}


## `_Proc` 第 79–115 行：两只都有昵称时 `rand() % 2` 取一只，否则取非 0 的那只；
## 都没有时按 `Ball_stdSet` 的缺省规则掷一次（`Battle.roll_nickname`，`EFC_mainGetRAND() % 7`）。
func _child_nickname(primary: Dictionary, secondary: Dictionary) -> int:
	var first := int(primary.get("nickname", -1))
	var second := int(secondary.get("nickname", -1))
	if first > 0 and second > 0:
		return first if randi() % 2 == 0 else second
	if first > 0:
		return first
	if second > 0:
		return second
	return Battle.roll_nickname(func(limit: int) -> int: return randi() % limit)


## `Param_moneySET(-200)`：`Game_monster` 侧同样夹在 0（`Param_moneySET`）。
func _charge_fee() -> void:
	var parameter: Variant = _story.progress.get("parameter", {})
	if parameter is Dictionary:
		parameter["moneyBalance"] = maxi(0, _money() - MonsterMix.FEE)


func _select_monster(slot: int) -> void:
	if _closing or is_transitioning() or sub_state != Phase.MONSTER:
		return
	if slot >= _monsters.size():
		return
	cursor = slot
	_press_ok()


func _select_stone(slot: int) -> void:
	if _closing or is_transitioning() or sub_state != Phase.STONE:
		return
	# 空道具格现在也画出来（原生照画空位格底），点它不应进入确认流程。
	if slot >= _items.size():
		return
	item_cursor = slot
	_toggle_stone()


func _choose(index: int) -> void:
	if _closing or is_transitioning() or sub_state != Phase.CONFIRM:
		return
	choice = index
	_confirm()


## `Game_Monster_SetList(0)`：`Ball_bagList` 的顺序里**排除**出战三只。
func _rebuild_monsters() -> void:
	_monsters.clear()
	var order: Array = _story.progress.get("partyOrder", [])
	var monsters: Array = _story.progress.get("monsters", [])
	for index in range(monsters.size()):
		if order.has(index) or not monsters[index] is Dictionary:
			continue
		var record: Dictionary = monsters[index]
		_monsters.append({"index": index, "record": record, "species": int(record.get("species", -1))})
	cursor = clampi(cursor, 0, maxi(0, _monsters.size() - 1))


## `Game_Monster_Mix_SetJewel`：袋 0 里 `kind 7` 的定义号 4／5
## （袋内顺序同强化页：道具号升序）。
func _rebuild_items() -> void:
	_items = _owned_item_ids(MonsterMix.is_stone)
	item_cursor = clampi(item_cursor, 0, maxi(0, _items.size() - 1))


func _refresh() -> void:
	var list_page := sub_state != Phase.CONFIRM and sub_state != Phase.STONE
	$Content/Subtitle.visible = sub_state != Phase.CONFIRM
	$Content/ListFrame.visible = list_page
	$Content/ListStrip.visible = list_page
	$Content/ListMoney.visible = list_page
	$Content/ListCount.visible = list_page
	$Content/Info.visible = list_page
	$Content/Confirm.visible = sub_state == Phase.CONFIRM
	$Content/Items.visible = sub_state == Phase.STONE
	$Content/Confirm/Option0/Inner.modulate = Color.WHITE if choice == Choice.STONE \
		else Color("#186385")
	$Content/Confirm/Option0/Outer.modulate = $Content/Confirm/Option0/Inner.modulate
	$Content/Confirm/Option1/Inner.modulate = Color.WHITE if choice == Choice.RUN \
		else Color("#186385")
	$Content/Confirm/Option1/Outer.modulate = $Content/Confirm/Option1/Inner.modulate
	$Content/Confirm/Percent.present(str(_percent()))
	$Content/Confirm/Fee/Number.present(str(MonsterMix.FEE))
	$Content/ListMoney/Number.present(str(_money()))
	$Content/ListCount.present("%d/%d" % [mini(_monsters.size(), MONSTER_COLUMNS), _monsters.size()])
	_refresh_monster_cells()
	_refresh_info()
	_refresh_item_cells()
	_refresh_portraits()


## 已选的主位／副位精灵画角标（`ItemData.mix_primary_monster`／`mix_secondary_monster`）。
func _monster_marked(_slot: int, entry: Dictionary) -> bool:
	var index := int(entry.get("index", -1))
	return index == primary_index or index == secondary_index


## 原生 `equipment_code > 0`；工程里装备索引用 −1 表示没有，所以判 `>= 0`（同强化页的标记）。
func _monster_equipped(_slot: int, entry: Dictionary) -> bool:
	return _has_equipment(entry)


func _refresh_info() -> void:
	var entry: Dictionary = _monsters[cursor] if cursor < _monsters.size() else {}
	var species: MonsterDefinition = _catalog().monster(int(entry.get("species", -1))) \
		if not entry.is_empty() else null
	var name := ""
	if species != null:
		name = _monster_name(species, int(entry.get("record", {}).get("nickname", -1)))
	$Content/Info/Name.text = name
	$Content/Info/Level/Number.present(str(int(entry.get("record", {}).get("level", 0))))
	$Content/Info/Brain/Number.present("%d/%d" % [
		int(entry.get("record", {}).get("brainCurrent", 0)),
		int(entry.get("record", {}).get("brainLimit", 0))])
	var result := ""
	match sub_state:
		Phase.RUNNING:
			result = _text(Msg.Id.MONSTER_MIX_RUNNING)
		Phase.FAILED:
			result = _text(Msg.Id.MONSTER_MIX_LOW_RESULT)
		Phase.SUCCEEDED:
			result = _text(Msg.Id.MONSTER_MIX_HIGH_RESULT)
	$Content/Info/Result.text = result
	$Content/Info/Result.visible = not result.is_empty()
	for node: Control in [$Content/Info/Name, $Content/Info/Level, $Content/Info/Brain]:
		node.visible = result.is_empty()


func _marked_item(item_id: int) -> bool:
	return MonsterMix.is_stone(item_id) and ItemKind.index_of(item_id) == stone_index


## 子状态 0–3 画两只立绘（原生第 615–639 行），4／5 画结果精灵与爆点（第 557–613 行）。
func _refresh_portraits() -> void:
	var merging := sub_state == Phase.RUNNING
	var result := sub_state == Phase.FAILED or sub_state == Phase.SUCCEEDED
	var primary := _monster_record(primary_index)
	var secondary := _monster_record(secondary_index)
	var primary_visible := not result and not primary.is_empty()
	var secondary_visible := not result and not secondary.is_empty()
	var primary_node: Node2D = $Content/Portraits/Primary
	var secondary_node: Node2D = $Content/Portraits/Secondary
	primary_node.visible = primary_visible
	secondary_node.visible = secondary_visible
	if not merging:
		primary_node.position.x = _primary_home
		secondary_node.position.x = _secondary_home
		primary_node.modulate.a = 1.0
		secondary_node.modulate.a = 1.0
	if primary_visible:
		primary_node.present(MonsterAnimation.battle_identity(int(primary["species"])),
			AniAction.Clip.IDLE, PRIMARY_DIRECTION)
	if secondary_visible:
		secondary_node.present(MonsterAnimation.battle_identity(int(secondary["species"])),
			AniAction.Clip.IDLE, SECONDARY_DIRECTION)
	$Content/Portraits/Merged.visible = result
	$Content/Portraits/Effect.visible = result
	$Content/Outcome.visible = result
	if not result:
		return
	var merged: Node2D = $Content/Portraits/Merged
	var effect: Node2D = $Content/Portraits/Effect
	var merged_species := int(_outcome_record.get("species", -1))
	if merged_species >= 0:
		merged.present(MonsterAnimation.battle_identity(merged_species), AniAction.Clip.IDLE,
			PRIMARY_DIRECTION)
	var action := SUCCEEDED_EFFECT_ACTION if sub_state == Phase.SUCCEEDED \
		else FAILED_EFFECT_ACTION
	effect.present("obj/b_effect", action, 0, false)
	var species: MonsterDefinition = _catalog().monster(merged_species)
	$Content/Outcome/Name.text = _monster_name(species, int(_outcome_record.get("nickname", -1))) \
		if species != null else ""
	$Content/Outcome/Level/Number.present(str(int(_outcome_record.get("level", 0))))
	$Content/Outcome/Brain/Number.present("%d/%d" % [
		int(_outcome_record.get("brainCurrent", 0)), int(_outcome_record.get("brainLimit", 0))])


func _percent() -> int:
	var primary := _monster_record(primary_index)
	var species: MonsterDefinition = _catalog().monster(int(primary.get("species", -1))) \
		if not primary.is_empty() else null
	if species == null:
		return 0
	return MonsterMixTable.percent(int(species.attribute_entry), stone_index)


func _monster_record(index: int) -> Dictionary:
	var monsters: Array = _story.progress.get("monsters", [])
	if index < 0 or index >= monsters.size() or not monsters[index] is Dictionary:
		return {}
	return monsters[index]


## 原生 `equipment_code > 0`；工程里装备索引用 −1 表示没有，所以判 `>= 0`（同强化页的标记）。
func _has_equipment(entry: Dictionary) -> bool:
	var arguments: Variant = entry.get("record", {}).get("nativeArguments", [])
	return arguments is Array and arguments.size() > 3 and int(arguments[3]) >= 0


func _position_of(monster_index: int) -> int:
	for position in range(_monsters.size()):
		if int(_monsters[position]["index"]) == monster_index:
			return position
	return 0


## `ParamData.ability_values[0]`（合成页的掷骰加成分片读槽 0，强化页读槽 1）。
func _ability() -> int:
	return _allocated_value(MonsterMix.ABILITY_VALUE_INDEX)
