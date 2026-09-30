extends CanvasLayer

# Debug overlay toggled with F2 (action "toggle_coords"). Shows the player's
# position in Godot world units (1 unit = 1 m) and headings on a compass
# mapped onto the world axes: North = -Z, East = +X, South = +Z, West = -X.
# Headings are degrees clockwise from North, as on a real compass.
# Also shows FPS and frame time.
#
# F3 (action "save_position") appends the current position to SAVE_FILE as
# save_1, save_2, ... so a playtest spot can be referred to by name in chat.
# F4 (action "log_performance") measures for PERF_SECONDS and appends frame
# times, draw calls and triangles to PERF_FILE as perf_1, perf_2, ...
# Numbering continues from the highest entry already in each file.
#
# Both then pause the game and ask for a playtest note (Enter = log it with
# the note, Esc = log it without). The note is written on its own line under
# the entry, so feedback is read from these files instead of pasted into chat.
# F4 measures first and asks afterwards: an open text box would skew the numbers.
# F3 also keeps a screenshot of what was on screen when it was pressed (before
# the note box opens): playtest/shots/save_N.jpg, named on the entry's line, so
# Claude can see what the player saw (owner, 2026-09-29).
#
# While the player's god mode (F7) is on, a status line is shown as well.
#
# F10 / F9 open the tuning panels (scripts/ui/tuning_panel.gd): tool and
# detector feel numbers, live; closing one logs its values to TUNING_FILE as
# tune_N, and F3 entries list any values changed from the game's.

const DIRECTIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SAVE_FILE := "playtest/saves.md"
const PERF_FILE := "playtest/perf.md"
const NOTICE_SECONDS := 4.0
const PERF_SECONDS := 5.0

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label

## Folder the logs go in. Empty = res:// in the editor, user:// in an export
## (res:// is read-only there). Tests point it elsewhere.
var log_root := ""

var _player: Node3D
var _player_visual: Node3D
var _pinned_visible := false
var _notice := ""
var _notice_time_left := 0.0
var _last_god_mode := false
var _frame_ms := 16.7
var _perf_samples: Array[Dictionary] = []
var _perf_time_left := 0.0

var _note_box: PanelContainer
var _note_title: Label
var _note_edit: LineEdit
var _pending: Dictionary = {}          # the entry waiting for its note
var _was_paused := false
var _old_mouse_mode := Input.MOUSE_MODE_CAPTURED

var tuning: CanvasLayer

func _ready() -> void:
	panel.visible = false
	add_to_group("coord_overlay")
	tuning = preload("res://scripts/ui/tuning_panel.gd").new()
	tuning.name = "TuningPanel"
	tuning.logger = self
	add_child(tuning)
	# Debug overlay only; gameplay notices go to the HUD (group "hud").
	# Always processing so the note box works while the game is paused for it;
	# _process and the F-keys below still stop while anything else pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_note_box()

func note_open() -> bool:
	return _note_box.visible

# _input, before the text box: a LineEdit may keep Esc for itself.
func _input(event: InputEvent) -> void:
	if note_open() and event.is_action_pressed("ui_cancel"):
		_finish_note("")
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if note_open() or get_tree().paused:
		return
	if event.is_action_pressed("tune_tools"):
		tuning.toggle("tools")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tune_detector"):
		tuning.toggle("detector")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_coords"):
		_pinned_visible = not _pinned_visible
	if event.is_action_pressed("save_position"):
		_save_position()
	if event.is_action_pressed("log_performance") and _perf_time_left <= 0.0:
		_perf_samples.clear()
		_perf_time_left = PERF_SECONDS

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	if _perf_time_left > 0.0:
		_sample_performance(delta)
	_notice_time_left = maxf(_notice_time_left - delta, 0.0)
	var god_mode: bool = _find_player() and _player.get("god_mode") == true
	if god_mode != _last_god_mode:
		_last_god_mode = god_mode
		show_notice("God mode %s" % ("ON" if god_mode else "OFF"))
	panel.visible = _pinned_visible or _notice_time_left > 0.0 or _perf_time_left > 0.0
	if not panel.visible or _player == null:
		return

	var lines: Array[String] = []
	if _perf_time_left > 0.0:
		lines.append("Measuring... %.0f s" % ceilf(_perf_time_left))
	if _notice_time_left > 0.0:
		lines.append(_notice)
	if god_mode:
		lines.append("GOD  %s" % ("flying" if _player.get("flying") else "2x Space = fly"))
	lines.append("FPS %3d  %5.1f ms" % [roundi(1000.0 / maxf(_frame_ms, 0.1)), _frame_ms])
	lines.append_array(_describe_position())
	lines.append("N=-Z  E=+X")
	label.text = "\n".join(lines)

