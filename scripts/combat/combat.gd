extends CanvasLayer

# The fight screen: turn-based robot combat on the live world (an enemy node
# like the hill sentry starts it with begin()). Rules and numbers are in
# combat_state.gd / Catalog / Settings / Tuning; this script runs the turns,
# reads the buttons, draws the meters and animates both robots.
#
# Fights use the tool controls (owner, 2026-09-30: "fight controls the same as
# the tool controls... consistent"). Your turn: RB / Q switch tools, RT / click
# uses the one in hand, in its own way - smasher: tap fast in a burst; cutter:
# hold and let go in the green (the same heat as in the world, F10 tunes both);
# laser: hold and trace the glowing seam with the mouse / right stick;
# fabricator: hold to print a repair. Its turn: defend with the tool in hand -
# smasher: tap to bash the blow aside; cutter: hold and let go as the ring
# closes (parry); laser: hold the beam on its eye (dazzle); fabricator: hold to
# print a shield; no tool: jump on the ring. Each result is a quality
# ("perfect" / "good" / "miss") that combat_state turns into damage.
# Tests drive it with select_tool() / start_attack() / perform_for_test() /
# dismiss_coach() and read `phase`.
#
# Teaching: a coach panel stops the fight the first time each thing happens
# (saved flags "coach:<id>"), a banner announces every turn, and every attack
# gets a "get ready" beat. Every step goes to the log ("fight: ...").

signal finished(won: bool)

const State := preload("res://scripts/combat/combat_state.gd")
const STYLE := preload("res://scripts/ui/ui_style.gd")
const BANNER_SECONDS := 1.1
const GET_READY_SECONDS := 1.0
const T := preload("res://scripts/game/tuning.gd")
const FIGHT_TOOLS := ["smasher", "cutter", "laser", "fabricator"]
const SMASH_SECONDS := 2.0         # the tap burst (Easy: x1.5)
const SMASH_TARGET := 7            # taps for "perfect" (Easy: 4); half of it for "good"
const BASH_TARGET := 4             # taps before the ring closes to bash a blow aside (Easy: 2)
const TRACE_SECONDS := 3.0         # time to trace the seam (Easy: x1.5)
const TRACE_DOTS := 5
const TRACE_REACH := 34.0          # px from the cursor that burns a dot
const CURSOR_SPEED := 520.0        # px per second at full stick
const MOUSE_AIM := 1.0
const DAZZLE_NEEDED := 0.45        # seconds the beam must rest on its eye (Easy: 0.25)
const PRINT_SECONDS := 1.2         # hold to print a repair
const ATTACK_RING := 0.9      # seconds the attack ring takes to close at normal speed
const NEXT_HIT_RING := 0.55   # later hits of a combo come faster
const RING_START := 170.0
const RING_TARGET := 46.0

var state = State.new()
var player: CharacterBody3D
var enemy_node: Node3D           # the enemy actor (hill_sentry.gd): arena positions and animations
var enemy_id := ""
var enemy_name := ""
## "intro", "coach", "choose", "attack", "defend", "busy", "done". Tests wait on it.
var phase := ""
var aborted := false

var _tools: Array[String] = []    # the tools this fight can use, in FIGHT_TOOLS order
var _tool := ""                    # the one in hand
var _held := false                 # use_tool is down
var _presses := 0
var _press_times: Array[float] = []
var _released_at := -1.0
var _pressed_at := -1.0
var _t := 0.0                      # seconds into the current pattern
var _aim := Vector2.ZERO           # the laser cursor, px from the screen centre
var _forced := ""                  # tests: the result the current pattern should give
var _meter: FightMeter
var _tool_card: Label
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
	for t in FIGHT_TOOLS:
		if Game.has_tool(t):
			_tools.append(t)
	_tool = String(Game.data["equipped_tool"]) if _tools.has(String(Game.data["equipped_tool"])) else (_tools[0] if not _tools.is_empty() else "")
	_equipped_before = String(Game.data["equipped_tool"])
	player.set("in_combat", true)
	player.velocity = Vector3.ZERO
	_log("begin %s (%s), tools %s, in hand %s, energy %.0f" % [id, Settings.difficulty, _tools, _tool, Energy.current])
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
		if rounds == 1 and state.outcome == "" and not aborted and _tools.size() > 1:
			await _coach("switch_tools", "Every tool fights its own way", "Switch tools with %s: each one attacks and defends differently - the same way it works out in the world." % Glyphs.label("cycle_tool"), [["cycle_tool", "switch tool"], ["use_tool", "use it"]])
	await _finish()

