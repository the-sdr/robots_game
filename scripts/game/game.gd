extends Node

# Autoload "Game": everything that persists between sessions lives in `data`
# (flags, inventory, tools, energy, clock, where the robot last docked).
# Other autoloads (Clock, Energy) read and write their own keys in here so a
# single JSON file is the whole save. Saving happens when the robot docks at a
# charger (the owner wants a diegetic reason for that later: the robot copies
# its own consciousness at the charger).

signal inventory_changed
signal flag_changed(flag: String, value: bool)
signal loaded          # a save was applied to the running world
signal new_game_started

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var data: Dictionary = {}
## Set by the main menu: the world scene applies the save when it is ready.
var pending_load := false

func _ready() -> void:
	_reset_data()

func _reset_data() -> void:
	data = {
		"version": SAVE_VERSION,
		"flags": {},
		"inventory": {},          # item id -> count
		"tools": [],              # tool ids the robot has built (in order)
		"equipped_tool": "",
		"energy": Energy.MAX,
		"time": Clock.START_TIME,
		"day": 1,
		"last_charger": "",       # node name of the charger last docked at
		"player_position": [0.0, 0.0, 0.0],
		"player_yaw": 0.0,
		"seen_beats": [],
		"chargers": {},           # charger name -> its saved state
	}

# --- flags ---------------------------------------------------------------------
func get_flag(flag: String) -> bool:
	return data["flags"].get(flag, false)

func set_flag(flag: String, value: bool = true) -> void:
	if get_flag(flag) == value:
		return
	data["flags"][flag] = value
	flag_changed.emit(flag, value)

# --- inventory -----------------------------------------------------------------
func count(item_id: String) -> int:
	return int(data["inventory"].get(item_id, 0))

func add_item(item_id: String, amount: int = 1) -> void:
	data["inventory"][item_id] = count(item_id) + amount
	inventory_changed.emit()

func remove_item(item_id: String, amount: int = 1) -> bool:
	if count(item_id) < amount:
		return false
	var left := count(item_id) - amount
	if left == 0:
		data["inventory"].erase(item_id)
	else:
		data["inventory"][item_id] = left
	inventory_changed.emit()
	return true

func has_items(needed: Dictionary) -> bool:
	for id in needed:
		if count(id) < int(needed[id]):
			return false
	return true

# --- tools -----------------------------------------------------------------------
func has_tool(tool_id: String) -> bool:
	return data["tools"].has(tool_id)

func add_tool(tool_id: String) -> void:
	if has_tool(tool_id):
		return
	data["tools"].append(tool_id)
	if data["equipped_tool"] == "":
		data["equipped_tool"] = tool_id
	inventory_changed.emit()

# --- crafting ---------------------------------------------------------------------
## Returns "" when the recipe can be made, else the reason it can't.
func craft_blocker(recipe_id: String) -> String:
	var recipe: Dictionary = Catalog.RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return "Unknown recipe"
	if recipe.has("requires_flag") and not get_flag(recipe["requires_flag"]):
		return "Not understood yet"
	if recipe.has("tool") and has_tool(recipe["tool"]):
		return "Already built"
	if not has_items(recipe["needs"]):
		return "Missing parts"
	return ""

func craft(recipe_id: String) -> bool:
	if craft_blocker(recipe_id) != "":
		return false
	var recipe: Dictionary = Catalog.RECIPES[recipe_id]
	for id in recipe["needs"]:
		remove_item(id, int(recipe["needs"][id]))
	if recipe.has("tool"):
		add_tool(recipe["tool"])
	for id in recipe.get("gives", {}):
		add_item(id, int(recipe["gives"][id]))
	return true

# --- beats (one-shot story messages) -------------------------------------------------
func beat_seen(beat_id: String) -> bool:
	return data["seen_beats"].has(beat_id)

func mark_beat(beat_id: String) -> void:
	if not beat_seen(beat_id):
		data["seen_beats"].append(beat_id)

# --- persistence --------------------------------------------------------------------
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func new_game() -> void:
	_reset_data()
	pending_load = false
	Energy.reset()
	Clock.reset()
	new_game_started.emit()

## Called by a charger when the robot docks. Player position/yaw come from the world.
func save(player: Node3D, charger_name: String) -> bool:
	data["last_charger"] = charger_name
	var p := player.global_position
	data["player_position"] = [p.x, p.y, p.z]
	var visual: Node3D = player.get_node_or_null("Visual")
	data["player_yaw"] = visual.global_rotation.y if visual != null else 0.0
	data["energy"] = Energy.current
	data["time"] = Clock.time
	data["day"] = Clock.day
	for c in get_tree().get_nodes_in_group("charger"):
		data["chargers"][c.name] = c.save_state()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

## Reads the save into `data` (no world changes). Returns false if missing or broken.
func load_save() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != SAVE_VERSION:
		push_warning("Save file unreadable or old version; ignoring it")
		return false
	_reset_data()
	for key in data:
		if parsed.has(key):
			data[key] = parsed[key]
	Energy.current = float(data["energy"])
	Clock.time = float(data["time"])
	Clock.day = int(data["day"])
	return true

## Applies the loaded data to the live player. Called by the world when ready.
func apply_to_world(player: Node3D) -> void:
	var p: Array = data["player_position"]
	player.global_position = Vector3(p[0], p[1], p[2])
	var visual: Node3D = player.get_node_or_null("Visual")
	if visual != null:
		visual.global_rotation.y = float(data["player_yaw"])
	for c in get_tree().get_nodes_in_group("charger"):
		if data["chargers"].has(c.name):
			c.load_state(data["chargers"][c.name])
	pending_load = false
	inventory_changed.emit()
	loaded.emit()

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
