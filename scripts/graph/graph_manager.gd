class_name GraphManager
extends Node3D

signal graph_built(node_count: int, edge_count: int)
signal node_selected(node: GraphNodeBase)
signal node_deselected
signal layout_settled
signal layout_resumed

var _graph_data: WxODataModel.GraphData
var _layout: GraphLayout
var _nodes: Dictionary = {}  # id -> GraphNodeBase
var _edge_mesh: ImmediateMesh
var _edge_instance: MeshInstance3D
var _highlight_mesh: ImmediateMesh
var _highlight_instance: MeshInstance3D
var _settled: bool = false
var _settle_threshold: float = 0.5
var _settle_frames: int = 0
var _selected_node: GraphNodeBase = null
var _camera: Camera3D

# Shared meshes (one instance per type, reused by all nodes)
var _agent_mesh: SphereMesh
var _tool_mesh: BoxMesh
var _kb_mesh: CylinderMesh

# Shared materials (templates - each node gets a duplicate)
var _agent_material: StandardMaterial3D
var _tool_material: StandardMaterial3D
var _kb_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _highlight_edge_material: StandardMaterial3D


func build(graph_data: WxODataModel.GraphData, camera: Camera3D):
	_graph_data = graph_data
	_camera = camera
	_create_shared_resources()
	_create_nodes()
	_init_layout()
	_create_edge_renderer()
	_update_node_positions()
	_update_edges()

	graph_built.emit(_nodes.size(), _layout.edges.size())


func _create_shared_resources():
	# Agent: blue sphere
	_agent_mesh = SphereMesh.new()
	_agent_mesh.radius = 0.5
	_agent_mesh.height = 1.0

	_agent_material = StandardMaterial3D.new()
	_agent_material.albedo_color = Color(0.29, 0.56, 0.85)  # #4A90D9

	# Tool: green cube
	_tool_mesh = BoxMesh.new()
	_tool_mesh.size = Vector3(0.7, 0.7, 0.7)

	_tool_material = StandardMaterial3D.new()
	_tool_material.albedo_color = Color(0.31, 0.78, 0.47)  # #50C878

	# Knowledge base: orange cylinder
	_kb_mesh = CylinderMesh.new()
	_kb_mesh.top_radius = 0.4
	_kb_mesh.bottom_radius = 0.4
	_kb_mesh.height = 0.8

	_kb_material = StandardMaterial3D.new()
	_kb_material.albedo_color = Color(0.91, 0.58, 0.23)  # #E8943A

	# Edges: semi-transparent unshaded gray lines
	_edge_material = StandardMaterial3D.new()
	_edge_material.albedo_color = Color(0.7, 0.7, 0.7, 0.6)
	_edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Highlighted edges: bright white with emission glow
	_highlight_edge_material = StandardMaterial3D.new()
	_highlight_edge_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_highlight_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_edge_material.emission_enabled = true
	_highlight_edge_material.emission = Color(1.0, 1.0, 1.0)
	_highlight_edge_material.emission_energy_multiplier = 2.0


func _create_nodes():
	# Agents
	for id in _graph_data.agents:
		var agent = _graph_data.agents[id]
		var node = GraphNodeBase.new()
		node.setup(id, "agent", agent.display_name, _agent_mesh, _agent_material)
		add_child(node)
		_nodes[id] = node

	# Tools
	for id in _graph_data.tools:
		var tool_data = _graph_data.tools[id]
		var node = GraphNodeBase.new()
		node.setup(id, "tool", tool_data.name, _tool_mesh, _tool_material)
		add_child(node)
		_nodes[id] = node

	# Knowledge bases
	for id in _graph_data.knowledge_bases:
		var kb = _graph_data.knowledge_bases[id]
		var node = GraphNodeBase.new()
		node.setup(id, "knowledge_base", kb.display_name, _kb_mesh, _kb_material)
		add_child(node)
		_nodes[id] = node


func _init_layout():
	_layout = GraphLayout.new()
	_layout.init_random(_nodes.keys())

	# Build edge list from agent relationships
	var edges: Array = []
	for id in _graph_data.agents:
		var agent = _graph_data.agents[id]
		for tool_id in agent.tool_ids:
			if _nodes.has(tool_id):
				edges.append([id, tool_id])
		for collab_id in agent.collaborator_ids:
			if _nodes.has(collab_id):
				edges.append([id, collab_id])
		for kb_id in agent.knowledge_base_ids:
			if _nodes.has(kb_id):
				edges.append([id, kb_id])

	_layout.set_edges(edges)


func _create_edge_renderer():
	# Normal edges
	_edge_mesh = ImmediateMesh.new()
	_edge_instance = MeshInstance3D.new()
	_edge_instance.mesh = _edge_mesh
	_edge_instance.material_override = _edge_material
	add_child(_edge_instance)

	# Highlighted edges (drawn on top)
	_highlight_mesh = ImmediateMesh.new()
	_highlight_instance = MeshInstance3D.new()
	_highlight_instance.mesh = _highlight_mesh
	_highlight_instance.material_override = _highlight_edge_material
	add_child(_highlight_instance)


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_pick(event.position)
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_set_settled(not _settled)
		_settle_frames = 0


