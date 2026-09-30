extends Node3D

# The robot's tool arm. Reads the equipped tool from Game/Catalog, builds a
# placeholder head for it, swings it on `use_tool`, and applies the tool's
# effect to the nearest Breakable in front of the robot. Adding a tool is a
# Catalog entry; nothing here needs to change for smash/cut variants. Other
# effect families (hover, laser, matter generation) plug in via `_special`.

## Hit volume: a box from the robot's centre out to the tool's reach, this wide
## and tall. (A ball centred ahead missed a door the robot was pressed against.)
const HIT_WIDTH := 1.1
const HIT_HEIGHT := 1.3
const DRY_SWING_COST_FRACTION := 0.25
## A tiny robot (the Angry Zombie's curse) hits half as hard.
const TINY_POWER := 0.5
## Ranged tools look for targets in a box this wide and tall along their reach.
const RANGED_AIM_WIDTH := 1.6
const RANGED_AIM_HEIGHT := 2.0
const HAMMER_MODEL := "res://scenes/props/items/hammer_head.res"
const T := preload("res://scripts/game/tuning.gd")          # the feel numbers (F10 tunes them live)

# --- how each tool feels (owner, 2026-09-29): Catalog.TOOLS "pattern" ---------------
# The player presses and releases (press/release, from player.gd); use() stays a
# single complete action (tests, the fight screen). Easy softens every pattern.
## Smasher, "rapid": each press is a hit; quick presses build a combo.
const COMBO_MAX := 5
const RAPID_ENERGY := 1.5        # per hit
const EASY_AUTO_HIT := 0.3       # Easy: holding the button hits this often
## Cutter, "hold_heat": cuts while held; heat climbs. Let go in the green zone for
## a clean cut (a bonus); hold to the top and it overheats and must cool.
const HELD_TICK := 0.15          # held tools deal damage in ticks
## Laser, "trace": a steady beam aimed with the camera; long things (vines) burn
## segment by segment as the beam is swept along them (Breakable.burn_at).
const LASER_ENERGY_RATE := 1.0   # energy per second = the tool's energy x this
const NOZZLE_MODEL := "res://scenes/props/items/nozzle.res"

@onready var player: CharacterBody3D = owner as CharacterBody3D
@onready var visual: Node3D = get_node("../..")          # Visual, whose -Z is the robot's facing
@onready var arm: Node3D = get_parent()                   # ArmRight

var tool_id := ""
## True between press() and release() for held tools.
var holding := false
## Cutter heat 0..1, and seconds left of an overheat.
var heat := 0.0
var overheated := 0.0
## Smasher combo (1 = a single hit).
var combo := 0
## Clean cuts made (tests).
var clean_cuts := 0
var _last_hit_time := -10.0
var _now := 0.0                       # game time (seconds), so combos follow the game's clock
var _tick := 0.0
var _auto_hit := 0.0
var _cut_target: Node3D = null
var _told: Array[Node] = []           # targets already told "wrong tool" this press
var _laser_beam: MeshInstance3D
var _laser_material: StandardMaterial3D
var _head: Node3D
var _cooldown_left := 0.0
var _swing_tween: Tween
var _hit_shape := BoxShape3D.new()
var _flash: OmniLight3D

func _ready() -> void:
	_flash = OmniLight3D.new()
	_flash.light_energy = 0.0
	_flash.omni_range = 3.0
	_flash.position = Vector3(0, -0.3, -0.5)
	add_child(_flash)
	Game.inventory_changed.connect(refresh)
	Game.loaded.connect(refresh)
	Game.new_game_started.connect(refresh)
	refresh()

