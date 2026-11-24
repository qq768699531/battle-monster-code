extends RefCounted
class_name ItemKind
## 原生道具号与背包归属的语义名。
##
## `Item_datBasic` 以 `type`（= `item_basic.dat` 的组号）选组、`id % 1000` 取组内索引，
## 所以道具号恒为 `type * 1000 + index`（见 `wiki\data-format\dat-item-table.md`）。只有能对上原生消费点的
## 组才起语义名；其余保留 `GROUP_n` 并注明「含义未确认」，不按外观猜。

const ID_SCALE := 1000

enum Kind {
	CONSUMABLE = 1,   ## 第 1 组：可堆叠 99、可用（`Item_stdMax`、`wiki\data-format\dat-item-food.md`）
	EQUIPMENT = 2,    ## 第 2 组：装备（`battle.gd` 按 `type == 2` 查装备；`Field_Item_Sell_Price` 固定 100）
	MATERIAL = 3,     ## 第 3 组：材料（`wiki\data-format\dat-item-basic.md`「材料引用第 3 组」，堆叠 99）
	SKILL_BOOK = 4,   ## 第 4 组：技能书（`item_skill.dat` 的类型 4 入口；`book_model` 只收 type 4）
	ATTRIBUTE_BALL = 5,      ## 第 5 组：属性球（`capture_rating` 的 5 号索引 1–6 对应六属性）
	GROUP_6 = 6,      ## 原生第 6 组，含义未确认
	GROUP_7 = 7,      ## 原生第 7 组：6／7 号单格堆叠 1 且归入捕获那一袋，其余堆叠 20
}

enum Bag {
	ITEMS = 0,          ## 原生袋 0：第 1／7 组，战斗道具窗口的普通道具页
	SKILL_BOOKS = 3,    ## 原生袋 3：第 4 组（技能书）。`Item_fndBag` 把 `IK_BOOK` 映到
	                    ## `INVENTORY_BAG_BOOK` = 3，`Menu_Item_SetMenuList` 的 `case 3` 给
	                    ## 「合成」（`Menu_List_Set(0xAu)` → 文案 177）＋「丢弃」（`Menu_List_Set(6u)`）
	CAPTURE_BALLS = 4,  ## 原生袋 4：捕获球页（`Battle_Item_Capture_Get` 只列这一袋）
}
## 原生袋号 1、2、5 只由 `bag_of` 的「组 2–6 → 袋 组号−1」规则产生，尚无消费点可证语义，故不登记。
## 菜单道具页的袋数是 0–5 共 6 个。
const BAG_COUNT := 6

## 伪道具：`Item_stdAdd` 在查袋之前先按组号分派，这几组**不进任何背包**。
## 道具号编码与真道具相同（组号 × 1000 + 索引），所以 26000 就是「2000 块钱」。
## 事件 2 的初始包里有 `Op.ADD_ITEM(26000, 2000)`，宝箱表的 26000 也是钱（`Battle_Drop_BOX`）。
enum Pseudo {
	GROUP_23 = 23,   ## 含义未确认；`Item_stdAdd` 只把记录清零并返回成功
	GROUP_24 = 24,   ## 同上
	EXPERIENCE = 25, ## `Param_expSET(6, 数量)`：加进英雄 `player_progress`
	MONEY = 26,      ## `Param_moneySET(数量)`：加进 `money_balance`
}

## 组 23–26 都在 `Item_stdAdd` 查袋之前分派，永不进入任何背包。
const PSEUDO_KINDS := [Pseudo.GROUP_23, Pseudo.GROUP_24, Pseudo.EXPERIENCE, Pseudo.MONEY]

## 捕获球在原生第 7 组里的两个索引（`Battle_Capture_Action_IsCapture` 单独调权）。
const CAPTURE_BALL_INDEX := 6
const CAPTURE_BALL_STRONG_INDEX := 7
## 第 7 组第 20 号「超级大理石」：`Ball_stdUse` 的 `SHIWORD(n4) == 20` 分支
## （`feel += food > 30 ? 70 : 140` 后再 `Ball_stdFood(ball, 100)`）。
const SUPER_MARBLE_INDEX := 20


static func kind_of(item_id: int) -> int:
	return int(item_id / ID_SCALE)


static func index_of(item_id: int) -> int:
	return item_id % ID_SCALE


static func id_of(kind: int, index: int) -> int:
	return kind * ID_SCALE + index


## 伪道具（组 23–26）：`Item_stdAdd` 不查袋、不登记图鉴，但仍推 `Item_stdAddEx` 的入手提示。
static func is_pseudo(kind: int) -> bool:
	return PSEUDO_KINDS.has(kind)


## 原生 ``Menu_Item_*`` 的背包归属；不属于任何袋时返回 -1。
static func bag_of(kind: int, index: int) -> int:
	if kind >= Kind.EQUIPMENT and kind <= Kind.GROUP_6:
		return kind - 1
	if kind == Kind.GROUP_7 and index in [CAPTURE_BALL_INDEX, CAPTURE_BALL_STRONG_INDEX]:
		return Bag.CAPTURE_BALLS
	if kind == Kind.CONSUMABLE or kind == Kind.GROUP_7:
		return Bag.ITEMS
	return -1


## 原生 `Item_stdMax`：单格堆叠上限；等于 1 时跳过丢弃数量选择。
static func max_stack(kind: int, index: int) -> int:
	match kind:
		Kind.CONSUMABLE:
			return 10 if index >= 19 and index <= 24 else 99
		Kind.MATERIAL:
			return 99
		Kind.SKILL_BOOK:
			return 10
		Kind.GROUP_7:
			return 1 if index in [CAPTURE_BALL_INDEX, CAPTURE_BALL_STRONG_INDEX] else 20
	return 1
