extends StaticBody3D

# A charging station. Holds `capacity` units of energy, refilled by sunlight
# (the flat-panel physics: light on the panel scales with the angle to the sun,
# nothing at night, most at noon). Docking transfers stored energy into the
# robot at `transfer_rate` and writes the autosave. Chargers are named uniquely
# in the scene ("HouseCharger"); the save remembers the last one used.
#
# Upgrades (sprint 2), fitted while docked from the Tab screen (Catalog recipes
# with "upgrade"): "panel" (two more cells: fills 50 % faster), "tracker" (the
# panel follows the sun: full light whenever the sun is up), "battery" (holds
# BATTERY_BONUS more). They are saved with the charger and show on it.
# The post carries a charge bar: BAR_SEGMENTS glowing rings; the one still
# filling blinks.

signal docked(player: Node3D)
signal undocked
signal stored_changed(stored: float, capacity: float)
signal upgraded(kind: String)

const UPGRADES := ["panel", "tracker", "battery"]
const PANEL_BONUS := 1.5
const BATTERY_BONUS := 60.0
const BAR_SEGMENTS := 5
const BAR_ON := Color(0.35, 1.0, 0.55)
const BAR_OFF := Color(0.07, 0.09, 0.1)

@export var capacity: float = 120.0
@export var panel_rate: float = 0.45          # energy per second at full sun on the panel
@export var transfer_rate: float = 9.0        # energy per second into the robot
@export var stored: float = 60.0
## Which way the solar panel faces (local space). Tilting it towards the noon sun (south, +Z) beats flat.
@export var panel_normal: Vector3 = Vector3(0.0, 1.0, 0.0)
## Wake-up charger: the robot boots here when the battery dies.
@export var is_home: bool = false

@onready var interactable: Interactable = $Interactable
@onready var core: MeshInstance3D = $CoreMesh
@onready var glow: OmniLight3D = $Glow
@onready var panel: MeshInstance3D = $PanelMesh

var docked_player: Node3D = null
var upgrades: Array[String] = []
var _core_material: StandardMaterial3D
var _bar_materials: Array[StandardMaterial3D] = []
var _panel_rest: Transform3D
var _time := 0.0

func _ready() -> void:
	add_to_group("charger")
	interactable.interacted.connect(_on_interacted)
	interactable.prompt = "Dock"
	_core_material = core.get_surface_override_material(0).duplicate()
	core.set_surface_override_material(0, _core_material)
	_panel_rest = panel.transform
	_build_bar()
	_update_look()

func _process(delta: float) -> void:
	_time += delta
	var gained := fill_rate() * delta
	var cap := effective_capacity()
	if gained > 0.0 and stored < cap:
		stored = minf(stored + gained, cap)
		stored_changed.emit(stored, cap)
	if docked_player != null:
		var wanted := minf(transfer_rate * delta, stored)
		var taken := Energy.add(wanted)
		stored -= taken
		stored_changed.emit(stored, cap)
		if taken <= 0.0 or stored <= 0.0:
			if Energy.current >= Energy.MAX - 0.01:
				get_tree().call_group("hud", "show_notice", "Battery full")
			elif stored <= 0.0:
				get_tree().call_group("hud", "show_notice", "Charger empty. Sunlight refills it.")
			undock()
	if has_upgrade("tracker"):
		_face_sun()
	_update_look()
	interactable.prompt = "%s   charge %d%%" % ["Undock" if docked_player != null else "Dock", roundi(stored / cap * 100.0)]

func effective_capacity() -> float:
	return capacity + (BATTERY_BONUS if has_upgrade("battery") else 0.0)

func effective_rate() -> float:
	return panel_rate * (PANEL_BONUS if has_upgrade("panel") else 1.0)

## Energy per second the sun is putting in right now.
func fill_rate() -> float:
	return sun_factor() * effective_rate()

## Solar panel physics: light hitting the panel scales with the cosine of the
## angle between the panel's normal and the sun (nothing when the sun is below
## the horizon). A flat panel therefore gets sin(elevation). A sun tracker keeps
## the panel pointed at the sun: full light, except in the last minutes near the
## horizon where the light is too thin.
func sun_factor() -> float:
	var sun := Clock.sun_direction()
	if sun.y <= 0.0:
		return 0.0
	if has_upgrade("tracker"):
		return smoothstep(0.0, 0.15, sun.y)
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

# --- upgrades ------------------------------------------------------------------------------
func has_upgrade(kind: String) -> bool:
	return upgrades.has(kind)

func add_upgrade(kind: String) -> bool:
	if not UPGRADES.has(kind) or has_upgrade(kind):
		return false
	upgrades.append(kind)
	_show_upgrade(kind)
	stored_changed.emit(stored, effective_capacity())
	upgraded.emit(kind)
	return true

