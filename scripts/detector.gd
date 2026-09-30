extends Node

# The robot's detector: "robot vision" (owner, 2026-09-29). One press of the
# detector button (right mouse button or R, pad LB; owner 2026-09-30: "on button
# press", not a toggle or a timer) sends one sweep out from the robot: for about
# a second the ground turns into the robot's
# view (a grid with height contours, drawn by the terrain shader) and warm spots
# flare where the front passes something to recover - anything in the group
# "detectable" with a detect_position() (buried finds, parts, crates...).
#
# Far away a spot is big and soft and lands somewhere a little different each
# sweep, so it only gives a direction; closer in it tightens; within EXACT_WITHIN
# it is a crisp ring on the exact spot. Purely visual, so it works without sound.
# Far spots also glow as a warm haze above the trees (the forest would hide the
# ground). Each scan costs a little energy; the spots and the signal bars stay
# a few seconds so the player can walk towards them, then scan again.

const SCAN_COOLDOWN := 0.8       # seconds before the next scan can go out
const SCAN_ENERGY := 0.5
const SIGNAL_SHOW := 5.0         # seconds the signal bars stay after a scan
const SWEEP_TIME := 1.2          # the front's trip out to RANGE (it starts slow, so the ring
                                 # is seen rolling out from the robot even when a find is close)
