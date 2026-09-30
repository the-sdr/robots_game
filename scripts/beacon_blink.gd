extends OmniLight3D

# Slow blink for a warning beacon (relay tower). Cheap: one light, one sine.

@export var period: float = 2.4
@export var peak_energy: float = 2.5
@export var floor_energy: float = 0.2

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	var pulse: float = pow(maxf(sin(_t * TAU / period), 0.0), 6.0)
	light_energy = floor_energy + (peak_energy - floor_energy) * pulse
	var mesh: MeshInstance3D = get_parent().get_node_or_null("Beacon")
	if mesh != null and mesh.mesh != null:
		var material: StandardMaterial3D = mesh.mesh.material
		if material != null:
			material.emission_energy_multiplier = 0.6 + 5.0 * pulse
