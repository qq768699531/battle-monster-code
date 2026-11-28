extends Control
const PlayerData = preload("res://engine/data/player_data/player_data.gd")
## 精灵立绘组件：自己持有 `Hero`／`Monster` 两个 ANI 层与边框，谁把这份场景放进页面，
## 谁就在自己的渲染里调 `present_request()`。不再由 STATUS 页或菜单宿主跨页面驱动。
##
## 请求字典由持有页组装，形状沿用原 `status.gd` 的实现：
## `{"key": String, "layers": [{"path", "action", "direction", "offset"}], "monster": bool}`
## 缓存也归本实例所有，换页面、换成员互不干扰。

var _key := ""
var _frame_key := ""
var _error := ""


## 按请求重建立绘；空请求或层请求为空时整块收起。
func present_request(host: Control, request: Dictionary) -> void:
	if request.is_empty():
		_key = ""
		_frame_key = ""
		_error = ""
		$StatusPortraitLayers.visible = false
		$StatusPortraitBorder.visible = false
		return
	var layer_requests: Variant = request.get("layers", [])
	if not layer_requests is Array or layer_requests.is_empty():
		$StatusPortraitLayers.visible = false
		$StatusPortraitBorder.visible = false
		return
	var monster: Node2D = $StatusPortraitLayers/Monster
	var hero: Node2D = $StatusPortraitLayers/Hero
	var error: Control = $PortraitError
	monster.visible = bool(request.get("monster", false))
	hero.visible = String(request.get("key", "")) == "hero"
	error.hide()
	var requested_key := String(request["key"])
	if _key == requested_key and _frame_key == requested_key:
		if not _error.is_empty():
			error.show()
		return
	_key = requested_key
	_frame_key = requested_key
	_error = ""
	for layer_request: Dictionary in layer_requests:
		var path: String = layer_request["path"]
		# `obj/ui_eff` 是底板特效，由场景里的 `Effect` 常驻，不在 ANI 层里播。
		if path == "obj/ui_eff":
			continue
		var animation: Node2D = monster if path.begins_with("mon2/") else hero
		if not animation.present(path, int(layer_request["action"]),
				int(layer_request["direction"])):
			_error = animation.last_error
			error.show()
			$StatusPortraitLayers.visible = false
			$StatusPortraitBorder.visible = false
			return
		if animation == monster:
			monster.get_node("Content").position = layer_request["offset"]
	$StatusPortraitLayers.visible = true
	$StatusPortraitBorder.visible = true


## 组一个「按成员索引」的立绘请求（队伍页、队伍详情、道具二级窗共用）：
## 索引无效但还有栏位时给 `party:empty`（只有底板特效），否则按物种取 `mon2` 路径。
static func member_request(host: Control, member_index: int) -> Dictionary:
	var layers: Array[Dictionary] = [{
		"path": "obj/ui_eff", "action": 1, "frame": 0, "direction": 0,
	}]
	var monsters: Variant = host.story_progress.get("monsters", [])
	var capacity: Variant = PlayerData.monster_capacity(host.story_progress)
	if not monsters is Array:
		return {}
	if member_index < 0 or member_index >= monsters.size():
		if not monsters.is_empty() or (capacity is int and capacity >= 0):
			return {"key": "party:empty", "layers": layers}
		return {}
	var member: Variant = monsters[member_index]
	if not member is Dictionary:
		return {}
	var args: Variant = member.get("nativeArguments", [])
	if not args is Array or args.is_empty() or not args[0] is int:
		return {}
	var species_id: int = args[0]
	var base_species := species_id % 1000
	var form := 2 if species_id > 999 else 1
	var path := "mon2/m_b_%03d_%d" % [base_species, form]
	var offset: Vector2 = host.portrait_offset(base_species, form - 1)
	layers.append({"path": path, "action": 0, "direction": 0,
		"offset": Vector2(offset.x, -offset.y)})
	return {"key": "member:%d:%s" % [member_index, path], "layers": layers, "monster": true}
