extends Resource
class_name BattleSpeciesTable
## 每个战斗物种的动作分段：本体按顺序播哪几段 `animation_id`、每段在哪一帧命中、
## 什么时候生成分身、技能附带什么状态码。
##
## 数据源是反编译代码（`Battle_Monster_00NN_procCurr`／`_procNext`／`_procSkill`），
## 由 `script\export_battle_species.py` 从伪代码快照生成（不需要 IDA），不要手改本文件：
##
##     species = {
##       6: {"attack": [segment], "skill": [segment], "status": 0},
##     }
##     segment = {
##       "animation": 14 | 15 | 20 | …,           # 原生 `animation_id`
##       "hits": [{"frame", "percent", "status", "behind", "all"}, …],
##       "clones": [{"frame", "animation", "dash", "dash_addend", "all"}, …],
##       "dash": int,                              # 本体在该段每帧 `x += dash * (n + dash_addend)`
##       "dash_addend": int,                       # 括号里那个常数 k（`~n`／`(n + 1)` 是 +1，`x -= dash * n` 是 0）
##     }
##
## `all` 在命中上是「对行动者那一侧的所有对象逐个结算」（`BattleData + 20676` 的循环），
## 在分身上是「对每个敌人各建一具」（`Battle_Monster_0062_procCurr` 的 `Object_objCreate` 循环）。
## 技能命中（`Battle_dmg2SKILL`／`Param_dmg2SKILL`）的那一条另带 `skill_code`：调用点写死的
## `n0x31` 实参，即 `Param_dmg2SKILL` 的技能码（也是主动效果槽号，`switch` 按它选
## 附哪个状态、取哪个受方被动做反弹）；符号化的物种取该物种 `_procSkill` 的返回值。

## 数据文件；与 `battle-poses.tres` 一样是生成物。
const TABLE_PATH := "res://game/battle/combat/combat/battle-species.tres"
## 觉醒／进化物种号在基础物种号上加 1000（`Ball_stdFeel` 的 `definition_id += 1000`），
## 这些变体共用基础物种的动作回调（`Battle_Monster_00NN_procCurr`），所以查表时取模。
const VARIANT_OFFSET := 1000
## 命中记录里没有 `skill_code` 时的返回值（原生技能码只到 0x31，负数不会与真实值冲突）。
const SKILL_CODE_UNRECORDED := -1

@export var species: Dictionary = {}

## 查表缓存。`load()` 每次都要走 ResourceLoader 的路径规范化与缓存查找，而战斗表现每帧都会按
## 物种反查分段（`field._body_dash` 每帧 6 个对象各查一次），所以这里只取一次。
static var _table_cache: Dictionary = {}


static func table() -> Dictionary:
	if not _table_cache.is_empty():
		return _table_cache
	var loaded := load(TABLE_PATH) as BattleSpeciesTable
	_table_cache = loaded.species if loaded != null else {}
	return _table_cache


static func record(species_id: int) -> Dictionary:
	return table().get(key(species_id), {})


static func has(species_id: int) -> bool:
	return table().has(key(species_id))


static func key(species_id: int) -> int:
	return species_id % VARIANT_OFFSET


## 攻击／技能的播放分段（按顺序）。
static func segments(species_id: int, skill: bool) -> Array:
	return record(species_id).get("skill" if skill else "attack", [])


## `Battle_Monster_00NN_procSkill` 的返回值：物种技能码（原生 `n0x31`，即 `Param_dmg2SKILL`
## 的 `switch` 键，同时是主动效果的槽号）；0 表示这一技能只结算伤害。
static func status(species_id: int) -> int:
	return int(record(species_id).get("status", 0))


## 该技能命中在原生传的技能码 `n0x31`（`Param_dmg2SKILL` 的第三个参数）。
## 老数据没有这个键时返回 `SKILL_CODE_UNRECORDED`，不要当成 0（0 是「只结算伤害」）。
static func skill_code(hit: Dictionary) -> int:
	return int(hit.get("skill_code", SKILL_CODE_UNRECORDED))


## 该物种动作会用到的 ANI 动作号（本体分段与分身动作），供视图预载。
static func clip_actions(species_id: int) -> Array[int]:
	var actions: Array[int] = []
	for skill: bool in [false, true]:
		for segment: Dictionary in segments(species_id, skill):
			_append(actions, AniAction.action_of(int(segment["animation"])))
			for clone: Dictionary in segment["clones"]:
				_append(actions, AniAction.action_of(int(clone["animation"])))
	return actions


static func _append(actions: Array[int], action: int) -> void:
	if action >= 0 and not actions.has(action):
		actions.append(action)