const OVERLAY_IN := 0.15         # seconds for the robot view to come up
const OVERLAY_OUT := 0.5         # and to fade after the sweep
const RANGE := 60.0
const MAX_SPOTS := 12            # must match the terrain shader's arrays
const SPOT_GLOW := 4.0           # seconds a spot keeps glowing after the front reaches it
const EXACT_WITHIN := 2.5        # metres: closer than this, the fix is exact
const FUZZ_PER_METRE := 0.3      # how far off a far fix can land, per metre of distance
const MAX_FUZZ := 12.0
const HAZE_BEYOND := 12.0        # metres: farther than this a spot also glows above the trees
const TERRAIN_MATERIAL := "res://materials/terrain_painterly.tres"
const SCREEN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float vignette = smoothstep(0.35, 0.9, distance(UV, vec2(0.5)));
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 1.7);
	COLOR = vec4(0.25, 0.85, 0.95, (vignette * 0.35 + scan * 0.05) * amount);
}
"""

@onready var player: Node3D = get_parent()

## Sweeps sent since the game started (tests).
var sweeps := 0
## The spots from the last sweep: {pos: Vector3, radius, strength, heat, lit, reveal_at, distance}.
var spots: Array[Dictionary] = []
var _time := 100.0               # since the last sweep started
var _overlay := 0.0
var _origin := Vector3.ZERO
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _screen_rect: ColorRect
var _signal_box: HBoxContainer
var _signal_bars: Array[ColorRect] = []
var _signal_note: Label
## 0-5 bars from the nearest find at the last sweep (the visual "beep").
var signal_bars := 0
var _hazes: Array[MeshInstance3D] = []
var _idle_pushed := false

func _ready() -> void:
	_rng.randomize()
	if ResourceLoader.exists(TERRAIN_MATERIAL):
		_material = load(TERRAIN_MATERIAL) as ShaderMaterial
	_build_screen()
	_build_hazes()
	_push()

## The detector button: one sweep (false while the last one is still going out).
func scan() -> bool:
	if _time < SCAN_COOLDOWN:
		return false
	if not player.get("god_mode"):
		Energy.drain(SCAN_ENERGY)
	get_tree().call_group("hud", "queue_card", "detector")
	_sweep()
	return true

## True while a sweep's front is rolling out.
func sweeping() -> bool:
	return _time < SWEEP_TIME

## The sweep front's distance from where it started (-100 = no front): it eases
## out from the robot, so the ring near the robot lasts long enough to see.
func wave_radius() -> float:
	if _time >= SWEEP_TIME:
		return -100.0
	var t := _time / SWEEP_TIME
	return RANGE * t * t

## How far off a fix from this distance may land (0 = exact).
static func fuzz(distance: float) -> float:
	return clampf((distance - EXACT_WITHIN) * FUZZ_PER_METRE, 0.0, MAX_FUZZ)

func _process(delta: float) -> void:
	_time += delta
	var rolling := sweeping()
	_overlay = move_toward(_overlay, 1.0 if rolling else 0.0, delta / (OVERLAY_IN if rolling else OVERLAY_OUT))
	for s in spots:
		if not s["lit"]:
			if _time >= s["reveal_at"]:
				s["lit"] = true
				s["heat"] = s["strength"]
		else:
			s["heat"] = maxf(float(s["heat"]) - delta * float(s["strength"]) / SPOT_GLOW, 0.0)
	var busy := _time < SIGNAL_SHOW or _overlay > 0.0 or _any_glowing()
	if busy or not _idle_pushed:
		_push()
		_update_hazes()
		_update_screen()
		_idle_pushed = not busy

func _any_glowing() -> bool:
	for s in spots:
		if float(s["heat"]) > 0.0 or not s["lit"]:
			return true
	return false

## Sends a sweep: every detectable thing in range gets a spot, fuzzier the farther it is.
func _sweep() -> void:
	_time = 0.0
	sweeps += 1
	_origin = player.global_position
	spots.clear()
	var found: Array = []
	for node in get_tree().get_nodes_in_group("detectable"):
		if not node.has_method("detect_position"):
			continue
		var p: Vector3 = node.call("detect_position")
		var d := Vector2(p.x - _origin.x, p.z - _origin.z).length()
		if d <= RANGE:
			found.append([d, p])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for f in found.slice(0, MAX_SPOTS):
		var d: float = f[0]
		var p: Vector3 = f[1]
		var off := fuzz(d)
		var shift := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * off
		spots.append({"pos": p + Vector3(shift.x, 0.0, shift.y), "radius": maxf(0.5, off * 1.3),
			"strength": lerpf(1.0, 0.4, d / RANGE), "heat": 0.0, "lit": false,
			"reveal_at": sqrt(d / RANGE) * SWEEP_TIME, "distance": d})
	var nearest: float = spots[0]["distance"] if not spots.is_empty() else INF
	signal_bars = 0 if spots.is_empty() else clampi(5 - int(nearest / 12.0), 1, 5)
	for i in _signal_bars.size():
		_signal_bars[i].color = Color(0.45, 0.95, 1.0) if i < signal_bars else Color(0.1, 0.18, 0.2, 0.8)
	_signal_note.text = "no signal" if spots.is_empty() else ("right here!" if nearest < EXACT_WITHIN else "")

func _push() -> void:
	if _material == null:
		return
	var centres := PackedVector4Array()
	var heat := PackedFloat32Array()
	var any := false
	for i in MAX_SPOTS:
		if i < spots.size() and float(spots[i]["heat"]) > 0.0:
			var p: Vector3 = spots[i]["pos"]
			centres.append(Vector4(p.x, p.y, p.z, spots[i]["radius"]))
			heat.append(spots[i]["heat"])
			any = true
		else:
			centres.append(Vector4.ZERO)
			heat.append(0.0)
	_material.set_shader_parameter("scan_amount", _overlay)
	_material.set_shader_parameter("scan_spots_on", 1.0 if any else 0.0)
	_material.set_shader_parameter("scan_origin", _origin)
	_material.set_shader_parameter("scan_wave", wave_radius())
	_material.set_shader_parameter("scan_range", RANGE)
	_material.set_shader_parameter("scan_spots", centres)
	_material.set_shader_parameter("scan_spot_heat", heat)

func _exit_tree() -> void:
	# the material is shared and outlives the robot: leave the normal look behind
	_time = 100.0
	_overlay = 0.0
	spots.clear()
	_push()

# --- on screen ---------------------------------------------------------------------------
func _build_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DetectorScreen"
	add_child(layer)
	_screen_rect = ColorRect.new()
	_screen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SCREEN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_screen_rect.material = mat
	_screen_rect.visible = false
	layer.add_child(_screen_rect)
	# "DETECTOR" and five signal bars, bottom centre
	_signal_box = HBoxContainer.new()
	_signal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_signal_box.add_theme_constant_override("separation", 6)
	_signal_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 110)
	_signal_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_signal_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_signal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signal_box.visible = false
	layer.add_child(_signal_box)
	var title := _hud_label("DETECTOR")
	_signal_box.add_child(title)
	for i in 5:
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(10, 8 + i * 5)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		bar.color = Color(0.1, 0.18, 0.2, 0.8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_signal_box.add_child(bar)
		_signal_bars.append(bar)
	_signal_note = _hud_label("")
	_signal_box.add_child(_signal_note)

func _hud_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	return label

func _update_screen() -> void:
	_screen_rect.visible = _overlay > 0.0
	(_screen_rect.material as ShaderMaterial).set_shader_parameter("amount", _overlay)
	_signal_box.visible = _time < SIGNAL_SHOW

# --- the warm haze above far spots -------------------------------------------------------
func _build_hazes() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in MAX_SPOTS:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = true                # seen through the trees
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.albedo_texture = texture
		var haze := MeshInstance3D.new()
		haze.name = "Haze%d" % i
		haze.mesh = quad
		haze.material_override = mat
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		haze.top_level = true
		haze.visible = false
		add_child(haze)
		_hazes.append(haze)

func _update_hazes() -> void:
	for i in _hazes.size():
		var haze := _hazes[i]
		var show := i < spots.size() and float(spots[i]["heat"]) > 0.0 and float(spots[i]["distance"]) > HAZE_BEYOND
		haze.visible = show
		if show:
			var s: Dictionary = spots[i]
			var r: float = s["radius"]
			haze.global_position = (s["pos"] as Vector3) + Vector3(0, 3.0 + r * 0.3, 0)
			haze.scale = Vector3.ONE * r * 2.2
			(haze.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.55, 0.15, 0.55 * float(s["heat"]))
