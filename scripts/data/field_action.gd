extends RefCounted
class_name FieldAction
## 地图角色的 `action` 状态号（原生 `Field_Hero_procAction`／`Map_obj*` 用来选 ANI）。
##
## 只登记能对上原生分支的取值；剧情给的动作码（3／4／10／11 的基帧表在
## `field_actors.gd` 的 `HERO_ACTION_BASES`、`100 + N` 是物件动作）不在这里命名。

enum Hero {
	IDLE = 0,
	WALK = 1,
	RUN = 2,
	## 原生 `Field_Basic_mKeyPressed` 的 `Object_objHIT` 分支 `case 152: Object_objANI(hero, 3)`：
	## 面向帧 152 那一组宽物件（152–155，`Map_objCREATE` 的 16×8 档）按确认键时，
	## 英雄原地播一次动作 3。动作本身的语义未确认（ANI 基帧 9，见 `field_actors.gd` 的
	## `HERO_ACTION_BASES`），所以按触发它的物件帧号命名。
	OBJECT_152_INTERACT = 3,
	## 原生 `Field_Basic_mKeyPressed:48-49` 的 `if (MapData.map_file_number == 0) return
	## Object_objANI(hero, 4)`：第 0 组地图上、面向帧 0／5／10 的物件按确认键时英雄播一次动作 4。
	## 这三帧的物件只有第 0 组才被 `Map_objCREATE:88-100` 置 `active_state = 3`（可被
	## `Object_objHIT` 命中），动作本身语义未确认（ANI 基帧 12 加朝向变体），按触发条件命名。
	GROUP_0_OBJECT_INTERACT = 4,
	SCRIPT_WALK = 6,   ## 事件脚本的逐格移动（`story.gd` 的 move 指令），与走路同基帧
	WARP = 10,         ## `Field_Hero_procNext` case 10：飞艇登船／出发，播完才 `Map_warpProc`
	ARRIVE = 11,       ## 同一函数的 case 11：换图后的落地动作，播完回待机
}

## 地图角色的朝向位（`lastDirection` / `direction_flags` 的低位）。
## 见 `field_runtime.gd` 的 `FACING_TILES` 与 `Field_Basic` 的移动方向表。
enum Facing {
	LEFT = 1,
	RIGHT = 2,
	UP = 16,
	DOWN = 32,
}

## 上下朝向的位掩码（`direction & VERTICAL_MASK` 判断是否朝上／下）。
const VERTICAL_MASK := 48
