extends "res://tests/unit/gut_case.gd"

const NARRATION = preload("res://game/field/dialogue/narration_view/narration_view.tscn")


## opcode 4 的叙事字幕（`Evt_scrDRAW`）：版式 3 不盖背景、块心在 `height / 3`；1–3 之外的版式号
## 照常走完时间轴；步长取自 Scene 的 `Rhythm/step` 动画长度（原生 1000 ms 一步）；确定键直接结束
## 整条指令而不是快进到最后一页。
func test_legacy_suite() -> void:
	var narration = NARRATION.instantiate()
	add_child_autofree(narration)
	var lines: Control = narration.get_node("Lines")
	assert_true(narration.present([{"text": "第一行"}], 3), "版式 3 有正文就能显示")
	assert_false(narration.get_node("Back").visible, "版式 3 不填背景（`Evt_stdPAINT1` case 3 返回 0）")
	assert_eq(lines.position, Vector2(0, 75),
		"版式 3 块心在 height/3：单行块高 10，首行 y＝80 − 10/2（`Evt_scrDRAW:30-35`）")
	assert_eq((lines.get_node("Line0") as Label).position, Vector2.ZERO, "行内偏移由 Scene 摆好")

	narration.clear()
	assert_true(narration.present([{"text": "兜底版式"}], 4), "1–3 之外的版式号照常接收")
	narration.advance(6.0)
	assert_true(narration.finished(), "兜底版式照常走完放出／保持／淡出后结束")

	assert_true(narration.present([{"text": "字"}], 1), "版式 1 有正文就能显示")
	assert_eq(lines.position, Vector2(0, 115),
		"版式 1 块心在 height/2：单行首行 y＝120 − 10/2（`Evt_scrDRAW:148-151`）")

	assert_true(narration.present([{"text": "字".repeat(40)}], 1), "折行成两行的页能显示")
	var second: Label = lines.get_node("Line1")
	assert_false(second.visible, "第 1 步只放出第一行")
	narration.advance(0.9)
	assert_false(second.visible, "0.9 秒还停在第 1 步（一步＝`Rhythm/step` 的 1 秒）")
	narration.advance(0.2)
	assert_true(second.visible, "过 1 秒进第 2 步，放出第二行（`Evt_scrDRAW:136-140`）")

	assert_true(narration.present([{"text": "第一页"}, {"text": "第二页"}], 1), "多页字幕能显示")
	narration.advance(1.2)
	assert_false(narration.finished(), "还有下一页时自然推进不结束")
	narration.finish()
	assert_true(narration.finished(), "确定键直接结束整条指令")

	# 步长取自 Scene 里 `Rhythm/step` 的动画长度，不读运行中的位置：动画被停掉
	# （`current_animation_length` 归 0）也不会让推进循环空转——旧实现按
	# `length - position` 算步长，动画播完那一刻算出 0，`advance()` 里 `remaining`
	# 永远减不下去，Godot 进程挂住不退出（实测 3 次）。
	assert_true(narration.present([{"text": "字"}], 1), "重新建立一页")
	narration.get_node("Rhythm").stop()
	narration.advance(3.0)
	assert_false(narration.finished(), "动画停止时 advance 照 Scene 的步长走完三步，不空转也不跳步")
