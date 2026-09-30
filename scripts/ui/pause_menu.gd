extends CanvasLayer

# Esc pauses. Resume, back to the main menu, or quit. Nothing is saved here on
# purpose: saving is what docking at a charger does.

@onready var resume_button: Button = %ResumeButton
@onready var menu_button: Button = %MenuButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	var controls := Button.new()
	controls.name = "ControlsButton"
	controls.text = "Help and controls (F1)"
	controls.custom_minimum_size = resume_button.custom_minimum_size
	controls.add_theme_font_size_override("font_size", resume_button.get_theme_font_size("font_size"))
	controls.pressed.connect(func() -> void: get_tree().call_group("hud", "open_help", "Controls"))
	resume_button.add_sibling(controls)
	var notes := Button.new()
	notes.name = "NotesButton"
	notes.text = "Testing notes"
	notes.custom_minimum_size = resume_button.custom_minimum_size
	notes.add_theme_font_size_override("font_size", resume_button.get_theme_font_size("font_size"))
	notes.pressed.connect(func() -> void: get_tree().call_group("hud", "open_help", "Testing notes"))
	controls.add_sibling(notes)
	resume_button.pressed.connect(toggle)
	menu_button.pressed.connect(_to_menu)
	quit_button.pressed.connect(func() -> void: get_tree().quit())

# The player is paused while this is open, so Esc is handled here.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and not _controls_open():
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		resume_button.grab_focus()

func _controls_open() -> bool:
	var hud := get_tree().get_first_node_in_group("hud")
	return hud != null and hud.tool_card != null and (hud.tool_card.page_open() or hud.tool_card.card_open() or hud.help_menu.is_open())

## Back from the Tools & controls page.
func focus_first() -> void:
	if visible:
		resume_button.grab_focus()

func _to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