func _process(delta: float) -> void:
	_now += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	var pattern := String(definition().get("pattern", ""))
	if holding and (player.docked or player.shut_down or player.get("in_combat")):
		release()
	if holding:
		match pattern:
			"rapid":
				_auto_hit -= delta
				if _easy() and _auto_hit <= 0.0:
					_auto_hit = EASY_AUTO_HIT
					_rapid_hit()
			"hold_heat":
				_cut(delta)
			"trace":
				_fire_laser(delta)
	if not (holding and pattern == "hold_heat"):
		heat = maxf(heat - T.v("cutter_cool_rate") * delta, 0.0)
		overheated = maxf(overheated - delta, 0.0)
	if pattern == "hold_heat" or heat > 0.0:
		var clean := _clean_zone()
		get_tree().call_group("hud", "show_heat", heat, clean.x, clean.y, overheated > 0.0)
	if _head != null and tool_id == "cutter":
		_head.rotate_object_local(Vector3.FORWARD, delta * (28.0 if holding or _cooldown_left > 0.0 else 3.0))

func _easy() -> bool:
	return Settings.difficulty == "easy"

func pattern() -> String:
	return String(definition().get("pattern", ""))

## The use button went down (player.gd, once per click or trigger pull).
func press() -> void:
	if tool_id == "":
		use()                                  # says "no tool attached"
		return
	if player.docked or player.shut_down:
		return
	_told.clear()
	match pattern():
		"rapid":
			holding = true
			_auto_hit = EASY_AUTO_HIT
			_rapid_hit()
		"hold_heat":
			if overheated > 0.0:
				get_tree().call_group("hud", "show_notice", "Too hot! Let the %s cool down." % definition()["name"])
				return
			holding = true
			_tick = 0.0
			_cut_target = null
		"trace":
			if Energy.current <= 0.0:
				get_tree().call_group("hud", "show_notice", "Not enough energy to use the %s" % definition()["name"])
				return
			holding = true
			_tick = 0.0
			get_tree().call_group("hud", "show_aim", true)
		_:
			use()

## The use button came up.
func release() -> void:
	if not holding:
		return
	holding = false
	match pattern():
		"hold_heat":
			var clean := _clean_zone()
			if overheated <= 0.0 and heat >= clean.x and heat <= clean.y and is_instance_valid(_cut_target):
				clean_cuts += 1
				var bonus: float = float(definition()["power"]) * T.v("cutter_clean_bonus") * _power_scale()
				_cut_target.call("apply", "cut", bonus, player.global_position)
				_spark(1.8)
				get_tree().call_group("hud", "show_notice", "Clean cut!")
		"trace":
			_laser_off()
			get_tree().call_group("hud", "show_aim", false)

func _clean_zone() -> Vector2:
	return Vector2(T.v("cutter_clean_from"), T.v("cutter_clean_to"))

func _power_scale() -> float:
	return TINY_POWER if player.get("tiny") else 1.0

## One smasher hit; quick hits build the combo.
func _rapid_hit() -> void:
	if _cooldown_left > 0.0:
		return
	var def := definition()
	if Energy.current < RAPID_ENERGY:
		get_tree().call_group("hud", "show_notice", "Not enough energy to use the %s" % def["name"])
		return
	combo = mini(combo + 1, COMBO_MAX) if _now - _last_hit_time <= T.v("smasher_combo_window") else 1
	_last_hit_time = _now
	_cooldown_left = T.v("smasher_cooldown")
	_swing(0.28)
	var target := _find_target(def["range"])
	if target == null:
		Energy.spend(RAPID_ENERGY * DRY_SWING_COST_FRACTION)
		return
	Energy.spend(RAPID_ENERGY)
	var power: float = float(def["power"]) * (1.0 + T.v("smasher_combo_bonus") * (combo - 1)) * _power_scale()
	if _apply_once(target, "smash", power):
		_spark(2.5 + combo)
		if combo > 1:
			get_tree().call_group("hud", "show_combo", combo)

## Applies an effect, but a target that refuses it is told only once per press.
func _apply_once(target: Node3D, effect: String, power: float) -> bool:
	if target.has_method("accepts") and not target.call("accepts", effect):
		if not _told.has(target):
			_told.append(target)
			target.call("apply", effect, power, player.global_position)     # it says why not
		return false
	return target.call("apply", effect, power, player.global_position)

