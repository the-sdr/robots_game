extends Node3D

# Dungeon 1, the Relay Vault (below the Hub; the lift in the relay tower's base
# room brings you here). The shell (rooms, walls, collision, markers) is built by
# tools/relay_vault_build.gd from level_design/relay_vault_design.json; this
# wrapper adds what you play with, at the shell's markers:
#   - the mirror hall: a beam enters from the west wall and bounces off mirrors
#     (E flips one); lighting the receiver lens opens the door to Pythia. The
#     beam is powered while the sun is up (a shaft to the surface) or for a while
#     after the laser hits the port in the wall;
#   - Pythia (scenes/npc/pythia.tscn), the solar cell behind the door, the lift
#     back up, lamps, story triggers, and interior lighting while you're inside.

const MIRROR_SCRIPT := preload("res://scripts/dungeons/mirror.gd")
const PORT_SCRIPT := preload("res://scripts/dungeons/laser_port.gd")
const LIFT := preload("res://scenes/props/lift_pad.tscn")
const PYTHIA := preload("res://scenes/npc/pythia.tscn")
const COLLECTIBLE := preload("res://scenes/props/collectible_part.tscn")
const STORY_TRIGGER := preload("res://scripts/interact/story_trigger.gd")
const LIT_FLAG := "vault_lit"
const BEAM_Y := 1.2
const SUN_COLOUR := Color(1.0, 0.88, 0.55)
const LASER_COLOUR := Color(1.0, 0.35, 0.3)
## Where the lift up arrives: in the relay tower's base room, facing its door.
const TOWER_ARRIVAL := Vector3(0, 0.1, -133.2)

@onready var shell: Node3D = $Shell

var mirrors := {}                 # id -> mirror body
var laser_left := 0.0
var _source: Vector2
var _direction := Vector2i(1, 0)
var _laser_seconds := 20.0
var _hall := Rect2()
var _receiver: Vector2
var _beam_parts: Array[MeshInstance3D] = []
var _beam_material: StandardMaterial3D
var _shaft: MeshInstance3D
var _receiver_material: StandardMaterial3D
var _door: StaticBody3D
var _last_lit := false

func _ready() -> void:
	var src: Marker3D = shell.get_node("BeamSource")
	_source = Vector2(src.position.x, src.position.z)
	_direction = {"E": Vector2i(1, 0), "W": Vector2i(-1, 0), "N": Vector2i(0, -1), "S": Vector2i(0, 1)}[String(src.get_meta("direction", "E"))]
	_laser_seconds = float(src.get_meta("laser_seconds", 20.0))
	var r: Array = src.get_meta("hall_rect")
	_hall = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	var rec: Marker3D = shell.get_node("Receiver")
	_receiver = Vector2(rec.position.x, rec.position.z)
	for child in shell.get_children():
		if child is Marker3D and child.name.begins_with("Mirror_"):
			var m: StaticBody3D = StaticBody3D.new()
			m.set_script(MIRROR_SCRIPT)
			m.name = child.name
			m.position = child.position
			add_child(m)
			m.setup(String(child.get_meta("start", "/")), bool(child.get_meta("decoy", false)))
			mirrors[String(child.name).trim_prefix("Mirror_")] = m
	_build_port(src.position)
	_build_receiver(rec.position)
	_build_door()
	_build_beam()
	_build_lights()
	_build_triggers()
	var pythia: Node3D = PYTHIA.instantiate()
	pythia.position = (shell.get_node("Pythia") as Node3D).position
	pythia.rotation.y = PI                 # faces south, into her chamber
	add_child(pythia)
	var cell: Node3D = COLLECTIBLE.instantiate()
	cell.name = "SolarCell"
	cell.set("part_name", "Solar cell")
	cell.set("item_id", "solar_cell")
	cell.position = (shell.get_node("SolarCell") as Node3D).position
	add_child(cell)
	var lift: Node3D = LIFT.instantiate()
	lift.name = "LiftUp"
	lift.set("prompt", "Go up: the relay tower")
	lift.set("target", TOWER_ARRIVAL)
	lift.set("target_heading", 180.0)
	lift.position = (shell.get_node("Lift") as Node3D).position
	add_child(lift)
	if Game.get_flag(LIT_FLAG):
		_open_door(false)

