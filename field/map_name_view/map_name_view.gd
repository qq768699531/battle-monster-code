extends Control
## 消息卷轴条：横条展开/收拢与文字显出。原生 `Game_msgDraw(0/1)` 用同一套画法画两条，
## `Game_msgInit(index, …)` 按下标写入；`:48` 的 `height / 4 + 20 * index + v5` 让两条纵向差 20 px。
## 场景基准位置对应 index 1（地图名称条），index 0（`Map_warpProc:59-60` 的 404）上移一格。

## 地图名称条的触发来源，决定要不要重播。原生唯一的入口是 `Map_warpProc:54` 的
## `Game_msgInit(1, MapData.reserved_0x10)`：它在 `Map_warpIsAble` 通过、`GameCanvas_mapFREE`／
## `GameCanvas_mapLOAD` 之后**无条件**调用，目标图就是当前图（同图传送）也照样弹一次，所以
## 「要不要重播」只看来源、不看名字是否相同。`Game_msgDraw` 每次绘制按
## `GameData.transition_parameter_bits` 的档位（50→…→0）画。
## - `WARP`：真正换图（传送，或剧情 opcode 14 换到另一张图），每次都从头重播。
## - `STORY`：剧情 opcode 14（`Evt_stdPROC` 的 case 0xE）载入的仍是当前这张图，移植侧没有换图，
##   不重播（bm-P2-104）。
## 见 wiki\field\field-movement.md「地图名称条只在换图时重播」。
enum Source {
	STORY,
	WARP,
}

const BAR_STEP_PX := 20.0
## `Game_msgInit` 的槽下标：0 = 404 等消息，1 = 地图名称（场景基准）。
@export_range(0, 1) var bar_index := 1

var map_name := ""
var elapsed := 0.0

@onready var _text: Label = $Bounds/Roll/Text
@onready var _animation: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_animation.assigned_animation = &"reveal"
	var bounds: Control = $Bounds
	var lift := BAR_STEP_PX * (1 - bar_index)
	bounds.offset_top -= lift
	bounds.offset_bottom -= lift
	hide()


func present(text: Variant, source: Source) -> void:
	var requested: String = "" if text == null else text.replace("\n", " ")
	if requested.is_empty():
		map_name = requested
		elapsed = 0.0
		refresh()
		return
	if source == Source.STORY:
		return
	map_name = requested
	elapsed = 0.0
	refresh()


func advance(delta: float) -> void:
	if visible:
		elapsed += delta
		refresh()


func refresh() -> void:
	_text.text = map_name
	if map_name.is_empty():
		hide()
		return
	_animation.seek(minf(elapsed, _animation.get_animation(&"reveal").length), true)
