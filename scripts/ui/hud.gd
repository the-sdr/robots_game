extends CanvasLayer

# The game HUD: battery, clock, equipped tool, interaction prompt, notices and
# story messages. Anything can call_group("hud", "show_notice", text) or
# call_group("hud", "show_message", title, text) — the debug overlay
# (coord_overlay.gd) is separate and stays out of this group.

const NOTICE_SECONDS := 3.0
const MESSAGE_SECONDS := 7.0

@onready var battery_bar: ProgressBar = %BatteryBar
@onready var battery_label: Label = %BatteryLabel
@onready var clock_label: Label = %ClockLabel
@onready var curse_label: Label = %CurseLabel
@onready var sun_icon: Control = %SunIcon
@onready var solar_label: Label = %SolarLabel
@onready var charger_label: Label = %ChargerLabel
@onready var tool_label: Label = %ToolLabel
@onready var prompt_panel: PanelContainer = %PromptPanel
@onready var prompt_label: Label = %PromptLabel
@onready var notice_label: Label = %NoticeLabel
@onready var message_panel: PanelContainer = %MessagePanel
@onready var message_title: Label = %MessageTitle
@onready var message_text: Label = %MessageText
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var inventory_panel: Control = $InventoryPanel

var _notice_time := 0.0
var _message_hint: Label
## Tool cards and the Tools & controls page (scripts/ui/tool_card.gd).
var tool_card: CanvasLayer
## F1 help: controls, testing notes, map (scripts/ui/help_menu.gd).
var help_menu: CanvasLayer
## Tool feedback (tool_rig.gd): the cutter's heat, the smasher's combo, the laser's aim.
var heat_gauge: HeatGauge
var combo_label: Label
var aim_dot: Control
var _combo_tween: Tween
var _prompt_target: Interactable = null
var _message_time := 0.0
var _notices: Array[String] = []

func _ready() -> void:
	add_to_group("hud")
	Energy.changed.connect(_on_energy_changed)
	Game.inventory_changed.connect(_refresh_tool)
	_on_energy_changed(Energy.current, Energy.MAX)
	_refresh_tool()
	prompt_panel.visible = false
	notice_label.visible = false
	message_panel.visible = false
	_build_tool_feedback()
	help_menu = preload("res://scripts/ui/help_menu.gd").new()
	help_menu.name = "HelpMenu"
	help_menu.in_game = true
	add_child(help_menu)
	tool_card = preload("res://scripts/ui/tool_card.gd").new()
	tool_card.name = "ToolCard"
	add_child(tool_card)
	Game.tool_added.connect(queue_card)
	Game.inventory_changed.connect(_check_first_parts)
	Glyphs.device_changed.connect(func(_pad: bool) -> void:
		_refresh_tool()
		set_prompt(_prompt_target))

func _process(delta: float) -> void:
	clock_label.text = "Day %d  %s" % [Clock.day, Clock.time_text()]
	_update_solar()
	var tiny_left: float = Game.tiny_days_left()
	curse_label.visible = tiny_left > 0.0
	if curse_label.visible:
		var hours := ceili(tiny_left * 24.0)
		curse_label.text = "Tiny curse: %d d %d h left" % [hours / 24, hours % 24]
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			if _notices.is_empty():
				notice_label.visible = false
			else:
				_show_next_notice()

## The solar readout: how much sun a panel gets right now, and the charger you
## rely on (the one you're docked at, else the last one you docked at, else home):
## its charge and how fast the sun is filling it.
func _update_solar() -> void:
	var day := Clock.is_day()
	var light := Clock.sunlight()
	sun_icon.set("level", light)
	sun_icon.set("night", not day)
	sun_icon.queue_redraw()
	solar_label.text = "Sun %d%%" % roundi(light * 100.0) if day else "Night: no sun"
	var charger := readout_charger()
	charger_label.visible = charger != null
	if charger == null:
		return
	var cap: float = charger.effective_capacity()
	var rate: String
	if charger.docked_player != null:
		rate = "charging you"
	elif charger.fill_rate() > 0.005:
		rate = "+%.2f/s" % charger.fill_rate()
	else:
		rate = "not filling"
	charger_label.text = "%s %d%%  %s" % [charger_title(charger.name), roundi(charger.stored / cap * 100.0), rate]