# --- turns ------------------------------------------------------------------------------
func _player_turn() -> void:
	await _show_banner("YOUR TURN", Color(0.5, 1.0, 0.6))
	await _coach("your_turn", "Your turn", "Fight with the tool in your hand, just like out in the world. %s switches tools, %s uses the one you hold." % [Glyphs.label("cycle_tool"), Glyphs.label("use_tool")],
		[["cycle_tool", "switch tool"], ["use_tool", "use it"]])
	phase = "choose"
	_chosen = {}
	_log("your turn (%.0f / %.0f HP), in hand: %s" % [state.player_hp, state.player_max, _tool])
	_tip("choose", "Your turn! %s to use the %s, %s to switch." % [Glyphs.label("use_tool"), Catalog.tool_name(_tool) if _tool != "" else "treads", Glyphs.label("cycle_tool")])
	_refresh()
	while _chosen.is_empty() and not aborted:
		await get_tree().process_frame
	if aborted:
		return
	phase = "busy"
	var tool_id: String = _chosen["tool"]
	var move: Dictionary = _chosen["move"]
	_log("you use %s: %s (%s)" % [tool_id, move["name"], move["kind"]])
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
	var kind := String(move["kind"])
	if kind == "attack":
		await _coach("attack_" + tool_id, "The %s in a fight" % Catalog.tool_name(tool_id), ATTACK_HOWTO.get(tool_id, "Press %s on the beat.") % Glyphs.label("use_tool"), [["use_tool", ATTACK_SHORT.get(tool_id, "use it")]])
		for i in int(move.get("hits", 1)):
			var q := await _attack_pattern(tool_id)
			if aborted:
				return
			qualities.append(q)
			_log("  %s attack: %s" % [tool_id, q])
			_player_lunge()
			_popup({"perfect": "PERFECT!", "good": "Good", "miss": "Miss..."}[q], enemy_node.global_position + Vector3(0, 2.6, 0), Color(1, 0.9, 0.3))
			await _wait(0.3)
	elif kind == "repair":
		await _coach("attack_" + tool_id, "The fabricator in a fight", "Hold %s to print patches over your dents. Let go when the bar is full." % Glyphs.label("use_tool"), [["use_tool", "hold until full"]])
		var q := await _attack_pattern(tool_id)
		move = move.duplicate()
		move["heal"] = float(move.get("heal", 0.0)) * {"perfect": 1.0, "good": 0.6, "miss": 0.25}[q]
	var result: Dictionary = state.player_move(move, qualities, weak)
	match kind:
		"attack":
			_popup(str(result["damage"]), enemy_node.global_position + Vector3(0, 2.2, 0), Color(1, 0.4, 0.3))
			enemy_node.call("flinch")
		"repair":
			_popup("+%d" % result["healed"], player.global_position + Vector3(0, 1.8, 0), Color(0.4, 1, 0.5))
	_refresh()
	await _wait(0.7)

