extends Node3D

# A part lying in the world: spins and bobs, goes into the inventory when the
# robot touches it. `item_id` is a Catalog item; if empty it is derived from
# part_name ("Servo motor" -> "servo_motor"). Stays collected across saves.

const SPIN_SPEED := 1.2
const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.0
## Per-item models built by tools/item_models_bake.gd; the gear is the fallback.
const MODEL := "res://scenes/props/items/%s.res"

@export var part_name: String = "Robot part"
@export var item_id: String = ""
@export var amount: int = 1
@export var color: Color = Color(1.0, 0.7, 0.2)
## Reach of the pickup: an upright cylinder from the ground to 1.2 m, so the
## tiny-cursed robot (5 cm tall) reaches it as well as the full-size one. Small
## for parts hidden in tight spots (the crooked house's mouse-hole nook), so
## they can't be grabbed from outside.
@export var pickup_radius: float = 0.9

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
	add_to_group("detectable")
	var model_path := MODEL % item_id
	if ResourceLoader.exists(model_path):
		# the item's own model (tools/item_models_bake.gd) replaces the placeholder gear
		for placeholder in visual.get_children():
			placeholder.free()
		var model := MeshInstance3D.new()
		model.name = "Model"
		model.mesh = load(model_path)
		visual.add_child(model)
	else:
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
	var col: CollisionShape3D = pickup.get_node("CollisionShape3D")
	if not is_equal_approx((col.shape as CylinderShape3D).radius, pickup_radius):
		var cylinder := CylinderShape3D.new()    # the scene's shape is shared by every pickup
		cylinder.radius = pickup_radius
		cylinder.height = (col.shape as CylinderShape3D).height
		col.shape = cylinder
	pickup.body_entered.connect(_on_body_entered)

## Where the detector senses it.
func detect_position() -> Vector3:
	return global_position

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
