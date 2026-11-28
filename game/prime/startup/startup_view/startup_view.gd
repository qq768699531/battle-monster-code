extends Node2D
## 启动欢迎页（原生状态 2 `Prime_NotMem_*`；空间不足页状态 3 `Prime_NotSpace_*` 共用本场景）。
##
## 原生 `Prime_NotMem_mPaint@0x6A53C` 每帧先清屏，再按状态计时二选一画同一个 Box2 框：
## 计时 ≤ 3000 ms 用 `Menu_win_Box2_DrawPROGRESS@0x4AEF8`（标题／正文／点线／进度条），
## 计时 > 3000 ms 用 `Menu_win_Box2_DrawOk@0x4B11C`（点线下换成 44×16 的确定键）。
## `Prime_NotSpace_mPaint@0x6925C` 只有 DrawOk 形态，文案换成 361／362。
##
## 几何全部按原生落在 Scene 里，脚本只做状态与文案绑定：
## - 窗宽 180（`Prime_NotMem_mPaint@0x6A53C:15-16` 的宽度常量）：
##   `Menu_win_Box2_DrawWindow@0x4ADE8:41` 的 `x = (400 − 180) / 2 = 110`，即 `Content` 的 110..290；
## - 窗高 `13 × 折行数 + 33 + n11`（`Menu_win_Box2_DrawPROGRESS@0x4AEF8:39`，有标题时 `n11 = 29`）
##   → 固定留白 62，见 `Content` 的 `metadata/vertical_padding`；
## - 标题基线 `y + 11`（`:48`）、正文顶 `y + 29`（`:53`）、点线 `正文顶 + 13 × 行数 + 5`（`:57`），
##   即 `Heading.offset_top = 11`、`Lines.offset_top = 29`、`Footer.offset_top = -28`
##   （这三处只在「标题非空」时成立，本页标题恒为 562，有正文）。
## 进度条在 `startup_footer.tscn` 的 `Progress`：外层 #7B756B 162×8（`:81`）、内层黑 160×6（`:79`）、
## 轨道黑 158×4（`:75`）、已填充 #AD9E9C 宽 `158 × 计时 / 3000`（`:77`）；点线是
## `:59` 的 `JC_grpSetRESERVE(v20 + 4, y_1, width − 8, 1)` 裁剪出的 172 宽 1 px（`:61-71` 每 3 px 画 2 px）。
##
## 窗框走 `dialog_panel`（`native_panel` 三层描边＋#0E1B2F 填充，逐层对上 `Menu_win_Box2_Draw@0x4AD78:5-11`），
## 不复用 `components/window_transition`：本页相位 `p_n4` 恒为 4（`Prime_NotMem_mPaint@0x6A53C:9`
## 写死 `4`，`Menu_win_Box2_DrawPROGRESS@0x4AEF8:29-45` 只在这一相位画全窗），没有开合动画要演。

const Layout = preload("res://game/prime/ui/layout/layout.gd")
const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const StartupRuntime = preload("res://game/prime/startup/startup_runtime/startup_runtime.gd")

## 原生 `Prime_NotMem_mPaint@0x6A53C:7-8` 的 `JC_fxt2Return(562)`／`(563)`；
## `Prime_NotSpace_mPaint@0x6925C:7-8` 的 `(361)`／`(362)`。记录号统一在 `Msg.Id`。
@export var center := Vector2.ZERO
var messages: Dictionary = {}


func configure(_catalog: Object, texts: Dictionary) -> bool:
	messages = texts
	return true


## 标题／正文记录号：原生两页共用同一绘制入口，只换文案。
func _title_id(scene_index: int) -> int:
	return Msg.Id.STARTUP_NOTICE_TITLE if scene_index == C.NOT_MEM else Msg.Id.STARTUP_STORAGE_TITLE


func _body_id(scene_index: int) -> int:
	return Msg.Id.STARTUP_NOTICE_BODY if scene_index == C.NOT_MEM else Msg.Id.STARTUP_STORAGE_BODY


func startup_layout(paint: Dictionary) -> Dictionary:
	var width := int($Content.size.x)
	var text_width := Layout.content_text_width(width, $Content/Lines)
	var lines := Layout.wrap_text(messages[_body_id(paint.scene)], text_width, Layout.UI_FONT)
	var height: int = $Content/Lines.line_step() * lines.size() + int($Content.get_meta("vertical_padding"))
	var rect := Rect2i(Vector2i(center - Vector2(width, height) / 2), Vector2i(width, height))
	return {"rect": rect, "lines": lines, "divider": rect.end.y + int($Content/Footer.offset_top)}


func present(paint: Dictionary) -> void:
	visible = paint.scene in [C.NOT_MEM, C.NOT_SPACE]
	if not visible:
		return
	var layout := startup_layout(paint)
	$Content.position = layout.rect.position
	$Content.size = layout.rect.size
	$Content/Heading.text = messages[_title_id(paint.scene)]
	$Content/Lines.present(layout.lines)
	$Content/Footer.present(int(paint.startup_elapsed_ms),
		paint.scene == C.NOT_MEM and paint.startup_elapsed_ms <= StartupRuntime.PROGRESS_FULL_MS,
		messages[Msg.Id.CONFIRM_OK],
		float(paint.get("startup_load_ratio", 1.0)))


func okay_rect(paint: Dictionary) -> Rect2i:
	var layout := startup_layout(paint)
	var footer := Layout.control_rect($Content/Footer, layout.rect)
	return Layout.control_rect($Content/Footer/Choice, footer)


## 确定键只在「空间不足」或欢迎页计时走完后才可点（原生进度条阶段没有按钮）。
func regions(paint: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not visible:
		return result
	if paint.scene == C.NOT_SPACE or paint.startup_elapsed_ms > StartupRuntime.PROGRESS_FULL_MS:
		result.append(Layout._region(TouchCode.Key.OK, okay_rect(paint)))
	return result
