extends Control

# The HUD's little sky gauge: a sun whose rays grow with the sunlight a solar
# panel gets right now (Clock.sunlight), or a pale moon at night.

## 0..1: how strong the sun is.
var level := 0.0
var night := false

func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.26
	if night:
		draw_circle(c, r * 1.1, Color(0.85, 0.88, 1.0))
		draw_circle(c + Vector2(r * 0.55, -r * 0.35), r * 0.95, Color(0.06, 0.07, 0.1))
		return
	var sun := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.95, 0.6), level)
	draw_circle(c, r, sun)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 1.35, c + d * r * (1.4 + 0.9 * level), sun, 2.0, true)
