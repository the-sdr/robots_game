extends Area3D

# Plays a Story beat when the robot drives in. Give it a collision shape and a
# beat id; it fires once per save (Story handles that).

@export var beat: String = ""

func _ready() -> void:
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and beat != "":
		Story.play(beat)