func _find_player() -> bool:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player != null:
			_player_visual = _player.get_node_or_null("Visual") as Node3D
	return _player != null

func _describe_position() -> Array[String]:
	var pos: Vector3 = _player.global_position
	var lines: Array[String] = []
	lines.append("X %+7.1f" % pos.x)
	lines.append("Y %+7.1f" % pos.y)
	lines.append("Z %+7.1f" % pos.z)
	if _player_visual != null:
		lines.append("Facing  %s" % _heading_text(-_player_visual.global_basis.z))
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		lines.append("Camera  %s" % _heading_text(-camera.global_basis.z))
		lines.append("Pitch   %+4d°" % int(round(camera.global_rotation_degrees.x)))
	return lines

func _heading_text(dir: Vector3) -> String:
	var degrees: float = fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	var index: int = int(round(degrees / 45.0)) % 8
	return "%-2s %03d°" % [DIRECTIONS[index], int(round(degrees)) % 360]

func _save_position() -> void:
	if not _find_player():
		return
	var details: String = "  ".join(_describe_position()) + "  FPS %d" % roundi(1000.0 / maxf(_frame_ms, 0.1))
	var T := preload("res://scripts/game/tuning.gd")
	var tuned := (T.summary("tools", true) + " " + T.summary("detector", true)).strip_edges()
	if tuned != "":
		details += "  —  tuned: " + tuned
	_ask_note({
		"file": SAVE_FILE, "prefix": "save", "details": details, "notice": "Saved %s",
		"shot": _grab_screen(),
		"header": "# Playtest saves (F3). North = -Z, East = +X. Headings clockwise from North.",
		"title": "%s at X %.1f  Z %.1f: what's here?",
	})

