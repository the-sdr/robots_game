extends CanvasLayer

# The fight screen: turn-based robot combat on the live world (an enemy node
# like the hill sentry starts it with begin()). Rules and numbers are in
# combat_state.gd / Catalog / Settings; this script runs the turns, reads the
# keys, draws the timing ring and animates both robots.
#
# Keys (Input Map): combat_slot_1..3 use the fight kit's tools (Game.loadout);
# hold move_forward (W) or move_back (S) with one for that tool's other moves;
# combat_timing (Space / A) presses on the beat, and the slot key works too.
# Tests drive it through input_move() / input_timing() and read `phase`.

signal finished(won: bool)

const State := preload("res://scripts/combat/combat_state.gd")
const ATTACK_RING := 0.9      # seconds the attack ring takes to close at normal speed
const NEXT_HIT_RING := 0.55   # later hits of a combo come faster
const RING_START := 170.0
const RING_TARGET := 46.0

var state = State.new()
var player: CharacterBody3D
var enemy_node: Node3D           # the enemy actor (hill_sentry.gd): arena positions and animations
var enemy_id := ""
var enemy_name := ""
## "intro", "choose", "timing", "busy", "done". Tests wait on it.
var phase := ""
var aborted := false

var _kit: Array[String] = []
var _chosen := {}
var _beat_at := 0.0
var _beat_t := 0.0
var _press_offset := INF
var _awaiting := false
var _defending := false
var _tips := {}
var _equipped_before := ""
var _camera: Camera3D
var _player_start := Transform3D()

var _root: Control
var _enemy_bar: ProgressBar
var _player_bar: ProgressBar
var _enemy_label: Label
var _player_label: Label
var _message: Label
var _hint: Label
var _now: Label
var _ring: Control
var _ring_key: Label
var _cards: Array[PanelContainer] = []
var _card_labels: Array[Label] = []

# --- start ------------------------------------------------------------------------------
func begin(p: CharacterBody3D, enemy: Node3D, id: String) -> void:
	player = p
	enemy_node = enemy
	enemy_id = id
	var def: Dictionary = Catalog.ENEMIES[id]
	enemy_name = String(def["name"])
	state.start(def, Settings.tuning(), Catalog.PLAYER_HEALTH)
	_kit = Game.loadout()
	_equipped_before = String(Game.data["equipped_tool"])
	player.set("in_combat", true)
	player.velocity = Vector3.ZERO
	Energy.depleted.connect(_on_battery_dead)
	_build_ui()
	_refresh()
	_run()

func _run() -> void:
	phase = "intro"
	_say("%s wants a fight!" % enemy_name)
	_tip("intro", "Fights take turns. On your turn press 1, 2 or 3 to use a tool from your fight kit.")
	await _place_fighters()
	while state.outcome == "" and not aborted:
		await _player_turn()
		if state.outcome != "" or aborted:
			break
		await _enemy_turn()
	await _finish()

# --- turns ------------------------------------------------------------------------------
func _player_turn() -> void:
	phase = "choose"
	_chosen = {}
	_tip("choose", "Your turn! Press 1, 2 or 3. Hold W or S at the same time for a different move.")
	_highlight(-1)
	while _chosen.is_empty() and not aborted:
		await get_tree().process_frame
	if aborted:
		return
	phase = "busy"
	var tool_id: String = _chosen["tool"]
	var move: Dictionary = _chosen["move"]
	_highlight(int(_chosen["slot"]))
	var cost := float(move.get("energy", 0.0))
	var weak := false
	if cost > 0.0:
		if Energy.current >= cost:
			Energy.spend(cost)
		else:
			weak = true
	_say("%s%s!" % [move["name"], " (low battery: weak)" if weak else ""])
	_show_tool(tool_id)
	var qualities := []
	if String(move["kind"]) == "attack":
		_tip("attack", "Press SPACE when the ring touches the circle! Perfect timing hits harder.")
		for i in int(move.get("hits", 1)):
			var q := await _timing(state.ring_seconds(ATTACK_RING if i == 0 else NEXT_HIT_RING), false)
			if aborted:
				return
			qualities.append(q)
			_player_lunge()
			_popup({"perfect": "PERFECT!", "good": "Good", "miss": "Miss..."}[q], enemy_node.global_position + Vector3(0, 2.6, 0), Color(1, 0.9, 0.3))
			await _wait(0.25)
	var result: Dictionary = state.player_move(move, qualities, weak)
	match String(move["kind"]):
		"attack":
			_popup(str(result["damage"]), enemy_node.global_position + Vector3(0, 2.2, 0), Color(1, 0.4, 0.3))
			enemy_node.call("flinch")
		"guard":
			_say("%s: ready for the next blow." % move["name"])
		"evade":
			_say("%s: it will miss you!" % move["name"])
		"stun":
			_say("%s! %s can't see." % [move["name"], enemy_name])
			enemy_node.call("flinch")
		"repair":
			_popup("+%d" % result["healed"], player.global_position + Vector3(0, 1.8, 0), Color(0.4, 1, 0.5))
	_refresh()
	await _wait(0.7)

