extends StaticBody3D

# The old zombie robot (Serious mode, in the crooked house where Silly has the
# Angry Zombie; owner, 2026-10-02): an ancient, rusted robot of the player's
# own make, barely working. Its battery is flat. It can't fight. Talk to it (E)
# and it mumbles; share a quarter of your battery and it wakes far enough to
# talk, gives you what it kept in the wardrobe (the sun tracker, which Silly
# hides behind the mouse hole) and leaves a memory for the memory system
# (flag "memory:zombie_robot"). Its model is a copy of the player's own,
# painted with rust, slumped, one arm hanging, one tread off, one lens dead.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PAINT := preload("res://scripts/robot_paint.gd")
const SHARE := 25.0              # battery given (Energy.MAX is 100)
const KEEP := 10.0               # it won't take your last bit
const WOKE_FLAG := "woke:zombie_robot"
const MEMORY_FLAG := "memory:zombie_robot"
const GIFT := "sun_tracker"
const LENS_DEAD := Color(0.04, 0.03, 0.03)
const LENS_GLOW := Color(1.0, 0.55, 0.2)
const MUMBLES := [
	"Old robot: \"...unit... unit four... nobody came...\"",
	"Old robot: \"...waiting... told to wait... power... low...\"",
	"Old robot: \"...k... kkkh...\" Its one lens flickers at you.",
]
const AWAKE_LINES := [
	"Old robot: \"Go north. The relay still calls. Don't wait like I did.\"",
	"Old robot: \"Your serial number is mine, plus one. Think about that.\"",
	"Old robot: \"She'll not be coming back. I know that now.\"",
]

@onready var interactable: Interactable = $Interactable

var visual: Node3D
var awake := false
var _talks := 0
var _time := 0.0
var _lens: StandardMaterial3D
var _head: Node3D
var _head_rest := 0.0

func _ready() -> void:
	add_to_group("zombie_robot")
	visual = build_model()
	add_child(visual)
	_pose()
	interactable.interacted.connect(talk)
	awake = Game.get_flag(WOKE_FLAG)
	if awake:
		_wake_pose(false)
	_refresh_prompt()

## The player's own model, without its tool rig and headlight, painted with rust.
static func build_model() -> Node3D:
	var donor: Node = PLAYER_SCENE.instantiate()      # never enters the tree: no player logic runs
	var model: Node3D = donor.get_node("Visual")
	donor.remove_child(model)
	donor.free()
	for path in ["ArmRight/ToolRig", "Head/Headlight"]:
		var part := model.get_node_or_null(path)
		if part != null:
			part.get_parent().remove_child(part)
			part.free()
	PAINT.apply(model, "rust")
	return model

## Slumped where it stopped: leaning forward, head down, left arm hanging, the
## right tread fallen off beside it, one lens dead.
func _pose() -> void:
	visual.rotation.x = -0.32
	visual.position.y = -0.06
	_head = visual.get_node("Head")
	_head.rotation.x = -0.55
	_head_rest = _head.rotation.x
	var arm: Node3D = visual.get_node("ArmLeft")
	arm.rotation = Vector3(0.35, 0.0, -0.2)
	var tread: Node3D = visual.get_node("TreadRight")
	tread.position += Vector3(0.28, -0.08, 0.12)
	tread.rotation = Vector3(0.0, 0.4, 1.35)
	var lens_mesh: Mesh = (visual.get_node("Head/LensLeft") as MeshInstance3D).mesh
	_lens = (lens_mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_lens.emission = LENS_GLOW
	_lens.emission_energy_multiplier = 0.4
	(visual.get_node("Head/LensLeft") as MeshInstance3D).material_override = _lens
	var dead := StandardMaterial3D.new()
	dead.albedo_color = LENS_DEAD
	dead.roughness = 0.3
	(visual.get_node("Head/LensRight") as MeshInstance3D).material_override = dead
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh.get_aabb().size.length() < 0.12:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # small parts: no shadow cost

func _process(delta: float) -> void:
	_time += delta
	if awake:
		_lens.emission_energy_multiplier = 1.6 + 0.2 * sin(_time * 1.3)
	else:      # a dying flicker: mostly dim, now and then a stutter
		var stutter := 1.0 if fmod(_time, 3.7) < 0.25 and sin(_time * 40.0) > 0.0 else 0.0
		_lens.emission_energy_multiplier = 0.25 + 0.15 * sin(_time * 2.1) + 1.4 * stutter

## E. Returns true when this talk woke it.
func talk(_player: Node3D = null) -> bool:
	if awake:
		_say(AWAKE_LINES[_talks % AWAKE_LINES.size()])
		_talks += 1
		return false
	if _talks == 0:
		_talks = 1
		Story.play("old_robot")
		_say(MUMBLES[0])
		_twitch()
		_refresh_prompt()
		return false
	if Energy.current - SHARE < KEEP:
		_say("Not enough battery to share. Charge up first.")
		_say(MUMBLES[_talks % MUMBLES.size()])
		_talks += 1
		return false
	Energy.spend(SHARE)
	_wake()
	return true

func _wake() -> void:
	awake = true
	_talks = 0
	Game.set_flag(WOKE_FLAG, true)
	Game.set_flag(MEMORY_FLAG, true)
	Game.add_item(GIFT)
	_say("Shared %d%% of your battery." % int(SHARE))
	_say("Received %s" % Catalog.item_name(GIFT))
	_wake_pose(true)
	Story.play("old_robot_wakes")
	_refresh_prompt()

func _wake_pose(animate: bool) -> void:
	var lift := _head_rest + 0.35
	if not animate:
		_head.rotation.x = lift
		return
	var t := create_tween()
	t.tween_property(_head, "rotation:x", lift + 0.15, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_head, "rotation:x", lift, 0.4)

func _twitch() -> void:
	var t := create_tween()
	t.tween_property(_head, "rotation:z", 0.12, 0.06)
	t.tween_property(_head, "rotation:z", -0.08, 0.06)
	t.tween_property(_head, "rotation:z", 0.0, 0.1)

func _refresh_prompt() -> void:
	if awake:
		interactable.prompt = "Talk to the old robot"
	elif _talks == 0:
		interactable.prompt = "Look at the old robot"
	else:
		interactable.prompt = "Share power (%d%%)" % int(SHARE)

func _say(text: String) -> void:
	get_tree().call_group("hud", "show_notice", text)
