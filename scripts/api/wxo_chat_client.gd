class_name WxOChatClient
extends Node

signal message_received(text: String)
signal chat_error(message: String)
signal thinking_started
signal thinking_finished
signal debug_log(message: String)

var _base_url: String
var _auth_header: String
var _thread_id: String = ""
var _agent_id: String = ""
var _http: HTTPRequest


func _ready():
	_http = HTTPRequest.new()
	_http.timeout = 120
	add_child(_http)


func configure(config: ConfigData) -> void:
	_base_url = config.server_url.rstrip("/") + "/api"
	_auth_header = config.get_auth_header()


func restore_session(agent_id: String, thread_id: String) -> void:
	_agent_id = agent_id
	_thread_id = thread_id


func start_session(agent_id: String) -> void:
	_agent_id = agent_id
	_thread_id = ""
	# Create a new thread for this agent
	var http = HTTPRequest.new()
	add_child(http)
	var headers = [
		"Authorization: " + _auth_header,
		"Content-Type: application/json",
	]
	var body = JSON.stringify({"agent_id": agent_id})
	http.request_completed.connect(_on_thread_created.bind(http))
	var err = http.request(_base_url + "/v1/threads", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		chat_error.emit("Failed to create thread")


func send_message(text: String) -> void:
	if _agent_id.is_empty():
		chat_error.emit("No agent selected")
		return

	thinking_started.emit()

	var headers = [
		"Authorization: " + _auth_header,
		"Content-Type: application/json",
	]

	var body_dict = {
		"message": {"role": "user", "content": text},
		"agent_id": _agent_id,
	}
	if not _thread_id.is_empty():
		body_dict["thread_id"] = _thread_id

	var body = JSON.stringify(body_dict)

	var http = HTTPRequest.new()
	http.timeout = 120
	add_child(http)
	http.request_completed.connect(_on_run_completed.bind(http))
	var err = http.request(_base_url + "/v1/orchestrate/runs/stream", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		thinking_finished.emit()
		chat_error.emit("Failed to send message")


func _on_thread_created(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var body_str = body.get_string_from_utf8()
	debug_log.emit("Thread response (HTTP %d): %s" % [response_code, body_str.left(500)])
	if response_code < 200 or response_code >= 300:
		chat_error.emit("Failed to create thread (HTTP %d)" % response_code)
		return
	var json = JSON.new()
	if json.parse(body_str) != OK:
		chat_error.emit("Invalid thread response")
		return
	var data = json.data
	if data is Dictionary and data.has("id"):
		_thread_id = str(data["id"])
	elif data is Dictionary and data.has("thread_id"):
		_thread_id = str(data["thread_id"])
	debug_log.emit("Thread ID: %s" % _thread_id)


func _on_run_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	thinking_finished.emit()

	var body_str = body.get_string_from_utf8()
	debug_log.emit("Run response (HTTP %d, %d bytes):\n%s" % [response_code, body_str.length(), body_str.left(2000)])

	if response_code < 200 or response_code >= 300:
		var error_text = "HTTP %d" % response_code
		var json = JSON.new()
		if json.parse(body_str) == OK and json.data is Dictionary:
			if json.data.has("detail"):
				error_text = str(json.data["detail"])
		chat_error.emit(error_text)
		return

	var reply = _parse_sse_response(body_str)
	debug_log.emit("SSE parse result: '%s'" % reply.left(200))

	if reply.is_empty():
		reply = _parse_json_response(body_str)
		debug_log.emit("JSON parse result: '%s'" % reply.left(200))

	if reply.is_empty():
		chat_error.emit("No response from agent")
	else:
		message_received.emit(reply)


func _parse_sse_response(body: String) -> String:
	# Parse newline-delimited JSON (NDJSON) response from wxO runs/stream
	var content_parts: Array[String] = []

	for line in body.split("\n"):
		var trimmed = line.strip_edges()
		if trimmed.is_empty():
			continue

		# Handle both NDJSON (raw JSON per line) and SSE (data: prefix)
		var json_str = trimmed
		if trimmed.begins_with("data:"):
			json_str = trimmed.substr(5).strip_edges()
		if json_str == "[DONE]":
			continue

		var json = JSON.new()
		if json.parse(json_str) != OK:
			continue

		var event_data = json.data
		if not event_data is Dictionary:
			continue

		var event_type = event_data.get("event", "")
		var data = event_data.get("data", {})
		if not data is Dictionary:
			continue

		# message.delta: collect content fragments
		if event_type == "message.delta":
			var delta = data.get("delta", {})
			if delta is Dictionary:
				var content = delta.get("content", [])
				if content is Array:
					for part in content:
						if part is Dictionary:
							var text = part.get("text", "")
							if text is String and not text.is_empty():
								content_parts.append(text)

		# message.created: may contain the full assembled message
		elif event_type == "message.created":
			var message = data.get("message", {})
			if message is Dictionary:
				var content = message.get("content", [])
				if content is Array:
					for part in content:
						if part is Dictionary:
							var text = part.get("text", "")
							if text is String and not text.is_empty():
								return text

	if not content_parts.is_empty():
		return "".join(content_parts)

	return ""


func _parse_json_response(body: String) -> String:
	var json = JSON.new()
	if json.parse(body) != OK:
		return ""
	var data = json.data
	if not data is Dictionary:
		return ""

	# OpenAI-style response
	if data.has("choices"):
		var choices = data["choices"]
		if choices is Array and not choices.is_empty():
			var first = choices[0]
			if first is Dictionary:
				var msg = first.get("message", {})
				if msg is Dictionary:
					return msg.get("content", "")

	# Direct message field
	if data.has("message"):
		var msg = data["message"]
		if msg is String:
			return msg

	# Output field
	if data.has("output"):
		var output = data["output"]
		if output is String:
			return output
		elif output is Array:
			for item in output:
				if item is Dictionary:
					var content = item.get("content", "")
					if content is String and not content.is_empty():
						return content

	return ""
