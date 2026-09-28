extends Node

# The opening cutscene (New Game only; the owner's shot list, PROJECT_VISION.md
# "Opening cutscene"), played inside the real world with the game's own models:
#   1. establishing shot over the forest, pushing in towards the house;
#   2. the house roof: a board lies across it, precarious; a bird flies in
#   3. and lands on it: it wobbles;
#   4. close-up of the bird: it looks round and takes off;
#   5. the board tips and slides off: a solar panel underneath catches the sun;
#   6. close-up of the dock: the charge bar lights, one ring blinking;
#   7. extreme close-up of the robot's face: the iris in its lens opens slightly.
# Space / Enter / Esc / a click skips. World.gd starts it and plays the wake
# beat after `finished`. The board ends where world.tscn put it (on the ground).

signal finished

const BIRD := preload("res://scenes/props/bird.tscn")
const BOARD_ROOF_POS := Vector3(0.3, 4.03, -2.37)      # resting on the south rim of the flat roof
const BOARD_ROOF_TILT := 12.2                          # degrees: its far end lies on the solar frame's high edge
const BOARD_ROOF_YAW := 8.0

var world: Node3D
var player: CharacterBody3D
var board: Node3D
var roof_solar: Node3D
var charger: Node3D
var hud: CanvasLayer
var bird: Node3D
var cam: Camera3D
## True once the cutscene has handed control back (tests wait on it).
var done := false

var _skip := false
var _tweens: Array[Tween] = []
var _board_ground: Transform3D
var _stored_before := 0.0
var _layer: CanvasLayer
var _fade: ColorRect
var _cells: StandardMaterial3D
var _glint: OmniLight3D

func play(p_world: Node3D) -> void:
	world = p_world
	player = world.get_node("Player")
	board = world.get_node("FallenBoard")
	roof_solar = world.get_node("RoofSolar")
	charger = world.get_node("HouseCharger")
	hud = world.get_node("HUD")
	_cells = (roof_solar.get_node("Panel/Cells") as MeshInstance3D).mesh.surface_get_material(0)
	_glint = roof_solar.get_node("GlintLight")
	_board_ground = board.global_transform
	Clock.running = false
	hud.visible = false
	player.set("shut_down", true)          # asleep: no lights, no driving, until the last shot
	player.call("set_iris", 0.0)
	_stored_before = charger.get("stored")
	charger.set("stored", 0.0)
	board.global_transform = _board_on_roof()
	cam = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.make_current()
	_build_layer()
	await _run()
	_finish()

