class_name LocalServiceClient
extends Node
## 本地兼容服务的 HTTP 客户端；响应经信号交回调用方。
## 这是本机模拟服务，不代表原版在线协议。

signal response_received(operation: String, status: int, payload: Variant)

const DEFAULT_BASE_URL := "http://127.0.0.1:8765/api/v1"
const MAX_RESPONSE_BYTES := 1_048_576

var base_url := DEFAULT_BASE_URL
var token := ""
var _requests: Dictionary = {}


func request_json(operation: String, method: int, path: String,
		payload: Dictionary = {}) -> bool:
	if operation.is_empty() or not path.begins_with("/") or path.contains(".."):
		push_error("Invalid local service operation or path.")
		return false
	var request := HTTPRequest.new()
	request.body_size_limit = MAX_RESPONSE_BYTES
	request.timeout = 1.0 if operation == "service-health" else 8.0
	add_child(request)
	_requests[request.get_instance_id()] = operation
	request.request_completed.connect(_on_request_completed.bind(request),
		CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Accept: application/json"])
	var body := ""
	if method in [HTTPClient.METHOD_POST, HTTPClient.METHOD_PUT, HTTPClient.METHOD_PATCH]:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var error := request.request(base_url + path, headers, method, body)
	if error != OK:
		_requests.erase(request.get_instance_id())
		request.queue_free()
		push_error("Could not send local service request: %s" % error_string(error))
		return false
	return true


func register(username: String, password: String) -> bool:
	return request_json("register", HTTPClient.METHOD_POST, "/auth/register",
		{"username": username, "password": password})


func login(username: String, password: String) -> bool:
	return request_json("login", HTTPClient.METHOD_POST, "/auth/login",
		{"username": username, "password": password})


func logout() -> bool:
	return request_json("logout", HTTPClient.METHOD_POST, "/auth/logout")


func upload_save(slot: int, save: Dictionary) -> bool:
	if slot not in [0, 1]:
		push_error("Local service save slot must be 0 or 1.")
		return false
	return request_json("upload-save", HTTPClient.METHOD_PUT, "/saves/%d" % slot,
		{"save": save})


func download_save(slot: int) -> bool:
	if slot not in [0, 1]:
		push_error("Local service save slot must be 0 or 1.")
		return false
	return request_json("download-save", HTTPClient.METHOD_GET, "/saves/%d" % slot)


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	var instance_id := request.get_instance_id()
	var operation: String = _requests.get(instance_id, "")
	_requests.erase(instance_id)
	if result != HTTPRequest.RESULT_SUCCESS:
		response_received.emit(operation, 0, {
			"error": "connection_failed",
			"message": "本地服务连接失败；请先启动 script/local_service/local_server.py。",
		})
		request.queue_free()
		return
	var json := JSON.new()
	var parse_error := json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		response_received.emit(operation, response_code, {
			"error": "invalid_response",
			"message": "本地服务返回了无效 JSON。",
		})
	else:
		var payload: Variant = json.data
		response_received.emit(operation, response_code, payload)
	request.queue_free()