## The cutter while held: heat climbs, whatever is in front is cut in ticks.
func _cut(delta: float) -> void:
	if overheated > 0.0:
		return
	var def := definition()
	heat += delta / T.v("cutter_heat_seconds")
	Energy.drain(float(def["energy"]) * delta)
	_tick -= delta
	if _tick <= 0.0:
		_tick = HELD_TICK
		var target := _find_target(def["range"])
		if target != null:
			if _apply_once(target, "cut", float(def["power"]) * T.v("cutter_rate") * HELD_TICK * _power_scale()):
				_cut_target = target
				_spark(1.2)
		_recoil_small()
	if heat >= 1.0:
		heat = 1.0
		overheated = T.v("cutter_overheat_seconds")
		holding = false
		get_tree().call_group("hud", "show_notice", "Overheated! Let it cool.")

## The laser while held: a steady beam to whatever the camera looks at.
func _fire_laser(delta: float) -> void:
	var def := definition()
	var cost: float = float(def["energy"]) * LASER_ENERGY_RATE * delta
	if Energy.current < cost:
		release()
		get_tree().call_group("hud", "show_notice", "Not enough energy to use the %s" % def["name"])
		return
	Energy.drain(cost)
	var aim := laser_aim(float(def["range"]))
	var hit_point: Vector3 = aim["point"]
	var body: Node3D = aim["body"]
	# the robot turns to face where it fires
	var flat := hit_point - player.global_position
	flat.y = 0.0
	if flat.length() > 0.2:
		visual.global_rotation.y = lerp_angle(visual.global_rotation.y, atan2(flat.x, flat.z) + PI, 12.0 * delta)
	_laser_on(def, hit_point)
	if body == null:
		return
	if body.has_method("burn_at"):
		body.call("burn_at", hit_point, delta, player.global_position, float(def["power"]) * T.v("laser_beam_rate") * _power_scale())
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = HELD_TICK
		if body.has_method("apply"):
			_apply_once(body, "burn", float(def["power"]) * T.v("laser_beam_rate") * HELD_TICK * _power_scale())

