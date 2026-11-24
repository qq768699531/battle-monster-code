extends Control
## 战斗数值行组合件。

@export var heading_id := 0
@export var left_key := ""
@export var right_key := ""


func present(headings: Dictionary, stats: Dictionary) -> void:
	get_node("Heading").set_line(headings[heading_id])
	for column in ["Left", "Right"]:
		var value: Variant = stats.get(left_key if column == "Left" else right_key)
		get_node(column + "/Number").text = "--" if value == null else str(value)