func _enemy_turn() -> void:
	phase = "busy"
	_hint.text = ""          # "Your turn! ..." stayed up through its turn (save_78)
	await _show_banner("%s'S TURN" % enemy_name.to_upper(), Color(1.0, 0.55, 0.4))
	var attack: Dictionary = state.next_attack()
	_log("its turn: %s, you defend with %s" % [attack.get("name", "dazzled, skips") if not attack.is_empty() else "dazzled, skips", _tool if _tool != "" else "a jump"])
	if attack.is_empty():
		_say("%s is dazzled and misses its turn!" % enemy_name)
		state.enemy_move([])
		await _wait(1.2)
		return
	var defence: String = _tool if DEFEND_HOWTO.has(_tool) else ""
	await _coach("defend_" + (defence if defence != "" else "jump"), "Its turn: defend with the %s" % (Catalog.tool_name(defence) if defence != "" else "jump"),
		DEFEND_HOWTO.get(defence, "Press %s just as the ring closes to jump out of the way.") % Glyphs.label("use_tool" if defence != "" else "combat_timing"),
		[["use_tool" if defence != "" else "combat_timing", DEFEND_SHORT.get(defence, "jump as the ring closes")]])
	_say("%s: %s! Get ready..." % [enemy_name, attack["name"]])
	_refresh()
	await _wait(GET_READY_SECONDS)
	var qualities := []
	for i in int(attack.get("hits", 1)):
		var seconds: float = state.ring_seconds(float(attack["wind_up"]) if i == 0 else NEXT_HIT_RING)
		enemy_node.call("wind_up", seconds)
		var q := await _defence_pattern(defence, seconds)
		if aborted:
			return
		qualities.append(q)
		_log("  defend %s: %s" % [defence if defence != "" else "jump", q])
		enemy_node.call("strike")
		if q == "perfect":
			_player_dodge()
			_popup(DEFEND_WIN.get(defence, "DODGED!"), player.global_position + Vector3(0, 1.9, 0), Color(0.5, 1, 0.6))
		else:
			_player_hit()
			_popup("Blocked" if q == "good" else "Ouch!", player.global_position + Vector3(0, 1.9, 0), Color(1, 0.8, 0.4) if q == "good" else Color(1, 0.4, 0.3))
		await _wait(0.3)
	var result: Dictionary = state.enemy_move(qualities)
	if int(result["damage"]) > 0:
		_popup("-%d" % result["damage"], player.global_position + Vector3(0, 1.5, 0), Color(1, 0.35, 0.3))
	_refresh()
	await _wait(0.7)

# --- how each tool fights ---------------------------------------------------------------------
const ATTACK_HOWTO := {
	"smasher": "Tap %s as fast as you can while the bar runs. Quick taps build a combo: more hits, more damage.",
	"cutter": "Hold %s: the heat climbs. Let go in the green for a clean cut. Too long and it overheats and misses.",
	"laser": "Hold %s to fire and trace the glowing seam, dot by dot, with the mouse or right stick. Burn them all!",
}
const ATTACK_SHORT := {"smasher": "tap fast", "cutter": "hold, let go in the green", "laser": "hold and trace the dots"}
const DEFEND_HOWTO := {
	"smasher": "Tap %s fast while it winds up to bash the blow aside. Enough taps before the ring closes and it misses you.",
	"cutter": "Hold %s while it winds up and let go just as the ring touches the circle: a parry. Close to it still blocks half.",
	"laser": "Hold %s and keep the beam on its glowing eye until the ring closes: dazzled, it misses.",
	"fabricator": "Hold %s while it winds up to print a shield. The longer you hold, the stronger it is.",
}
const DEFEND_SHORT := {"smasher": "tap fast to bash it aside", "cutter": "hold, let go as the ring touches", "laser": "beam on its eye", "fabricator": "hold to print a shield"}
const DEFEND_WIN := {"smasher": "BASHED ASIDE!", "cutter": "PARRIED!", "laser": "DAZZLED!", "fabricator": "SHIELDED!"}

