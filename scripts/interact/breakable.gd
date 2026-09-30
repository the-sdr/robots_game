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
## Solid chunks thrown when it breaks (rigid bodies, gone after a few seconds).
@export var chunk_count: int = 8

var _max_health: float
var _visual_root: Node3D

# --- the laser's trace (tool_rig.gd "trace"; owner, 2026-09-29) ----------------------
# A long burnable thing (vines across a wall gap) burns segment by segment where
# the beam lingers, so the player sweeps the beam along it. Short ones just burn.
const TRACE_MIN_LENGTH := 1.5
const TRACE_SEGMENT := 0.6
const TRACE_SECONDS := 0.3
const EASY_TRACE_SECONDS := 0.18
const BURN_TICK := 0.15
var _trace_left: Array[float] = []       # beam seconds each segment still needs
var _trace_centre := Vector3.ZERO
var _trace_axis := Vector3.ZERO
var _trace_length := 0.0
var _trace_ready := false
var _burn_tick := 0.0
var _burn_told := false

func _ready() -> void:
	add_to_group("breakable")
	_max_health = health
	if break_flag == "":
		break_flag = "broken:" + String(get_path()).trim_prefix("/root/")
	if Game.get_flag(break_flag):
		queue_free()
		return
	if not drops.is_empty():
		add_to_group("detectable")          # something to recover inside: the detector senses it

## Where the detector senses what's inside.
func detect_position() -> Vector3:
	return global_position

func accepts(effect: String) -> bool:
	return effects.has(effect)

## Returns true when the effect applied. The tool rig calls this.
func apply(effect: String, power: float, from: Vector3) -> bool:
	if not accepts(effect):
		get_tree().call_group("hud", "show_notice", hit_notice if hit_notice != "" else "That doesn't work on %s" % display_name)
		return false
	health -= power
	_punch(from)
	_debris(from, mini(8, debris_count / 4))
	hit.emit(effect, health)
	if health <= 0.0:
		_break(from)
	return true

## The laser beam resting on `point` for `delta` seconds.
func burn_at(point: Vector3, delta: float, from: Vector3, power: float) -> void:
	if not accepts("burn"):
		if not _burn_told:
			_burn_told = true
			apply("burn", 0.0, from)            # says why not
		return
	_setup_trace()
	if _trace_left.is_empty():
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = BURN_TICK
			apply("burn", power * BURN_TICK, from)
		return
	var along := (point - _trace_centre).dot(_trace_axis) + _trace_length * 0.5
	var i := clampi(int(along / (_trace_length / _trace_left.size())), 0, _trace_left.size() - 1)
	if _trace_left[i] <= 0.0:
		return
	_trace_left[i] -= delta
	if _trace_left[i] <= 0.0:
		_char_segment(i)
		var left := 0
		for t in _trace_left:
			if t > 0.0:
				left += 1
		health = _max_health * float(left) / _trace_left.size()
		hit.emit("burn", health)
		if left == 0:
			_break(from)

## [segments burned, segments in all] (0, 0 for things too short to trace).
func trace_progress() -> Vector2i:
	_setup_trace()
	var burned := 0
	for t in _trace_left:
		if t <= 0.0:
			burned += 1
	return Vector2i(burned, _trace_left.size())

## World-space centre of segment i (tests, and where its char mark goes).
func trace_point(i: int) -> Vector3:
	_setup_trace()
	var step := _trace_length / maxi(_trace_left.size(), 1)
	return _trace_centre + _trace_axis * (-_trace_length * 0.5 + step * (i + 0.5))

func _setup_trace() -> void:
	if _trace_ready:
		return
	_trace_ready = true
	for node in find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var shape_basis := shape.global_transform.basis
		var lengths := [box.size.x * shape_basis.x.length(), box.size.y * shape_basis.y.length(), box.size.z * shape_basis.z.length()]
		var longest := 0
		for k in 3:
			if lengths[k] > lengths[longest]:
				longest = k
		if lengths[longest] < TRACE_MIN_LENGTH:
			return
		_trace_centre = shape.global_position
		_trace_axis = shape_basis[longest].normalized()
		_trace_length = lengths[longest]
		var seconds: float = preload("res://scripts/game/tuning.gd").v("laser_trace_seconds")
		for k in maxi(int(ceil(_trace_length / TRACE_SEGMENT)), 2):
			_trace_left.append(seconds)
		return

