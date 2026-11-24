extends RefCounted
## 战斗区域页面的状态机。

const C = preload("res://game/prime/data/runtime_constants/runtime_constants.gd")
const View = preload("res://game/prime/title/battle_zone_scene/battle_zone_scene.gd")

var network_battle_zone := false
var network_battle_selected := 0
var network_battle_stats := {}


func open(context: RefCounted, payload: Dictionary) -> void:
	network_battle_zone = true
	network_battle_selected = 0
	network_battle_stats = _battle_zone_stats(payload)
	context.window_state = 1


func dispatch(context: RefCounted, key: int) -> void:
	if key == TouchCode.Key.BACK:
		network_battle_zone = false
		context.window_state = 1
		context._clear_input()
	elif key in [TouchCode.Pad.UP, TouchCode.Pad.DOWN]:
		network_battle_selected = posmod(network_battle_selected + (-1 if key == TouchCode.Pad.UP else 1),
			View.BUTTON_COUNT)
	elif key == TouchCode.Key.OK:
		context.network_request_pending = true
		context._pending_effects.append({"kind": "local-service-request",
			"action": ["battle-quick", "battle-ranked", "battle-friendly",
				"battle-challenge", "battle-ranking", "battle-log"][network_battle_selected],
			"slot": context.save_slot_selected})
		context._clear_input()


func paint_page(paint: Dictionary) -> void:
	paint.merge({"network_battle_zone": network_battle_zone,
		"network_battle_selected": network_battle_selected,
		"network_battle_stats": network_battle_stats.duplicate(true)})


static func _battle_integer(value: Variant) -> Variant:
	if (value is int or value is float) and is_finite(value) and \
			value >= -2147483647 and value <= 2147483647 and value == int(value):
		return int(value)
	return null


static func _battle_zone_stats(payload: Dictionary) -> Dictionary:
	var stats := {"rank": _battle_integer(payload.get("rank")),
		"rank_change": _battle_integer(payload.get("rank_change"))}
	for mode in ["ranked", "friendly", "offline"]:
		for result in ["wins", "losses"]:
			stats[mode + "_" + result] = null
	var log: Variant = payload.get("log")
	if not log is Array:
		return stats
	# The service retains only 100 log entries; incomplete history is not a lifetime total.
	var total := 0
	for key in ["wins", "losses", "draws"]:
		var count: Variant = _battle_integer(payload.get(key))
		if count == null or count < 0:
			return stats
		total += int(count)
	if total != log.size():
		return stats
	for key in stats:
		if key not in ["rank", "rank_change"]:
			stats[key] = 0
	for record: Variant in log:
		if not record is Dictionary:
			for key in stats:
				if key not in ["rank", "rank_change"]:
					stats[key] = null
			return stats
		var mode := str(record.get("mode", ""))
		if mode in ["quick", "ranked"]:
			mode = "ranked"
		elif mode in ["local", "offline"]:
			mode = "offline"
		if mode not in ["ranked", "friendly", "offline"]:
			continue
		var result := str(record.get("result", ""))
		if result in ["win", "loss"]:
			stats[mode + ("_wins" if result == "win" else "_losses")] += 1
	return stats
