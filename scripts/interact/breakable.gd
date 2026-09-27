class_name Breakable
extends StaticBody3D

# Something a tool can destroy: a door, brambles, a rotten trunk, a crate.
# `effects` lists which tool effects hurt it (see Catalog.TOOLS "effect").
# When health reaches zero it drops items, sets a flag and disappears; the
# flag keeps it gone across saves (flag "broken:<scene path>" unless
# `break_flag` is set). Put the collision shapes and meshes under this node.

signal hit(effect: String, health_left: float)
signal broken

@export var effects: PackedStringArray = ["smash"]
@export var health: float = 100.0
@export var drops: Dictionary = {}           # item id -> count, given straight to the robot
@export var break_flag: String = ""          # set when broken; also what marks it gone on load
@export var debris_colour: Color = Color(0.5, 0.4, 0.3)
@export var debris_count: int = 28
@export var hit_notice: String = ""          # shown on a hit with the wrong tool (default text if empty)
@export var display_name: String = "it"

var _max_health: float

func _ready() -> void:
	add_to_group("breakable")
	_max_health = health
	if break_flag == "":
		break_flag = "broken:" + String(get_path()).trim_prefix("/root/")
	if Game.get_flag(break_flag):
		queue_free()

func accepts(effect: String) -> bool:
	return effects.has(effect)

## Returns true when the effect applied. The tool rig calls this.
func apply(effect: String, power: float, from: Vector3) -> bool:
	if not accepts(effect):
		get_tree().call_group("hud", "show_notice", hit_notice if hit_notice != "" else "That doesn't work on %s" % display_name)
		return false
	health -= power
	_shake()
	_debris(from, mini(6, debris_count / 4))
	hit.emit(effect, health)
	if health <= 0.0:
		_break(from)
	return true

func _break(from: Vector3) -> void:
	_debris(from, debris_count)
	for id in drops:
		Game.add_item(id, int(drops[id]))
		get_tree().call_group("hud", "show_notice", "Took %s x%d" % [Catalog.item_name(id), int(drops[id])])
	Game.set_flag(break_flag, true)
	broken.emit()
	queue_free()

func _shake() -> void:
	var tween := create_tween()
	var origin := position
	tween.tween_property(self, "position", origin + Vector3(0.03, 0.0, 0.03), 0.04)
	tween.tween_property(self, "position", origin - Vector3(0.03, 0.0, 0.03), 0.04)
	tween.tween_property(self, "position", origin, 0.04)

func _debris(from: Vector3, count: int) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 1.1
	particles.explosiveness = 1.0
	particles.direction = (global_position - from).normalized() + Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.5
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.05, 0.07)
	var material := StandardMaterial3D.new()
	material.albedo_color = debris_colour
	mesh.material = material
	particles.mesh = mesh
	var aabb := _collision_aabb()
	get_parent().add_child(particles)        # a sibling: survives this node being freed
	particles.global_position = aabb.get_center() if aabb.size != Vector3.ZERO else global_position
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.2).timeout.connect(particles.queue_free)

func _collision_aabb() -> AABB:
	var result := AABB()
	var first := true
	for shape in find_children("*", "CollisionShape3D", true, false):
		var box: BoxShape3D = (shape as CollisionShape3D).shape as BoxShape3D
		var size: Vector3 = box.size if box != null else Vector3.ONE
		var aabb := AABB((shape as CollisionShape3D).global_position - size * 0.5, size)
		result = aabb if first else result.merge(aabb)
		first = false
	return result
