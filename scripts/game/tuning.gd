extends RefCounted

# The feel numbers for tools and the detector, in one table the code reads live
# (owner, 2026-09-30: "an F10 toggle to bring up tool timing which you can read
# off my playtest and bake into the code"; F9 for the detector). The playtester
# changes them with the F10 / F9 panels (scripts/ui/tuning_panel.gd), which log
# the values to playtest/tuning.md; Claude bakes the good ones into DEFAULTS.
# Values are not kept between runs: every session starts from DEFAULTS.
# A key with an "_easy" twin uses the twin on Easy.

const DEFAULTS := {
	# cutter ("hold_heat"); heat + green zone from tune_6 (Surface, Medium fights),
	# strength / overheat / cooling from tune_10 (laptop)
	"cutter_heat_seconds": 0.9, "cutter_heat_seconds_easy": 2.6,
	"cutter_clean_from": 0.6, "cutter_clean_from_easy": 0.55,
	"cutter_clean_to": 0.72, "cutter_clean_to_easy": 0.92,
	"cutter_rate": 1.6, "cutter_clean_bonus": 1.4,
	"cutter_overheat_seconds": 1.9, "cutter_cool_rate": 0.9,
	# smasher ("rapid")
	"smasher_combo_window": 0.55, "smasher_combo_bonus": 0.2, "smasher_cooldown": 0.14,
	# laser ("trace")
	"laser_trace_seconds": 0.3, "laser_trace_seconds_easy": 0.18, "laser_beam_rate": 1.0,
	# detector
	"detector_range": 60.0, "detector_sweep_time": 1.2, "detector_spot_glow": 4.0,
	"detector_fuzz_per_metre": 0.3, "detector_max_fuzz": 12.0, "detector_exact_within": 2.5,
	"detector_near_strength": 1.0, "detector_far_strength": 0.25, "detector_strength_curve": 0.7,
	"detector_pillar_beyond": 12.0, "detector_pillar_height": 7.0, "detector_overlay": 1.0,
}

## The sliders: key (without "_easy"), label, min, max, step. "tools" = F10, "detector" = F9.
const PANELS := {
	"tools": [
		["cutter_heat_seconds", "Cutter: seconds to full heat", 0.6, 5.0, 0.1],
		["cutter_clean_from", "Cutter: green zone starts (0-1)", 0.2, 0.95, 0.01],
		["cutter_clean_to", "Cutter: green zone ends (0-1)", 0.3, 0.99, 0.01],
		["cutter_rate", "Cutter: cut strength", 0.3, 4.0, 0.1],
		["cutter_clean_bonus", "Cutter: clean-cut bonus", 0.0, 4.0, 0.1],
		["cutter_overheat_seconds", "Cutter: overheat lock (s)", 0.5, 5.0, 0.1],
		["cutter_cool_rate", "Cutter: cooling per second", 0.2, 3.0, 0.1],
		["smasher_combo_window", "Smasher: combo window (s)", 0.2, 1.2, 0.05],
		["smasher_combo_bonus", "Smasher: bonus per combo step", 0.0, 0.6, 0.05],
		["smasher_cooldown", "Smasher: time between hits (s)", 0.05, 0.6, 0.01],
		["laser_trace_seconds", "Laser: beam time per segment (s)", 0.05, 1.0, 0.01],
		["laser_beam_rate", "Laser: damage on small things", 0.2, 3.0, 0.1],
	],
	"detector": [
		["detector_range", "Range (m)", 20.0, 120.0, 5.0],
		["detector_sweep_time", "Sweep out time (s)", 0.4, 3.0, 0.1],
		["detector_spot_glow", "Spots glow for (s)", 1.0, 10.0, 0.5],
		["detector_fuzz_per_metre", "Far vagueness (per metre)", 0.0, 0.8, 0.02],
		["detector_max_fuzz", "Largest vagueness (m)", 2.0, 25.0, 1.0],
		["detector_exact_within", "Exact within (m)", 0.5, 8.0, 0.5],
		["detector_near_strength", "Brightness near", 0.2, 2.0, 0.05],
		["detector_far_strength", "Brightness far", 0.0, 1.0, 0.05],
		["detector_strength_curve", "Near-to-far curve", 0.2, 2.0, 0.05],
		["detector_pillar_beyond", "Light pillar beyond (m)", 3.0, 40.0, 1.0],
		["detector_pillar_height", "Light pillar height (m)", 1.0, 15.0, 0.5],
		["detector_overlay", "Robot view strength", 0.0, 1.5, 0.05],
	],
}

static var values := {}

static func _key(key: String) -> String:
	var easy := key + "_easy"
	return easy if DEFAULTS.has(easy) and Settings.difficulty == "easy" else key

## The live value of a tuning key (its Easy twin on Easy).
static func v(key: String) -> float:
	var k := _key(key)
	return float(values.get(k, DEFAULTS[k]))

static func set_value(key: String, value: float) -> void:
	values[_key(key)] = value

static func is_tuned(key: String) -> bool:
	var k := _key(key)
	return values.has(k) and not is_equal_approx(float(values[k]), float(DEFAULTS[k]))

## "key=value ..." for every key on a panel (for the tuning log and F3).
static func summary(panel: String, only_tuned: bool = false) -> String:
	var parts: Array[String] = []
	for row in PANELS[panel]:
		var key: String = row[0]
		if only_tuned and not is_tuned(key):
			continue
		parts.append("%s=%s%s" % [_key(key), snappedf(v(key), 0.001), "*" if is_tuned(key) else ""])
	return " ".join(parts)

static func reset() -> void:
	values.clear()
