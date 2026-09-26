extends Node3D

const SWAY_RADIUS := 1.5
const SWAY_AMOUNT := 0.25
const SWAY_SPEED := 6.0

var _base_rotation: Vector3
var _player: Node3D

func _ready() -> void:
	_base_rotation = rotation
	_player = get_tree().get_first_node_in_group("player")

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
