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
## Tool cards and the Tools & controls page (scripts/ui/tool_card.gd).
var tool_card: CanvasLayer
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
	tool_card = preload("res://scripts/ui/tool_card.gd").new()
	tool_card.name = "ToolCard"
	add_child(tool_card)
	Game.tool_added.connect(queue_card)
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
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message_panel.visible = false

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
func show_message(title: String, text: String) -> void:
	message_title.text = title
	message_text.text = text
	message_panel.visible = true
	_message_time = MESSAGE_SECONDS + text.length() * 0.03

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

## A tool card, shown once when nothing else is on screen.
func queue_card(id: String) -> void:
	tool_card.queue_card(id)

## The pause menu's Tools & controls page.
func open_controls_page() -> void:
	tool_card.show_page()

func toggle_inventory() -> void:
	inventory_panel.toggle()