## Scores (static, so tests can check the rules directly).
static func smash_quality(taps: int, easy: bool) -> String:
	var target := 4 if easy else SMASH_TARGET
	return "perfect" if taps >= target else ("good" if taps * 2 >= target else "miss")

static func cut_quality(heat_at_release: float, overheated: bool, clean_from: float, clean_to: float) -> String:
	if overheated:
		return "miss"
	if heat_at_release >= clean_from and heat_at_release <= clean_to:
		return "perfect"
	return "good" if heat_at_release >= 0.3 else "miss"

static func trace_quality(burned: int) -> String:
	return "perfect" if burned >= TRACE_DOTS else ("good" if burned >= 3 else "miss")

static func share_quality(share: float) -> String:
	return "perfect" if share >= 0.99 else ("good" if share >= 0.5 else "miss")

func _easy() -> bool:
	return Settings.difficulty == "easy"

func _begin_pattern(mode: String) -> void:
	phase = "attack" if mode in ["taps", "heat", "trace", "fill"] else "defend"
	_presses = 0
	_press_times.clear()
	_released_at = -1.0
	_pressed_at = -1.0
	_t = 0.0
	_forced = ""
	_held = Input.is_action_pressed("use_tool")     # a release during a coach panel would be missed
	_meter.mode = mode
	_meter.visible = true

func _end_pattern() -> void:
	_meter.visible = false
	_ring.visible = false
	phase = "busy"

## Runs one attack with `tool_id`'s pattern and returns its quality.
func _attack_pattern(tool_id: String) -> String:
	match tool_id:
		"smasher":
			_begin_pattern("taps")
			var seconds := SMASH_SECONDS * (1.5 if _easy() else 1.0)
			_meter.target = 4 if _easy() else SMASH_TARGET
			while _t < seconds and _forced == "" and not aborted:
				await _pattern_frame()
				_meter.progress = _t / seconds
				_meter.count = _presses
			var q := _forced if _forced != "" else smash_quality(_presses, _easy())
			_end_pattern()
			return q
		"cutter":
			_begin_pattern("heat")
			_meter.clean_from = T.v("cutter_clean_from")
			_meter.clean_to = T.v("cutter_clean_to")
			var heat := 0.0
			var over := false
			var waited := 0.0
			while _forced == "" and not aborted:
				await _pattern_frame()
				if _held:
					heat += get_process_delta_time() / T.v("cutter_heat_seconds")
					if heat >= 1.0:
						over = true
						heat = 1.0
						break
				elif heat > 0.0:
					break                                    # let go
				else:
					waited += get_process_delta_time()
					if waited > 5.0:
						break                                # never pressed
				_meter.heat = heat
			var q := _forced if _forced != "" else cut_quality(heat, over, T.v("cutter_clean_from"), T.v("cutter_clean_to"))
			if over:
				_popup("OVERHEATED", player.global_position + Vector3(0, 1.8, 0), Color(1, 0.4, 0.2))
			_end_pattern()
			return q
		"laser":
			_begin_pattern("trace")
			var seconds := TRACE_SECONDS * (1.5 if _easy() else 1.0)
			_aim = Vector2(-240, 30)
			_meter.dots = []
			for i in TRACE_DOTS:
				var x := -160.0 + 320.0 * i / (TRACE_DOTS - 1)
				_meter.dots.append(Vector2(x, sin(i * 1.3) * 40.0))
			_meter.burned = []
			while _t < seconds and _forced == "" and not aborted:
				await _pattern_frame()
				_move_aim()
				_meter.cursor = _aim
				_meter.firing = _held
				if _held:
					for i in _meter.dots.size():
						if not _meter.burned.has(i) and (_meter.dots[i] as Vector2).distance_to(_aim) <= TRACE_REACH:
							_meter.burned.append(i)
				_meter.progress = _t / seconds
				if _meter.burned.size() >= TRACE_DOTS:
					break
			var q := _forced if _forced != "" else trace_quality(_meter.burned.size())
			_end_pattern()
			return q
		"fabricator":
			_begin_pattern("fill")
			var filled := 0.0
			var waited := 0.0
			while _forced == "" and not aborted:
				await _pattern_frame()
				if _held:
					filled = minf(filled + get_process_delta_time() / PRINT_SECONDS, 1.0)
				elif filled > 0.0:
					break
				else:
					waited += get_process_delta_time()
					if waited > 5.0:
						break
				_meter.heat = filled
			var q := _forced if _forced != "" else share_quality(filled)
			_end_pattern()
			return q
	# no tool: ram on the beat (the old timing ring, pressed with use or jump)
	var r := await _timing(state.ring_seconds(ATTACK_RING), false)
	return _forced if _forced != "" else r