## Where the laser hits: along the camera's centre line, within reach of the robot.
## {point: Vector3, body: Node3D or null}.
func laser_aim(reach: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var eye := player.global_position + Vector3(0, 0.9 * float(player.get("size_scale")), 0)
	var direction: Vector3 = -visual.global_transform.basis.z
	if camera != null:
		direction = -camera.global_transform.basis.z
	var space := player.get_world_3d().direct_space_state
	var start := eye
	if camera != null:
		# from the camera through the screen centre, starting level with the robot
		var along := (player.global_position - camera.global_position).dot(direction)
		start = camera.global_position + direction * maxf(along, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(start, start + direction * reach)
	ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return {"point": start + direction * reach, "body": null}
	return {"point": hit["position"], "body": hit["collider"] as Node3D}

func _laser_on(def: Dictionary, to: Vector3) -> void:
	if _laser_beam == null:
		_laser_material = StandardMaterial3D.new()
		_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_laser_material.albedo_color = def.get("colour", Color.RED)
		_laser_material.emission_enabled = true
		_laser_material.emission = def.get("colour", Color.RED)
		_laser_material.emission_energy_multiplier = 4.0
		var rod := CylinderMesh.new()
		rod.top_radius = 0.02
		rod.bottom_radius = 0.02
		rod.height = 1.0
		rod.radial_segments = 6
		rod.material = _laser_material
		_laser_beam = MeshInstance3D.new()
		_laser_beam.name = "LaserBeam"
		_laser_beam.mesh = rod
		_laser_beam.top_level = true
		_laser_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_laser_beam)
	var from := global_position + (-visual.global_transform.basis.z) * 0.35
	var length := from.distance_to(to)
	if length < 0.05:
		_laser_beam.visible = false
		return
	var up := (to - from) / length
	var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	_laser_beam.global_transform = Transform3D(Basis(side, up * length, side.cross(up)), (from + to) * 0.5)
	_laser_beam.visible = true
	_flash.light_color = def.get("colour", Color.RED)
	_flash.light_energy = 2.0 + sin(Time.get_ticks_msec() * 0.05) * 0.5

func _laser_off() -> void:
	if _laser_beam != null:
		_laser_beam.visible = false
	_flash.light_energy = 0.0

## Laser beam visible (tests).
func laser_firing() -> bool:
	return _laser_beam != null and _laser_beam.visible

func _spark(energy: float) -> void:
	_flash.light_color = definition().get("colour", Color.WHITE)
	_flash.light_energy = energy
	var tween := create_tween()
	tween.tween_property(_flash, "light_energy", 0.0, 0.15)

func _recoil_small() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		return
	_swing_tween = create_tween()
	_swing_tween.tween_property(arm, "rotation:x", 0.12, 0.05)
	_swing_tween.tween_property(arm, "rotation:x", 0.0, 0.08)

func definition() -> Dictionary:
	return Catalog.TOOLS.get(tool_id, {})

func refresh() -> void:
	var wanted: String = Game.data["equipped_tool"]
	if wanted == tool_id and (_head != null or wanted == ""):
		return
	tool_id = wanted
	if _head != null:
		_head.queue_free()
		_head = null
	if tool_id != "":
		_head = _build_head(definition())
		add_child(_head)
	holding = false
	_laser_off()

## Q: attach the next tool the robot has built.
func cycle() -> void:
	var tools: Array = Game.data["tools"]
	if tools.size() < 2:
		if tools.size() == 1:
			get_tree().call_group("hud", "show_notice", "Only one tool built")
		return
	var index := tools.find(Game.data["equipped_tool"])
	Game.data["equipped_tool"] = tools[(index + 1) % tools.size()]
	Game.inventory_changed.emit()
	get_tree().call_group("hud", "show_notice", "Attached the %s" % Catalog.tool_name(Game.data["equipped_tool"]))

## Left click: swing at whatever is in front.
func use() -> bool:
	if tool_id == "":
		get_tree().call_group("hud", "show_notice", "No tool attached. Build one (%s)." % Glyphs.label("inventory"))
		return false
	if _cooldown_left > 0.0 or player.docked or player.shut_down:
		return false
	var def := definition()
	if def.get("effect", "") == "hover":
		get_tree().call_group("hud", "show_notice", "The hover pack works on its own: jump, then hold %s in the air." % Glyphs.label("jump"))
		return false
	if def.get("effect", "") == "make":
		return _print_nearby(def)
	var cost: float = def["energy"]
	if Energy.current < cost:
		get_tree().call_group("hud", "show_notice", "Not enough energy to use the %s" % def["name"])
		return false
	_cooldown_left = def["cooldown"]
	var ranged: bool = def.get("ranged", false)
	var target := _find_ranged_target(def["range"]) if ranged else _find_target(def["range"])
	if ranged:
		_recoil()
		_beam(def, target)
	else:
		_swing(def["cooldown"])
	if target == null:
		Energy.spend(cost * DRY_SWING_COST_FRACTION)
		return false
	Energy.spend(cost)
	var power: float = def["power"] * (TINY_POWER if player.get("tiny") else 1.0)
	var applied: bool = target.apply(def["effect"], power, player.global_position)
	if applied:
		_flash.light_color = def.get("colour", Color.WHITE)
		_flash.light_energy = 4.0
		var tween := create_tween()
		tween.tween_property(_flash, "light_energy", 0.0, 0.18)
	return applied

## The fabricator in the world: prints the nearest ghost outline in reach
## (group "buildable", scripts/interact/buildable.gd); parts are printed in Tab.
func _print_nearby(def: Dictionary) -> bool:
	var best: Node3D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildable"):
		var node := b as Node3D
		if node == null or node.get("built"):
			continue
		var d := player.global_position.distance_to(node.call("focus_position"))
		if d <= float(def["range"]) and d < best_d:
			best_d = d
			best = node
	if best == null:
		get_tree().call_group("hud", "show_notice", "Nothing here to print. Parts are printed from scrap on the build screen (%s)." % Glyphs.label("inventory"))
		return false
	var cost: float = def["energy"]
	if Energy.current < cost:
		get_tree().call_group("hud", "show_notice", "Not enough energy to print")
		return false
	_cooldown_left = def["cooldown"]
	_recoil()
	var built: bool = best.call("build", player)
	if built:
		Energy.spend(cost)
	return built

## The nearest thing in reach that a tool can act on: any body with
## apply(effect, power, from) -> bool (a Breakable, the Angry Zombie...).
func _find_target(reach: float) -> Node3D:
	var forward: Vector3 = -visual.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var s: float = player.get("size_scale") if player.get("size_scale") != null else 1.0
	reach *= s
	_hit_shape.size = Vector3(HIT_WIDTH * s, HIT_HEIGHT * s, reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hit_shape
	query.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), player.global_position + Vector3(0, 0.6 * s, 0) + forward * (reach * 0.5))
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var best: Node3D = null
	var best_d := INF
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := hit["collider"] as Node3D
		if body == null or not body.has_method("apply"):
			continue
		var d := player.global_position.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best

