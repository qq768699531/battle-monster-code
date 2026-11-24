extends NinePatchRect
## 通用窗框：持有窗框图集与切片边距，界面场景实例化它而不是各自引用贴图。
## `frame` 选择图集里的整帧区域；边距按 8 像素九宫格切，改这里即可全局生效。

const FRAMES := {
	"box4": Rect2(0, 0, 87, 28),
	"box2": Rect2(0, 210, 50, 48),
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
	var region: Rect2 = FRAMES[frame]
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	texture = atlas