func _process(delta: float) -> void:
	laser_left = maxf(laser_left - delta, 0.0)
	var sunny := sun_on_source()
	_shaft.visible = sunny
	var powered := sunny or laser_left > 0.0
	var result := trace()
	var lit: bool = powered and result["lit"]
	_draw_beam(result["points"] if powered else [], LASER_COLOUR if laser_left > 0.0 and not sunny else SUN_COLOUR)
	_receiver_material.emission_energy_multiplier = 4.0 if lit else 0.2
	if lit and not Game.get_flag(LIT_FLAG):
		Game.set_flag(LIT_FLAG, true)
		get_tree().call_group("hud", "show_notice", "The lens blazes. Somewhere, a door grinds open.")
		Story.play("vault_lit")
		_open_door(true)
	_last_lit = lit

## The sun reaches the beam's source down the shaft while it's properly up.
func sun_on_source() -> bool:
	return Clock.sun_direction().y > 0.15

## Follows the beam from the source through the mirrors to a wall.
## {"points": [Vector2 in the vault's x/z], "lit": reaches the receiver}.
func trace() -> Dictionary:
	var pos := _source
	var dir := _direction
	var points: Array[Vector2] = [pos]
	for bounce in 12:
		var hit := ""
		var best := INF
		for id in mirrors:
			var mp := Vector2(mirrors[id].position.x, mirrors[id].position.z)
			var rel := mp - pos
			var ahead := rel.x * dir.x + rel.y * dir.y
			var side := absf(rel.x * dir.y - rel.y * dir.x)
			if ahead > 0.05 and side < 0.3 and ahead < best:
				best = ahead
				hit = id
		if hit == "":
			var end := _wall_hit(pos, dir)
			points.append(end)
			return {"points": points, "lit": end.distance_to(_receiver) < 0.5}
		pos = Vector2(mirrors[hit].position.x, mirrors[hit].position.z)
		points.append(pos)
		dir = MIRROR_SCRIPT.reflect(mirrors[hit].state, dir)
	return {"points": points, "lit": false}

func _wall_hit(pos: Vector2, dir: Vector2i) -> Vector2:
	if dir.x > 0:
		return Vector2(_hall.end.x, pos.y)
	if dir.x < 0:
		return Vector2(_hall.position.x, pos.y)
	if dir.y < 0:
		return Vector2(pos.x, _hall.position.y)
	return Vector2(pos.x, _hall.end.y)

## The laser port feeds the beam for a while (hit it with the laser).
func power_from_laser() -> void:
	laser_left = _laser_seconds
	get_tree().call_group("hud", "show_notice", "The lens in the wall drinks the laser. The beam runs for %d seconds." % roundi(_laser_seconds))

func _open_door(animate: bool) -> void:
	for shape in _door.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = true
	var up: float = _door.position.y + 3.4
	if not animate:
		_door.position.y = up
		return
	var t := create_tween()
	t.tween_property(_door, "position:y", up, 2.0).set_trans(Tween.TRANS_SINE)

