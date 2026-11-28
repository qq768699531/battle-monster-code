extends "res://tests/unit/gut_case.gd"

const MessageStack = preload("res://engine/ui/message_stack/message_stack.gd")
const Msg = preload("res://engine/ui/msg/msg.gd")


class FakeStack extends Control:
	var pushed: Array = []

	func push(icon_frame: int, text: String) -> void:
		pushed.append([icon_frame, text])


var _stack: Control


func before_each() -> void:
	super()
	_stack = FakeStack.new()
	add_child_autofree(_stack)
	MessageStack.active = _stack


## 提示的形态是固定的：调用方只给类型和数据，图标／高亮色／格式都由 `message_stack` 拼。
func test_typed_entries_build_the_fixed_styles() -> void:
	MessageStack.push_item("宝珠", 3, 12, 1)
	assert_eq(_stack.pushed.size(), 1, "一条获得提示")
	assert_eq(int(_stack.pushed[0][0]), 12, "图标帧由调用方给")
	assert_eq(String(_stack.pushed[0][1]),
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.ITEM_OBTAINED) %
			[MessageStack.ITEM_GRADE_COLORS[1], "宝珠", 3],
		"正文按 fxt 416 的固定格式拼")

	MessageStack.push_monster("毛球兽", 1, 2, 4)
	assert_eq(int(_stack.pushed[1][0]), MessageStack.BALL_ICONS[4], "精灵图标按属性查表")
	assert_eq(String(_stack.pushed[1][1]),
		MessageStack.GRADE_COLORS[1] +
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.NICKNAME_PREFIX + 2) + " " +
		(AssetCatalog.text_message(Msg.SOURCE, Msg.Id.MONSTER_OBTAINED) % "毛球兽"),
		"精灵提示 = 品级色 + 性格前缀 + 名称获得")

	MessageStack.push_quest("测试任务", Msg.Id.QUEST_ACCEPT_SUFFIX)
	assert_eq(int(_stack.pushed[2][0]), MessageStack.QUEST_ICON, "任务提示图标固定")
	assert_eq(String(_stack.pushed[2][1]),
		MessageStack.HIGHLIGHT + "测试任务" +
		AssetCatalog.text_message(Msg.SOURCE, Msg.Id.QUEST_ACCEPT_SUFFIX), "标题高亮 + 后缀")

	MessageStack.push_quest_progress("测试任务", "0/5")
	assert_eq(_stack.pushed.size(), 5, "进度提示是标题 + 目标两行")
	assert_eq(_stack.pushed[3][1], MessageStack.HIGHLIGHT + "测试任务", "标题行")
	assert_eq(_stack.pushed[4][1], "%s[0/5]" % MessageStack.HIGHLIGHT, "目标行带方括号")
