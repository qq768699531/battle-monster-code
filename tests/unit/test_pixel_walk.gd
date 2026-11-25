extends "res://tests/unit/gut_case.gd"

const PixelWalk = preload("res://game/field/runtime/pixel_walk/pixel_walk.gd")


## 原生 `Map_tileMove`：每 1px 判一次碰撞，被挡就停在最后一个可站像素。
func test_move_step_stops_at_wall() -> void:
	var free := func(foot: Vector2) -> bool: return foot.x < 10.0
	var result: Dictionary = PixelWalk.move_step(Vector2.ZERO, Vector2i.RIGHT, 20, free)
	assert_eq([result["position"], result["moved"]], [Vector2(9, 0), 9],
		"向右 20px 在 x=10 被挡，实际走 9px 并停在阻挡前")


func test_move_step_zero_distance() -> void:
	var free := func(_foot: Vector2) -> bool: return true
	var result: Dictionary = PixelWalk.move_step(Vector2(4, 4), Vector2i.DOWN, 0, free)
	assert_eq([result["position"], result["moved"]], [Vector2(4, 4), 0], "0px 不走")


## 原生 `Field_Hero_procMOVE` 的侧滑：斜前方 1px 起、按 1..32px 交替试两侧。
func test_slide_direction_scans_perpendicular() -> void:
	# 右移被挡；只有向上 5px 的位置可站。
	var free := func(foot: Vector2) -> bool: return foot.y <= 95.0
	var slide: Dictionary = PixelWalk.slide_direction(Vector2(100, 100), Vector2i.RIGHT, 6, free)
	assert_eq([slide["direction"], slide["pixels"]], [Vector2i.UP, 5],
		"向右被挡时向上扫到第 5px 可站，侧滑距离夹到剩余 5px")
	var blocked := func(_foot: Vector2) -> bool: return false
	assert_true(PixelWalk.slide_direction(Vector2(100, 100), Vector2i.RIGHT, 6, blocked).is_empty(),
		"两侧 32px 都不可站时不侧滑")
	assert_true(PixelWalk.slide_direction(Vector2(100, 100), Vector2i.RIGHT, 0, free).is_empty(),
		"没有剩余距离时不侧滑")


func test_slide_prefers_up_then_down_for_horizontal() -> void:
	var both := func(foot: Vector2) -> bool: return foot.y <= 100.0 or foot.y >= 101.0
	var slide: Dictionary = PixelWalk.slide_direction(Vector2(100, 100), Vector2i.RIGHT, 4, both)
	assert_eq(slide["direction"], Vector2i.UP, "横向请求先试上方")