## Ranged tools (the laser): the nearest body with apply() in a long box ahead
## (a little auto-aim) that nothing solid stands in front of.
func _find_ranged_target(reach: float) -> Node3D:
	var forward: Vector3 = -visual.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var s: float = player.get("size_scale") if player.get("size_scale") != null else 1.0
	var box := BoxShape3D.new()
	box.size = Vector3(RANGED_AIM_WIDTH, RANGED_AIM_HEIGHT, reach)
	var eye := player.global_position + Vector3(0, 0.9 * s, 0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), eye + forward * (reach * 0.5))
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	var candidates := []
	for hit in space.intersect_shape(query, 32):
		var body := hit["collider"] as Node3D
		if body != null and body.has_method("apply"):
			candidates.append(body)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return eye.distance_squared_to(a.global_position) < eye.distance_squared_to(b.global_position))
	for body in candidates:
		var aim: Vector3 = _aim_point(body)
		var ray := PhysicsRayQueryParameters3D.create(eye, aim)
		ray.exclude = [player.get_rid()]
		var seen := space.intersect_ray(ray)
		if seen.is_empty() or seen["collider"] == body:
			return body
	return null

## Where to aim at a body: the centre of its first collision shape (a door's
## box, a lens in a wall), or a little above its origin if it has none.
func _aim_point(body: Node3D) -> Vector3:
	for child in body.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return (child as CollisionShape3D).global_position
	return body.global_position + Vector3(0, 0.8, 0)

## The laser's beam: a thin glowing rod from the arm to what it hit (or as far as it reaches).
func _beam(def: Dictionary, target: Node3D) -> void:
	var from := global_position + (-visual.global_transform.basis.z) * 0.4
	var forward: Vector3 = -visual.global_transform.basis.z
	forward.y = 0.0
	var to: Vector3 = _aim_point(target) if target != null else from + forward.normalized() * float(def["range"])
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var rod := CylinderMesh.new()
	rod.top_radius = 0.025
	rod.bottom_radius = 0.025
	rod.height = length
	rod.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = def.get("colour", Color.RED)
	material.emission_enabled = true
	material.emission = def.get("colour", Color.RED)
	material.emission_energy_multiplier = 4.0
	rod.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = rod
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(mi)
	var up := (to - from).normalized()
	var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (from + to) * 0.5)
	var tween := mi.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(mi.queue_free)

func _recoil() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(arm, "rotation:x", 0.35, 0.05)
	_swing_tween.tween_property(arm, "rotation:x", 0.0, 0.25)

## The fight screen's swing (no target, no energy: combat_state does the rules).
func swing() -> void:
	if definition().get("ranged", false):
		_recoil()
		_beam(definition(), null)
	else:
		_swing(0.5)

