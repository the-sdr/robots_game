extends CanvasLayer

# Tool cards and the Tools & controls page: the player's side of the controls
# (owner, 2026-09-29: "the robot would know; this separate popup is for the
# player"). Non-diegetic on purpose. A card shows what a tool is for, which
# button does it (for the device in hand, via Glyphs), and a small looping
# diagram of how to use it (tap, hold-and-release, rapid presses, trace).
#
# Cards queue up (queue_card) and show once each, when nothing else is on
# screen; seen cards are remembered in the save (flag "card:<id>"). The pause
# menu's Tools & controls page lists the basics and every card seen so far.
# The HUD owns this node.

const CARDS := {
	"basics": {"title": "Getting around", "text": "The robot knows how to do all this. This card is for you.",
		"rows": [["move", "Drive"], ["look", "Look around"], ["jump", "Jump"], ["interact", "Use, dock, dig"],
			["detector", "Detector on / off"], ["inventory", "Parts and building"], ["use_tool", "Use the tool"],
			["cycle_tool", "Next tool"], ["pause", "Pause"]], "pattern": ""},
	"detector": {"title": "Detector", "text": "Every few seconds it sweeps. Warm spots show where something is: far away they are big and drift about, closer in they tighten into a ring. Dig on the ring.",
		"rows": [["detector", "On / off"], ["interact", "Dig on the ring"]], "pattern": "sweep"},
	"smasher": {"title": "Smasher", "text": "Bash! Quick presses hit harder and harder. Keep the rhythm going.",
		"easy": "On Easy you can just hold it down.",
		"rows": [["use_tool", "Press quickly"], ["cycle_tool", "Change tool"]], "pattern": "rapid"},
	"cutter": {"title": "Cutter", "text": "Hold to cut and watch the heat. Let go in the green for a clean cut. Hold too long and it overheats.",
		"rows": [["use_tool", "Hold, let go in the green"], ["cycle_tool", "Change tool"]], "pattern": "hold_heat"},
	"laser": {"title": "Laser", "text": "Hold to fire. Sweep the beam along the whole vine or seam to burn it through.",
		"rows": [["use_tool", "Hold to fire"], ["look", "Sweep along the line"]], "pattern": "trace"},
	"hover": {"title": "Hover pack", "text": "Jump, then keep holding jump to hover up to high ledges. It drinks energy while it flies.",
		"rows": [["jump", "Jump, then hold"]], "pattern": "hold"},
	"fabricator": {"title": "Fabricator", "text": "Stand by a ghost outline and use the tool to print it. Parts are printed from scrap on the build screen.",
		"rows": [["use_tool", "Print"], ["inventory", "Print parts"]], "pattern": "press"},
}

const CYAN := Color(0.45, 0.95, 1.0)

## Headless tests set this: queued cards never pop up (they would pause the game mid-test).
static var suppressed := false

var _queue: Array[String] = []
var _showing := ""
var _was_paused := false
var _old_mouse := Input.MOUSE_MODE_CAPTURED
var _from_page := false
var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _text: Label
var _diagram: PatternDiagram
var _rows: VBoxContainer
var _ok_row: HBoxContainer
var _ok_button: Button
var _page: PanelContainer
var _page_list: VBoxContainer

func _ready() -> void:
	layer = 20                                        # above the HUD and menus
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Glyphs.device_changed.connect(func(_pad: bool) -> void: _refresh_glyphs())

## Shows a card once (it waits until nothing else is on screen).
func queue_card(id: String) -> void:
	if not CARDS.has(id) or Game.get_flag("card:" + id) or _queue.has(id) or _showing == id:
		return
	_queue.append(id)

func card_open() -> bool:
	return _showing != ""

func page_open() -> bool:
	return _page.visible

func _process(_delta: float) -> void:
	if _showing == "" and not _queue.is_empty() and not suppressed and not get_tree().paused and not _page.visible:
		show_card(_queue.pop_front())

func show_card(id: String, from_page: bool = false) -> void:
	_showing = id
	_from_page = from_page
	var card: Dictionary = CARDS[id]
	_title.text = card["title"]
	var text: String = card["text"]
	if card.has("easy") and Settings.difficulty == "easy":
		text += "\n" + String(card["easy"])
	_text.text = text
	_diagram.pattern = card["pattern"]
	_diagram.visible = card["pattern"] != ""
	_fill_rows(_rows, card["rows"])
	if not from_page:
		_was_paused = get_tree().paused
		_old_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_page.visible = false
	_dim.visible = true
	_card.visible = true
	_refresh_ok()
	_ok_button.grab_focus()

