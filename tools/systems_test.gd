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

func drive_to(p: CharacterBody3D, target: Vector2, max_frames: int) -> bool:
	for i in max_frames:
		var d := Vector2(target.x - p.global_position.x, target.y - p.global_position.z)
		if d.length() < 0.6:
			return true
		var dir := d.normalized()
		var vy: float = p.velocity.y - 9.8 / 60.0 if not p.is_on_floor() else -0.5
		p.velocity = Vector3(dir.x * 3.0, vy, dir.y * 3.0)
		p.move_and_slide()
		await physics_frame
	return false

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
	create_timer(240.0).timeout.connect(func() -> void: print("RESULT: WATCHDOG TIMEOUT (a check hung or a script error aborted the run)"); quit(2))
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

	print("== part models")
	var bad_models := []
	for id in Catalog.ITEMS:
		var path := "res://scenes/props/items/%s.res" % id
		var mesh: Mesh = load(path) if ResourceLoader.exists(path) else null
		var size: Vector3 = mesh.get_aabb().size if mesh != null else Vector3.ZERO
		if mesh == null or mesh.get_surface_count() == 0 or size.length() < 0.2 or maxf(size.x, maxf(size.y, size.z)) > 0.8:
			bad_models.append(id)
	check(bad_models.is_empty(), "every Catalog item has a real model, 0.2-0.8 m (missing or odd: %s)" % [bad_models])
	var pickup_test: Node3D = load("res://scenes/props/collectible_part.tscn").instantiate()
	pickup_test.set("item_id", "gear_train")
	root.add_child(pickup_test)
	var shown: MeshInstance3D = pickup_test.get_node_or_null("Visual/Model")
	check(shown != null and shown.mesh.resource_path.ends_with("gear_train.res") and pickup_test.get_node("Visual").get_child_count() == 1,
		"a pickup shows its item's model instead of the placeholder gear")
	pickup_test.free()

	print("== settings: difficulty")
	var settings: Node = root.get_node("Settings")
	var owner_level: String = settings.difficulty          # put back at the end of this section
	for level in settings.LEVELS:
		var t: Dictionary = settings.DIFFICULTY[level]
		for field in ["name", "ring_speed", "good_window", "perfect_window", "miss_factor", "defend_window", "now_cue", "enemy_damage", "enemy_health", "tutorial_knockout"]:
			check(t.has(field), "difficulty %s has %s" % [level, field])
	var easy: Dictionary = settings.DIFFICULTY["easy"]
	var medium: Dictionary = settings.DIFFICULTY["medium"]
	var hard: Dictionary = settings.DIFFICULTY["hard"]
	check(easy["good_window"] > medium["good_window"] and medium["good_window"] > hard["good_window"], "timing windows narrow from Easy to Hard")
	check(easy["defend_window"] >= 0.5 and easy["ring_speed"] <= 0.5 and easy["miss_factor"] == 1.0, "Easy: slow ring, half-second dodge window, a missed press still hits")
	check(not easy["tutorial_knockout"] and medium["tutorial_knockout"], "the tutorial fight can't be lost on Easy")
	settings.set_difficulty("easy")
	settings.next_difficulty()
	check(settings.difficulty == "medium", "Easy -> Medium")
	settings.next_difficulty()
	settings.next_difficulty()
	check(settings.difficulty == "easy", "Hard wraps back to Easy")
	settings.set_difficulty("hard")
	var stored := ConfigFile.new()
	check(stored.load(settings.PATH) == OK and stored.get_value("game", "difficulty") == "hard", "difficulty saved to settings.cfg")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var diff_button: Button = menu.get_node("%DifficultyButton")
	check(diff_button.text == "Difficulty: Hard", "main menu shows the difficulty (%s)" % diff_button.text)
	diff_button.pressed.emit()
	check(settings.difficulty == "easy" and diff_button.text == "Difficulty: Easy", "pressing it cycles to Easy")
	menu.free()
	settings.set_difficulty(owner_level)

	print("== fight rules (combat_state.gd)")
	var State: Script = load("res://scripts/combat/combat_state.gd")
	var fight = State.new()
	var sentry_def: Dictionary = Catalog.ENEMIES["hill_sentry"]
	var smash: Dictionary = Catalog.move("smasher", "")
	fight.start(sentry_def, easy, Catalog.PLAYER_HEALTH)
	check(fight.enemy_max == 42.0 and fight.quality(0.3) == "good" and fight.quality(-0.1) == "perfect" and fight.quality(0.5) == "miss", "Easy: sentry 42 HP, wide timing windows")
	check(fight.player_move(smash, ["miss"])["damage"] == 14, "Easy: a missed press still hits full")
	check(fight.enemy_move(["miss"])["damage"] == 5, "Easy: the clamp hurts half")
	fight.player_hp = 3.0
	fight.enemy_move(["miss", "miss"])
	check(fight.player_hp == 1.0 and fight.outcome == "", "Easy tutorial: the robot can't be knocked out")
	fight.start(sentry_def, medium, Catalog.PLAYER_HEALTH)
	check(fight.player_move(smash, ["perfect"])["damage"] == 21 and fight.player_move(smash, ["good"])["damage"] == 14 and fight.player_move(smash, ["miss"])["damage"] == 8, "Medium: perfect 21, good 14, miss 8")
	check(fight.enemy_move(["good"])["damage"] == 5 and fight.enemy_move(["perfect", "perfect"])["damage"] == 0, "blocking halves a blow, dodging takes none")
	fight.player_move(Catalog.move("smasher", "back"), [])
	var braced: Dictionary = fight.enemy_move(["good"])
	check(braced["damage"] == 2 and braced["countered"] == 8, "Brace: a third of a blocked clamp lands, and it bonks back (%s)" % [braced])
	fight.player_move(Catalog.move("laser", "back"), [])
	check(fight.next_attack().is_empty() and fight.enemy_move([])["skipped"], "Dazzle: the sentry loses its turn")
	fight.player_hp = 3.0
	fight.enemy_move(["miss", "miss"])
	check(fight.outcome == "lost", "Medium: the tutorial can be lost")
	for level in ["easy", "hard"]:
		fight.start(sentry_def, settings.DIFFICULTY[level], Catalog.PLAYER_HEALTH)
		var turns := 0
		while fight.outcome == "" and turns < 30:
			fight.player_move(smash, ["miss"])
			if fight.outcome == "":
				fight.enemy_move(["miss", "miss"])
			turns += 1
		check(fight.outcome == ("won" if level == "easy" else "lost"), "%s, pressing nothing at all: %s in %d turns" % [level, fight.outcome, turns])

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
	check(str(Game.loadout()) == str(["smasher", "cutter", ""]), "fight kit fills as tools are built (%s)" % [Game.loadout()])
	for id in ["optic_lens", "circuit_board", "antenna_coil"]:
		Game.add_item(id)
	check(Game.craft("laser") and Game.has_tool("laser"), "laser crafted from the forest's other three parts")
	check(str(Game.loadout()) == str(["smasher", "cutter", "laser"]), "three tools: a full fight kit")
	Game.cycle_loadout_slot(0)
	check(Game.loadout()[0] == "", "a kit slot can be emptied")
	Game.cycle_loadout_slot(0)
	check(Game.loadout()[0] == "smasher", "and filled again (no tool twice)")
	Game.data["loadout"] = []
	check(str(Game.loadout()) == str(["smasher", "cutter", "laser"]), "an old save without a kit gets the first three tools")

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

	print("== chargers: charge bar, upgrades, solar readout")
	var hud_c: CanvasLayer = world.get_node("HUD")
	charger.undock()
	check(Game.craft_blocker("battery_bank") == "Dock at a charger first", "charger upgrades need a dock")
	charger.stored = charger.effective_capacity() * 0.1
	check(str(charger.bar_state()) == str([0, 0]), "nearly empty: the first ring blinks (%s)" % [charger.bar_state()])
	charger.stored = charger.effective_capacity() * 0.5
	check(str(charger.bar_state()) == str([2, 2]), "half full: two rings lit, the third blinking (%s)" % [charger.bar_state()])
	charger.stored = charger.effective_capacity()
	for i in 2:
		await process_frame
	var top_ring: MeshInstance3D = charger.get_node("BarSegment4")
	check(str(charger.bar_state()) == str([5, -1]) and (top_ring.material_override as StandardMaterial3D).emission_energy_multiplier > 1.0, "full: all five rings glow")
	Energy.current = 50.0
	charger.dock(player)
	Game.add_item("capacitor")
	Game.add_item("solar_cell", 2)
	Game.add_item("sun_tracker")
	check(Game.craft_blocker("battery_bank") == "", "docked: the battery bank can be fitted")
	check(Game.craft("battery_bank") and charger.effective_capacity() == 180.0 and charger.has_node("Upgrade_battery"), "battery bank: holds 60 more, and shows on the charger")
	check(Game.craft_blocker("battery_bank") == "Already fitted", "only one per charger")
	Clock.time = 0.5
	var flat_rate: float = charger.fill_rate()
	check(Game.craft("panel_extension") and absf(charger.fill_rate() - flat_rate * 1.5) < 0.001 and charger.has_node("PanelMesh/Upgrade_panel"), "panel extension: fills half again as fast")
	Clock.time = 0.28
	var before_tracker: float = charger.sun_factor()
	check(Game.craft("fit_sun_tracker") and charger.sun_factor() > before_tracker + 0.3, "sun tracker: full light in the early morning (%.2f -> %.2f)" % [before_tracker, charger.sun_factor()])
	var fresh: Node = load("res://scenes/props/charging_station.tscn").instantiate()
	world.add_child(fresh)
	fresh.load_state(charger.save_state())
	check(fresh.effective_capacity() == 180.0 and fresh.has_upgrade("panel") and fresh.has_upgrade("tracker"), "upgrades are saved and loaded with the charger")
	fresh.free()
	Clock.time = 0.5
	for i in 3:
		await process_frame
	check(hud_c.solar_label.text.begins_with("Sun ") and hud_c.charger_label.text.begins_with("House charger") and hud_c.charger_label.text.ends_with("charging you"),
		"HUD: sunlight and the docked charger (%s | %s)" % [hud_c.solar_label.text, hud_c.charger_label.text])
	charger.undock()
	charger.stored = 20.0
	for i in 3:
		await process_frame
	check(hud_c.charger_label.text.contains("+"), "HUD: the charger's fill rate when not docked (%s)" % hud_c.charger_label.text)
	Clock.time = 0.0
	for i in 3:
		await process_frame
	check(hud_c.solar_label.text.begins_with("Night") and hud_c.charger_label.text.ends_with("not filling"), "HUD at night: no sun, not filling")
	Clock.time = 0.5

	print("== tools and breakables")
	Game.new_game()
	Game.add_tool("smasher")
	Game.add_tool("cutter")
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	var rig: Node3D = player.get_node("Visual/ArmRight/ToolRig")
	await process_frame
	check(rig.tool_id == "smasher" and rig.get_node_or_null("Head") != null, "smasher head built on the arm")
	var breakable_script: Script = load("res://scripts/interact/breakable.gd")
	var crate: StaticBody3D = breakable_script.new()
	crate.name = "TestCrate"
	crate.set("effects", PackedStringArray(["smash"]))
	crate.set("health", 60.0)
	crate.set("drops", {"scrap_metal": 2})
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	col.shape = box
	col.position.y = 0.4
	crate.add_child(col)
	world.add_child(crate)
	player.global_position = Vector3(0.0, 0.1, -5.0)
	crate.global_position = Vector3(0.0, 0.0, -6.3)        # 1.3 m north of the robot
	player.get_node("Visual").global_rotation.y = 0.0     # Visual -Z = north
	for i in 3:
		await physics_frame
	Energy.current = 50.0
	check(rig.use(), "smasher hits the crate")
	check(absf(crate.health - 26.0) < 0.01, "crate took 34 damage (%.0f left)" % crate.health)
	check(absf(Energy.current - 47.0) < 0.01, "smash cost 3 energy")
	check(not rig.use(), "second swing blocked by cooldown")
	for i in 40:
		await process_frame
	rig.cycle()
	check(rig.tool_id == "cutter", "Q cycles to the cutter")
	await process_frame
	check(not rig.use(), "cutter does nothing to a smash-only crate")
	check(absf(crate.health - 26.0) < 0.01, "crate unharmed by the wrong tool")
	for i in 30:
		await process_frame
	rig.cycle()
	await process_frame
	var crate_flag: String = crate.break_flag
	rig.use()
	await process_frame
	check(not is_instance_valid(crate) or crate.is_queued_for_deletion(), "crate broke")
	check(Game.count("scrap_metal") == 2, "crate dropped scrap")
	check(Game.get_flag(crate_flag), "break flag set")
	Energy.current = 1.0
	for i in 40:
		await process_frame
	check(not rig.use(), "no swing without energy")
	Energy.current = 50.0

	print("== the house: sealed door, parts, smasher, way out")
	Game.new_game()
	Game.data["tools"] = []
	Game.data["equipped_tool"] = ""
	Game.inventory_changed.emit()
	await process_frame
	player.set_physics_process(false)
	var door: StaticBody3D = world.get_node("HouseDoor")
	check(door != null and is_instance_valid(door), "door present on a new game")
	var cut: int = world.get_node("House").get("door_triangles_removed")
	check(cut > 100, "house model's own door slab cut out of the doorway (%d triangles)" % cut)
	player.global_position = Vector3(0.0, 0.1, -6.0)
	var blocked := await drive_to(player, Vector2(0.0, -9.5), 240)
	check(not blocked and player.global_position.z > -7.6, "door blocks the way out (z %.2f)" % player.global_position.z)
	for part in ["HammerHead", "ActuatorArm"]:
		var node: Node3D = world.get_node_or_null(part)
		if node == null:
			continue
		player.global_position = node.global_position + Vector3(0, 0.3, 0)
		for i in 4:
			await physics_frame
	check(Game.count("hammer_head") == 1 and Game.count("actuator_arm") == 1, "both smasher parts found in the house")
	check(Game.craft("smasher"), "smasher built from them (anywhere)")
	await process_frame
	player.global_position = Vector3(0.0, 0.1, -7.2)    # pressed against the door (owner's save_4)
	player.get_node("Visual").global_rotation.y = 0.0    # Visual -Z = north; the door wall is the north wall (z -7.74)
	for i in 3:
		await physics_frame
	var swings := 0
	while is_instance_valid(door) and not door.is_queued_for_deletion() and swings < 6:
		rig.use()
		swings += 1
		for i in 40:
			await process_frame
	check(swings == 3, "door breaks on the third smash (%d)" % swings)
	check(Game.get_flag("house_door_broken") and Game.beat_seen("door"), "door flag set and its story beat played")
	var out := await drive_to(player, Vector2(0.0, -9.5), 240)
	check(out, "the way out is open")
	player.set_physics_process(true)
	Game.save(player, "HouseCharger")

	print("== the crooked house: Angry Zombie, tiny curse, mouse hole")
	var crooked: Node3D = world.get_node_or_null("GeneratedLevel/Props/CrookedHouse")
	check(crooked != null, "the crooked house is in the forest")
	var zombie: Node = crooked.get_node("AngryZombie")
	check(zombie.global_position.distance_to(Vector3(-25.7, 0.0, 3.0)) < 0.3, "the Angry Zombie stands inside it (%s)" % zombie.global_position)
	var shell_origin: Vector3 = crooked.global_position
	var hole_front := shell_origin + (crooked.get_node("Shell/HoleFront") as Node3D).position
	var nook := shell_origin + (crooked.get_node("Shell/NookCentre") as Node3D).position
	var hud_node: CanvasLayer = world.get_node("HUD")
	Game.data["tiny_until"] = 0.0
	player.set_tiny(false, false)
	player.set_physics_process(false)
	player.global_position = hole_front + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	await physics_frame
	await drive_to(player, Vector2(nook.x, nook.z), 120)
	for i in 4:
		await physics_frame
	check(player.global_position.x > shell_origin.x - 0.89 + 0.3, "full size: the mouse hole is too small (%.2f m from the wardrobe front)" % (player.global_position.x - (shell_origin.x - 0.89)))
	check(Game.count("sun_tracker") == 0, "and the part inside can't be grabbed through it")
	player.set_physics_process(true)
	check(not zombie.poke(player) and not zombie.poke(player), "two pokes: just grumbling")
	check(not Game.is_tiny(), "not cursed yet")
	check(zombie.poke(player), "the third poke casts the curse")
	for i in 40:
		await process_frame
	check(Game.is_tiny() and absf(Game.tiny_days_left() - 2.0) < 0.05, "tiny for two days (%.2f left)" % Game.tiny_days_left())
	for i in 40:
		await physics_frame                  # the player's own physics step shrinks it
	check(player.tiny and absf(player.get_node("Visual").scale.x - 0.4) < 0.02, "the robot shrank (scale %.2f)" % player.get_node("Visual").scale.x)
	check((player.get_node("CollisionShape3D").shape as CapsuleShape3D).radius < 0.2, "its collision shrank too")
	check(hud_node.curse_label.visible and hud_node.curse_label.text.begins_with("Tiny curse"), "HUD shows the curse (%s)" % hud_node.curse_label.text)
	var until_before: float = Game.data["tiny_until"]
	zombie.poke(player)
	check(Game.data["tiny_until"] == until_before, "poking him while tiny only makes him laugh")
	Game.save(player, "HouseCharger")
	Game.new_game()
	check(not Game.is_tiny(), "a new game has no curse")
	Game.load_save()
	Game.inventory_changed.emit()          # re-attach the loaded tool (new_game detached it)
	check(Game.is_tiny(), "the curse survives save and load")
	player.set_physics_process(false)
	player.global_position = hole_front + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	await physics_frame
	var in_nook := await drive_to(player, Vector2(nook.x - 0.5, nook.z), 240)     # aim at the back: drive_to stops within 0.6 m
	for i in 4:
		await physics_frame
	check(in_nook and Game.count("sun_tracker") == 1, "tiny: through the mouse hole to the sun tracker (reached %s, at %s, nook %s)" % [in_nook, player.global_position, nook])
	Game.data["tiny_until"] = 0.0          # the curse runs out while it's in there
	for i in 3:
		player._update_size(1.0)
	check(player.tiny and not player.room_to_grow(), "no regrowing inside the wardrobe (too cramped)")
	check(await drive_to(player, Vector2(hole_front.x + 0.6, hole_front.z), 240), "the tiny robot drives back out")
	player._update_size(1.0)
	check(not player.tiny and (player.get_node("CollisionShape3D").shape as CapsuleShape3D).radius > 0.3, "full size again outside it (at %s)" % player.global_position)
	player.global_position = shell_origin + Vector3(0.7, 0.1, -1.3)
	await physics_frame
	await drive_to(player, Vector2(shell_origin.x + 1.0, shell_origin.z - 2.5), 120)     # into the shelf: stops right in front of it
	for i in 4:
		await physics_frame
	check(Game.count("solar_cell") == 1, "the solar cell on the shelf")
	# a tool hit is the last straw too
	player.global_position = shell_origin + Vector3(0.6, 0.1, 0.0)
	player.get_node("Visual").global_rotation.y = PI * 0.5        # Visual -Z = west, at the zombie
	for i in 40:
		await process_frame
	Energy.current = 50.0
	check(rig.use(), "the smasher hits the zombie")
	for i in 40:
		await process_frame
	check(Game.is_tiny(), "hitting him casts the curse")
	Clock.advance(1.9)
	check(Game.is_tiny(), "still tiny a little before two days")
	Clock.advance(0.2)
	check(not Game.is_tiny(), "the curse wears off after two days")
	player.set_physics_process(true)
	for i in 40:
		await physics_frame
	check(not player.tiny, "and the robot regrows by itself")

	print("== the Hub: rubble, key, gate, card, tower door")
	player.set_physics_process(false)
	var hub: Node = world.get_node("GeneratedHub")
	var rubble: StaticBody3D = hub.get_node("Props/Gate_east_rubble")
	player.global_position = Vector3(11.2, 0.3, -114.0)
	player.get_node("Visual").global_rotation.y = -PI * 0.5      # forward = east
	for i in 3:
		await physics_frame
	var hits := 0
	while is_instance_valid(rubble) and not rubble.is_queued_for_deletion() and hits < 8:
		rig.use()
		hits += 1
		for i in 40:
			await process_frame
	check(hits == 4, "rubble breaks on the fourth smash (%d)" % hits)
	check(Game.count("scrap_metal") >= 3, "rubble dropped scrap (%d)" % Game.count("scrap_metal"))
	check(await drive_to(player, Vector2(24.0, -114.0), 400), "drove into the east yard")
	for i in 4:
		await physics_frame
	check(Game.count("gate_key") == 1, "found the gate key")
	var west_gate: StaticBody3D = hub.get_node("Props/Gate_west_gate")
	player.global_position = Vector3(-11.0, 0.3, -124.0)
	for i in 30:
		await physics_frame
	player._update_focus()                  # normally runs in the player's (disabled) physics step
	var focus: Interactable = player.get("_focus")
	check(focus != null and focus.get_parent() == west_gate, "west gate prompt found")
	if focus != null:
		focus.interact(player)
	check(Game.get_flag("unlocked:west_gate"), "gate key opens the west gate")
	for i in 90:
		await physics_frame
	check(await drive_to(player, Vector2(-24.0, -124.0), 400), "drove into the west yard")
	for i in 4:
		await physics_frame
	check(Game.count("relay_card") == 1, "found the relay access card")
	player.global_position = Vector3(0.0, 0.3, -128.0)
	for i in 30:
		await physics_frame
	player._update_focus()
	focus = player.get("_focus")
	check(focus != null and focus.get_parent().name == "Gate_tower_door", "tower door prompt found")
	if focus != null:
		focus.interact(player)
	check(Game.get_flag("unlocked:tower_door") and Game.get_flag("slice_complete") and Game.beat_seen("relay"), "the card opens the tower: slice complete")
	for i in 90:
		await physics_frame
	check(await drive_to(player, Vector2(0.0, -134.0), 300), "drove into the tower")
	player.set_physics_process(true)

	print("== the laser")
	for id in ["optic_lens", "circuit_board", "antenna_coil"]:
		Game.add_item(id)
	check(Game.craft("laser"), "laser built")
	Game.data["equipped_tool"] = "laser"
	Game.inventory_changed.emit()
	await process_frame
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.3, -112.0)          # the Hub avenue, facing north
	player.get_node("Visual").global_rotation.y = 0.0
	var vines: StaticBody3D = breakable_script.new()
	vines.name = "TestVines"
	vines.set("effects", PackedStringArray(["burn"]))
	vines.set("health", 50.0)
	var vine_shape := CollisionShape3D.new()
	var vine_box := BoxShape3D.new()
	vine_box.size = Vector3(1.5, 2.0, 0.4)
	vine_shape.shape = vine_box
	vine_shape.position.y = 1.0
	vines.add_child(vine_shape)
	world.add_child(vines)
	vines.global_position = Vector3(0.0, 0.0, -121.0)            # 9 m ahead
	for i in 30:
		await physics_frame
	Energy.current = 60.0
	check(rig.use() and absf(vines.health - 20.0) < 0.01, "the laser burns vines 9 m away (%.0f left)" % vines.health)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3.0, 3.0, 0.3)
	wall_shape.shape = wall_box
	wall_shape.position.y = 1.5
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = Vector3(0.0, 0.0, -116.0)
	for i in 60:
		await physics_frame
	check(not rig.use() and absf(vines.health - 20.0) < 0.01, "but not through a wall")
	wall.free()
	vines.free()

	print("== the Hill Sentry: the tutorial fight")
	var sentry: Node3D = world.get_node("GeneratedLevel/Props/HillSentry")
	check(sentry.global_position.distance_to(Vector3(3, sentry.global_position.y, -90)) < 0.1, "the sentry stands on the hill")
	var owner_difficulty: String = settings.difficulty
	settings.set_difficulty("easy")
	Energy.current = 100.0
	Game.data["loadout"] = ["smasher", "cutter", "laser"]
	player.global_position = Vector3(0.0, 6.0, -79.0)
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame                  # drop onto the hillside
	for i in 400:                            # up the hill until the sentry stops us
		if player.in_combat:
			break
		await drive_to(player, Vector2(0.0, -86.0), 1)
	for i in 5:
		await physics_frame
	var combat: Node = sentry.get_node_or_null("Combat")
	check(combat != null and player.in_combat, "walking up to the crest starts the fight")
	var frames := 0
	var presses := 0
	while is_instance_valid(combat) and combat.phase != "done" and frames < 60 * 90:
		if combat.phase == "choose":
			combat.input_move(0, "")                      # 1: Smash
		elif combat.phase == "timing" and combat.seconds_to_beat() <= 0.0:
			combat.input_timing()                         # right on the beat
			presses += 1
		await process_frame
		frames += 1
	check(Game.get_flag("defeated:hill_sentry") and Game.count("capacitor") == 1, "Easy: won with good timing, the capacitor dropped (%d frames, %d presses)" % [frames, presses])
	for i in 120:
		await process_frame
	check(not player.in_combat and player.camera.current and not is_instance_valid(combat), "the robot drives again with its own camera")
	check(sentry.global_position.distance_to(Vector3(3, sentry.global_position.y, -90)) < 0.1 and sentry.inspect.enabled, "the sentry sits back down beside the path, inspectable")
	# a lost fight on Hard (never pressing): back down the hill, and it can be tried again
	Game.set_flag("defeated:hill_sentry", false)
	sentry.reset()
	settings.set_difficulty("hard")
	Energy.current = 100.0
	player.global_position = Vector3(0.0, 7.0, -86.0)
	combat = sentry.start_fight(player)
	frames = 0
	while is_instance_valid(combat) and combat.phase != "done" and frames < 60 * 120:
		if combat.phase == "choose":
			combat.input_move(0, "")
		await process_frame
		frames += 1
	for i in 150:
		await process_frame
	check(not Game.get_flag("defeated:hill_sentry") and player.global_position.z > -81.0 and not player.in_combat, "Hard, pressing nothing: lost, rolled back down the hill (z %.1f)" % player.global_position.z)
	check(not sentry.fighting, "the sentry is ready for another try")
	Game.set_flag("defeated:hill_sentry", true)
	settings.set_difficulty(owner_difficulty)
	player.set_physics_process(true)

	print("== menus open and close from the keyboard while paused")
	var panel: Control = world.get_node("HUD/InventoryPanel")
	var pause_menu: CanvasLayer = world.get_node("HUD/PauseMenu")
	for action in ["inventory", "inventory", "pause", "pause", "inventory", "pause"]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
	check(not panel.visible and not pause_menu.visible and not paused, "Tab opens/closes the parts screen, Esc the pause menu, Esc closes the parts screen")
	var ev2 := InputEventAction.new()
	ev2.action = "inventory"
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await process_frame
	await process_frame
	check(panel.visible and paused, "parts screen open pauses the game")
	var ev3 := InputEventAction.new()
	ev3.action = "inventory"
	ev3.pressed = true
	Input.parse_input_event(ev3)
	await process_frame
	await process_frame
	check(not panel.visible and not paused, "Tab closes it again while paused")

	print("== pickups")
	var pickup: Node3D = world.get_node("GeneratedLevel/Collectibles").get_child(0)
	var pickup_path := String(pickup.get_path())
	var pickup_item: String = pickup.item_id
	player.global_position = pickup.global_position + Vector3(0, 0.2, 0)
	for i in 5:
		await physics_frame
	check(Game.count(pickup_item) == 1, "touching a part puts it in the inventory (%s)" % pickup_item)
	Game.save(player, "HouseCharger")

	print("== a reloaded world remembers what is gone")
	world.free()
	Game.load_save()
	Game.pending_load = true
	world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await physics_frame
	player = world.get_node("Player")
	charger = world.get_node("HouseCharger")
	check(world.get_node_or_null(pickup_path.trim_prefix("/root/" + world.name + "/")) == null, "collected part is gone after load")
	check(world.get_node_or_null("HouseDoor") == null, "broken door stays gone after load")
	check(world.get_node_or_null("HammerHead") == null, "house part stays collected after load")
	Game.set_flag("door_broken")

	print("== shutdown and reboot")
	Clock.time = 0.6
	var day_before: int = Clock.day
	Energy.drain(1000.0)
	for i in 4 * 60:
		await physics_frame
	check(Clock.day == day_before + 1 and absf(Clock.time - 0.30) < 0.01, "rebooted next morning")
	check(Energy.current > 0.0 and not player.shut_down, "rebooted with emergency energy (%.0f)" % Energy.current)
	check(player.global_position.distance_to(charger.global_position) < 2.5, "rebooted beside the last charger")
	check(Game.count(pickup_item) == 1, "inventory kept through the shutdown")

	world.free()
	Game.delete_save()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "PROBLEMS FOUND", failures])
	quit(0 if failures == 0 else 1)