func _swing(seconds: float) -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween().set_parallel(true)
	_swing_tween.tween_property(arm, "rotation:x", -2.2, seconds * 0.3).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(visual, "rotation:x", -0.12, seconds * 0.3).set_ease(Tween.EASE_OUT)   # wind up, lean back
	_swing_tween.chain().tween_property(arm, "rotation:x", 0.5, seconds * 0.2).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(visual, "rotation:x", 0.22, seconds * 0.2).set_ease(Tween.EASE_IN)     # lunge into the blow
	_swing_tween.chain().tween_property(arm, "rotation:x", 0.0, seconds * 0.5)
	_swing_tween.tween_property(visual, "rotation:x", 0.0, seconds * 0.5)

# Placeholder heads from primitives, coloured from the catalog, so a new tool
# shows up the moment it is defined. Real art can replace these per tool.
func _build_head(def: Dictionary) -> Node3D:
	var head := Node3D.new()
	head.name = "Head"
	var material := StandardMaterial3D.new()
	material.albedo_color = def.get("colour", Color.GRAY)
	material.metallic = 0.7
	material.roughness = 0.35
	var mi := MeshInstance3D.new()
	match def.get("effect", ""):
		"cut":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.16
			disc.bottom_radius = 0.16
			disc.height = 0.02
			disc.radial_segments = 12
			mi.mesh = disc
			mi.rotation.x = PI * 0.5
			mi.material_override = material
		"hover":
			var fan := CylinderMesh.new()
			fan.top_radius = 0.13
			fan.bottom_radius = 0.13
			fan.height = 0.05
			fan.radial_segments = 14
			mi.mesh = fan
			mi.material_override = material
		"burn":
			# an emitter barrel with a glowing lens at the tip
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.03
			barrel.bottom_radius = 0.045
			barrel.height = 0.24
			barrel.radial_segments = 10
			mi.mesh = barrel
			mi.rotation.x = PI * 0.5
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.2, 0.21, 0.23)
			dark.metallic = 0.8
			dark.roughness = 0.4
			mi.material_override = dark
			var lens := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.035
			ball.height = 0.07
			lens.mesh = ball
			var glow := StandardMaterial3D.new()
			glow.albedo_color = def.get("colour", Color.RED)
			glow.emission_enabled = true
			glow.emission = def.get("colour", Color.RED)
			glow.emission_energy_multiplier = 3.0
			lens.material_override = glow
			lens.position = Vector3(0, 0, -0.13)
			head.add_child(lens)
		"make":
			# the print nozzle, pointing forward, with a glowing tip
			if ResourceLoader.exists(NOZZLE_MODEL):
				mi.mesh = load(NOZZLE_MODEL)
				mi.scale = Vector3.ONE * 0.7
				mi.rotation.x = PI * 0.5          # the model's tip points down (-Y); turn it forward (-Z)
			else:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.02
				cone.bottom_radius = 0.07
				cone.height = 0.16
				mi.mesh = cone
				mi.rotation.x = -PI * 0.5
				mi.material_override = material
			var tip := MeshInstance3D.new()
			var dot := SphereMesh.new()
			dot.radius = 0.025
			dot.height = 0.05
			tip.mesh = dot
			var glow := StandardMaterial3D.new()
			glow.albedo_color = def.get("colour", Color.CYAN)
			glow.emission_enabled = true
			glow.emission = def.get("colour", Color.CYAN)
			glow.emission_energy_multiplier = 2.5
			tip.material_override = glow
			tip.position = Vector3(0, 0, -0.15)
			head.add_child(tip)
		_:
			if ResourceLoader.exists(HAMMER_MODEL):     # the hammer head the smasher is built from
				mi.mesh = load(HAMMER_MODEL)
				mi.scale = Vector3.ONE * 0.5
				mi.rotation.y = PI * 0.5
			else:
				var box := BoxMesh.new()
				box.size = Vector3(0.14, 0.1, 0.2)
				mi.mesh = box
				mi.material_override = material
	head.add_child(mi)
	head.position = Vector3(0, -0.24, -0.36)
	return head
