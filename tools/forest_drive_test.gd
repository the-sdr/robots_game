extends SceneTree

# Headless physics test of the built level (run tools/forest_routes.py first):
#   <godot> --headless --path . -s tools/forest_drive_test.gd
# 1. Drives the real robot body from the house door along every route in
#    level_design/build/routes.json (the design's own path curves) at
#    player speed, on the real terrain and collision. Reports any route that
#    gets stuck, and how many collectibles are left afterwards (should be 0).
# 2. Checks no individual tree reaches into the house (vertex-exact).
# 3. Drives hill crest -> city -> back up, so nobody can get trapped below.
# Headless = no window, no GPU; it proves logic and collision, never looks.

const ROUTES := "res://level_design/build/routes.json"
const SPEED := 3.0          # scripts/player.gd SPEED

var p: CharacterBody3D

func drive_to(target: Vector2, max_frames: int) -> bool:
	for i in max_frames:
		var d := Vector2(target.x - p.global_position.x, target.y - p.global_position.z)
		if d.length() < 0.6:
			return true
		var dir := d.normalized()
		var vy: float = p.velocity.y - 9.8 / 60.0 if not p.is_on_floor() else -0.5
		p.velocity = Vector3(dir.x * SPEED, vy, dir.y * SPEED)
		p.move_and_slide()
		await physics_frame
	return false

func _initialize() -> void:
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await physics_frame
	p = world.get_node("Player")
	p.set_physics_process(false)
	var ok := true

	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTES))
	var failures := 0
	for name in routes:
		p.global_position = Vector3(0, 0.3, -8.6)
		p.velocity = Vector3.ZERO
		await physics_frame
		var stuck := []
		for q in routes[name]:
			if not await drive_to(Vector2(q[0], q[1]), 200):
				stuck.append(Vector2(q[0], q[1]))
				if stuck.size() > 2:
					break
		var end := Vector2(p.global_position.x, p.global_position.z)
		var goal := Vector2(routes[name][-1][0], routes[name][-1][1])
		var reached := stuck.is_empty() or end.distance_to(goal) < 2.5
		if not reached:
			failures += 1
			print("  STUCK  %-12s end (%.1f, %.1f) near %s" % [name, end.x, end.y, stuck[0]])
	var left := world.get_node("GeneratedLevel/Collectibles").get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	print("routes: %d of %d reached | collectibles left: %d" % [routes.size() - failures, routes.size(), left])
	ok = ok and failures == 0 and left == 0

	var bad := []
	for t in world.get_node("GeneratedLevel/Trees").get_children():
		if Vector2(t.position.x, t.position.z).distance_to(Vector2(0, -5)) > 14:
			continue
		for mi in t.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = mi.global_transform
			for s in mi.mesh.get_surface_count():
				for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = xf * v
					if w.x > -2.99 and w.x < 2.99 and w.z > -8.04 and w.z < -2.01 and w.y < 4.3 and not bad.has(t.name):
						bad.append(t.name)
	print("trees reaching into the house: %s" % [bad])
	ok = ok and bad.is_empty()

	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 60, -84), Vector3(0, -60, -84))
	ray.exclude = [p.get_rid()]
	p.global_position = p.get_world_3d().direct_space_state.intersect_ray(ray).position + Vector3(0, 0.3, 0)
	await physics_frame
	var down := await drive_to(Vector2(0, -97), 600)
	var up := await drive_to(Vector2(0, -84), 600)
	print("hill -> city: %s | city -> back up the hill: %s" % ["ok" if down else "STUCK", "ok" if up else "STUCK"])
	ok = ok and down and up

	print("RESULT: %s" % ("OK" if ok else "PROBLEMS FOUND"))
	quit(0 if ok else 1)
