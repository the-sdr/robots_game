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
const TERRAIN_SHADER := "res://shaders/terrain_painterly.gdshader"
# Hand-tunable (painterly sliders); created once, then reused so edits survive rebuilds.
const TERRAIN_MATERIAL := "res://materials/terrain_painterly.tres"
const GROUND_TEXTURES := "res://assets/textures/ground/"
const GROUND_LAYERS := {"forest": "forest_ground_06", "dirt": "dirt_floor",
	"mud": "brown_mud_leaves_01", "moss": "rocky_mossy_terrain_02"}
const WALL_SIZE := Vector3(2.0, 3.12, 0.41)
const WALL_CENTRE := Vector3(0, 1.56, -0.11)
const BACKGROUND_CHUNK := 32.0
# Batched (MultiMesh) versions of the tinted leaf materials, by the pack's material name.
const BATCHED_LEAF_MATERIALS := {
	"Leaves_NormalTree": "res://materials/leaves_normal_batched.tres",
	"Leaves_TwistedTree": "res://materials/leaves_twisted_batched.tres",
	"Leaves_Pine": "res://materials/leaves_pine_batched.tres",
}
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
				tree.set("leaf_tint", Color(o["tint"][0], o["tint"][1], o["tint"][2]))
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
	var layers := PackedFloat32Array(t["layers"])
	for iz in nz:
		for ix in nx:
			var y: float = h[iz * nx + ix]
			var i := (iz * nx + ix) * 3
			# Ground-layer weights for the terrain shader: R dirt, G mud, B moss.
			st.set_color(Color(layers[i], layers[i + 1], layers[i + 2], 1.0))
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
	var material: ShaderMaterial
	if ResourceLoader.exists(TERRAIN_MATERIAL):
		material = load(TERRAIN_MATERIAL)
	else:
		material = ShaderMaterial.new()
		material.shader = load(TERRAIN_SHADER)
		for layer in GROUND_LAYERS:
			material.set_shader_parameter(layer + "_albedo", load(GROUND_TEXTURES + GROUND_LAYERS[layer] + "_albedo_height.png"))
			material.set_shader_parameter(layer + "_normal", load(GROUND_TEXTURES + GROUND_LAYERS[layer] + "_normal.png"))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TERRAIN_MATERIAL.get_base_dir()))
		material = _save_external(material, TERRAIN_MATERIAL)
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

# Background trees are merged into one ordinary mesh per chunk (one surface
# per material). MultiMesh can't be used here: in a headless bake Godot's
# stand-in renderer keeps no MultiMesh data, so the saved batches were empty.
# Merged meshes use a simpler detail level of each model (BACKGROUND_LOD) and
# carry each tree's leaf tint in the vertex colour.
const BACKGROUND_LOD := 2      # 0 = full detail; each level roughly halves the triangles

func _build_background(items: Array) -> void:
	var group := _group("BackgroundForest")
	var models := {}    # asset path -> Array of {material, positions, normals, uvs, indices, leaf}
	var chunks := {}    # "cx,cz" -> Array of [Transform3D, Color, path]
	for o in items:
		var path: String = o["path"]
		if not models.has(path):
			models[path] = _model_surfaces(path, BACKGROUND_LOD)
		var xf := _transform(o)
		var key := "%d,%d" % [floori(xf.origin.x / BACKGROUND_CHUNK), floori(xf.origin.z / BACKGROUND_CHUNK)]
		if not chunks.has(key):
			chunks[key] = []
		var tint: Array = o.get("tint", [1.0, 1.0, 1.0])
		chunks[key].append([xf, Color(tint[0], tint[1], tint[2]), path])
	var triangles := 0
	for key in chunks:
		var by_material := {}   # material -> [positions, normals, uvs, colors, indices]
		for entry in chunks[key]:
			var xf: Transform3D = entry[0]
			var normal_basis: Basis = xf.basis.inverse().transposed()
			for surf in models[entry[2]]:
				var mat: Material = surf["material"]
				if not by_material.has(mat):
					by_material[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
				var acc: Array = by_material[mat]
				var base: int = acc[0].size()
				var colour: Color = entry[1] if surf["leaf"] else Color.WHITE
				var positions: PackedVector3Array = surf["positions"]
				var normals: PackedVector3Array = surf["normals"]
				for i in positions.size():
					acc[0].append(xf * positions[i])
					acc[1].append((normal_basis * normals[i]).normalized())
					acc[3].append(colour)
				acc[2].append_array(surf["uvs"])
				for index in surf["indices"]:
					acc[4].append(base + index)
		var mesh := ArrayMesh.new()
		for mat in by_material:
			var acc: Array = by_material[mat]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = acc[0]
			arrays[Mesh.ARRAY_NORMAL] = acc[1]
			arrays[Mesh.ARRAY_TEX_UV] = acc[2]
			arrays[Mesh.ARRAY_COLOR] = acc[3]
			arrays[Mesh.ARRAY_INDEX] = acc[4]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			triangles += acc[4].size() / 3
		var file := OUT_DIR + "background/chunk_%s.res" % key.replace(",", "_")
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%s" % key.replace(",", "_")
		mi.mesh = _save_external(mesh, file)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mi)
		mi.owner = _root
	print("background: %d chunks, %d triangles" % [chunks.size(), triangles])

# One model's surfaces at a given detail level, compacted to the vertices that
# level uses, in model space. Leaf surfaces get the batched tinted material.
func _model_surfaces(path: String, lod: int) -> Array:
	var model: Node3D = load(path).instantiate()
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var local: Transform3D = mi.transform
	var parent := mi.get_parent()
	while parent != model and parent is Node3D:
		local = (parent as Node3D).transform * local
		parent = parent.get_parent()
	var out := []
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var surf: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
		var lods: Array = surf.get("lods", [])
		if lod > 0 and lods.size() > 0:
			var data: PackedByteArray = lods[mini(lod, lods.size()) - 1]["index_data"]
			var wide: bool = arrays[Mesh.ARRAY_VERTEX].size() > 65535
			indices = PackedInt32Array()
			var step := 4 if wide else 2
			for i in range(0, data.size(), step):
				indices.append(data.decode_u32(i) if wide else data.decode_u16(i))
		var remap := {}
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var compact := PackedInt32Array()
		for index in indices:
			if not remap.has(index):
				remap[index] = positions.size()
				positions.append(local * arrays[Mesh.ARRAY_VERTEX][index])
				normals.append((local.basis * arrays[Mesh.ARRAY_NORMAL][index]).normalized())
				uvs.append(arrays[Mesh.ARRAY_TEX_UV][index])
			compact.append(remap[index])
		var mat: Material = mi.mesh.surface_get_material(s)
		var leaf := mat != null and BATCHED_LEAF_MATERIALS.has(mat.resource_name)
		if leaf:
			mat = load(BATCHED_LEAF_MATERIALS[mat.resource_name])
		out.append({"material": mat, "positions": positions, "normals": normals, "uvs": uvs, "indices": compact, "leaf": leaf})
	model.free()
	return out