func readout_charger() -> Node:
	var chargers := get_tree().get_nodes_in_group("charger")
	var wanted := String(Game.data.get("last_charger", ""))
	var home: Node = null
	for c in chargers:
		if c.docked_player != null:
			return c
	for c in chargers:
		if c.name == wanted:
			return c
		if c.get("is_home"):
			home = c
	return home

## "HouseCharger" -> "House charger".
static func charger_title(node_name: String) -> String:
	return node_name.replace("Charger", " charger").strip_edges()

func _on_energy_changed(current: float, maximum: float) -> void:
	battery_bar.max_value = maximum
	battery_bar.value = current
	battery_label.text = "%d%%" % roundi(current / maximum * 100.0)
	var f := current / maximum
	var colour := Color(1.0, 0.3, 0.2) if f < 0.2 else Color(1.0, 0.8, 0.2) if f < 0.5 else Color(0.35, 0.95, 0.6)
	battery_bar.get("theme_override_styles/fill").bg_color = colour

func _refresh_tool() -> void:
	var tool_id: String = Game.data["equipped_tool"]
	tool_label.text = ("Tool: %s   (%s next, %s to use)" % [Catalog.tool_name(tool_id), Glyphs.label("cycle_tool"), Glyphs.label("use_tool")]) if tool_id != "" else "No tool attached"

## Called by the player every frame with the current interactable (or null).
func set_prompt(target: Interactable) -> void:
	_prompt_target = target
	if target == null:
		prompt_panel.visible = false
		return
	prompt_panel.visible = true
	prompt_label.text = "%s  %s" % [Glyphs.text("interact"), target.prompt]

func show_notice(text: String) -> void:
	if notice_label.visible and _notice_time > 0.0:
		if _notices.is_empty() or _notices.back() != text:
			_notices.append(text)
		return
	notice_label.text = text
	notice_label.visible = true
	_notice_time = NOTICE_SECONDS

func _show_next_notice() -> void:
	notice_label.text = _notices.pop_front()
	notice_label.visible = true
	_notice_time = NOTICE_SECONDS

## A story beat or a longer explanation; stays up for a while.
## A story card at the top of the screen. It stays (the game keeps going) until
## the player closes it (B / Esc) or the next one replaces it (owner, save_48).
func show_message(title: String, text: String) -> void:
	message_title.text = title
	message_text.text = text
	message_panel.visible = true
	if _message_hint == null:
		_message_hint = Label.new()
		_message_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_message_hint.add_theme_font_size_override("font_size", 15)
		_message_hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.7))
		message_text.add_sibling(_message_hint)
	_message_hint.text = "%s close" % Glyphs.text("ui_cancel")

func message_open() -> bool:
	return message_panel.visible

func close_message() -> void:
	message_panel.visible = false

# Before the player's pause: with a story card up, B / Esc closes the card.
func _input(event: InputEvent) -> void:
	if _ask_panel != null:
		if event.is_action_pressed("ui_cancel"):
			answer(false)
			get_viewport().set_input_as_handled()
		return
	var player := get_tree().get_first_node_in_group("player")
	var fighting: bool = player != null and bool(player.get("in_combat"))
	if message_panel.visible and event.is_action_pressed("ui_cancel") and not get_tree().paused and not fighting:
		close_message()
		get_viewport().set_input_as_handled()

# --- dialogue (Pythia and later NPC robots) ------------------------------------------------
signal dialogue_finished(speaker: String)

var _dialogue: PanelContainer
var _dialogue_name: Label
var _dialogue_text: Label
var _pages: Array = []
var _page := 0
var _speaker := ""

## Shows lines one at a time at the bottom of the screen; E moves on.
func show_dialogue(speaker: String, pages: Array) -> void:
	if _dialogue == null:
		_build_dialogue()
	_speaker = speaker
	_pages = pages
	_page = 0
	_dialogue_name.text = speaker
	_dialogue_text.text = String(_pages[0])
	_dialogue.visible = true

func dialogue_open() -> bool:
	return _dialogue != null and _dialogue.visible

func advance_dialogue() -> void:
	if not dialogue_open():
		return
	_page += 1
	if _page >= _pages.size():
		_dialogue.visible = false
		dialogue_finished.emit(_speaker)
		return
	_dialogue_text.text = String(_pages[_page])

# The HUD sits after the player in the world, so it sees E first while talking.
func _unhandled_input(event: InputEvent) -> void:
	if dialogue_open() and event.is_action_pressed("interact"):
		advance_dialogue()
		get_viewport().set_input_as_handled()

