extends StaticBody3D

@export var model_path: String = ""
@export var trunk_radius: float = 0.35
@export var trunk_height: float = 2.5

func _ready() -> void:
	if model_path != "":
		var scene: PackedScene = load(model_path)
		add_child(scene.instantiate())

	var shape := CapsuleShape3D.new()
	shape.radius = trunk_radius
	shape.height = trunk_height

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, trunk_height * 0.5, 0)
	add_child(collision)
