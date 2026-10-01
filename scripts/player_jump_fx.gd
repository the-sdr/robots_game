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
#
# Silly mode (owner, 2026-10-02: "goat simulator / wobbly life") adds a wobble
# on top, still visual only - the body, velocity and collision are untouched:
#   a looser, bouncier shape spring and bigger landing squashes; the body leans
#   and rolls on springs kicked by speeding up, braking and turning (it wobbles
#   when it stops); the head bobbles and the arms flop while driving; bumping a
#   wall at speed recoils; a big fall cartwheels and lands the turn. Serious
#   keeps the tidy original. Written here, not in a second
#   script, because this node already owns the model's shape.

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

## The shape spring and landing per mode; `wobble` turns on the Silly extras.
const PROFILES := {
	"serious": {"spring": SPRING, "damping": DAMPING, "land": 1.0, "wobble": false},
	"silly": {"spring": 110.0, "damping": 5.5, "land": 1.7, "wobble": true},
}
const LEAN_SPRING := 70.0            # the body's lean and roll (Silly)
const LEAN_DAMPING := 4.0            # well under critical (16.7): it rocks a few times
const LEAN_KICK := 0.9               # rad/s of lean per m/s of speed change
const LEAN_MAX := 0.5
const HEAD_SPRING := 45.0
const HEAD_DAMPING := 2.5
const BUMP_SPEED := 1.8              # m/s lost against a wall that counts as a bump
const TUMBLE_FALL := 6.5             # m/s falling before a big fall tumbles
const TUMBLE_RATE := 9.0             # rad/s
const TUMBLE_PIVOT := 0.6            # metres up the body: it cartwheels about its middle, not its treads

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
## Silly's wobble (tests read these): lean = (pitch, roll), tumble = cartwheel angle.
var wobble := false
var lean := Vector2.ZERO
var tumble := 0.0
var bumps := 0
var _profile: Dictionary = PROFILES["serious"]
var _lean_velocity := Vector2.ZERO
var _head_roll := 0.0
var _head_roll_velocity := 0.0
var _last_velocity := Vector3.ZERO
var _bump_cooldown := 0.0
var _landing_flip := false
var _time := 0.0

signal bumped(strength: float)       # Silly sounds listen
signal landed(hard: float)

func _ready() -> void:
	_profile = PROFILES[Game.mode]
	wobble = bool(_profile["wobble"])
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
	var accel := (target - squash) * float(_profile["spring"]) - _squash_velocity * float(_profile["damping"])
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
	if wobble:
		_wobble(delta, on_floor, still)

## Silly: lean, roll, bobble, flop, bump and tumble (see the top of the file).
func _wobble(delta: float, on_floor: bool, still: bool) -> void:
	_time += delta
	var velocity: Vector3 = player.velocity
	if player.in_combat:
		_last_velocity = velocity          # the fight animates the model itself: start it upright
		if lean != Vector2.ZERO or tumble != 0.0:
			lean = Vector2.ZERO
			_lean_velocity = Vector2.ZERO
			tumble = 0.0
			_landing_flip = false
			visual.rotation.x = 0.0
			visual.rotation.z = 0.0
			visual.position = Vector3.ZERO
		return
	var basis := visual.global_transform.basis.orthonormalized()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var change := basis.transposed() * (flat - Vector3(_last_velocity.x, 0.0, _last_velocity.z))
	# a wall at speed: most of the speed gone in one frame, and touching a wall
	_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
	var lost := Vector2(_last_velocity.x, _last_velocity.z).length() - Vector2(flat.x, flat.z).length()
	if player.is_on_wall() and lost > BUMP_SPEED and _bump_cooldown == 0.0 and not still:
		_bump(clampf(lost / player.SPEED, 0.0, 1.5))
	_last_velocity = velocity
	if not still:
		# inertia: speeding up forward tips the top back (+x), braking tips it
		# forward; turning (sideways change) rolls it outwards
		_lean_velocity += Vector2(-change.z, change.x) * LEAN_KICK
		_head_roll_velocity += change.x * LEAN_KICK * 1.5
	var lean_accel := -lean * LEAN_SPRING - _lean_velocity * LEAN_DAMPING
	_lean_velocity += lean_accel * delta
	lean += _lean_velocity * delta
	lean = lean.clamp(Vector2(-LEAN_MAX, -LEAN_MAX), Vector2(LEAN_MAX, LEAN_MAX))
	var head_accel := -_head_roll * HEAD_SPRING - _head_roll_velocity * HEAD_DAMPING
	_head_roll_velocity += head_accel * delta
	_head_roll += _head_roll_velocity * delta
	# a big fall: cartwheel, then land the turn (to the nearest whole one)
	if not on_floor and not still and maxf(-velocity.y, 0.0) > TUMBLE_FALL:
		tumble += TUMBLE_RATE * delta
		_landing_flip = true
	elif _landing_flip:
		var whole := roundf(tumble / TAU) * TAU
		tumble = lerpf(tumble, whole, clampf(14.0 * delta, 0.0, 1.0))
		if absf(tumble - whole) < 0.01:
			tumble = 0.0
			_landing_flip = false
	# driving: a little bobble in the head, the arms flop to the rhythm of the treads
	var pace := clampf(flat.length() / player.SPEED, 0.0, 1.0) if on_floor and not still else 0.0
	visual.rotation.x = lean.x
	visual.rotation.z = lean.y + tumble
	# keep the cartwheel's middle in place: position = c - Rz(tumble) * c, c = the pivot
	var h := TUMBLE_PIVOT * float(player.visual_size)
	visual.position = Vector3(h * sin(tumble), h * (1.0 - cos(tumble)), 0.0).rotated(Vector3.UP, visual.rotation.y)
	head.rotation.z = _head_roll + sin(_time * 13.0) * 0.07 * pace
	arm_left.rotation.z += -absf(lean.y) * 0.8 - sin(_time * 9.0) * 0.18 * pace
	arm_right.rotation.z += absf(lean.y) * 0.8 + sin(_time * 9.0 + 1.3) * 0.18 * pace

func _bump(strength: float) -> void:
	bumps += 1
	_bump_cooldown = 0.4
	_lean_velocity.x += 3.5 * strength        # bonks back off the wall
	_head_roll_velocity += (4.0 if bumps % 2 == 0 else -4.0) * strength
	squash = Vector3(1.0 + 0.15 * strength, 1.0 - 0.12 * strength, 1.0 - 0.1 * strength)
	_squash_velocity = Vector3.ZERO
	bumped.emit(strength)

func _land() -> void:
	if _air_time < LAND_MIN_AIR or _fall_speed < LAND_MIN_SPEED:
		return
	landings += 1
	var hard := clampf(_fall_speed / 10.0, 0.0, 1.0)           # 0 = a little hop, 1 = a long drop
	var amount := lerpf(0.12, 0.25, hard) * float(_profile["land"])
	squash = Vector3(1.0 + amount * 0.6, 1.0 - amount, 1.0 + amount * 0.6)
	_squash_velocity = Vector3.ZERO
	_arm_out = -0.15                                              # arms slap down past rest
	_camera_dip = CAMERA_DIP * hard * player.size_scale
	landed.emit(hard)
	if _fall_speed >= DUST_SPEED:
		dust.scale = Vector3.ONE * player.size_scale
		dust.amount = int(lerpf(8.0, 16.0, hard))
		dust.restart()
