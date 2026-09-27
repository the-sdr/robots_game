extends Node3D

# The playable world. Starts a new game at the house charger or applies the
# autosave, and handles the battery running out: the robot shuts down and
# reboots at the charger it last docked with, next morning.

const REBOOT_ENERGY := 30.0
const SHUTDOWN_SECONDS := 2.5

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

var _shutting_down := false

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
	Game.flag_changed.connect(_on_flag_changed)

func _start_new_game() -> void:
	var home := home_charger()
	if home != null:
		_place_beside(home)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().create_timer(1.2).timeout.connect(func() -> void: Story.play("wake"))

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
