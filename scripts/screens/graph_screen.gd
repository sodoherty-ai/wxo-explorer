extends Node3D

signal back_pressed

const FONT_LIGHT = preload("res://resources/fonts/IBM_Plex_Sans/static/IBMPlexSans-Light.ttf")
const FONT_MEDIUM = preload("res://resources/fonts/IBM_Plex_Sans/static/IBMPlexSans-Medium.ttf")

@onready var back_button: Button = %BackButton
@onready var camera: Camera3D = %Camera3D
@onready var status_label: Label = %StatusLabel

var graph_data: WxODataModel.GraphData
var config: ConfigData
var iam_manager: IamTokenManager
var _manager: GraphManager
var _starfield: Starfield
var _chat_client: WxOChatClient

# Detail panel (built in code)
var _detail_panel: PanelContainer
var _detail_content: RichTextLabel

# Chat panel
var _chat_panel: PanelContainer
var _chat_history: RichTextLabel
var _chat_input: LineEdit
var _chat_send_button: Button
var _chat_reset_button: Button
var _chat_agent_name: String = ""
var _chat_lines: Array[String] = []
var _chat_debug_buffer: Array[String] = []
var _chat_sessions: Dictionary = {}  # agent_id -> { "lines": Array, "thread_id": String }
var _chat_current_agent_id: String = ""
var _chat_dragging: bool = false
var _chat_drag_start_y: float = 0.0
var _chat_drag_start_offset: float = 0.0
const CHAT_MIN_HEIGHT = 120.0
const CHAT_MAX_HEIGHT = 600.0

# Search panel
var _search_panel: PanelContainer
var _search_input: LineEdit
var _search_list: ItemList
var _search_node_ids: Array[String] = []


func _ready():
	back_button.pressed.connect(_on_back_pressed)
	camera.mode_changed.connect(_on_camera_mode_changed)
	status_label.add_theme_font_override("font", FONT_MEDIUM)
	_build_detail_panel()
	_build_chat_panel()
	_build_search_panel()
	_build_controls_panel()

	_starfield = Starfield.new()
	_starfield.set_camera(camera)
	add_child(_starfield)

	_chat_client = WxOChatClient.new()
	add_child(_chat_client)
	if iam_manager:
		add_child(iam_manager)
	if config:
		_chat_client.configure(config, iam_manager)
	_chat_client.message_received.connect(_on_chat_message_received)
	_chat_client.chat_error.connect(_on_chat_error)
	_chat_client.thinking_started.connect(_on_chat_thinking_started)
	_chat_client.thinking_finished.connect(_on_chat_thinking_finished)
	_chat_client.debug_log.connect(_on_chat_debug)

	if graph_data:
		_build_graph()
	else:
		status_label.text = "No data loaded"


func _build_detail_panel():
	var hud = back_button.get_parent()

	_detail_panel = PanelContainer.new()
	_detail_panel.anchor_left = 1.0
	_detail_panel.anchor_right = 1.0
	_detail_panel.anchor_top = 0.0
	_detail_panel.anchor_bottom = 1.0
	_detail_panel.offset_left = -350.0
	_detail_panel.offset_right = 0.0
	_detail_panel.offset_top = 0.0
	_detail_panel.offset_bottom = 0.0

	# Semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_detail_panel.add_theme_stylebox_override("panel", style)

	# Single scrollable RichTextLabel for all content
	_detail_content = RichTextLabel.new()
	_detail_content.bbcode_enabled = true
	_detail_content.scroll_active = true
	_detail_content.selection_enabled = true
	_detail_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_font_override("normal_font", FONT_LIGHT)
	_detail_content.add_theme_font_override("bold_font", FONT_MEDIUM)
	_detail_content.add_theme_font_override("italics_font", FONT_LIGHT)
	_detail_content.add_theme_font_size_override("normal_font_size", 12)
	_detail_content.add_theme_font_size_override("bold_font_size", 12)

	_detail_content.meta_clicked.connect(_on_link_clicked)
	_detail_panel.add_child(_detail_content)
	hud.add_child(_detail_panel)
	_detail_panel.visible = false


func _build_graph():
	_manager = GraphManager.new()
	add_child(_manager)
	_manager.graph_built.connect(_on_graph_built)
	_manager.node_selected.connect(_on_node_selected)
	_manager.node_deselected.connect(_on_node_deselected)
	_manager.layout_settled.connect(func(): pass)
	_manager.layout_resumed.connect(func(): pass)
	_manager.build(graph_data, camera)


