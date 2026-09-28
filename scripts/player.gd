extends CharacterBody3D

const SPEED = 3.0   # exploration pace (owner, 2026-09-27)
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const TURN_SPEED = 10.0
const MOUSE_SENSITIVITY = 0.003
const LOOK_STICK_SPEED = 3.0
const PITCH_MIN = deg_to_rad(-60)
const PITCH_MAX = deg_to_rad(20)
const ZOOM_MIN = 1.5
const ZOOM_MAX = 8.0
const ZOOM_STEP = 0.5
const ZOOM_DEFAULT = 2.0
const CAMERA_COLLISION_MARGIN = 0.3
const CAMERA_ZOOM_SMOOTHING = 10.0
const CAMERA_PROBE_RADIUS = 0.3
# God mode (F7, debug): double-tap jump to toggle flying; jump = up, fly_down = down.
const FLY_SPEED = 10.0
const FLY_VERTICAL_SPEED = 6.0
const DOUBLE_TAP_TIME = 0.3
# The Angry Zombie's tiny curse (Game.is_tiny): smaller, slower, thriftier, fits through mouse holes.
const TINY_SCALE = 0.4
const TINY_SPEED = 0.6
const TINY_JUMP = 0.6
const TINY_DRAIN = 0.5
const TINY_ZOOM = 0.55
const CAMERA_HEIGHT = 1.5
# The eye lenses' irises: six blades in front of each lens (the opening
# cutscene's last shot). 0 = shut, 1 = open (normal play).
const IRIS_BLADES = 6
const IRIS_SHUT_R = 0.013
const IRIS_OPEN_R = 0.037
const IRIS_BLADE_HALF_LENGTH = 0.026
const IRIS_BLADE_HALF_WIDTH = 0.012

@onready var visual: Node3D = $Visual
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_arm: Node3D = $CameraRig/CameraArm
@onready var camera: Camera3D = $CameraRig/CameraArm/Camera3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var interact_probe: Area3D = $InteractProbe
@onready var headlight: SpotLight3D = $Visual/Head/Headlight
@onready var tool_rig: Node3D = $Visual/ArmRight/ToolRig
@onready var wheels: Array[Node] = [$Visual/TreadLeft/WheelFront, $Visual/TreadLeft/WheelBack, $Visual/TreadRight/WheelFront, $Visual/TreadRight/WheelBack]
@onready var chest_panel: MeshInstance3D = $Visual/ChestPanel
@onready var lenses: Array[Node] = [$Visual/Head/LensLeft, $Visual/Head/LensRight]

const WHEEL_RADIUS := 0.12
var _chest_material: StandardMaterial3D
var _lens_material: StandardMaterial3D

var target_zoom := ZOOM_DEFAULT
var _camera_probe_shape: SphereShape3D
var god_mode := false
var flying := false
var _last_jump_press_time := -1.0
## Set by a charger while docked: no driving, energy flows in.
var docked := false
## Set by the world while the battery is dead: nothing responds.
var shut_down := false
## Set by the fight screen (scripts/combat/combat.gd): no driving, tools or interacting.
var in_combat := false
var _hud: CanvasLayer
var _focus: Interactable = null
## True while the tiny curse has shrunk the robot (it can lag Game.is_tiny() while there's no room to regrow).
var tiny := false
## 1.0 normally, TINY_SCALE while tiny: camera, tool reach and hit height follow it.
var size_scale := 1.0
var _normal_shape: CapsuleShape3D
var _tiny_shape: CapsuleShape3D
var _regrow_wait := 0.0
var _cramped_told := false
var _size_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_normal_shape = body_collision.shape as CapsuleShape3D
	_tiny_shape = CapsuleShape3D.new()
	_tiny_shape.radius = _normal_shape.radius * TINY_SCALE
	_tiny_shape.height = _normal_shape.height * TINY_SCALE
	_build_iris()
	_build_hover_fx()
	# Own copies of the shared materials so this robot can light up on its own.
	_chest_material = StandardMaterial3D.new()
	_chest_material.albedo_color = Color(0.1, 0.11, 0.12)
	_chest_material.emission_enabled = true
	chest_panel.material_override = _chest_material
	_lens_material = (lenses[0] as MeshInstance3D).mesh.material.duplicate()
	for lens in lenses:
		(lens as MeshInstance3D).material_override = _lens_material
	Energy.changed.connect(_on_energy_changed)
	_on_energy_changed(Energy.current, Energy.MAX)

