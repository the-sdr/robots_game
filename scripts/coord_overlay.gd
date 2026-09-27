extends CanvasLayer

# Debug overlay toggled with F2 (action "toggle_coords"). Shows the player's
# position in Godot world units (1 unit = 1 m) and headings on a compass
# mapped onto the world axes: North = -Z, East = +X, South = +Z, West = -X.
# Headings are degrees clockwise from North, as on a real compass.
#
# F3 (action "save_position") appends the current position to SAVE_FILE as
# save_1, save_2, ... so a playtest spot can be referred to by name in chat.
# Numbering continues from the highest save already in the file.
#
# While the player's god mode (F7) is on, a status line is shown as well.

const DIRECTIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SAVE_FILE := "res://playtest/saves.md"
const SAVE_FILE_EXPORTED := "user://saves.md"
const NOTICE_SECONDS := 4.0

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label

var _player: Node3D
var _player_visual: Node3D
var _pinned_visible := false
var _notice := ""
var _notice_time_left := 0.0
var _last_god_mode := false

func _ready() -> void:
	panel.visible = false
	add_to_group("hud")   # anything can call_group("hud", "show_notice", text)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_coords"):
		_pinned_visible = not _pinned_visible
	if event.is_action_pressed("save_position"):
		_save_position()

func _process(delta: float) -> void:
	_notice_time_left = maxf(_notice_time_left - delta, 0.0)
	var god_mode: bool = _find_player() and _player.get("god_mode") == true
	if god_mode != _last_god_mode:
		_last_god_mode = god_mode
		show_notice("God mode %s" % ("ON" if god_mode else "OFF"))
	panel.visible = _pinned_visible or _notice_time_left > 0.0
	if not panel.visible or _player == null:
		return

	var lines: Array[String] = []
	if _notice_time_left > 0.0:
		lines.append(_notice)
	if god_mode:
		lines.append("GOD  %s" % ("flying" if _player.get("flying") else "2x Space = fly"))
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
	# res:// is only writable when running from the editor.
	var path: String = SAVE_FILE if OS.has_feature("editor") else SAVE_FILE_EXPORTED
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	var existing := ""
	if FileAccess.file_exists(path):
		existing = FileAccess.get_file_as_string(path)
	var save_name := "save_%d" % (_highest_save_number(existing) + 1)

	var file := FileAccess.open(path, FileAccess.READ_WRITE if existing != "" else FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	if existing == "":
		file.store_line("# Playtest saves (F3). North = -Z, East = +X. Headings clockwise from North.")
		file.store_line("")
	file.seek_end()
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	var details: String = "  ".join(_describe_position())
	file.store_line("- **%s** — %s — %s" % [save_name, timestamp, details])
	file.close()

	show_notice("Saved %s" % save_name)
	print("Saved %s: %s" % [save_name, details])

func show_notice(text: String) -> void:
	_notice = text
	_notice_time_left = NOTICE_SECONDS

func _highest_save_number(text: String) -> int:
	var regex := RegEx.create_from_string("save_(\\d+)")
	var highest := 0
	for found in regex.search_all(text):
		highest = maxi(highest, found.get_string(1).to_int())
	return highest
