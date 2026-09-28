extends StaticBody3D

# A mirror on a pedestal in the Relay Vault's hall. It stands at 45 degrees:
# "/" turns a beam E<->N and W<->S, "\" turns it E<->S and W<->N (seen from
# above, north up). E flips it. The vault (relay_vault.gd) traces the beam.

signal flipped(state: String)

var state := "/"
var decoy := false

var _plate: Node3D
var _tween: Tween
var _interactable: Interactable

func setup(start: String, is_decoy: bool) -> void:
	state = start
	decoy = is_decoy
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.31, 0.34)
	metal.metallic = 0.7
	metal.roughness = 0.4
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.28
	cyl.height = 0.7
	pedestal.mesh = cyl
	pedestal.material_override = metal
	pedestal.position.y = 0.35
	add_child(pedestal)
	_plate = Node3D.new()
	_plate.position.y = 1.2
	add_child(_plate)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.9, 0.95)
	glass.metallic = 1.0
	glass.roughness = 0.05
	var face := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.9, 0.05)
	face.mesh = box
	face.material_override = glass
	_plate.add_child(face)
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(1.06, 0.96, 0.03)
	back.mesh = back_box
	back.material_override = metal
	back.position.z = 0.04
	_plate.add_child(back)
	_plate.rotation.y = _yaw(state)
	var shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(0.6, 1.7, 0.6)
	shape.shape = body_box
	shape.position.y = 0.85
	add_child(shape)
	_interactable = Interactable.new()
	_interactable.prompt = "Turn the mirror"
	var area_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.4
	area_shape.shape = sphere
	_interactable.add_child(area_shape)
	_interactable.position.y = 0.8
	add_child(_interactable)
	_interactable.interacted.connect(func(_p: Node3D) -> void: flip())

## "/" runs from south-west to north-east: its face points north-west (yaw 45 deg).
func _yaw(s: String) -> float:
	return deg_to_rad(45.0) if s == "/" else deg_to_rad(-45.0)

func flip() -> void:
	state = "\\" if state == "/" else "/"
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_plate, "rotation:y", _yaw(state), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flipped.emit(state)

## Where a beam travelling `dir` (x east, y = z south) goes after this mirror.
static func reflect(s: String, dir: Vector2i) -> Vector2i:
	if s == "/":
		return Vector2i(-dir.y, -dir.x)       # E(1,0)->N(0,-1), N->E, W->S, S->W
	return Vector2i(dir.y, dir.x)             # E->S, S->E, W->N, N->W
