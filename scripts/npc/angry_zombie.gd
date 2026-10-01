extends StaticBody3D

# The Angry Zombie (crooked house, the owner's son's Easter egg). He can't be
# hurt and never attacks on his own. Poke him (E) and he gets angrier; the
# third poke, or any tool hit, and he roars and zaps the robot with the tiny
# curse (Game.curse_tiny: two in-game days). While the robot is tiny he just
# laughs at it. His anger cools off if he's left alone for a while.

signal cursed

const POKES_TO_CURSE := 3
const CALM_DOWN_SECONDS := 20.0
const ZAP_SECONDS := 0.7
const SKIN := Color(0.45, 0.66, 0.36)
const ANGRY_SKIN := Color(0.85, 0.35, 0.25)

@onready var visual: Node3D = $Visual
@onready var interactable: Interactable = $Interactable
@onready var arm_left: Node3D = $Visual/ArmLeft
@onready var arm_right: Node3D = $Visual/ArmRight
@onready var head: Node3D = $Visual/Head
@onready var brow: Node3D = $Visual/Head/Brow
@onready var zap_light: OmniLight3D = $ZapLight

var pokes := 0
var _calm_timer := 0.0
var _shake := 0.0
var _laugh := 0.0
var _time := 0.0
var _zapping := false
var _skin_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("zombie")
	interactable.prompt = "Poke Angry Zombie"
	interactable.interacted.connect(poke)
	_skin_material = ($Visual/Head/Face as MeshInstance3D).get_surface_override_material(0)
	zap_light.light_energy = 0.0

func _process(delta: float) -> void:
	_time += delta
	if pokes > 0 and not _zapping:
		_calm_timer -= delta
		if _calm_timer <= 0.0:
			pokes = 0
	var anger := float(pokes) / float(POKES_TO_CURSE)
	_skin_material.albedo_color = SKIN.lerp(ANGRY_SKIN, anger)
	brow.rotation.z = 0.1 + 0.25 * anger
	# idle: a slow zombie sway with arms out; angry: a shake; laughing: a bounce
	_shake = maxf(_shake - delta, 0.0)
	_laugh = maxf(_laugh - delta, 0.0)
	var sway := sin(_time * 1.3) * 0.06
	visual.rotation.z = sway + (sin(_time * 55.0) * 0.06 * _shake)
	visual.position.y = absf(sin(_time * 14.0)) * 0.12 * minf(_laugh, 1.0)
	arm_left.rotation.x = 1.35 + sin(_time * 1.7) * 0.12
	arm_right.rotation.x = 1.35 + sin(_time * 1.7 + 1.0) * 0.12
	head.rotation.y = sin(_time * 0.6) * 0.25

## E: one poke. Returns true once the curse is cast.
func poke(player: Node3D = null) -> bool:
	if _zapping:
		return false
	if Game.is_tiny():
		_laugh_at_tiny()
		return false
	Story.play("zombie")
	Sfx.play("squeak")
	pokes += 1
	_calm_timer = CALM_DOWN_SECONDS
	_shake = 0.3 + 0.3 * pokes
	match pokes:
		1:
			_say("Angry Zombie: \"Grrr.\"")
		2:
			_say("Angry Zombie: \"GRRRR! Stop poking me!\"")
		_:
			_curse(player)
			return true
	return false

## A tool hit (the tool rig calls this like it would on a Breakable). He takes
## no damage, but that was the last straw.
func apply(_effect: String, _power: float, _from: Vector3) -> bool:
	if _zapping:
		return true
	if Game.is_tiny():
		_laugh_at_tiny()
		return true
	Story.play("zombie")
	_curse(get_tree().get_first_node_in_group("player") as Node3D)
	return true

func _laugh_at_tiny() -> void:
	_laugh = 1.2
	_say("Angry Zombie laughs: \"Heh heh heh. Tiny robot!\"")

func _say(text: String) -> void:
	get_tree().call_group("hud", "show_notice", text)

func _curse(player: Node3D) -> void:
	_zapping = true
	_shake = 1.2
	_say("Angry Zombie: \"ROOOAAAR!\"")
	Sfx.play("wahwah")
	var beam := _zap_beam(player)
	var tween := create_tween()
	tween.tween_property(zap_light, "light_energy", 6.0, 0.08)
	tween.tween_property(zap_light, "light_energy", 0.0, ZAP_SECONDS)
	await get_tree().create_timer(ZAP_SECONDS * 0.5).timeout
	Game.curse_tiny()
	Story.play("tiny")
	cursed.emit()
	if beam != null:
		beam.queue_free()
	pokes = 0
	_zapping = false

## A green zap from his hands to the robot: a thin glowing rod, gone in a moment.
func _zap_beam(player: Node3D) -> MeshInstance3D:
	if player == null:
		return null
	var from := global_position + Vector3(0, 1.1, 0)
	var to := player.global_position + Vector3(0, 0.5, 0)
	var length := from.distance_to(to)
	if length < 0.1:
		return null
	var rod := CylinderMesh.new()
	rod.top_radius = 0.035
	rod.bottom_radius = 0.035
	rod.height = length
	rod.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.5, 1.0, 0.3)
	material.emission_enabled = true
	material.emission = Color(0.5, 1.0, 0.3)
	material.emission_energy_multiplier = 3.0
	rod.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = rod
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	var mid := (from + to) * 0.5
	var up := (to - from).normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	mi.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), mid)
	return mi
