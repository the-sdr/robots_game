extends CanvasLayer

# F1 (pad: D-pad down): the player's help (owner, 2026-09-30). Tabs:
#   Controls       - every button for the device in hand, the tools you have
#                    (their cards again) and the testing keys (F2-F11)
#   Testing notes  - what this sprint asks the playtester to look at
#                    (playtest/testing_notes.json, kept current by Claude)
#   Map            - in the game only: the as-built map with the robot on it
# LB / RB (or Q) switch tabs, the sticks / arrows scroll, B / Esc / F1 close.
# The HUD owns one (in_game); the main menu makes its own without the map.

const STYLE := preload("res://scripts/ui/ui_style.gd")
const NOTES := "res://playtest/testing_notes.json"
const MAP := "res://level_design/maps/forest_map_v3_built.png"
# tools/forest_map.py's frame: world area, pixels per metre, margin, map width (the legend is cut off)
const MAP_X0 := -42.0
const MAP_Z0 := -96.0
const MAP_X1 := 42.0
const MAP_Z1 := 16.0
const MAP_S := 9.0
const MAP_M := 46.0
const MAP_W := 848
const TABS := ["Controls", "Testing notes", "Map"]
const SCROLL_SPEED := 900.0

@export var in_game := true

var tab := "Controls"
var _was_paused := false
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _dim: ColorRect
var _tab_buttons := {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _map_texture: Texture2D

static func load_notes() -> Dictionary:
	if not FileAccess.file_exists(NOTES):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOTES))
	return parsed if parsed is Dictionary else {}

## Where a world position sits on the built map (pixels), for the robot marker.
static func map_pixel(world: Vector3) -> Vector2:
	return Vector2(MAP_M + (world.x - MAP_X0) * MAP_S, MAP_M + (world.z - MAP_Z0) * MAP_S)

static func on_map(world: Vector3) -> bool:
	return world.x >= MAP_X0 and world.x <= MAP_X1 and world.z >= MAP_Z0 and world.z <= MAP_Z1

func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	Glyphs.device_changed.connect(func(_pad: bool) -> void:
		if visible:
			_show_tab(tab))

func is_open() -> bool:
	return visible

func open(which: String = "Controls") -> void:
	if not visible:
		_was_paused = get_tree().paused
		_old_mouse = Input.mouse_mode
		if in_game:
			get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_show_tab(which)

func close() -> void:
	if not visible:
		return
	visible = false
	if in_game:
		get_tree().paused = _was_paused
		Input.mouse_mode = _old_mouse
	get_tree().call_group("main_menu", "focus_first")
	get_tree().call_group("pause_menu", "focus_first")

func _tabs() -> Array:
	return TABS if in_game else TABS.slice(0, 2)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.is_action_pressed("help")):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_tool"):
		var tabs := _tabs()
		var step := -1 if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_show_tab(tabs[(tabs.find(tab) + step + tabs.size()) % tabs.size()])
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	var axis := Input.get_axis("move_forward", "move_back") + Input.get_axis("look_up", "look_down") + Input.get_axis("ui_up", "ui_down")
	if absf(axis) > 0.2:
		_scroll.scroll_vertical += int(axis * SCROLL_SPEED * delta)

