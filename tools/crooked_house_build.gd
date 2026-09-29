extends SceneTree

# Builds the crooked house's shell: Medieval Village pieces + primitive furniture
# merged into one mesh (one surface per material = a handful of draw calls on the
# laptop), a sealed box collision shell (walls with a door gap + ceiling, rule 6),
# and Marker3D anchors the hand-made wrapper (scenes/props/crooked_house.tscn)
# snaps its gameplay nodes to. From the project root:
#   <godot> --headless --path . -s tools/crooked_house_build.gd
# Writes scenes/props/crooked_house/ (never hand-edit: rebuilt every run).
#
# House frame: origin = floor centre, 4 m (X) x 6 m (Z), door in the east wall
# (+X). The whole structure is sheared (leans ~5 deg west and ~2 deg north),
# which keeps every join closed while the timber frame runs crooked; the roof,
# chimney, door and a shutter get their own extra tilt. Furniture stays upright.
# The forest design's "solids" (level_design/forest_design.json) mirror the
# walls and furniture below for the 2D verifier: change both together.

const OUT_DIR := "res://scenes/props/crooked_house/"
const SCENE_FILE := "generated_crooked_house_shell.tscn"
const MEDIEVAL := "res://assets/quaternius_medieval/%s.gltf"

const SHEAR_X := -0.087      # x moves this much per metre of height (tan 5 deg, leaning west)
const SHEAR_Z := -0.03       # z per metre of height (leaning north)
const WALL_TOP := 3.12
const HALF_W := 2.0          # outer wall lines at x = +-2, z = +-3
const HALF_L := 3.0
const DOOR_HALF := 0.65      # measured opening of Wall_Plaster_Door_Round
const WALL_IN := 0.31        # wall pieces reach 0.31 m inward and 0.09 m outward of their line
const WALL_OUT := 0.09

# Wardrobe with the mouse hole in the south-west corner (see the tiny curse).
const WARDROBE := {"x0": -1.69, "x1": -0.89, "z0": 1.2, "z1": 2.6, "height": 2.0, "shelf": 1.0,
	"hole_half": 0.035, "hole_height": 0.07, "board": 0.04}

