extends Resource
class_name ShopTable

## 原生 `Field_Item_Buy_SetList` 的货架表（野外商店买页的商品来源）。
##
## 调用点只有两处：`Field_Item_Buy_init`（`FieldData+0x20` 组游标清零后
## `SetList(0)` 取第一档）与 `Field_Item_Buy_mKeyPressed` 的 case 13（左右切档位：
## `游标 = (游标 + 组数 − 1) % 组数` 后 `SetList(游标)`）。参数 `a1` 是
## `Field_Item_Buy_Get` 组表的下标，`p_n5[a1]` 才是组号（0 道具／1 装备／3 书）。
##
## 函数按 `ItemData.shop_mode_code`（`Evt_chtMENU`：交互码 3 → 1 装备店、6 → 0 道具店）
## 与 `MapData.map_id` 的三处特判（148／6／97）逐条 `Item_stdSet(type, index)`；其余地图走默认序列。
## 每个 id 都是反编译立即数里那个 int32 拆出来的两个 int16，见 `script\export_shops.py`。
##
## 结构：组号 → { 地图号 → 道具 id 数组 }，地图号 −1 是该组的默认货架。
## 97 号地图的两组记成 `{"dynamic": "…"}`：原生那时从 `ParamData.event_map_npc_count`
## 取事件参数（`+1..+5` 装备、`+11..+15` 书），本工程没有这条剧情通道，所以不伪造 id。

const DEFAULT_MAP := -1


@export var stocks: Dictionary = {}


## 该组是否登记了这张地图（含默认货架）的条目。
func has(group_code: int, map_id: int) -> bool:
	var groups: Variant = stocks.get(group_code)
	if not groups is Dictionary:
		return false
	return groups.has(map_id) or groups.has(DEFAULT_MAP)


## 货架道具 id（原生 `Item_stdSet(type, index)` 的展开顺序）。条目缺失或由事件参数提供时为空。
func stock(group_code: int, map_id: int) -> Array:
	var entry: Variant = _entry(group_code, map_id)
	return (entry as Array).duplicate() if entry is Array else []


## 非空表示这张货架在原生里由事件参数填（`ParamData.event_map_npc_count`），本工程未建模。
func dynamic_source(group_code: int, map_id: int) -> String:
	var entry: Variant = _entry(group_code, map_id)
	return str(entry.get("dynamic", "")) if entry is Dictionary else ""


func _entry(group_code: int, map_id: int) -> Variant:
	var groups: Variant = stocks.get(group_code)
	if not groups is Dictionary:
		return null
	if groups.has(map_id):
		return groups[map_id]
	return groups.get(DEFAULT_MAP)
