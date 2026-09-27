extends StaticBody3D

# A gate that opens with a key item (kept, not consumed). Unlocking sets a
# flag so the gate stays open across saves. Put the fence/door meshes and the
# collision shapes under this node; an Interactable child gives the prompt.

signal opened

@export var key_item: String = "gate_key"
@export var gate_id: String = ""
@export var display_name: String = "the gate"
@export var locked_notice: String = ""

@onready var interactable: Interactable = $Interactable

func flag() -> String:
	return "unlocked:" + (gate_id if gate_id != "" else name)

func _ready() -> void:
	add_to_group("gate")
	if Game.get_flag(flag()):
		queue_free()
		return
	interactable.prompt = "Unlock %s (%s)" % [display_name, Catalog.item_name(key_item)]
	interactable.interacted.connect(_on_interacted)

func _on_interacted(_player: Node3D) -> void:
	if Game.count(key_item) > 0:
		unlock()
	else:
		get_tree().call_group("hud", "show_notice", locked_notice if locked_notice != "" else "Locked. It wants a %s." % Catalog.item_name(key_item).to_lower())

func unlock() -> void:
	Game.set_flag(flag(), true)
	get_tree().call_group("hud", "show_notice", "Unlocked %s with the %s" % [display_name, Catalog.item_name(key_item).to_lower()])
	interactable.enabled = false
	for shape in find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = true
	opened.emit()
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + 3.2, 1.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