func _on_energy_changed(current: float, maximum: float) -> void:
	var f := current / maximum
	var colour := Color(1.0, 0.25, 0.15).lerp(Color(1.0, 0.8, 0.2), clampf(f * 2.0, 0.0, 1.0)).lerp(Color(0.3, 1.0, 0.6), clampf(f * 2.0 - 1.0, 0.0, 1.0))
	_chest_material.emission = colour
	_chest_material.emission_energy_multiplier = 0.4 + 1.6 * f
	_camera_probe_shape = SphereShape3D.new()
	_camera_probe_shape.radius = CAMERA_PROBE_RADIUS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_rotate_camera(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	if event.is_action_pressed("pause"):
		if _find_hud():
			_hud.toggle_pause()
			get_viewport().set_input_as_handled()
	if in_combat:
		return               # the fight screen reads its own keys
	if event.is_action_pressed("inventory") and not shut_down:
		if _find_hud():
			_hud.toggle_inventory()
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("interact") and not shut_down and _focus != null:
		_focus.interact(self)
	if event.is_action_pressed("use_tool") and not shut_down:
		tool_rig.use()
	if event.is_action_pressed("cycle_tool") and not shut_down:
		tool_rig.cycle()
	if event.is_action_pressed("zoom_in"):
		target_zoom = clamp(target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if event.is_action_pressed("zoom_out"):
		target_zoom = clamp(target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if event.is_action_pressed("toggle_god_mode") and OS.is_debug_build():   # debug/editor only, never in a release build
		god_mode = not god_mode
		if not god_mode:
			_set_flying(false)
	if god_mode and event.is_action_pressed("jump") and not event.is_echo():
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_jump_press_time < DOUBLE_TAP_TIME:
			_set_flying(not flying)
			_last_jump_press_time = -1.0
		else:
			_last_jump_press_time = now

func _set_flying(enabled: bool) -> void:
	flying = enabled
	# Flying passes through everything, so the level can be inspected from anywhere.
	body_collision.disabled = enabled
	velocity.y = 0.0

func _rotate_camera(yaw_delta: float, pitch_delta: float) -> void:
	camera_rig.rotate_y(yaw_delta)
	camera_arm.rotate_x(pitch_delta)
	camera_arm.rotation.x = clamp(camera_arm.rotation.x, PITCH_MIN, PITCH_MAX)

func _update_camera_distance(delta: float) -> void:
	var pivot_pos: Vector3 = camera_arm.global_transform.origin
	var back_dir: Vector3 = camera_arm.global_transform.basis.z
	var zoom: float = target_zoom * (TINY_ZOOM if tiny else 1.0)
	var motion: Vector3 = back_dir * zoom
	_camera_probe_shape.radius = CAMERA_PROBE_RADIUS * size_scale

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_probe_shape
	query.transform = Transform3D(Basis(), pivot_pos)
	query.motion = motion
	query.exclude = [get_rid()]

	var space_state := get_world_3d().direct_space_state
	var result := space_state.cast_motion(query)
	var safe_fraction: float = result[0] if result.size() > 0 else 1.0

	var safe_distance: float = max(zoom * safe_fraction - CAMERA_COLLISION_MARGIN * size_scale, 0.5 * size_scale)

	var smoothing: float = clamp(CAMERA_ZOOM_SMOOTHING * delta, 0.0, 1.0)
	var new_distance: float = lerp(camera.position.z, safe_distance, smoothing)
	camera.position = Vector3(0, 0, new_distance)

func _find_hud() -> bool:
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	return _hud != null

## Nearest enabled Interactable inside the probe, or null.
func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for area in interact_probe.get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.enabled:
			continue
		var d := global_position.distance_squared_to(candidate.focus_position())
		if d < best_d:
			best_d = d
			best = candidate
	if best != _focus:
		_focus = best
		if _find_hud():
			_hud.set_prompt(_focus)

func _process(delta: float) -> void:
	# Headlights come on as the sun goes down (and off when the battery is dead).
	var dark: float = 1.0 - smoothstep(-0.05, 0.12, Clock.sun_direction().y)
	headlight.light_energy = 0.0 if shut_down else 3.0 * dark
	_lens_material.emission_energy_multiplier = 0.0 if shut_down else 1.2 + 2.5 * dark
	_hover_fx.visible = hovering
	# Tread wheels turn with the ground speed (the tread bodies are boxes; the wheels sell it).
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if ground_speed > 0.05:
		var forward_sign: float = signf(-visual.global_transform.basis.z.dot(Vector3(velocity.x, 0, velocity.z)))
		for wheel in wheels:
			(wheel as Node3D).rotate_x(-forward_sign * ground_speed / WHEEL_RADIUS * delta)

func _physics_process(delta: float) -> void:
	_update_focus()
	_update_size(delta)
	if shut_down or docked or in_combat:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		_update_camera_distance(delta)
		return
	if flying:
		var vertical: float = Input.get_action_strength("jump") - Input.get_action_strength("fly_down")
		velocity.y = vertical * FLY_VERTICAL_SPEED
	else:
		hovering = false
		if not is_on_floor():
			if Game.has_tool("hover") and Input.is_action_pressed("jump") and Energy.current > 0.0:
				_hover(delta)
			else:
				velocity.y -= GRAVITY * delta
		if Input.is_action_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY * (TINY_JUMP if tiny else 1.0)

	var look_vec := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_vec.length() > 0.0:
		_rotate_camera(-look_vec.x * LOOK_STICK_SPEED * delta, -look_vec.y * LOOK_STICK_SPEED * delta)

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var cam_forward := -camera_rig.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := camera_rig.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := (cam_forward * -input_2d.y) + (cam_right * input_2d.x)

	var speed: float = FLY_SPEED if flying else SPEED * (TINY_SPEED if tiny else 1.0)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	if move_dir.length() > 0.1:
		var target_angle := atan2(move_dir.x, move_dir.z) + PI
		# Global, not local: the Player root itself may be rotated in the level.
		visual.global_rotation.y = lerp_angle(visual.global_rotation.y, target_angle, TURN_SPEED * delta)

	move_and_slide()
	_update_camera_distance(delta)
	if not god_mode:
		Energy.drain((Energy.DRIVE_DRAIN if move_dir.length() > 0.1 else Energy.IDLE_DRAIN) * delta * (TINY_DRAIN if tiny else 1.0))

# --- the hover pack (Catalog tool "hover", from Pythia's lift fans and gyro) -----------
const HOVER_LIFT = 2.2          # m/s up while below the ceiling height
const HOVER_MAX_HEIGHT = 2.5    # metres above the ground it will climb to
const HOVER_ACCEL = 14.0
const HOVER_DRAIN = 3.0         # energy per second
var hovering := false
var _hover_fx: Node3D

func _hover(delta: float) -> void:
	hovering = true
	var target: float = HOVER_LIFT if height_above_ground() < HOVER_MAX_HEIGHT * size_scale else -0.2
	velocity.y = move_toward(velocity.y, target, HOVER_ACCEL * delta)
	Energy.drain(HOVER_DRAIN * delta)

func height_above_ground() -> float:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.1, 0), global_position + Vector3(0, -20, 0))
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return global_position.y - (hit["position"] as Vector3).y if not hit.is_empty() else 20.0

## Two little fans under the treads that glow while hovering.
func _build_hover_fx() -> void:
	_hover_fx = Node3D.new()
	_hover_fx.name = "HoverFans"
	_hover_fx.visible = false
	visual.add_child(_hover_fx)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.55, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.9, 1.0)
	glow.emission_energy_multiplier = 2.5
	var disc := CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.12
	disc.height = 0.02
	for x in [-0.25, 0.25]:
		var fan := MeshInstance3D.new()
		fan.mesh = disc
		fan.material_override = glow
		fan.position = Vector3(x, -0.02, 0)
		_hover_fx.add_child(fan)
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.9, 1.0)
	light.light_energy = 1.2
	light.omni_range = 2.0
	light.position = Vector3(0, -0.1, 0)
	_hover_fx.add_child(light)

