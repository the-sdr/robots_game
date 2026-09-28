extends Node

# Autoload "Energy": the robot's battery. Drains while idle, more while
# driving, and per tool use. Chargers refill it (see charger.gd). At zero the
# robot shuts down and reboots at the last charger next morning (world.gd).

signal changed(current: float, maximum: float)
signal depleted

const MAX := 100.0
const IDLE_DRAIN := 0.08      # per second, just being switched on
const DRIVE_DRAIN := 0.9      # per second while driving: a full battery is ~110 s, ~330 m at 3 m/s (door to hill crest is 111 m)
const LOW_WARNING := 20.0

var current: float = MAX
var _warned_low := false
var _was_empty := false

func reset() -> void:
	current = MAX
	_warned_low = false
	_was_empty = false
	changed.emit(current, MAX)

func fraction() -> float:
	return current / MAX

func is_empty() -> bool:
	return current <= 0.0

## Takes energy; returns false (and takes nothing) if there isn't enough.
func spend(amount: float) -> bool:
	if current < amount:
		return false
	_apply(current - amount)
	return true

func drain(amount: float) -> void:
	_apply(current - amount)

func add(amount: float) -> float:
	var before := current
	_apply(current + amount)
	return current - before

func _apply(value: float) -> void:
	current = clampf(value, 0.0, MAX)
	changed.emit(current, MAX)
	if current <= LOW_WARNING and not _warned_low:
		_warned_low = true
		get_tree().call_group("hud", "show_notice", "Battery low")
	if current > LOW_WARNING:
		_warned_low = false
	if current <= 0.0 and not _was_empty:
		_was_empty = true
		depleted.emit()
	if current > 0.0:
		_was_empty = false
