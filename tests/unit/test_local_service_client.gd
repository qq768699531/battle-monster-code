extends "res://tests/unit/gut_case.gd"

const LocalServiceClient = preload("res://field/local_service_client/local_service_client.gd")
const LocalServiceProcess = preload("res://field/local_service_process/local_service_process.gd")
const Story = preload("res://core/story/story.gd")

## 这套用例打的是真实回环服务（见 `script/local_service/README.md`）。没人在 8765 上跑着的时候，
## 用例自己拉起一份：临时空闲端口 + 独立数据目录，跑完由 `LocalServiceProcess` 停掉，
## 既不依赖外部先启动服务，也不碰开发者 8765 上的数据。
const TEST_DATA_DIR := "user://local-service-test"
const READY_ATTEMPTS := 40

var _service: Node
var _port_probe := TCPServer.new()


## 和 `test_local_service_autostart` 一样按进程号散列探头找空闲端口，避免固定端口被占用。
func _available_port() -> int:
	for offset in range(40000):
		var candidate := 20000 + posmod(OS.get_process_id() + offset, 40000)
		if _port_probe.listen(candidate, "127.0.0.1") == OK:
			_port_probe.stop()
			return candidate
	return -1


func _start_local_service(client: Node) -> bool:
	var port := _available_port()
	if port <= 0:
		return false
	_service = LocalServiceProcess.new()
	get_tree().root.add_child(_service)
	var error: int = _service.configure()
	if error == OK:
		_service.port = port
		_service.data_dir = ProjectSettings.globalize_path(TEST_DATA_DIR)
		error = _service.start(ProjectSettings.globalize_path(
			"res://tools/local_service/local_server.py"))
	if error != OK:
		printerr("Local service could not start: ", _service.last_error)
		return false
	client.base_url = "http://127.0.0.1:%d/api/v1" % _service.port
	for _attempt in READY_ATTEMPTS:
		if client.request_json("service-health", HTTPClient.METHOD_GET, "/health"):
			var probe: Array = await client.response_received
			if probe[1] == 200:
				return true
		await get_tree().create_timer(0.25).timeout
	return false


func _stop_local_service() -> void:
	if _service == null:
		return
	_service.stop()
	_service.queue_free()
	_service = null
	var data_dir := ProjectSettings.globalize_path(TEST_DATA_DIR)
	DirAccess.remove_absolute(data_dir.path_join("service.json"))
	DirAccess.remove_absolute(data_dir)


func _run() -> void:
	var client := LocalServiceClient.new()
	var args := OS.get_cmdline_user_args()
	get_tree().root.add_child(client)
	if not args.is_empty():
		client.base_url = args[0]
	elif not await _start_local_service(client):
		_stop_local_service()
		pending("本地服务不可用；先跑 python tools/local_service/local_server.py 再验回环集成。")
		return
	client.request_json("network-time", HTTPClient.METHOD_GET, "/time")
	var time_response: Array = await client.response_received
	assert_true(time_response[0] == "network-time" and time_response[1] == 200 and
		time_response[2].server_time > 0 and client.token.is_empty(),
		"Original time synchronization works before account registration.")
	var identity := Crypto.new().generate_random_bytes(12).hex_encode()
	client.register("g_" + identity.substr(0, 20), identity + "_local_test")
	var registered: Array = await client.response_received
	assert_true(registered[0] == "register" and registered[1] == 201
		and registered[2] is Dictionary and registered[2].get("token") is String,
		"Godot client can register against the real loopback service.")
	client.token = registered[2].get("token", "") if registered[2] is Dictionary else ""
	client.upload_save(0, Story.initial_progress(0))
	await client.response_received
	client.download_save(0)
	var downloaded: Array = await client.response_received
	var envelope: Variant = downloaded[2].get("save") if downloaded[2] is Dictionary else null
	var progress_copy: Variant = \
		Story.normalize_integer_types(envelope.get("data")) if envelope is Dictionary else null
	assert_true(downloaded[1] == 200 and Story.validate_progress(progress_copy, 0),
		"Downloaded service saves remain compatible with StoryRuntime validation.")
	client.queue_free()
	_stop_local_service()


func test_legacy_suite() -> void:
	await _run()
