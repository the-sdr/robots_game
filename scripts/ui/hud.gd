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
	tool_label.text = ("Tool: %s   (Q next, click to use)" % Catalog.tool_name(tool_id)) if tool_id != "" else "No tool attached"

## Called by the player every frame with the current interactable (or null).
func set_prompt(target: Interactable) -> void:
	if target == null:
		prompt_panel.visible = false
		return
	prompt_panel.visible = true
	prompt_label.text = "[E]  %s" % target.prompt

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

func toggle_pause() -> void:
	pause_menu.toggle()

func toggle_inventory() -> void:
	inventory_panel.toggle()
