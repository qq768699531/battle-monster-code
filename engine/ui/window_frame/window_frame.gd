extends NinePatchRect
## 通用窗框：持有拆出来的两张窗框图片（box4 带标题条、box2 是确认框），
## 界面场景实例化本场景切换 `frame` 即可，不再引用整张大图集。

const FRAMES := {
	"box4": "res://engine/ui/window_frame/window_frame_box4.webp",
	"box2": "res://engine/ui/window_frame/window_frame_box2.webp",
}

@export var frame := "box4":
	set(value):
		frame = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not FRAMES.has(frame):
		return
	texture = load(FRAMES[frame])
