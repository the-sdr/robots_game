extends Node

# Autoload "Clock": the in-game day. One full day lasts DAY_SECONDS of real
# time. `time` runs 0..1 (0 = midnight, 0.25 = 06:00, 0.5 = noon, 0.75 = 18:00).
# The sun's position is derived from it here so lighting and solar chargers
# agree exactly. Sun rises in the east (+X), passes the south (+Z) at noon,
# sets in the west (-X); peak elevation SUN_MAX_ELEVATION.

signal day_started(day: int)

const DAY_SECONDS := 480.0          # 8 real minutes per day (owner, sprint 1)
const START_TIME := 0.34            # ~08:10, mid-morning wake-up
const SUN_MAX_ELEVATION := deg_to_rad(62.0)
const SUNRISE := 0.25
const SUNSET := 0.75

var time: float = START_TIME
var day: int = 1
var running := true

func reset() -> void:
	time = START_TIME
	day = 1

func _process(delta: float) -> void:
	if not running:
		return
	advance(delta / DAY_SECONDS)

func advance(fraction: float) -> void:
	time += fraction
	while time >= 1.0:
		time -= 1.0
		day += 1
		day_started.emit(day)

## Jump forward to the next morning (used after an energy shutdown).
func skip_to_morning(morning: float = 0.30) -> void:
	if time >= morning:
		day += 1
		day_started.emit(day)
	time = morning

func is_day() -> bool:
	return time > SUNRISE and time < SUNSET

## Sun elevation in radians; negative at night.
func sun_elevation() -> float:
	if is_day():
		return SUN_MAX_ELEVATION * sin((time - SUNRISE) / (SUNSET - SUNRISE) * PI)
	var night_length := 1.0 - (SUNSET - SUNRISE)
	var since_sunset: float = time - SUNSET if time >= SUNSET else time + 1.0 - SUNSET
	return -SUN_MAX_ELEVATION * sin(since_sunset / night_length * PI)

## Unit vector from the ground towards the sun (east at dawn, south+up at noon, west at dusk).
func sun_direction() -> Vector3:
	var elev := sun_elevation()
	var progress: float = (time - SUNRISE) / (SUNSET - SUNRISE)   # 0 dawn .. 1 dusk (outside at night)
	var azimuth: float = lerpf(0.0, PI, clampf(progress, 0.0, 1.0))  # 0 = east, PI = west
	var horizontal := Vector3(cos(azimuth), 0.0, sin(azimuth))       # east (+X) -> south (+Z) -> west (-X)
	return (horizontal * cos(elev) + Vector3.UP * sin(elev)).normalized()

## 0..1: how much sunlight reaches a flat, upward-facing solar panel.
func sunlight() -> float:
	return clampf(sin(sun_elevation()), 0.0, 1.0)

func time_text() -> String:
	var minutes := int(round(time * 24.0 * 60.0)) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