## A burned-through segment: a charred band and a puff of embers.
func _char_segment(i: int) -> void:
	var step := _trace_length / _trace_left.size()
	var mark := MeshInstance3D.new()
	var band := BoxMesh.new()
	band.size = Vector3(step * 0.95, 0.35, 0.35)
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.05, 0.04, 0.03)
	soot.emission_enabled = true
	soot.emission = Color(1.0, 0.35, 0.05)
	soot.emission_energy_multiplier = 0.6
	band.material = soot
	mark.mesh = band
	add_child(mark)
	var x := _trace_axis
	var y := (Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).cross(x).normalized()
	mark.global_transform = Transform3D(Basis(x, y, x.cross(y)), trace_point(i))
	var ember := debris_colour
	debris_colour = Color(1.0, 0.45, 0.1)
	_debris(trace_point(i), 6)
	debris_colour = ember

func _break(from: Vector3) -> void:
	_debris(from, debris_count)
	_burst(from)
	for id in drops:
		Game.add_item(id, int(drops[id]))
		get_tree().call_group("hud", "show_notice", "Took %s x%d" % [Catalog.item_name(id), int(drops[id])])
	Game.set_flag(break_flag, true)
	broken.emit()
	queue_free()

## A visible hit: the whole thing jolts away from the blow and squashes.
func _punch(from: Vector3) -> void:
	var away := (global_position - from)
	away.y = 0.0
	away = away.normalized() * 0.09
	var tween := create_tween().set_parallel(true)
	var origin := position
	var base_scale := scale
	tween.tween_property(self, "position", origin + away, 0.05)
	tween.tween_property(self, "scale", base_scale * Vector3(1.06, 0.92, 1.06), 0.05)
	tween.chain().tween_property(self, "position", origin - away * 0.4, 0.06)
	tween.tween_property(self, "scale", base_scale * Vector3(0.97, 1.04, 0.97), 0.06)
	tween.chain().tween_property(self, "position", origin, 0.08)
	tween.tween_property(self, "scale", base_scale, 0.08)

## Solid chunks that fly apart and tumble; sized from the collision box.
func _burst(from: Vector3) -> void:
	var aabb := _collision_aabb()
	if aabb.size == Vector3.ZERO:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = debris_colour
	material.roughness = 0.85
	var away := (aabb.get_center() - from)
	away.y = 0.0
	away = away.normalized()
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var thin: float = minf(aabb.size.x, minf(aabb.size.y, aabb.size.z))
	for i in chunk_count:
		var body := RigidBody3D.new()
		var mesh := BoxMesh.new()
		# planks for flat things (doors, fences), blocks for boxes and rubble
		var plank := thin < longest * 0.25
		mesh.size = Vector3(longest * 0.12, longest * 0.4, maxf(thin, 0.05)) if plank else aabb.size * 0.28
		mesh.material = material
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		body.add_child(shape)
		body.collision_layer = 0                      # never blocks the robot
		body.collision_mask = 1
		body.mass = 2.0
		var t := float(i) / maxf(chunk_count - 1, 1)
		var start: Vector3 = aabb.position + Vector3(aabb.size.x * (0.15 + 0.7 * fmod(t * 2.0, 1.0)), aabb.size.y * (0.25 + 0.6 * t), aabb.size.z * 0.5)
		get_parent().add_child(body)
		body.global_position = start
		body.rotation = Vector3(t * 1.7, i * 0.9, t * 0.6)
		var spin := Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
		body.apply_central_impulse((away * randf_range(2.5, 5.0) + Vector3(randf_range(-1.5, 1.5), randf_range(3.0, 6.0), 0)) * body.mass)
		body.angular_velocity = spin
		get_tree().create_timer(3.0 + randf() * 1.5).timeout.connect(body.queue_free)

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
