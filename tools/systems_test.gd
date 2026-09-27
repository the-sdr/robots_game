extends SceneTree

# Headless test of the game systems (no window, no GPU):
#   <godot> --headless --fixed-fps 60 --path . -s tools/systems_test.gd
# Covers: catalog integrity, inventory + crafting, save/load round trip,
# the clock and sun, energy drain/depletion, docking at the house charger in
# the real world scene, and reboot after a shutdown.

var failures := 0
# A -s script is compiled before the autoload names exist, so fetch the nodes.
var Game: Node
var Clock: Node
var Energy: Node
var Catalog: Node

func check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)

func _initialize() -> void:
	Game = root.get_node("Game")
	Clock = root.get_node("Clock")
	Energy = root.get_node("Energy")
	Catalog = root.get_node("Catalog")
	await process_frame      # _initialize runs before the root joins the tree
	print("== catalog")
	for rid in Catalog.RECIPES:
		var r: Dictionary = Catalog.RECIPES[rid]
		for id in r["needs"]:
			check(Catalog.ITEMS.has(id), "recipe %s needs known item %s" % [rid, id])
		if r.has("tool"):
			check(Catalog.TOOLS.has(r["tool"]), "recipe %s builds known tool %s" % [rid, r["tool"]])
		for id in r.get("gives", {}):
			check(Catalog.ITEMS.has(id), "recipe %s gives known item %s" % [rid, id])
	for tid in Catalog.TOOLS:
		var t: Dictionary = Catalog.TOOLS[tid]
		for field in ["name", "effect", "power", "energy", "range", "cooldown"]:
			check(t.has(field), "tool %s has %s" % [tid, field])

	print("== inventory and crafting")
	Game.delete_save()
	Game.new_game()
	check(Game.craft_blocker("smasher") == "Missing parts", "smasher blocked without parts")
	Game.add_item("hammer_head")
	Game.add_item("actuator_arm")
	check(Game.craft("smasher"), "smasher crafted")
	check(Game.has_tool("smasher") and Game.data["equipped_tool"] == "smasher", "smasher attached and equipped")
	check(Game.count("hammer_head") == 0, "parts consumed")
	check(Game.craft_blocker("smasher") == "Already built", "no second smasher")
	Game.add_item("scrap_metal", 2)
	check(Game.craft("blade_strip") and Game.count("blade_strip") == 1, "blade strip from scrap")
	for id in ["servo_motor", "gear_train", "power_cell"]:
		Game.add_item(id)
	check(Game.craft("cutter") and Game.has_tool("cutter"), "cutter crafted from forest parts")

	print("== clock and sun")
	Clock.time = 0.5
	check(Clock.sun_elevation() > 1.0 and Clock.sunlight() > 0.85, "noon sun high, panel near full")
	check(absf(Clock.sun_direction().z - sin(Clock.sun_elevation()) * 0.0) < 1.0 and Clock.sun_direction().y > 0.8, "noon sun points up")
	Clock.time = 0.0
	check(Clock.sun_elevation() < 0.0 and Clock.sunlight() == 0.0, "midnight dark, no solar")
	Clock.time = 0.26
	check(Clock.sun_direction().x > 0.9, "dawn sun in the east (+X)")
	Clock.time = 0.74
	check(Clock.sun_direction().x < -0.9, "dusk sun in the west (-X)")
	Clock.time = 0.99
	Clock.day = 1
	Clock.advance(0.02)
	check(Clock.day == 2 and Clock.time < 0.02, "midnight rolls the day")
	Clock.time = 0.6
	Clock.skip_to_morning()
	check(Clock.day == 3 and absf(Clock.time - 0.30) < 0.001, "skip to next morning")

	print("== energy")
	Energy.reset()
	var got_depleted := [false]
	Energy.depleted.connect(func() -> void: got_depleted[0] = true)
	check(Energy.spend(10.0) and absf(Energy.current - 90.0) < 0.001, "spend 10")
	check(not Energy.spend(500.0), "cannot overspend")
	Energy.drain(1000.0)
	check(Energy.current == 0.0 and got_depleted[0], "drain to zero emits depleted")
	check(Energy.add(25.0) == 25.0 and Energy.current == 25.0, "add returns what fit")

	print("== world: new game, dock, save, load")
	Game.new_game()
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await physics_frame
	var player: CharacterBody3D = world.get_node("Player")
	var charger: Node = world.get_node("HouseCharger")
	check(player.global_position.distance_to(charger.global_position) < 2.5, "new game spawns beside the house charger (%.1f m)" % player.global_position.distance_to(charger.global_position))
	check(player.global_position.x > -2.6 and player.global_position.z > -7.7 and player.global_position.z < -2.4, "spawn inside the house walls")
	var west_edge: float = charger.global_position.x - 0.85
	check(west_edge > -2.59, "charger pad clear of the west wall (edge %.2f)" % west_edge)
	for i in 30:
		await physics_frame
	check(player.get("_focus") != null and player.get("_focus").prompt.begins_with("Dock"), "charger prompt found by the probe")
	Energy.current = 40.0
	charger.stored = 50.0
	player.get("_focus").interact(player)
	check(charger.docked_player == player and player.docked, "docked")
	check(Game.has_save(), "docking wrote the autosave")
	for i in 120:
		await physics_frame
	check(Energy.current > 40.0 and charger.stored < 50.0, "energy flows from charger to robot (%.1f, charger %.1f)" % [Energy.current, charger.stored])
	charger.undock()
	check(not player.docked, "undocked")
	Game.add_item("optic_lens", 2)
	Game.set_flag("door_broken")
	Game.save(player, "HouseCharger")
	var saved_pos := player.global_position
	var saved_energy: float = Energy.current
	Game.new_game()
	check(Game.count("optic_lens") == 0, "new game clears inventory")
	check(Game.load_save(), "save loads")
	check(Game.count("optic_lens") == 2 and Game.get_flag("door_broken"), "inventory and flags restored")
	check(absf(Energy.current - saved_energy) < 0.001, "energy restored")
	player.global_position = Vector3(50, 0, 50)
	Game.pending_load = true
	Game.apply_to_world(player)
	check(player.global_position.distance_to(saved_pos) < 0.01, "player position restored")
	check(charger.stored < 50.0, "charger level restored")

	print("== day and night")
	var day_night: Node = world.get_node("DayNight")
	var sun: DirectionalLight3D = world.get_node("DirectionalLight3D")
	Clock.time = 0.5
	day_night.update()
	check(sun.light_energy > 1.0 and sun.light_color.b > 0.7, "noon: bright white sun (energy %.2f)" % sun.light_energy)
	check(charger.sun_factor() > 0.95, "tilted panel faces the noon sun (%.2f)" % charger.sun_factor())
	check(-sun.global_transform.basis.z.y < -0.8, "sun light shines down at noon")
	Clock.time = 0.27
	day_night.update()
	check(sun.light_color.b < 0.6 and sun.light_energy > 0.0, "dawn: warm low sun")
	Clock.time = 0.0
	day_night.update()
	check(sun.light_energy < 0.3 and sun.light_color.b > sun.light_color.r, "midnight: dim blue moon (energy %.2f)" % sun.light_energy)
	check(charger.sun_factor() == 0.0, "no solar at midnight")
	var env: Environment = world.get_node("WorldEnvironment").environment
	check(env.ambient_light_color.r < 0.15, "night ambient is dark")
	for i in 3:
		await process_frame
	check(player.headlight.light_energy > 2.0, "headlights on at night")
	Clock.time = 0.5
	for i in 3:
		await process_frame
	check(player.headlight.light_energy < 0.1, "headlights off at noon")

	print("== shutdown and reboot")
	Clock.time = 0.6
	var day_before: int = Clock.day
	Energy.drain(1000.0)
	for i in 4 * 60:
		await physics_frame
	check(Clock.day == day_before + 1 and absf(Clock.time - 0.30) < 0.01, "rebooted next morning")
	check(Energy.current > 0.0 and not player.shut_down, "rebooted with emergency energy (%.0f)" % Energy.current)
	check(player.global_position.distance_to(charger.global_position) < 2.5, "rebooted beside the last charger")
	check(Game.count("optic_lens") == 2, "inventory kept through the shutdown")

	world.free()
	Game.delete_save()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "PROBLEMS FOUND", failures])
	quit(0 if failures == 0 else 1)