# --- building ---------------------------------------------------------------------------------
func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.02, 0.03, 0.7)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", STYLE.panel_style(0.7))
	panel.custom_minimum_size = Vector2(1000, 640)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var title := STYLE.label("HELP", 40, STYLE.CYAN)
	title.add_theme_font_override("font", STYLE.title_font())
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	header.add_child(spacer)
	for name in TABS:
		var b := Button.new()
		b.text = name
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE           # LB / RB switch tabs; the focus stays in the page
		b.pressed.connect(_show_tab.bind(name))
		header.add_child(b)
		_tab_buttons[name] = b
	var line := ColorRect.new()
	line.color = Color(STYLE.CYAN, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	box.add_child(line)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	footer.add_child(STYLE.label("", 16, STYLE.DIM))          # filled per device in _show_tab
	footer.name = "Footer"

func _show_tab(which: String) -> void:
	if not _tabs().has(which):
		which = "Controls"
	tab = which
	for name in _tab_buttons:
		var b: Button = _tab_buttons[name]
		b.visible = _tabs().has(name)
		b.button_pressed = name == which
	for child in _content.get_children():
		child.queue_free()
	match which:
		"Controls":
			_fill_controls()
		"Testing notes":
			_fill_notes()
		"Map":
			_fill_map()
	_scroll.scroll_vertical = 0
	var footer: HBoxContainer = find_child("Footer", true, false)
	(footer.get_child(0) as Label).text = ("B close      LB / RB switch tabs      sticks scroll" if Glyphs.pad
		else "Esc or F1 close      Q switch tabs      W / S or mouse wheel scroll")

func _heading(text: String) -> void:
	var l := STYLE.label(text, 24, STYLE.CYAN)
	l.add_theme_font_override("font", STYLE.font(600))
	_content.add_child(l)

func _row(action: String, what: String, parent: Container) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var b := Glyphs.badge(action)
	b.custom_minimum_size = Vector2(170, 0)
	line.add_child(b)
	line.add_child(STYLE.label(what, 19))
	parent.add_child(line)

func _fill_controls() -> void:
	_heading("Getting around" + ("  (controller)" if Glyphs.pad else "  (keyboard and mouse)"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for row in [["move", "Drive"], ["look", "Look around"], ["jump", "Jump"], ["interact", "Use, dock, dig, open"],
			["use_tool", "Use the tool"], ["cycle_tool", "Next tool"], ["detector", "Detector on / off"],
			["inventory", "Parts and building"], ["pause", "Pause"], ["help", "This help"], ["ui_cancel", "Back / close a card"]]:
		_row(row[0], row[1], grid)
	_heading("In a fight")
	var fight := GridContainer.new()
	fight.columns = 2
	fight.add_theme_constant_override("h_separation", 40)
	fight.add_theme_constant_override("v_separation", 8)
	_content.add_child(fight)
	for row in [["combat_slot_1", "Use the tool in kit slot 1"], ["combat_slot_2", "Kit slot 2"], ["combat_slot_3", "Kit slot 3"],
			["combat_timing", "On the beat: hit, or dodge its attack"]]:
		_row(row[0], row[1], fight)
	var more := STYLE.label("Hold %s or %s with a tool's button for its other moves." % ["the stick up" if Glyphs.pad else "W", "down" if Glyphs.pad else "S"], 18, STYLE.DIM)
	_content.add_child(more)
	var tools: Array = Game.data.get("tools", [])
	if not tools.is_empty():
		_heading("Your tools")
		var cards := preload("res://scripts/ui/tool_card.gd")
		for tool_id in tools:
			if not cards.CARDS.has(tool_id):
				continue
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 14)
			line.add_child(STYLE.label(Catalog.tool_name(tool_id), 20, STYLE.WARM))
			line.add_child(STYLE.label(String(cards.CARDS[tool_id]["text"]), 17, STYLE.DIM))
			(line.get_child(1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(line.get_child(1) as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if in_game:
				var how := Button.new()
				how.text = "How"
				how.pressed.connect(func() -> void:
					close()
					get_tree().call_group("hud", "show_tool_card", tool_id))
				line.add_child(how)
			_content.add_child(line)
	_heading("Testing keys (keyboard)")
	for row in [["F2", "Position, facing and FPS"], ["F3", "Save this spot with a note and a picture"],
			["F4", "Log 5 seconds of performance"], ["F7", "God mode: double-tap jump to fly"], ["F11", "Fullscreen"]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var b := STYLE.badge(row[0])
		b.custom_minimum_size = Vector2(170, 0)
		line.add_child(b)
		line.add_child(STYLE.label(row[1], 19))
		_content.add_child(line)

func _fill_notes() -> void:
	var notes := load_notes()
	if notes.is_empty():
		_heading("No testing notes yet")
		return
	var sprint := STYLE.label(String(notes.get("sprint", "")), 26, STYLE.CYAN)
	sprint.add_theme_font_override("font", STYLE.font(600))
	sprint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(sprint)
	var intro := STYLE.label("%s   (updated %s)" % [notes.get("intro", ""), notes.get("updated", "")], 18, STYLE.DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	for item in notes.get("items", []):
		_content.add_child(note_card(item))

## One testing-notes item: its title, what to try, what to tell us.
static func note_card(item: Dictionary, compact: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := STYLE.label(String(item.get("title", "")), 21 if not compact else 18, STYLE.WARM)
	title.add_theme_font_override("font", STYLE.font(600))
	box.add_child(title)
	for part in [["Try", "try"], ["Tell us", "ask"]]:
		if item.has(part[1]):
			var l := STYLE.label("%s: %s" % [part[0], item[part[1]]], 17 if not compact else 15, STYLE.INK if part[1] == "try" else STYLE.DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(300, 0)
			box.add_child(l)
	return box

func _fill_map() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _map_texture == null:
		var image := Image.load_from_file(ProjectSettings.globalize_path(MAP))
		if image != null and not image.is_empty():
			_map_texture = ImageTexture.create_from_image(image.get_region(Rect2i(0, 0, mini(MAP_W, image.get_width()), image.get_height())))
	if _map_texture == null:
		_heading("The map isn't available in this build")
		return
	var where := "You are the arrow." if player != null and on_map(player.global_position) else "You're off this map: the city lies north of it."
	_content.add_child(STYLE.label("The forest as built (a testing map: red marks are finds). " + where, 17, STYLE.DIM))
	var frame := MapView.new()
	frame.texture = _map_texture
	frame.player = player
	frame.custom_minimum_size = Vector2(900, 900.0 * _map_texture.get_height() / _map_texture.get_width())
	_content.add_child(frame)

## The map, scaled to fit, with the robot drawn on it as an arrow.
class MapView extends Control:
	var texture: Texture2D
	var player: Node3D

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var k := size.x / texture.get_width()
		draw_texture_rect(texture, Rect2(Vector2.ZERO, texture.get_size() * k), false)
		if player == null or not is_instance_valid(player):
			return
		var pos: Vector3 = player.global_position
		var at := (Vector2(42.0 + 46.0 / 9.0 + pos.x, 96.0 + 46.0 / 9.0 + pos.z) * 9.0) * k
		at = at.clamp(Vector2(8, 8), size - Vector2(8, 8))
		var visual := player.get_node_or_null("Visual") as Node3D
		var yaw: float = visual.global_rotation.y if visual != null else 0.0
		var ahead := Vector2(-sin(yaw), -cos(yaw))        # the robot faces its Visual's -Z
		var side := Vector2(-ahead.y, ahead.x)
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
		draw_circle(at, 16.0 * pulse, Color(0.45, 0.95, 1.0, 0.25))
		draw_colored_polygon(PackedVector2Array([at + ahead * 14.0, at - ahead * 8.0 + side * 8.0, at - ahead * 3.0, at - ahead * 8.0 - side * 8.0]), Color(0.1, 0.55, 0.7))
		draw_polyline(PackedVector2Array([at + ahead * 14.0, at - ahead * 8.0 + side * 8.0, at - ahead * 3.0, at - ahead * 8.0 - side * 8.0, at + ahead * 14.0]), Color.WHITE, 2.0)
