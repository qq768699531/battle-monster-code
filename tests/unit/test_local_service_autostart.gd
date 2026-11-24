extends "res://tests/unit/gut_case.gd"

const LocalServiceProcess = preload("res://field/local_service_process/local_service_process.gd")

const PORT_ENV := "BATTLEMONSTER_LOCAL_SERVICE_PORT"
const DATA_DIR_ENV := "BATTLEMONSTER_LOCAL_SERVICE_DATA_DIR"

var server := TCPServer.new()
var supervisor: Node
var data_dir := ""
var previous_port := ""
var previous_data_dir := ""


func _available_port() -> int:
	for offset in range(40000):
		var candidate := 20000 + posmod(OS.get_process_id() + offset, 40000)
		if server.listen(candidate, "127.0.0.1") == OK:
			server.stop()
			return candidate
	return -1


func _run() -> void:
	previous_port = OS.get_environment(PORT_ENV)
	previous_data_dir = OS.get_environment(DATA_DIR_ENV)
	var port := _available_port()
	if port <= 0:
		pending("No free loopback port for the local service test.")
		_cleanup()
		return
	data_dir = ProjectSettings.globalize_path(
		"user://local-service-autostart-%d" % Time.get_ticks_usec())
	OS.set_environment(PORT_ENV, str(port))
	OS.set_environment(DATA_DIR_ENV, data_dir)
	supervisor = LocalServiceProcess.new()
	get_tree().root.add_child(supervisor)
	assert_true(supervisor.configure() == OK and supervisor.port == port and supervisor.data_dir == data_dir,
		"The role environment configures the spawned service.")
	var script_path := ProjectSettings.globalize_path(
		"res://tools/local_service/local_server.py")
	assert_true(supervisor.start(script_path) == OK and supervisor.process_id > 0 and
		OS.is_process_running(supervisor.process_id),
		"Prime starts the bundled local service process: %s" % supervisor.last_error)
	var output: Array = []
	var client_exit := OS.execute("python", ["-c", _health_probe_script(), str(port)],
		output, true)
	var response: Variant = JSON.parse_string(str(output[0])) if not output.is_empty() else null
	assert_true(client_exit == 0 and response is Dictionary and response.get("ok", false),
		"The automatically launched service answers its health endpoint.")
	supervisor.free()
	_cleanup()


func _health_probe_script() -> String:
	return "import json, sys, time, urllib.request\n" + \
		"url = 'http://127.0.0.1:' + sys.argv[1] + '/api/v1/health'\n" + \
		"deadline = time.monotonic() + 10\n" + \
		"while time.monotonic() < deadline:\n" + \
		"    try:\n" + \
		"        with urllib.request.urlopen(url, timeout=1) as response:\n" + \
		"            print(response.read().decode('utf-8'))\n" + \
		"            sys.exit(0)\n" + \
		"    except OSError:\n" + \
		"        time.sleep(0.1)\n" + \
		"sys.exit(1)\n"


func _cleanup() -> void:
	OS.set_environment(PORT_ENV, previous_port)
	OS.set_environment(DATA_DIR_ENV, previous_data_dir)
	if is_instance_valid(supervisor):
		supervisor.queue_free()
	if not data_dir.is_empty() and DirAccess.dir_exists_absolute(data_dir):
		var directory := DirAccess.open(data_dir)
		if directory != null:
			for file_name in directory.get_files():
				DirAccess.remove_absolute(data_dir.path_join(file_name))
			DirAccess.remove_absolute(data_dir)


func test_legacy_suite() -> void:
	_run()