func close_card() -> void:
	if _showing == "":
		return
	Game.set_flag("card:" + _showing, true)
	_showing = ""
	_card.visible = false
	if _from_page:
		show_page(true)
		return
	_dim.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _old_mouse

## The Tools & controls page (from the pause menu): the basics, then every card seen.
func show_page(returning: bool = false) -> void:
	if not returning:
		_old_mouse = Input.mouse_mode
	for child in _page_list.get_children():
		child.queue_free()
	var basics: Array = CARDS["basics"]["rows"]
	var rows := VBoxContainer.new()
	_fill_rows(rows, basics)
	_page_list.add_child(rows)
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	for id in CARDS:
		if id == "basics":
			continue
		if not (Game.get_flag("card:" + id) or Game.has_tool(id)):
			continue
		var button := Button.new()
		button.text = CARDS[id]["title"]
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(show_card.bind(id, true))
		cards.add_child(button)
	if cards.get_child_count() > 0:
		var heading := _label("Tools (pick one to see its card)", 20, CYAN)
		_page_list.add_child(heading)
		_page_list.add_child(cards)
	_dim.visible = true
	_page.visible = true
	var first: Control = cards.get_child(0) if cards.get_child_count() > 0 else _page.find_child("PageClose", true, false)
	first.grab_focus.call_deferred()

func close_page() -> void:
	_page.visible = false
	_dim.visible = false
	Input.mouse_mode = _old_mouse
	get_tree().call_group("pause_menu", "focus_first")

# _input, before the GUI and the pause menu: the card answers its own keys.
func _input(event: InputEvent) -> void:
	if _showing != "" and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_card()
		get_viewport().set_input_as_handled()
	elif _page.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_page()
		get_viewport().set_input_as_handled()

# --- building the screens -----------------------------------------------------------------
func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_card = _panel()
	var box := _content(_card)
	_title = _label("", 32, CYAN)
	box.add_child(_title)
	_text = _label("", 20, Color(0.92, 0.95, 0.97))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 0)
	box.add_child(_text)
	_diagram = PatternDiagram.new()
	_diagram.custom_minimum_size = Vector2(560, 110)
	box.add_child(_diagram)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)
	_ok_row = HBoxContainer.new()
	_ok_row.alignment = BoxContainer.ALIGNMENT_END
	_ok_row.add_theme_constant_override("separation", 10)
	box.add_child(_ok_row)
	_ok_button = Button.new()
	_ok_button.text = "Got it"
	_ok_button.add_theme_font_size_override("font_size", 22)
	_ok_button.pressed.connect(close_card)
	_card.visible = false
	add_child(_card)

	_page = _panel()
	var page_box := _content(_page)
	page_box.add_child(_label("Tools & controls", 32, CYAN))
	page_box.add_child(_label("The robot knows how to do all this. This page is for you.", 18, Color(0.85, 0.9, 0.92)))
	_page_list = VBoxContainer.new()
	_page_list.add_theme_constant_override("separation", 12)
	page_box.add_child(_page_list)
	var close := Button.new()
	close.name = "PageClose"
	close.text = "Back"
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(close_page)
	page_box.add_child(close)
	_page.visible = false
	add_child(_page)

## The VBox inside a _panel().
func _content(holder: Control) -> VBoxContainer:
	return holder.get_child(0).get_child(0).get_child(0) as VBoxContainer

## A full-screen holder > CenterContainer > the card (PanelContainer) > VBox.
func _panel() -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.11, 0.96)
	style.set_corner_radius_all(16)
	style.border_color = Color(CYAN, 0.6)
	style.set_border_width_all(2)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	inner.add_child(box)
	centre.add_child(inner)
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(centre)
	return holder

func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label

