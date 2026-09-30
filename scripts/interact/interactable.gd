class_name Interactable
extends Area3D

# Something the robot can use with the interact key when close. Put one on any
# node (as an Area3D with a collision shape), set `prompt`, and connect
# `interacted`. The player's InteractProbe finds the nearest enabled one and the
# HUD shows "[E] <prompt>". `verb` is spoken by the HUD; `prompt` is the object.

signal interacted(player: Node3D)

@export var prompt: String = "Use"
@export var enabled: bool = true
## Interaction point for distance sorting (defaults to this node's origin).
@export var focus_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("interactable")
	monitoring = false           # the probe finds us; we never need to scan
	monitorable = true

func focus_position() -> Vector3:
	return global_transform * focus_offset

func interact(player: Node3D) -> void:
	if enabled:
		interacted.emit(player)