var _root: Node3D
var _surfaces := {}           # model path -> surfaces
var _by_material := {}        # Material -> [positions, normals, uvs, colours, indices]
var _body: StaticBody3D
var _mats := {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_root = Node3D.new()
	_root.name = "CrookedHouseShell"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_add(_root, _body)
	var shear := Transform3D(Basis(Vector3(1, 0, 0), Vector3(SHEAR_X, 1, SHEAR_Z), Vector3(0, 0, 1)), Vector3.ZERO)

	# --- structure (sheared) -------------------------------------------------------
	var east := [["Wall_Plaster_Window_Wide_Round", -2.0], ["Wall_Plaster_Door_Round", 0.0], ["Wall_Plaster_WoodGrid", 2.0]]
	var west := [["Wall_Plaster_Window_Thin_Round", -2.0], ["Wall_Plaster_Straight", 0.0], ["Wall_Plaster_WoodGrid", 2.0]]
	for w in east:
		_piece(w[0], shear * _xf(Vector3(HALF_W, 0, w[1]), 90))
	for w in west:
		_piece(w[0], shear * _xf(Vector3(-HALF_W, 0, w[1]), -90))
	_piece("Wall_Plaster_WoodGrid", shear * _xf(Vector3(-1, 0, -HALF_L), 180))
	_piece("Wall_Plaster_Straight", shear * _xf(Vector3(1, 0, -HALF_L), 180))
	_piece("Wall_Plaster_Straight", shear * _xf(Vector3(-1, 0, HALF_L), 0))
	_piece("Wall_Plaster_Window_Wide_Round", shear * _xf(Vector3(1, 0, HALF_L), 0))
	for c in [Vector3(HALF_W, 0, -HALF_L), Vector3(HALF_W, 0, HALF_L), Vector3(-HALF_W, 0, -HALF_L), Vector3(-HALF_W, 0, HALF_L)]:
		_piece("Corner_Exterior_Wood", shear * _xf(c, 0))
	_piece("DoorFrame_Round_WoodDark", shear * _xf(Vector3(HALF_W, 0, 0), 90))
	_piece("Window_Wide_Round1", shear * _xf(Vector3(HALF_W, 0, -2.0), 90))
	_piece("Window_Thin_Round1", shear * _xf(Vector3(-HALF_W, 0, -2.0), -90))
	_piece("Window_Wide_Round1", shear * _xf(Vector3(1, 0, HALF_L), 0))
	_piece("WindowShutters_Wide_Round_Open", shear * _xf(Vector3(HALF_W, 0, -2.0), 90, 0.0, 9.0))   # hangs askew
	_piece("WindowShutters_Wide_Round_Closed", shear * _xf(Vector3(1, 0, HALF_L), 0, 0.0, -4.0))
	_piece("Roof_Front_Brick4", shear * _xf(Vector3(0, WALL_TOP, -HALF_L), 180))
	_piece("Roof_Front_Brick4", shear * _xf(Vector3(0, WALL_TOP, HALF_L), 0))
	_piece("Roof_RoundTiles_4x6", shear * _xf(Vector3(0, WALL_TOP - 0.05, 0), 2.5, 0.0, 3.0))    # sags and twists
	_piece("Prop_Chimney", shear * _xf(Vector3(1.1, 4.4, 1.9), 10, 0.0, -13.0))
	_piece("Prop_Vine5", shear * _xf(Vector3(HALF_W + 0.12, 3.0, -1.1), 90))
	_piece("Prop_Vine6", shear * _xf(Vector3(0.2, 3.0, HALF_L + 0.12), 0))
	_piece("Prop_Vine4", shear * _xf(Vector3(-0.9, 4.1, -HALF_L - 0.14), 180))

	# --- upright pieces: floor, the door hanging open, fallen bricks -----------------
	for x in [-1.0, 1.0]:
		for z in [-2.0, 0.0, 2.0]:
			_piece("Floor_WoodDark", _xf(Vector3(x, 0.02, z), 0))
	_piece("Door_1_Round", _xf(Vector3(HALF_W + 0.05, 0.03, DOOR_HALF + 0.02), -15, 0.0, 3.0))
	for b in [[Vector3(1.6, 0.08, 3.9), 20], [Vector3(2.2, 0.08, 3.5), 75], [Vector3(0.9, 0.08, 4.3), 140]]:
		_piece("Prop_Brick1", _xf(b[0], b[1]))

	# --- furniture (primitives, upright) ----------------------------------------------
	var wood := _mat("wood", Color(0.30, 0.20, 0.13), 0.8)
	var dark_wood := _mat("dark_wood", Color(0.18, 0.12, 0.08), 0.85)
	var cloth := _mat("cloth", Color(0.28, 0.36, 0.22), 0.95)
	var stone := _mat("hole", Color(0.02, 0.02, 0.02), 1.0)
	# the candle: plain wax with a small flame (a glowing stick read as a pickup, playtest 2026-09-29)
	var wax := _mat("wax", Color(0.85, 0.8, 0.66), 0.7)
	var flame := _mat("flame", Color(1.0, 0.8, 0.4), 1.0, Color(1.0, 0.65, 0.25))
	# bed in the north-west corner
	_box(wood, Vector3(-1.14, 0.2, -1.84), Vector3(1.0, 0.4, 1.7), true)
	_box(cloth, Vector3(-1.14, 0.44, -1.74), Vector3(0.94, 0.1, 1.4), false)
	_box(cloth, Vector3(-1.14, 0.47, -2.5), Vector3(0.6, 0.12, 0.25), false)
	# shelf against the north wall, east half (the solar cell sits on top)
	_box(wood, Vector3(1.0, 0.475, -2.52), Vector3(1.0, 0.95, 0.34), true)
	_box(dark_wood, Vector3(1.0, 0.45, -2.35), Vector3(0.96, 0.04, 0.02), false)
	# table and stool, south-east
	_box(wood, Vector3(1.05, 0.77, 2.05), Vector3(0.9, 0.06, 0.7), false)
	for leg in [Vector3(0.66, 0.37, 1.76), Vector3(1.44, 0.37, 1.76), Vector3(0.66, 0.37, 2.34), Vector3(1.44, 0.37, 2.34)]:
		_box(dark_wood, leg, Vector3(0.06, 0.74, 0.06), false)
	_shape(Vector3(1.05, 0.4, 2.05), Vector3(0.9, 0.8, 0.7))
	_box(wood, Vector3(0.45, 0.22, 1.2), Vector3(0.34, 0.44, 0.34), true)
	_box(wax, Vector3(1.2, 0.86, 2.15), Vector3(0.05, 0.12, 0.05), false)
	_box(flame, Vector3(1.2, 0.935, 2.15), Vector3(0.012, 0.03, 0.012), false)
	# plank ceiling under the roof (follows the lean), so indoors never shows the roof's underside
	_box(dark_wood, Vector3(SHEAR_X * 3.08, 3.08, SHEAR_Z * 3.08), Vector3(HALF_W * 2 - 0.5, 0.04, HALF_L * 2 - 0.5), false)
	# rug in the middle (no collision: the robot drives over it)
	_box(cloth, Vector3(0.1, 0.035, 0.2), Vector3(1.4, 0.01, 2.2), false)
	_wardrobe(dark_wood, wood, stone)

	# --- collision shell: sheared walls as tilted boxes, door gap, ceiling ---------------
	var lean_x := atan(-SHEAR_X)      # east/west walls lean west: rotate about Z
	var lean_z := atan(SHEAR_Z)       # north/south walls lean north: rotate about X
	var h := WALL_TOP + 0.35
	var t := WALL_IN + WALL_OUT
	var mid_x := HALF_W - (WALL_IN - WALL_OUT) * 0.5    # centre line of the east wall's thickness
	var mid_z := HALF_L - (WALL_IN - WALL_OUT) * 0.5
	var along := HALF_L + WALL_OUT + 0.2
	var door_len := along - DOOR_HALF
	_wall(Vector3(-mid_x, h * 0.5, 0), Vector3(t, h, along * 2), lean_x, 0.0)
	_wall(Vector3(mid_x, h * 0.5, -(DOOR_HALF + door_len * 0.5)), Vector3(t, h, door_len), lean_x, 0.0)
	_wall(Vector3(mid_x, h * 0.5, DOOR_HALF + door_len * 0.5), Vector3(t, h, door_len), lean_x, 0.0)
	_wall(Vector3(0, h * 0.5, -mid_z), Vector3((HALF_W + WALL_OUT + 0.2) * 2, h, t), 0.0, lean_z)
	_wall(Vector3(0, h * 0.5, mid_z), Vector3((HALF_W + WALL_OUT + 0.2) * 2, h, t), 0.0, lean_z)
	_wall(Vector3(0, WALL_TOP + 0.1, 0), Vector3(HALF_W * 2 + 1.2, 0.2, HALF_L * 2 + 1.2), 0.0, 0.0, true)
	_wall(Vector3(mid_x, (2.45 + h) * 0.5, 0), Vector3(t, h - 2.45, DOOR_HALF * 2 + 0.2), lean_x, 0.0)   # wall above the door arch

	# --- anchors for the wrapper scene ---------------------------------------------------
	_marker("Inside", Vector3(0.7, 0, 0))
	_marker("ZombieSpot", Vector3(-0.7, 0, 0.0))
	_marker("ShelfTop", Vector3(1.0, 0.95, -2.52))
	_marker("NookCentre", Vector3((WARDROBE["x0"] + WARDROBE["x1"]) * 0.5, 0, (WARDROBE["z0"] + WARDROBE["z1"]) * 0.5))
	_marker("HoleFront", Vector3(WARDROBE["x1"] + 0.5, 0, (WARDROBE["z0"] + WARDROBE["z1"]) * 0.5))
	_marker("Candle", Vector3(1.2, 0.95, 2.15))
	_marker("RoomLight", Vector3(0.0, 2.5, 0.0))
	_marker("DoorOutside", Vector3(HALF_W + 1.2, 0, 0))
	_marker("ChimneyTop", shear * Vector3(1.1 + sin(deg_to_rad(13.0)) * 3.1, 4.4 + 3.0, 1.9))

	var mesh := ArrayMesh.new()
	var triangles := 0
	for mat in _by_material:
		var acc: Array = _by_material[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc[0]
		arrays[Mesh.ARRAY_NORMAL] = acc[1]
		arrays[Mesh.ARRAY_TEX_UV] = acc[2]
		arrays[Mesh.ARRAY_INDEX] = acc[4]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		triangles += acc[4].size() / 3
	var err := ResourceSaver.save(mesh, OUT_DIR + "crooked_house_mesh.res", ResourceSaver.FLAG_COMPRESS)
	var mi := MeshInstance3D.new()
	mi.name = "House"
	mi.mesh = ResourceLoader.load(OUT_DIR + "crooked_house_mesh.res", "", ResourceLoader.CACHE_MODE_REPLACE)
	_add(_root, mi)
	var packed := PackedScene.new()
	if err == OK:
		err = packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + SCENE_FILE)
	print("crooked house: %d surfaces, %d triangles, %d collision boxes -> %s" % [mesh.get_surface_count(), triangles, _body.get_child_count(), error_string(err)])
	_root.free()
	quit(0 if err == OK else 1)

# Transform for a piece standing at `base`: turned `yaw` degrees (0 = local +Z
# faces +Z), then leaned about its own X and rolled about its own Z.
func _xf(base: Vector3, yaw: float, lean: float = 0.0, roll: float = 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.FORWARD, deg_to_rad(-roll)) * Basis(Vector3.RIGHT, deg_to_rad(lean))
	return Transform3D(b, base)

func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root

func _marker(marker_name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	_add(_root, m)

func _mat(key: String, colour: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = colour
	m.roughness = roughness
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m

var _by_name := {}           # material name -> the first Material of that name (every glTF brings its own copy)

func _accumulate(mat: Material, positions: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, xf: Transform3D) -> void:
	if mat != null and mat.resource_name != "":
		if not _by_name.has(mat.resource_name):
			_by_name[mat.resource_name] = mat
		mat = _by_name[mat.resource_name]
	if not _by_material.has(mat):
		_by_material[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
	var acc: Array = _by_material[mat]
	var base: int = acc[0].size()
	var normal_basis: Basis = xf.basis.inverse().transposed()
	for i in positions.size():
		acc[0].append(xf * positions[i])
		acc[1].append((normal_basis * normals[i]).normalized())
	acc[2].append_array(uvs)
	for index in indices:
		acc[4].append(base + index)

func _piece(asset: String, xf: Transform3D) -> void:
	var path := MEDIEVAL % asset
	if not _surfaces.has(path):
		_surfaces[path] = _model_surfaces(path)
	for s in _surfaces[path]:
		_accumulate(s["material"], s["positions"], s["normals"], s["uvs"], s["indices"], xf)

## A primitive box into the merged mesh; `solid` also adds a matching collision box.
func _box(mat: Material, centre: Vector3, size: Vector3, solid: bool) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_accumulate(mat, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_TEX_UV], indices, Transform3D(Basis(), centre))
	if solid:
		_shape(centre, size)

func _shape(centre: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "Box%d" % _body.get_child_count()
	col.shape = shape
	col.position = centre
	_add(_body, col)

## A collision box tilted like the sheared walls (about Z for east/west walls, X for north/south).
func _wall(centre: Vector3, size: Vector3, about_z: float, about_x: float, ceiling: bool = false) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "Ceiling" if ceiling else "Wall%d" % _body.get_child_count()
	col.shape = shape
	var b := Basis(Vector3.FORWARD, -about_z) * Basis(Vector3.RIGHT, about_x)
	# shift the centre with the shear so the box follows the leaning wall
	col.transform = Transform3D(b, centre + Vector3(SHEAR_X, 0, SHEAR_Z) * centre.y)
	_add(_body, col)

## The wardrobe: an upper cupboard, and below its shelf a low compartment whose
## only way in is a mouse hole in the front: too small for the robot, just right
## for a tiny one. The compartment is lower than the full-size robot, so the
## tiny curse can never wear off in there and trap it (player.gd checks the room).
func _wardrobe(outer: Material, trim: Material, hole: Material) -> void:
	var w := WARDROBE
	var bd: float = w["board"]
	var x0: float = w["x0"]
	var x1: float = w["x1"]
	var z0: float = w["z0"]
	var z1: float = w["z1"]
	var top: float = w["height"]
	var shelf: float = w["shelf"]
	var hh: float = w["hole_half"]
	var hy: float = w["hole_height"]
	var zc := (z0 + z1) * 0.5
	var xc := (x0 + x1) * 0.5
	_box(outer, Vector3(x0 + bd * 0.5, top * 0.5, zc), Vector3(bd, top, z1 - z0), true)                  # back
	_box(outer, Vector3(xc, top * 0.5, z0 + bd * 0.5), Vector3(x1 - x0, top, bd), true)                  # sides
	_box(outer, Vector3(xc, top * 0.5, z1 - bd * 0.5), Vector3(x1 - x0, top, bd), true)
	_box(outer, Vector3(xc, top - bd * 0.5, zc), Vector3(x1 - x0, bd, z1 - z0), true)                    # top
	_box(outer, Vector3(xc, shelf + bd * 0.5, zc), Vector3(x1 - x0, bd, z1 - z0), true)                  # compartment ceiling
	_box(outer, Vector3(xc, (shelf + top) * 0.5, zc), Vector3(x1 - x0 - bd * 2, top - shelf - bd * 2, z1 - z0 - bd * 2), true)   # upper cupboard (closed)
	_box(trim, Vector3(x1 - bd * 0.5, (shelf + top) * 0.5, zc), Vector3(bd, top - shelf, z1 - z0), false)   # doors
	_box(outer, Vector3(x1 + 0.02, top - 0.4, zc - 0.25), Vector3(0.04, 0.08, 0.04), false)              # knob
	# front of the compartment: left and right of the hole, and above it
	var left := (zc - hh) - z0
	_box(trim, Vector3(x1 - bd * 0.5, shelf * 0.5, z0 + left * 0.5), Vector3(bd, shelf, left), true)
	_box(trim, Vector3(x1 - bd * 0.5, shelf * 0.5, z1 - left * 0.5), Vector3(bd, shelf, left), true)
	_box(trim, Vector3(x1 - bd * 0.5, (hy + shelf) * 0.5, zc), Vector3(bd, shelf - hy, hh * 2), true)
	# a dark arch just inside the hole so it reads as a hole from across the room
	var arch := CylinderMesh.new()
	arch.top_radius = hh
	arch.bottom_radius = hh
	arch.height = 0.01
	arch.radial_segments = 16
	var arrays := arch.get_mesh_arrays()
	var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, 0.0), Vector3(x0 + bd + 0.02, hy - hh, zc))
	_accumulate(hole, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_TEX_UV], arrays[Mesh.ARRAY_INDEX], xf)

# One model's surfaces in model space (LOD 0).
func _model_surfaces(path: String) -> Array:
	var model: Node3D = load(path).instantiate()
	var out := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var local: Transform3D = (mi as MeshInstance3D).transform
		var parent: Node = mi.get_parent()
		while parent != model and parent is Node3D:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var positions := PackedVector3Array()
			var normals := PackedVector3Array()
			for v in arrays[Mesh.ARRAY_VERTEX]:
				positions.append(local * v)
			for n in arrays[Mesh.ARRAY_NORMAL]:
				normals.append((local.basis * n).normalized())
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			if uvs.size() != positions.size():
				uvs.resize(positions.size())
			out.append({"material": mesh.surface_get_material(s), "positions": positions, "normals": normals,
				"uvs": uvs, "indices": arrays[Mesh.ARRAY_INDEX]})
	model.free()
	return out