func _try_pick(screen_pos: Vector2):
	if not _camera:
		return
	var from = _camera.project_ray_origin(screen_pos)
	var to = from + _camera.project_ray_normal(screen_pos) * 500.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space.intersect_ray(query)

	if result:
		var hit_node = _find_graph_node(result.collider)
		if hit_node:
			_set_settled(true)
			_select_node(hit_node)
			return

	# Clicked empty space - deselect
	_select_node(null)


func _find_graph_node(collider: Node) -> GraphNodeBase:
	# The collider is the StaticBody3D, its parent is the GraphNodeBase
	var parent = collider.get_parent()
	if parent is GraphNodeBase:
		return parent
	return null


func select_by_id(id: String):
	if _nodes.has(id):
		_settled = true
		_select_node(_nodes[id])


func get_node_cluster_bounds(id: String) -> Array:
	## Returns [center: Vector3, radius: float] for the node and its connected nodes.
	if not _nodes.has(id):
		return [Vector3.ZERO, 10.0]
	var positions: Array[Vector3] = [_nodes[id].position]
	for edge in _layout.edges:
		if edge[0] == id and _nodes.has(edge[1]):
			positions.append(_nodes[edge[1]].position)
		elif edge[1] == id and _nodes.has(edge[0]):
			positions.append(_nodes[edge[0]].position)
	var center = Vector3.ZERO
	for p in positions:
		center += p
	center /= positions.size()
	var radius = 0.0
	for p in positions:
		radius = maxf(radius, center.distance_to(p))
	return [center, maxf(radius, 3.0)]


func _select_node(node: GraphNodeBase):
	if _selected_node == node:
		return
	if _selected_node:
		_selected_node.set_selected(false)
	_selected_node = node

	# Find connected node IDs
	var connected_ids: Dictionary = {}
	if _selected_node:
		connected_ids[_selected_node.node_id] = true
		for edge in _layout.edges:
			if edge[0] == _selected_node.node_id:
				connected_ids[edge[1]] = true
			elif edge[1] == _selected_node.node_id:
				connected_ids[edge[0]] = true

	# Update all node visuals
	for id in _nodes:
		var n = _nodes[id]
		if _selected_node == null:
			n.set_dimmed(false)
		elif connected_ids.has(id):
			n.set_dimmed(false)
		else:
			n.set_dimmed(true)

	if _selected_node:
		_selected_node.set_selected(true)
		node_selected.emit(_selected_node)
	else:
		node_deselected.emit()
	# Redraw edges to update highlighting
	_update_edges()


func _set_settled(value: bool):
	if _settled == value:
		return
	_settled = value
	if _settled:
		layout_settled.emit()
	else:
		layout_resumed.emit()


func _process(delta):
	if _settled:
		return

	var movement = _layout.step(delta)
	_update_node_positions()
	_update_edges()

	# Settle after movement drops below threshold for several frames
	if movement < _settle_threshold:
		_settle_frames += 1
		if _settle_frames > 60:
			_set_settled(true)
	else:
		_settle_frames = 0


func _update_node_positions():
	for id in _nodes:
		_nodes[id].position = _layout.positions[id]


func _update_edges():
	var selected_id = _selected_node.node_id if _selected_node else ""

	# Split edges into normal vs highlighted
	var normal_edges: Array = []
	var highlight_edges: Array = []

	for edge in _layout.edges:
		if selected_id != "" and (edge[0] == selected_id or edge[1] == selected_id):
			highlight_edges.append(edge)
		else:
			normal_edges.append(edge)

	# Draw normal edges (dimmed when there's a selection)
	_edge_mesh.clear_surfaces()
	if not normal_edges.is_empty():
		_edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in normal_edges:
			var pos_a = _layout.positions.get(edge[0], Vector3.ZERO)
			var pos_b = _layout.positions.get(edge[1], Vector3.ZERO)
			_edge_mesh.surface_add_vertex(pos_a)
			_edge_mesh.surface_add_vertex(pos_b)
		_edge_mesh.surface_end()

	# Dim normal edges when something is selected
	if selected_id != "":
		_edge_material.albedo_color = Color(0.4, 0.4, 0.4, 0.3)
	else:
		_edge_material.albedo_color = Color(0.7, 0.7, 0.7, 0.6)

	# Draw highlighted edges
	_highlight_mesh.clear_surfaces()
	if not highlight_edges.is_empty():
		_highlight_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in highlight_edges:
			var pos_a = _layout.positions.get(edge[0], Vector3.ZERO)
			var pos_b = _layout.positions.get(edge[1], Vector3.ZERO)
			_highlight_mesh.surface_add_vertex(pos_a)
			_highlight_mesh.surface_add_vertex(pos_b)
		_highlight_mesh.surface_end()
