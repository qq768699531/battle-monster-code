extends RefCounted
class_name MapEffect
## 全屏地图特效（原生 `Map_eft*` 一族）的档位表。
##
## 取证见 `wiki\field\map-effects.md`：`Map_eftSET(slot, kind, sub, color, repaint)` 写
## `MapData.reserved_0x152[2..9]`；`Map_eftMODE` 按 kind 设绘制组模式与颜色，
## `Map_eftDRAW` 用该模式整屏填充，`Map_eftPROC` 逐帧推进分级序列。
## 所有色值都按 `JC_grpSetRGB` 量化到 RGB565（R8>>3<<3、G8>>2<<2、B8>>3<<3），
## 表里直接写量化后的结果。

## `Map_eftSET` 的第一个参数（`MapData.reserved_0x152[2]`）：哪个槽整屏填充。
## 1 = `Map_Proc:16` 用它跳掉地图绘制；2／3 = `Map_Tile:122`／`:124`
## 在瓦片画完之后填充。三个槽共用同一份状态，所以同时只有一个在画。
enum Slot {
	MAP = 1,
	TILE_FILL_2 = 2,
	TILE_FILL_3 = 3,
}

## `Map_eftSET` 的第二个参数（`MapData.reserved_0x152[3]`），由 `Map_eftMODE` 的 switch 分派。
## 12–17 在原生里只存在爬坡、没有终态（`Map_eftPROC` 5 帧后直接复位），也没有调用方，故不登记。
enum Kind {
	BLANK = 0,          ## 无特效：`Map_eftReset` 清槽 id 后 `Map_eftMODE` 直接返回 0
	CUSTOM = 1,         ## 模式与颜色全由调用方给（只作为 10／11 的分级终态出现，事件不会直接设置）
	WHITE = 2,
	BLACK = 3,
	DODGE = 4,
	MULTIPLY = 5,
	GRADE_WHITE = 6,    ## 5 帧线性减淡爬坡 → WHITE
	GRADE_BLACK = 7,    ## 5 帧正片叠底爬坡 → BLACK
	GRADE_DODGE = 8,    ## 5 帧线性减淡爬坡 → DODGE
	GRADE_MULTIPLY = 9, ## 5 帧正片叠底爬坡 → MULTIPLY
	GRADE_WARM = 10,    ## 5 帧暖色爬坡 → CUSTOM(22, #FA3E00)
	GRADE_NIGHT = 11,   ## 5 帧冷色爬坡 → CUSTOM(20, #0051FF)
}

## `JC_grpSetMODE` 的 `GRP_MODE_TYPE`，只列本族用到的三档。
enum Blend {
	NORMAL = 0,
	MULTIPLY = 20,
	LINEAR_DODGE = 22,
}

## `Evt_stdPROC:111` 的 `match_parameter`：等于 4 才 `Map_eftSET(1, 3, 0, 0, 1)`，
## 其余取值一律 `Map_eftReset(1)`。
const BLACKOUT_PARAMETER := 4

## 静态档位（`Map_eftMODE` case 2..5）→ `{"blend", "color"}`。`Kind.CUSTOM`（case 1）
## 的模式与颜色由调用方给，不在表里。
const STATIC_STATES := {
	Kind.WHITE: {"blend": Blend.NORMAL, "color": 0xF8FCF8},
	Kind.BLACK: {"blend": Blend.NORMAL, "color": 0x000000},
	Kind.DODGE: {"blend": Blend.LINEAR_DODGE, "color": 0xB0B4B0},
	Kind.MULTIPLY: {"blend": Blend.MULTIPLY, "color": 0xB8BCB8},
}

## 分级档位 → 爬坡用的模式、Scene 里的爬坡片段名、5 帧后的终态。
## 爬坡值本身在 `scenes\field\map_effect.tscn` 的 `grade_*` 轨道里（原生是 `Map_eftMODE`
## 里的内联 5 字节常量表，见 `wiki\field\map-effects.md` 第 5 节）。
const GRADES := {
	Kind.GRADE_WHITE: {
		"blend": Blend.LINEAR_DODGE, "clip": "grade_white",
		"target": {"tier": Kind.WHITE, "blend": Blend.NORMAL, "color": 0xF8FCF8}},
	Kind.GRADE_BLACK: {
		"blend": Blend.MULTIPLY, "clip": "grade_black",
		"target": {"tier": Kind.BLACK, "blend": Blend.NORMAL, "color": 0x000000}},
	Kind.GRADE_DODGE: {
		"blend": Blend.LINEAR_DODGE, "clip": "grade_dodge",
		"target": {"tier": Kind.DODGE, "blend": Blend.LINEAR_DODGE, "color": 0xB0B4B0}},
	Kind.GRADE_MULTIPLY: {
		"blend": Blend.MULTIPLY, "clip": "grade_multiply",
		"target": {"tier": Kind.MULTIPLY, "blend": Blend.MULTIPLY, "color": 0xB8BCB8}},
	Kind.GRADE_WARM: {
		"blend": Blend.LINEAR_DODGE, "clip": "grade_warm",
		"target": {"tier": Kind.CUSTOM, "blend": Blend.LINEAR_DODGE, "color": 0xF83C00}},
	Kind.GRADE_NIGHT: {
		"blend": Blend.MULTIPLY, "clip": "grade_night",
		"target": {"tier": Kind.CUSTOM, "blend": Blend.MULTIPLY, "color": 0x0050F8}},
}


## 无特效状态（`Map_eftReset`）。
static func blank() -> Dictionary:
	return {"slot": Slot.MAP, "tier": Kind.BLANK, "blend": Blend.NORMAL, "color": 0}


## 事件请求（`Evt_stdPROC` case 3 子模式 5 的 `match_parameter`）→ 新状态。
static func from_request(parameter: int) -> Dictionary:
	if parameter != BLACKOUT_PARAMETER:
		return blank()
	return static_state(Kind.BLACK)


## 静态档位 → 完整状态；未知档位按无特效处理（原生 default 分支只会用残留状态填屏，
## 那部分不可复现，见 `wiki\field\map-effects.md` 第 4 节）。
## 键名用 `tier` 而不是 `kind`：场景效果字典的 `kind` 是效果类型字符串（`_emit` 会覆盖它）。
static func static_state(kind: int) -> Dictionary:
	var entry: Dictionary = STATIC_STATES.get(kind, {})
	if entry.is_empty():
		return blank()
	return {"slot": Slot.MAP, "tier": kind,
		"blend": int(entry["blend"]), "color": int(entry["color"])}


static func is_graded(kind: int) -> bool:
	return GRADES.has(kind)


## 分级档位爬坡时用的绘制模式。
static func ramp_blend(kind: int) -> int:
	return int(GRADES.get(kind, {}).get("blend", Blend.NORMAL))


## 分级档位在 Scene 里的爬坡片段名（`map_effect.tscn` 的动画名）。
static func grade_clip(kind: int) -> String:
	return str(GRADES.get(kind, {}).get("clip", ""))


## 分级档位 5 帧爬坡结束后落到的状态。爬坡最后一档的颜色就等于它，所以这里只负责换模式。
static func target_state(kind: int) -> Dictionary:
	var entry: Dictionary = GRADES.get(kind, {})
	if entry.is_empty():
		return blank()
	var target: Dictionary = entry["target"]
	return {"slot": Slot.MAP, "tier": int(target["tier"]),
		"blend": int(target["blend"]), "color": int(target["color"])}
