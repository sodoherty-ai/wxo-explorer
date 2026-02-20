class_name IamTokenManager
extends Node

## Exchanges an API key for a bearer token via IBM Cloud IAM or wxO MCSP, and refreshes before expiry.

signal token_refreshed(token: String)
signal token_error(message: String)
signal debug_log(message: String)

const IBM_CLOUD_IAM_URL = "https://iam.cloud.ibm.com/identity/token"
const MCSP_TOKEN_URL = "https://iam.platform.saas.ibm.com/siusermgr/api/1.0/apikeys/token"
const REFRESH_MARGIN = 300  # Refresh 5 minutes before expiry

var _api_key: String
var _auth_mode: int  # ConfigData.AuthMode
var _access_token: String = ""
var _expiration: int = 0  # Unix timestamp
var _refreshing: bool = false


func configure(api_key: String, auth_mode: int = ConfigData.AuthMode.WXO_API_KEY) -> void:
	# Only reset token if credentials changed
	if _api_key != api_key or _auth_mode != auth_mode:
		_access_token = ""
		_expiration = 0
	_api_key = api_key
	_auth_mode = auth_mode


func get_auth_header() -> String:
	return "Bearer " + _access_token


func is_token_valid() -> bool:
	if _access_token.is_empty():
		return false
	return int(Time.get_unix_time_from_system()) < (_expiration - REFRESH_MARGIN)


func ensure_token() -> bool:
	if is_token_valid():
		return true
	if _refreshing:
		var result = await token_refreshed
		return not _access_token.is_empty()
	return await _exchange_token()


func _exchange_token() -> bool:
	_refreshing = true

	var http = HTTPRequest.new()
	add_child(http)

	var url: String
	var headers: Array
	var body: String

	if _auth_mode == ConfigData.AuthMode.IBM_CLOUD_API_KEY:
		# IBM Cloud IAM: form-encoded
		url = IBM_CLOUD_IAM_URL
		headers = [
			"Content-Type: application/x-www-form-urlencoded",
			"Accept: application/json",
		]
		body = "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=" + _api_key.uri_encode()
	else:
		# wxO MCSP: JSON body
		url = MCSP_TOKEN_URL
		headers = [
			"Content-Type: application/json",
			"Accept: application/json",
		]
		body = JSON.stringify({"apikey": _api_key})

	print("[IAM] Requesting token from ", url)
	debug_log.emit("Requesting token from %s..." % url)

	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[IAM] Failed to start request, error: ", err)
		http.queue_free()
		_refreshing = false
		token_error.emit("Failed to start token request (error %d)" % err)
		return false

	var raw = await http.request_completed
	http.queue_free()

	var result_code: int = raw[0]
	var response_code: int = raw[1]
	var response_body: PackedByteArray = raw[3]
	var body_str = response_body.get_string_from_utf8()

	print("[IAM] Result: %d, HTTP: %d, Body (%d bytes): %s" % [result_code, response_code, body_str.length(), body_str.left(500)])

	if result_code != HTTPRequest.RESULT_SUCCESS:
		_refreshing = false
		var msg = "Token request failed (result %d) - check internet connection" % result_code
		print("[IAM] ", msg)
		token_error.emit(msg)
		return false

	if response_code < 200 or response_code >= 300:
		debug_log.emit("Token error (HTTP %d): %s" % [response_code, body_str.left(500)])
		_refreshing = false
		token_error.emit("Token exchange failed (HTTP %d)" % response_code)
		return false

	var json = JSON.new()
	if json.parse(body_str) != OK:
		print("[IAM] JSON parse error")
		_refreshing = false
		token_error.emit("Invalid token response")
		return false

	var data = json.data
	if not data is Dictionary:
		print("[IAM] Unexpected response type: ", typeof(data))
		_refreshing = false
		token_error.emit("Unexpected token response format")
		return false

	# IBM Cloud IAM returns "access_token" + "expiration" (unix timestamp)
	# MCSP returns "token" + "expires_in" (seconds)
	if data.has("access_token"):
		_access_token = data["access_token"]
		_expiration = int(data.get("expiration", 0))
	elif data.has("token"):
		_access_token = data["token"]
		var expires_in = int(data.get("expires_in", 7200))
		_expiration = int(Time.get_unix_time_from_system()) + expires_in
	else:
		print("[IAM] No token in response. Keys: ", data.keys())
		_refreshing = false
		token_error.emit("No token in response")
		return false

	if _access_token.is_empty():
		_refreshing = false
		token_error.emit("Empty token in response")
		return false

	var expires_in = _expiration - int(Time.get_unix_time_from_system())
	print("[IAM] Token obtained, expires in %d seconds" % expires_in)
	debug_log.emit("Token obtained, expires in %d seconds" % expires_in)
	_refreshing = false
	token_refreshed.emit(_access_token)
	return true
