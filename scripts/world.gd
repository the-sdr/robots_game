extends Node3D

# The playable world. Starts a new game at the house charger or applies the
# autosave, and handles the battery running out: the robot shuts down and
# reboots at the charger it last docked with, next morning.

const REBOOT_ENERGY := 30.0
const WAKE_ENERGY := 28.0        # a new game starts nearly flat: dock first, then smash
const SHUTDOWN_SECONDS := 2.5
const INTRO := preload("res://scenes/cutscene/opening.tscn")

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

var _shutting_down := false
var _told_scan := false

# The detector card shows as the robot first steps out of the house (owner,
# save_55: "as soon as you're out we need to tell the player how to scan").
const HOUSE_MIN := Vector2(-2.79, -7.84)
const HOUSE_MAX := Vector2(2.79, -2.21)

func _process(_delta: float) -> void:
	if _told_scan or not Game.get_flag("house_door_broken"):
		return
	var p := player.global_position
	if p.x < HOUSE_MIN.x or p.x > HOUSE_MAX.x or p.z < HOUSE_MIN.y or p.z > HOUSE_MAX.y:
		_told_scan = true
		hud.queue_card("detector")

func _ready() -> void:
	Clock.running = true
	Energy.depleted.connect(_on_energy_depleted)
	if Game.pending_load:
		Game.apply_to_world(player)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.show_notice("Consciousness restored at %s" % _charger_label(Game.data["last_charger"]))
	else:
		_start_new_game()
	for c in get_tree().get_nodes_in_group("charger"):
		c.docked.connect(func(_player: Node3D) -> void: Story.play("copy"))
		c.docked.connect(_offer_rest.bind(c))
	Game.flag_changed.connect(_on_flag_changed)

# --- resting through the night (owner, save_57) -------------------------------------------
## Docking at night asks whether to rest until morning (optional: "Not now" just docks).
func _offer_rest(_player: Node3D, charger: Node3D) -> void:
	if Clock.is_day() or _shutting_down:
		return
	hud.ask("Night", "It's dark and the sun won't fill any charger until morning. Rest here until morning?",
		"Rest until morning", "Not now", _rest_until_morning.bind(charger))

## Skips to morning while docked: the robot takes what the charger holds, the
## copy is saved, and a new day starts.
func _rest_until_morning(charger: Node3D) -> void:
	await hud.fade(1.0, 0.6)
	var wanted: float = Energy.MAX - Energy.current
	var given: float = minf(wanted, float(charger.get("stored")))
	Energy.add(given)
	charger.set("stored", float(charger.get("stored")) - given)
	Clock.skip_to_morning()
	Game.save(player, charger.name)
	print("rested at %s until %s, day %d: gave %.1f" % [charger.name, Clock.time_text(), Clock.day, given])
	await get_tree().create_timer(0.4).timeout
	await hud.fade(0.0, 0.8)
	hud.show_message("Morning, day %d" % Clock.day, "Rested at the %s through the night. Battery %d%%." % [_charger_label(charger.name), roundi(Energy.fraction() * 100.0)])

func _start_new_game() -> void:
	var home := home_charger()
	if home != null:
		_place_beside(home)
	Energy.current = WAKE_ENERGY
	Energy.changed.emit(Energy.current, Energy.MAX)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Game.play_intro:
		Game.play_intro = false
		var intro: Node = INTRO.instantiate()
		add_child(intro)
		intro.finished.connect(func() -> void: get_tree().create_timer(0.8).timeout.connect(_wake))
		intro.play(self)
	else:
		get_tree().create_timer(1.2).timeout.connect(_wake)

## The wake-up message, then (once it has been read) the controls card.
func _wake() -> void:
	Story.play("wake")
	get_tree().create_timer(4.0).timeout.connect(func() -> void: hud.queue_card("basics"))

func _on_flag_changed(flag: String, value: bool) -> void:
	if flag == "house_door_broken" and value:
		Story.play("door")
	if flag == "unlocked:tower_door" and value:
		Story.play("relay")
		Game.set_flag("slice_complete", true)

func home_charger() -> Node3D:
	for c in get_tree().get_nodes_in_group("charger"):
		if c.get("is_home"):
			return c
	return null

func charger_named(charger_name: String) -> Node3D:
	for c in get_tree().get_nodes_in_group("charger"):
		if c.name == charger_name:
			return c
	return home_charger()

func _charger_label(charger_name: String) -> String:
	return "the house charger" if charger_name == "HouseCharger" or charger_name == "" else charger_name.capitalize().to_lower()

## Puts the robot a metre in front of a charger, facing it.
func _place_beside(charger: Node3D) -> void:
	var toward := Vector3(1.0, 0.0, -1.0).normalized()     # out into the room: the house charger sits in the north-west corner (-X, -Z)
	if charger.has_node("SpawnPoint"):
		var spawn: Node3D = charger.get_node("SpawnPoint")
		player.global_position = spawn.global_position
		toward = -(spawn.global_position - charger.global_position).normalized()
	else:
		player.global_position = charger.global_position + toward * 1.3 + Vector3(0, 0.1, 0)
		toward = -toward
	var visual: Node3D = player.get_node("Visual")
	visual.global_rotation.y = atan2(toward.x, toward.z) + PI

func _on_energy_depleted() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	player.set("shut_down", true)
	hud.show_message("Power lost", "Systems shutting down. The last copy of you is at %s." % _charger_label(Game.data["last_charger"]))
	await get_tree().create_timer(SHUTDOWN_SECONDS).timeout
	var charger := charger_named(Game.data["last_charger"])
	if charger != null:
		_place_beside(charger)
		charger.set("stored", maxf(float(charger.get("stored")) - REBOOT_ENERGY * 0.5, 0.0))
	Clock.skip_to_morning()
	Energy.current = REBOOT_ENERGY
	Energy.changed.emit(Energy.current, Energy.MAX)
	player.set("shut_down", false)
	_shutting_down = false
	hud.show_message("Day %d" % Clock.day, "Rebooted from the last copy. Whatever you carried, you still carry.")
