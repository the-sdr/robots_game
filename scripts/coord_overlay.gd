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
# While the player's god mode (F7) is on, a status line is shown as well.

const DIRECTIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SAVE_FILE := "playtest/saves.md"
const PERF_FILE := "playtest/perf.md"
const NOTICE_SECONDS := 4.0
const PERF_SECONDS := 5.0

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label

var _player: Node3D
var _player_visual: Node3D
var _pinned_visible := false
var _notice := ""
var _notice_time_left := 0.0
var _last_god_mode := false
var _frame_ms := 16.7
var _perf_samples: Array[Dictionary] = []
var _perf_time_left := 0.0

func _ready() -> void:
	panel.visible = false
	add_to_group("hud")   # anything can call_group("hud", "show_notice", text)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_coords"):
		_pinned_visible = not _pinned_visible
	if event.is_action_pressed("save_position"):
		_save_position()
	if event.is_action_pressed("log_performance") and _perf_time_left <= 0.0:
		_perf_samples.clear()
		_perf_time_left = PERF_SECONDS

func _process(delta: float) -> void:
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
	var entry := _append_entry(SAVE_FILE, "save",
		"# Playtest saves (F3). North = -Z, East = +X. Headings clockwise from North.", details)
	if entry != "":
		show_notice("Saved %s" % entry)

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
	var details := "avg %.1f ms (%d FPS), worst %.1f ms, draw calls %d, triangles %.2fM, objects %d, %s  —  %s" % [
		avg, roundi(1000.0 / avg), worst, roundi(draw_calls / n), triangles / n / 1e6, roundi(objects / n),
		RenderingServer.get_current_rendering_method(), "  ".join(_describe_position())]
	var entry := _append_entry(PERF_FILE, "perf",
		"# Performance logs (F4): %d s averages. North = -Z, East = +X." % int(PERF_SECONDS), details)
	if entry != "":
		show_notice("Logged %s: %d FPS" % [entry, roundi(1000.0 / avg)])

# Appends "- **<prefix>_N** — time — details" to a log and returns the entry name.
func _append_entry(relative_path: String, prefix: String, header: String, details: String) -> String:
	# res:// is only writable when running from the editor.
	var path: String = ("res://" if OS.has_feature("editor") else "user://") + relative_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var existing := ""
	if FileAccess.file_exists(path):
		existing = FileAccess.get_file_as_string(path)
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
	file.close()
	print("%s: %s" % [entry, details])
	return entry

func show_notice(text: String) -> void:
	_notice = text
	_notice_time_left = NOTICE_SECONDS

func _highest_number(text: String, prefix: String) -> int:
	var regex := RegEx.create_from_string(prefix + "_(\\d+)")
	var highest := 0
	for found in regex.search_all(text):
		highest = maxi(highest, found.get_string(1).to_int())
	return highest
