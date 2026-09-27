extends StaticBody3D

# Trunk collision measured from each model's mesh at 0.3-0.6 m height (where
# the robot's treads hit). Centre is the trunk's offset from the model origin.
# Values are the outermost trunk vertex, so nothing can pass through the bark.
const TRUNKS := {
	"CommonTree_1": {"radius": 0.55, "centre": Vector2(0.02, 0.11)},
	"CommonTree_3": {"radius": 0.55, "centre": Vector2(0.01, 0.11)},
	"CommonTree_5": {"radius": 0.50, "centre": Vector2(0.07, 0.10)},
	"DeadTree_1": {"radius": 0.52, "centre": Vector2(0.13, 0.0)},
	"TwistedTree_2": {"radius": 1.12, "centre": Vector2(0.06, -0.01)},
	"TwistedTree_4": {"radius": 1.15, "centre": Vector2(0.02, 0.10)},
}

const LOD_BIAS := 0.4   # < 1 = switch to the model's simpler versions sooner (matches level_bake.gd)

@export var model_path: String = ""
## 0 = use the measured trunk for this model (see TRUNKS).
@export var trunk_radius: float = 0.0
@export var trunk_height: float = 2.5

func _ready() -> void:
	if model_path != "":
		var scene: PackedScene = load(model_path)
		var model: Node = scene.instantiate()
		add_child(model)
		for mesh_instance in model.find_children("*", "GeometryInstance3D"):
			(mesh_instance as GeometryInstance3D).lod_bias = LOD_BIAS

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