func _enemy_turn() -> void:
	phase = "busy"
	var attack: Dictionary = state.next_attack()
	if attack.is_empty():
		_say("%s is dazzled and misses its turn!" % enemy_name)
		state.enemy_move([])
		await _wait(1.2)
		return
	_say("%s: %s!" % [enemy_name, attack["name"]])
	_tip("defend", "It's winding up! Press SPACE just as the ring closes to dodge.")
	var qualities := []
	for i in int(attack.get("hits", 1)):
		var seconds: float = state.ring_seconds(float(attack["wind_up"]) if i == 0 else NEXT_HIT_RING)
		enemy_node.call("wind_up", seconds)
		var q := await _timing(seconds, true)
		if aborted:
			return
		qualities.append(q)
		enemy_node.call("strike")
		if q == "perfect":
			_player_dodge()
			_popup("DODGED!", player.global_position + Vector3(0, 1.9, 0), Color(0.5, 1, 0.6))
		else:
			_player_hit()
			_popup("Blocked" if q == "good" else "Ouch!", player.global_position + Vector3(0, 1.9, 0), Color(1, 0.8, 0.4) if q == "good" else Color(1, 0.4, 0.3))
		await _wait(0.3)
	var result: Dictionary = state.enemy_move(qualities)
	if int(result["damage"]) > 0:
		_popup("-%d" % result["damage"], player.global_position + Vector3(0, 1.5, 0), Color(1, 0.35, 0.3))
	if int(result["countered"]) > 0:
		_popup("Counter %d" % result["countered"], enemy_node.global_position + Vector3(0, 2.2, 0), Color(0.5, 0.9, 1))
		enemy_node.call("flinch")
	_refresh()
	await _wait(0.7)

## One timing press: the ring closes over `seconds`; returns the quality.
func _timing(seconds: float, defend: bool) -> String:
	_defending = defend
	_beat_at = seconds
	_beat_t = 0.0
	_press_offset = INF
	_awaiting = true
	phase = "timing"
	_ring.visible = true
	var window: float = float(state.tuning["defend_window"]) * 2.0 if defend else float(state.tuning["good_window"])
	var cue := bool(state.tuning["now_cue"])
	while _awaiting and _beat_t < seconds + window and not aborted:
		await get_tree().process_frame
		if not get_tree().paused:
			_beat_t += get_process_delta_time()
		_ring.set("progress", _beat_t / seconds)
		_ring.set("in_window", absf(_beat_t - seconds) <= (float(state.tuning["defend_window"]) if defend else window))
		_ring.queue_redraw()
		_now.visible = cue and absf(_beat_t - seconds) <= window
	_awaiting = false
	_ring.visible = false
	_now.visible = false
	phase = "busy"
	return state.defence_quality(_press_offset) if defend else state.quality(_press_offset)

## Seconds until the current beat (negative once it has passed); tests press on it.
func seconds_to_beat() -> float:
	return _beat_at - _beat_t

# --- input ------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if phase == "choose":
		for n in 3:
			if event.is_action_pressed("combat_slot_%d" % (n + 1), false, true):
				input_move(n, _direction())
				get_viewport().set_input_as_handled()
				return
	elif phase == "timing":
		var pressed := event.is_action_pressed("combat_timing", false, true)
		for n in 3:
			pressed = pressed or event.is_action_pressed("combat_slot_%d" % (n + 1), false, true)
		if pressed:
			input_timing()
			get_viewport().set_input_as_handled()

func _direction() -> String:
	if Input.is_action_pressed("move_forward"):
		return "forward"
	if Input.is_action_pressed("move_back"):
		return "back"
	return ""

## Pick slot 0-2's tool with a direction ("", "forward", "back"). False if the slot is empty.
func input_move(slot: int, direction: String) -> bool:
	if phase != "choose":
		return false
	var tool_id: String = _kit[slot] if slot < _kit.size() else ""
	if tool_id == "" and _kit.any(func(t: String) -> bool: return t != ""):
		_say("Slot %d is empty. Put a tool in it on the Tab screen." % (slot + 1))
		return false
	_chosen = {"slot": slot, "tool": tool_id, "move": Catalog.move(tool_id, direction)}
	return true

