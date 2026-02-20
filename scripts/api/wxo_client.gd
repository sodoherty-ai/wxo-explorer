class_name WxOClient
extends Node

signal connection_tested(success: bool, message: String)
signal data_fetched(graph_data: WxODataModel.GraphData)
signal fetch_error(message: String)
signal debug_log(message: String)

var _base_url: String
var _auth_header: String
var _http: HTTPRequest
var _iam_manager: IamTokenManager
var _is_local: bool = true


func _ready():
	_http = HTTPRequest.new()
	add_child(_http)


func configure(config: ConfigData, iam_manager: IamTokenManager = null) -> void:
	_base_url = config.get_base_api_url()
	_is_local = (config.auth_mode == ConfigData.AuthMode.LOCAL_BEARER)
	_iam_manager = iam_manager
	if iam_manager:
		_auth_header = ""  # Will be set dynamically from IAM manager
	else:
		_auth_header = config.get_auth_header()


func _get_auth_header() -> String:
	if _iam_manager:
		return _iam_manager.get_auth_header()
	return _auth_header


func test_connection() -> void:
	if _iam_manager and not _iam_manager.is_token_valid():
		var success = await _iam_manager.ensure_token()
		if not success:
			connection_tested.emit(false, "Failed to obtain IAM token")
			return
	var url = _base_url + "/v1/orchestrate/agents"
	var headers = ["Authorization: " + _get_auth_header()]
	_http.request_completed.connect(_on_test_completed, CONNECT_ONE_SHOT)
	var err = _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		connection_tested.emit(false, "HTTP request failed to start (error %d)" % err)


func fetch_all() -> void:
	if _iam_manager and not _iam_manager.is_token_valid():
		var success = await _iam_manager.ensure_token()
		if not success:
			fetch_error.emit("Failed to obtain IAM token")
			return
	# Fetch sequentially (local dev server may not handle concurrent requests)
	var agents_result = await _fetch_endpoint("/v1/orchestrate/agents", "Agents")
	var tools_path = "/v1/tools" if _is_local else "/v1/orchestrate/tools"
	var tools_result = await _fetch_endpoint(tools_path, "Tools")
	var kb_result = await _fetch_endpoint("/v1/orchestrate/knowledge-bases", "Knowledge bases")

	# Check for errors
	var errors: Array[String] = []
	if agents_result.error:
		errors.append("Agents: " + agents_result.message)
	if tools_result.error:
		errors.append("Tools: " + tools_result.message)
	if kb_result.error:
		errors.append("Knowledge bases: " + kb_result.message)
	if not errors.is_empty():
		fetch_error.emit("Fetch failed - " + ", ".join(errors))
		return

	# Build graph data
	var graph = WxODataModel.GraphData.new()
	for d in agents_result.data:
		var agent = WxODataModel.AgentData.from_dict(d)
		graph.agents[agent.id] = agent
	for d in tools_result.data:
		var tool = WxODataModel.ToolData.from_dict(d)
		graph.tools[tool.id] = tool
	for d in kb_result.data:
		var kb = WxODataModel.KnowledgeBaseData.from_dict(d)
		graph.knowledge_bases[kb.id] = kb

	data_fetched.emit(graph)


func _log(message: String):
	debug_log.emit(message)


# --- Internal helpers ---

class _ApiResult:
	var error: bool
	var message: String
	var data: Array

	static func ok(arr: Array) -> _ApiResult:
		var r = _ApiResult.new()
		r.error = false
		r.data = arr
		return r

	static func fail(msg: String) -> _ApiResult:
		var r = _ApiResult.new()
		r.error = true
		r.message = msg
		r.data = []
		return r


func _fetch_endpoint(path: String, label: String) -> _ApiResult:
	_log("GET %s%s" % [_base_url, path])
	var http = _start_request(path)
	if not http:
		_log("%s: ERROR - failed to start request" % label)
		return _ApiResult.fail("Failed to start request")
	var raw = await http.request_completed
	http.queue_free()
	_log("%s: HTTP %d (%d bytes)" % [label, raw[1], raw[3].size()])
	var result = _parse_response(raw)
	if result.error:
		_log("%s: PARSE ERROR - %s" % [label, result.message])
	else:
		_log("%s: OK (%d items)" % [label, result.data.size()])
	return result


func _start_request(path: String) -> HTTPRequest:
	var url = _base_url + path
	var headers = ["Authorization: " + _get_auth_header()]
	var http = HTTPRequest.new()
	add_child(http)
	var err = http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_log("ERROR starting request for %s (error %d)" % [path, err])
		http.queue_free()
		return null
	return http


func _parse_response(raw: Array) -> _ApiResult:
	var response_code: int = raw[1]
	var body: PackedByteArray = raw[3]
	if response_code < 200 or response_code >= 300:
		return _ApiResult.fail("HTTP %d" % response_code)
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return _ApiResult.fail("JSON parse error")
	var result = json.data
	if result is Array:
		return _ApiResult.ok(result)
	elif result is Dictionary:
		if result.has("detail"):
			return _ApiResult.fail(str(result["detail"]))
		return _ApiResult.ok([result])
	return _ApiResult.fail("Unexpected response format")


func _on_test_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		connection_tested.emit(false, "HTTP %d - check server URL and credentials" % response_code)
		return
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		connection_tested.emit(false, "Invalid JSON response")
		return
	var data = json.data
	var count = data.size() if data is Array else 1
	connection_tested.emit(true, "Connected - found %d agent(s)" % count)