func _build_dialogue() -> void:
	_dialogue = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.07, 0.88)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	_dialogue.add_theme_stylebox_override("panel", style)
	_dialogue.anchor_left = 0.5
	_dialogue.anchor_right = 0.5
	_dialogue.anchor_top = 1.0
	_dialogue.anchor_bottom = 1.0
	_dialogue.offset_left = -380
	_dialogue.offset_right = 380
	_dialogue.offset_top = -250
	_dialogue.offset_bottom = -100
	var box := VBoxContainer.new()
	_dialogue.add_child(box)
	_dialogue_name = Label.new()
	_dialogue_name.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_dialogue_name.add_theme_font_size_override("font_size", 20)
	box.add_child(_dialogue_name)
	_dialogue_text = Label.new()
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.custom_minimum_size = Vector2(720, 0)
	_dialogue_text.add_theme_font_size_override("font_size", 19)
	box.add_child(_dialogue_text)
	var hint := Label.new()
	hint.text = "%s next" % Glyphs.text("interact")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	box.add_child(hint)
	$Root.add_child(_dialogue)

# --- fades (the lift) --------------------------------------------------------------------------
var _fade_rect: ColorRect

## Fades to black, runs `action` (a teleport), fades back.
func fade_through(action: Callable, seconds: float = 0.35) -> void:
	if _fade_rect == null:
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 0)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.anchor_right = 1.0
		_fade_rect.anchor_bottom = 1.0
		$Root.add_child(_fade_rect)
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 1.0, seconds)
	t.tween_callback(action)
	t.tween_property(_fade_rect, "color:a", 0.0, seconds)

func toggle_pause() -> void:
	pause_menu.toggle()

# --- tool feedback ---------------------------------------------------------------------------
func _build_tool_feedback() -> void:
	heat_gauge = HeatGauge.new()
	heat_gauge.name = "HeatGauge"
	heat_gauge.custom_minimum_size = Vector2(300, 34)
	heat_gauge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 170)
	heat_gauge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	heat_gauge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	heat_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_gauge.visible = false
	add_child(heat_gauge)
	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.add_theme_font_size_override("font_size", 44)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	combo_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	combo_label.add_theme_constant_override("outline_size", 8)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	combo_label.position += Vector2(90, -90)
	combo_label.pivot_offset = Vector2(40, 25)
	combo_label.visible = false
	add_child(combo_label)
	aim_dot = AimDot.new()
	aim_dot.name = "AimDot"
	aim_dot.custom_minimum_size = Vector2(24, 24)
	aim_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	aim_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_dot.visible = false
	add_child(aim_dot)

## The cutter's heat (0..1) with its clean zone; hidden when cold.
func show_heat(heat: float, clean_from: float, clean_to: float, overheated: bool) -> void:
	heat_gauge.visible = heat > 0.0 or overheated
	heat_gauge.heat = heat
	heat_gauge.clean_from = clean_from
	heat_gauge.clean_to = clean_to
	heat_gauge.overheated = overheated
	heat_gauge.queue_redraw()

## "SMASH x3!" popping near the middle of the screen.
func show_combo(count: int) -> void:
	combo_label.text = "SMASH x%d!" % count
	combo_label.visible = true
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2.ONE * 1.4
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_tween = create_tween()
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.12)
	_combo_tween.tween_interval(0.4)
	_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.3)
	_combo_tween.tween_callback(func() -> void: combo_label.visible = false)

## The laser's aim dot at the screen centre.
func show_aim(on: bool) -> void:
	aim_dot.visible = on

class HeatGauge extends Control:
	var heat := 0.0
	var clean_from := 0.6
	var clean_to := 0.88
	var overheated := false

	func _draw() -> void:
		var bar := Rect2(Vector2(0, 8), Vector2(size.x, size.y - 8))
		draw_rect(bar, Color(0.1, 0.13, 0.15, 0.85))
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * clean_from, 0), Vector2(bar.size.x * (clean_to - clean_from), bar.size.y)), Color(0.2, 0.65, 0.25, 0.9))
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * clean_to, 0), Vector2(bar.size.x * (1.0 - clean_to), bar.size.y)), Color(0.75, 0.18, 0.12, 0.9))
		var fill := Color(1.0, 0.25, 0.15) if overheated else Color(1.0, 0.75, 0.3)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(heat, 0.0, 1.0), bar.size.y * 0.5)), fill)
		var x := bar.size.x * clampf(heat, 0.0, 1.0)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color.WHITE, 3.0)
		draw_rect(bar, Color(0.45, 0.95, 1.0), false, 2.0)

