extends Control

# Opening menu. Pick the game first: Silly or Serious (owner, 2026-10-02: two
# games on one engine, like Breath of the Wild and Tears of the Kingdom). Each
# has its own save; Continue loads that mode's autosave (written whenever the
# robot docks), New Game starts it at the house charger. The pick is remembered.
# On the right, the testing notes slide in at start (owner, 2026-09-30: what
# this sprint asks the playtester to look at, so nobody has to scroll a
# terminal to remember). Help and controls opens the same F1 menu as in the
# game; the bottom bar says which buttons open it there (F1 / D-pad down).

const WORLD := "res://scenes/world.tscn"
const STYLE := preload("res://scripts/ui/ui_style.gd")
const HELP := preload("res://scripts/ui/help_menu.gd")

@onready var silly_button: Button = %SillyButton
@onready var serious_button: Button = %SeriousButton
@onready var mode_label: Label = %ModeLabel
@onready var subtitle: Label = $Left/VBox/Subtitle
@onready var continue_button: Button = %ContinueButton
@onready var new_button: Button = %NewButton
@onready var help_button: Button = %HelpButton
@onready var notes_button: Button = %NotesButton
@onready var quit_button: Button = %QuitButton
@onready var info_label: Label = %InfoLabel
@onready var title: Label = %Title

var help_menu: CanvasLayer
var notes_panel: PanelContainer

func _ready() -> void:
	add_to_group("main_menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Clock.running = false
	title.add_theme_font_override("font", STYLE.title_font())
	var group := ButtonGroup.new()
	silly_button.button_group = group
	serious_button.button_group = group
	silly_button.pressed.connect(pick_mode.bind("silly"))
	serious_button.pressed.connect(pick_mode.bind("serious"))
	continue_button.pressed.connect(_continue)
	new_button.pressed.connect(_new_game)
	help_button.pressed.connect(func() -> void: help_menu.open("Controls"))
	notes_button.pressed.connect(func() -> void: help_menu.open("Testing notes"))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	_show_mode()
	help_menu = HELP.new()
	help_menu.name = "HelpMenu"
	help_menu.in_game = false
	add_child(help_menu)
	_build_notes_panel()
	_build_help_bar()
	focus_first()

func focus_first() -> void:
	(continue_button if not continue_button.disabled else new_button).grab_focus()

# --- which game ------------------------------------------------------------------------------
const MODE_BLURB := {
	"silly": "Wobbly robot, grumpy zombie, lots of BOING. For the little ones.",
	"serious": "Rust, ruins and a long-dead city. Something is still switched on.",
}
const MODE_SUBTITLE := {
	"silly": "Beep boop! Something is still switched on.",
	"serious": "Something is still switched on.",
}

func pick_mode(new_mode: String) -> void:
	Settings.set_mode(new_mode)
	_show_mode()

## The selected mode's buttons, blurb and save.
func _show_mode() -> void:
	var m: String = Game.mode
	silly_button.set_pressed_no_signal(m == "silly")
	serious_button.set_pressed_no_signal(m == "serious")
	mode_label.text = MODE_BLURB[m]
	subtitle.text = MODE_SUBTITLE[m]
	continue_button.disabled = not Game.has_save()
	if Game.has_save() and Game.load_save():
		info_label.text = "%s: last copy day %d, %s" % [Settings.mode_name(), Game.data["day"], Clock.time_text()]
	else:
		info_label.text = "%s: no save yet" % Settings.mode_name()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("help") and not help_menu.is_open():
		help_menu.open("Controls")
		get_viewport().set_input_as_handled()

# --- the testing notes, on the right ---------------------------------------------------------
func _build_notes_panel() -> void:
	var notes := HELP.load_notes()
	notes_panel = PanelContainer.new()
	notes_panel.name = "NotesPanel"
	notes_panel.add_theme_stylebox_override("panel", STYLE.panel_style(0.6))
	notes_panel.anchor_left = 1.0
	notes_panel.anchor_right = 1.0
	notes_panel.anchor_top = 0.0
	notes_panel.anchor_bottom = 1.0
	notes_panel.offset_left = -620
	notes_panel.offset_right = -60
	notes_panel.offset_top = 60
	notes_panel.offset_bottom = -110
	add_child(notes_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	notes_panel.add_child(box)
	var heading := STYLE.label("TESTING NOTES", 34, STYLE.CYAN)
	heading.add_theme_font_override("font", STYLE.title_font())
	box.add_child(heading)
	if notes.is_empty():
		box.add_child(STYLE.label("No testing notes for this build.", 18, STYLE.DIM))
		return
	var sprint := STYLE.label(String(notes.get("sprint", "")), 20, STYLE.INK)
	sprint.add_theme_font_override("font", STYLE.font(600))
	sprint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sprint)
	var intro := STYLE.label("%s   (updated %s)" % [notes.get("intro", ""), notes.get("updated", "")], 16, STYLE.DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "Items"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var n := 0
	for item in notes.get("items", []):
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var number := STYLE.label("%d" % n, 26, Color(STYLE.CYAN, 0.7))
		number.add_theme_font_override("font", STYLE.title_font())
		number.custom_minimum_size = Vector2(26, 0)
		row.add_child(number)
		var card := HELP.note_card(item, true)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		list.add_child(row)
	# it slides in from the right when the menu opens: the first thing to read
	notes_panel.offset_left += 700
	notes_panel.offset_right += 700
	notes_panel.modulate.a = 0.0
	var slide := create_tween().set_parallel(true)
	slide.tween_property(notes_panel, "offset_left", -620.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.25)
	slide.tween_property(notes_panel, "offset_right", -60.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.25)
	slide.tween_property(notes_panel, "modulate:a", 1.0, 0.5).set_delay(0.25)

# --- which buttons open help, keyboard and pad ------------------------------------------------
func _build_help_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "HelpBar"
	bar.add_theme_constant_override("separation", 10)
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 80
	bar.offset_right = -60
	bar.offset_top = -70
	bar.offset_bottom = -30
	add_child(bar)
	bar.add_child(STYLE.label("In the game:", 19, STYLE.DIM))
	bar.add_child(STYLE.badge("F1", Color(0.28, 0.3, 0.33), 18))
	bar.add_child(STYLE.label("or", 19, STYLE.DIM))
	bar.add_child(STYLE.badge("D-pad down", Color(0.2, 0.36, 0.42), 18))
	bar.add_child(STYLE.label("opens Help: controls, testing notes and the map.", 19, STYLE.INK))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	bar.add_child(STYLE.badge("Esc", Color(0.28, 0.3, 0.33), 16))
	bar.add_child(STYLE.badge("B", Glyphs.PAD_COLOURS[1], 16))
	bar.add_child(STYLE.label("back", 17, STYLE.DIM))
	bar.add_child(STYLE.badge("F11", Color(0.28, 0.3, 0.33), 16))
	bar.add_child(STYLE.label("fullscreen", 17, STYLE.DIM))

func _continue() -> void:
	if Game.load_save():
		Game.pending_load = true
		get_tree().change_scene_to_file(WORLD)

func _new_game() -> void:
	Game.new_game()
	Game.play_intro = true
	get_tree().change_scene_to_file(WORLD)
