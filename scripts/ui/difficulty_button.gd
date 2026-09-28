extends Button

# One button that cycles Easy -> Medium -> Hard. Used on the main menu and the
# pause menu; a single press target is simpler for small hands than a dropdown,
# and works the same with mouse, keyboard and gamepad (also while paused).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pressed.connect(Settings.next_difficulty)
	Settings.difficulty_changed.connect(func(_level: String) -> void: _refresh())
	_refresh()

func _refresh() -> void:
	text = "Difficulty: %s" % Settings.difficulty_name()
	tooltip_text = "Changes fights only. Easy: slow timing, big hints, the first fight can't be lost."
