extends Resource
class_name FoodRecipes

## `item_food.dat` 的食谱表（`Field_Item_Food_init` 的列表 → `Field_Item_Food_Proc`）。
## 由 `script\export_food_recipes.py` 从 `assets\assets\common\item_food.dat` 的原字节导出，
## 不要在脚本里重抄这份表。
##
## 每条记录的 detail 槽 0／1／2 是 `<材料索引(u8) | 件数(u8) << 8>`（`Item_datBuff`）：
## `Field_Item_Food_Proc` 用 `LOBYTE` 取 basic 第 3 组材料、`HIBYTE` 取件数。
## 另外两项不在 DAT 里，是原生代码的常量：
## - `product_count` = 1：列表项 `Item_stdSet(…, 27, n, 1)` 的持有数，`Field_Item_Food_Proc`
##   原样交给 `Item_stdAddEx`（`LOWORD(v9) = v4` 只改类型，件数不动）。
## - `price` = 100：`Param_moneySET(-100)`；`Field_Item_Food_DrawPrice` 也写死 100。
##
## 条目顺序就是 DAT 的组序，即 `Field_Item_Food_init` 的列表序。

@export var entries: Array[Dictionary] = []


func size() -> int:
	return entries.size()


## 产品 id（`ItemKind.id_of(1, 组号)`）→ 食谱；没有这条就报错并返回空字典。
func get_recipe(product_id: int) -> Dictionary:
	for entry: Dictionary in entries:
		if int(entry.get("product_id", -1)) == product_id:
			return entry
	push_error("食物制作：食谱表里没有产品 %d。" % product_id)
	return {}