class AimDot extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.0, Color(1.0, 0.4, 0.3))
		draw_arc(c, 9.0, 0.0, TAU, 20, Color(1.0, 0.4, 0.3, 0.8), 2.0)

## A tool card, shown once when nothing else is on screen.
func queue_card(id: String) -> void:
	tool_card.queue_card(id)

## The first part picked up shows the parts card; the first time a recipe can be
## built, a story card says so (and which button opens the build screen).
func _check_first_parts() -> void:
	var inventory: Dictionary = Game.data["inventory"]
	if inventory.is_empty():
		return
	queue_card("parts")
	for recipe_id in Catalog.RECIPES:
		var recipe: Dictionary = Catalog.RECIPES[recipe_id]
		if not recipe.has("tool") or Game.has_tool(String(recipe["tool"])):
			continue
		if Game.craft_blocker(recipe_id) == "" and not Game.get_flag("hint_ready:" + recipe_id):
			Game.set_flag("hint_ready:" + recipe_id, true)
			show_message("Ready to build", "You have everything for the %s. Open the build screen (%s) and pick it." % [recipe["name"], Glyphs.label("inventory")])
			return

# --- a yes / no question, and a fade to black ------------------------------------------------
var _ask_panel: PanelContainer
var _ask_yes: Callable
var _fader: ColorRect

## A small question over the game (which waits): yes runs `on_yes`. A / Enter
## says yes, B / Esc says no; the buttons work with the mouse too.
func ask(title: String, text: String, yes_text: String, no_text: String, on_yes: Callable) -> void:
	const STYLE := preload("res://scripts/ui/ui_style.gd")
	if _ask_panel != null:
		_ask_panel.queue_free()
	_ask_yes = on_yes
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ask_panel = PanelContainer.new()
	_ask_panel.name = "AskPanel"
	_ask_panel.add_theme_stylebox_override("panel", STYLE.panel_style(0.7))
	_ask_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_ask_panel.add_child(box)
	var head := STYLE.label(title, 30, STYLE.CYAN)
	head.add_theme_font_override("font", STYLE.title_font())
	box.add_child(head)
	var body := STYLE.label(text, 20)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var no := Button.new()
	no.text = "%s  (%s)" % [no_text, Glyphs.label("ui_cancel")]
	no.pressed.connect(answer.bind(false))
	row.add_child(no)
	var yes := Button.new()
	yes.text = "%s  (%s)" % [yes_text, Glyphs.label("ui_accept")]
	yes.pressed.connect(answer.bind(true))
	row.add_child(yes)
	var holder := CanvasLayer.new()
	holder.layer = 21
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(holder)
	holder.add_child(centre)
	centre.add_child(_ask_panel)
	_ask_panel.set_meta("holder", holder)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	yes.grab_focus()

func asking() -> bool:
	return _ask_panel != null

## The answer to ask() (also for tests).
func answer(yes: bool) -> void:
	if _ask_panel == null:
		return
	(_ask_panel.get_meta("holder") as Node).queue_free()
	_ask_panel = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if yes and _ask_yes.is_valid():
		_ask_yes.call()

## Fades the screen to `alpha` (1 = black) over `seconds`.
func fade(alpha: float, seconds: float) -> void:
	if _fader == null:
		var holder := CanvasLayer.new()
		holder.layer = 30
		add_child(holder)
		_fader = ColorRect.new()
		_fader.color = Color(0, 0, 0, 0)
		_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(_fader)
	var tween := create_tween()
	tween.tween_property(_fader, "color:a", alpha, seconds)
	await tween.finished

## The pause menu's Tools & controls page.
func open_controls_page() -> void:
	tool_card.show_page()

## F1 / D-pad down, or the pause menu: help on a tab ("Controls", "Testing notes", "Map").
func open_help(tab: String = "Controls") -> void:
	help_menu.open(tab)

## A tool's card again (from the help menu).
func show_tool_card(tool_id: String) -> void:
	tool_card.show_card(tool_id)

func toggle_inventory() -> void:
	inventory_panel.toggle()
