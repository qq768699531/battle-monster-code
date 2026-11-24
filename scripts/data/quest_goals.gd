class_name QuestGoals
extends RefCounted
## `Qst_stdCHECK` 的现场清点（`goal_kind` 1／2）：菜单任务页与野外运行时共用这一份规则。
##   • 精灵：`Ball_bagFindCount(goal_target, 0)` —— 精灵袋里同一物种的个体数，`a2 == 0` 时排除上阵成员。
##   • 素材：`Item_fndCount(IK_METERIAL, goal_target)` —— 素材袋里该道具的持有量。


## `Ball_bagFindCount` 用 `definition_id % 1000` 取物种号（与 `ItemKind.ID_SCALE` 同一刻度）。
static func bag_monster_count(progress: Dictionary, species: int) -> int:
	var monsters: Array = progress.get("monsters", [])
	var party: Array = progress.get("partyOrder", [])
	var count := 0
	for index in monsters.size():
		if party.has(index):
			continue
		var args: Variant = monsters[index].get("nativeArguments", [])
		if not args is Array or args.is_empty():
			continue
		if int(args[0]) % ItemKind.ID_SCALE == species % ItemKind.ID_SCALE:
			count += 1
	return count


static func material_count(progress: Dictionary, target: int) -> int:
	var inventory: Dictionary = progress.get("inventory", {})
	var count := 0
	for key: Variant in inventory:
		var key_text := str(key)
		if not key_text.is_valid_int():
			continue
		var item_id := int(key_text)
		if ItemKind.kind_of(item_id) != ItemKind.Kind.MATERIAL or \
				ItemKind.index_of(item_id) != target:
			continue
		count += int(inventory[key])
	return count