func _on_graph_built(node_count: int, edge_count: int):
	status_label.text = "%d nodes, %d edges" % [node_count, edge_count]


func _on_node_selected(node: GraphNodeBase):
	status_label.text = ""
	_show_detail(node)
	if node.node_type == "agent":
		_show_chat(node)
	else:
		_chat_panel.visible = false


func _on_node_deselected():
	status_label.text = ""
	_detail_panel.visible = false
	_save_chat_session()
	_chat_panel.visible = false


func _on_link_clicked(meta):
	var node_id = str(meta)
	if _manager:
		_manager.select_by_id(node_id)


func _show_detail(node: GraphNodeBase):
	var type_colors = {
		"agent": "#4A90D9",
		"tool": "#50C878",
		"knowledge_base": "#E8943A",
	}
	var type_labels = {
		"agent": "AGENT",
		"tool": "TOOL",
		"knowledge_base": "KNOWLEDGE BASE",
	}

	var color = type_colors.get(node.node_type, "#FFFFFF")
	var type_text = type_labels.get(node.node_type, node.node_type.to_upper())
	var bbcode = ""

	# Header
	bbcode += "[color=%s][font_size=11]%s[/font_size][/color]\n" % [color, type_text]
	bbcode += "[font_size=16]%s[/font_size]\n" % node.display_name
	bbcode += "[color=#555555]%s[/color]\n" % node.node_id

	if node.node_type == "agent" and graph_data.agents.has(node.node_id):
		bbcode += _build_agent_detail(graph_data.agents[node.node_id])
	elif node.node_type == "tool" and graph_data.tools.has(node.node_id):
		bbcode += _build_tool_detail(graph_data.tools[node.node_id])
	elif node.node_type == "knowledge_base" and graph_data.knowledge_bases.has(node.node_id):
		bbcode += _build_kb_detail(graph_data.knowledge_bases[node.node_id])

	_detail_content.clear()
	_detail_content.append_text(bbcode)
	_detail_content.scroll_to_line(0)
	_detail_panel.visible = true


func _build_agent_detail(agent: WxODataModel.AgentData) -> String:
	var bbcode = ""

	# Description
	bbcode += _section("Description")
	bbcode += "%s\n" % (agent.description if agent.description != "" else "[i]No description[/i]")

	# Instructions
	if agent.instructions != "":
		bbcode += _section("Instructions")
		bbcode += "%s\n" % agent.instructions

	# Style
	if agent.style != "":
		bbcode += _section("Style")
		bbcode += "%s\n" % agent.style

	# LLM
	if agent.llm != "":
		bbcode += _section("LLM")
		bbcode += "%s\n" % agent.llm

	# Guidelines
	if not agent.guidelines.is_empty():
		bbcode += _section("Guidelines (%d)" % agent.guidelines.size())
		for i in range(agent.guidelines.size()):
			var g = agent.guidelines[i]
			var condition = g.get("condition", "")
			var action = g.get("action", "")
			var tool_name = g.get("tool", "")
			bbcode += "[b]%d.[/b] [color=#CCCCCC]When[/color] %s\n" % [i + 1, condition]
			if action != "":
				bbcode += "    [color=#CCCCCC]Then[/color] %s\n" % action
			if tool_name != "":
				bbcode += "    [color=#CCCCCC]Tool:[/color] [color=#50C878]%s[/color]\n" % tool_name
			bbcode += "\n"

	# Connections
	bbcode += _section("Connections")

	if not agent.tool_ids.is_empty():
		bbcode += "[b]Tools (%d):[/b]\n" % agent.tool_ids.size()
		for tid in agent.tool_ids:
			bbcode += "  [url=%s][color=#50C878]%s[/color][/url]\n" % [tid, graph_data.get_tool_display(tid)]
		bbcode += "\n"

	if not agent.collaborator_ids.is_empty():
		bbcode += "[b]Collaborators (%d):[/b]\n" % agent.collaborator_ids.size()
		for cid in agent.collaborator_ids:
			bbcode += "  [url=%s][color=#4A90D9]%s[/color][/url]\n" % [cid, graph_data.get_agent_display(cid)]
		bbcode += "\n"

	if not agent.knowledge_base_ids.is_empty():
		bbcode += "[b]Knowledge Bases (%d):[/b]\n" % agent.knowledge_base_ids.size()
		for kid in agent.knowledge_base_ids:
			bbcode += "  [url=%s][color=#E8943A]%s[/color][/url]\n" % [kid, graph_data.get_kb_display(kid)]
		bbcode += "\n"

	if agent.tool_ids.is_empty() and agent.collaborator_ids.is_empty() and agent.knowledge_base_ids.is_empty():
		bbcode += "[i]No connections[/i]\n"

	# Used by - agents that list this agent as a collaborator
	var used_by_agents: Array[String] = []
	for aid in graph_data.agents:
		var a = graph_data.agents[aid]
		if a.collaborator_ids.has(agent.id):
			used_by_agents.append("[url=%s][color=#4A90D9]%s[/color][/url]" % [aid, a.display_name])
	if not used_by_agents.is_empty():
		bbcode += _section("Used by")
		bbcode += "\n".join(used_by_agents) + "\n"

	# Raw extra fields
	bbcode += _build_raw_extras(agent.raw, ["id", "name", "display_name", "description",
		"instructions", "style", "llm", "guidelines", "tools", "collaborators", "knowledge_base"])

	return bbcode


