extends Node3D

# The robot's tool arm. Reads the equipped tool from Game/Catalog, builds a
# placeholder head for it, swings it on `use_tool`, and applies the tool's
# effect to the nearest Breakable in front of the robot. Adding a tool is a
# Catalog entry; nothing here needs to change for smash/cut variants. Other
# effect families (hover, laser, matter generation) plug in via `_special`.

const HIT_RADIUS := 0.55
const DRY_SWING_COST_FRACTION := 0.25

@onready var player: CharacterBody3D = owner as CharacterBody3D
@onready var visual: Node3D = get_node("../..")          # Visual, whose -Z is the robot's facing
@onready var arm: Node3D = get_parent()                   # ArmRight

var tool_id := ""
var _head: Node3D
var _cooldown_left := 0.0
var _swing_tween: Tween
var _hit_shape := SphereShape3D.new()
var _flash: OmniLight3D

func _ready() -> void:
	_hit_shape.radius = HIT_RADIUS
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
		get_tree().call_group("hud", "show_notice", "No tool attached. Build one (Tab).")
		return false
	if _cooldown_left > 0.0 or player.docked or player.shut_down:
		return false
	var def := definition()
	var cost: float = def["energy"]
	if Energy.current < cost:
		get_tree().call_group("hud", "show_notice", "Not enough energy to use the %s" % def["name"])
		return false
	_cooldown_left = def["cooldown"]
	_swing(def["cooldown"])
	var target := _find_target(def["range"])
	if target == null:
		Energy.spend(cost * DRY_SWING_COST_FRACTION)
		return false
	Energy.spend(cost)
	var applied: bool = target.apply(def["effect"], def["power"], player.global_position)
	if applied:
		_flash.light_color = def.get("colour", Color.WHITE)
		_flash.light_energy = 4.0
		var tween := create_tween()
		tween.tween_property(_flash, "light_energy", 0.0, 0.18)
	return applied

func _find_target(reach: float) -> Breakable:
	var forward: Vector3 = -visual.global_transform.basis.z
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hit_shape
	query.transform = Transform3D(Basis(), player.global_position + Vector3(0, 0.6, 0) + forward * (reach * 0.65))
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var best: Breakable = null
	var best_d := INF
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := hit["collider"] as Breakable
		if body == null:
			continue
		var d := player.global_position.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best

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
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.14, 0.1, 0.2)
			mi.mesh = box
	mi.material_override = material
	head.add_child(mi)
	head.position = Vector3(0, -0.24, -0.36)
	return head
