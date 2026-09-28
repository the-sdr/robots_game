extends SceneTree

# Builds a small model for every Catalog item, replacing the one tinted gear
# every pickup used to be: Godot primitives (and real toothed gears) placed and
# merged into one ArrayMesh per item, a few surfaces each (metal, plastic,
# glass...) plus a glowing accent in the item's Catalog colour so parts still
# read at night. Plain ArrayMesh (never MultiMesh: headless drops its data).
# From the project root:
#   <godot> --headless --path . -s tools/item_models_bake.gd
# Writes scenes/props/items/<item_id>.res (generated: never hand-edit).
# collectible_part.gd shows the model when one exists for its item.
# Models are ~0.4-0.5 m across (game-readable, not real-life size), centred on
# the origin (the pickup spins them about Y).

const OUT_DIR := "res://scenes/props/items/"

var _acc := {}          # Material -> [vertices, normals, uvs, indices]
var _mats := {}         # shared materials by name
var _model := Transform3D()     # whole-model tilt, applied to every piece

func _initialize() -> void:
	var catalog: Node = root.get_node("Catalog")      # -s scripts compile before autoload names exist
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := 0
	for id in catalog.ITEMS:
		_acc = {}
		_model = Transform3D()
		var colour: Color = catalog.ITEMS[id]["colour"]
		if not _build(String(id), colour):
			print("  no model recipe for ", id)
			failed += 1
			continue
		var mesh := ArrayMesh.new()
		var tris := 0
		for mat in _acc:
			var a: Array = _acc[mat]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = a[0]
			arrays[Mesh.ARRAY_NORMAL] = a[1]
			arrays[Mesh.ARRAY_TEX_UV] = a[2]
			arrays[Mesh.ARRAY_INDEX] = a[3]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			tris += a[3].size() / 3
		var path := OUT_DIR + "%s.res" % id
		var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		var size := mesh.get_aabb().size
		print("  %-14s %d surfaces, %4d triangles, %.2f x %.2f x %.2f m -> %s" % [id, mesh.get_surface_count(), tris, size.x, size.y, size.z, error_string(err)])
		if err != OK:
			failed += 1
	print("item models: %d items, %d failed" % [catalog.ITEMS.size(), failed])
	quit(0 if failed == 0 else 1)

