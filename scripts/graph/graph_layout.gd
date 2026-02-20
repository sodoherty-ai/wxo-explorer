class_name GraphLayout

var positions: Dictionary = {}   # id -> Vector3
var velocities: Dictionary = {}  # id -> Vector3
var edges: Array = []            # [[id_a, id_b], ...]

var repulsion_strength: float = 80.0
var attraction_strength: float = 0.05
var ideal_edge_length: float = 4.0
var center_gravity: float = 0.02
var damping: float = 0.85
var min_distance: float = 1.0


func init_random(node_ids: Array, radius: float = 8.0):
	for id in node_ids:
		positions[id] = Vector3(
			randf_range(-radius, radius),
			randf_range(-radius * 0.3, radius * 0.3),
			randf_range(-radius, radius)
		)
		velocities[id] = Vector3.ZERO


func set_edges(edge_list: Array):
	edges = edge_list


func step(delta: float) -> float:
	var forces: Dictionary = {}
	for id in positions:
		forces[id] = Vector3.ZERO

	var ids = positions.keys()

	# Repulsion between all node pairs (Coulomb's law)
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var id_a = ids[i]
			var id_b = ids[j]
			var diff = positions[id_a] - positions[id_b]
			var dist = max(diff.length(), min_distance)
			var force = diff.normalized() * (repulsion_strength / (dist * dist))
			forces[id_a] += force
			forces[id_b] -= force

	# Attraction along edges (Hooke's law)
	for edge in edges:
		var id_a = edge[0]
		var id_b = edge[1]
		if not positions.has(id_a) or not positions.has(id_b):
			continue
		var diff = positions[id_b] - positions[id_a]
		var dist = diff.length()
		var displacement = dist - ideal_edge_length
		var force = diff.normalized() * (displacement * attraction_strength)
		forces[id_a] += force
		forces[id_b] -= force

	# Gentle gravity toward center to prevent drift
	for id in positions:
		forces[id] -= positions[id] * center_gravity

	# Integrate forces into velocities and positions
	var total_movement: float = 0.0
	for id in positions:
		velocities[id] = (velocities[id] + forces[id] * delta) * damping
		# Cap velocity to prevent explosions
		var speed = velocities[id].length()
		if speed > 20.0:
			velocities[id] = velocities[id].normalized() * 20.0
		positions[id] += velocities[id] * delta
		total_movement += velocities[id].length()

	return total_movement
