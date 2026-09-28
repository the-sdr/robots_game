extends Node

# Autoload "Catalog": every item, tool and recipe in the game, as plain data.
# Add a tool here and it exists: the framework (tool_rig.gd, breakable.gd)
# reads "effect" to know what it does. Dozens are expected eventually
# (smash, cut, hover/fly, lasers, matter generation...).
#
# Tool fields:  name, effect ("smash" | "cut" | ... matched by Breakable),
#   power (damage per use), energy (battery per use), range (m),
#   cooldown (s), colour (for the placeholder mesh and its flash).
# Item fields:  name, description, colour (pickup glow).
# Recipe fields: name, needs {item: count}, tool (id built) or gives {item: count},
#   optional requires_flag (story gate), description.

const ITEMS := {
	"servo_motor": {"name": "Servo motor", "description": "Still turns. Barely.", "colour": Color(1.0, 0.6, 0.15)},
	"optic_lens": {"name": "Optic lens", "description": "Scratched, but it focuses.", "colour": Color(0.3, 0.8, 1.0)},
	"power_cell": {"name": "Power cell", "description": "Holds a charge. Someone left it full.", "colour": Color(0.5, 1.0, 0.4)},
	"circuit_board": {"name": "Circuit board", "description": "Green, with a burnt corner.", "colour": Color(0.9, 0.4, 1.0)},
	"gear_train": {"name": "Gear train", "description": "Teeth intact. Rare.", "colour": Color(0.95, 0.85, 0.3)},
	"antenna_coil": {"name": "Antenna coil", "description": "Listens to nothing now.", "colour": Color(1.0, 0.45, 0.55)},
	"hammer_head": {"name": "Hammer head", "description": "Heavy. Dented on one side from a job it finished.", "colour": Color(0.75, 0.75, 0.8)},
	"actuator_arm": {"name": "Actuator arm", "description": "A piston that still pushes when asked.", "colour": Color(0.9, 0.55, 0.25)},
	"scrap_metal": {"name": "Scrap metal", "description": "Bent plates and brackets.", "colour": Color(0.6, 0.62, 0.65)},
	"blade_strip": {"name": "Blade strip", "description": "An edge that was part of something bigger.", "colour": Color(0.8, 0.9, 1.0)},
	"gate_key": {"name": "Gate key", "description": "Brass, heavy, a number stamped on it: 7.", "colour": Color(0.95, 0.8, 0.3)},
	"relay_card": {"name": "Relay access card", "description": "A card with a chip. The relay tower's door reads these.", "colour": Color(0.4, 0.9, 1.0)},
	"solar_cell": {"name": "Solar cell", "description": "A square of dark glass that drinks sunlight. Two would make a charger's panel bigger.", "colour": Color(0.35, 0.55, 1.0)},
	"sun_tracker": {"name": "Sun tracker", "description": "A little motor with an eye for the sun. On a charger, it turns the panel to follow the sun all day.", "colour": Color(1.0, 0.8, 0.3)},
	"capacitor": {"name": "Capacitor bank", "description": "Stores a lot of charge and lets it go all at once. The hill sentry won't need it any more.", "colour": Color(1.0, 0.9, 0.3)},
	"lift_fan": {"name": "Lift fan", "description": "A fan in a ring. Point it down and it pushes you up.", "colour": Color(0.55, 0.9, 1.0)},
	"gyro": {"name": "Gyro", "description": "Spinning rings that always know which way is up.", "colour": Color(0.9, 0.7, 1.0)},
	"printer_core": {"name": "Printer core", "description": "The heart of a matter printer. It hums when you hold it.", "colour": Color(0.3, 1.0, 0.85)},
	"nozzle": {"name": "Print nozzle", "description": "A hot little cone that lays down metal a hair at a time.", "colour": Color(1.0, 0.5, 0.2)},
}