func _build_tool_detail(tool_data: WxODataModel.ToolData) -> String:
	var bbcode = ""

	# Description
	bbcode += _section("Description")
	bbcode += "%s\n" % (tool_data.description if tool_data.description != "" else "[i]No description[/i]")

	# Used by
	bbcode += _section("Used by")
	var tool_agents: Array[String] = []
	for aid in graph_data.agents:
		var a = graph_data.agents[aid]
		if a.tool_ids.has(tool_data.id):
			tool_agents.append("[url=%s][color=#4A90D9]%s[/color][/url]" % [aid, a.display_name])
	if not tool_agents.is_empty():
		bbcode += "\n".join(tool_agents) + "\n"
	else:
		bbcode += "[i]No agents[/i]\n"

	# Raw extra fields
	bbcode += _build_raw_extras(tool_data.raw, ["id", "name", "description"])

	return bbcode


func _build_kb_detail(kb: WxODataModel.KnowledgeBaseData) -> String:
	var bbcode = ""

	# Description
	bbcode += _section("Description")
	bbcode += "%s\n" % (kb.description if kb.description != "" else "[i]No description[/i]")

	# Status
	bbcode += _section("Status")
	bbcode += "%s\n" % kb.status

	# Used by
	bbcode += _section("Used by")
	var kb_agents: Array[String] = []
	for aid in graph_data.agents:
		var a = graph_data.agents[aid]
		if a.knowledge_base_ids.has(kb.id):
			kb_agents.append("[url=%s][color=#4A90D9]%s[/color][/url]" % [aid, a.display_name])
	if not kb_agents.is_empty():
		bbcode += "\n".join(kb_agents) + "\n"
	else:
		bbcode += "[i]No agents[/i]\n"

	# Raw extra fields
	bbcode += _build_raw_extras(kb.raw, ["id", "name", "display_name", "description", "vector_index"])

	return bbcode


func _build_raw_extras(raw: Dictionary, known_keys: Array) -> String:
	var extras: Dictionary = {}
	for key in raw:
		if key in known_keys:
			continue
		var val = raw[key]
		# Skip empty values
		if val == null:
			continue
		if val is String and val == "":
			continue
		if val is Array and val.is_empty():
			continue
		if val is Dictionary and val.is_empty():
			continue
		extras[key] = val

	if extras.is_empty():
		return ""

	var bbcode = _section("Other Properties")
	for key in extras:
		var val = extras[key]
		if val is Dictionary or val is Array:
			bbcode += "[b]%s:[/b]\n%s" % [key, _format_value(val, 1)]
		else:
			bbcode += "[b]%s:[/b] %s\n" % [key, str(val)]
	return bbcode


func _format_value(val, indent: int = 0) -> String:
	var prefix = "  ".repeat(indent)
	if val is Dictionary:
		if val.is_empty():
			return prefix + "[i]empty[/i]\n"
		var result = ""
		for k in val:
			var child = val[k]
			if child is Dictionary or child is Array:
				result += "%s[color=#AAAAAA]%s:[/color]\n%s" % [prefix, k, _format_value(child, indent + 1)]
			else:
				result += "%s[color=#AAAAAA]%s:[/color] %s\n" % [prefix, k, str(child)]
		return result
	elif val is Array:
		if val.is_empty():
			return prefix + "[i]empty[/i]\n"
		var result = ""
		for item in val:
			if item is Dictionary:
				result += _format_value(item, indent)
				result += "\n"
			elif item is Array:
				result += _format_value(item, indent + 1)
			else:
				result += "%s- %s\n" % [prefix, str(item)]
		return result
	else:
		return "%s%s\n" % [prefix, str(val)]


