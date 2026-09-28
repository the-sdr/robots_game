extends StaticBody3D

# A lens set in the Relay Vault's west wall. Hit it with the laser and it feeds
# the mirror hall's beam for a while, day or night (tool_rig.gd finds it like any
# body with apply()).

signal powered

func apply(effect: String, _power: float, _from: Vector3) -> bool:
	if effect != "burn":
		get_tree().call_group("hud", "show_notice", "A lens in the wall. It wants light, not a knock.")
		return false
	powered.emit()
	return true
