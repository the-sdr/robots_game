extends Node

# The player robot's jump, animated (owner, 2026-09-29: keep the jump, make it
# read). Takeoff stays instant; this only moves the model:
#   takeoff  - the body stretches, the treads push down like pistons, arms fling out
#   in air   - stretched while rising, arms out for balance, treads tuck back up
#   landing  - a squash sized by the fall, a springy recovery with a little
#              overshoot, a nod, a dust puff and a small camera dip
# One damped spring drives the body's shape, so quick hops blend instead of
# snapping. Everything is a multiplier or scales with the player's size, so the
# tiny curse (0.04) works too. Nothing moves while flying, hovering, docked,
# shut down or fighting. The player composes nothing itself: this node writes
# Visual.scale (the player's visual_size times the squash) every physics frame.

const TAKEOFF_STRETCH := Vector3(0.92, 1.16, 0.92)
const RISE_STRETCH := 0.08           # extra height while still going up fast
const SPRING := 190.0                # stiffness of the body's shape spring
const DAMPING := 12.0                # below critical (2*sqrt(SPRING) = 27.6): a little overshoot
const TREAD_PUSH := 0.07             # metres the treads drop at takeoff (model space)
const ARM_OUT_AIR := 0.55            # radians, arms out while airborne
const ARM_OUT_TAKEOFF := 1.0
const HEAD_NOD := 0.9                # head pitch per unit of squash
const LAND_MIN_AIR := 0.12           # seconds airborne before a landing counts
const LAND_MIN_SPEED := 1.2          # m/s fall speed before a landing counts
const DUST_SPEED := 3.0              # m/s fall speed for a dust puff
const CAMERA_DIP := 0.07             # metres, at the hardest landing
# The head (and its headlight) tilts a little with the camera (owner, save_53:
# "not a full 90 or even 45 degrees, just a nice touch"): level at the usual
# look-down, up to ~17 degrees when looking up.
const LOOK_LEVEL := -0.35            # camera pitch (rad) at which the head is level
const LOOK_TILT := 0.6               # head tilt per radian of camera pitch past that
const LOOK_TILT_MIN := -0.12
const LOOK_TILT_MAX := 0.3

const PlayerScript := preload("res://scripts/player.gd")

@onready var player: PlayerScript = get_parent()
@onready var visual: Node3D = player.get_node("Visual")
@onready var treads: Array[Node3D] = [player.get_node("Visual/TreadLeft"), player.get_node("Visual/TreadRight")]
@onready var arm_left: Node3D = player.get_node("Visual/ArmLeft")
@onready var arm_right: Node3D = player.get_node("Visual/ArmRight")
@onready var head: Node3D = player.get_node("Visual/Head")
@onready var dust: CPUParticles3D = $Dust

var squash := Vector3.ONE            # the body's shape (read by tests)
var _squash_velocity := Vector3.ZERO
var _tread_rest: Array[float] = []
var _tread_offset := 0.0
var _arm_out := 0.0
var _head_rest := 0.0
var _camera_dip := 0.0
var _air_time := 0.0
var _fall_speed := 0.0
var _was_on_floor := true
var _jumped_this_frame := false
var _look_tilt := 0.0
## How many landings played (tests).
var landings := 0

func _ready() -> void:
	for t in treads:
		_tread_rest.append(t.position.y)
	_head_rest = head.rotation.x
	player.jumped.connect(_on_jumped)

func _on_jumped() -> void:
	_jumped_this_frame = true
	squash = TAKEOFF_STRETCH
	_squash_velocity = Vector3.ZERO
	_tread_offset = -TREAD_PUSH
	_arm_out = ARM_OUT_TAKEOFF

func _still() -> bool:
	return player.flying or player.hovering or player.docked or player.shut_down or player.in_combat

# Runs after the player's own _physics_process (children follow their parent),
# so is_on_floor() and velocity are this frame's.
func _physics_process(delta: float) -> void:
	var on_floor := player.is_on_floor()
	var still := _still()
	var target := Vector3.ONE
	if still:
		_air_time = 0.0
	elif not on_floor:
		_air_time += delta
		_fall_speed = maxf(-player.velocity.y, 0.0)
		var rising := clampf(player.velocity.y / player.JUMP_VELOCITY, 0.0, 1.0)
		target = Vector3(1.0 - RISE_STRETCH * rising * 0.5, 1.0 + RISE_STRETCH * rising, 1.0 - RISE_STRETCH * rising * 0.5)
	elif not _was_on_floor and not _jumped_this_frame:
		_land()
	if on_floor:
		_air_time = 0.0
	_was_on_floor = on_floor
	_jumped_this_frame = false

	# the shape spring
	var accel := (target - squash) * SPRING - _squash_velocity * DAMPING
	_squash_velocity += accel * delta
	squash += _squash_velocity * delta
	visual.scale = Vector3.ONE * player.visual_size * squash

	# treads, arms, head and camera ease back towards rest
	var airborne := not on_floor and not still
	var arm_target := ARM_OUT_AIR if airborne else 0.0
	_arm_out = lerpf(_arm_out, arm_target, clampf(10.0 * delta, 0.0, 1.0))
	arm_left.rotation.z = -_arm_out
	arm_right.rotation.z = _arm_out
	_tread_offset = lerpf(_tread_offset, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	for i in treads.size():
		treads[i].position.y = _tread_rest[i] + _tread_offset
	var pitch: float = player.camera_arm.rotation.x
	var tilt_target := clampf((pitch - LOOK_LEVEL) * LOOK_TILT, LOOK_TILT_MIN, LOOK_TILT_MAX)
	_look_tilt = lerpf(_look_tilt, 0.0 if still and player.shut_down else tilt_target, clampf(6.0 * delta, 0.0, 1.0))
	head.rotation.x = _head_rest - (1.0 - squash.y) * HEAD_NOD + _look_tilt
	_camera_dip = lerpf(_camera_dip, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	player.camera_rig.position.y = player.CAMERA_HEIGHT * player.size_scale - _camera_dip

func _land() -> void:
	if _air_time < LAND_MIN_AIR or _fall_speed < LAND_MIN_SPEED:
		return
	landings += 1
	var hard := clampf(_fall_speed / 10.0, 0.0, 1.0)           # 0 = a little hop, 1 = a long drop
	var amount := lerpf(0.12, 0.25, hard)
	squash = Vector3(1.0 + amount * 0.6, 1.0 - amount, 1.0 + amount * 0.6)
	_squash_velocity = Vector3.ZERO
	_arm_out = -0.15                                              # arms slap down past rest
	_camera_dip = CAMERA_DIP * hard * player.size_scale
	if _fall_speed >= DUST_SPEED:
		dust.scale = Vector3.ONE * player.size_scale
		dust.amount = int(lerpf(8.0, 16.0, hard))
		dust.restart()
