extends CanvasLayer

# The fight screen: turn-based robot combat on the live world (an enemy node
# like the hill sentry starts it with begin()). Rules and numbers are in
# combat_state.gd / Catalog / Settings; this script runs the turns, reads the
# keys, draws the timing ring and animates both robots.
#
# Keys (Input Map): combat_slot_1..3 use the fight kit's tools (Game.loadout);
# hold move_forward (W) or move_back (S) with one for that tool's other moves;
# combat_timing (Space / A) presses on the beat, and the slot key works too.
# Tests drive it through input_move() / input_timing() / dismiss_coach() and
# read `phase`.
#
# Teaching (owner, 2026-09-30: "the whole fight needs to slow down with pop-ups
# to teach the player, let them know what's about to happen and what to
# press"): a coach panel stops the fight the first time each thing happens
# (saved flags "coach:<id>"), a banner announces every turn, and every attack
# gets a "get ready" beat. Every step also goes to the log ("fight: ..."), so a
# freeze shows where it happened (the Surface froze in a fight, 2026-09-30).

signal finished(won: bool)

const State := preload("res://scripts/combat/combat_state.gd")
const STYLE := preload("res://scripts/ui/ui_style.gd")
const BANNER_SECONDS := 1.1
const GET_READY_SECONDS := 1.0
const ATTACK_RING := 0.9      # seconds the attack ring takes to close at normal speed
const NEXT_HIT_RING := 0.55   # later hits of a combo come faster
const RING_START := 170.0
const RING_TARGET := 46.0

var state = State.new()
var player: CharacterBody3D
var enemy_node: Node3D           # the enemy actor (hill_sentry.gd): arena positions and animations
var enemy_id := ""
var enemy_name := ""
## "intro", "coach", "choose", "timing", "busy", "done". Tests wait on it.
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
var _coach_panel: PanelContainer
var _coach_title: Label
var _coach_text: Label
var _coach_rows: VBoxContainer
var _coach_ok: Button
var _coaching := false
var _banner: Label

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
	_log("begin %s (%s), kit %s, energy %.0f" % [id, Settings.difficulty, _kit, Energy.current])
	Energy.depleted.connect(_on_battery_dead)
	_build_ui()
	_refresh()
	_run()

func _run() -> void:
	phase = "intro"
	_say("%s wants a fight!" % enemy_name)
	await _place_fighters()
	await _coach("start", "A fight!", "%s wants to fight. Fights take turns: first you pick a move, then it attacks. Nothing happens until you're ready." % enemy_name)
	var rounds := 0
	while state.outcome == "" and not aborted:
		await _player_turn()
		if state.outcome != "" or aborted:
			break
		await _enemy_turn()
		rounds += 1
		if rounds == 1 and state.outcome == "" and not aborted:
			await _coach("other_moves", "More moves", "Hold %s with a tool for a defensive move: it gets you ready for the next blow (Brace, Parry, Dazzle...). Hold %s for a big attack." % [_back_name(), _forward_name()])
	await _finish()

# --- turns ------------------------------------------------------------------------------
func _player_turn() -> void:
	await _show_banner("YOUR TURN", Color(0.5, 1.0, 0.6))
	var kit_rows := []
	for i in 3:
		var t: String = _kit[i] if i < _kit.size() else ""
		kit_rows.append(["combat_slot_%d" % (i + 1), Catalog.tool_name(t) if t != "" else "(empty)"])
	await _coach("your_turn", "Your turn: pick a tool", "Your fight kit is the cards at the bottom. Press a tool's button to use it. Hold %s or %s at the same time for its other moves." % [_forward_name(), _back_name()], kit_rows)
	phase = "choose"
	_chosen = {}
	_log("your turn (%.0f / %.0f HP)" % [state.player_hp, state.player_max])
	_tip("choose", "Your turn! Press %s, %s or %s." % [Glyphs.label("combat_slot_1"), Glyphs.label("combat_slot_2"), Glyphs.label("combat_slot_3")])
	_highlight(-1)
	while _chosen.is_empty() and not aborted:
		await get_tree().process_frame
	if aborted:
		return
	phase = "busy"
	var tool_id: String = _chosen["tool"]
	var move: Dictionary = _chosen["move"]
	_log("you chose %s: %s (%s)" % [tool_id, move["name"], move["kind"]])
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
		await _coach("attack_ring", "Hit on the beat", "A ring will close onto the circle in the middle. Press %s the moment it touches: perfect timing hits hardest.%s" % [Glyphs.label("combat_timing"), " On Easy a miss still hits." if bool(state.tuning.get("now_cue", false)) else ""], [["combat_timing", "when the ring touches the circle"]])
		_tip("attack", "Press %s when the ring touches the circle!" % Glyphs.label("combat_timing"))
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
	await _show_banner("%s'S TURN" % enemy_name.to_upper(), Color(1.0, 0.55, 0.4))
	var attack: Dictionary = state.next_attack()
	_log("its turn: %s" % (attack.get("name", "dazzled, skips") if not attack.is_empty() else "dazzled, skips"))
	if attack.is_empty():
		_say("%s is dazzled and misses its turn!" % enemy_name)
		state.enemy_move([])
		await _wait(1.2)
		return
	await _coach("defend_ring", "Its turn: get ready to dodge", "%s is about to attack. The ring closes again: press %s just as it touches to dodge (no damage), or close to it to block (half)." % [enemy_name, Glyphs.label("combat_timing")], [["combat_timing", "as the ring touches: dodge!"]])
	_say("%s: %s! Get ready..." % [enemy_name, attack["name"]])
	_tip("defend", "Press %s just as the ring closes to dodge!" % Glyphs.label("combat_timing"))
	await _wait(GET_READY_SECONDS)
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
	var quality: String = state.defence_quality(_press_offset) if defend else state.quality(_press_offset)
	_log("%s ring %.2f s: %s (off by %s)" % ["defend" if defend else "attack", seconds, quality, "no press" if _press_offset == INF else "%.2f s" % _press_offset])
	return quality

