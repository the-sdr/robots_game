extends RefCounted

# Paint for the robot model (scenes/player.tscn's Visual, and copies of it such
# as the old zombie robot). The model is built from four shared materials -
# metal, dark, blue, yellow - plus the glowing lenses; a palette swaps those
# four by role, as material_override on each part. Overrides already set (the
# chest panel, lenses and iris the player lights up itself) are left alone.
#   silly:   bright toy plastic (owner, 2026-10-02: the kids' game)
#   serious: worn, grimy metal (the adults' game)
#   rust:    the old zombie robot, long dead in the crooked house
# Usage: preload("res://scripts/robot_paint.gd").apply(visual, "serious")

## role -> [albedo, metallic, roughness, grime (0 = clean .. 1 = mottled)]
const PALETTES := {
	"silly": {
		"metal": [Color(1.0, 0.76, 0.12), 0.0, 0.32, 0.0],
		"dark": [Color(0.13, 0.3, 0.85), 0.0, 0.4, 0.0],
		"blue": [Color(0.92, 0.2, 0.16), 0.0, 0.3, 0.0],
		"yellow": [Color(0.3, 0.85, 0.35), 0.0, 0.3, 0.0],
	},
	"serious": {
		"metal": [Color(0.5, 0.5, 0.47), 0.75, 0.68, 0.45],
		"dark": [Color(0.12, 0.12, 0.12), 0.4, 0.85, 0.3],
		"blue": [Color(0.17, 0.21, 0.32), 0.45, 0.7, 0.4],
		"yellow": [Color(0.62, 0.46, 0.16), 0.35, 0.75, 0.5],
	},
	"rust": {
		"metal": [Color(0.47, 0.25, 0.12), 0.35, 0.92, 0.9],
		"dark": [Color(0.19, 0.12, 0.08), 0.3, 0.95, 0.7],
		"blue": [Color(0.26, 0.23, 0.21), 0.3, 0.9, 0.8],
		"yellow": [Color(0.42, 0.31, 0.12), 0.3, 0.92, 0.9],
	},
}
## A part of each role in the model: its mesh's material names the role.
const ROLE_PARTS := {"metal": "Torso", "dark": "Neck", "blue": "TorsoBand", "yellow": "Collar"}

static var _grime: NoiseTexture2D
static var _cache := {}       # "palette/role" -> StandardMaterial3D, shared by every robot

## Paints `visual` (the model's root node) with a palette. Returns how many parts changed.
static func apply(visual: Node3D, palette: String) -> int:
	if not PALETTES.has(palette):
		return 0
	var roles := {}            # the model's own material -> role
	for role in ROLE_PARTS:
		var part := visual.get_node_or_null(String(ROLE_PARTS[role])) as MeshInstance3D
		if part != null and part.mesh != null and part.mesh.surface_get_material(0) != null:
			roles[part.mesh.surface_get_material(0)] = role
	var painted := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or (mi.material_override != null and not _is_paint(mi.material_override)):
			continue
		var role: String = roles.get(mi.mesh.surface_get_material(0), "")
		if role != "":
			mi.material_override = material(palette, role)
			painted += 1
	return painted

## The shared material for a palette's role.
static func material(palette: String, role: String) -> StandardMaterial3D:
	var key := palette + "/" + role
	if _cache.has(key):
		return _cache[key]
	var spec: Array = PALETTES[palette][role]
	var m := StandardMaterial3D.new()
	m.resource_name = "paint:" + key
	m.albedo_color = spec[0]
	m.metallic = spec[1]
	m.roughness = spec[2]
	var grime: float = spec[3]
	if grime > 0.0:
		# mottled wear: one small noise texture for every robot, mapped in world
		# space (triplanar) so the primitive parts need no UVs
		m.albedo_texture = _grime_texture()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 1.6
		m.albedo_color = spec[0] * Color(1, 1, 1).lerp(Color(1.25, 1.2, 1.15), grime)
	_cache[key] = m
	return m

static func _is_paint(m: Material) -> bool:
	return m.resource_name.begins_with("paint:")

static func _grime_texture() -> NoiseTexture2D:
	if _grime == null:
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.03
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.5, 0.45))
		ramp.set_color(1, Color(0.95, 0.93, 0.9))
		_grime = NoiseTexture2D.new()
		_grime.width = 128
		_grime.height = 128
		_grime.seamless = true
		_grime.noise = noise
		_grime.color_ramp = ramp
	return _grime
