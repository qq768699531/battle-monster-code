extends Control
## 左上角色摘要：头像、LV/EXP 图标与进度条。

var _level := -1
var _experience: Variant = -1


func _ready() -> void:
	hide()


func present(parameter: Dictionary) -> void:
	var level: int = parameter.level
	var experience: Variant = parameter.get("development", {}).get("experience")
	if level != _level:
		$Level.present(str(level))
	if experience != _experience:
		$Experience.visible = experience != null
		$UnknownExperience.visible = experience == null
		if experience != null:
			$Experience.present(str(experience))
	if level != _level or experience != _experience:
		# Param_expINIT(6): player EXP is a within-level remainder, not island progress.
		$Gauge/Track/Fill.offset_right = 0 if experience == null else floorf(
			$Gauge/Track.size.x * clampf(float(experience) / maxi(1, 65 * level * level), 0.0, 1.0))
	_level = level
	_experience = experience
