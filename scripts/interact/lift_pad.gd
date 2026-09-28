extends Node3D

# A lift platform: E on it fades the screen, moves the robot to `target` facing
# `target_heading` (compass degrees, 0 = north), and fades back in. The relay
# tower's base room has one going down to the Relay Vault, the vault has one
# coming back up. A fade and a jump is steadier than a moving platform.

@export var prompt := "Go down"
## World position the robot arrives at.
@export var target := Vector3.ZERO
@export var target_heading := 0.0

@onready var interactable: Interactable = $Interactable
@onready var ring: MeshInstance3D = $Ring

var _time := 0.0

func _ready() -> void:
	interactable.prompt = prompt
	interactable.interacted.connect(travel)

func _process(delta: float) -> void:
	_time += delta
	(ring.material_override as StandardMaterial3D).emission_energy_multiplier = 1.2 + 0.6 * sin(_time * 3.0)

## Moves the robot (fades through black when there is a HUD to do it).
func travel(player: Node3D) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var go := func() -> void:
		player.global_position = target
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		var visual: Node3D = player.get_node_or_null("Visual")
		if visual != null:
			visual.global_rotation.y = -deg_to_rad(target_heading)
	if hud != null and hud.has_method("fade_through"):
		hud.fade_through(go)
	else:
		go.call()
