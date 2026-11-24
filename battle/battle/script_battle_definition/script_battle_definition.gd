extends Resource
class_name ScriptBattleDefinition

## 战斗配置（按战斗 id 一条）：`constructors` 每项是 10 个整数构造参数，
## 依次为怪物目录索引、等级、成长、加成、难度档、觉醒、被动、被动等级、装备、昵称。

@export var id: int
@export var constructors: Array[PackedInt32Array] = []