# --- building the pieces ----------------------------------------------------------------------
func _mat(colour: Color, emission: float = 0.0, metallic: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metallic
	m.roughness = 0.4
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = emission
	return m

func _mesh(parent: Node, mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _build_port(at: Vector3) -> void:
	var port := StaticBody3D.new()
	port.set_script(PORT_SCRIPT)
	port.name = "LaserPort"
	port.position = Vector3(_hall.position.x + 0.2, at.y, at.z)
	add_child(port)
	var housing := CylinderMesh.new()
	housing.top_radius = 0.3
	housing.bottom_radius = 0.34
	housing.height = 0.35
	_mesh(port, housing, _mat(Color(0.25, 0.26, 0.28)), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	var lens := CylinderMesh.new()
	lens.top_radius = 0.2
	lens.bottom_radius = 0.2
	lens.height = 0.05
	_mesh(port, lens, _mat(Color(1.0, 0.45, 0.35), 1.2, 0.2), Vector3(0.19, 0, 0), Vector3(0, 0, PI * 0.5))
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.7, 0.7)
	col.shape = box
	port.add_child(col)
	port.powered.connect(power_from_laser)

func _build_receiver(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "ReceiverLens"
	holder.position = Vector3(at.x, at.y, _hall.position.y + 0.1)
	add_child(holder)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.48
	_mesh(holder, ring, _mat(Color(0.7, 0.55, 0.25), 0.0, 0.9), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	var lens := CylinderMesh.new()
	lens.top_radius = 0.36
	lens.bottom_radius = 0.36
	lens.height = 0.08
	_receiver_material = _mat(Color(1.0, 0.9, 0.55), 0.2, 0.1)
	_mesh(holder, lens, _receiver_material, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))

func _build_door() -> void:
	var marker: Node3D = shell.get_node("Door")
	var size: Vector3 = marker.get_meta("size")
	_door = StaticBody3D.new()
	_door.name = "OracleDoor"
	_door.position = marker.position
	add_child(_door)
	var box := BoxMesh.new()
	box.size = size
	_mesh(_door, box, _mat(Color(0.3, 0.32, 0.35)), Vector3(0, size.y * 0.5, 0))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(size.x, 0.15, size.z + 0.02)
	_mesh(_door, stripe, _mat(Color(0.9, 0.7, 0.1), 0.3, 0.0), Vector3(0, size.y * 0.5, 0))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	_door.add_child(col)

func _build_beam() -> void:
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color = SUN_COLOUR
	_beam_material.emission_enabled = true
	_beam_material.emission = SUN_COLOUR
	_beam_material.emission_energy_multiplier = 3.0
	for i in 8:
		var mi := MeshInstance3D.new()
		mi.name = "Beam%d" % i
		var rod := CylinderMesh.new()
		rod.top_radius = 0.04
		rod.bottom_radius = 0.04
		rod.height = 1.0
		rod.radial_segments = 6
		mi.mesh = rod
		mi.material_override = _beam_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_beam_parts.append(mi)
	# the sunlight coming down the shaft onto the source
	_shaft = MeshInstance3D.new()
	_shaft.name = "SunShaft"
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.35
	shaft.bottom_radius = 0.18
	shaft.height = 4.2
	_shaft.mesh = shaft
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light.albedo_color = Color(1.0, 0.95, 0.75, 0.25)
	_shaft.material_override = light
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft.position = Vector3(_source.x + 0.25, BEAM_Y + 2.1, _source.y)
	add_child(_shaft)

func _draw_beam(points: Array, colour: Color) -> void:
	_beam_material.albedo_color = colour
	_beam_material.emission = colour
	for i in _beam_parts.size():
		var part := _beam_parts[i]
		if i + 1 >= points.size():
			part.visible = false
			continue
		var a := Vector3(points[i].x, BEAM_Y, points[i].y)
		var b := Vector3(points[i + 1].x, BEAM_Y, points[i + 1].y)
		var length := a.distance_to(b)
		if length < 0.01:
			part.visible = false
			continue
		part.visible = true
		var dir := (b - a) / length
		var side := dir.cross(Vector3.UP).normalized()
		part.transform = Transform3D(Basis(side, dir, side.cross(dir)), (a + b) * 0.5)
		part.scale = Vector3(1, length, 1)

func _build_lights() -> void:
	for child in shell.get_children():
		if child is Marker3D and child.name.begins_with("Light"):
			var lamp := OmniLight3D.new()
			lamp.position = child.position
			lamp.light_color = Color(1.0, 0.85, 0.65)
			lamp.light_energy = 1.4
			lamp.omni_range = 9.0
			add_child(lamp)

func _build_triggers() -> void:
	# the lighting goes underground while the robot is anywhere in the vault
	var inside := Area3D.new()
	inside.name = "Inside"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(18, 9, 38)
	shape.shape = box
	shape.position = Vector3(0, 3.5, -14.5)
	inside.add_child(shape)
	add_child(inside)
	inside.body_entered.connect(func(body: Node3D) -> void: _set_interior(body, true))
	inside.body_exited.connect(func(body: Node3D) -> void: _set_interior(body, false))
	for pair in [["VaultTrigger", "vault"], ["HallTrigger", "mirrors"]]:
		var t := Area3D.new()
		t.set_script(STORY_TRIGGER)
		t.set("beat", pair[1])
		t.position = (shell.get_node(String(pair[0])) as Node3D).position + Vector3(0, 1, 0)
		var s := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.5
		s.shape = sphere
		t.add_child(s)
		add_child(t)

func _set_interior(body: Node3D, on: bool) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("day_night", "set_interior", on)
