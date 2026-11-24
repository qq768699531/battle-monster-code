extends Resource
class_name EncounterDefinition

## 原生地图怪物池（按地图 id 一条）。
##
## `mode` 为 `native-weighted` 时按 `pool` 权重抽取；
## `native-dynamic-unimplemented` 表示原生该图用动态生成（`Map_mifLOAD` 的
## `map_id - 97 <= 0x18` 分支）：物种按稀有度行现抽、等级取玩家等级。

const DYNAMIC_MODE := "native-dynamic-unimplemented"

## 原生 `.rodata` 0x9AF7C（`C.9.10047`，`memcpy` 60 字节 = 10 行 × 6 列）：
## 行 = `clamp(世界等级 / 10, 0, 9)`，列 = 怪物稀有度（`item_mon.dat` 记录第 133 字节，
## 即本工程的 `MonsterDefinition.attribute_entry`）。0 权重表示该稀有度不出现在这一档。
const DYNAMIC_WEIGHTS := [
	[35, 35, 30, 0, 0, 0],
	[34, 35, 30, 1, 0, 0],
	[32, 35, 30, 2, 1, 0],
	[29, 35, 30, 3, 2, 1],
	[26, 35, 30, 4, 3, 2],
	[25, 35, 30, 5, 3, 2],
	[24, 35, 30, 6, 3, 2],
	[23, 35, 30, 7, 3, 2],
	[22, 35, 30, 8, 3, 2],
	[19, 35, 30, 9, 4, 3],
]

@export var id: int
@export var mode: String
@export var world_level: int
@export var pool: Array[EncounterEntry] = []


func is_dynamic() -> bool:
	return mode == DYNAMIC_MODE


## 原生 `Map_worldLEVEL`：97–121 号图直接用玩家当前等级，其余用 `world_level`。
func resolved_world_level(player_level: int) -> int:
	return player_level if is_dynamic() else world_level


## 原生 `Map_mifLOAD` 的动态分支：按世界等级行取权重，每个稀有度用 `Map_monGET`
## 的规则随机挑一只该稀有度的物种（`Map_monGET` 在原生是进图时调一次，之后固定）。
## 该档没有候选物种的稀有度整列丢弃（原生会建出空对象，等价于不生成）。
func dynamic_pool(catalog: GameplayData, player_level: int, roll: Callable) -> Array[EncounterEntry]:
	var entries: Array[EncounterEntry] = []
	if catalog == null:
		return entries
	var row := clampi(resolved_world_level(player_level) / 10, 0, DYNAMIC_WEIGHTS.size() - 1)
	var weights: Array = DYNAMIC_WEIGHTS[row]
	for grade in weights.size():
		var weight := int(weights[grade])
		if weight <= 0:
			continue
		var candidates: Array[int] = []
		for record: MonsterDefinition in catalog.monsters:
			if int(record.attribute_entry) == grade:
				candidates.append(int(record.id))
		if candidates.is_empty():
			continue
		var entry := EncounterEntry.new()
		entry.species = candidates[int(roll.call(candidates.size()))]
		entry.weight = weight
		entries.append(entry)
	return entries


## 原生 `Map_mifLOAD` 写的 `MapData+0x6E`：动态图野外怪物等级 = `clamp(10 × 行, 5, 85)`。
func dynamic_monster_level(player_level: int) -> int:
	var row := clampi(resolved_world_level(player_level) / 10, 0, DYNAMIC_WEIGHTS.size() - 1)
	return 5 if row == 0 else mini(10 * row, 85)
