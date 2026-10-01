extends Node

# Autoload "Settings": preferences that belong to whoever holds the controller,
# not to the robot's progress, so they live outside the save (user://settings.cfg)
# and can change any time from the main menu or the pause menu.
#
# Difficulty changes fights and battery life. Easy is tuned so a six-year-old
# wins without trouble (PROJECT_VISION.md, "Who it's for"): slow timing ring,
# wide windows, a missed press still hits, a big "NOW!" cue, the tutorial
# can't be lost, and a full battery lasts 15 minutes of driving.
#
# The mode (Silly / Serious, see Game.MODES) last picked on the main menu is
# remembered here, and so is a difficulty per mode: a child's Silly Easy and a
# parent's Serious Hard don't overwrite each other (owner, 2026-10-02: mode and
# difficulty are separate settings). Settings loads after Game and hands it the mode.

signal difficulty_changed(level: String)
signal mode_changed(mode: String)

const PATH := "user://settings.cfg"
const LEVELS: Array[String] = ["easy", "medium", "hard"]
const DEFAULT_LEVEL := "easy"
const DEFAULT_MODE := "silly"

## ring_speed: how fast the timing ring closes (1 = normal).
## good_window / perfect_window: seconds either side of the beat that count.
## miss_factor: damage share of an attack whose timing press missed.
## defend_window: seconds either side of the enemy's blow that count as a dodge.
## now_cue: flash a big "NOW!" when it's time to press.
## enemy_damage / enemy_health: multipliers on every enemy.
## tutorial_knockout: whether the tutorial fight can be lost at all.
## battery_minutes: how long a full battery lasts while driving (owner's
## playtest, 2026-09-29: Easy 15, Medium 10, Hard 5; it was under 2 minutes).
const DIFFICULTY := {
	"easy": {"name": "Easy", "ring_speed": 0.5, "good_window": 0.40, "perfect_window": 0.15,
		"miss_factor": 1.0, "defend_window": 0.50, "now_cue": true,
		"enemy_damage": 0.5, "enemy_health": 0.7, "tutorial_knockout": false, "battery_minutes": 15.0},
	"medium": {"name": "Medium", "ring_speed": 1.0, "good_window": 0.18, "perfect_window": 0.07,
		"miss_factor": 0.6, "defend_window": 0.20, "now_cue": false,
		"enemy_damage": 1.0, "enemy_health": 1.0, "tutorial_knockout": true, "battery_minutes": 10.0},
	"hard": {"name": "Hard", "ring_speed": 1.3, "good_window": 0.10, "perfect_window": 0.04,
		"miss_factor": 0.4, "defend_window": 0.12, "now_cue": false,
		"enemy_damage": 1.4, "enemy_health": 1.3, "tutorial_knockout": true, "battery_minutes": 5.0},
}
const MODE_NAMES := {"silly": "Silly", "serious": "Serious"}

var difficulty: String = DEFAULT_LEVEL
var mode: String = DEFAULT_MODE
## Tests write to their own file so a run never changes the player's settings.
var path := PATH

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var saved := String(config.get_value("game", "mode", DEFAULT_MODE))
		if Game.MODES.has(saved):
			mode = saved
	difficulty = _stored_difficulty(mode)
	Game.set_mode(mode)

## The fight tuning for the current difficulty (see DIFFICULTY).
func tuning() -> Dictionary:
	return DIFFICULTY[difficulty]

func difficulty_name() -> String:
	return String(DIFFICULTY[difficulty]["name"])

func mode_name(for_mode: String = "") -> String:
	return String(MODE_NAMES.get(for_mode if for_mode != "" else mode, "?"))

func set_difficulty(level: String) -> void:
	if not LEVELS.has(level) or level == difficulty:
		return
	difficulty = level
	_store("difficulty_" + mode, difficulty)
	difficulty_changed.emit(difficulty)

## Easy -> Medium -> Hard -> Easy (the menus' one-button selector).
func next_difficulty() -> void:
	set_difficulty(LEVELS[(LEVELS.find(difficulty) + 1) % LEVELS.size()])

## Picks the game (main menu): remembered, and its own difficulty comes back.
func set_mode(new_mode: String) -> void:
	if not Game.MODES.has(new_mode):
		return
	var changed := new_mode != mode
	mode = new_mode
	Game.set_mode(mode)
	_store("mode", mode)
	var level := _stored_difficulty(mode)
	if level != difficulty:
		difficulty = level
		difficulty_changed.emit(difficulty)
	if changed:
		mode_changed.emit(mode)

## A mode's difficulty; before the split there was one for both.
func _stored_difficulty(for_mode: String) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return DEFAULT_LEVEL
	var level := String(config.get_value("game", "difficulty_" + for_mode, config.get_value("game", "difficulty", DEFAULT_LEVEL)))
	return level if LEVELS.has(level) else DEFAULT_LEVEL

func _store(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(path)           # keep any other settings already in the file
	config.set_value("game", key, value)
	config.save(path)
