class_name Starfield
extends Node3D

## Static white star dots surrounding the graph area.
## Fades out when layout settles, fades back in when resumed.

var _tween: Tween
var _camera: Camera3D
var _star_container: Node3D


func _ready():
	_create_environment()
	_create_stars()


func set_camera(cam: Camera3D):
	_camera = cam


func _process(_delta):
	if _camera:
		global_position = _camera.global_position


func fade_out(duration: float = 2.0):
	_kill_tween()
	_tween = create_tween()
	for star in _star_container.get_children():
		_tween.parallel().tween_property(star, "transparency", 1.0, duration)


func fade_in(duration: float = 1.0):
	_kill_tween()
	_tween = create_tween()
	for star in _star_container.get_children():
		_tween.parallel().tween_property(star, "transparency", 0.0, duration)


func _kill_tween():
	if _tween and _tween.is_running():
		_tween.kill()


func _create_environment():
	var env = Environment.new()

	# Dark background
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.025)
	env.ambient_light_color = Color(0.05, 0.08, 0.06)
	env.ambient_light_energy = 0.3

	# Subtle glow
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.6
	env.glow_bloom = 0.03
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Tonemap
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _create_stars():
	_star_container = Node3D.new()
	add_child(_star_container)

	var star_count = 400
	var min_radius = 80.0
	var max_radius = 250.0

	# Shared mesh and material
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.5
	sphere.material = mat

	for i in range(star_count):
		var dir = _random_direction()
		var dist = min_radius + randf() * (max_radius - min_radius)

		var mi = MeshInstance3D.new()
		mi.mesh = sphere
		mi.position = dir * dist
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Random size variation
		var s = 0.5 + randf() * 1.5
		mi.scale = Vector3(s, s, s)

		_star_container.add_child(mi)


func _random_direction() -> Vector3:
	var theta = randf() * TAU
	var phi = acos(2.0 * randf() - 1.0)
	return Vector3(
		sin(phi) * cos(theta),
		sin(phi) * sin(theta),
		cos(phi)
	)
