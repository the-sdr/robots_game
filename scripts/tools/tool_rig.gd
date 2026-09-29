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
const NOZZLE_MODEL := "res://scenes/props/items/nozzle.res"

@onready var player: CharacterBody3D = owner as CharacterBody3D
@onready var visual: Node3D = get_node("../..")          # Visual, whose -Z is the robot's facing
@onready var arm: Node3D = get_parent()                   # ArmRight

var tool_id := ""
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
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _head != null and tool_id == "cutter":
		_head.rotate_object_local(Vector3.FORWARD, delta * (28.0 if _cooldown_left > 0.0 else 3.0))

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