func _section(title: String) -> String:
	return "\n[color=#888888]━━━ %s ━━━[/color]\n" % title


func _build_chat_panel():
	var hud = back_button.get_parent()

	_chat_panel = PanelContainer.new()
	_chat_panel.anchor_left = 0.0
	_chat_panel.anchor_right = 1.0
	_chat_panel.anchor_top = 1.0
	_chat_panel.anchor_bottom = 1.0
	_chat_panel.offset_left = 220.0
	_chat_panel.offset_right = -360.0
	_chat_panel.offset_top = -200.0
	_chat_panel.offset_bottom = 0.0

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_chat_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Drag handle
	var handle = Control.new()
	handle.custom_minimum_size = Vector2(0, 14)
	handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	handle.gui_input.connect(_on_chat_handle_input)

	var handle_bar = ColorRect.new()
	handle_bar.color = Color(0.6, 0.6, 0.6, 0.8)
	handle_bar.custom_minimum_size = Vector2(40, 3)
	handle_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	handle_bar.offset_left = -20.0
	handle_bar.offset_right = 20.0
	handle_bar.offset_top = 5.0
	handle_bar.offset_bottom = 8.0
	handle.add_child(handle_bar)
	vbox.add_child(handle)

	# Chat history area
	_chat_history = RichTextLabel.new()
	_chat_history.bbcode_enabled = true
	_chat_history.scroll_active = true
	_chat_history.scroll_following = true
	_chat_history.selection_enabled = true
	_chat_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_history.add_theme_font_override("normal_font", FONT_LIGHT)
	_chat_history.add_theme_font_override("bold_font", FONT_MEDIUM)
	_chat_history.add_theme_font_size_override("normal_font_size", 11)
	_chat_history.add_theme_font_size_override("bold_font_size", 11)
	vbox.add_child(_chat_history)

	# Input row
	var input_row = HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Type a message..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_font_override("font", FONT_LIGHT)
	_chat_input.add_theme_font_size_override("font_size", 11)
	_chat_input.text_submitted.connect(_on_chat_submit)
	input_row.add_child(_chat_input)

	_chat_send_button = Button.new()
	_chat_send_button.text = "Send"
	_chat_send_button.add_theme_font_override("font", FONT_MEDIUM)
	_chat_send_button.add_theme_font_size_override("font_size", 11)
	_chat_send_button.pressed.connect(_on_chat_send_pressed)
	input_row.add_child(_chat_send_button)

	_chat_reset_button = Button.new()
	_chat_reset_button.text = "Reset"
	_chat_reset_button.add_theme_font_override("font", FONT_MEDIUM)
	_chat_reset_button.add_theme_font_size_override("font_size", 11)
	_chat_reset_button.pressed.connect(_on_chat_reset_pressed)
	input_row.add_child(_chat_reset_button)

	vbox.add_child(input_row)
	_chat_panel.add_child(vbox)
	hud.add_child(_chat_panel)
	_chat_panel.visible = false


func _show_chat(node: GraphNodeBase):
	# Save current session before switching
	_save_chat_session()

	_chat_agent_name = node.display_name
	_chat_current_agent_id = node.node_id
	_chat_panel.visible = true
	_chat_input.text = ""
	_chat_input.editable = true
	_chat_send_button.disabled = false

	if _chat_sessions.has(node.node_id):
		# Restore existing session
		var session = _chat_sessions[node.node_id]
		_chat_lines.assign(session["lines"])
		_chat_client.restore_session(node.node_id, session["thread_id"])
	else:
		# Start fresh session
		_chat_lines.clear()
		_chat_client.start_session(node.node_id)
		_chat_lines.append("[color=#666666]Chat with %s[/color]" % node.display_name)

	_render_chat()
	_chat_input.grab_focus()


func _save_chat_session():
	if _chat_current_agent_id.is_empty():
		return
	_chat_sessions[_chat_current_agent_id] = {
		"lines": _chat_lines.duplicate(),
		"thread_id": _chat_client._thread_id,
	}