func _sample_performance(delta: float) -> void:
	_perf_samples.append({
		"ms": delta * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	})
	_perf_time_left -= delta
	if _perf_time_left > 0.0 or not _find_player():
		return
	_perf_time_left = 0.0
	var total := 0.0
	var worst := 0.0
	var draw_calls := 0.0
	var triangles := 0.0
	var objects := 0.0
	for s in _perf_samples:
		total += s["ms"]
		worst = maxf(worst, s["ms"])
		draw_calls += s["draw_calls"]
		triangles += s["triangles"]
		objects += s["objects"]
	var n := float(_perf_samples.size())
	var avg := total / n
	var fps := roundi(1000.0 / avg)
	# The machine goes in the line: x86_64 = the laptop, arm64 = the Surface.
	var machine := "%s, %s, %s" % [Engine.get_architecture_name(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_current_rendering_driver_name()]
	var details := "avg %.1f ms (%d FPS), worst %.1f ms, draw calls %d, triangles %.2fM, objects %d, %s, %s  —  %s" % [
		avg, fps, worst, roundi(draw_calls / n), triangles / n / 1e6, roundi(objects / n),
		RenderingServer.get_current_rendering_method(), machine, "  ".join(_describe_position())]
	_ask_note({
		"file": PERF_FILE, "prefix": "perf", "details": details, "notice": "Logged %%s: %d FPS" % fps,
		"header": "# Performance logs (F4): %d s averages. North = -Z, East = +X." % int(PERF_SECONDS),
		"title": "%%s: %d FPS. What are you looking at?" % fps,
	})

# Pauses the game and opens the note box for an entry; it is written by _finish_note.
func _ask_note(entry: Dictionary) -> void:
	_pending = entry
	var entry_name := "%s_%d" % [entry["prefix"], _highest_number(_read_log(entry["file"]), entry["prefix"]) + 1]
	var title: String = entry["title"]
	if entry["prefix"] == "save":
		title = title % [entry_name, _player.global_position.x, _player.global_position.z]
	else:
		title = title % entry_name
	_note_title.text = title
	_note_edit.clear()
	_was_paused = get_tree().paused
	_old_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_note_box.visible = true
	panel.visible = false
	_note_edit.grab_focus()

func _finish_note(note: String) -> void:
	if not note_open():
		return
	_note_box.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _old_mouse_mode
	var entry: Dictionary = _pending
	_pending = {}
	if entry.get("shot") != null:
		var entry_name := "%s_%d" % [entry["prefix"], _highest_number(_read_log(entry["file"]), entry["prefix"]) + 1]
		var shot_path := save_shot(entry["shot"], entry_name)
		if shot_path != "":
			entry["details"] = String(entry["details"]) + "  —  shot: " + shot_path
	var written := _append_entry(entry["file"], entry["prefix"], entry["header"], entry["details"], note.strip_edges())
	if written != "":
		show_notice(String(entry["notice"]) % written)

## What is on screen right now (null when nothing is rendered, e.g. headless).
const TUNING_FILE := "playtest/tuning.md"

## The tuning panel's log (tune_1, tune_2...): every value on the panel as it closed.
func log_tuning(_panel: String, details: String) -> void:
	var entry := _append_entry(TUNING_FILE, "tune",
		"# Tuning (F10 tools, F9 detector): the values as each panel closed. * = changed from the game's.", details)
	if entry != "":
		show_notice("Logged %s" % entry)

func _grab_screen() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture := get_viewport().get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	return image if image != null and not image.is_empty() else null

const SHOT_WIDTH := 1280         # screenshots are scaled down to this: enough to read, small in git

## Saves a screenshot as playtest/shots/<entry>.jpg and returns that path (relative
## to the log folder), or "" if it couldn't be written.
func save_shot(image: Image, entry_name: String) -> String:
	var relative := "playtest/shots/%s.jpg" % entry_name
	var path := _log_path(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var copy := image.duplicate() as Image
	if copy.get_width() > SHOT_WIDTH:
		copy.resize(SHOT_WIDTH, roundi(copy.get_height() * float(SHOT_WIDTH) / copy.get_width()), Image.INTERPOLATE_BILINEAR)
	if copy.save_jpg(path, 0.82) != OK:
		push_warning("Could not save screenshot %s" % path)
		return ""
	return relative

func _build_note_box() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_note_box = PanelContainer.new()
	_note_box.name = "NoteBox"
	_note_box.add_theme_stylebox_override("panel", style)
	_note_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	_note_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_note_box.visible = false
	var vbox := VBoxContainer.new()
	_note_box.add_child(vbox)
	_note_title = Label.new()
	_note_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_note_title)
	_note_edit = LineEdit.new()
	_note_edit.custom_minimum_size = Vector2(720, 0)
	_note_edit.placeholder_text = "Playtest note (optional)"
	_note_edit.add_theme_font_size_override("font_size", 18)
	_note_edit.text_submitted.connect(_finish_note)
	# Clicking outside the box must not leave the keyboard nowhere.
	_note_edit.focus_exited.connect(func() -> void:
		if note_open():
			_note_edit.grab_focus.call_deferred())
	vbox.add_child(_note_edit)
	var hint := Label.new()
	hint.text = "Enter = save with note     Esc = save without note"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(hint)
	add_child(_note_box)

func _log_path(relative_path: String) -> String:
	if log_root != "":
		return log_root.path_join(relative_path)
	# res:// is only writable when running from the editor.
	return ("res://" if OS.has_feature("editor") else "user://") + relative_path

func _read_log(relative_path: String) -> String:
	var path := _log_path(relative_path)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

# Appends "- **<prefix>_N** — time — details" (and an indented note line) to a
# log and returns the entry name.
func _append_entry(relative_path: String, prefix: String, header: String, details: String, note := "") -> String:
	var path := _log_path(relative_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var existing := _read_log(relative_path)
	var entry := "%s_%d" % [prefix, _highest_number(existing, prefix) + 1]
	var file := FileAccess.open(path, FileAccess.READ_WRITE if existing != "" else FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	if existing == "":
		file.store_line(header)
		file.store_line("")
	file.seek_end()
	file.store_line("- **%s** — %s — %s" % [entry, Time.get_datetime_string_from_system(false, true), details])
	if note != "":
		file.store_line("  - **Note:** %s" % note)
	file.close()
	print("%s: %s%s" % [entry, details, ("  NOTE: " + note) if note != "" else ""])
	return entry

func show_notice(text: String) -> void:
	_notice = text
	_notice_time_left = NOTICE_SECONDS

# Only the bold entry names count, so a note mentioning "save_12" can't skip numbers.
func _highest_number(text: String, prefix: String) -> int:
	var regex := RegEx.create_from_string("\\*\\*" + prefix + "_(\\d+)\\*\\*")
	var highest := 0
	for found in regex.search_all(text):
		highest = maxi(highest, found.get_string(1).to_int())
	return highest
