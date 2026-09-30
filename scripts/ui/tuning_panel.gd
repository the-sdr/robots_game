extends CanvasLayer

# F10 (tools) and F9 (detector): sliders for the feel numbers in
# scripts/game/tuning.gd, changed live while playing (the game keeps going).
# Closing the panel logs every value on it to playtest/tuning.md as tune_N
# (through the coord overlay's log), so Claude can bake the good ones in.
# A testing tool: keyboard keys, debug builds.

const T := preload("res://scripts/game/tuning.gd")
const STYLE := preload("res://scripts/ui/ui_style.gd")
const TITLES := {"tools": "Tool tuning  (F10)", "detector": "Detector tuning  (F9)"}

## Where the log goes (the coord overlay: log_tuning(panel, details)).
var logger: Node
var panel_name := ""
var _box: VBoxContainer
var _rows: VBoxContainer
var _title: Label
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _sliders := {}

func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", STYLE.panel_style(0.6))
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -520
	holder.offset_right = -16
	holder.offset_top = 16
	holder.offset_bottom = -16
	add_child(holder)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	_title = STYLE.label("", 26, STYLE.CYAN)
	_title.add_theme_font_override("font", STYLE.title_font())
	_box.add_child(_title)
	var hint := STYLE.label("Changes work straight away. Close this panel to log the values (playtest/tuning.md); F3 notes changed ones too. * = changed.", 15, STYLE.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(hint)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_box.add_child(_rows)
	var reset := Button.new()
	reset.text = "Reset these to the game's values"
	reset.pressed.connect(func() -> void:
		for row in T.PANELS[panel_name]:
			T.values.erase(T._key(String(row[0])))
		_fill())
	_box.add_child(reset)

func is_open() -> bool:
	return visible

## Opens a panel ("tools" / "detector"); the same key closes it; the other key switches.
func toggle(which: String) -> void:
	if visible and panel_name == which:
		close()
		return
	if visible:
		_log()
	else:
		_old_mouse = Input.mouse_mode
	panel_name = which
	_title.text = TITLES[which] + ("   (Easy values)" if Settings.difficulty == "easy" else "")
	_fill()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not visible:
		return
	_log()
	visible = false
	Input.mouse_mode = _old_mouse

func _log() -> void:
	if logger != null and logger.has_method("log_tuning"):
		logger.call("log_tuning", panel_name, "%s (%s): %s" % [panel_name, Settings.difficulty, T.summary(panel_name)])

func _fill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_sliders.clear()
	for row in T.PANELS[panel_name]:
		var key: String = row[0]
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		var top := HBoxContainer.new()
		var name_label := STYLE.label(String(row[1]), 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var value_label := STYLE.label("", 16, STYLE.WARM)
		top.add_child(value_label)
		line.add_child(top)
		var slider := HSlider.new()
		slider.min_value = float(row[2])
		slider.max_value = float(row[3])
		slider.step = float(row[4])
		slider.value = T.v(key)
		slider.custom_minimum_size = Vector2(440, 20)
		var show := func(value: float) -> void:
			value_label.text = "%s%s" % [snappedf(value, float(row[4])), "  *" if T.is_tuned(key) else ""]
		slider.value_changed.connect(func(value: float) -> void:
			T.set_value(key, value)
			show.call(value))
		show.call(T.v(key))
		line.add_child(slider)
		_rows.add_child(line)
		_sliders[key] = slider

## Sets a slider as if dragged (tests).
func set_slider(key: String, value: float) -> void:
	(_sliders[key] as HSlider).value = value
