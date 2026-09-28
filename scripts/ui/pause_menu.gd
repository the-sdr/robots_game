extends CanvasLayer

# Esc pauses. Resume, back to the main menu, or quit. Nothing is saved here on
# purpose: saving is what docking at a charger does.

@onready var resume_button: Button = %ResumeButton
@onready var menu_button: Button = %MenuButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(toggle)
	menu_button.pressed.connect(_to_menu)
	quit_button.pressed.connect(func() -> void: get_tree().quit())

# The player is paused while this is open, so Esc is handled here.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		resume_button.grab_focus()

func _to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
