extends RefCounted
## 野外像素走位的纯几何核心（参考原生 `Map_tileMove` / `Field_Hero_procMOVE`）。
##
## 原生每次只走 1px，逐像素问 `Map_tileIsMoveRect`；碰撞盒 16×16 由调用方在 `is_free`
## 里表达（传入候选的**脚点像素**，脚点 = 碰撞盒中心）。被挡时沿垂直方向扫 1..32px
## 找可站位置，再把剩余距离沿侧向走掉。

## 原生侧滑候选顺序：横向先上后下，纵向先左后右。
const SLIDE_PERPENDICULARS := {
	Vector2i.RIGHT: [Vector2i.UP, Vector2i.DOWN],
	Vector2i.LEFT: [Vector2i.UP, Vector2i.DOWN],
	Vector2i.UP: [Vector2i.LEFT, Vector2i.RIGHT],
	Vector2i.DOWN: [Vector2i.LEFT, Vector2i.RIGHT],
}
const SLIDE_SCAN_PX := 32


## 从 `start`（脚点像素）沿 `direction` 走 `pixels` 像素；每 1px 判一次 `is_free`。
## 返回 `{"position": Vector2, "moved": int}`，`moved < pixels` 表示被挡。
static func move_step(start: Vector2, direction: Vector2i, pixels: int, is_free: Callable) -> Dictionary:
	var position := start
	var step := Vector2(direction)
	var moved := 0
	for _index in range(maxi(pixels, 0)):
		var candidate := position + step
		if not bool(is_free.call(candidate)):
			break
		position = candidate
		moved += 1
	return {"position": position, "moved": moved}


## 原生 `Field_Hero_procMOVE` 的侧滑选向：先看斜前方 1px，再按 1..32px 交替试两侧。
## 返回 `{"direction": Vector2i, "pixels": int}`（`pixels` 已夹到剩余距离），找不到返回空。
static func slide_direction(foot: Vector2, direction: Vector2i, leftover: int,
		is_free: Callable) -> Dictionary:
	if leftover <= 0:
		return {}
	var forward := Vector2(direction)
	var perpendiculars: Array = SLIDE_PERPENDICULARS.get(direction, [])
	for offset in range(1, SLIDE_SCAN_PX + 1):
		for perpendicular: Vector2i in perpendiculars:
			var candidate := foot + forward + Vector2(perpendicular) * float(offset)
			if bool(is_free.call(candidate)):
				return {"direction": perpendicular, "pixels": mini(offset, leftover)}
	return {}
