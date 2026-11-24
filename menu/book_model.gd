extends RefCounted

## 图鉴（原生 `Game_Book_List`／`Game_Book_Monster`／`Game_Book_Skill`）的数据投影与导航规则。
##
## 发现位由原生 `Ball_stdAdd`（获得怪物 → `Param_bookSetMonster(id % 1000, 1)`）与
## `Item_stdAdd`（获得 type 4 技能书 → `Param_bookSetSkill(index, 1)`）置位，所以图鉴记录的是
## 「获得过」——`skt/method_.fxt:43`：1)精灵图鉴：捕获目录 2)技能书图鉴：获得目录。
## 存档里按升序记录已获得的 id（怪物 0-131、技能书 0-167），没记录的 id 就是未获得。
## 图鉴页不直接读存档，而是读一张「知识表」（`records()` 或任意同形的字典），所以调试与剧情
## 可以换上 `all_records()` 或自定义表来看不同的收录范围，存档本身只在获得时增长。
##
## 怪物分 6 类 × 22 条：`Game_Book_Monster_Load` 用 `22 * 类别 + 序号` 取物种，
## 而光标取模 `6 * ((22 + 5) / 6) = 24`，所以每类末两格是 X（`Menu_winDrawIcon16` 帧 2，
## 落在这两格时详情显示空记录 NO.000）。

const Battle = preload("res://battle/battle.gd")

const MONSTER_CATEGORIES := 6
const MONSTER_SLOTS := 22
const MONSTER_COLUMNS := 6
const MONSTER_ROWS := 2
const MONSTER_CURSOR_SLOTS := 24
const SKILL_ROWS := 4
const SKILL_SLOTS := 168
const BOOK_MONSTERS := "monsters"
const BOOK_SKILLS := "skills"
const MONSTER_TOTAL := MONSTER_CATEGORIES * MONSTER_SLOTS
const SKILL_TOTAL := SKILL_SLOTS


static func monster_id(category: int, cursor: int) -> int:
	return category * MONSTER_SLOTS + cursor


## 每类只有 22 条真实记录；22／23 是光标能到、但没有物种的 X 格。
static func monster_slot_exists(category: int, cursor: int) -> bool:
	return cursor >= 0 and cursor < MONSTER_SLOTS and \
		monster_id(category, cursor) < MONSTER_CATEGORIES * MONSTER_SLOTS


## `JC_knlSTART`：把光标所在行保持进可见窗口，返回新的滚动起点。
static func scroll_start(scroll: int, cursor: int, rows: int) -> int:
	var row := cursor / MONSTER_COLUMNS
	var top := mini(row, scroll / MONSTER_COLUMNS)
	var bottom := row + 1 - rows
	return MONSTER_COLUMNS * maxi(bottom, top)


static func monster_scroll(cursor: int, scroll: int) -> int:
	return scroll_start(scroll, cursor, MONSTER_ROWS)


static func skill_scroll(cursor: int, scroll: int) -> int:
	return scroll_start(scroll, cursor, SKILL_ROWS)


## `Game_Book_Monster_mKeyPressed`：四个方向在 24 格上取模环绕。
static func step_monster_cursor(cursor: int, delta: int) -> int:
	return posmod(cursor + delta, MONSTER_CURSOR_SLOTS)


## `Game_Book_Skill_mKeyPressed`：格数是 `Item_passiveCount()` 上取整到 6 的倍数。
static func skill_cursor_slots(count: int) -> int:
	return MONSTER_COLUMNS * maxi(1, (maxi(count, 1) + MONSTER_COLUMNS - 1) / MONSTER_COLUMNS)


static func step_skill_cursor(cursor: int, delta: int, count: int) -> int:
	return posmod(cursor + delta, skill_cursor_slots(count))


static func is_discovered(progress: Dictionary, key: String, value: int) -> bool:
	return contains(records(progress), key, value)


## 给图鉴页的知识表：`{monsters: [升序 id], skills: [升序 id]}`，越界项丢掉。
## 页面只认这张表，所以调用方可以换成任意一份（调试全开、剧情指定）而不动存档。
static func records(progress: Dictionary) -> Dictionary:
	var record: Variant = progress.get("book")
	if not record is Dictionary:
		return {BOOK_MONSTERS: [], BOOK_SKILLS: []}
	return {BOOK_MONSTERS: _clean(record.get(BOOK_MONSTERS), MONSTER_TOTAL),
		BOOK_SKILLS: _clean(record.get(BOOK_SKILLS), SKILL_TOTAL)}


## 全开的记录（调试与剧情用），与 `records()` 同形。
static func all_records() -> Dictionary:
	return {BOOK_MONSTERS: range(MONSTER_TOTAL), BOOK_SKILLS: range(SKILL_TOTAL)}


