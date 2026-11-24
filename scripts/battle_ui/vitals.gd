extends Control
## 战斗 HP/SP 等数值条。

@export var attributes: Array[Texture2D] = []


func present(ball: Dictionary, selected := false) -> void:
	$Selection.visible = selected
	$Attribute/Icon.texture = attributes[int(ball.attribute)]
	$Metrics/HP/Number.present("--" if ball.hp == null else str(ball.hp))
	$Metrics/SP/Number.present("%s/%s" % [
		"--" if ball.sp == null else str(ball.sp),
		"--" if ball.max_sp == null else str(ball.max_sp)])
	for name: String in ["HP", "SP"]:
		var key := name.to_lower()
		var track: Control = get_node("Metrics/" + name + "/Gauge/Track")
		var fill: Control = track.get_node("Fill")
		fill.visible = ball[key] != null and ball["max_" + key] != null
		if not fill.visible:
			continue
		fill.anchor_right = 0.0
		fill.offset_right = floorf(track.size.x * int(ball[key]) / maxi(1, int(ball["max_" + key])))