func _on_chat_submit(_text: String):
	_on_chat_send_pressed()


func _on_chat_send_pressed():
	var message = _chat_input.text.strip_edges()
	if message.is_empty():
		return
	# Blank line between exchanges, but not before the first one
	if _chat_lines.size() > 1:
		_chat_lines.append("")
	_chat_lines.append("[b]You:[/b] %s" % message)
	# Add thinking placeholder
	_chat_lines.append("[color=#4A90D9][b]%s:[/b][/color] [color=#888888]Thinking...[/color]" % _chat_agent_name)
	_render_chat()
	_chat_input.text = ""
	_chat_input.editable = false
	_chat_send_button.disabled = true
	_chat_client.send_message(message)


func _on_chat_reset_pressed():
	_chat_lines.clear()
	_chat_input.text = ""
	_chat_input.editable = true
	_chat_send_button.disabled = false
	# Clear saved session for this agent
	if _chat_sessions.has(_chat_current_agent_id):
		_chat_sessions.erase(_chat_current_agent_id)
	if not _chat_current_agent_id.is_empty():
		_chat_client.start_session(_chat_current_agent_id)
		_chat_lines.append("[color=#666666]Chat with %s[/color]" % _chat_agent_name)
	_render_chat()
	_chat_input.grab_focus()


func _on_chat_message_received(text: String):
	# Replace the last line (thinking placeholder) with actual response
	var rendered = MarkdownToBBCode.convert(text)
	if not _chat_lines.is_empty():
		_chat_lines[_chat_lines.size() - 1] = "[color=#4A90D9][b]%s:[/b][/color] %s" % [_chat_agent_name, rendered]
	_render_chat()
	_chat_input.editable = true
	_chat_send_button.disabled = false
	_chat_input.grab_focus()
	_chat_debug_buffer.clear()


func _on_chat_error(message: String):
	# Replace the last line (thinking placeholder) with error
	if not _chat_lines.is_empty():
		_chat_lines[_chat_lines.size() - 1] = "[color=#4A90D9][b]%s:[/b][/color] [color=#CC4444]%s[/color]" % [_chat_agent_name, message]
	_render_chat()
	_chat_input.editable = true
	_chat_send_button.disabled = false
	_chat_input.grab_focus()
	# Dump buffered debug on error
	print("[Chat Error] ", message)
	for line in _chat_debug_buffer:
		print("[Chat Debug] ", line)
	_chat_debug_buffer.clear()


func _on_chat_thinking_started():
	pass


func _on_chat_thinking_finished():
	pass


func _on_chat_debug(message: String):
	_chat_debug_buffer.append(message)


func _on_chat_handle_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_chat_dragging = true
			_chat_drag_start_y = event.global_position.y
			_chat_drag_start_offset = _chat_panel.offset_top
		else:
			_chat_dragging = false
	elif event is InputEventMouseMotion and _chat_dragging:
		var delta_y = event.global_position.y - _chat_drag_start_y
		var new_offset = _chat_drag_start_offset + delta_y
		# Clamp to min/max height (offset_top is negative, bottom is 0)
		new_offset = clampf(new_offset, -CHAT_MAX_HEIGHT, -CHAT_MIN_HEIGHT)
		_chat_panel.offset_top = new_offset


func _render_chat():
	_chat_history.clear()
	_chat_history.append_text("\n".join(_chat_lines))


func _build_search_panel():
	var hud = back_button.get_parent()

	_search_panel = PanelContainer.new()
	_search_panel.anchor_left = 0.5
	_search_panel.anchor_right = 0.5
	_search_panel.anchor_top = 0.0
	_search_panel.anchor_bottom = 0.0
	_search_panel.offset_left = -200.0
	_search_panel.offset_right = 200.0
	_search_panel.offset_top = 40.0
	_search_panel.offset_bottom = 340.0

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_search_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search nodes..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.add_theme_font_override("font", FONT_LIGHT)
	_search_input.add_theme_font_size_override("font_size", 12)
	_search_input.text_changed.connect(_on_search_text_changed)
	vbox.add_child(_search_input)

	_search_list = ItemList.new()
	_search_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_list.add_theme_font_override("font", FONT_LIGHT)
	_search_list.add_theme_font_size_override("font_size", 11)
	_search_list.item_selected.connect(_on_search_item_activated)
	vbox.add_child(_search_list)

	_search_panel.add_child(vbox)
	hud.add_child(_search_panel)
	_search_panel.visible = false