## Seconds until the current beat (negative once it has passed); tests press on it.
func seconds_to_beat() -> float:
	return _beat_at - _beat_t

# --- input ------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if phase == "coach":
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("combat_timing") or event.is_action_pressed("ui_cancel"):
			dismiss_coach()
			get_viewport().set_input_as_handled()
		return
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
		_say("Slot %d is empty. Put a tool in it on the build screen (%s)." % [slot + 1, Glyphs.label("inventory")])
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
	_log("end: %s" % ("won" if won else ("aborted (battery)" if aborted else "lost")))
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

# --- teaching: the coach, turn banners, the log --------------------------------------------------
## Stops the fight with a how-to panel the first time `id` comes up (saved), until
## the player presses A / Enter / Space (or B / Esc, or clicks Got it).
func _coach(id: String, title: String, text: String, rows: Array = []) -> void:
	if Game.get_flag("coach:" + id) or aborted:
		return
	Game.set_flag("coach:" + id, true)
	var before := phase
	phase = "coach"
	_log("coach: %s" % id)
	_coach_title.text = title
	_coach_text.text = text
	for child in _coach_rows.get_children():
		child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var badge := Glyphs.badge(String(row[0]))
		badge.custom_minimum_size = Vector2(120, 0)
		line.add_child(badge)
		line.add_child(STYLE.label(String(row[1]), 20))
		_coach_rows.add_child(line)
	_coach_ok.text = "Got it  (%s)" % Glyphs.label("ui_accept")
	_coach_panel.visible = true
	_coaching = true
	while _coaching and not aborted:
		await get_tree().process_frame
	_coach_panel.visible = false
	phase = before
	await _wait(0.35)

## The player read the coach panel (also for tests).
func dismiss_coach() -> void:
	_coaching = false

## "YOUR TURN" / "SENTRY'S TURN", big in the middle, then it fades.
func _show_banner(text: String, colour: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", colour)
	_banner.visible = true
	_banner.modulate.a = 1.0
	await _wait(BANNER_SECONDS)
	_banner.visible = false

func _forward_name() -> String:
	return "the stick up" if Glyphs.pad else Glyphs.label("move_forward")

func _back_name() -> String:
	return "the stick down" if Glyphs.pad else Glyphs.label("move_back")

## One line per fight step in the game's log (godot.log), to find freezes.
func _log(text: String) -> void:
	print("fight: %s" % text)

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
			_card_labels[i].text = "[%s]  (empty)\n%s: add a tool" % [Glyphs.label("combat_slot_%d" % (i + 1)), Glyphs.label("inventory")]
			continue
		var m0 := Catalog.move(tool_id, "")
		var mf := Catalog.move(tool_id, "forward")
		var mb := Catalog.move(tool_id, "back")
		var key := Glyphs.label("combat_slot_%d" % (i + 1))
		var up := "Up" if Glyphs.pad else Glyphs.label("move_forward")
		var down := "Down" if Glyphs.pad else Glyphs.label("move_back")
		_card_labels[i].text = "[%s]  %s\n%s\n%s + %s   %s\n%s + %s   %s" % [key, Catalog.tool_name(tool_id), m0["name"], up, key, mf["name"], down, key, mb["name"]]

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
	_ring_key = _label(Glyphs.label("combat_timing").to_upper(), 22)
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
	# the turn banner, centre
	_banner = _label("", 64, Color(0.5, 1.0, 0.6))
	_banner.add_theme_font_override("font", STYLE.title_font())
	_banner.visible = false
	_root.add_child(_banner)
	_anchor(_banner, Control.PRESET_CENTER, -400, -60, 400, 40)
	# the coach panel, centre, over everything
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)
	_coach_panel = PanelContainer.new()
	_coach_panel.add_theme_stylebox_override("panel", STYLE.panel_style(0.8))
	_coach_panel.custom_minimum_size = Vector2(620, 0)
	_coach_panel.visible = false
	centre.add_child(_coach_panel)
	var coach_box := VBoxContainer.new()
	coach_box.add_theme_constant_override("separation", 12)
	_coach_panel.add_child(coach_box)
	_coach_title = STYLE.label("", 32, STYLE.CYAN)
	_coach_title.add_theme_font_override("font", STYLE.title_font())
	coach_box.add_child(_coach_title)
	_coach_text = STYLE.label("", 21)
	_coach_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_text.custom_minimum_size = Vector2(580, 0)
	coach_box.add_child(_coach_text)
	_coach_rows = VBoxContainer.new()
	_coach_rows.add_theme_constant_override("separation", 6)
	coach_box.add_child(_coach_rows)
	_coach_ok = Button.new()
	_coach_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	_coach_ok.focus_mode = Control.FOCUS_NONE        # the keys are read by _unhandled_input
	_coach_ok.pressed.connect(dismiss_coach)
	coach_box.add_child(_coach_ok)

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
