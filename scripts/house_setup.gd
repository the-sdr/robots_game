extends Node3D

const TEXTURE_PATH := "res://assets/quaternius_buildings/Textures/Texture_Light.png"

func _ready() -> void:
	var texture: Texture2D = load(TEXTURE_PATH)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(self, meshes)
	for mesh_instance in meshes:
		mesh_instance.create_multiple_convex_collisions()
		_fix_material(mesh_instance, texture)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_collect_meshes(child, out)

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