# --- materials -------------------------------------------------------------------------
func _mat(key: String, colour: Color, metallic: float, roughness: float, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = colour
	m.metallic = metallic
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED        # small models, hand-wound gear faces: never show a hole
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m

func _glow(colour: Color) -> StandardMaterial3D:
	return _mat("glow_%s" % colour.to_html(false), colour, 0.0, 0.4, colour, 2.5)

func _steel() -> StandardMaterial3D: return _mat("steel", Color(0.74, 0.76, 0.79), 0.85, 0.3)
func _dark() -> StandardMaterial3D: return _mat("dark_metal", Color(0.2, 0.21, 0.23), 0.8, 0.42)
func _black() -> StandardMaterial3D: return _mat("black_plastic", Color(0.07, 0.07, 0.08), 0.0, 0.55)
func _brass() -> StandardMaterial3D: return _mat("brass", Color(0.86, 0.66, 0.3), 0.9, 0.3)
func _copper() -> StandardMaterial3D: return _mat("copper", Color(0.86, 0.46, 0.26), 0.9, 0.28)
func _orange() -> StandardMaterial3D: return _mat("orange_plastic", Color(0.95, 0.5, 0.14), 0.0, 0.45)

# --- geometry ----------------------------------------------------------------------------
func _xf(pos: Vector3, rot_deg: Vector3, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var e := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	return _model * Transform3D(Basis.from_euler(e) * Basis.from_scale(scale), pos)

func _add(mat: Material, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, xf: Transform3D) -> void:
	if not _acc.has(mat):
		_acc[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	var a: Array = _acc[mat]
	var base: int = a[0].size()
	var nb: Basis = xf.basis.inverse().transposed()
	for i in verts.size():
		a[0].append(xf * verts[i])
		a[1].append((nb * normals[i]).normalized())
	if uvs.size() == verts.size():
		a[2].append_array(uvs)
	else:
		var blank := PackedVector2Array()
		blank.resize(verts.size())
		a[2].append_array(blank)
	for idx in indices:
		a[3].append(base + idx)

func _prim(mat: Material, mesh: PrimitiveMesh, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> void:
	var arr := mesh.get_mesh_arrays()
	_add(mat, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_TEX_UV], arr[Mesh.ARRAY_INDEX], _xf(pos, rot, scale))

func _box(mat: Material, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	_prim(mat, m, pos, rot)

## A cylinder along its local Y (a cone when the radii differ; 4-6 segments give prisms).
func _cyl(mat: Material, r_top: float, r_bottom: float, height: float, pos: Vector3, rot: Vector3 = Vector3.ZERO, segments: int = 18) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	_prim(mat, m, pos, rot)

func _sphere(mat: Material, radius: float, pos: Vector3, scale: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	_prim(mat, m, pos, rot, scale)

## A ring lying in its local XZ plane (axis Y).
func _ring(mat: Material, inner: float, outer: float, pos: Vector3, rot: Vector3 = Vector3.ZERO, rings: int = 28) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = 8
	_prim(mat, m, pos, rot)

func _tooth(mat: Material, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var m := PrismMesh.new()
	m.size = size
	_prim(mat, m, pos, rot)

## A spur gear lying in its local XZ plane: trapezoid teeth, flat shaded.
func _gear(mat: Material, radius: float, teeth: int, depth: float, thickness: float, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var outline := PackedVector2Array()
	var n := teeth * 4
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var tip := i % 4 == 1 or i % 4 == 2
		outline.append(Vector2(cos(a), sin(a)) * (radius if tip else radius - depth))
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var idx := PackedInt32Array()
	var h := thickness * 0.5
	for side in [1.0, -1.0]:                  # top and bottom: fans from the centre (the outline is star-shaped)
		var centre := v.size()
		v.append(Vector3(0, h * side, 0))
		nr.append(Vector3(0, side, 0))
		for p in outline:
			v.append(Vector3(p.x, h * side, p.y))
			nr.append(Vector3(0, side, 0))
		for i in n:
			var a2 := centre + 1 + i
			var b2 := centre + 1 + (i + 1) % n
			if side > 0.0:
				idx.append_array(PackedInt32Array([centre, b2, a2]))
			else:
				idx.append_array(PackedInt32Array([centre, a2, b2]))
	for i in n:                                # rim quads, each with its own normal
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var edge := (p1 - p0).normalized()
		var normal := Vector3(edge.y, 0, -edge.x)
		var s := v.size()
		v.append_array(PackedVector3Array([Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p1.x, -h, p1.y), Vector3(p0.x, -h, p0.y)]))
		nr.append_array(PackedVector3Array([normal, normal, normal, normal]))
		idx.append_array(PackedInt32Array([s, s + 1, s + 2, s, s + 2, s + 3]))
	_add(mat, v, nr, PackedVector2Array(), idx, _xf(pos, rot))

# --- the models ----------------------------------------------------------------------------
func _build(id: String, colour: Color) -> bool:
	var glow := _glow(colour)
	match id:
		"servo_motor":
			_box(_orange(), Vector3(0.36, 0.22, 0.2), Vector3.ZERO)
			_box(_black(), Vector3(0.5, 0.025, 0.2), Vector3(0, 0.05, 0))
			for x in [-0.22, 0.22]:
				_cyl(_steel(), 0.018, 0.018, 0.03, Vector3(x, 0.07, 0))
			_cyl(_black(), 0.06, 0.06, 0.05, Vector3(0.09, 0.135, 0))
			_box(_steel(), Vector3(0.3, 0.02, 0.05), Vector3(0.09, 0.17, 0), Vector3(0, 20, 0))
			_box(_steel(), Vector3(0.05, 0.02, 0.2), Vector3(0.09, 0.17, 0), Vector3(0, 20, 0))
			_box(_black(), Vector3(0.05, 0.03, 0.2), Vector3(-0.2, -0.07, 0.07), Vector3(0, 30, 0))
			_box(glow, Vector3(0.03, 0.03, 0.01), Vector3(-0.12, 0.03, -0.101))
		"optic_lens":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(90), 0, 0)), Vector3.ZERO)   # stands up, faces forward
			_ring(_dark(), 0.16, 0.22, Vector3.ZERO)
			for i in 16:
				var a := TAU * i / 16.0
				_box(_dark(), Vector3(0.03, 0.07, 0.03), Vector3(cos(a) * 0.225, 0, sin(a) * 0.225), Vector3(0, -rad_to_deg(a), 0))
			_sphere(_mat("lens_glass", Color(0.6, 0.85, 1.0, 0.5), 0.2, 0.04, colour, 0.35), 0.17, Vector3.ZERO, Vector3(1, 0.32, 1))
			_ring(_steel(), 0.15, 0.17, Vector3(0, 0.035, 0))
		"power_cell":
			_cyl(_dark(), 0.12, 0.12, 0.4, Vector3.ZERO)
			_cyl(glow, 0.124, 0.124, 0.1, Vector3(0, -0.02, 0))
			_cyl(_steel(), 0.1, 0.11, 0.03, Vector3(0, 0.215, 0))
			_cyl(_steel(), 0.035, 0.035, 0.05, Vector3(0, 0.25, 0))
			_cyl(_steel(), 0.11, 0.1, 0.02, Vector3(0, -0.21, 0))
		"circuit_board":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(55), 0, 0)), Vector3.ZERO)
			_box(_mat("pcb", Color(0.08, 0.42, 0.2), 0.1, 0.5), Vector3(0.46, 0.02, 0.32), Vector3.ZERO)
			_box(_black(), Vector3(0.12, 0.025, 0.12), Vector3(-0.08, 0.022, 0.02))
			_box(_black(), Vector3(0.07, 0.02, 0.05), Vector3(0.12, 0.02, -0.08))
			_box(_black(), Vector3(0.05, 0.02, 0.09), Vector3(0.13, 0.02, 0.07))
			for x in [-0.01, 0.03, 0.07]:
				_cyl(_steel(), 0.018, 0.018, 0.05, Vector3(x, 0.035, -0.1))
			for z in [-0.06, 0.0, 0.06, 0.1]:
				_box(_brass(), Vector3(0.3, 0.004, 0.008), Vector3(0.05, 0.012, z))
			_box(_mat("char", Color(0.05, 0.04, 0.03), 0.0, 0.95), Vector3(0.11, 0.005, 0.09), Vector3(-0.18, 0.012, -0.12), Vector3(0, 25, 0))
			_box(glow, Vector3(0.025, 0.02, 0.025), Vector3(0.19, 0.02, 0.12))
		"gear_train":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(40), 0, 0)), Vector3.ZERO)
			_box(_dark(), Vector3(0.46, 0.03, 0.3), Vector3.ZERO)
			_gear(_brass(), 0.15, 14, 0.03, 0.04, Vector3(-0.08, 0.04, 0))
			_gear(_brass(), 0.095, 9, 0.03, 0.04, Vector3(0.155, 0.04, 0), Vector3(0, 20, 0))
			_cyl(_steel(), 0.02, 0.02, 0.1, Vector3(-0.08, 0.04, 0))
			_cyl(_steel(), 0.02, 0.02, 0.1, Vector3(0.155, 0.04, 0))
			_box(glow, Vector3(0.02, 0.012, 0.02), Vector3(0.2, 0.02, 0.12))
		"antenna_coil":
			_cyl(_dark(), 0.035, 0.035, 0.44, Vector3.ZERO, Vector3(0, 0, 90))
			for i in 9:
				_ring(_copper(), 0.037, 0.064, Vector3(-0.14 + i * 0.035, 0, 0), Vector3(0, 0, 90), 12)
			for x in [-0.19, 0.19]:
				_cyl(_black(), 0.07, 0.07, 0.03, Vector3(x, 0, 0), Vector3(0, 0, 90))
			_cyl(_steel(), 0.008, 0.012, 0.3, Vector3(0.19, 0.17, 0))
			_sphere(glow, 0.03, Vector3(0.19, 0.33, 0))
		"hammer_head":
			_box(_steel(), Vector3(0.3, 0.14, 0.14), Vector3.ZERO)
			_cyl(_steel(), 0.085, 0.085, 0.08, Vector3(0.18, 0, 0), Vector3(0, 0, 90))
			_cyl(_steel(), 0.02, 0.075, 0.13, Vector3(-0.21, 0, 0), Vector3(0, 45, 90), 4)
			_box(_dark(), Vector3(0.06, 0.02, 0.06), Vector3(0, 0.071, 0))
			_sphere(_dark(), 0.028, Vector3(0.222, 0.03, 0.035))
			_box(glow, Vector3(0.1, 0.02, 0.005), Vector3(-0.02, -0.03, 0.071))
		"actuator_arm":
			var paint := _mat("orange_paint", Color(0.85, 0.45, 0.18), 0.4, 0.5)
			var chrome := _mat("chrome", Color(0.92, 0.94, 0.96), 1.0, 0.12)
			_cyl(paint, 0.07, 0.07, 0.34, Vector3(-0.06, 0, 0), Vector3(0, 0, 90))
			for x in [-0.235, 0.115]:
				_cyl(_dark(), 0.078, 0.078, 0.03, Vector3(x, 0, 0), Vector3(0, 0, 90))
			_cyl(chrome, 0.03, 0.03, 0.2, Vector3(0.21, 0, 0), Vector3(0, 0, 90))
			_box(_dark(), Vector3(0.06, 0.1, 0.08), Vector3(-0.28, 0, 0))
			_box(_dark(), Vector3(0.06, 0.1, 0.08), Vector3(0.32, 0, 0))
			for x in [-0.28, 0.32]:
				_cyl(_steel(), 0.016, 0.016, 0.1, Vector3(x, 0, 0), Vector3(90, 0, 0))
			_ring(_black(), 0.085, 0.105, Vector3(-0.06, 0.06, 0), Vector3(90, 0, 0))
			_box(glow, Vector3(0.08, 0.012, 0.012), Vector3(-0.06, 0.071, -0.04))
		"scrap_metal":
			var rust := _mat("rust", Color(0.5, 0.34, 0.24), 0.5, 0.8)
			_box(rust, Vector3(0.3, 0.02, 0.2), Vector3.ZERO, Vector3(10, 20, 15))
			_box(_steel(), Vector3(0.25, 0.02, 0.15), Vector3(0.05, 0.05, 0.03), Vector3(-25, 60, 5))
			_box(rust, Vector3(0.2, 0.02, 0.2), Vector3(-0.06, -0.05, 0.02), Vector3(30, -40, -10))
			_box(_dark(), Vector3(0.18, 0.02, 0.05), Vector3(0.05, 0.1, -0.05), Vector3(0, 30, 70))
			_box(_dark(), Vector3(0.12, 0.02, 0.05), Vector3(0.1, 0.16, -0.05), Vector3(0, 30, 0))
			_cyl(_steel(), 0.015, 0.015, 0.1, Vector3(-0.1, 0.06, -0.06), Vector3(40, 0, 20), 6)
			_box(glow, Vector3(0.04, 0.02, 0.04), Vector3(-0.12, 0.03, 0.08), Vector3(0, 20, 0))
		"blade_strip":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15), 0, deg_to_rad(12))), Vector3.ZERO)
			_box(_steel(), Vector3(0.5, 0.08, 0.02), Vector3.ZERO)
			for i in 12:
				_tooth(_steel(), Vector3(0.04, 0.035, 0.02), Vector3(-0.22 + i * 0.04, 0.0575, 0))
			_box(glow, Vector3(0.5, 0.006, 0.022), Vector3(0, 0.038, 0))
			for x in [-0.15, 0.0, 0.15]:
				_cyl(_dark(), 0.012, 0.012, 0.024, Vector3(x, -0.01, 0), Vector3(90, 0, 0), 8)
		"gate_key":
			_ring(_brass(), 0.05, 0.09, Vector3(-0.18, 0, 0), Vector3(90, 0, 0))
			_cyl(_brass(), 0.022, 0.022, 0.3, Vector3(0.03, 0, 0), Vector3(0, 0, 90))
			_box(_brass(), Vector3(0.05, 0.09, 0.02), Vector3(0.14, -0.055, 0))
			_box(_brass(), Vector3(0.03, 0.055, 0.02), Vector3(0.08, -0.04, 0))
			_ring(_steel(), 0.018, 0.03, Vector3(-0.28, -0.03, 0), Vector3(90, 0, 0))
			_box(glow, Vector3(0.06, 0.08, 0.01), Vector3(-0.29, -0.1, 0))
		"relay_card":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(70), 0, 0)), Vector3.ZERO)
			_box(_mat("card_white", Color(0.9, 0.92, 0.95), 0.1, 0.4), Vector3(0.34, 0.012, 0.22), Vector3.ZERO)
			_box(_brass(), Vector3(0.06, 0.016, 0.05), Vector3(-0.09, 0.0, 0.03))
			_box(glow, Vector3(0.34, 0.016, 0.04), Vector3(0, 0.0, -0.07))
			_ring(_dark(), 0.02, 0.03, Vector3(0.1, 0.008, 0.04))
		"solar_cell":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(55), 0, 0)), Vector3.ZERO)
			_box(_mat("solar_glass", Color(0.06, 0.1, 0.3), 0.5, 0.12, colour * 0.3, 0.6), Vector3(0.42, 0.015, 0.42), Vector3.ZERO)
			for i in [1, 2, 3]:
				var c: float = -0.21 + 0.105 * i
				_box(_steel(), Vector3(0.42, 0.018, 0.006), Vector3(0, 0, c))
				_box(_steel(), Vector3(0.006, 0.018, 0.42), Vector3(c, 0, 0))
			for s in [-1.0, 1.0]:
				_box(_steel(), Vector3(0.44, 0.03, 0.02), Vector3(0, 0, 0.215 * s))
				_box(_steel(), Vector3(0.02, 0.03, 0.44), Vector3(0.215 * s, 0, 0))
		"sun_tracker":
			_cyl(_dark(), 0.12, 0.14, 0.06, Vector3(0, -0.12, 0))
			_cyl(_steel(), 0.025, 0.025, 0.16, Vector3(0, -0.01, 0))
			_box(_orange(), Vector3(0.12, 0.08, 0.08), Vector3(0, 0.08, 0))
			_box(_steel(), Vector3(0.2, 0.02, 0.03), Vector3(0.07, 0.14, 0), Vector3(0, 0, 30))
			_sphere(glow, 0.05, Vector3(0.16, 0.19, 0))
			_ring(_dark(), 0.05, 0.068, Vector3(0.16, 0.19, 0), Vector3(0, 0, 60))
		"capacitor":
			var sleeve := _mat("capacitor_blue", Color(0.15, 0.3, 0.7), 0.1, 0.35)
			_cyl(sleeve, 0.13, 0.13, 0.34, Vector3.ZERO)
			_cyl(_steel(), 0.125, 0.125, 0.02, Vector3(0, 0.18, 0))
			_box(_dark(), Vector3(0.18, 0.006, 0.012), Vector3(0, 0.191, 0))
			_box(_dark(), Vector3(0.012, 0.006, 0.18), Vector3(0, 0.191, 0))
			for x in [-0.05, 0.05]:
				_cyl(_steel(), 0.012, 0.012, 0.08, Vector3(x, -0.21, 0))
			_cyl(glow, 0.133, 0.133, 0.03, Vector3(0, 0.08, 0))
		"lift_fan":
			_model = Transform3D(Basis.from_euler(Vector3(deg_to_rad(60), 0, 0)), Vector3.ZERO)
			_ring(_dark(), 0.18, 0.23, Vector3.ZERO)
			_cyl(_steel(), 0.05, 0.05, 0.06, Vector3.ZERO)
			for i in 6:
				var a := TAU * i / 6.0
				_box(_steel(), Vector3(0.12, 0.01, 0.05), Vector3(cos(a) * 0.11, 0, sin(a) * 0.11), Vector3(25, -rad_to_deg(a), 0))
			for i in 3:
				var a := TAU * i / 3.0 + 0.5
				_box(_dark(), Vector3(0.14, 0.015, 0.015), Vector3(cos(a) * 0.12, -0.03, sin(a) * 0.12), Vector3(0, -rad_to_deg(a), 0))
			_ring(glow, 0.225, 0.235, Vector3(0, 0.03, 0))
		"gyro":
			_ring(_brass(), 0.19, 0.22, Vector3.ZERO, Vector3(90, 0, 0))
			_ring(_steel(), 0.14, 0.165, Vector3.ZERO, Vector3(0, 0, 90))
			_ring(_brass(), 0.09, 0.11, Vector3.ZERO, Vector3(45, 0, 0))
			_sphere(glow, 0.05, Vector3.ZERO)
			for y in [-0.2, 0.2]:
				_cyl(_steel(), 0.012, 0.012, 0.05, Vector3(0, y, 0))
		"printer_core":
			var e := 0.32
			for a in [-1.0, 1.0]:
				for b in [-1.0, 1.0]:
					_box(_dark(), Vector3(e, 0.025, 0.025), Vector3(0, a * e * 0.5, b * e * 0.5))
					_box(_dark(), Vector3(0.025, e, 0.025), Vector3(a * e * 0.5, 0, b * e * 0.5))
					_box(_dark(), Vector3(0.025, 0.025, e), Vector3(a * e * 0.5, b * e * 0.5, 0))
			_box(glow, Vector3(0.13, 0.13, 0.13), Vector3.ZERO, Vector3(45, 35, 0))
			for x in [-0.08, 0.08]:
				_cyl(_steel(), 0.008, 0.008, e, Vector3(x, 0, 0.1))
		"nozzle":
			_box(_mat("heat_red", Color(0.7, 0.15, 0.1), 0.3, 0.5), Vector3(0.14, 0.1, 0.14), Vector3(0, 0.02, 0))
			_cyl(_brass(), 0.07, 0.07, 0.05, Vector3(0, -0.055, 0), Vector3.ZERO, 6)
			_cyl(_brass(), 0.012, 0.06, 0.12, Vector3(0, -0.14, 0))
			_sphere(glow, 0.02, Vector3(0, -0.205, 0))
			for i in 4:
				_box(_steel(), Vector3(0.18, 0.012, 0.18), Vector3(0, 0.1 + i * 0.03, 0))
			_cyl(_steel(), 0.02, 0.02, 0.1, Vector3(0, 0.18, 0))
		_:
			return false
	return true