## Its blow, defended the way the tool in hand does it; returns the quality.
func _defence_pattern(tool_id: String, seconds: float) -> String:
	_show_ring("use_tool")
	match tool_id:
		"smasher":
			_begin_pattern("bash")
			var needed := 2 if _easy() else BASH_TARGET
			_meter.target = needed
			while _t < seconds and _forced == "" and not aborted:
				await _pattern_frame()
				_ring_progress(seconds)
				_meter.count = _presses
			var q := _forced if _forced != "" else ("perfect" if _presses >= needed else ("good" if _presses * 2 >= needed else "miss"))
			_end_pattern()
			return q
		"cutter":
			_begin_pattern("parry")
			var window := float(state.tuning["defend_window"])
			while _t < seconds + window * 2.0 and _forced == "" and not aborted:
				await _pattern_frame()
				_ring_progress(seconds)
				if _released_at >= 0.0 and _pressed_at >= 0.0:
					break
			var offset := INF if _released_at < 0.0 or _pressed_at < 0.0 else _released_at - seconds
			var q := _forced if _forced != "" else state.defence_quality(offset)
			_end_pattern()
			return q
		"laser":
			_begin_pattern("eye")
			var needed := 0.25 if _easy() else DAZZLE_NEEDED
			_aim = Vector2(-200, 120)
			var on_eye := 0.0
			while _t < seconds and _forced == "" and not aborted:
				await _pattern_frame()
				_ring_progress(seconds)
				_move_aim()
				_meter.cursor = _aim
				_meter.firing = _held
				if _held and _aim.distance_to(FightMeter.EYE) <= TRACE_REACH:
					on_eye += get_process_delta_time()
				_meter.heat = on_eye / needed
			var q := _forced if _forced != "" else share_quality(on_eye / needed)
			_end_pattern()
			return q
		"fabricator":
			_begin_pattern("shield")
			var held := 0.0
			while _t < seconds and _forced == "" and not aborted:
				await _pattern_frame()
				_ring_progress(seconds)
				if _held:
					held += get_process_delta_time()
				_meter.heat = held / (seconds * 0.7)
			var q := _forced if _forced != "" else share_quality(held / (seconds * 0.7))
			_end_pattern()
			return q
	# no tool: jump as the ring closes
	var r := await _timing(seconds, true)
	return _forced if _forced != "" else r

func _pattern_frame() -> void:
	await get_tree().process_frame
	if not get_tree().paused:
		_t += get_process_delta_time()

## Shows the ring with the button this press uses under it (save_78: it always
## said the jump button, even when the tool in hand defends with use).
func _show_ring(action: String) -> void:
	_ring_key.text = Glyphs.label(action).to_upper()
	_ring.visible = true

func _ring_progress(seconds: float) -> void:
	_ring.set("progress", _t / seconds)
	_ring.set("in_window", absf(_t - seconds) <= float(state.tuning["defend_window"]))
	_ring.queue_redraw()

## The laser cursor follows the right stick (and the mouse, in _unhandled_input).
func _move_aim() -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_aim += stick * CURSOR_SPEED * get_process_delta_time()
	_aim = _aim.clamp(Vector2(-420, -260), Vector2(420, 260))

