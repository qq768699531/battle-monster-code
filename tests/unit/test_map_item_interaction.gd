extends "res://tests/unit/gut_case.gd"

const MapItem = preload("res://game/field/runtime/map_item_interaction/map_item_interaction.gd")
const FieldActors = preload("res://game/field/runtime/field_actors/field_actors.gd")
const FieldAction = preload("res://game/field/runtime/field_action/field_action.gd")
const ItemKind = preload("res://game/menu/item/item_kind/item_kind.gd")


func test_kind_of_matches_native_hit_set() -> void:
	assert_eq([MapItem.kind_of(152, false), MapItem.kind_of(176, false), MapItem.kind_of(166, false)],
		[MapItem.Kind.ORE, MapItem.Kind.CHEST, MapItem.Kind.GLOW],
		"宽物件 152／宝箱 176／发光石 166 在任意地图组都按原生命中集合分派")
	assert_eq([MapItem.kind_of(0, true), MapItem.kind_of(5, true), MapItem.kind_of(10, true)],
		[MapItem.Kind.TREE, MapItem.Kind.TREE, MapItem.Kind.TREE],
		"树只在第 0 组地图可交互（Map_objCREATE 只对第 0 组置 active_state = 3）")
	assert_eq([MapItem.kind_of(0, false), MapItem.kind_of(164, true), MapItem.kind_of(-1, true)],
		[MapItem.Kind.NONE, MapItem.Kind.NONE, MapItem.Kind.NONE],
		"非第 0 组的树帧、传送门帧与空格都不参与物品交互")


func test_reaction_action_follows_facing() -> void:
	assert_eq([MapItem.reaction_action(Vector2i.DOWN), MapItem.reaction_action(Vector2i.UP)],
		[MapItem.ORE_REACTION_VERTICAL, MapItem.ORE_REACTION_VERTICAL],
		"上下方向交互播 153（原生 case 3）")
	assert_eq([MapItem.reaction_action(Vector2i.RIGHT), MapItem.reaction_action(Vector2i.LEFT)],
		[155, 154], "原生 `Field_Hero_procCurr`：面向右 → 155，面向左 → 154")


## 树受击摇摆帧：0／5／10 三组基础帧各自映射到 1–4／6–9／11–14（下、上、左、右）。
func test_tree_reaction_mapping() -> void:
	assert_eq([MapItem.tree_reaction_action(0, Vector2i.DOWN),
		MapItem.tree_reaction_action(0, Vector2i.UP),
		MapItem.tree_reaction_action(0, Vector2i.LEFT),
		MapItem.tree_reaction_action(0, Vector2i.RIGHT)], [1, 2, 3, 4], "帧 0 的四个方向")
	assert_eq([MapItem.tree_reaction_action(5, Vector2i.DOWN),
		MapItem.tree_reaction_action(5, Vector2i.RIGHT)], [6, 9], "帧 5：下=6、右=9")
	assert_eq([MapItem.tree_reaction_action(10, Vector2i.UP),
		MapItem.tree_reaction_action(10, Vector2i.LEFT)], [12, 13], "帧 10：上=12、左=13")
	assert_eq(MapItem.tree_reaction_action(20, Vector2i.DOWN), 0, "非树基础帧没有摇摆映射")


func test_gather_tables_are_materials() -> void:
	for kind: int in [MapItem.Kind.ORE, MapItem.Kind.TREE]:
		var table: Array = MapItem.gather_table(kind)
		assert_true(not table.is_empty(), "采集种类 %d 有兜底表" % kind)
		for row: Array in table:
			assert_eq([ItemKind.kind_of(int(row[0])), int(row[1]) > 0],
				[ItemKind.Kind.MATERIAL, true], "兜底掉落是第 3 组材料且数量为正")
	assert_true(MapItem.gather_table(MapItem.Kind.NONE).is_empty() and
		MapItem.gather_drop(MapItem.Kind.NONE, 0).is_empty(), "非采集种类没有兜底表")
	var clamped: Dictionary = MapItem.gather_drop(MapItem.Kind.ORE, 99)
	assert_true(int(clamped["id"]) in [3024, 3025, 3026], "越界 roll 夹到表尾")


## 交互命中是像素级（`Object_objHIT`）：主角位置是连续浮点，不能取整成格子再找物体。
func test_object_hit_window_is_pixel_based() -> void:
	var hero := Vector2(168, 88)
	assert_true(FieldActors._facing_window(hero, Vector2(160, 88), FieldAction.Facing.LEFT),
		"面向左时左侧 8px 的物件命中（像素差）")
	assert_true(not FieldActors._facing_window(hero, Vector2(160, 88), FieldAction.Facing.RIGHT),
		"同一个物件在反方向不命中")
	assert_true(not FieldActors._facing_window(hero, Vector2(160, 79), FieldAction.Facing.LEFT),
		"横向前后看 |dy| ≤ 8，9px 不命中")
	assert_true(not FieldActors._facing_window(hero, Vector2(135, 88), FieldAction.Facing.LEFT),
		"纵深只到 32px，33px 不命中")
	assert_true(FieldActors._facing_window(hero, Vector2(168, 56), FieldAction.Facing.UP),
		"面向上的物件按 |dx| ≤ 8、上方 0..32px 命中")
	assert_true(not FieldActors._facing_window(hero, Vector2(168, 55), FieldAction.Facing.UP),
		"上方 33px 不命中")


## 两遍英雄动作、命中帧与次数上限取原生 active_state 规则，改动时这组断言会提醒同步文档。
func test_harvest_rhythm_constants() -> void:
	assert_eq(MapItem.HARVEST_SWINGS, 2, "一次采集播两遍英雄动作（计数 0 → 重播）")
	assert_eq([MapItem.harvest_limit(MapItem.Kind.ORE), MapItem.harvest_limit(MapItem.Kind.TREE)],
		[2, 2], "矿石 active_state 2、树 3 都是两次可得道具")
	assert_eq(MapItem.harvest_limit(MapItem.Kind.NONE), 0, "非采集种类没有收获上限")
	assert_eq([MapItem.MINE_HIT_FRAME, MapItem.SHAKE_HIT_FRAME], [6, 6],
		"两遍动作都在第 6 帧命中（原生命中帧）")
	assert_eq(FieldActors.NATIVE_ANI_SPEED, 1.2,
		"转换场景按 0.06 秒一帧，原生是 50ms 一帧，采集按 1.2 倍速播")
	assert_true(9 in FieldActors.GATHER_ANI_ACTIONS and 14 in FieldActors.GATHER_ANI_ACTIONS,
		"hero ANI 9–14 是动作 3／4 的三方向变体")
