extends RefCounted
class_name MapItemInteraction
## 地图物件交互：原版 `Field_Basic_mKeyPressed` 的 `Object_objHIT` 命中集合（帧 0／5／10／152／
## 166／176）与两种反应。
##
## 语义依据（不是按外观猜）：
## - 帧 152 是 16×8 档宽物件，公共图组 `obj/obj_f_99` 动作 52 是水晶矿；地图 14 的
##   (9,5) 有一处，事件 `evt0019.qst` 的触发 6 区域在 (10,5)，其任务文本是「在矿石前按OK键
##   采矿」。`Object_objHIT` 命中它时英雄播动作 3。
## - 帧 0／5／10 只有第 0 组地图会置 `active_state = 3`；`obj/obj_f_01` 的这三帧是阔叶树／
##   针叶树，事件 `evt0016.qst` 的触发 6 区域旁边就有帧 0／10 的树，任务文本写「敲击树木」。
##   命中时英雄播动作 4。
## - 166 → 167 是原生的换帧（发光石熄灭），不给道具。
## - 176 是宝箱（`Field_Box_Set`，已有独立实现）。
##
## 原版把采矿／摇树的奖励放在「区域调查」事件里（触发 6：英雄在该区域做过动作 3／4）。
## 本工程保留事件优先，只有当前没有这类事件等着时才按材质表兜底掉一件材料。

enum Kind {
	NONE,
	TREE,
	ORE,
	GLOW,
	CHEST,
}

## 交互物件帧号（`Object_objHIT` 的命中集合）。宝箱另有两帧 176／177，开过之后是 177。
const TREE_FRAMES: Array[int] = [0, 5, 10]
const ORE_FRAME := 152
const GLOW_FRAME_FROM := 166
const GLOW_FRAME_TO := 167
const CHEST_FRAME_CLOSED := 176
const CHEST_FRAME_OPEN := 177

## 宽物件受击后的三段反应帧（`Field_Object_procNext` 把 153..155 收回 152）。
## 原生 `Field_Hero_procCurr` 的 case 3：面向右 → 155，左 → 154，上/下 → 153。
const ORE_REACTION_VERTICAL := 153
const ORE_REACTION_RIGHT := 155
const ORE_REACTION_LEFT := 154

## 树受击后的 6 帧摇摆动画：基础帧 0／5／10 各自对应 1–4／6–9／11–14；
## 原生 case 4 的映射是下=base、上=base+1、左=base+2、右=base+3。
const TREE_REACTION_BASE := {0: 1, 5: 6, 10: 11}

## 兜底掉落表：第 3 组材料，`[道具号, 数量]`（取原生 `Field_Hero_procCurr` 的组内候选）：
## 矿取纯金／铜／铁（索引 24–26），树取空心的果实／昆虫／蜜（索引 27–29）。
const ORE_DROPS := [[3024, 1], [3025, 1], [3026, 1]]
const TREE_DROPS := [[3027, 1], [3028, 1], [3029, 1]]

## 采集节奏与次数上限（对齐原生 `Field_Hero_procCurr` 的 active_state）：
## 一次采集播两遍英雄动作（第一遍计数 0，结束回调重播时计数变 1），
## 命中帧各反应一次、第二遍命中帧才发道具。
## 矿石 `active_state` 从 2 递减，两次后移除；树从 3 递减，两次后仍可摇但只回「什么也没有」。
const HARVEST_SWINGS := 2
const ORE_HARVESTS := 2
const TREE_HARVESTS := 2
## 英雄动作 3 的原生命中帧（`Field_Hero_procCurr:47` 的 `frame_index == 6`）。
## 动作 4 的原生常量写作 0xF（15），但 hero 动作 4 的片段只有 11 帧，15 不可达；
## 这里取与采矿一致的第 6 帧作为动作中段的命中点（未确认原始意图）。
const MINE_HIT_FRAME := 6
const SHAKE_HIT_FRAME := 6


## 物件当前帧 → 交互种类。`tree_group` 是第 0 组地图的判定（原生只在第 0 组给树置
## `active_state = 3`），由调用方按 `map_group` 传入，避免两处各写一份组号常量。
static func kind_of(action: int, tree_group: bool) -> int:
	if action == ORE_FRAME:
		return Kind.ORE
	if action == GLOW_FRAME_FROM:
		return Kind.GLOW
	if action == CHEST_FRAME_CLOSED:
		return Kind.CHEST
	if tree_group and action in TREE_FRAMES:
		return Kind.TREE
	return Kind.NONE


## 英雄朝向（面前那一格的单位向量）→ 采矿反应帧：上下方向用 153，左右按原生映射。
static func reaction_action(facing: Vector2i) -> int:
	if facing.x == 0:
		return ORE_REACTION_VERTICAL
	return ORE_REACTION_RIGHT if facing.x > 0 else ORE_REACTION_LEFT


## 当前树帧 → 受击摇摆帧（不在 0／5／10 三张基础帧上时返回 0）。
static func tree_reaction_action(action: int, facing: Vector2i) -> int:
	var base := int(TREE_REACTION_BASE.get(action, 0))
	if base == 0:
		return 0
	if facing.x == 0:
		return base + (0 if facing.y > 0 else 1)
	return base + (3 if facing.x > 0 else 2)


static func is_vertical(facing: Vector2i) -> bool:
	return facing.x == 0


static func gather_table(kind: int) -> Array:
	match kind:
		Kind.ORE:
			return ORE_DROPS
		Kind.TREE:
			return TREE_DROPS
	return []


## 单个采集点的收获次数上限：矿石与树各一份；其它种类 0（不参与采集）。
static func harvest_limit(kind: int) -> int:
	match kind:
		Kind.ORE:
			return ORE_HARVESTS
		Kind.TREE:
			return TREE_HARVESTS
	return 0


## 纯函数式抽表：`roll` 由调用方给，测试可固定。越界时夹到两端。
static func gather_drop(kind: int, roll: int) -> Dictionary:
	var table: Array = gather_table(kind)
	if table.is_empty():
		return {}
	var row: Array = table[clampi(roll, 0, table.size() - 1)]
	return {"id": int(row[0]), "count": int(row[1])}
