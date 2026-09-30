extends RefCounted

# The game's look for menus and panels (owner, 2026-09-30: "make it look cool").
# Built in code, no asset files: the font is Windows' own Bahnschrift (a DIN
# style that suits a robot; both of the owner's machines have it) through a
# SystemFont, falling back to Godot's default elsewhere. Dark glass panels with
# a cyan edge; a focused button glows, so pad players always see where they are.
# Glyphs (autoload) sets this as the whole window's theme at start-up.

const CYAN := Color(0.45, 0.95, 1.0)
const INK := Color(0.9, 0.95, 0.97)
const DIM := Color(0.6, 0.68, 0.72)
const WARM := Color(1.0, 0.72, 0.3)
const GLASS := Color(0.035, 0.07, 0.09, 0.9)

static var _theme: Theme
static var _title_font: SystemFont

static func font(weight: int = 400, stretch: int = 100) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Noto Sans", "sans-serif"])
	f.font_weight = weight
	f.font_stretch = stretch
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f

## The big condensed font for titles.
static func title_font() -> SystemFont:
	if _title_font == null:
		_title_font = font(700, 75)
	return _title_font

static func panel_style(edge: float = 0.55) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.set_corner_radius_all(14)
	s.border_color = Color(CYAN, edge)
	s.set_border_width_all(2)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 12
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s

static func _button_box(bg: Color, edge: Color, glow: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.border_color = edge
	s.set_border_width_all(2)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if glow > 0.0:
		s.shadow_color = Color(CYAN, glow)
		s.shadow_size = 10
	return s

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _button_box(Color(0.05, 0.1, 0.13, 0.85), Color(CYAN, 0.3), 0.0))
	t.set_stylebox("hover", "Button", _button_box(Color(0.07, 0.16, 0.2, 0.92), Color(CYAN, 0.8), 0.0))
	t.set_stylebox("pressed", "Button", _button_box(Color(0.12, 0.3, 0.34, 0.95), CYAN, 0.0))
	t.set_stylebox("focus", "Button", _button_box(Color(0, 0, 0, 0), CYAN, 0.35))
	t.set_stylebox("disabled", "Button", _button_box(Color(0.04, 0.06, 0.07, 0.6), Color(1, 1, 1, 0.08), 0.0))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", CYAN)
	t.set_color("font_focus_color", "Button", CYAN)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("normal", "LineEdit", _button_box(Color(0.02, 0.04, 0.05, 0.95), Color(CYAN, 0.5), 0.0))
	t.set_stylebox("focus", "LineEdit", _button_box(Color(0, 0, 0, 0), CYAN, 0.25))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(CYAN, 0.5)
	grabber.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.05)
	track.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", track)
	_theme = t
	return t

## A label in the house style.
static func label(text: String, size: int = 20, colour: Color = INK, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.add_theme_font_override("font", font(600))
	return l

## A small key/button badge with the given text (for showing both devices at once).
static func badge(text: String, colour: Color = Color(0.28, 0.3, 0.33), size: int = 18) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(7)
	s.border_color = Color(1, 1, 1, 0.3)
	s.set_border_width_all(2)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", s)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label(text, size, Color.WHITE, true))
	return box
