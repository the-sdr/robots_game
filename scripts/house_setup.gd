extends Node3D

const TEXTURE_PATH := "res://assets/quaternius_buildings/Textures/Texture_Light.png"

## The 1Story model has its own door slab in the north doorway, just inside
## the smashable HouseDoor (z -7.74). It never moves or breaks, so smashing
## looked like nothing happened. Triangles lying wholly inside this world box
## (the slab: x +-0.55, up to 2.27 m, z -7.36..-7.47, plus its grey room-side
## face, x +-0.62 at z -7.39) are cut out on load; the frame (from x +-0.69),
## wall and floor extend beyond it and stay.
const BUILT_IN_DOOR := AABB(Vector3(-0.66, -0.1, -7.62), Vector3(1.32, 2.4, 0.42))

## How many triangles the door cut removed (checked by tools/systems_test.gd).
var door_triangles_removed := 0

func _ready() -> void:
	var texture: Texture2D = load(TEXTURE_PATH)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	for mesh_instance in meshes:
		door_triangles_removed += _cut_out(mesh_instance, BUILT_IN_DOOR)
		_fix_material(mesh_instance, texture)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_collect_meshes(child, out)

## Rebuilds the mesh without the triangles whose three corners all lie inside
## `world_box`. Returns how many were removed.
func _cut_out(mesh_instance: MeshInstance3D, world_box: AABB) -> int:
	var source := mesh_instance.mesh
	if source == null:
		return 0
	var to_world := mesh_instance.global_transform
	var result := ArrayMesh.new()
	var removed := 0
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			var inside := true
			for k in 3:
				if not world_box.has_point(to_world * verts[indices[t + k]]):
					inside = false
					break
			if inside:
				removed += 1
			else:
				kept.append_array([indices[t], indices[t + 1], indices[t + 2]])
		arrays[Mesh.ARRAY_INDEX] = kept
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if removed > 0:
		mesh_instance.mesh = result
	return removed

func _fix_material(mesh_instance: MeshInstance3D, texture: Texture2D) -> void:
	if mesh_instance.mesh == null:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	for i in surface_count:
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh_instance.set_surface_override_material(i, material)