## The timing press (Space / A, or the slot key again).
func input_timing() -> void:
	if _awaiting:
		_press_offset = _beat_t - _beat_at
		_awaiting = false

# --- the end ------------------------------------------------------------------------------
func _finish() -> void:
	phase = "done"
	var won: bool = state.outcome == "won"
	var def: Dictionary = Catalog.ENEMIES[enemy_id]
	if won:
		_say("You win! %s powers down." % enemy_name)
		Game.set_flag("defeated:" + enemy_id, true)
		for item in def.get("reward", {}):
			Game.add_item(item, int(def["reward"][item]))
			get_tree().call_group("hud", "show_notice", "Took %s" % Catalog.item_name(item))
		enemy_node.call("defeat")
		await _wait(1.6)
		Story.play("sentry_won")
	elif not aborted:
		_say("Knocked down the hill! Walk back up to try again.")
		await _wait(1.8)
		var back: Vector3 = enemy_node.call("retreat_position")
		player.global_position = _ground(back)
		enemy_node.call("reset")
	_restore()
	finished.emit(won)
	queue_free()

func _restore() -> void:
	if Energy.depleted.is_connected(_on_battery_dead):
		Energy.depleted.disconnect(_on_battery_dead)
	player.set("in_combat", false)
	player.visual.position = Vector3.ZERO
	var cam: Camera3D = player.get("camera")
	if cam != null:
		cam.make_current()
	if _camera != null:
		_camera.queue_free()
	if Game.has_tool(_equipped_before) or _equipped_before == "":
		Game.data["equipped_tool"] = _equipped_before
		Game.inventory_changed.emit()
	_root.visible = false

func _on_battery_dead() -> void:
	aborted = true           # the world shuts the robot down and reboots it at its last charger

# --- staging and animation ------------------------------------------------------------------
func _place_fighters() -> void:
	var p_pos: Vector3 = _ground(enemy_node.call("arena_player_position"))
	player.global_position = p_pos
	var e_pos: Vector3 = await enemy_node.step_to_arena()
	var to_enemy := e_pos - p_pos
	player.visual.global_rotation.y = atan2(to_enemy.x, to_enemy.z) + PI
	_camera = Camera3D.new()
	_camera.fov = 55.0
	enemy_node.get_parent().add_child(_camera)
	var mid := (p_pos + e_pos) * 0.5 + Vector3(0, 0.9, 0)
	var side := Vector3(to_enemy.x, 0, to_enemy.z).cross(Vector3.UP).normalized()
	if side.x < 0.0:
		side = -side
	_camera.look_at_from_position(mid + side * 5.2 + Vector3(0, 1.4, 0), mid)
	_camera.make_current()
	await _wait(0.4)

func _ground(pos: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 8, 0), pos + Vector3(0, -12, 0))
	ray.exclude = [player.get_rid(), enemy_node.get_rid()]
	var hit := space.intersect_ray(ray)
	return (hit["position"] as Vector3) + Vector3(0, 0.05, 0) if not hit.is_empty() else pos

func _show_tool(tool_id: String) -> void:
	if tool_id != "" and Game.data["equipped_tool"] != tool_id:
		Game.data["equipped_tool"] = tool_id
		Game.inventory_changed.emit()

func _player_lunge() -> void:
	var rig: Node = player.get("tool_rig")
	if rig != null and rig.has_method("swing"):
		rig.swing()
	var t := create_tween()
	t.tween_property(player.visual, "position", Vector3(0, 0, -0.5).rotated(Vector3.UP, player.visual.rotation.y), 0.12)
	t.tween_property(player.visual, "position", Vector3.ZERO, 0.2)

func _player_dodge() -> void:
	var t := create_tween()
	t.tween_property(player.visual, "position", Vector3(0.6, 0.35, 0).rotated(Vector3.UP, player.visual.rotation.y), 0.12)
	t.tween_property(player.visual, "position", Vector3.ZERO, 0.25)

func _player_hit() -> void:
	var t := create_tween()
	t.tween_property(player.visual, "position", Vector3(0, 0, 0.35).rotated(Vector3.UP, player.visual.rotation.y), 0.08)
	t.tween_property(player.visual, "position", Vector3.ZERO, 0.25)

## A floating word or number in the world that rises and fades.
func _popup(text: String, at: Vector3, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = colour
	label.no_depth_test = true
	enemy_node.get_parent().add_child(label)
	label.global_position = at
	var t := label.create_tween().set_parallel(true)
	t.tween_property(label, "global_position", at + Vector3(0, 0.7, 0), 1.0)
	t.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.4)
	t.chain().tween_callback(label.queue_free)

func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not aborted:
		await get_tree().process_frame
		if not get_tree().paused:
			left -= get_process_delta_time()