## Tests: finish the current attack / defence pattern with this quality.
func perform_for_test(quality: String) -> void:
	_forced = quality
	if _awaiting:
		_press_offset = 0.0 if quality == "perfect" else (0.2 if quality == "good" else INF)
		_awaiting = false

func _timing(seconds: float, defend: bool) -> String:
	_defending = defend
	_beat_at = seconds
	_beat_t = 0.0
	_press_offset = INF
	_awaiting = true
	phase = "timing"
	_show_ring("combat_timing" if defend else "use_tool")     # jump its blows, ram on the beat (the tool card says so)
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
	if event.is_action("use_tool"):
		var down := event.is_action_pressed("use_tool")
		if down and not _held:
			_held = true
			_presses += 1
			_press_times.append(_t)
			_pressed_at = _t
			if phase == "choose":
				start_attack()
			elif phase == "timing":
				input_timing()
		elif not down and event.is_action_released("use_tool") and _held:
			_held = false
			_released_at = _t
		get_viewport().set_input_as_handled()
		return
	if phase == "choose" and event.is_action_pressed("cycle_tool"):
		select_tool("")
		get_viewport().set_input_as_handled()
		return
	if phase == "timing" and event.is_action_pressed("combat_timing"):
		input_timing()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and phase in ["attack", "defend"]:
		_aim += (event as InputEventMouseMotion).relative * MOUSE_AIM
		_aim = _aim.clamp(Vector2(-420, -260), Vector2(420, 260))

## Pick slot 0-2's tool with a direction ("", "forward", "back"). False if the slot is empty.
## Switch to a tool ("" = the next one), on your turn.
func select_tool(tool_id: String) -> void:
	if _tools.is_empty():
		return
	if tool_id == "":
		tool_id = _tools[(_tools.find(_tool) + 1) % _tools.size()]
	if not _tools.has(tool_id):
		return
	_tool = tool_id
	_show_tool(tool_id)
	_refresh()

## Use the tool in hand (RT / click on your turn; tests call it too).
func start_attack() -> bool:
	if phase != "choose":
		return false
	_chosen = {"tool": _tool, "move": Catalog.move(_tool, "")}
	return true

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
		enemy_node.call("defeat")
		if enemy_node.has_method("drop_salvage"):
			enemy_node.call("drop_salvage")          # its reward is in there: cutter or laser (owner, 2026-09-30)
		else:
			for item in def.get("reward", {}):
				Game.add_item(item, int(def["reward"][item]))
				get_tree().call_group("hud", "show_notice", "Took %s" % Catalog.item_name(item))
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
	if _tool == "":
		_tool_card.text = "No tools yet: ram it on the beat (%s), jump its blows (%s)" % [Glyphs.label("use_tool"), Glyphs.label("combat_timing")]
		return
	var move := Catalog.move(_tool, "")
	var switch := ("   ◀ %s ▶" % Glyphs.label("cycle_tool")) if _tools.size() > 1 else ""
	_tool_card.text = "%s%s\nAttack: %s (%s: %s)\nDefend: %s" % [Catalog.tool_name(_tool).to_upper(), switch, move["name"], Glyphs.label("use_tool"),
		ATTACK_SHORT.get(_tool, "hold"), DEFEND_SHORT.get(_tool, "jump as the ring closes")]

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
	_ring_key = _label("", 22)          # set by _show_ring for each press
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
	# the tool in hand, bottom centre (RB / Q switch it on your turn)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.1, 0.88)))
	_root.add_child(card)
	_anchor(card, Control.PRESET_CENTER_BOTTOM, -360, -130, 360, -14)
	_tool_card = _label("", 19)
	card.add_child(_tool_card)
	# the meter for the current attack / defence, centre
	_meter = FightMeter.new()
	_meter.visible = false
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_meter)
	_anchor(_meter, Control.PRESET_CENTER, -440, -280, 440, 280)
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

