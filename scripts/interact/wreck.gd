extends Breakable

# A wreck to salvage: a dead machine with parts still in it (owner, 2026-09-29:
# "cutter and laser might be best for salvage; laser gets better loot").
# The cutter (held) or the laser (swept along its seam - it is long, so the
# beam traces it segment by segment) strips it. Stripped, it gives `drops`;
# stripped by the laser - a clean cut along the seam - it also gives `bonus`.
# Unlike other Breakables it stays, stripped and dark. Saved as salvaged.
# The detector senses it until then (Breakable: anything with drops).

## Extra loot when the laser finished the job.
@export var bonus: Dictionary = {}

var salvaged := false
var _last_effect := ""

func _ready() -> void:
	add_to_group("breakable")
	_max_health = health
	if break_flag == "":
		break_flag = "salvaged:" + String(get_path()).trim_prefix("/root/")
	if Game.get_flag(break_flag):
		_show_stripped()
		return
	add_to_group("detectable")

func apply(effect: String, power: float, from: Vector3) -> bool:
	if salvaged:
		get_tree().call_group("hud", "show_notice", "Stripped bare. Nothing left in it.")
		return false
	_last_effect = effect
	return super.apply(effect, power, from)

func burn_at(point: Vector3, delta: float, from: Vector3, power: float) -> void:
	if salvaged:
		return
	_last_effect = "burn"
	super.burn_at(point, delta, from, power)

func _break(from: Vector3) -> void:
	_debris(from, debris_count)
	var loot := drops.duplicate()
	if _last_effect == "burn":
		for id in bonus:
			loot[id] = int(loot.get(id, 0)) + int(bonus[id])
	for id in loot:
		Game.add_item(id, int(loot[id]))
		get_tree().call_group("hud", "show_notice", "Salvaged %s x%d" % [Catalog.item_name(id), int(loot[id])])
	if _last_effect == "burn" and not bonus.is_empty():
		get_tree().call_group("hud", "show_notice", "A clean cut along the seam: bonus parts!")
	Game.set_flag(break_flag, true)
	broken.emit()
	_show_stripped()

func _show_stripped() -> void:
	salvaged = true
	remove_from_group("detectable")
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.12, 0.1, 0.09)
	soot.roughness = 1.0
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = soot