func _show_upgrade(kind: String) -> void:
	if has_node("Upgrade_" + kind):
		return
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.23, 0.25)
	dark.metallic = 0.7
	dark.roughness = 0.4
	match kind:
		"panel":
			# two more cells either side of the panel, tilting with it
			var wings := Node3D.new()
			wings.name = "Upgrade_panel"
			panel.add_child(wings)
			var cell := BoxMesh.new()
			cell.size = Vector3(0.5, 0.035, 0.7)
			for side in [-1.0, 1.0]:
				var mi := MeshInstance3D.new()
				mi.mesh = cell
				mi.material_override = panel.get_surface_override_material(0)
				mi.position = Vector3(0.83 * side, 0, 0)
				wings.add_child(mi)
		"tracker":
			var motor := MeshInstance3D.new()
			motor.name = "Upgrade_tracker"
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.16, 0.22)
			motor.mesh = box
			var orange := StandardMaterial3D.new()
			orange.albedo_color = Color(0.95, 0.5, 0.14)
			motor.material_override = orange
			motor.position = Vector3(0, 1.8, 0)
			add_child(motor)
		"battery":
			var bank := MeshInstance3D.new()
			bank.name = "Upgrade_battery"
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.36, 0.3)
			bank.mesh = box
			bank.material_override = dark
			bank.position = Vector3(0.45, 0.33, 0.25)
			add_child(bank)
			var stripe := MeshInstance3D.new()
			var band := BoxMesh.new()
			band.size = Vector3(0.52, 0.06, 0.32)
			stripe.mesh = band
			var green := StandardMaterial3D.new()
			green.albedo_color = BAR_ON
			green.emission_enabled = true
			green.emission = BAR_ON
			green.emission_energy_multiplier = 1.5
			stripe.material_override = green
			bank.add_child(stripe)

## The tracker turns the panel (about its mount) to face the sun; parked flat at night.
func _face_sun() -> void:
	var sun := Clock.sun_direction()
	if sun.y <= 0.0:
		panel.transform = Transform3D(Basis(), _panel_rest.origin)
		return
	var local_sun := (global_transform.basis.inverse() * sun).normalized()
	var axis := Vector3.UP.cross(local_sun)
	var tilt := Basis() if axis.length() < 0.001 else Basis(axis.normalized(), Vector3.UP.angle_to(local_sun))
	panel.transform = Transform3D(tilt, _panel_rest.origin)

# --- the charge bar ---------------------------------------------------------------------------
func _build_bar() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 0.17
	ring.bottom_radius = 0.17
	ring.height = 0.07
	ring.radial_segments = 16
	for i in BAR_SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.name = "BarSegment%d" % i
		mi.mesh = ring
		var m := StandardMaterial3D.new()
		m.albedo_color = BAR_OFF
		m.emission_enabled = true
		m.emission = BAR_ON
		m.emission_energy_multiplier = 0.0
		mi.material_override = m
		mi.position = Vector3(0, 0.45 + i * 0.1, 0)
		add_child(mi)
		_bar_materials.append(m)

## [segments fully lit, index of the blinking (still filling) segment or -1].
func bar_state() -> Array[int]:
	var filled := stored / effective_capacity() * BAR_SEGMENTS
	var lit := clampi(int(floor(filled + 0.001)), 0, BAR_SEGMENTS)
	var blinking := lit if lit < BAR_SEGMENTS and filled - lit > 0.02 else -1
	return [lit, blinking]

func _update_look() -> void:
	var f := stored / effective_capacity()
	var pulse: float = 1.0 + 0.18 * sin(Time.get_ticks_msec() / 1000.0 * 7.0) if docked_player != null else 1.0
	core.scale = Vector3.ONE * pulse
	var colour := Color(0.2, 1.0, 0.9).lerp(Color(1.0, 0.35, 0.15), 1.0 - f)
	_core_material.emission = colour
	_core_material.emission_energy_multiplier = 1.0 + 3.0 * f
	glow.light_color = colour
	glow.light_energy = 0.4 + 1.6 * f
	var bar := bar_state()
	var blink_on := fmod(_time, 1.0) < 0.55
	for i in _bar_materials.size():
		var on := i < bar[0] or (i == bar[1] and blink_on)
		_bar_materials[i].albedo_color = BAR_ON if on else BAR_OFF
		_bar_materials[i].emission_energy_multiplier = 2.2 if on else 0.0

func save_state() -> Dictionary:
	return {"stored": stored, "upgrades": upgrades.duplicate()}

func load_state(state: Dictionary) -> void:
	stored = float(state.get("stored", stored))
	for kind in state.get("upgrades", []):
		add_upgrade(String(kind))
