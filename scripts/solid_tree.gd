extends StaticBody3D

# Trunk collision measured from each model's mesh at 0.3-0.6 m height (where
# the robot's treads hit). Centre is the trunk's offset from the model origin.
# Values are the outermost trunk vertex, so nothing can pass through the bark.
# Pines: thin trunks but branches to the ground, so collision covers the
# lowest branches. Mirrored in tools/level_common.py TRUNKS.
const TRUNKS := {
	"CommonTree_1": {"radius": 0.55, "centre": Vector2(0.02, 0.11)},
	"CommonTree_2": {"radius": 0.52, "centre": Vector2(-0.01, 0.04)},
	"CommonTree_3": {"radius": 0.55, "centre": Vector2(0.01, 0.11)},
	"CommonTree_4": {"radius": 0.55, "centre": Vector2(-0.04, 0.10)},
	"CommonTree_5": {"radius": 0.50, "centre": Vector2(0.07, 0.10)},
	"DeadTree_1": {"radius": 0.52, "centre": Vector2(0.13, 0.0)},
	"Pine_1": {"radius": 0.50, "centre": Vector2(0.03, -0.02)},
	"Pine_2": {"radius": 0.50, "centre": Vector2(0.03, -0.02)},
	"Pine_5": {"radius": 0.50, "centre": Vector2(0.02, -0.09)},
	"TwistedTree_2": {"radius": 1.12, "centre": Vector2(0.06, -0.01)},
	"TwistedTree_4": {"radius": 1.15, "centre": Vector2(0.02, 0.10)},
	"TwistedTree_5": {"radius": 1.32, "centre": Vector2(-0.49, -0.19)},
}

# The pack's leaf materials are replaced by shared tinted ones (white leaf
# mask x leaf_tint), so every tree can have its own colour without extra
# materials or draw calls.
const LEAF_MATERIALS := {
	"Leaves_NormalTree": preload("res://materials/leaves_normal.tres"),
	"Leaves_TwistedTree": preload("res://materials/leaves_twisted.tres"),
	"Leaves_Pine": preload("res://materials/leaves_pine.tres"),
}

const LOD_BIAS := 0.5    # < 1 switches to lower-detail LODs nearer the camera

@export var model_path: String = ""
## 0 = use the measured trunk for this model (see TRUNKS).
@export var trunk_radius: float = 0.0
@export var trunk_height: float = 2.5
## Leaf colour; set per tree by the level build.
@export var leaf_tint: Color = Color(0.34, 0.52, 0.20)

func _ready() -> void:
	if model_path != "":
		var scene: PackedScene = load(model_path)
		var model: Node = scene.instantiate()
		add_child(model)
		_tint_leaves(model)
		# Coarser mesh LODs sooner: integrated GPUs are overdraw-bound by leaf cards.
		for node in model.find_children("*", "MeshInstance3D"):
			(node as MeshInstance3D).lod_bias = LOD_BIAS

	var radius: float = trunk_radius
	var centre := Vector2.ZERO
	var measured: Dictionary = TRUNKS.get(model_path.get_file().get_basename(), {})
	if not measured.is_empty():
		centre = measured["centre"]
		if radius <= 0.0:
			radius = measured["radius"]
	if radius <= 0.0:
		radius = 0.5

	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = max(trunk_height, radius * 2.0)

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(centre.x, shape.height * 0.5, centre.y)
	add_child(collision)

func _tint_leaves(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.mesh.surface_get_material(surface)
			if original != null and LEAF_MATERIALS.has(original.resource_name):
				mesh_instance.set_surface_override_material(surface, LEAF_MATERIALS[original.resource_name])
				mesh_instance.set_instance_shader_parameter("leaf_tint", leaf_tint)
