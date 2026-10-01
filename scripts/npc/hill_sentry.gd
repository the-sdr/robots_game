extends StaticBody3D

# The Hill Sentry: a guard robot on top of the hill, the first fight (a
# tutorial: on Easy it can't be lost). Reaching the crest starts the fight
# screen (scenes/combat/combat.tscn); this node is the enemy actor it drives:
# arena positions and animations. Beaten, it sits down beside the path for
# good (flag "defeated:hill_sentry"), green-eyed and friendly, and its broken
# shield plating lies beside it: a wreck to salvage (cutter or laser; the laser
# along the seam gets bonus parts) holding its reward (owner, 2026-09-30).

const COMBAT := preload("res://scenes/combat/combat.tscn")
# In this scene's frame at rest (placed at (3, -90) facing south, heading 180):
const ARENA_PLAYER := Vector3(2.6, 0, -4.4)      # world (0.4, -85.6): the crest
const ARENA_ENEMY := Vector3(2.6, 0, -0.6)       # world (0.4, -89.4)
const RETREAT := Vector3(3.0, 0, -10.5)          # world (0, -79.5): back down the hill
const EYE_ANGRY := Color(1.0, 0.35, 0.1)
const EYE_FRIENDLY := Color(0.35, 1.0, 0.45)
const WRECK := preload("res://scenes/props/wreck.tscn")
const SALVAGE_AT := Vector3(-1.8, 0, 1.2)        # beside where it sits, in its own frame
const SALVAGE_BONUS := {"scrap_metal": 2}        # extra for a laser salvage
const SEAM_GLOW := 3.0                            # the wreck's seam; its default 0.6 vanished at night

@export var enemy_id := "hill_sentry"

@onready var visual: Node3D = $Visual
@onready var eye: MeshInstance3D = $Visual/Head/Eye
@onready var pincer: Node3D = $Visual/PincerArm
@onready var shield: Node3D = $Visual/ShieldArm
@onready var trigger: Area3D = $Trigger
@onready var inspect: Interactable = $Inspect

var fighting := false
var _rest: Transform3D
var _eye_material: StandardMaterial3D
var _anim: Tween

