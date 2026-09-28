extends SceneTree

# Builds the Relay Vault's shell from level_design/relay_vault_design.json:
# floor slabs, ceilings and walls for every space, with openings where two
# spaces share an edge (a lintel above the lower one). Mesh and collision are
# the same boxes, so the vault is sealed by construction (rule 6). Dressing:
# wall lamps, pipes, the skylight patch over the beam source, hazard stripes.
# Markers carry what the gameplay wrapper (scripts/dungeons/relay_vault.gd)
# needs (the design folder is not exported with the game).
#   <godot> --headless --path . -s tools/relay_vault_build.gd
# Writes scenes/level_vault/ (generated: never hand-edit).

const DESIGN := "res://level_design/relay_vault_design.json"
const OUT_DIR := "res://scenes/level_vault/"
const SCENE_FILE := "generated_vault_shell.tscn"
const EPS := 0.01

var _root: Node3D
var _body: StaticBody3D
var _acc := {}
var _mats := {}
var _t := 0.4

func _initialize() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	_t = float(d.get("wall", 0.4))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_root = Node3D.new()
	_root.name = "VaultShell"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_add(_root, _body)
	var floor_mat := _mat("vault_floor", Color(0.3, 0.31, 0.33), 0.6, 0.5)
	var wall_mat := _mat("vault_wall", Color(0.42, 0.43, 0.45), 0.0, 0.9)
	var ceiling_mat := _mat("vault_ceiling", Color(0.2, 0.21, 0.22), 0.0, 0.9)
	var spaces: Array = d["spaces"]
	var walls := 0
	for s in spaces:
		var r: Array = s["rect"]
		var h := float(s["height"])
		var x0 := float(r[0])
		var z0 := float(r[1])
		var x1 := float(r[2])
		var z1 := float(r[3])
		_box(floor_mat, Vector3((x0 + x1) * 0.5, -_t * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0 + _t * 2, _t, z1 - z0 + _t * 2), true)
		_box(ceiling_mat, Vector3((x0 + x1) * 0.5, h + _t * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0 + _t * 2, _t, z1 - z0 + _t * 2), true)
		# the four edges: [fixed coordinate, from, to, axis ("x" = runs along x), outward sign]
		var edges := [[z0, x0, x1, "x", -1.0], [z1, x0, x1, "x", 1.0], [x0, z0, z1, "z", -1.0], [x1, z0, z1, "z", 1.0]]
		for e in edges:
			var fixed := float(e[0])
			var a := float(e[1])
			var b := float(e[2])
			var along_x: bool = e[3] == "x"
			var out := float(e[4])
			var openings := []            # [from, to, neighbour height]
			for other in spaces:
				if other == s:
					continue
				var o: Array = other["rect"]
				var touches := false
				var oa := 0.0
				var ob := 0.0
				if along_x:
					touches = absf((float(o[3]) if out < 0.0 else float(o[1])) - fixed) < EPS
					oa = float(o[0])
					ob = float(o[2])
				else:
					touches = absf((float(o[2]) if out < 0.0 else float(o[0])) - fixed) < EPS
					oa = float(o[1])
					ob = float(o[3])
				if touches and minf(b, ob) - maxf(a, oa) > EPS:
					openings.append([maxf(a, oa), minf(b, ob), float(other["height"])])
			openings.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
			var cursor := a
			for gap in openings + [[b, b, 0.0]]:
				var ga := float(gap[0])
				if ga - cursor > EPS:
					_wall(fixed, cursor, ga, along_x, out, h, cursor <= a + EPS, ga >= b - EPS, wall_mat)
					walls += 1
				if float(gap[1]) > ga and float(gap[2]) < h:          # lintel over a lower opening
					_wall_piece(fixed, ga, float(gap[1]), along_x, out, float(gap[2]), h, wall_mat)
				cursor = maxf(cursor, float(gap[1]))
	_dress(d)
	_markers(d)
	var mesh := ArrayMesh.new()
	var tris := 0
	for m in _acc:
		var acc: Array = _acc[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc[0]
		arrays[Mesh.ARRAY_NORMAL] = acc[1]
		arrays[Mesh.ARRAY_TEX_UV] = acc[2]
		arrays[Mesh.ARRAY_INDEX] = acc[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		tris += acc[3].size() / 3
	var err := ResourceSaver.save(mesh, OUT_DIR + "vault_mesh.res", ResourceSaver.FLAG_COMPRESS)
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = ResourceLoader.load(OUT_DIR + "vault_mesh.res", "", ResourceLoader.CACHE_MODE_REPLACE)
	_add(_root, mi)
	var packed := PackedScene.new()
	if err == OK:
		err = packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + SCENE_FILE)
	print("relay vault: %d spaces, %d wall runs, %d collision boxes, %d surfaces, %d triangles -> %s" % [spaces.size(), walls, _body.get_child_count(), mesh.get_surface_count(), tris, error_string(err)])
	_root.free()
	quit(0 if err == OK else 1)

## A full-height wall run outside one edge; corners are sealed by extending the
## runs along X by the wall thickness at the rect's own corners.
func _wall(fixed: float, a: float, b: float, along_x: bool, out: float, h: float, at_start: bool, at_end: bool, mat: Material) -> void:
	if along_x:
		a -= _t if at_start else 0.0
		b += _t if at_end else 0.0
	_wall_piece(fixed, a, b, along_x, out, 0.0, h, mat)

func _wall_piece(fixed: float, a: float, b: float, along_x: bool, out: float, y0: float, y1: float, mat: Material) -> void:
	var line := fixed + out * _t * 0.5
	var centre: Vector3
	var size: Vector3
	if along_x:
		centre = Vector3((a + b) * 0.5, (y0 + y1) * 0.5, line)
		size = Vector3(b - a, y1 - y0, _t)
	else:
		centre = Vector3(line, (y0 + y1) * 0.5, (a + b) * 0.5)
		size = Vector3(_t, y1 - y0, b - a)
	_box(mat, centre, size, true)

func _dress(d: Dictionary) -> void:
	var lamp := _mat("vault_lamp", Color(1.0, 0.85, 0.6), 0.0, 0.5, Color(1.0, 0.8, 0.55), 2.2)
	var pipe := _mat("vault_pipe", Color(0.55, 0.36, 0.24), 0.7, 0.45)
	var hazard := _mat("vault_hazard", Color(0.9, 0.7, 0.1), 0.0, 0.7)
	var sky := _mat("vault_skylight", Color(1.0, 0.97, 0.85), 0.0, 0.5, Color(1.0, 0.95, 0.8), 1.2)
	for l in d["lights"]:
		_box(lamp, Vector3(l[0], float(l[1]) + 0.35, l[2]), Vector3(0.6, 0.06, 0.6), false)
	var hall := _space(d, "hall")
	for x in [float(hall[0]) + 0.25, float(hall[2]) - 0.25]:
		for y in [4.2, 4.6]:
			var p := CylinderMesh.new()
			p.top_radius = 0.09
			p.bottom_radius = 0.09
			p.height = float(hall[3]) - float(hall[1])
			p.radial_segments = 10
			_prim(pipe, p, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, (float(hall[1]) + float(hall[3])) * 0.5)))
	var src: Array = d["puzzle"]["source"]
	var hall_h := float(_space_def(d, "hall")["height"])
	_box(sky, Vector3(float(src[0]) + 0.25, hall_h - 0.02, src[1]), Vector3(0.9, 0.03, 0.9), false)
	for s in d["spaces"]:
		if String(s["id"]).ends_with("passage"):
			var r: Array = s["rect"]
			for z in [float(r[1]) + 0.15, float(r[3]) - 0.15]:
				_box(hazard, Vector3((float(r[0]) + float(r[2])) * 0.5, 0.005, z), Vector3(float(r[2]) - float(r[0]), 0.01, 0.12), false)

