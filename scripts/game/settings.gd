extends Node

# Autoload "Settings": preferences that belong to whoever holds the controller,
# not to the robot's progress, so they live outside the save (user://settings.cfg)
# and can change any time from the main menu or the pause menu.
#
# Difficulty only changes fights. Easy is tuned so a six-year-old wins without
# trouble (PROJECT_VISION.md, "Who it's for"): slow timing ring, wide windows,
# a missed press still hits, a big "NOW!" cue, and the tutorial can't be lost.

signal difficulty_changed(level: String)

const PATH := "user://settings.cfg"
const LEVELS: Array[String] = ["easy", "medium", "hard"]
const DEFAULT_LEVEL := "easy"

## ring_speed: how fast the timing ring closes (1 = normal).
## good_window / perfect_window: seconds either side of the beat that count.
## miss_factor: damage share of an attack whose timing press missed.
## defend_window: seconds either side of the enemy's blow that count as a dodge.
## now_cue: flash a big "NOW!" when it's time to press.
## enemy_damage / enemy_health: multipliers on every enemy.
## tutorial_knockout: whether the tutorial fight can be lost at all.
const DIFFICULTY := {
	"easy": {"name": "Easy", "ring_speed": 0.5, "good_window": 0.40, "perfect_window": 0.15,
		"miss_factor": 1.0, "defend_window": 0.50, "now_cue": true,
		"enemy_damage": 0.5, "enemy_health": 0.7, "tutorial_knockout": false},
	"medium": {"name": "Medium", "ring_speed": 1.0, "good_window": 0.18, "perfect_window": 0.07,
		"miss_factor": 0.6, "defend_window": 0.20, "now_cue": false,
		"enemy_damage": 1.0, "enemy_health": 1.0, "tutorial_knockout": true},
	"hard": {"name": "Hard", "ring_speed": 1.3, "good_window": 0.10, "perfect_window": 0.04,
		"miss_factor": 0.4, "defend_window": 0.12, "now_cue": false,
		"enemy_damage": 1.4, "enemy_health": 1.3, "tutorial_knockout": true},
}

var difficulty: String = DEFAULT_LEVEL

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var saved := String(config.get_value("game", "difficulty", DEFAULT_LEVEL))
		if LEVELS.has(saved):
			difficulty = saved

## The fight tuning for the current difficulty (see DIFFICULTY).
func tuning() -> Dictionary:
	return DIFFICULTY[difficulty]

func difficulty_name() -> String:
	return String(DIFFICULTY[difficulty]["name"])

func set_difficulty(level: String) -> void:
	if not LEVELS.has(level) or level == difficulty:
		return
	difficulty = level
	var config := ConfigFile.new()
	config.load(PATH)           # keep any other settings already in the file
	config.set_value("game", "difficulty", difficulty)
	config.save(PATH)
	difficulty_changed.emit(difficulty)

## Easy -> Medium -> Hard -> Easy (the menus' one-button selector).
func next_difficulty() -> void:
	set_difficulty(LEVELS[(LEVELS.find(difficulty) + 1) % LEVELS.size()])