#
# Fight moves (turn-based combat, scripts/combat/): every tool has three, picked
# with its loadout key alone ("") or with forward ("forward", W) / back ("back", S)
# held. Move fields: name, kind ("attack" | "guard" | "evade" | "stun" | "repair"),
# power (damage per hit), hits (timing presses, one per hit), energy (battery),
# guard (share of the next enemy blow that still lands), counter (damage back
# when that blow is dodged or blocked), heal, hint (one line for the fight screen).
const TOOLS := {
	"smasher": {"name": "Smasher", "effect": "smash", "power": 34.0, "energy": 3.0, "range": 2.2,
		"cooldown": 0.55, "colour": Color(0.85, 0.5, 0.2),
		"description": "A hammer head on an actuator. Breaks doors, boards, rotten wood.",
		"moves": {
			"": {"name": "Smash", "kind": "attack", "power": 14.0, "hits": 1, "energy": 3.0, "hint": "One big hit"},
			"forward": {"name": "Leaping slam", "kind": "attack", "power": 11.0, "hits": 2, "energy": 6.0, "hint": "Jump in, hit twice"},
			"back": {"name": "Brace", "kind": "guard", "guard": 0.35, "counter": 8.0, "energy": 2.0, "hint": "Block most of the next blow, bonk back"},
		}},
	"cutter": {"name": "Cutter", "effect": "cut", "power": 26.0, "energy": 2.0, "range": 2.0,
		"cooldown": 0.4, "colour": Color(0.4, 0.9, 1.0),
		"description": "A spinning blade strip. Clears brambles and thin trunks.",
		"moves": {
			"": {"name": "Slice", "kind": "attack", "power": 7.0, "hits": 2, "energy": 2.0, "hint": "Two quick cuts"},
			"forward": {"name": "Whirl", "kind": "attack", "power": 6.0, "hits": 3, "energy": 4.0, "hint": "Spin: three cuts"},
			"back": {"name": "Parry", "kind": "guard", "guard": 0.5, "counter": 12.0, "energy": 2.0, "hint": "Catch the next blow on the blade"},
		}},
	"laser": {"name": "Laser", "effect": "burn", "power": 30.0, "energy": 4.0, "range": 14.0,
		"cooldown": 0.8, "colour": Color(1.0, 0.35, 0.3), "ranged": true,
		"description": "A lens, a board and a coil: a beam that burns vines and ropes from far away.",
		"moves": {
			"": {"name": "Zap", "kind": "attack", "power": 12.0, "hits": 1, "energy": 4.0, "hint": "A quick beam"},
			"forward": {"name": "Charged beam", "kind": "attack", "power": 24.0, "hits": 1, "energy": 8.0, "hint": "Charge up, one huge beam"},
			"back": {"name": "Dazzle", "kind": "stun", "energy": 3.0, "hint": "Flash its eye: it misses its next turn"},
		}},
}

## Used when the fight kit is empty (it can't be, once the smasher exists, but never soft-lock a fight).
const TREAD_MOVES := {
	"": {"name": "Ram", "kind": "attack", "power": 6.0, "hits": 1, "energy": 0.0, "hint": "Drive into it"},
	"forward": {"name": "Ram", "kind": "attack", "power": 6.0, "hits": 1, "energy": 0.0, "hint": "Drive into it"},
	"back": {"name": "Duck", "kind": "guard", "guard": 0.6, "counter": 0.0, "energy": 0.0, "hint": "Keep your head down"},
}

## The robot's integrity in a fight (separate from the battery; refilled every fight).
const PLAYER_HEALTH := 50.0

## Enemies. Attacks come round in order; wind_up is how long the timing ring
## takes to close at normal speed (Settings scales it); hits > 1 = one dodge per hit.
const ENEMIES := {
	"hill_sentry": {"name": "Hill Sentry", "health": 60.0, "tutorial": true, "reward": {"capacitor": 1},
		"attacks": [
			{"name": "Clamp", "power": 10.0, "hits": 1, "wind_up": 1.3},
			{"name": "Double swipe", "power": 7.0, "hits": 2, "wind_up": 1.1},
			{"name": "Clamp", "power": 10.0, "hits": 1, "wind_up": 1.3},
			{"name": "Charge", "power": 16.0, "hits": 1, "wind_up": 1.8},
		]},
}

const RECIPES := {
	"smasher": {"name": "Smasher", "tool": "smasher",
		"needs": {"hammer_head": 1, "actuator_arm": 1},
		"description": "Attach a hammer head to an actuator arm."},
	"cutter": {"name": "Cutter", "tool": "cutter",
		"needs": {"servo_motor": 1, "gear_train": 1, "blade_strip": 1, "power_cell": 1},
		"description": "A servo spins a blade strip. Needs a cell of its own."},
	"laser": {"name": "Laser", "tool": "laser",
		"needs": {"optic_lens": 1, "circuit_board": 1, "antenna_coil": 1},
		"description": "The lens focuses, the board fires, the coil charges. Burns from far away."},
	# charger upgrades: fitted to the charger the robot is docked at ("upgrade" = charger.gd kind)
	"panel_extension": {"name": "Panel extension (charger)", "upgrade": "panel",
		"needs": {"solar_cell": 2},
		"description": "Two more solar cells on the charger you're docked at: it fills half again as fast."},
	"fit_sun_tracker": {"name": "Sun tracker (charger)", "upgrade": "tracker",
		"needs": {"sun_tracker": 1},
		"description": "The panel of the charger you're docked at turns to follow the sun: full light all day."},
	"battery_bank": {"name": "Battery bank (charger)", "upgrade": "battery",
		"needs": {"capacitor": 1},
		"description": "The charger you're docked at holds 60 more."},
	"blade_strip": {"name": "Blade strip", "gives": {"blade_strip": 1},
		"needs": {"scrap_metal": 2},
		"description": "Fold and grind scrap into an edge."},
}

func item_name(id: String) -> String:
	return String(ITEMS.get(id, {}).get("name", id))

func tool_name(id: String) -> String:
	return String(TOOLS.get(id, {}).get("name", id))

## A tool's fight move for "", "forward" or "back" (the treads' moves for "").
func move(tool_id: String, direction: String) -> Dictionary:
	var moves: Dictionary = TOOLS.get(tool_id, {}).get("moves", TREAD_MOVES)
	return moves.get(direction, moves[""])