func _markers(d: Dictionary) -> void:
	for key in d["markers"]:
		var p: Array = d["markers"][key]
		_marker(String(key).to_pascal_case(), Vector3(p[0], 0, p[1]))
	var pz: Dictionary = d["puzzle"]
	var src: Array = pz["source"]
	var source := _marker("BeamSource", Vector3(src[0], 1.2, src[1]))
	source.set_meta("direction", pz["direction"])
	source.set_meta("laser_seconds", float(pz.get("laser_seconds", 20)))
	source.set_meta("hall_rect", _space(d, "hall"))
	var rec: Array = pz["receiver"]
	_marker("Receiver", Vector3(rec[0], 1.2, rec[1]))
	var dr: Array = pz["door"]
	var door := _marker("Door", Vector3((float(dr[0]) + float(dr[2])) * 0.5, 0, (float(dr[1]) + float(dr[3])) * 0.5))
	door.set_meta("size", Vector3(float(dr[2]) - float(dr[0]), float(_space_def(d, "oracle_passage")["height"]), float(dr[3]) - float(dr[1])))
	for id in pz["mirrors"]:
		var m: Dictionary = pz["mirrors"][id]
		var mk := _marker("Mirror_" + String(id), Vector3(m["pos"][0], 0, m["pos"][1]))
		mk.set_meta("start", m["start"])
		mk.set_meta("decoy", String(id) == "decoy")
	var i := 0
	for l in d["lights"]:
		_marker("Light%d" % i, Vector3(l[0], l[1], l[2]))
		i += 1

func _space_def(d: Dictionary, id: String) -> Dictionary:
	for s in d["spaces"]:
		if s["id"] == id:
			return s
	return {}

func _space(d: Dictionary, id: String) -> Array:
	return _space_def(d, id)["rect"]

func _marker(marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	_add(_root, m)
	return m

func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root

func _mat(key: String, colour: Color, metallic: float, roughness: float, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = colour
	m.metallic = metallic
	m.roughness = roughness
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m

func _box(mat: Material, centre: Vector3, size: Vector3, solid: bool) -> void:
	var box := BoxMesh.new()
	box.size = size
	_prim(mat, box, Transform3D(Basis(), centre))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.name = "Box%d" % _body.get_child_count()
		col.shape = shape
		col.position = centre
		_add(_body, col)

func _prim(mat: Material, mesh: PrimitiveMesh, xf: Transform3D) -> void:
	var arr := mesh.get_mesh_arrays()
	if not _acc.has(mat):
		_acc[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	var acc: Array = _acc[mat]
	var base: int = acc[0].size()
	var nb: Basis = xf.basis.inverse().transposed()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for k in verts.size():
		acc[0].append(xf * verts[k])
		acc[1].append((nb * normals[k]).normalized())
	acc[2].append_array(arr[Mesh.ARRAY_TEX_UV])
	for idx in arr[Mesh.ARRAY_INDEX]:
		acc[3].append(base + idx)
