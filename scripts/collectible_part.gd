extends Node3D

# A part lying in the world: spins and bobs, goes into the inventory when the
# robot touches it. `item_id` is a Catalog item; if empty it is derived from
# part_name ("Servo motor" -> "servo_motor"). Stays collected across saves.

const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.0

@export var part_name: String = "Robot part"
@export var item_id: String = ""
@export var amount: int = 1
@export var color: Color = Color(1.0, 0.7, 0.2)

@onready var visual: Node3D = $Visual
@onready var pickup: Area3D = $Pickup

var _time := 0.0

func _flag() -> String:
	return "picked:" + String(get_path()).trim_prefix("/root/")

func _ready() -> void:
	if item_id == "":
		item_id = part_name.to_snake_case()
	if Game.get_flag(_flag()):
		queue_free()
		return
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
	Game.add_item(item_id, amount)
	Game.set_flag(_flag(), true)
	get_tree().call_group("hud", "show_notice", "Collected %s" % part_name)
	print("Collected %s" % part_name)
	queue_free()
