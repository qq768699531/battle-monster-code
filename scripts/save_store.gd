extends RefCounted

## Two independent native ConfigFile slots. The directory must already exist.
## load_slot returns an envelope: status (empty/ready/error), occupied, error,
## progress, and summary. Only empty slots get StoryRuntime.initial_progress().
## Errors remain occupied and save refuses to overwrite them.
const Story = preload("res://scripts/story.gd")
const FORMAT := "battlemonster.native-save"
const VERSION := 1

var directory: String


func _init(save_directory: String = "user://") -> void:
	directory = save_directory


func slot_path(slot: int) -> String:
	return directory.path_join("native-slot-%d.cfg" % slot)


func _result(slot: int, status: String, error: int, progress: Dictionary = {}) -> Dictionary:
	var summary := {}
	if status == "ready":
		summary = {
			"slot": slot, "mapId": progress["mapId"], "quest": progress["quest"],
			"eventId": progress["eventId"], "level": progress["parameter"]["level"],
		}
	return {
		"slot": slot, "status": status, "occupied": status != "empty",
		"error": error, "progress": progress, "summary": summary,
	}


func _read(path: String, slot: int) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return _result(slot, "error", error)
	if config.get_value("save", "format", null) != FORMAT or \
			config.get_value("save", "version", null) != VERSION or \
			config.get_value("save", "slot", null) != slot:
		return _result(slot, "error", ERR_INVALID_DATA)
	var progress: Variant = config.get_value("save", "progress", null)
	if not Story.validate_progress(progress, slot):
		return _result(slot, "error", ERR_INVALID_DATA)
	return _result(slot, "ready", OK, progress.duplicate(true))


func load_slot(slot: int) -> Dictionary:
	if slot not in [0, 1]:
		return _result(slot, "error", ERR_INVALID_PARAMETER)
	var folder := DirAccess.open(directory)
	if folder == null:
		return _result(slot, "error", DirAccess.get_open_error())
	var filename := slot_path(slot).get_file()
	if folder.dir_exists(filename):
		return _result(slot, "error", ERR_FILE_CANT_READ)
	if not folder.file_exists(filename):
		return _result(slot, "empty", OK, Story.initial_progress(slot))
	return _read(slot_path(slot), slot)


func slot_summary(slot: int) -> Dictionary:
	var result := load_slot(slot)
	result.erase("progress")
	return result


func delete_slot(slot: int) -> int:
	if slot not in [0, 1]:
		return ERR_INVALID_PARAMETER
	var existing := load_slot(slot)
	if existing.status == "error":
		return existing.error
	if existing.status == "empty":
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


func slots() -> Array:
	return [slot_summary(0), slot_summary(1)]


func check_storage() -> int:
	var folder := DirAccess.open(directory)
	if folder == null:
		return DirAccess.get_open_error()
	for slot in range(2):
		if folder.dir_exists(slot_path(slot).get_file()):
			return ERR_FILE_CANT_WRITE
	var path := directory.path_join(".prime-storage-%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()])
	if FileAccess.file_exists(path) or folder.dir_exists(path.get_file()):
		return ERR_ALREADY_EXISTS
	var probe := FileAccess.open(path, FileAccess.WRITE)
	if probe == null:
		return FileAccess.get_open_error()
	var bytes := PackedByteArray()
	bytes.resize(2 * 9576)
	probe.store_buffer(bytes)
	probe.flush()
	var error := probe.get_error()
	if error == OK and probe.get_length() != bytes.size():
		error = ERR_FILE_CANT_WRITE
	probe.close()
	var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return error if error != OK else cleanup


## Write and validate a same-directory staging file before replacing the slot.
## A failed write/validation/rename leaves the previous committed file intact.
## Interrupted staging files are never treated as committed progress.
func save(slot: int, progress: Dictionary) -> int:
	if slot not in [0, 1]:
		return ERR_INVALID_PARAMETER
	if not Story.validate_progress(progress, slot):
		return ERR_INVALID_DATA
	var existing := load_slot(slot)
	if existing["status"] == "error":
		return existing["error"]
	var path := slot_path(slot)
	var pending := path + ".pending"
	var config := ConfigFile.new()
	config.set_value("save", "format", FORMAT)
	config.set_value("save", "version", VERSION)
	config.set_value("save", "slot", slot)
	config.set_value("save", "progress", progress.duplicate(true))
	var error := config.save(pending)
	if error != OK:
		return error
	var verified := _read(pending, slot)
	if verified["status"] != "ready" or not _same_progress(verified["progress"], progress):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending))
		return ERR_INVALID_DATA
	# Recheck before committing: a corrupt externally replaced slot must survive.
	existing = load_slot(slot)
	if existing["status"] == "error":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending))
		return existing["error"]
	error = _commit_save(pending, path)
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending))
	return error


func _commit_save(pending: String, path: String) -> int:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(path))


## ConfigFile 文本往返会把浮点降精度（角色坐标带小数时 6.67706727981567 读回 6.6770673），
## 校验必须按浮点容差比较，否则合法存档会被判成 ERR_INVALID_DATA。
static func _same_progress(before: Variant, after: Variant) -> bool:
	if before is float or after is float:
		if not (before is float or before is int) or not (after is float or after is int):
			return false
		return is_equal_approx(float(before), float(after))
	if before is Dictionary and after is Dictionary:
		if before.size() != after.size():
			return false
		for key: Variant in before:
			if not after.has(key) or not _same_progress(before[key], after[key]):
				return false
		return true
	if before is Array and after is Array:
		if before.size() != after.size():
			return false
		for index in range(before.size()):
			if not _same_progress(before[index], after[index]):
				return false
		return true
	return before == after
