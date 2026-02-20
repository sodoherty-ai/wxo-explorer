class_name ConfigData
extends Resource

enum AuthMode { LOCAL_BEARER, WXO_API_KEY, IBM_CLOUD_API_KEY }

@export var server_url: String = "http://localhost:4321"
@export var auth_mode: int = AuthMode.LOCAL_BEARER
@export var bearer_token: String = ""
@export var api_key: String = ""

const SAVE_PATH = "user://config.tres"
const CREDENTIALS_RELATIVE = ".cache/orchestrate/credentials.yaml"


func save_config() -> void:
	ResourceSaver.save(self, SAVE_PATH)


static func load_config() -> ConfigData:
	if ResourceLoader.exists(SAVE_PATH):
		return ResourceLoader.load(SAVE_PATH) as ConfigData
	return ConfigData.new()


static func read_local_bearer_token() -> String:
	var path = _find_credentials_file()
	if path.is_empty():
		return ""
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var content = file.get_as_text()
	file.close()
	for line in content.split("\n"):
		var trimmed = line.strip_edges()
		if trimmed.begins_with("wxo_mcsp_token:"):
			return trimmed.substr(trimmed.find(":") + 1).strip_edges()
	return ""


static func _find_credentials_file() -> String:
	# macOS / Linux: ~/.cache/orchestrate/credentials.yaml
	var home = OS.get_environment("HOME")
	if not home.is_empty():
		var path = home.path_join(CREDENTIALS_RELATIVE)
		if FileAccess.file_exists(path):
			return path

	# Windows: %USERPROFILE%\.cache\orchestrate\credentials.yaml
	var userprofile = OS.get_environment("USERPROFILE")
	if not userprofile.is_empty():
		var path = userprofile.path_join(CREDENTIALS_RELATIVE)
		if FileAccess.file_exists(path):
			return path

	# Windows fallback: %APPDATA%\orchestrate\credentials.yaml
	var appdata = OS.get_environment("APPDATA")
	if not appdata.is_empty():
		var path = appdata.path_join("orchestrate/credentials.yaml")
		if FileAccess.file_exists(path):
			return path

	return ""


func get_auth_header() -> String:
	match auth_mode:
		AuthMode.LOCAL_BEARER:
			return "Bearer " + bearer_token
		AuthMode.WXO_API_KEY, AuthMode.IBM_CLOUD_API_KEY:
			return "Bearer " + api_key  # Placeholder; IAM manager replaces this
		_:
			return ""


func uses_iam() -> bool:
	return auth_mode in [AuthMode.WXO_API_KEY, AuthMode.IBM_CLOUD_API_KEY]


func get_base_api_url() -> String:
	var url = server_url.rstrip("/")
	match auth_mode:
		AuthMode.LOCAL_BEARER:
			return url + "/api"  # Local dev: http://localhost:4321/api
		_:
			return url  # SaaS: instance URL is the base already
