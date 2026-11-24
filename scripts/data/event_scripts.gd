extends Resource
class_name EventScripts

## 事件脚本集合：事件号 → qst payload（与原生一致的结构字典）。
##
## 剧情按数值 id 全局寻址（下一个事件是 `eventId + 1`，opcode 1 可跳到任意号），
## 所以这里是一张总表而不是按地图拆分。由使用它的 Scene 直接引用，运行时不再拼资源路径。

@export var scripts: Dictionary = {}


func script_for(id: int) -> Variant:
	return scripts.get(id)
