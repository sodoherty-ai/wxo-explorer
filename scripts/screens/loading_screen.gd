extends Control

signal data_ready(graph_data: WxODataModel.GraphData)
signal back_pressed

@onready var log_label: RichTextLabel = %LogLabel
@onready var back_button: Button = %BackButton

var _wxo_client: WxOClient


func _ready():
	back_button.pressed.connect(func(): back_pressed.emit())
	back_button.visible = false

	_wxo_client = WxOClient.new()
	add_child(_wxo_client)
	_wxo_client.data_fetched.connect(_on_data_fetched)
	_wxo_client.fetch_error.connect(_on_fetch_error)

	_start_fetch()


func _start_fetch():
	var config = ConfigData.load_config()
	_log("Server: " + config.server_url)
	var mode_names = {
		ConfigData.AuthMode.LOCAL_BEARER: "Local Bearer",
		ConfigData.AuthMode.WXO_API_KEY: "API Key (wxO)",
		ConfigData.AuthMode.IBM_CLOUD_API_KEY: "API Key (IBM Cloud)",
	}
	_log("Auth mode: " + mode_names.get(config.auth_mode, "Unknown"))

	_wxo_client.configure(config)
	_wxo_client.debug_log.connect(_on_debug_log)
	_log("Starting parallel fetch (agents + tools + knowledge bases)...")
	_wxo_client.fetch_all()


func _on_debug_log(message: String):
	_log(message)


func _on_data_fetched(graph_data: WxODataModel.GraphData):
	_log("")
	_log("=== Fetch Complete ===")
	_log("Agents: %d" % graph_data.agents.size())
	for id in graph_data.agents:
		var a = graph_data.agents[id]
		_log("  - %s (tools: %d, collabs: %d, kb: %d)" % [
			a.display_name, a.tool_ids.size(), a.collaborator_ids.size(), a.knowledge_base_ids.size()
		])
	_log("Tools: %d" % graph_data.tools.size())
	for id in graph_data.tools:
		var t = graph_data.tools[id]
		_log("  - %s" % t.name)
	_log("Knowledge Bases: %d" % graph_data.knowledge_bases.size())
	for id in graph_data.knowledge_bases:
		var kb = graph_data.knowledge_bases[id]
		_log("  - %s (%s)" % [kb.display_name, kb.status])
	_log("")
	_log("Entering 3D view in 2 seconds...")

	await get_tree().create_timer(2.0).timeout
	data_ready.emit(graph_data)


func _on_fetch_error(message: String):
	_log("")
	_log("[color=red]ERROR: " + message + "[/color]")
	_log("")
	_log("Check your server URL and credentials on the settings screen.")
	back_button.visible = true


func _log(message: String):
	print("[wxo-explorer] " + message)
	log_label.append_text(message + "\n")
