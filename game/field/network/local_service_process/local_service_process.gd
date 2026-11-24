extends Node
## 在游戏进程内拉起/停止本地兼容服务，并暴露实际端口。

const DEFAULT_PORT := 8765
const PORT_ENV := "BATTLEMONSTER_LOCAL_SERVICE_PORT"
const DATA_DIR_ENV := "BATTLEMONSTER_LOCAL_SERVICE_DATA_DIR"

var port := DEFAULT_PORT
var data_dir := ""
var process_id := -1
var last_error := ""


func configure() -> int:
	port = DEFAULT_PORT
	data_dir = ""
	last_error = ""
	var port_text := OS.get_environment(PORT_ENV).strip_edges()
	if not port_text.is_empty():
		if not port_text.is_valid_int():
			last_error = "%s must be an integer port." % PORT_ENV
			return ERR_INVALID_PARAMETER
		port = port_text.to_int()
		if port < 1024 or port > 65535:
			last_error = "%s must be between 1024 and 65535." % PORT_ENV
			return ERR_INVALID_PARAMETER
	data_dir = OS.get_environment(DATA_DIR_ENV).strip_edges()
	return OK


func start(script_path: String) -> int:
	if not last_error.is_empty():
		return ERR_INVALID_PARAMETER
	if process_id > 0 and OS.is_process_running(process_id):
		return OK
	if not FileAccess.file_exists(script_path):
		last_error = "Local service script was not found: " + script_path
		return ERR_FILE_NOT_FOUND
	var arguments := [script_path, "--port", str(port)]
	if not data_dir.is_empty():
		arguments.append_array(["--data-dir", data_dir])
	process_id = OS.create_process("python", arguments, false)
	if process_id <= 0:
		last_error = "Could not start Python for the local service."
		return ERR_CANT_CREATE
	return OK


func stop() -> void:
	if process_id > 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
	process_id = -1


func _exit_tree() -> void:
	stop()