## 用给定知识表覆盖存档里的图鉴记录；有越界／非整数项时整份拒绝，不写半张表。
static func set_records(progress: Dictionary, knowledge: Dictionary) -> bool:
	var monsters: Variant = knowledge.get(BOOK_MONSTERS)
	var skills: Variant = knowledge.get(BOOK_SKILLS)
	if not monsters is Array or not skills is Array:
		return false
	if not _is_record(monsters, MONSTER_TOTAL) or not _is_record(skills, SKILL_TOTAL):
		return false
	progress["book"] = {BOOK_MONSTERS: _clean(monsters, MONSTER_TOTAL),
		BOOK_SKILLS: _clean(skills, SKILL_TOTAL)}
	return true


## 原生 `Game_Book_Monster_mKeyPressed:42-69`：初始精灵确认前把 132 位怪物图鉴
## （`Param_bookSetMonster(i, 0)`，`i` 步长 11）与 168 位技能图鉴（`Param_bookSetSkill(j, 0)`，
## `j` 步长 8）全部清零，再按确认的物种重新登记。剧情期 `Op.ADD_MONSTER`（`Evt_stdPROC`
## case 0x1F → `Ball_stdAdd` → `Param_bookSetMonster`）记过的临时精灵因此不会留在图鉴里。
static func reset_records(progress: Dictionary) -> void:
	set_records(progress, {BOOK_MONSTERS: [], BOOK_SKILLS: []})


## 把「当前持有」补进获得记录：`progress.monsters` 的物种（`Ball_stdAdd` 同样取 % 1000）
## 与 `inventory` 里的 type 4 技能书。老存档没有图鉴字段、或怪物／技能书不经过获得指令
## （直接写 `monsters`／`inventory`）时靠这一步补齐；幂等，返回新记录了几条。
static func record_owned(progress: Dictionary) -> int:
	var added := 0
	var monsters: Variant = progress.get("monsters")
	if monsters is Array:
		for member: Variant in monsters:
			if member is Dictionary and member.get("species") is int and \
					discover_monster(progress, member["species"]):
				added += 1
	var inventory: Variant = progress.get("inventory")
	if inventory is Dictionary:
		for key: Variant in inventory:
			var text := str(key)
			if not text.is_valid_int() or not inventory[key] is int or int(inventory[key]) <= 0:
				continue
			if discover_item(progress, text.to_int()):
				added += 1
	return added


static func contains(knowledge: Dictionary, key: String, value: int) -> bool:
	var list: Array = knowledge.get(key, [])
	var position := list.bsearch(value)
	return position < list.size() and int(list[position]) == value


static func count(knowledge: Dictionary, key: String) -> int:
	var list: Variant = knowledge.get(key)
	return list.size() if list is Array else 0


static func _is_record(value: Array, limit: int) -> bool:
	for entry: Variant in value:
		if not entry is int or entry < 0 or entry >= limit:
			return false
	return true


static func _clean(value: Variant, limit: int) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is int and entry >= 0 and entry < limit and not result.has(entry):
			result.append(entry)
	result.sort()
	return result


static func discover(progress: Dictionary, key: String, value: int) -> bool:
	var record: Variant = progress.get("book")
	if not record is Dictionary:
		record = {BOOK_MONSTERS: [], BOOK_SKILLS: []}
		progress["book"] = record
	if not record.get(key) is Array:
		record[key] = []
	var list: Array = record[key]
	var position := list.bsearch(value)
	if position < list.size() and int(list[position]) == value:
		return false
	list.insert(position, value)
	return true


## `Ball_stdAdd`：物种号取 `definition_id % 1000`（1000 以上是变异形态）。
static func discover_monster(progress: Dictionary, species: int) -> bool:
	var value := species % 1000
	if value < 0 or value >= MONSTER_CATEGORIES * MONSTER_SLOTS:
		return false
	return discover(progress, BOOK_MONSTERS, value)


## `Item_stdAdd`：只有 type 4（技能书）才记入技能图鉴，索引就是技能号。
static func discover_item(progress: Dictionary, item_id: int) -> bool:
	if ItemKind.kind_of(item_id) != ItemKind.Kind.SKILL_BOOK:
		return false
	var index := ItemKind.index_of(item_id)
	if index < 0 or index >= SKILL_SLOTS:
		return false
	return discover(progress, BOOK_SKILLS, index)


## 原生 `Ball_stdSet(..., r2_0: 1, r3_0: 0, ...)`：图鉴里每只怪物都按 1 级、无成长、
## 无觉醒、无被动与装备的原始个体展示，所以数值来自同一个 `make_ball`。
static func native_ball(catalog: GameplayData, species: int) -> Dictionary:
	if catalog == null or catalog.monster(species) == null:
		return {}
	return Battle.make_ball(catalog, [species, 1, 0, 0, 0, 0, 0, 0, -1, 0], 0)