func _ready() -> void:
	add_to_group("enemy")
	_rest = global_transform
	_eye_material = (eye.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	eye.set_surface_override_material(0, _eye_material)
	trigger.body_entered.connect(_on_body_entered)
	inspect.enabled = false
	if Game.get_flag(flag()):
		_sit_down(false)
		if not Game.get_flag(salvage_flag()):
			drop_salvage.call_deferred(false)

func flag() -> String:
	return "defeated:" + enemy_id

func salvage_flag() -> String:
	return "salvaged:" + enemy_id

## Its broken shield plating, beside it: a wreck holding its reward.
func drop_salvage(tell: bool = true) -> Node3D:
	if get_parent().has_node("Salvage_" + enemy_id):
		return get_parent().get_node("Salvage_" + enemy_id)
	var wreck: StaticBody3D = WRECK.instantiate()
	wreck.name = "Salvage_" + enemy_id
	wreck.set("drops", Catalog.ENEMIES[enemy_id].get("reward", {}))
	wreck.set("bonus", SALVAGE_BONUS)
	wreck.set("break_flag", salvage_flag())
	wreck.set("display_name", "its shield plating")
	wreck.set("hit_notice", "The Sentry's broken shield plating. A blade or a beam would get the parts out.")
	# On the ground (it floated or sank on the hill's slope), 0.75 size (setting
	# .scale before global_transform was silently undone), seam bright enough to
	# read at night (save_80: "I can't find any loot in the sentry").
	var spot := _ground(_rest * SALVAGE_AT)
	get_parent().add_child(wreck)
	wreck.global_transform = Transform3D(_rest.basis.scaled(Vector3.ONE * 0.75), spot)
	var seam: MeshInstance3D = wreck.get_node_or_null("Chassis/Seam")
	if seam != null:
		var glow: StandardMaterial3D = (seam.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		glow.emission_energy_multiplier = SEAM_GLOW
		seam.material_override = glow
	if tell:
		get_tree().call_group("hud", "show_notice", "Its shield plating fell off beside it. Cut it or beam its glowing seam for parts.")
	return wreck

## Beaten, a blade or a beam on the Sentry itself salvages its plating: the
## story says its parts are "in there", so that's where players aim (save_80).
func apply(effect: String, power: float, from: Vector3) -> bool:
	var wreck := _unsalvaged_wreck()
	return wreck.call("apply", effect, power, from) if wreck != null else false

func burn_at(point: Vector3, delta: float, from: Vector3, power: float) -> void:
	var wreck := _unsalvaged_wreck()
	if wreck != null:      # the beam's sweep across the Sentry sweeps the plating's seam
		wreck.call("burn_at", wreck.global_position + (point - global_position), delta, from, power)

func _unsalvaged_wreck() -> Node3D:
	if not Game.get_flag(flag()) or Game.get_flag(salvage_flag()):
		return null
	return get_parent().get_node_or_null("Salvage_" + enemy_id) as Node3D

func _on_body_entered(body: Node3D) -> void:
	if fighting or Game.get_flag(flag()) or not body.is_in_group("player"):
		return
	if body.get("shut_down") or body.get("in_combat") or body.get("docked"):
		return
	start_fight(body as CharacterBody3D)

## Opens the fight screen; returns it (tests drive it).
func start_fight(player: CharacterBody3D) -> Node:
	fighting = true
	var combat: Node = COMBAT.instantiate()
	add_child(combat)
	combat.finished.connect(func(_won: bool) -> void: fighting = false)
	combat.begin(player, self, enemy_id)
	return combat

# --- what the fight screen asks for ----------------------------------------------------------
func arena_player_position() -> Vector3:
	return _rest * ARENA_PLAYER

func retreat_position() -> Vector3:
	return _rest * RETREAT

## Rolls into the arena facing the player's spot; returns where it stopped.
func step_to_arena() -> Vector3:
	var target := _ground(_rest * ARENA_ENEMY)
	var facing := arena_player_position() - target
	var yaw := atan2(facing.x, facing.z) + PI
	_play()
	_anim.set_parallel(true)
	_anim.tween_property(self, "global_position", target, 0.8).set_trans(Tween.TRANS_SINE)
	_anim.tween_property(self, "global_rotation:y", yaw, 0.8)
	_set_eye(EYE_ANGRY, 3.0)
	await _anim.finished
	return global_position

func wind_up(seconds: float) -> void:
	_play()
	_anim.set_parallel(true)
	_anim.tween_property(visual, "rotation:x", 0.22, seconds * 0.8).set_trans(Tween.TRANS_SINE)
	_anim.tween_property(pincer, "rotation:x", 1.6, seconds * 0.8)
	_anim.tween_method(func(v: float) -> void: _eye_material.emission_energy_multiplier = v, 2.0, 6.0, seconds * 0.8)

func strike() -> void:
	_play()
	_anim.tween_property(visual, "rotation:x", -0.25, 0.08)
	_anim.parallel().tween_property(pincer, "rotation:x", -0.6, 0.08)
	_anim.parallel().tween_property(visual, "position:z", -0.6, 0.08)
	_anim.tween_property(visual, "rotation:x", 0.0, 0.3)
	_anim.parallel().tween_property(pincer, "rotation:x", 0.0, 0.3)
	_anim.parallel().tween_property(visual, "position:z", 0.0, 0.3)
	_anim.parallel().tween_method(func(v: float) -> void: _eye_material.emission_energy_multiplier = v, 6.0, 3.0, 0.3)

func flinch() -> void:
	var t := create_tween()
	for i in 4:
		t.tween_property(visual, "rotation:z", 0.08 * (1 if i % 2 == 0 else -1), 0.05)
	t.tween_property(visual, "rotation:z", 0.0, 0.05)
	t.parallel().tween_method(func(v: float) -> void: _eye_material.emission_energy_multiplier = v, 0.5, 3.0, 0.3)

## Beaten: rolls back beside the path and sits down for good.
func defeat() -> void:
	_play()
	_anim.set_parallel(true)
	_anim.tween_property(self, "global_position", _rest.origin, 0.9).set_trans(Tween.TRANS_SINE)
	_anim.tween_property(self, "global_rotation:y", _rest.basis.get_euler().y, 0.9)
	await _anim.finished
	_sit_down(true)

## After a loss: back to its post, ready for the next try.
func reset() -> void:
	_stop()
	global_transform = _rest
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	pincer.rotation = Vector3.ZERO
	shield.rotation = Vector3.ZERO
	_set_eye(EYE_ANGRY, 2.0)

func _sit_down(animate: bool) -> void:
	global_transform = _rest
	inspect.enabled = true
	_set_eye(EYE_FRIENDLY, 1.2)
	if not animate:
		visual.rotation.x = 0.3
		visual.position.y = -0.22
		pincer.rotation.x = 0.9
		shield.rotation.z = -0.4
		return
	_play()
	_anim.set_parallel(true)
	_anim.tween_property(visual, "rotation:x", 0.3, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_anim.tween_property(visual, "position:y", -0.22, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_anim.tween_property(pincer, "rotation:x", 0.9, 0.6)
	_anim.tween_property(shield, "rotation:z", -0.4, 0.6)

func _set_eye(colour: Color, energy: float) -> void:
	_eye_material.emission = colour
	_eye_material.albedo_color = colour
	_eye_material.emission_energy_multiplier = energy

func _play() -> void:
	_stop()
	_anim = create_tween()

func _stop() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()

func _ground(pos: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 8, 0), pos + Vector3(0, -12, 0))
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return (hit["position"] as Vector3) if not hit.is_empty() else pos
