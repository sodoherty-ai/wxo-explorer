class_name GraphNodeBase
extends Node3D

const FONT_MEDIUM = preload("res://resources/fonts/IBM_Plex_Sans/static/IBMPlexSans-Medium.ttf")

var node_id: String
var node_type: String
var display_name: String

var _mesh_instance: MeshInstance3D
var _label: Label3D
var _body: StaticBody3D
var _base_color: Color
var _selected: bool = false
var _dimmed: bool = false


func setup(id: String, type: String, dname: String, mesh: Mesh, material: Material):
	node_id = id
	node_type = type
	display_name = dname

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	# Duplicate so each node has its own material for independent glow/dim
	var mat = material.duplicate() as StandardMaterial3D
	_base_color = mat.albedo_color
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	_label = Label3D.new()
	_label.text = dname
	_label.font = FONT_MEDIUM
	_label.position = Vector3(0, 1.2, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.outline_size = 8
	_label.modulate = Color.WHITE
	_label.outline_modulate = Color.BLACK
	add_child(_label)

	# Collision body for raycast picking
	_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.6
	col.shape = shape
	_body.add_child(col)
	add_child(_body)


func set_selected(selected: bool):
	_selected = selected
	_apply_visual_state()


func set_dimmed(dimmed: bool):
	_dimmed = dimmed
	_apply_visual_state()


func _apply_visual_state():
	var mat = _mesh_instance.material_override as StandardMaterial3D
	if not mat:
		return

	if _selected:
		mat.albedo_color = _base_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.emission_enabled = true
		mat.emission = _base_color
		mat.emission_energy_multiplier = 2.5
		_label.visible = true
		_label.modulate = Color.WHITE
	elif _dimmed:
		mat.albedo_color = _base_color.darkened(0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.35
		mat.emission_enabled = false
		_label.visible = false
	else:
		mat.albedo_color = _base_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.emission_enabled = false
		_label.visible = true
		_label.modulate = Color.WHITE
