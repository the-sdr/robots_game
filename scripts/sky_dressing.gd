extends Node3D

const CLOUD_CLUSTERS := 20
const PUFFS_PER_CLUSTER := 9
const CLOUD_HEIGHT := 55.0
const CLOUD_SPREAD := 180.0
const CLUSTER_RADIUS := 9.0
const TEXTURE_SIZE := 160
const SEED := 20260926

var _material: StandardMaterial3D

func _ready() -> void:
	_build_clouds()

func _make_cloud_texture(noise_seed: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55

	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEXTURE_SIZE * 0.5, TEXTURE_SIZE * 0.5)
	var max_dist := TEXTURE_SIZE * 0.5

	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var dist: float = Vector2(x, y).distance_to(center) / max_dist
			var falloff: float = clamp(1.0 - dist, 0.0, 1.0)
			falloff = falloff * falloff
			var n: float = (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var density: float = clamp((n * 0.8 + 0.45) * falloff, 0.0, 1.0)
			density = pow(density, 1.4)
			image.set_pixel(x, y, Color(1, 1, 1, density))

	return ImageTexture.create_from_image(image)

func _build_clouds() -> void:
	var material := StandardMaterial3D.new()
	_material = material
	material.albedo_texture = _make_cloud_texture(SEED)
	material.albedo_color = Color(1.0, 0.99, 0.96)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := QuadMesh.new()
	mesh.size = Vector2(16, 16)
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = CLOUD_CLUSTERS * PUFFS_PER_CLUSTER

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var index := 0
	for cluster in CLOUD_CLUSTERS:
		var cluster_x := rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		var cluster_z := rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		var cluster_y := CLOUD_HEIGHT + rng.randf_range(-8.0, 8.0)
		var cluster_stretch := rng.randf_range(1.0, 2.2)
		for puff in PUFFS_PER_CLUSTER:
			var offset := Vector3(
				rng.randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS) * cluster_stretch,
				rng.randf_range(-1.8, 1.8),
				rng.randf_range(-CLUSTER_RADIUS, CLUSTER_RADIUS)
			)
			var pos := Vector3(cluster_x, cluster_y, cluster_z) + offset
			var scale_factor := rng.randf_range(0.5, 1.4)
			var xform := Transform3D(Basis().scaled(Vector3.ONE * scale_factor), pos)
			multimesh.set_instance_transform(index, xform)
			index += 1

	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.multimesh = multimesh
	add_child(multimesh_instance)

## Day/night tint (the puffs are unshaded, so they would glow white at night).
func set_brightness(colour: Color) -> void:
	if _material != null:
		_material.albedo_color = colour
