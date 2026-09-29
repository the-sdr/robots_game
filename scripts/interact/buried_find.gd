extends Node3D

# Something buried. Only a faint patch of disturbed soil shows; the detector
# finds it (group "detectable", scripts/detector.gd). Standing on it, "Dig"
# (interact) digs it up: dirt flies, the find rises out of the ground and goes
# into the inventory, and a hole is left. The robot can always dig (owner,
# 2026-09-29). Stays dug across saves. Placed by the level pipeline from a
# design's "finds" with kind "buried".

const DIG_ENERGY := 1.0
const RISE_SECONDS := 0.6
const SHOW_SECONDS := 0.35
## Per-item models built by tools/item_models_bake.gd (the same ones pickups use).
const MODEL := "res://scenes/props/items/%s.res"

@export var item_id: String = "scrap_metal"
@export var amount: int = 1

@onready var mound: MeshInstance3D = $Mound
@onready var hole: MeshInstance3D = $Hole
@onready var interactable: Interactable = $Interactable
@onready var dirt: CPUParticles3D = $Dirt

var dug := false
## Set once the find has gone into the inventory (tests).
var recovered := false

func _flag() -> String:
	return "dug:" + String(get_path()).trim_prefix("/root/")

func _ready() -> void:
	interactable.prompt = "Dig"
	interactable.interacted.connect(_on_interacted)
	if Game.get_flag(_flag()):
		_show_dug()
		recovered = true
		return
	add_to_group("detectable")

## Where the detector senses it.
func detect_position() -> Vector3:
	return global_position

func _show_dug() -> void:
	dug = true
	remove_from_group("detectable")
	interactable.enabled = false
	mound.visible = false
	hole.visible = true

func _on_interacted(_player: Node3D) -> void:
	if dug:
		return
	if not Energy.spend(DIG_ENERGY):
		get_tree().call_group("hud", "show_notice", "Not enough energy to dig")
		return
	_show_dug()
	Game.set_flag(_flag(), true)
	dirt.restart()
	var model := _item_model()
	model.position = Vector3(0, -0.25, 0)
	add_child(model)
	var rise := create_tween()
	rise.tween_property(model, "position", Vector3(0, 0.8, 0), RISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.parallel().tween_property(model, "rotation:y", TAU, RISE_SECONDS + SHOW_SECONDS)
	rise.tween_interval(SHOW_SECONDS)
	rise.tween_callback(_recover.bind(model))

func _recover(model: Node3D) -> void:
	model.queue_free()
	Game.add_item(item_id, amount)
	recovered = true
	var what := Catalog.item_name(item_id) + (" x%d" % amount if amount > 1 else "")
	get_tree().call_group("hud", "show_notice", "Dug up: %s" % what)
	print("Dug up %s" % what)

func _item_model() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Find"
	if ResourceLoader.exists(MODEL % item_id):
		mi.mesh = load(MODEL % item_id)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.25, 0.1, 0.18)
		mi.mesh = box
	return mi
