extends SceneTree

# Headless physics test of the built level (run tools/forest_routes.py first):
#   <godot> --headless --fixed-fps 60 --path . -s tools/forest_drive_test.gd
# (--fixed-fps drops the wall-clock pacing: ~10 s instead of ~7 min.)
# Add `++ serious` (or `++ hub serious`) to drive the Serious mode's world
# (the old robot in the crooked house instead of the Angry Zombie).
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
	var game: Node = root.get_node("Game")
	game.save_prefix = "test_"                 # docking on a route autosaves: never over the player's own save
	for arg in OS.get_cmdline_user_args():     # ++ [district] [silly|serious]
		if game.MODES.has(arg):
			game.set_mode(arg)                 # not Settings.set_mode: that writes the player's settings
		else:
			district = arg
			ROUTES = "res://level_design/build/%s_routes.json" % district
	print("mode: %s" % game.mode)
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await physics_frame
	p = world.get_node("Player")
	p.set_physics_process(false)
	load("res://scripts/ui/tool_card.gd").suppressed = true      # a card would pause the physics mid-route
	root.get_node("Game").set_flag("defeated:hill_sentry")     # routes over the crest must not start the tutorial fight
	var ok := true

	if not FileAccess.file_exists(ROUTES):      # a script error here used to hang the run
		print("RESULT: no %s - run tools/forest_routes.py first (it's a build output, not in git)" % ROUTES)
		quit(2)
		return
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTES))
	var failures := 0
	var props: Node = world.get_node("GeneratedLevel/Props") if district == "" else world.get_node("Generated%s/Props" % district.capitalize())
	if routes.has("_start"):
		var sp: Array = routes["_start"]["pos"]
		start_pos = Vector3(sp[0], 0.3, sp[1])
		routes.erase("_start")
	var cleared := {}          # blockers an earlier route already cleared (several places can sit behind one)
	var finds: Node = props.get_parent().get_node_or_null("Finds")
	for name in routes:
		var points: Array = routes[name]["points"]
		var behind: Variant = routes[name]["behind"]
		# A place behind a blocker: the blocker must stop the robot first, then
		# clearing it (what the cutter does) must open the way.
		if behind != null and not cleared.has(behind):
			cleared[behind] = true
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
			continue
		# a dead end whose part is inside something: it must be right there, and smash open
		var cache: Node = finds.get_node_or_null("Find_%s" % name) if finds != null else null
		if cache != null and cache.has_method("accepts") and cache.get("model") != null:
			var near: float = Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(cache.global_position.x, cache.global_position.z))
			var hits := 0
			while is_instance_valid(cache) and not cache.is_queued_for_deletion() and hits < 10:
				cache.apply("smash", 34.0, p.global_position)
				hits += 1
			if near > 2.6 or hits >= 10:
				failures += 1
				print("  CACHE  %-12s %.1f m from the robot, %d smashes" % [name, near, hits])
			await physics_frame
	var left := props.get_parent().get_node("Collectibles").get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	var caches_left := 0
	if finds != null:
		for f in finds.get_children():
			if f.get("model") != null and routes.has(String(f.name).trim_prefix("Find_")) and not f.is_queued_for_deletion():
				caches_left += 1
	left += caches_left
	print("routes: %d of %d reached | collectibles left: %d (%d in caches)" % [routes.size() - failures, routes.size(), left, caches_left])
	ok = ok and failures == 0 and left == 0
	if district != "":
		print("RESULT: %s" % ("OK" if ok else "PROBLEMS FOUND"))
		quit(0 if ok else 1)
		return

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

	# Escape probes (2026-09-30: the robot walked out of the forest at the Spring
	# and the Pocket). From every dead end near the forest's west, east or south
	# edge, drive straight at the edge and along two diagonals: it must stay in.
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://level_design/forest_design.json"))
	var fb: Dictionary = design["forest_bounds"]
	var outward := {"west": Vector2(-1, 0), "east": Vector2(1, 0), "south": Vector2(0, 1)}
	var escaped := []
	var probes := 0
	for n in design["nodes"]:
		var node: Dictionary = design["nodes"][n]
		if node["kind"] != "dead_end":
			continue
		var at := Vector2(node["pos"][0], node["pos"][1])
		var gaps := {"west": at.x - float(fb["x_min"]), "east": float(fb["x_max"]) - at.x, "south": float(fb["z_max"]) - at.y}
		for side in gaps:
			if gaps[side] > 8.0:
				continue
			for angle in [-0.6, 0.0, 0.6]:
				probes += 1
				p.global_position = Vector3(at.x, 12.0, at.y)
				p.velocity = Vector3.ZERO
				for i in 90:                                   # drop onto the ground
					var vy: float = p.velocity.y - 9.8 / 60.0 if not p.is_on_floor() else 0.0
					p.velocity = Vector3(0, vy, 0)
					p.move_and_slide()
					await physics_frame
				var target: Vector2 = at + (outward[side] as Vector2).rotated(angle) * 16.0
				await drive_to(target, 60 * 7)
				var end := Vector2(p.global_position.x, p.global_position.z)
				# the forest runs FOREST_BORDER (5 m) past the line: getting 3 m out means it got through
				if end.x < float(fb["x_min"]) - 3.0 or end.x > float(fb["x_max"]) + 3.0 or end.y > float(fb["z_max"]) + 3.0:
					escaped.append("%s -> %s (%.1f, %.1f)" % [n, side, end.x, end.y])
	print("escape probes: %d drives out of dead ends near the edge, escaped: %s" % [probes, escaped])
	ok = ok and escaped.is_empty()

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
