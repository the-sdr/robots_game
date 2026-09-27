extends Control

# Opening menu. Continue loads the autosave (written whenever the robot docks);
# New Game starts at the house charger.

const WORLD := "res://scenes/world.tscn"

@onready var continue_button: Button = %ContinueButton
@onready var new_button: Button = %NewButton
@onready var quit_button: Button = %QuitButton
@onready var info_label: Label = %InfoLabel

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Clock.running = false
	continue_button.disabled = not Game.has_save()
	continue_button.pressed.connect(_continue)
	new_button.pressed.connect(_new_game)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	if Game.has_save() and Game.load_save():
		info_label.text = "Last copy: day %d, %s" % [Game.data["day"], Clock.time_text()]
	else:
		info_label.text = ""
	(continue_button if not continue_button.disabled else new_button).grab_focus()

func _continue() -> void:
	if Game.load_save():
		Game.pending_load = true
		get_tree().change_scene_to_file(WORLD)

func _new_game() -> void:
	Game.new_game()
	get_tree().change_scene_to_file(WORLD)
