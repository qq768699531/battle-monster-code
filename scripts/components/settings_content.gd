extends Node2D
## 设置页内容投影。
func present(next_index: int, next_values: Dictionary, selected: bool, labels: Dictionary, active_arrows: Array[Texture2D], inactive_arrows: Array[Texture2D]) -> void:
	var narrow := next_index in [0, 2, 3]
	$Caption.text = str(labels.get(202 + next_index, ""))
	$NarrowArrows.visible = narrow
	$WideArrows.visible = not narrow
	var arrow_nodes := $NarrowArrows.get_children() if narrow else $WideArrows.get_children()
	for i in range(2):
		arrow_nodes[i].texture = active_arrows[i] if selected else inactive_arrows[i]
	$Value.visible = not narrow
	$FiveSegments.visible = next_index in [0, 2]
	$ThreeSegments.visible = next_index == 3
	if not narrow:
		var id: int = [208, 209, 210][int(next_values.sound_mode)] if next_index == 1 else [211, 212][int(next_values.display)]
		$Value.text = str(labels.get(id, ""))
		return
	var value: int = int(next_values.speed) + 1 if next_index == 0 else (
		int(next_values.volume) if next_index == 2 else int(next_values.vibration))
	var segments := $ThreeSegments.get_children() if next_index == 3 else $FiveSegments.get_children()
	for i in range(segments.size()):
		segments[i].color = Color.WHITE if selected and i < value else (
			Color("#196485") if i < value else Color("#0E1B2F"))
		segments[i].get_node("Highlight").visible = selected and i < value
