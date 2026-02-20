extends Control

signal data_ready(graph_data: WxODataModel.GraphData)

@onready var server_url_input: LineEdit = %ServerURLInput
@onready var auth_mode_select: OptionButton = %AuthModeSelect
@onready var bearer_section: VBoxContainer = %BearerSection
@onready var bearer_token_input: LineEdit = %BearerTokenInput
@onready var auto_fill_button: Button = %AutoFillButton
@onready var api_key_section: VBoxContainer = %ApiKeySection
@onready var api_key_input: LineEdit = %ApiKeyInput
@onready var test_button: Button = %TestButton
@onready var enter_button: Button = %EnterButton
@onready var status_label: Label = %StatusLabel

var config: ConfigData
var _wxo_client: WxOClient


func _ready():
	config = ConfigData.load_config()

	auth_mode_select.add_item("Local (Bearer Token)", ConfigData.AuthMode.LOCAL_BEARER)
	auth_mode_select.add_item("API Key", ConfigData.AuthMode.SAAS_API_KEY)

	server_url_input.text = config.server_url
	auth_mode_select.selected = config.auth_mode
	bearer_token_input.text = config.bearer_token
	api_key_input.text = config.api_key
	_update_auth_sections()

	_wxo_client = WxOClient.new()
	add_child(_wxo_client)
	_wxo_client.connection_tested.connect(_on_connection_tested)
	_wxo_client.data_fetched.connect(_on_data_fetched)
	_wxo_client.fetch_error.connect(_on_fetch_error)

	auth_mode_select.item_selected.connect(_on_auth_mode_changed)
	auto_fill_button.pressed.connect(_on_auto_fill_pressed)
	test_button.pressed.connect(_on_test_pressed)
	enter_button.pressed.connect(_on_enter_pressed)


func _on_auth_mode_changed(_index: int):
	_update_auth_sections()


func _update_auth_sections():
	var mode = auth_mode_select.get_selected_id()
	bearer_section.visible = (mode == ConfigData.AuthMode.LOCAL_BEARER)
	api_key_section.visible = (mode == ConfigData.AuthMode.SAAS_API_KEY)


func _on_auto_fill_pressed():
	var token = ConfigData.read_local_bearer_token()
	if token.is_empty():
		var dialog = AcceptDialog.new()
		dialog.title = "Credentials Not Found"
		dialog.dialog_text = "Could not find credentials file.\n\nLooked in:\n  - ~/.cache/orchestrate/credentials.yaml\n  - %USERPROFILE%\\.cache\\orchestrate\\credentials.yaml\n  - %APPDATA%\\orchestrate\\credentials.yaml\n\nPlease enter your bearer token manually."
		dialog.ok_button_text = "OK"
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
	else:
		bearer_token_input.text = token
		status_label.text = "Bearer token loaded from local credentials"


func _on_test_pressed():
	_save_config()
	status_label.text = "Testing connection..."
	test_button.disabled = true
	_wxo_client.configure(config)
	_wxo_client.test_connection()


func _on_connection_tested(_success: bool, message: String):
	test_button.disabled = false
	status_label.text = message


func _on_enter_pressed():
	_save_config()
	_set_loading(true)
	status_label.text = "Loading data..."
	_wxo_client.configure(config)
	_wxo_client.fetch_all()


func _on_data_fetched(graph_data: WxODataModel.GraphData):
	data_ready.emit(graph_data)


func _on_fetch_error(message: String):
	_set_loading(false)
	status_label.text = message


func _set_loading(loading: bool):
	enter_button.disabled = loading
	test_button.disabled = loading
	server_url_input.editable = not loading
	auth_mode_select.disabled = loading


func _save_config():
	config.server_url = server_url_input.text
	config.auth_mode = auth_mode_select.get_selected_id()
	config.bearer_token = bearer_token_input.text
	config.api_key = api_key_input.text
	config.save_config()
