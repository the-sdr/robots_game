extends Node3D

const SWAY_RADIUS := 1.5
const SWAY_AMOUNT := 0.25
const SWAY_SPEED := 6.0
const LEAF_MATERIALS := {
	"Leaves_NormalTree": preload("res://materials/leaves_normal.tres"),
	"Leaves_TwistedTree": preload("res://materials/leaves_twisted.tres"),
	"Leaves_Pine": preload("res://materials/leaves_pine.tres"),
}

## Leaf colour; leave as-is for the pack's own material. Set by the level bake for brambles.
@export var leaf_tint: Color = Color(0, 0, 0, 0)

var _base_rotation: Vector3
var _player: Node3D

func _ready() -> void:
	_base_rotation = rotation
	_player = get_tree().get_first_node_in_group("player")
	if leaf_tint.a > 0.0:
		for node in find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var original := mesh_instance.mesh.surface_get_material(surface)
				if original != null and LEAF_MATERIALS.has(original.resource_name):
					mesh_instance.set_surface_override_material(surface, LEAF_MATERIALS[original.resource_name])
					mesh_instance.set_instance_shader_parameter("leaf_tint", leaf_tint)

func _process(delta: float) -> void:
	if _player == null:
		return

	var dist := global_position.distance_to(_player.global_position)
	var target_tilt := Vector3.ZERO
	if dist < SWAY_RADIUS:
		var to_player := global_position.direction_to(_player.global_position)
		var push: float = 1.0 - (dist / SWAY_RADIUS)
		target_tilt = Vector3(to_player.z, 0, -to_player.x) * push * SWAY_AMOUNT

	rotation = rotation.lerp(_base_rotation + target_tilt, SWAY_SPEED * delta)