## What the current attack / defence looks like: taps and their target, the
## heat gauge with its green zone, the seam to trace, the eye to dazzle, a fill bar.
class FightMeter extends Control:
	const EYE := Vector2(0, -150)          # where "its eye" is, from the centre (the dazzle target)
	var mode := ""
	var progress := 0.0
	var count := 0
	var target := 1
	var heat := 0.0
	var clean_from := 0.7
	var clean_to := 0.85
	var dots: Array = []
	var burned: Array = []
	var cursor := Vector2.ZERO
	var firing := false

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var font := ThemeDB.fallback_font
		var cyan := Color(0.45, 0.95, 1.0)
		var warm := Color(1.0, 0.72, 0.3)
		match mode:
			"taps", "bash":
				var label := "TAP!" if mode == "taps" else "BASH IT ASIDE!"
				draw_string(font, c + Vector2(-120, 120), "%s  %d / %d" % [label, count, target], HORIZONTAL_ALIGNMENT_LEFT, -1, 40, warm if count >= target else cyan)
				if mode == "taps":
					draw_rect(Rect2(c + Vector2(-200, 140), Vector2(400, 14)), Color(0.1, 0.13, 0.15, 0.85))
					draw_rect(Rect2(c + Vector2(-200, 140), Vector2(400 * (1.0 - progress), 14)), cyan)
			"heat", "fill", "shield":
				var bar := Rect2(c + Vector2(-220, 120), Vector2(440, 30))
				draw_rect(bar, Color(0.1, 0.13, 0.15, 0.85))
				if mode == "heat":
					draw_rect(Rect2(bar.position + Vector2(bar.size.x * clean_from, 0), Vector2(bar.size.x * (clean_to - clean_from), bar.size.y)), Color(0.2, 0.65, 0.25, 0.9))
					draw_rect(Rect2(bar.position + Vector2(bar.size.x * clean_to, 0), Vector2(bar.size.x * (1.0 - clean_to), bar.size.y)), Color(0.75, 0.18, 0.12, 0.9))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(heat, 0.0, 1.0), bar.size.y * 0.5)), warm)
				draw_rect(bar, cyan, false, 2.0)
				var word: String = {"heat": "HOLD... LET GO IN THE GREEN", "fill": "HOLD TO PRINT", "shield": "HOLD FOR A SHIELD"}[mode]
				draw_string(font, bar.position + Vector2(0, -12), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, cyan)
			"trace":
				for i in dots.size():
					var p: Vector2 = c + dots[i]
					if i > 0:
						draw_line(c + dots[i - 1], p, Color(1.0, 0.6, 0.2, 0.5), 4.0)
					draw_circle(p, 14.0, Color(0.3, 0.2, 0.15) if burned.has(i) else Color(1.0, 0.7, 0.3))
				draw_circle(c + cursor, 10.0, Color(1.0, 0.3, 0.2) if firing else Color(1, 1, 1, 0.6))
				draw_arc(c + cursor, 18.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
				draw_string(font, c + Vector2(-160, 200), "TRACE THE SEAM  %d / %d" % [burned.size(), dots.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, cyan)
			"eye":
				draw_circle(c + EYE, 24.0, Color(1.0, 0.35, 0.1, 0.9))
				draw_arc(c + EYE, 34.0, 0.0, TAU * clampf(heat, 0.0, 1.0), 32, cyan, 5.0)
				draw_circle(c + cursor, 10.0, Color(1.0, 0.3, 0.2) if firing else Color(1, 1, 1, 0.6))
				draw_arc(c + cursor, 18.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
				draw_string(font, c + Vector2(-150, 200), "BEAM ON ITS EYE!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, cyan)
			"parry":
				draw_string(font, c + Vector2(-190, 200), "HOLD... LET GO AS THE RING TOUCHES", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, cyan)
