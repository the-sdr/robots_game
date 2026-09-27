extends StaticBody3D

# A charging station. Holds `capacity` units of energy, refilled by sunlight
# (Clock.sunlight() x `panel_rate`, the flat-panel physics: nothing at night,
# most at noon). Docking transfers stored energy into the robot at
# `transfer_rate` and writes the autosave. Chargers are named uniquely in the
# scene ("HouseCharger"); the save remembers the last one used.

signal docked(player: Node3D)
signal undocked
signal stored_changed(stored: float, capacity: float)

@export var capacity: float = 120.0
@export var panel_rate: float = 0.45          # energy per second at full noon sun
@export var transfer_rate: float = 9.0        # energy per second into the robot
@export var stored: float = 60.0
## Which way the solar panel faces (local space). Tilting it towards the noon sun (south, +Z) beats flat.
@export var panel_normal: Vector3 = Vector3(0.0, 1.0, 0.0)
## Wake-up charger: the robot boots here when the battery dies.
@export var is_home: bool = false

@onready var interactable: Interactable = $Interactable
@onready var core: MeshInstance3D = $CoreMesh
@onready var glow: OmniLight3D = $Glow

var docked_player: Node3D = null
var _core_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("charger")
	interactable.interacted.connect(_on_interacted)
	interactable.prompt = "Dock"
	_core_material = core.get_surface_override_material(0).duplicate()
	core.set_surface_override_material(0, _core_material)
	_update_look()

func _process(delta: float) -> void:
	var gained := sun_factor() * panel_rate * delta
	if gained > 0.0 and stored < capacity:
		stored = minf(stored + gained, capacity)
		stored_changed.emit(stored, capacity)
	if docked_player != null:
		var wanted := minf(transfer_rate * delta, stored)
		var taken := Energy.add(wanted)
		stored -= taken
		stored_changed.emit(stored, capacity)
		if taken <= 0.0 or stored <= 0.0:
			if Energy.current >= Energy.MAX - 0.01:
				get_tree().call_group("hud", "show_notice", "Battery full")
			elif stored <= 0.0:
				get_tree().call_group("hud", "show_notice", "Charger empty. Sunlight refills it.")
			undock()
	_update_look()
	interactable.prompt = "%s   charge %d%%" % ["Undock" if docked_player != null else "Dock", roundi(stored / capacity * 100.0)]

## Solar panel physics: light hitting the panel scales with the cosine of the
## angle between the panel's normal and the sun (nothing when the sun is below
## the horizon). A flat panel therefore gets sin(elevation).
func sun_factor() -> float:
	var sun := Clock.sun_direction()
	if sun.y <= 0.0:
		return 0.0
	var normal := (global_transform.basis * panel_normal).normalized()
	return clampf(normal.dot(sun), 0.0, 1.0)

func _on_interacted(player: Node3D) -> void:
	if docked_player != null:
		undock()
	else:
		dock(player)

func dock(player: Node3D) -> void:
	docked_player = player
	player.set("docked", true)
	Game.save(player, name)
	get_tree().call_group("hud", "show_notice", "Docked. Consciousness copied.")
	docked.emit(player)

func undock() -> void:
	if docked_player == null:
		return
	docked_player.set("docked", false)
	docked_player = null
	undocked.emit()

func _update_look() -> void:
	var f := stored / capacity
	var pulse: float = 1.0 + 0.18 * sin(Time.get_ticks_msec() / 1000.0 * 7.0) if docked_player != null else 1.0
	core.scale = Vector3.ONE * pulse
	var colour := Color(0.2, 1.0, 0.9).lerp(Color(1.0, 0.35, 0.15), 1.0 - f)
	_core_material.emission = colour
	_core_material.emission_energy_multiplier = 1.0 + 3.0 * f
	glow.light_color = colour
	glow.light_energy = 0.4 + 1.6 * f

func save_state() -> Dictionary:
	return {"stored": stored}

func load_state(state: Dictionary) -> void:
	stored = float(state.get("stored", stored))
