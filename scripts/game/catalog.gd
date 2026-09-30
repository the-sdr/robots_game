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
}

const TOOLS := {
	"smasher": {"name": "Smasher", "effect": "smash", "power": 34.0, "energy": 3.0, "range": 2.2,
		"cooldown": 0.55, "colour": Color(0.85, 0.5, 0.2),
		"description": "A hammer head on an actuator. Breaks doors, boards, rotten wood."},
	"cutter": {"name": "Cutter", "effect": "cut", "power": 26.0, "energy": 2.0, "range": 2.0,
		"cooldown": 0.4, "colour": Color(0.4, 0.9, 1.0),
		"description": "A spinning blade strip. Clears brambles and thin trunks."},
}

const RECIPES := {
	"smasher": {"name": "Smasher", "tool": "smasher",
		"needs": {"hammer_head": 1, "actuator_arm": 1},
		"description": "Attach a hammer head to an actuator arm."},
	"cutter": {"name": "Cutter", "tool": "cutter",
		"needs": {"servo_motor": 1, "gear_train": 1, "blade_strip": 1, "power_cell": 1},
		"description": "A servo spins a blade strip. Needs a cell of its own."},
	"blade_strip": {"name": "Blade strip", "gives": {"blade_strip": 1},
		"needs": {"scrap_metal": 2},
		"description": "Fold and grind scrap into an edge."},
}

func item_name(id: String) -> String:
	return String(ITEMS.get(id, {}).get("name", id))

func tool_name(id: String) -> String:
	return String(TOOLS.get(id, {}).get("name", id))
