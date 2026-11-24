class_name QuestSet
extends QuestTable
## 任务资源的目录化加载：`field/quest_set/qN/`（常规任务）与
## `field/quest_set/eN/`（事件任务），每个目录自带定义、文本与对话切片。
##
## 文本仍是 `TextTables` 结构；正文按原键（`qst/qstlist.fxt:<任务号>`、
## `evt/evtlist.fxt:<事件任务号>`）从 `core/message_stack/zh_CN.tres` 取，
## 所以拆目录不改变任何翻译键。

const ROOT := "res://field/quest_set"
const EVENT_TEXT_TABLE := "res://field/quest_detail/event_text.tres"


## 合并 `qN/quest.tres` 里的单条定义，返回可直接当 `QuestTable` 用的表。
static func load_table(root: String = ROOT) -> QuestSet:
	var table := QuestSet.new()
	for dir_name: String in _dirs(root, "q"):
		var slice: QuestTable = load("%s/%s/quest.tres" % [root, dir_name])
		if slice == null:
			push_error("QuestSet: 缺少 %s/quest.tres" % dir_name)
			continue
		for entry: Dictionary in slice.entries:
			table.entries.append(entry)
	return table


## 把分散的 TextTables 切片合并回一个按来源前缀索引的表，供 ResourceCatalog 懒加载。
## `qst` = 55 条 `qst/qstlist.fxt` 记录 + 17 份 `qst/qstNNNN.cht`；
## `evt` = 82 份 `evt/evtNNNN.cht`（仍在 event_text.tres）+ 62 条 `evt/evtlist.fxt`。
static func build_text(prefix: String, root: String = ROOT) -> TextTables:
	var payloads: Dictionary = {}
	if prefix == "qst":
		for dir_name: String in _dirs(root, "q"):
			_merge_file(payloads, "%s/%s/text.tres" % [root, dir_name])
			var dialogue := "%s/%s/dialogue.tres" % [root, dir_name]
			if ResourceLoader.exists(dialogue):
				_merge_file(payloads, dialogue)
	elif prefix == "evt":
		_merge_file(payloads, EVENT_TEXT_TABLE)
		for dir_name: String in _dirs(root, "e"):
			_merge_file(payloads, "%s/%s/text.tres" % [root, dir_name])
	else:
		push_error("QuestSet: 未知文本前缀 %s" % prefix)
	var table := TextTables.new()
	table.payloads = payloads
	return table


static func _dirs(root: String, prefix: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		push_error("QuestSet: 目录不存在 %s" % root)
		return result
	for name: String in directory.get_directories():
		if name.begins_with(prefix) and name.substr(1).is_valid_int():
			result.append(name)
	result.sort_custom(func(a: String, b: String) -> bool:
		return int(a.substr(1)) < int(b.substr(1)))
	return result


static func _merge_file(payloads: Dictionary, path: String) -> void:
	var table: TextTables = load(path)
	if table == null:
		push_error("QuestSet: 无法加载 %s" % path)
		return
	for key: String in table.payloads:
		var payload: Dictionary = table.payloads[key]
		if not payloads.has(key):
			payloads[key] = payload.duplicate(true)
			continue
		var target: Dictionary = payloads[key]
		if target.get("records") is Array and payload.get("records") is Array:
			target["records"].append_array(payload["records"])
			target["record_count"] = float(target["records"].size())
		elif target.get("groups") is Array and payload.get("groups") is Array:
			target["groups"].append_array(payload["groups"])
