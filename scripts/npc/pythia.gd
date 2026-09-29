extends StaticBody3D

# Pythia, the relay's keeper (the Relay Vault's oracle chamber): the first NPC
# robot. She can't leave; she talks (HUD dialogue, E for the next line) and,
# the first time, gives the lift fans and gyro for the hover pack and points
# the way to the Agora. Her lines are placeholders: the reason a charger can
# keep a copy of you is still the owner's decision (PROJECT_VISION).

const GIFT_FLAG := "pythia_gift"
const GIFT := {"lift_fan": 2, "gyro": 1}
const FIRST_TALK: Array[String] = [
	"A visitor. It has been a long time since anyone lit the hall. I am Pythia. I keep the relay, and the relay keeps listening.",
	"You woke up at a charger, and when your power runs out you wake there again. Every charger listens while you rest, and keeps a copy of what you are. [placeholder: the real reason is still being decided]",
	"I cannot leave this room. You can. Take these: two lift fans and a gyro. Build a hover pack, and a high ledge stops being a wall.",
	"East of the gate there is a market, choked with vines. Something that burns from far away would open it.",
]
const LATER_TALK: Array[String] = [
	"The market is east of the gate, behind the vines. Burn them. And come back and tell me what is out there.",
]

@onready var interactable: Interactable = $Interactable
@onready var face: MeshInstance3D = $Visual/Head/Face
@onready var head: Node3D = $Visual/Head

var _time := 0.0
var _face_material: StandardMaterial3D

func _ready() -> void:
	interactable.prompt = "Talk to Pythia"
	interactable.interacted.connect(talk)
	_face_material = (face.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	face.set_surface_override_material(0, _face_material)

func _process(delta: float) -> void:
	_time += delta
	_face_material.emission_energy_multiplier = 1.6 + 0.5 * sin(_time * 1.3)
	head.rotation.z = sin(_time * 0.5) * 0.05

func talk(_player: Node3D = null) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or hud.dialogue_open():
		return
	var first := not Game.get_flag(GIFT_FLAG)
	hud.show_dialogue("Pythia", FIRST_TALK if first else LATER_TALK)
	if first:
		hud.dialogue_finished.connect(_give_gift, CONNECT_ONE_SHOT)

func _give_gift(_speaker: String) -> void:
	if Game.get_flag(GIFT_FLAG):
		return
	Game.set_flag(GIFT_FLAG, true)
	for id in GIFT:
		Game.add_item(id, GIFT[id])
	get_tree().call_group("hud", "show_notice", "Took 2 lift fans and a gyro. Build the hover pack (%s)." % Glyphs.label("inventory"))
