extends Node3D

# A ghost outline of something the fabricator can print: a ramp, a bridge...
# Until it is built it is a see-through glowing shape with no collision, and
# the robot sees "[E] Print <name> (N scrap)". With the fabricator built and
# the scrap in hand, E (or a fabricator click, tool_rig.gd) prints it: the
# real thing grows up out of the ground and becomes solid. `flag` remembers it.
#
# Scene layout: Ghost (Node3D, meshes only), Solid (StaticBody3D: a Model
# Node3D with the meshes + collision shapes), Interactable (Area3D + shape).

@export var display_name := "the ramp"
@export var cost := {"scrap_metal": 2}
@export var flag := "built:scrap_ramp"

@onready var ghost: Node3D = $Ghost
@onready var solid: StaticBody3D = $Solid
@onready var interactable: Interactable = $Interactable

var built := false
var _layer := 1
var _time := 0.0

func _ready() -> void:
	add_to_group("buildable")
	_layer = solid.collision_layer
	interactable.interacted.connect(func(player: Node3D) -> void: build(player))
	Game.loaded.connect(_sync)
	Game.new_game_started.connect(_sync)
	Game.inventory_changed.connect(_update_prompt)
	_sync()

func _process(delta: float) -> void:
	if built:
		return
	_time += delta
	ghost.scale = Vector3.ONE * (1.0 + 0.012 * sin(_time * 2.5))     # a gentle "not quite real" shimmer

func focus_position() -> Vector3:
	return interactable.global_position

func scrap_needed() -> int:
	var n := 0
	for id in cost:
		n += int(cost[id])
	return n

## "" when it can be printed now, else why not.
func blocker() -> String:
	if built:
		return "Already printed"
	if not Game.has_tool("fabricator"):
		return "A ghost outline of %s, drawn in light. A matter printer could fill it in." % display_name
	if not Game.has_items(cost):
		return "Printing %s needs %d scrap metal." % [display_name, scrap_needed()]
	return ""

func build(_player: Node3D = null) -> bool:
	var why := blocker()
	if why != "":
		get_tree().call_group("hud", "show_notice", why)
		return false
	for id in cost:
		Game.remove_item(id, int(cost[id]))
	Game.set_flag(flag)
	_set_built(true, true)
	get_tree().call_group("hud", "show_notice", "Printed %s" % display_name)
	return true

func _sync() -> void:
	_set_built(Game.get_flag(flag), false)

func _set_built(on: bool, animate: bool) -> void:
	built = on
	ghost.visible = not on
	solid.visible = on
	solid.collision_layer = _layer if on else 0
	interactable.enabled = not on
	_update_prompt()
	# only the visible model grows in (scaling a physics body is asking for trouble)
	var model := solid.get_node_or_null("Model") as Node3D
	if model == null:
		return
	if on and animate:
		model.scale = Vector3(1.0, 0.05, 1.0)
		var tween := create_tween()
		tween.tween_property(model, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		model.scale = Vector3.ONE

func _update_prompt() -> void:
	interactable.prompt = "Print %s (%d scrap)" % [display_name, scrap_needed()]
