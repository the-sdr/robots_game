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

@onready var visual: Node3D = $Visual
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_arm: Node3D = $CameraRig/CameraArm
@onready var camera: Camera3D = $CameraRig/CameraArm/Camera3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D

var target_zoom := ZOOM_DEFAULT
var _camera_probe_shape: SphereShape3D
var god_mode := false
var flying := false
var _last_jump_press_time := -1.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_probe_shape = SphereShape3D.new()
	_camera_probe_shape.radius = CAMERA_PROBE_RADIUS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_rotate_camera(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("zoom_in"):
		target_zoom = clamp(target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if event.is_action_pressed("zoom_out"):
		target_zoom = clamp(target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if event.is_action_pressed("toggle_god_mode"):
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
	var motion: Vector3 = back_dir * target_zoom

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_probe_shape
	query.transform = Transform3D(Basis(), pivot_pos)
	query.motion = motion
	query.exclude = [get_rid()]

	var space_state := get_world_3d().direct_space_state
	var result := space_state.cast_motion(query)
	var safe_fraction: float = result[0] if result.size() > 0 else 1.0

	var safe_distance: float = max(target_zoom * safe_fraction - CAMERA_COLLISION_MARGIN, 0.5)

	var smoothing: float = clamp(CAMERA_ZOOM_SMOOTHING * delta, 0.0, 1.0)
	var new_distance: float = lerp(camera.position.z, safe_distance, smoothing)
	camera.position = Vector3(0, 0, new_distance)

func _physics_process(delta: float) -> void:
	if flying:
		var vertical: float = Input.get_action_strength("jump") - Input.get_action_strength("fly_down")
		velocity.y = vertical * FLY_VERTICAL_SPEED
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		if Input.is_action_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

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

	var speed: float = FLY_SPEED if flying else SPEED
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	if move_dir.length() > 0.1:
		var target_angle := atan2(move_dir.x, move_dir.z) + PI
		# Global, not local: the Player root itself may be rotated in the level.
		visual.global_rotation.y = lerp_angle(visual.global_rotation.y, target_angle, TURN_SPEED * delta)

	move_and_slide()
	_update_camera_distance(delta)
