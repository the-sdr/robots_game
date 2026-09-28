extends Node3D

# A small robin for the opening cutscene. Faces -Z. `flapping` beats the wings;
# otherwise they fold. look_around() turns the head; the cutscene moves the bird.

@onready var wing_left: Node3D = $WingLeft
@onready var wing_right: Node3D = $WingRight
@onready var head: Node3D = $Head

var flapping := false
var _time := 0.0
var _fold := 0.1

func _process(delta: float) -> void:
	_time += delta
	var angle: float = sin(_time * 30.0) * 1.0 if flapping else lerpf(wing_left.rotation.z, _fold, minf(delta * 10.0, 1.0))
	wing_left.rotation.z = angle
	wing_right.rotation.z = -angle

## A little head turn, the way birds check around before they go.
func look_around() -> Tween:
	var t := create_tween()
	t.tween_property(head, "rotation:y", 0.7, 0.18)
	t.tween_interval(0.35)
	t.tween_property(head, "rotation:y", -0.6, 0.2)
	t.tween_interval(0.3)
	t.tween_property(head, "rotation:y", 0.0, 0.15)
	return t
