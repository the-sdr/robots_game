extends SceneTree

# Build step 2 of 2: level_design/build/level.json -> scenes/level/generated_level.tscn
# (run tools/level_build.py first). From the project root:
#   <godot> --headless --path . -s tools/level_bake.gd
# Overwrites only files in scenes/level/. world.tscn instances the result.

const LEVEL_JSON := "res://level_design/build/level.json"
const OUT_DIR := "res://scenes/level/"
const TREE_SCENE := "res://scenes/props/solid_tree.tscn"
const ROCK_SCENE := "res://scenes/props/solid_rock.tscn"
const COLLECTIBLE_SCENE := "res://scenes/props/collectible_part.tscn"
const BUSH_SCRIPT := "res://scripts/bush_sway.gd"
const GROUND_COLOR := Color(0.3, 0.55, 0.3)
const WALL_SIZE := Vector3(2.0, 3.12, 0.41)
const WALL_CENTRE := Vector3(0, 1.56, -0.11)
const BACKGROUND_CHUNK := 32.0
const COLLECTIBLES := {
	"CP1": {"name": "Servo motor", "color": Color(1.0, 0.6, 0.15)},
	"CP2": {"name": "Optic lens", "color": Color(0.3, 0.8, 1.0)},
	"CP3": {"name": "Power cell", "color": Color(0.5, 1.0, 0.4)},
	"CP4": {"name": "Circuit board", "color": Color(0.9, 0.4, 1.0)},
}

var _root: Node3D
var _scenes := {}

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_JSON))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "background"))
	_root = Node3D.new()
	_root.name = "GeneratedLevel"
	_build_terrain(data["terrain"])
	var trees := _group("Trees")
	var props := _group("Props")
	var collectibles := _group("Collectibles")
	var counts := {}
	for o in data["objects"]:
		var xf := _transform(o)
		var kind: String = o["kind"]
		counts[kind] = counts.get(kind, 0) + 1
		var node_name := "%s_%d" % [o["code"], counts[kind]]
		match kind:
			"tree":
				var tree := _instance(TREE_SCENE, trees, node_name, xf)
				tree.set("model_path", o["path"])
			"rock":
				var rock := _instance(ROCK_SCENE, props, node_name, xf)
				rock.set("model_path", o["path"])
			"bush":
				var bush := _instance(o["path"], props, node_name, xf)
				bush.set_script(load(BUSH_SCRIPT))
			"wall":
				var body := _static_body(props, node_name, xf)
				_instance(o["path"], body, "Model", Transform3D())
				_box_collision(body, WALL_SIZE, WALL_CENTRE)
			"building":
				var body := _static_body(props, node_name, xf)
				var model := _instance(o["path"], body, "Model", Transform3D())
				var aabb := _model_aabb(model)
				_box_collision(body, aabb.size, aabb.get_center())
			"collectible":
				var part := _instance(COLLECTIBLE_SCENE, collectibles, node_name, xf)
				var info: Dictionary = COLLECTIBLES.get(o["code"], {"name": o["code"], "color": Color.WHITE})
				part.set("part_name", info["name"])
				part.set("color", info["color"])
			_:
				_instance(o["path"], props, node_name, xf)
	_build_background(data["background"])

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + "generated_level.tscn")
	print("baked generated_level.tscn: ", counts, " background ", data["background"].size(), " -> ", error_string(err))
	_root.free()
	quit(0 if err == OK else 1)

func _group(group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	_root.add_child(n)
	n.owner = _root
	return n

func _transform(o: Dictionary) -> Transform3D:
	var b: Array = o["basis"]
	var basis := Basis(Vector3(b[0], b[3], b[6]), Vector3(b[1], b[4], b[7]), Vector3(b[2], b[5], b[8]))
	return Transform3D(basis, Vector3(o["origin"][0], o["origin"][1], o["origin"][2]))

func _instance(path: String, parent: Node, node_name: String, xf: Transform3D) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var n: Node3D = _scenes[path].instantiate()
	n.name = node_name
	n.transform = xf
	parent.add_child(n)
	n.owner = _root
	return n

func _static_body(parent: Node, node_name: String, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = xf
	parent.add_child(body)
	body.owner = _root
	return body

func _box_collision(body: StaticBody3D, size: Vector3, centre: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	col.position = centre
	body.add_child(col)
	col.owner = _root

func _model_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var local: Transform3D = model.transform.affine_inverse() * (mi as MeshInstance3D).transform
		var box: AABB = local * (mi as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _build_terrain(t: Dictionary) -> void:
	var nx: int = t["nx"]
	var nz: int = t["nz"]
	var x0: float = t["x0"]
	var z0: float = t["z0"]
	var h := PackedFloat32Array(t["heights"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var y: float = h[iz * nx + ix]
			var dx: float = h[iz * nx + mini(ix + 1, nx - 1)] - h[iz * nx + maxi(ix - 1, 0)]
			var dz: float = h[mini(iz + 1, nz - 1) * nx + ix] - h[maxi(iz - 1, 0) * nx + ix]
			var slope: float = clampf(Vector2(dx, dz).length() * 0.5, 0.0, 1.0)
			# Subtle shading: higher ground a touch lighter, slopes a touch darker.
			var k: float = 0.9 + clampf(y, -1.0, 6.0) * 0.025 - slope * 0.15
			st.set_color(Color(GROUND_COLOR.r * k, GROUND_COLOR.g * k, GROUND_COLOR.b * k))
			st.set_uv(Vector2(x0 + ix, z0 + iz) * 0.25)
			st.add_vertex(Vector3(x0 + ix, y, z0 + iz))
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx)
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	st.set_material(material)
	var mesh: Mesh = _save_external(st.commit(), OUT_DIR + "terrain_mesh.res")

	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = h
	shape = _save_external(shape, OUT_DIR + "terrain_shape.res")

	var body := StaticBody3D.new()
	body.name = "Terrain"
	_root.add_child(body)
	body.owner = _root
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)
	mi.owner = _root
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	col.position = Vector3(x0 + (nx - 1) * 0.5, 0, z0 + (nz - 1) * 0.5)
	body.add_child(col)
	col.owner = _root

# Saves to its own file and returns the copy loaded back from disk, so the scene
# references the file instead of embedding the data.
func _save_external(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])
		return res
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)

func _build_background(items: Array) -> void:
	var group := _group("BackgroundForest")
	var meshes := {}     # asset path -> [mesh, local transform of the mesh inside the model]
	var chunks := {}     # "cx,cz,path" -> Array[Transform3D]
	for o in items:
		var path: String = o["path"]
		if not meshes.has(path):
			var model: Node3D = load(path).instantiate()
			var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
			var file := OUT_DIR + "background/%s.res" % path.get_file().get_basename()
			var mesh: Mesh = _save_external(mi.mesh.duplicate(), file)
			meshes[path] = [mesh, model.transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else mi.transform]
			model.free()
		var xf := _transform(o)
		var key := "%d,%d,%s" % [floori(xf.origin.x / BACKGROUND_CHUNK), floori(xf.origin.z / BACKGROUND_CHUNK), path]
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(xf * meshes[path][1])
	for key in chunks:
		var path: String = key.get_slice(",", 2)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[path][0]
		mm.instance_count = chunks[key].size()
		for i in chunks[key].size():
			mm.set_instance_transform(i, chunks[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Chunk_%s_%s_%s" % [key.get_slice(",", 0), key.get_slice(",", 1), path.get_file().get_basename()]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mmi)
		mmi.owner = _root
