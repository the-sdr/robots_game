extends Node3D

const TREE_MODELS := [
	"res://assets/quaternius_nature/CommonTree_1.gltf",
	"res://assets/quaternius_nature/TwistedTree_2.gltf",
	"res://assets/quaternius_nature/CommonTree_3.gltf",
	"res://assets/quaternius_nature/DeadTree_1.gltf",
	"res://assets/quaternius_nature/TwistedTree_4.gltf",
	"res://assets/quaternius_nature/CommonTree_5.gltf",
]

const SOLID_TREE_SCENE := preload("res://scenes/props/solid_tree.tscn")

const TREE_SPACING := 1.9
const CORRIDOR_WIDTH := 3.0
const MIN_TREE_GAP := 1.3

# Hand-designed winding path through the thicket: the single way through.
const PATH := [
	Vector3(0, 0, -8),
	Vector3(0, 0, -11),
	Vector3(3.5, 0, -13),
	Vector3(3.5, 0, -16),
	Vector3(-2.5, 0, -18),
	Vector3(-2.5, 0, -21),
	Vector3(0, 0, -23),
]

const FILL_X_MIN := -7.0
const FILL_X_MAX := 7.0
const FILL_Z_MIN := -22.3
const FILL_Z_MAX := -8.5
const FILL_STEP := 2.0

var _tree_index := 0
var _placed_positions: Array[Vector2] = []

func _ready() -> void:
	for i in PATH.size() - 1:
		_line_of_trees(PATH[i], PATH[i + 1])
	_fill_perimeter()

func _line_of_trees(start: Vector3, end: Vector3) -> void:
	var diff: Vector3 = end - start
	var length: float = diff.length()
	var dir: Vector3 = diff.normalized()
	var perp := Vector3(-dir.z, 0, dir.x)
	var count: int = max(1, int(round(length / TREE_SPACING)))

	for side in [1.0, -1.0]:
		var offset: Vector3 = perp * (CORRIDOR_WIDTH * 0.5) * side
		for i in count + 1:
			var t: float = float(i) / float(count)
			var pos: Vector3 = start.lerp(end, t) + offset
			_place_tree(pos)

func _fill_perimeter() -> void:
	var x := FILL_X_MIN
	while x <= FILL_X_MAX:
		var z := FILL_Z_MIN
		while z <= FILL_Z_MAX:
			if _far_from_path(Vector3(x, 0, z), 2.0):
				_place_tree(Vector3(x, 0, z))
			z += FILL_STEP
		x += FILL_STEP

func _far_from_path(pos: Vector3, min_dist: float) -> bool:
	for i in PATH.size() - 1:
		var closest: Vector3 = _closest_point_on_segment(pos, PATH[i], PATH[i + 1])
		if pos.distance_to(closest) < min_dist:
			return false
	return true

func _closest_point_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return a + ab * t

func _place_tree(pos: Vector3) -> void:
	for existing in _placed_positions:
		if existing.distance_to(Vector2(pos.x, pos.z)) < MIN_TREE_GAP:
			return
	_placed_positions.append(Vector2(pos.x, pos.z))

	var model_path: String = TREE_MODELS[_tree_index % TREE_MODELS.size()]
	_tree_index += 1

	var instance := SOLID_TREE_SCENE.instantiate()
	add_child(instance)
	instance.position = pos
	instance.model_path = model_path
