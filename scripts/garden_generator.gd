extends Node3D

@export var tree_count: int = 25
@export var foliage_count: int = 220
@export var garden_radius: float = 28.0
@export var min_tree_spacing: float = 3.0
@export var exclusion_center: Vector3 = Vector3(0, 0, -5)
@export var exclusion_half_extents: Vector2 = Vector2(6, 14)
@export var layout_seed: int = 20260926

const TreeScene := preload("res://scenes/props/tree.tscn")

var _rng := RandomNumberGenerator.new()
var _tree_positions: Array[Vector2] = []

func _ready() -> void:
	_rng.seed = layout_seed
	_scatter_trees()
	_scatter_foliage()

func _is_excluded(pos: Vector2) -> bool:
	return abs(pos.x - exclusion_center.x) < exclusion_half_extents.x \
		and abs(pos.y - exclusion_center.z) < exclusion_half_extents.y

func _random_point() -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := sqrt(_rng.randf_range(0.0, 1.0)) * garden_radius
	return Vector2(cos(angle) * radius, sin(angle) * radius)

func _scatter_trees() -> void:
	var attempts := 0
	while _tree_positions.size() < tree_count and attempts < tree_count * 40:
		attempts += 1
		var pos := _random_point()
		if _is_excluded(pos):
			continue
		var too_close := false
		for existing in _tree_positions:
			if existing.distance_to(pos) < min_tree_spacing:
				too_close = true
				break
		if too_close:
			continue
		_tree_positions.append(pos)

		var tree := TreeScene.instantiate()
		add_child(tree)
		tree.position = Vector3(pos.x, 0, pos.y)
		tree.rotate_y(_rng.randf_range(0.0, TAU))
		var s := _rng.randf_range(0.8, 1.3)
		tree.scale = Vector3(s, s, s)

func _scatter_foliage() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 0.9

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.42, 0.16)
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = foliage_count

	for i in foliage_count:
		var pos := _random_point()
		while _is_excluded(pos):
			pos = _random_point()

		var angle := _rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, angle)
		var s := _rng.randf_range(0.6, 1.6)
		basis = basis.scaled(Vector3(s, s * _rng.randf_range(0.6, 1.1), s))

		var xform := Transform3D(basis, Vector3(pos.x, 0.2, pos.y))
		multimesh.set_instance_transform(i, xform)

	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.multimesh = multimesh
	add_child(multimesh_instance)