# --- the eye irises ------------------------------------------------------------------
var iris_open := 1.0
var _iris_meshes: Array[MeshInstance3D] = []
var _iris_material: StandardMaterial3D

func _build_iris() -> void:
	_iris_material = StandardMaterial3D.new()
	_iris_material.albedo_color = Color(0.1, 0.1, 0.11)
	_iris_material.metallic = 0.8
	_iris_material.roughness = 0.35
	_iris_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for lens in lenses:
		var mi := MeshInstance3D.new()
		mi.name = "Iris"
		mi.material_override = _iris_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# in front of the lens, facing out of the head (-Z)
		mi.position = (lens as Node3D).position + Vector3(0, 0, -0.007)
		lens.get_parent().add_child(mi)
		_iris_meshes.append(mi)
	set_iris(iris_open)

## 0 = shut, 1 = open. Rebuilds the two small blade meshes (a cutscene animates it).
func set_iris(amount: float) -> void:
	iris_open = clampf(amount, 0.0, 1.0)
	var r: float = lerpf(IRIS_SHUT_R, IRIS_OPEN_R, iris_open)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in IRIS_BLADES:
		var a := TAU * i / IRIS_BLADES + iris_open * 0.5          # the blades turn a little as they open
		var radial := Vector3(cos(a), sin(a), 0)
		var tangent := Vector3(-sin(a), cos(a), 0)
		var centre := radial * r + Vector3(0, 0, -0.0004 * i)     # staggered: overlapping blades never flicker
		var s := verts.size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(centre + tangent * IRIS_BLADE_HALF_LENGTH * corner.x + radial * IRIS_BLADE_HALF_WIDTH * corner.y)
			normals.append(Vector3(0, 0, -1))
		indices.append_array(PackedInt32Array([s, s + 1, s + 2, s, s + 2, s + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for mi in _iris_meshes:
		mi.mesh = mesh

# --- the tiny curse ------------------------------------------------------------------
## Shrinks when Game says the curse is on; regrows when it's over, but only once
## there's room for the full-size body (never inside the wardrobe's mouse hole).
func _update_size(delta: float) -> void:
	var want := Game.is_tiny()
	if want == tiny:
		_cramped_told = false
		return
	if want:
		set_tiny(true)
		return
	_regrow_wait -= delta
	if _regrow_wait > 0.0:
		return
	_regrow_wait = 0.5
	if room_to_grow():
		set_tiny(false)
		Story.play("tiny_over")
	elif not _cramped_told:
		_cramped_told = true
		get_tree().call_group("hud", "show_notice", "The curse is over, but it's too cramped to grow here")

## Would the full-size body fit where the robot stands now?
func room_to_grow() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _normal_shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, _normal_shape.height * 0.5 + 0.05, 0))
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Instant for loading and tests; animated (a squash-and-pop) in play.
func set_tiny(on: bool, animate: bool = true) -> void:
	tiny = on
	size_scale = TINY_SCALE if on else 1.0
	body_collision.shape = _tiny_shape if on else _normal_shape
	body_collision.position.y = (_tiny_shape.height if on else _normal_shape.height) * 0.5
	camera_rig.position.y = CAMERA_HEIGHT * size_scale
	if _size_tween != null and _size_tween.is_valid():
		_size_tween.kill()
	if not animate or not is_inside_tree():
		visual.scale = Vector3.ONE * size_scale
		return
	_size_tween = create_tween()
	_size_tween.tween_property(visual, "scale", Vector3.ONE * size_scale * (0.8 if on else 1.15), 0.18)
	_size_tween.tween_property(visual, "scale", Vector3.ONE * size_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
