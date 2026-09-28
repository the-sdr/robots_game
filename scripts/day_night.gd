extends Node

# Drives the sun, sky, fog and ambient light from Clock. One directional light
# plays both sun and moon (a second shadowed light would cost too much on an
# integrated GPU). Colours are keyed on the sun's height: warm and low at dawn
# and dusk, blue-black at night.

@export var sun_path: NodePath = ^"../DirectionalLight3D"
@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var clouds_path: NodePath = ^"../Clouds"

const DAY_SKY_TOP := Color(0.3, 0.55, 0.85)
const DAY_HORIZON := Color(0.75, 0.85, 0.92)
const DUSK_HORIZON := Color(0.98, 0.58, 0.36)
const DUSK_SKY_TOP := Color(0.22, 0.3, 0.55)
const NIGHT_SKY_TOP := Color(0.015, 0.025, 0.06)
const NIGHT_HORIZON := Color(0.05, 0.07, 0.13)
const DAY_GROUND := Color(0.3, 0.55, 0.3)
const NIGHT_GROUND := Color(0.03, 0.04, 0.06)
const DAY_AMBIENT := Color(0.55, 0.62, 0.7)
const NIGHT_AMBIENT := Color(0.07, 0.09, 0.15)
const SUN_COLOUR := Color(1.0, 0.95, 0.85)
const DAWN_COLOUR := Color(1.0, 0.62, 0.38)
const MOON_COLOUR := Color(0.55, 0.65, 0.95)
const SUN_ENERGY := 1.2
const MOON_ENERGY := 0.16
const INTERIOR_AMBIENT := Color(0.07, 0.075, 0.085)

@onready var sun: DirectionalLight3D = get_node(sun_path)
@onready var environment: Environment = (get_node(environment_path) as WorldEnvironment).environment
@onready var clouds: Node = get_node_or_null(clouds_path)
@onready var sky: ProceduralSkyMaterial = environment.sky.sky_material

## Underground (the Relay Vault): no sun or sky light, only the rooms' own lamps.
var interior := false

func set_interior(on: bool) -> void:
	interior = on
	update()

func _ready() -> void:
	add_to_group("day_night")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	update()

func _process(_delta: float) -> void:
	update()

## 0 = deep night, 1 = full day. Dawn/dusk sit in between.
func daylight() -> float:
	return smoothstep(-0.12, 0.28, sin(Clock.sun_elevation()))

## 1 at the horizon, 0 once the sun is well up or well down.
func horizon_glow() -> float:
	var s := sin(Clock.sun_elevation())
	return 1.0 - smoothstep(0.0, 0.32, absf(s)) if s > -0.15 else 0.0

func update() -> void:
	var sun_dir := Clock.sun_direction()
	var d := daylight()
	var glow := horizon_glow()
	var above := sun_dir.y > 0.0

	# Light: the sun by day, the moon (opposite side, dim and blue) by night.
	if above:
		var toward := -sun_dir
		sun.look_at_from_position(Vector3.ZERO, toward, Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = DAWN_COLOUR.lerp(SUN_COLOUR, smoothstep(0.0, 0.4, sun_dir.y))
		sun.light_energy = SUN_ENERGY * smoothstep(0.0, 0.18, sun_dir.y)
	else:
		var moon_dir := Vector3(-sun_dir.x, maxf(0.35, -sun_dir.y * 0.8), -sun_dir.z).normalized()
		sun.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)
		sun.light_color = MOON_COLOUR
		sun.light_energy = MOON_ENERGY * smoothstep(0.0, 0.1, -sun_dir.y)

	# Sky and fog.
	var top := NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, d).lerp(DUSK_SKY_TOP, glow * 0.6)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, d).lerp(DUSK_HORIZON, glow * 0.85)
	sky.sky_top_color = top
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon
	sky.ground_bottom_color = NIGHT_GROUND.lerp(DAY_GROUND, d)
	environment.fog_light_color = horizon
	environment.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, d).lerp(DUSK_HORIZON * 0.6, glow * 0.4)

	if interior:
		sun.light_energy = 0.0
		environment.ambient_light_color = INTERIOR_AMBIENT
		environment.fog_light_color = INTERIOR_AMBIENT
	if clouds != null and clouds.has_method("set_brightness"):
		clouds.set_brightness(Color(0.22, 0.25, 0.38).lerp(Color(1.0, 0.99, 0.96), d).lerp(DUSK_HORIZON, glow * 0.7))
