extends Node

# Autoload "Glyphs": which button does what, in the words of the device the
# player is holding right now. Tracks the last device used (keyboard/mouse or a
# pad) and names any Input Map action for it: "E" / "X", "Left click" / "RT".
# Everything that tells the player a button (the interact prompt, tool cards,
# the Tools & controls page, notices) asks here, so prompts follow the device
# (owner, 2026-09-29: "controller prompts if a controller is detected").

signal device_changed(pad: bool)

## Xbox face-button colours, for badges.
const PAD_COLOURS := {0: Color(0.36, 0.75, 0.25), 1: Color(0.86, 0.25, 0.22),
	2: Color(0.2, 0.5, 0.95), 3: Color(0.95, 0.75, 0.15)}
const PAD_BUTTONS := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 5: "Xbox", 6: "Menu",
	7: "Left stick click", 8: "Right stick click", 9: "LB", 10: "RB",
	11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}
const PAD_AXES := {0: "Left stick", 1: "Left stick", 2: "Right stick", 3: "Right stick", 4: "LT", 5: "RT"}
const MOUSE_BUTTONS := {1: "Left click", 2: "Right click", 3: "Middle click", 4: "Wheel up", 5: "Wheel down"}
const KEY_SHORT := {"Escape": "Esc", "Enter": "Enter", "Kp Enter": "Enter"}
## Groups of actions that read better as one thing.
const COMPOSITE := {
	"move": ["WASD", "Left stick"],
	"look": ["Mouse", "Right stick"],
	"zoom": ["Mouse wheel", "D-pad"],
}

## True while the last input came from a pad.
var pad := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS           # menus pause the game; keep listening
	pad = not Input.get_connected_joypads().is_empty()
	# the game's look for every menu and panel (scripts/ui/ui_style.gd)
	get_tree().root.theme = preload("res://scripts/ui/ui_style.gd").theme()

func _input(event: InputEvent) -> void:
	var from_pad := pad
	if event is InputEventJoypadButton:
		from_pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		from_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		from_pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		from_pad = false
	if from_pad != pad:
		pad = from_pad
		device_changed.emit(pad)

## The button for an action on the current device ("E", "RT", "Left click"...).
func label(action: String) -> String:
	if COMPOSITE.has(action):
		return COMPOSITE[action][1 if pad else 0]
	if not InputMap.has_action(action):
		return action
	var fallback := ""
	for event in InputMap.action_get_events(action):
		var name := _event_name(event)
		if name == "":
			continue
		if _is_pad(event) == pad:
			return name
		if fallback == "":
			fallback = name
	return fallback if fallback != "" else action

## "[E]" style, for text.
func text(action: String) -> String:
	return "[%s]" % label(action)

## A badge colour for an action's button (Xbox face colours; grey otherwise).
func colour(action: String) -> Color:
	if pad and InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and PAD_COLOURS.has((event as InputEventJoypadButton).button_index):
				return PAD_COLOURS[(event as InputEventJoypadButton).button_index]
	return Color(0.28, 0.3, 0.33)

## A rounded button badge (a PanelContainer with the label), for menus and cards.
func badge(action: String, font_size: int = 20) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = colour(action)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.border_color = Color(1, 1, 1, 0.35)
	style.set_border_width_all(2)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_label := Label.new()
	text_label.text = label(action)
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text_label)
	return box

func _is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion

func _event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_NONE:
			return ""
		var name := OS.get_keycode_string(code)
		if key.alt_pressed:
			name = "Alt+" + name
		return KEY_SHORT.get(name, name)
	if event is InputEventMouseButton:
		return MOUSE_BUTTONS.get((event as InputEventMouseButton).button_index, "Mouse")
	if event is InputEventJoypadButton:
		return PAD_BUTTONS.get((event as InputEventJoypadButton).button_index, "Pad")
	if event is InputEventJoypadMotion:
		return PAD_AXES.get((event as InputEventJoypadMotion).axis, "Stick")
	return ""
