extends SceneTree

# Headless physics test of the built level (run tools/forest_routes.py first):
#   <godot> --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd
# (--fixed-fps drops the wall-clock pacing: ~10 s instead of ~7 min.)
# 1. Drives the real robot body from the house door along every route in
#    level_design/build/routes.json (the design's own path curves) at
#    player speed, on the real terrain and collision. Reports any route that
#    gets stuck, and how many collectibles are left afterwards (should be 0).
# 2. Checks no individual tree reaches into the house (vertex-exact).
# 3. Drives hill crest -> city -> back up, so nobody can get trapped below.
# Headless = no window, no GPU; it proves logic and collision, never looks.

const SPEED := 3.0          # scripts/player.gd SPEED

var ROUTES := "res://level_design/build/routes.json"
var district := ""          # "" = the forest; "hub" = ++ hub: routes from hub_routes.json, gates instead of brambles
var start_pos := Vector3(0, 0.3, -8.6)
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

## Drives one route from the start; true if the last point was reached.
func drive_route(points: Array) -> bool:
	p.global_position = start_pos
	p.velocity = Vector3.ZERO
	await physics_frame
	var stuck := 0
	for q in points:
		if not await drive_to(Vector2(q[0], q[1]), 200):
			stuck += 1
			if stuck > 2:
				break
	var end := Vector2(p.global_position.x, p.global_position.z)
	var goal := Vector2(points[-1][0], points[-1][1])
	return stuck == 0 or end.distance_to(goal) < 2.5

func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		district = user_args[0]
		ROUTES = "res://level_design/build/%s_routes.json" % district
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await physics_frame
	p = world.get_node("Player")
	p.set_physics_process(false)
	var ok := true

	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTES))
	var failures := 0
	var props: Node = world.get_node("GeneratedLevel/Props") if district == "" else world.get_node("Generated%s/Props" % district.capitalize())
	if routes.has("_start"):
		var sp: Array = routes["_start"]["pos"]
		start_pos = Vector3(sp[0], 0.3, sp[1])
		routes.erase("_start")
	for name in routes:
		var points: Array = routes[name]["points"]
		var behind: Variant = routes[name]["behind"]
		# A place behind a blocker: the blocker must stop the robot first, then
		# clearing it (what the cutter does) must open the way.
		if behind != null:
			var reached_early := await drive_route(points)
			if reached_early:
				failures += 1
				print("  REACHED TOO EARLY  %-12s (blocker %s does not hold)" % [name, behind])
				continue
			var blocker: Node = props.get_node_or_null("Brambles_%s" % behind)
			if blocker == null:
				blocker = props.get_node_or_null("Gate_%s" % behind)
			if blocker == null or not (blocker.has_method("accepts") or blocker.has_method("unlock")):
				failures += 1
				print("  BLOCKER MISSING or not clearable: %s" % behind)
				continue
			if blocker.has_method("unlock"):
				root.get_node("Game").add_item(blocker.key_item)     # the key the design says opens it
				blocker.unlock()                                       # rises and frees itself
				for i in 90:
					await physics_frame
			else:
				blocker.queue_free()
				await physics_frame
				await physics_frame
		if not await drive_route(points):
			failures += 1
			var end := Vector2(p.global_position.x, p.global_position.z)
			print("  STUCK  %-12s end (%.1f, %.1f)%s" % [name, end.x, end.y, " after clearing %s" % behind if behind != null else ""])
	var left := props.get_parent().get_node("Collectibles").get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	print("routes: %d of %d reached | collectibles left: %d" % [routes.size() - failures, routes.size(), left])
	ok = ok and failures == 0 and left == 0
	if district != "":
		print("RESULT: %s" % ("OK" if ok else "PROBLEMS FOUND"))
		quit(0 if ok else 1)

	# No individual tree may reach inside a house: [centre x, z, then box x0, z0, x1, z1, below height].
	var houses := {"the house": [0.0, -5.0, -2.99, -8.04, 2.99, -2.01, 4.3],
		"the crooked house": [-25.0, 3.0, -27.1, -0.1, -22.9, 6.1, 3.1]}
	for house in houses:
		var hb: Array = houses[house]
		var bad := []
		for t in world.get_node("GeneratedLevel/Trees").get_children():
			if Vector2(t.position.x, t.position.z).distance_to(Vector2(hb[0], hb[1])) > 14:
				continue
			for mi in t.find_children("*", "MeshInstance3D", true, false):
				var xf: Transform3D = mi.global_transform
				for s in mi.mesh.get_surface_count():
					for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
						var w: Vector3 = xf * v
						if w.x > hb[2] and w.x < hb[4] and w.z > hb[3] and w.z < hb[5] and w.y < hb[6] and not bad.has(t.name):
							bad.append(t.name)
		print("trees reaching into %s: %s" % [house, bad])
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