func _toggle_search():
	_search_panel.visible = not _search_panel.visible
	if _search_panel.visible:
		_search_input.text = ""
		_search_input.grab_focus()
		_update_search_results("")
	else:
		_search_input.release_focus()


func _on_search_text_changed(query: String):
	_update_search_results(query)


func _update_search_results(query: String):
	_search_list.clear()
	_search_node_ids.clear()
	if not graph_data:
		return

	var q = query.strip_edges().to_lower()
	var type_colors = {
		"agent": Color(0.29, 0.56, 0.85),
		"tool": Color(0.31, 0.78, 0.47),
		"knowledge_base": Color(0.91, 0.58, 0.23),
	}
	var type_labels = {
		"agent": "Agent",
		"tool": "Tool",
		"knowledge_base": "KB",
	}

	# Collect matching entries: [display_name, type, id]
	var entries: Array = []
	for id in graph_data.agents:
		var a = graph_data.agents[id]
		if q.is_empty() or a.display_name.to_lower().find(q) != -1 or a.name.to_lower().find(q) != -1:
			entries.append({"name": a.display_name, "type": "agent", "id": id})
	for id in graph_data.tools:
		var t = graph_data.tools[id]
		if q.is_empty() or t.name.to_lower().find(q) != -1:
			entries.append({"name": t.name, "type": "tool", "id": id})
	for id in graph_data.knowledge_bases:
		var kb = graph_data.knowledge_bases[id]
		if q.is_empty() or kb.display_name.to_lower().find(q) != -1 or kb.name.to_lower().find(q) != -1:
			entries.append({"name": kb.display_name, "type": "knowledge_base", "id": id})

	for entry in entries:
		var label = "[%s] %s" % [type_labels[entry["type"]], entry["name"]]
		var idx = _search_list.add_item(label)
		_search_list.set_item_custom_fg_color(idx, type_colors[entry["type"]])
		_search_node_ids.append(entry["id"])


func _on_search_item_activated(index: int):
	if index < 0 or index >= _search_node_ids.size():
		return
	var node_id = _search_node_ids[index]
	_search_panel.visible = false
	_search_input.release_focus()
	if _manager:
		_manager.select_by_id(node_id)
		# Move camera to frame the node and its connections
		var bounds = _manager.get_node_cluster_bounds(node_id)
		var center: Vector3 = bounds[0]
		var radius: float = bounds[1]
		camera.orbit_target = center
		camera.orbit_distance = radius * 2.5 + 5.0
		camera._update_orbit_transform()


func _build_controls_panel():
	var hud = back_button.get_parent()

	var panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 10.0
	panel.offset_right = 210.0
	panel.offset_top = -145.0
	panel.offset_bottom = -10.0

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.fit_content = true
	label.add_theme_font_override("normal_font", FONT_LIGHT)
	label.add_theme_font_override("bold_font", FONT_MEDIUM)
	label.add_theme_font_size_override("normal_font_size", 9)
	label.add_theme_font_size_override("bold_font_size", 9)

	var text = ""
	text += "[b]Controls[/b]\n"
	text += "[color=#999999]WASD / Arrows[/color]  Move / Pan\n"
	text += "[color=#999999]Left-drag[/color]  Orbit\n"
	text += "[color=#999999]Right-drag[/color]  Pan / Look\n"
	text += "[color=#999999]Scroll[/color]  Zoom / Speed\n"
	text += "[color=#999999]Tab[/color]  Toggle Orbit / Free-fly\n"
	text += "[color=#999999]Space[/color]  Pause / Resume layout\n"
	text += "[color=#999999]Click[/color]  Select node\n"
	text += "[color=#999999]F[/color]  Search nodes\n"
	text += "[color=#999999]Esc[/color]  Back\n"
	text += "[color=#666666]Gamepad: Sticks, Triggers, Triangle[/color]"
	label.append_text(text)

	panel.add_child(label)
	hud.add_child(panel)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		var gui_has_focus = get_viewport().gui_get_focus_owner()
		# Only toggle search if no other input has focus (or search input itself has focus)
		if gui_has_focus == null or gui_has_focus == _search_input:
			_toggle_search()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _search_panel.visible:
			_search_panel.visible = false
			_search_input.release_focus()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		back_pressed.emit()


func _on_back_pressed():
	back_pressed.emit()


func _on_camera_mode_changed(_mode_name: String, _help_text: String):
	pass
