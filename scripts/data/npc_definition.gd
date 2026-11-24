extends Resource
class_name NpcDefinition

## 原生 NPC 绑定记录（`npc.nm`）：贴图序号、交互码与待机移动闸门。
##
## 名字不在这里——它按 `npc:<id>` 存在翻译资源 `zh_CN.tres` 里，与其它正文同一处维护。

@export var id: int
## NPC 贴图序号，拼成 `npc/n_f_%02d`。
@export var field_sprite_id: int
@export var interaction_code: int
@export var idle_movement_gate: int


## 普通对白源（原生 `Field_Basic_Chat` 按 NPC 记录号取 `npc/npcNNNN.cht`）。
## 静态 NPC 由地图节点的 `metadata/npc_dialogue` 声明；事件 `Op.NPC_RECORDS` 生成的 NPC
## 没有场景节点，路径规则集中在这里，避免在各处再写一遍。
static func dialogue_source(npc_id: int) -> String:
	return "npc/npc%04d.cht" % npc_id
