extends Resource
class_name GameplayData

## 原生玩法数值的唯一数据入口：道具、物种、被动、地图怪物池与脚本战斗配置。
##
## 记录按 id 存成数组，便于在检查器里逐条编辑；查询按 id 线性查找——记录量最多几百条，
## 而缓存会在测试夹具就地替换数组后失效，因此不做惰性索引。

@export var items: Array[ItemDefinition] = []
@export var monsters: Array[MonsterDefinition] = []
@export var passives: Array[PassiveDefinition] = []
@export var encounters: Array[EncounterDefinition] = []
@export var script_battles: Array[ScriptBattleDefinition] = []
@export var npcs: Array[NpcDefinition] = []


func item(id: int) -> ItemDefinition:
	return _find(items, id)


func monster(id: int) -> MonsterDefinition:
	return _find(monsters, id)


func passive(id: int) -> PassiveDefinition:
	return _find(passives, id)


func encounter(map_id: int) -> EncounterDefinition:
	return _find(encounters, map_id)


func script_battle(id: int) -> ScriptBattleDefinition:
	return _find(script_battles, id)


func npc(id: int) -> NpcDefinition:
	return _find(npcs, id)


static func _find(records: Array, id: int) -> Resource:
	for record: Variant in records:
		if record.id == id:
			return record
	return null
