extends RefCounted
class_name QuestMark
## NPC 头顶任务图标码：`Qst_icoGET` 的返回值，由 `Qst_icoSET` 写进
## 对象最后一个字节（`animation_resource + 135`），工程里由 `field_runtime` 落到 actor 的
## `quest_status`。两个消费者共用这一份枚举：`field/emotion.gd`（`Field_Emoticon_procDraw`
## 画头顶图标）与 `field/minimap.gd`（`Map_miniDRAW` 画 HUD 色块）。
##
## 原生只产出这五种；1 不产出（负进度兜底也压成 2），与 0 一样不画。

enum Code {
	NONE = 0,
	ACCEPTABLE = 2,
	IN_PROGRESS = 3,
	GOAL_REACHED = 4,
	EVENT = 5,
}

## 世界地图标记（`Map_worldDRAW`）：不是上面那套对象字节，而是任务文本资源的两个
## 页——page 3 逐项列出的地图号是 RELATED，page 4 第 0 项是 TARGET。取值直接就是原生
## `Menu_winDrawIcon12(x, y, a3 = mark - 1)` 的 mark，消费方是 `menu/world_map_canvas.gd`。
enum MapMark {
	NONE = 0,
	RELATED = 1,  ## page 3：`JC_fxtQINDEX(res, 3, n)` 的地图号（绿色标记）
	TARGET = 2,   ## page 4：`JC_fxtQINDEX(res, 4, 0)` 的地图号（黄色标记，`> 0` 才算）
}

## 任务文本资源的页序（`qst/qstlist.fxt` 按 `\t` 拆段，与 `menu/quest.gd` 的 `MAP_PAGE` 同一个 3）。
const RELATED_PAGE := 3
const TARGET_PAGE := 4
## page 4 只有 `> 0` 才当标记（`Map_worldDRAW` 的 `if (v10 > 0)`，0 表示没有目标地图）。
const TARGET_MIN_MAP := 0


## `Qst_icoGET:15-16` 的整段抑制：事件正在执行记录（`EvtData.step_index > 0`）时一律返回 0，
## 连任务表那套 2／3／4 都不画。`step` 取自 `StoryRuntime.event_step()`。
static func suppresses_marks(step: Dictionary) -> bool:
	return int(step["index"]) > StoryRuntime.STEP_INDEX_TRIGGER


## `Qst_icoGET:17` 的事件任务分支：停在首记录（`step_index == 0`）且这一步是「等与该对象
## 交互」——`EvtData.step_kind == 4`、`EvtData.item_condition_parameter` 为交互号——时，
## 被等的那一个对象拿 `EVENT`（5）。锁存由 `Evt_stdSET:10-13` 写、`Evt_stdIsPROC:40-43`
## 读。其余情况回 `NONE`：原生继续往下扫描任务表（2／3／4 由任务表判定，本工程在 `QuestLog.status`）。
static func event_step_code(step: Dictionary, object_id: int) -> int:
	if int(step["index"]) != StoryRuntime.STEP_INDEX_TRIGGER or \
			int(step["kind"]) != StoryRuntime.Trigger.INTERACT_LATCH:
		return Code.NONE
	return Code.EVENT if int(step["parameter"]) == object_id else Code.NONE


## 任务文本资源的页 → 地图号 → `MapMark`。原生按条目顺序逐条赋值，page 4 在 page 3 之后追加，
## 所以同一张地图两处都出现时最后落成 TARGET（图标也是后画的 mark 2 压在上面）。
static func marks_from_pages(pages: Variant) -> Dictionary:
	var marks := {}
	if not pages is Array and not pages is PackedStringArray:
		return marks
	for part: String in page_text(pages, RELATED_PAGE).split(",", true):
		var value := part.strip_edges()
		if value.is_valid_int():
			marks[int(value)] = MapMark.RELATED
	var target_parts := page_text(pages, TARGET_PAGE).split(",", true)
	if not target_parts.is_empty():
		var target := target_parts[0].strip_edges()
		if target.is_valid_int() and int(target) > TARGET_MIN_MAP:
			marks[int(target)] = MapMark.TARGET
	return marks


## 第 `index` 页正文（超出段数按空串，对应 `JC_fxtPAGE` 的越界返回 0）。
static func page_text(pages: Variant, index: int) -> String:
	if index < 0 or index >= pages.size():
		return ""
	return String(pages[index])
