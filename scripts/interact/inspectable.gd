extends Interactable

# "Inspect": plays a Story beat the first time, and shows it again afterwards.

@export var beat: String = ""

func _ready() -> void:
	super()
	if prompt == "Use":
		prompt = "Inspect"
	interacted.connect(_on_interacted)

func _on_interacted(_player: Node3D) -> void:
	if beat == "":
		return
	if not Story.play(beat):
		var b: Dictionary = Story.beat(beat)       # this mode's text, again
		if not b.is_empty():
			get_tree().call_group("hud", "show_message", b["title"], b["text"])
