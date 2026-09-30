extends StaticBody3D

@export var model_path: String = ""
@export var collision_radius: float = 0.8

func _ready() -> void:
	if model_path != "":
		var scene: PackedScene = load(model_path)
		add_child(scene.instantiate())

	var shape := SphereShape3D.new()
	shape.radius = collision_radius

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, collision_radius * 0.6, 0)
	add_child(collision)