# --- the screen ------------------------------------------------------------------------------
func _say(text: String) -> void:
	if _message != null:
		_message.text = text

## A how-to line: every time on Easy (it has the big cues), once per fight otherwise.
func _tip(id: String, text: String) -> void:
	if bool(state.tuning.get("now_cue", false)) or not _tips.has(id):
		_tips[id] = true
		_hint.text = text

func _refresh() -> void:
	_enemy_bar.max_value = state.enemy_max
	_enemy_bar.value = state.enemy_hp
	_enemy_label.text = "%s   %d / %d" % [enemy_name, roundi(state.enemy_hp), roundi(state.enemy_max)]
	_player_bar.max_value = state.player_max
	_player_bar.value = state.player_hp
	_player_label.text = "Your robot   %d / %d" % [roundi(state.player_hp), roundi(state.player_max)]
	for i in 3:
		var tool_id: String = _kit[i] if i < _kit.size() else ""
		if tool_id == "":
			_card_labels[i].text = "[%d]  (empty)\nTab: add a tool" % (i + 1)
			continue
		var m0 := Catalog.move(tool_id, "")
		var mf := Catalog.move(tool_id, "forward")
		var mb := Catalog.move(tool_id, "back")
		_card_labels[i].text = "[%d]  %s\n%s\nW+%d  %s\nS+%d  %s" % [i + 1, Catalog.tool_name(tool_id), m0["name"], i + 1, mf["name"], i + 1, mb["name"]]

func _highlight(slot: int) -> void:
	for i in _cards.size():
		_cards[i].modulate = Color(1.25, 1.2, 0.8) if i == slot else Color(1, 1, 1)

func _panel_style(colour: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	return s

func _bar(colour: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 22)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(5)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	back.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar

func _label(text: String, size: int, colour: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _anchor(c: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom

func _build_ui() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# enemy health, top centre
	var top := VBoxContainer.new()
	_root.add_child(top)
	_anchor(top, Control.PRESET_CENTER_TOP, -220, 14, 220, 70)
	_enemy_label = _label("", 22, Color(1, 0.75, 0.6))
	top.add_child(_enemy_label)
	_enemy_bar = _bar(Color(0.9, 0.3, 0.2), 440)
	top.add_child(_enemy_bar)
	_message = _label("", 26)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_message)
	_anchor(_message, Control.PRESET_CENTER_TOP, -380, 88, 380, 128)
	_hint = _label("", 20, Color(1, 0.92, 0.5))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_hint)
	_anchor(_hint, Control.PRESET_CENTER_TOP, -380, 130, 380, 190)
	# the timing ring, centre
	_ring = TimingRing.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_root.add_child(_ring)
	_anchor(_ring, Control.PRESET_CENTER, -180, -180, 180, 180)
	_ring_key = _label("SPACE", 22)
	_ring.add_child(_ring_key)
	_anchor(_ring_key, Control.PRESET_TOP_LEFT, 0, 165, 360, 195)
	_now = _label("NOW!", 72, Color(1, 0.95, 0.3))
	_now.visible = false
	_root.add_child(_now)
	_anchor(_now, Control.PRESET_CENTER, -150, 150, 150, 240)
	# your robot's health, bottom left
	var mine := VBoxContainer.new()
	_root.add_child(mine)
	_anchor(mine, Control.PRESET_BOTTOM_LEFT, 16, -214, 340, -156)
	_player_label = _label("", 20, Color(0.7, 1, 0.75))
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mine.add_child(_player_label)
	_player_bar = _bar(Color(0.3, 0.9, 0.45), 320)
	mine.add_child(_player_bar)
	# the fight kit, bottom centre
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	_root.add_child(cards)
	_anchor(cards, Control.PRESET_CENTER_BOTTOM, -405, -150, 405, -14)
	for i in 3:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(262, 128)
		card.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.1, 0.85)))
		var text := _label("", 17)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_child(text)
		cards.add_child(card)
		_cards.append(card)
		_card_labels.append(text)

## The timing ring: a fixed circle and a ring closing onto it. Gold while
## closing, green inside the window.
class TimingRing extends Control:
	var progress := 0.0
	var in_window := false

	func _draw() -> void:
		var c := size * 0.5
		var r: float = lerpf(170.0, 46.0, clampf(progress, 0.0, 1.25))
		draw_circle(c, 46.0, Color(0, 0, 0, 0.35))
		draw_arc(c, 46.0, 0.0, TAU, 48, Color(1, 1, 1, 0.95), 6.0, true)
		draw_arc(c, maxf(r, 8.0), 0.0, TAU, 64, Color(0.4, 1, 0.5) if in_window else Color(1, 0.8, 0.25), 8.0, true)