func _run() -> void:
	# 1. establishing: over the treetops towards the house
	await _camera_move(Vector3(4, 16, 14), Vector3(0, 3, -8), Vector3(3, 13, 7), Vector3(0, 3.2, -6), 5.0)
	if _skip:
		return
	# 2. the roof from over the house's north side; a bird comes in over the garden
	var land := board.global_transform * Vector3(0.0, 0.05, 0.35)
	_camera_hold(Vector3(3.0, 6.5, -6.6), Vector3(0.4, 4.0, -2.6))
	bird = BIRD.instantiate()
	world.add_child(bird)
	bird.scale = Vector3.ONE * 1.3
	bird.global_position = Vector3(-6.0, 8.5, 6.0)
	bird.look_at(land, Vector3.UP)
	bird.flapping = true
	var fly := _tween()
	fly.tween_property(bird, "global_position", land + Vector3(0, 0.6, 0.4), 1.9).set_trans(Tween.TRANS_SINE)
	fly.tween_property(bird, "global_position", land, 0.4).set_ease(Tween.EASE_OUT)
	await _wait(2.3)
	if _skip:
		return
	# 3. it lands: the board wobbles (the bird rides it)
	bird.flapping = false
	var face_north := bird.global_transform.looking_at(bird.global_position + Vector3(0.3, 0, -1), Vector3.UP)
	bird.global_transform = face_north.scaled_local(Vector3.ONE * 1.3)
	bird.reparent(board)
	var wobble := _tween()
	for angle in [17.0, 9.0, 15.0, 10.5, 13.0, BOARD_ROOF_TILT]:
		wobble.tween_property(board, "rotation_degrees:x", angle, 0.22).set_trans(Tween.TRANS_SINE)
	await _wait(1.6)
	if _skip:
		return
	# 4. close-up: it looks round, and goes
	var head := bird.global_position + Vector3(0, 0.25, 0)
	_camera_hold(head + Vector3(0.55, 0.2, -0.75), head)
	await _wait(0.4)
	var look: Tween = bird.look_around()
	_tweens.append(look)
	await _wait(1.3)
	if _skip:
		return
	bird.reparent(world)
	bird.flapping = true
	bird.look_at(Vector3(-8, 10, 6), Vector3.UP)
	var away := _tween()
	away.tween_property(bird, "global_position", bird.global_position + Vector3(-7, 6, 7), 1.6).set_ease(Tween.EASE_IN)
	var kick := _tween()                    # the push as it leaves
	kick.tween_property(board, "rotation_degrees:x", 18.0, 0.15)
	await _wait(0.9)
	if _skip:
		return
	# 5. the board tips and slides off the edge; the panel underneath catches the sun
	_camera_hold(Vector3(2.8, 6.0, -5.6), Vector3(0.3, 3.9, -2.6))
	var fall := _tween()
	fall.tween_property(board, "rotation_degrees:x", 45.0, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall.tween_property(board, "global_transform", _board_ground, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await _wait(1.3)
	if _skip:
		return
	_glint.visible = true
	var shine := _tween().set_parallel(true)
	shine.tween_property(_cells, "emission_energy_multiplier", 2.5, 0.25)
	shine.tween_property(_glint, "light_energy", 3.0, 0.25)
	shine.chain().tween_property(_cells, "emission_energy_multiplier", 0.0, 1.0)
	shine.tween_property(_glint, "light_energy", 0.0, 1.0)
	await _wait(1.8)
	if _skip:
		return
	# 6. the dock: sunlight reaches it, the bar lights, one ring blinking
	var post: Vector3 = charger.global_position
	_camera_hold(post + Vector3(0.7, 0.72, 0.55), post + Vector3(0, 0.62, 0))
	await _wait(0.7)
	charger.set("stored", float(charger.call("effective_capacity")) * 0.1)
	await _wait(2.3)
	if _skip:
		return
	# 7. the robot's face, very close: the iris opens, a little
	var lens: Node3D = player.get_node("Visual/Head/LensLeft")
	var forward: Vector3 = -(player.get_node("Visual") as Node3D).global_transform.basis.z
	cam.fov = 35.0
	_camera_hold(lens.global_position + forward * 0.28 + Vector3(0, 0.015, 0), lens.global_position)
	await _wait(0.8)
	player.set("shut_down", false)          # the eye lights up
	var iris := _tween()
	iris.tween_method(func(v: float) -> void: player.call("set_iris", v), 0.0, 0.35, 0.9).set_trans(Tween.TRANS_SINE)
	await _wait(1.8)
	var fade := _tween()
	fade.tween_property(_fade, "color:a", 1.0, 0.6)
	await _wait(0.7)

# --- camera --------------------------------------------------------------------------------
func _camera_hold(pos: Vector3, target: Vector3) -> void:
	cam.look_at_from_position(pos, target, Vector3.UP)

func _camera_move(from_pos: Vector3, from_target: Vector3, to_pos: Vector3, to_target: Vector3, seconds: float) -> void:
	_camera_hold(from_pos, from_target)
	var t := _tween()
	t.tween_method(func(k: float) -> void: _camera_hold(from_pos.lerp(to_pos, k), from_target.lerp(to_target, k)), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)
	await _wait(seconds)

# --- skipping and cleaning up ----------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	var skip := event.is_action_pressed("pause") or event.is_action_pressed("jump") or event.is_action_pressed("interact") \
		or event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if skip:
		_skip = true
		get_viewport().set_input_as_handled()

## Puts everything where the game expects it, whether the cutscene ran to the end or was skipped.
func _finish() -> void:
	for t in _tweens:
		if t.is_valid():
			t.kill()
	if is_instance_valid(bird):
		bird.queue_free()
	board.global_transform = _board_ground
	_cells.emission_energy_multiplier = 0.0
	_glint.light_energy = 0.0
	_glint.visible = false
	charger.set("stored", _stored_before)
	player.set("shut_down", false)
	var cam_player: Camera3D = player.get("camera")
	cam_player.make_current()
	cam.queue_free()
	hud.visible = true
	Clock.running = true
	Game.set_flag("intro_seen", true)
	done = true
	finished.emit()
	# fade in from black while the iris opens the rest of the way
	var t := _layer.create_tween().set_parallel(true)
	t.tween_property(_fade, "color:a", 0.0, 0.6)
	t.tween_method(func(v: float) -> void: player.call("set_iris", v), float(player.get("iris_open")), 1.0, 0.8)
	for bar in [_layer.get_node("Top"), _layer.get_node("Bottom"), _layer.get_node("Skip")]:
		t.tween_property(bar, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(queue_free)

func _board_on_roof() -> Transform3D:
	var e := Vector3(deg_to_rad(BOARD_ROOF_TILT), deg_to_rad(BOARD_ROOF_YAW), 0.0)
	return Transform3D(Basis.from_euler(e), BOARD_ROOF_POS)

func _tween() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t

func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 25
	add_child(_layer)
	for bar_name in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = bar_name
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if bar_name == "Top":
			bar.anchor_bottom = 0.11
		else:
			bar.anchor_top = 0.89
			bar.anchor_bottom = 1.0
		_layer.add_child(bar)
	var hint := Label.new()
	hint.name = "Skip"
	hint.text = "Space / Esc: skip"
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -200
	hint.offset_top = -40
	hint.offset_right = -16
	hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(hint)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_layer.add_child(_fade)
