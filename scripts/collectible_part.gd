extends Node3D

# Placeholder collectible robot part: spins and bobs, disappears when the
# player touches it. No inventory yet - it just announces itself.

const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.0

@export var part_name: String = "Robot part"
@export var color: Color = Color(1.0, 0.7, 0.2)

@onready var visual: Node3D = $Visual
@onready var pickup: Area3D = $Pickup

var _time := 0.0

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	for mesh_instance in visual.find_children("*", "MeshInstance3D"):
		(mesh_instance as MeshInstance3D).material_override = material
	($Glow as OmniLight3D).light_color = color
	pickup.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	visual.rotation.y += SPIN_SPEED * delta
	visual.position.y = 0.6 + sin(_time * BOB_SPEED) * BOB_HEIGHT

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	get_tree().call_group("hud", "show_notice", "Collected %s" % part_name)
	print("Collected %s" % part_name)
	queue_free()