func _fill_rows(container: VBoxContainer, rows: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var badge := Glyphs.badge(String(row[0]))
		badge.custom_minimum_size = Vector2(150, 0)
		line.add_child(badge)
		line.add_child(_label(String(row[1]), 20, Color(0.92, 0.95, 0.97)))
		container.add_child(line)

func _refresh_ok() -> void:
	for child in _ok_row.get_children():
		_ok_row.remove_child(child)
		if child != _ok_button:
			child.queue_free()
	_ok_row.add_child(Glyphs.badge("ui_accept"))
	_ok_row.add_child(_ok_button)

func _refresh_glyphs() -> void:
	if _showing != "":
		_fill_rows(_rows, CARDS[_showing]["rows"])
		_refresh_ok()
	elif _page.visible:
		show_page(true)

## A small looping picture of how a tool is used.
class PatternDiagram extends Control:
	var pattern := ""
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if visible:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var mid := Vector2(w * 0.5, h * 0.5)
		var cyan := Color(0.45, 0.95, 1.0)
		var dim := Color(0.2, 0.3, 0.35)
		var font := ThemeDB.fallback_font
		match pattern:
			"rapid":
				var t := fmod(_t, 1.6)
				for i in 3:
					var lit := t >= i * 0.22 and t < i * 0.22 + 0.14
					draw_circle(Vector2(mid.x - 120 + i * 60, mid.y), 18.0, cyan if lit else dim)
				var combo := mini(int(t / 0.22) + 1, 3) if t < 0.8 else 3
				draw_string(font, Vector2(mid.x + 80, mid.y + 12), "x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 0.75, 0.3))
			"hold_heat":
				var cycle := fmod(_t, 2.8)
				var fill := clampf(cycle / 1.9, 0.0, 0.8) if cycle < 2.2 else lerpf(0.8, 0.0, (cycle - 2.2) / 0.6)
				var bar := Rect2(mid.x - 220, mid.y - 14, 440, 28)
				draw_rect(bar, dim)
				draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.6, 0), Vector2(bar.size.x * 0.28, bar.size.y)), Color(0.2, 0.6, 0.25))
				draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.88, 0), Vector2(bar.size.x * 0.12, bar.size.y)), Color(0.75, 0.2, 0.15))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color(1.0, 0.7, 0.3, 0.85))
				draw_rect(bar, cyan, false, 2.0)
				var said := "hold..." if cycle < 1.5 else ("let go!" if cycle < 2.2 else "clean cut!")
				draw_string(font, Vector2(mid.x - 60, bar.position.y + 60), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, cyan)
			"trace":
				var along := fmod(_t, 2.6) / 2.2
				var points: PackedVector2Array = []
				for i in 41:
					var x := float(i) / 40.0
					points.append(Vector2(mid.x - 220 + x * 440, mid.y + sin(x * 9.0) * 14.0))
				draw_polyline(points, Color(0.3, 0.6, 0.25), 6.0)
				var burnt := clampi(int(along * 40.0), 0, 40)
				if burnt > 1:
					draw_polyline(points.slice(0, burnt + 1), Color(0.35, 0.2, 0.1), 6.0)
				var tip := points[mini(burnt, 40)]
				draw_line(Vector2(mid.x, h), tip, Color(1.0, 0.3, 0.25), 3.0)
				draw_circle(tip, 7.0, Color(1.0, 0.8, 0.4))
			"sweep":
				var r := fmod(_t, 2.0) / 1.0 * 200.0
				draw_arc(Vector2(mid.x - 200, mid.y + 30), r, -1.2, 0.3, 32, Color(cyan, maxf(0.0, 1.0 - r / 220.0)), 3.0)
				var tight := fmod(_t / 2.0, 3.0)
				var blob: float = 40.0 - floorf(tight) * 14.0
				draw_circle(Vector2(mid.x + 120, mid.y), blob, Color(1.0, 0.45, 0.1, 0.35))
				draw_arc(Vector2(mid.x + 120, mid.y), blob, 0, TAU, 32, Color(1.0, 0.8, 0.3), 2.0)
			"hold":
				var up := absf(sin(_t * 1.5)) * 30.0
				draw_rect(Rect2(mid.x - 20, mid.y + 10 - up, 40, 24), cyan)
				draw_line(Vector2(mid.x, mid.y + 40), Vector2(mid.x, mid.y + 40 - up), Color(1, 1, 1, 0.4), 2.0)
			"press":
				var pulse := 1.0 - fmod(_t, 1.0)
				draw_circle(mid, 16.0 + pulse * 10.0, Color(cyan, 0.3 + pulse * 0.5))
