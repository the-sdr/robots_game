extends SceneTree

# Headless test of the game systems (no window, no GPU):
#   <godot> --headless --fixed-fps 60 --path . -s tools/systems_test.gd
#   <godot> --headless --fixed-fps 60 --path . -s tools/systems_test.gd ++ serious
# Covers: catalog integrity, inventory + crafting, save/load round trip,
# the clock and sun, energy drain/depletion, docking at the house charger in
# the real world scene, and reboot after a shutdown.
# Runs in one game mode (`++ silly`, the default, or `++ serious`): run it in
# both. It writes only test_ files, never the player's own saves or settings.

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


## Silly: the Angry Zombie, the tiny curse, the mouse hole.
func _crooked_house_silly(world: Node, player: CharacterBody3D, rig: Node3D) -> void:
	check((player.get_node("Visual/Torso") as MeshInstance3D).material_override.resource_name == "paint:silly/metal", "Silly: the robot is painted toy plastic")
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
	check(player.tiny and absf(player.get_node("Visual").scale.x - 0.04) < 0.005, "the robot shrank (scale %.2f)" % player.get_node("Visual").scale.x)
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

## Serious: no zombie, no curse; the old robot shares the wardrobe's secret.
func _crooked_house_serious(world: Node, player: CharacterBody3D) -> void:
	check((player.get_node("Visual/Torso") as MeshInstance3D).material_override.resource_name == "paint:serious/metal", "Serious: the robot is painted worn metal")
	var crooked: Node3D = world.get_node_or_null("GeneratedLevel/Props/CrookedHouse")
	check(crooked != null, "the crooked house is in the forest")
	check(crooked.get_node_or_null("AngryZombie") == null and crooked.get_node_or_null("SunTracker") == null, "no Angry Zombie, no pickup behind the mouse hole")
	var robot: Node3D = crooked.get_node_or_null("ZombieRobot")
	check(robot != null and robot.global_position.distance_to(Vector3(-25.7, 0.0, 3.0)) < 0.3, "the old robot sits where Silly's zombie stands (%s)" % (robot.global_position if robot != null else Vector3.INF))
	var model: Node3D = robot.get("visual")
	check(model.get_node_or_null("ArmRight/ToolRig") == null and model.get_node_or_null("Head/Headlight") == null
		and (model.get_node("Torso") as MeshInstance3D).material_override.resource_name == "paint:rust/metal", "it's the player's own model, rusted, without tools or headlight")
	Game.curse_tiny()
	check(not Game.is_tiny(), "no tiny curse in Serious")
	var trackers: int = Game.count("sun_tracker")
	Energy.current = 30.0
	check(not robot.talk(player) and robot.interactable.prompt.begins_with("Share power"), "a first look: it mumbles; now it can be given power")
	check(not robot.talk(player) and Game.count("sun_tracker") == trackers and Energy.current == 30.0, "it won't take the last of a low battery")
	Energy.current = 80.0
	check(robot.talk(player) and absf(Energy.current - 55.0) < 0.01, "sharing a quarter of the battery wakes it (battery %.0f)" % Energy.current)
	check(Game.count("sun_tracker") == trackers + 1 and Game.get_flag("memory:zombie_robot") and Game.beat_seen("old_robot_wakes"), "it gives the sun tracker it kept, and a memory")
	check(not robot.talk(player) and Game.count("sun_tracker") == trackers + 1, "awake, it talks; nothing more to give")
	Game.save(player, "HouseCharger")
	Game.new_game()
	check(not Game.get_flag("woke:zombie_robot"), "a new game: it sleeps again")
	Game.load_save()
	Game.inventory_changed.emit()
	check(Game.get_flag("woke:zombie_robot"), "and a loaded game remembers it woke")
	var shell_origin: Vector3 = crooked.global_position
	player.set_physics_process(false)
	player.global_position = shell_origin + Vector3(0.7, 0.1, -1.3)
	player.velocity = Vector3.ZERO
	await physics_frame
	await drive_to(player, Vector2(shell_origin.x + 1.0, shell_origin.z - 2.5), 120)
	for i in 4:
		await physics_frame
	check(Game.count("solar_cell") == 1, "the solar cell on the shelf, past the old robot")
	player.set_physics_process(true)

func _remove_test_files() -> void:
	for file in ["test_settings.cfg", "test_save.json", "test_save_silly.json", "test_save_serious.json"]:
		if FileAccess.file_exists("user://" + file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + file))

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
	# The game run from the editor shares user:// with this test: never touch its
	# saves or settings (every run used to delete the player's save).
	var settings: Node = root.get_node("Settings")
	Game.save_prefix = "test_"
	settings.path = "user://test_settings.cfg"
	_remove_test_files()
	var args := OS.get_cmdline_user_args()
	var test_mode: String = args[0] if not args.is_empty() and Game.MODES.has(args[0]) else "silly"
	settings.set_mode(test_mode)
	print("== mode: %s" % test_mode)
	load("res://scripts/ui/tool_card.gd").suppressed = true     # cards pause the game; tested on their own below
	create_timer(480.0).timeout.connect(func() -> void: print("RESULT: WATCHDOG TIMEOUT (a check hung or a script error aborted the run)"); quit(2))
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
	check(stored.load(settings.path) == OK and stored.get_value("game", "difficulty_" + test_mode) == "hard", "difficulty saved to settings.cfg, for this mode")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var diff_button: Button = menu.get_node("%DifficultyButton")
	check(diff_button.text == "Difficulty: Hard", "main menu shows the difficulty (%s)" % diff_button.text)
	diff_button.pressed.emit()
	check(settings.difficulty == "easy" and diff_button.text == "Difficulty: Easy", "pressing it cycles to Easy")
	var other_mode: String = "serious" if test_mode == "silly" else "silly"
	(menu.get_node("%SillyButton" if other_mode == "silly" else "%SeriousButton") as Button).pressed.emit()
	check(Game.mode == other_mode and settings.mode == other_mode and settings.difficulty == "easy" and diff_button.text == "Difficulty: Easy",
		"picking %s on the menu switches the game; its own difficulty (Easy) comes back" % other_mode)
	settings.set_difficulty("medium")
	(menu.get_node("%SillyButton" if test_mode == "silly" else "%SeriousButton") as Button).pressed.emit()
	check(Game.mode == test_mode and settings.difficulty == "easy", "and back: %s keeps its own difficulty" % test_mode)
	menu.free()
	settings.set_difficulty(owner_level)

	print("== two games, two saves")
	var mode_stand_in := Node3D.new()
	root.add_child(mode_stand_in)
	for m in Game.MODES:
		settings.set_mode(m)
		Game.new_game()
		Game.save(mode_stand_in, "")
	settings.set_mode("silly")
	Game.data["day"] = 7
	Game.save(mode_stand_in, "")
	settings.set_mode("serious")
	check(Game.load_save() and int(Game.data["day"]) == 1 and Game.data["mode"] == "serious", "each mode loads its own save (serious: day %s)" % Game.data["day"])
	check(Game.save_path("silly").ends_with("test_save_silly.json") and Game.save_path("serious").ends_with("test_save_serious.json"), "one file per mode, test_ files in tests")
	Game.delete_save()
	check(not Game.has_save("serious") and Game.has_save("silly"), "deleting one mode's save leaves the other")
	Game.set_mode("silly")
	Game.delete_save()
	var legacy := FileAccess.open("user://test_save.json", FileAccess.WRITE)
	legacy.store_string("{}")
	legacy.close()
	Game._migrate_legacy_save()
	check(Game.has_save("silly") and not FileAccess.file_exists("user://test_save.json"), "the old single save becomes the Silly save")
	Game.delete_save()
	mode_stand_in.free()
	settings.set_mode(test_mode)
	Game.new_game()

	print("== Silly sounds")
	var sfx: Node = root.get_node("Sfx")
	var bad_sounds := []
	for id in sfx.SOUNDS:
		var wav: AudioStreamWAV = sfx.streams.get(id)
		var loudest := 0
		if wav != null:
			for i in range(0, wav.data.size() - 1, 64):
				loudest = maxi(loudest, absi(wav.data.decode_s16(i)))
		if wav == null or absf(wav.get_length() - float(sfx.SOUNDS[id][2])) > 0.01 or loudest < 3000:
			bad_sounds.append(id)
	check(bad_sounds.is_empty(), "every sound is synthesized, the right length and audible (bad: %s)" % [bad_sounds])
	var playing_before := 0
	for p in sfx.get_children():
		playing_before += 1 if (p as AudioStreamPlayer).playing else 0
	sfx.play("boing")
	var playing_after := 0
	for p in sfx.get_children():
		playing_after += 1 if (p as AudioStreamPlayer).playing else 0
	check((playing_after > playing_before) == Game.silly(), "%s: play() %s" % [test_mode, "sounds" if Game.silly() else "stays silent"])

	print("== story: two voices")
	var story: Node = root.get_node("Story")
	var one_mode := {"zombie": "silly", "tiny": "silly", "tiny_over": "silly", "old_robot": "serious", "old_robot_wakes": "serious"}
	var voice_gaps := []
	for id in story.BEATS:
		for m in Game.MODES:
			var should: bool = not one_mode.has(id) or one_mode[id] == m
			var pair: Array = story.BEATS[id].get(m, [])
			if should != (pair.size() == 2 and String(pair[0]) != "" and String(pair[1]) != ""):
				voice_gaps.append("%s/%s" % [id, m])
	check(voice_gaps.is_empty(), "every beat has a Silly and a Serious text; zombie and curse only in Silly, the old robot only in Serious (gaps: %s)" % [voice_gaps])
	var mirror_text: String = story.beat("mirrors").get("text", "")
	check(mirror_text != "" and not mirror_text.contains("{"), "button names in beats come from Glyphs (%s)" % mirror_text.right(40))
	check(story.beat(one_mode.keys()[0] if test_mode == "serious" else "old_robot").is_empty(), "the other mode's beats don't play in %s" % test_mode)
	var combat_words: Dictionary = load("res://scripts/combat/combat.gd").WORDS
	check(combat_words["silly"].keys() == combat_words["serious"].keys(), "fight popups have words in both voices")

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
	var settings_node: Node = root.get_node("Settings")
	var level_before: String = settings_node.difficulty
	for level in {"easy": 15.0, "medium": 10.0, "hard": 5.0}.keys():
		settings_node.difficulty = level
		var minutes: float = Energy.MAX / Energy.drive_drain() / 60.0
		check(absf(minutes - {"easy": 15.0, "medium": 10.0, "hard": 5.0}[level]) < 0.01 and Energy.idle_drain() < Energy.drive_drain() * 0.1,
			"%s: a full battery lasts %.1f minutes of driving" % [level, minutes])
	settings_node.difficulty = level_before

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
	var grade: Dictionary = day_night.GRADES[Game.mode]
	var base_fog: Array = env.get_meta("base_fog", [0.0, 0.0, 0.0])
	check(env.adjustment_enabled and is_equal_approx(env.adjustment_saturation, grade["saturation"])
		and is_equal_approx(env.fog_depth_begin, float(base_fog[0]) * float(grade["fog_near"])),
		"%s grade: saturation %.2f, fog from %.0f m (scene's %.0f m)" % [Game.mode, env.adjustment_saturation, env.fog_depth_begin, float(base_fog[0])])
	day_night._apply_grade()
	check(is_equal_approx(env.fog_depth_begin, float(base_fog[0]) * float(grade["fog_near"])), "grading again never compounds the fog")
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
	Clock.time = 0.0
	check(str(charger.bar_state()) == str([2, -1]), "at night, nobody docked: steady, nothing blinks (%s)" % [charger.bar_state()])
	Clock.time = 0.5
	charger.stored = charger.effective_capacity()
	for i in 2:
		await process_frame
	var top_ring: MeshInstance3D = charger.get_node("BarSegment4")
	check(str(charger.bar_state()) == str([5, -1]) and (top_ring.material_override as StandardMaterial3D).emission_energy_multiplier > 1.0, "full: all five rings glow")
	Energy.current = 50.0
	charger.dock(player)
	for i in 2:
		await process_frame
	check(charger.bar_state()[1] == 4, "docked: the ring the robot is charging from blinks (%s)" % [charger.bar_state()])
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
	for i in 40:
		await process_frame
	var cable_ends: Array = charger.cable_ends()
	var port: Vector3 = player.get_node("Visual/ChargePort").global_position
	check(cable_ends.size() == 2 and (cable_ends[1] as Vector3).distance_to(port) < 0.01 and charger.get_node("Cable").visible,
		"docked: the cable reels out into the robot's charge port (%s)" % [cable_ends])
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
	for i in 30:
		await process_frame
	check(charger.cable_ends().is_empty() and not charger.get_node("Cable").visible, "undocked: the cable reels back in")

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

	print("== the crooked house (%s mode)" % Game.mode)
	if Game.silly():
		await _crooked_house_silly(world, player, rig)
	else:
		await _crooked_house_serious(world, player)

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
	var combat_rules: Script = load("res://scripts/combat/combat.gd")
	var sentry: Node3D = world.get_node("GeneratedLevel/Props/HillSentry")
	check(sentry.global_position.distance_to(Vector3(3, sentry.global_position.y, -90)) < 0.1, "the sentry stands on the hill")
	var owner_difficulty: String = settings.difficulty
	settings.set_difficulty("easy")
	Energy.current = 100.0
	Game.data["loadout"] = ["smasher", "cutter", "laser"]
	Game.data["equipped_tool"] = "smasher"
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
	var coach_seen := {}
	var switched := false
	var ring_keys := {}                      # the button shown under the ring, per phase (save_78)
	var hint_in_its_turn := ""
	while is_instance_valid(combat) and combat.phase != "done" and frames < 60 * 90:
		if combat.phase in ["defend", "timing"] and combat._ring.visible:
			ring_keys[combat.phase] = combat._ring_key.text
		if combat.phase == "defend":
			hint_in_its_turn += combat._hint.text
		if combat.phase == "coach":
			coach_seen[combat._coach_title.text] = true
			combat.dismiss_coach()
		elif combat.phase == "choose":
			if not switched:                              # RB / Q switches the tool in hand, then back
				switched = true
				var rb := InputEventAction.new()
				rb.action = "cycle_tool"
				rb.pressed = true
				Input.parse_input_event(rb)
				for i in 3:
					await process_frame
				check(combat._tool != "smasher" and combat._tools.size() > 1, "RB / Q switches tools on your turn (to the %s)" % combat._tool)
				combat.select_tool("smasher")
			combat.start_attack()                         # RT: the smasher in hand
		elif combat.phase in ["attack", "defend", "timing"]:
			combat.perform_for_test("perfect")
			presses += 1
		await process_frame
		frames += 1
	var coached := ", ".join(coach_seen.keys())
	check(coach_seen.has("A fight!") and coach_seen.has("Your turn") and coached.contains("The Smasher in a fight") and coached.contains("Its turn: defend with the Smasher"),
		"the first fight stops to teach each step (%s)" % coached)
	var use_key: String = root.get_node("Glyphs").label("use_tool").to_upper()
	check(ring_keys.get("defend", "") == use_key, "defending with the smasher, the ring shows the use button %s (was the jump button; shown: %s)" % [use_key, ring_keys])
	check(hint_in_its_turn == "", "its turn: the \"Your turn!\" hint is gone (save_78)")
	check(Game.get_flag("defeated:hill_sentry") and Game.count("capacitor") == 0, "Easy: won with the smasher (%d frames, %d patterns); the reward isn't handed over..." % [frames, presses])
	var plating: Node = sentry.get_parent().get_node_or_null("Salvage_hill_sentry")
	check(plating != null and plating.is_in_group("detectable"), "...its shield plating fell off beside it: salvage to find")
	var below := PhysicsRayQueryParameters3D.create(plating.global_position + Vector3(0, 0.5, 0), plating.global_position + Vector3(0, -3, 0))
	below.exclude = [plating.get_rid()]
	var ground_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(below)
	check(not ground_hit.is_empty() and absf((ground_hit["position"] as Vector3).y - plating.global_position.y) < 0.15 and absf(plating.scale.x - 0.75) < 0.01,
		"the plating sits on the hillside at 0.75 size (%s)" % plating.global_position)
	var caps_before: int = Game.count("capacitor")
	for i in 4:
		if is_instance_valid(plating) and not plating.salvaged:
			sentry.apply("cut", 26.0, sentry.global_position + Vector3(1, 0, 0))      # aimed at the Sentry itself (save_80)
	check(Game.count("capacitor") == caps_before + 1 and plating.salvaged, "cutting the beaten Sentry itself salvages its plating: the capacitor")
	check(not sentry.apply("cut", 26.0, sentry.global_position), "stripped: nothing more from the Sentry")
	check(combat_rules.smash_quality(7, false) == "perfect" and combat_rules.smash_quality(4, false) == "good" and combat_rules.smash_quality(4, true) == "perfect"
		and combat_rules.cut_quality(0.78, false, 0.72, 0.84) == "perfect" and combat_rules.cut_quality(0.5, false, 0.72, 0.84) == "good" and combat_rules.cut_quality(1.0, true, 0.72, 0.84) == "miss"
		and combat_rules.trace_quality(5) == "perfect" and combat_rules.trace_quality(3) == "good" and combat_rules.share_quality(0.3) == "miss",
		"each tool's fight scoring: taps, heat, trace, hold")
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
		if combat.phase == "coach":
			combat.dismiss_coach()
		elif combat.phase == "choose":
			combat.start_attack()
		elif combat.phase in ["attack", "defend", "timing"]:
			combat.perform_for_test("miss")                # pressing nothing
		await process_frame
		frames += 1
	for i in 150:
		await process_frame
	check(not Game.get_flag("defeated:hill_sentry") and player.global_position.z > -81.0 and not player.in_combat, "Hard, pressing nothing: lost, rolled back down the hill (z %.1f)" % player.global_position.z)
	check(not sentry.fighting, "the sentry is ready for another try")
	Game.set_flag("defeated:hill_sentry", true)
	settings.set_difficulty(owner_difficulty)
	player.set_physics_process(true)

	print("== the relay vault: lift, sealed rooms, mirror puzzle, Pythia, hover")
	var vault: Node3D = world.get_node("RelayVault")
	var vo: Vector3 = vault.global_position                 # the vault's frame: rooms are relative to it
	var day_night_node: Node = world.get_node("DayNight")
	Game.data["tiny_until"] = 0.0          # this test sets the clock back to midnight, which would revive the zombie's curse
	player.set_tiny(false, false)
	world.get_node("GeneratedHub/Props/RelayTower/LiftDown").travel(player)
	for i in 45:
		await process_frame
	check(player.global_position.distance_to(Vector3(0, -29.9, -140.8)) < 0.4, "the tower's lift goes down to the vault (%s)" % player.global_position)
	for i in 5:
		await physics_frame
	check(day_night_node.interior and (world.get_node("DirectionalLight3D") as DirectionalLight3D).light_energy == 0.0, "underground: no sun, the vault's own lamps")
	player.set_physics_process(false)
	var escaped := []
	for k in 8:
		var a := TAU * k / 8.0
		player.global_position = vo + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		await drive_to(player, Vector2(vo.x + cos(a) * 40.0, vo.z + sin(a) * 40.0), 300)
		var q := player.global_position - vo
		if absf(q.x) > 7.0 or q.z > 3.0 or q.z < -32.0 or q.y < -0.5 or q.y > 5.0:
			escaped.append(q)
	check(escaped.is_empty(), "sealed: driving flat out in 8 directions never leaves the vault (%s)" % [escaped])
	check(not vault.trace()["lit"], "the mirrors start the wrong way round")
	for id in ["m1", "m2", "m3"]:
		vault.mirrors[id].flip()
	var solved: Dictionary = vault.trace()
	check(solved["lit"] and solved["points"].size() == 5, "all three turned: the beam reaches the receiver (%s)" % [solved["points"]])
	Clock.time = 0.0
	for i in 10:
		await process_frame
	check(not vault.sun_on_source() and not Game.get_flag("vault_lit"), "at night the shaft is dark: no beam, nothing opens")
	Game.data["equipped_tool"] = "laser"
	Game.inventory_changed.emit()
	player.global_position = vo + Vector3(-3.5, 0.1, -10.0)
	player.get_node("Visual").global_rotation.y = PI * 0.5       # facing west, at the port
	for i in 60:
		await physics_frame
	Energy.current = 80.0
	check(rig.use() and vault.laser_left > 0.0, "the laser powers the port")
	for i in 10:
		await process_frame
	check(Game.get_flag("vault_lit"), "the beam reaches the lens: the hall is lit")
	for i in 150:
		await process_frame
	await drive_to(player, Vector2(vo.x, vo.z - 18.0), 400)
	check(await drive_to(player, Vector2(vo.x, vo.z - 26.0), 400), "the door is open: into Pythia's chamber")
	var pythia: Node = vault.get_node("Pythia")
	var hud_v: CanvasLayer = world.get_node("HUD")
	pythia.talk(player)
	check(hud_v.dialogue_open(), "Pythia talks")
	for i in 4:
		hud_v.advance_dialogue()
	check(not hud_v.dialogue_open() and Game.count("lift_fan") == 2 and Game.count("gyro") == 1, "after her four lines: two lift fans and a gyro")
	var cell_spot := vo + Vector3(3.6, 0, -29.6)
	var cells_before: int = Game.count("solar_cell")
	await drive_to(player, Vector2(cell_spot.x, cell_spot.z), 300)
	for i in 5:
		await physics_frame
	check(Game.count("solar_cell") == cells_before + 1, "the solar cell behind the door")
	check(Game.craft("hover_pack") and Game.has_tool("hover"), "hover pack built")
	player.global_position = vo + Vector3(-2.0, 0.2, -27.0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	for i in 30:
		await physics_frame
	var floor_y: float = player.global_position.y
	var energy_before: float = Energy.current
	Input.action_press("jump")
	var top := floor_y
	for i in 150:
		await physics_frame
		top = maxf(top, player.global_position.y)
	check(top - floor_y > 2.0 and top - floor_y < 2.9, "hovering climbs to about 2.5 m and holds (%.2f m)" % (top - floor_y))
	check(energy_before - Energy.current > 5.0, "hovering drinks energy (%.1f in 2.5 s)" % (energy_before - Energy.current))
	Input.action_release("jump")
	for i in 90:
		await physics_frame
	check(player.global_position.y - floor_y < 0.1, "let go: back down on the floor")
	vault.get_node("LiftUp").travel(player)
	for i in 45:
		await process_frame
	for i in 5:
		await physics_frame
	check(player.global_position.distance_to(Vector3(0, 0.1, -133.2)) < 0.5 and not day_night_node.interior, "the lift goes back up to the tower, and daylight returns")
	Clock.time = 0.5
	player.set_physics_process(true)

	print("== the Agora: vines, shutter, fabricator, printing, the ledge, charger")
	var agora: Node = world.get_node("GeneratedAgora")
	var agora_vines: StaticBody3D = agora.get_node("Props/Gate_agora_vines")
	player.set_physics_process(false)
	player.global_position = Vector3(24.5, 0.3, -114.0)          # the Hub's east yard, at the vines in its east wall
	player.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	check(not await drive_to(player, Vector2(31.0, -114.0), 240), "the vines hold the way into the Agora")
	player.get_node("Visual").global_rotation.y = -PI * 0.5      # facing east, at the vines
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	await process_frame
	Energy.current = 90.0
	var vine_health: float = agora_vines.health
	rig.use()
	check(is_equal_approx(agora_vines.health, vine_health), "the smasher bounces off the vines")
	for i in 45:
		await process_frame
	Game.data["equipped_tool"] = "laser"
	Game.inventory_changed.emit()
	await process_frame
	var shots := 0
	while is_instance_valid(agora_vines) and not agora_vines.is_queued_for_deletion() and shots < 6:
		rig.use()
		shots += 1
		for i in 60:
			await process_frame
	check(shots == 2 and Game.get_flag("cleared:agora_vines"), "the laser burns the vines away (%d shots)" % shots)
	check(await drive_to(player, Vector2(31.0, -114.0), 300) and await drive_to(player, Vector2(43.0, -114.0), 400), "through the burnt gap into the market square")
	check(await drive_to(player, Vector2(43.0, -121.0), 300) and await drive_to(player, Vector2(47.8, -121.0), 300), "up the north lane to the printer shop")
	var shutter: StaticBody3D = agora.get_node("Props/Gate_shop_shutter")
	check(not await drive_to(player, Vector2(53.0, -121.0), 200), "the jammed shutter holds")
	player.get_node("Visual").global_rotation.y = -PI * 0.5
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	for i in 60:
		await process_frame
	var scrap_before: int = Game.count("scrap_metal")
	var smashes := 0
	while is_instance_valid(shutter) and not shutter.is_queued_for_deletion() and smashes < 8:
		rig.use()
		smashes += 1
		for i in 40:
			await process_frame
	check(smashes == 3 and Game.count("scrap_metal") == scrap_before + 2, "the shutter gives way to the third smash and drops 2 scrap (%d smashes)" % smashes)
	check(await drive_to(player, Vector2(52.8, -120.8), 300) and await drive_to(player, Vector2(55.0, -121.2), 300), "into the printer shop")
	for i in 5:
		await physics_frame
	check(Game.count("printer_core") == 1 and Game.count("nozzle") == 1, "the printer core and the nozzle are on the shop floor")
	check(Game.beat_seen("agora") and Game.beat_seen("printer_shop"), "story cards for the square and the shop")
	check(Game.craft_blocker("print_power_cell") == "Not understood yet", "scrap printing stays hidden until the fabricator exists")
	check(Game.craft("fabricator") and Game.has_tool("fabricator"), "fabricator built")
	Game.add_item("scrap_metal", 12)
	var power_cells_before: int = Game.count("power_cell")
	var scrap_now: int = Game.count("scrap_metal")
	check(Game.craft("print_power_cell") and Game.count("power_cell") == power_cells_before + 1 and Game.count("scrap_metal") == scrap_now - 3,
		"the fabricator prints a power cell from 3 scrap")
	check(Game.craft("print_solar_cell") and Game.craft("print_capacitor"), "and a solar cell, and a capacitor bank")
	check(Catalog.move("fabricator", "")["kind"] == "repair", "its fight moves: Patch up heals")
	# the ledge: 1.6 m, too high to drive; hover up (real input), or print the ramp
	var ramp: Node3D = agora.get_node("Props/ScrapRamp")
	player.global_position = Vector3(54.0, 0.3, -111.0)          # north of the ledge
	player.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	check(not await drive_to(player, Vector2(54.0, -106.0), 200) and player.global_position.y < 0.5, "the ledge is too high to drive up")
	player.global_position = Vector3(54.0, 0.3, -111.0)
	player.velocity = Vector3.ZERO
	player.camera_rig.global_rotation.y = PI                    # the camera looks south: forward = +Z, towards the ledge
	player.set_physics_process(true)
	for i in 10:
		await physics_frame
	var scrap_ledge: int = Game.count("scrap_metal")
	Energy.current = 90.0
	Input.action_press("jump")
	for i in 90:
		await physics_frame
	Input.action_press("move_forward")
	for i in 80:
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("jump")
	for i in 90:
		await physics_frame
	var landed: Vector3 = player.global_position
	check(landed.y > 1.5 and landed.z > -108.6 and landed.z < -103.4 and landed.x > 51.4 and landed.x < 56.6, "hover up and over: the robot lands on the ledge (%s)" % landed)
	player.set_physics_process(false)
	await drive_to(player, Vector2(52.8, -107.0), 200)
	await drive_to(player, Vector2(54.6, -107.5), 200)
	for i in 5:
		await physics_frame
	check(Game.count("scrap_metal") == scrap_ledge + 2, "the scrap cache on top (%d)" % (Game.count("scrap_metal") - scrap_ledge))
	player.global_position = Vector3(45.8, 0.3, -106.0)          # the ramp's foot, west of the ledge
	player.velocity = Vector3.ZERO
	player.get_node("Visual").global_rotation.y = -PI * 0.5
	for i in 10:
		await physics_frame
	check(not ramp.built and ramp.get_node("Solid").collision_layer == 0, "the ramp is only a ghost outline")
	Game.data["equipped_tool"] = "fabricator"
	Game.inventory_changed.emit()
	await process_frame
	Game.remove_item("scrap_metal", Game.count("scrap_metal"))
	Game.add_item("scrap_metal", 1)
	check(not rig.use() and not ramp.built, "one scrap is not enough to print it")
	for i in 45:
		await process_frame
	Game.add_item("scrap_metal", 1)
	check(rig.use() and ramp.built and Game.get_flag("built:scrap_ramp") and Game.count("scrap_metal") == 0, "the fabricator prints the ramp from 2 scrap")
	for i in 70:
		await process_frame
	check(await drive_to(player, Vector2(53.5, -106.0), 400) and player.global_position.y > 1.5, "drove up the printed ramp onto the ledge (y %.2f)" % player.global_position.y)
	var agora_charger: Node = agora.get_node_or_null("Props/AgoraCharger")
	check(agora_charger != null and agora_charger.is_in_group("charger") and is_equal_approx(float(agora_charger.capacity), 140.0), "the Agora charger stands in the square")
	Game.data["equipped_tool"] = "laser"
	Game.inventory_changed.emit()
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

	print("== controller: A presses menu buttons, the right trigger uses the tool")
	var pad_a := InputEventJoypadButton.new()
	pad_a.button_index = JOY_BUTTON_A
	pad_a.pressed = true
	check(pad_a.is_action_pressed("ui_accept"), "A is ui_accept (presses the focused menu button)")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.8
	check(trigger.is_action_pressed("use_tool"), "the right trigger is use_tool")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	check(not rb.is_action("use_tool"), "RB no longer uses the tool")
	Input.parse_input_event(ev2)
	await process_frame
	await process_frame
	var focused := panel.get_viewport().gui_get_focus_owner()
	check(focused is Button and panel.is_ancestor_of(focused), "the parts screen focuses a button when it opens (%s)" % [focused])
	panel.toggle()
	var pulls := 0
	Input.action_press("use_tool")               # held state only; the events go straight to tool_pulled
	for value in [0.6, 0.8, 1.0, 0.9]:          # one squeeze sends a stream of axis values
		trigger.axis_value = value
		pulls += int(player.tool_pulled(trigger))
		await physics_frame
	check(pulls == 1, "one trigger pull uses the tool once (%d)" % pulls)
	Input.action_release("use_tool")
	await physics_frame
	await physics_frame
	trigger.axis_value = 0.8
	check(player.tool_pulled(trigger), "after a release the next pull works")
	await physics_frame

	print("== falling off the edge of the world")
	for i in 40:
		await physics_frame
	var safe_spot := player.global_position
	player.global_position = safe_spot + Vector3(0, -45.0, 0)
	await physics_frame
	await physics_frame
	check(player.global_position.y < safe_spot.y - 40.0, "not straight away (a teleport to lower ground is not a fall)")
	var fall_frames := 0
	while player.global_position.y < safe_spot.y - 10.0 and fall_frames < 60 * 6:
		await physics_frame
		fall_frames += 1
	check(player.global_position.distance_to(safe_spot) < 1.0, "a robot that falls out of the world is put back on solid ground after %d frames (%s)" % [fall_frames, player.global_position])

	print("== the jump animation")
	var fx: Node = player.get_node("JumpFx")
	for i in 150:                            # Silly's looser spring takes ~2 s to settle the last landing
		await physics_frame
	check((fx.squash as Vector3).distance_to(Vector3.ONE) < 0.02 and absf(player.visual.scale.y - player.visual_size) < 0.01, "at rest the body keeps its shape")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	check(fx.squash.y > 1.05, "takeoff: the body stretches (%.2f)" % fx.squash.y)
	var hop_landings: int = fx.landings
	var hop_squash := 2.0
	for i in 120:
		await physics_frame
		if fx.landings > hop_landings:
			hop_squash = minf(hop_squash, fx.squash.y)
	check(fx.landings == hop_landings + 1 and hop_squash < 0.92, "a hop lands with a squash (%.2f)" % hop_squash)
	for i in 60:
		await physics_frame
	check((fx.squash as Vector3).distance_to(Vector3.ONE) < 0.02 and absf(player.visual.scale.y - player.visual_size) < 0.01, "then springs back to exactly its shape")
	player.global_position += Vector3(0, 4.0, 0)
	var drop_landings: int = fx.landings
	var drop_squash := 2.0
	var most_tumble := 0.0
	for i in 150:
		await physics_frame
		most_tumble = maxf(most_tumble, absf(fx.tumble))
		if fx.landings > drop_landings:
			drop_squash = minf(drop_squash, fx.squash.y)
	check(fx.landings == drop_landings + 1 and drop_squash < hop_squash - 0.03, "a drop from 4 m squashes harder than a hop (%.2f vs %.2f)" % [drop_squash, hop_squash])
	for i in 60:
		await physics_frame
	if Game.silly():
		check(fx.wobble and most_tumble > 1.0 and fx.tumble == 0.0 and player.visual.position.length() < 0.01 and absf(player.visual.rotation.z) < 0.05,
			"Silly: the 4 m drop cartwheels (%.1f rad) and lands the turn upright" % most_tumble)
		var most_lean := 0.0
		Input.action_press("move_forward")
		for i in 40:
			await physics_frame
			most_lean = maxf(most_lean, fx.lean.length())
		Input.action_release("move_forward")
		for i in 30:
			await physics_frame
			most_lean = maxf(most_lean, fx.lean.length())
		check(most_lean > 0.05, "Silly: speeding up and stopping rocks the body (lean up to %.2f rad)" % most_lean)
		for i in 180:
			await physics_frame
		check(fx.lean.length() < 0.01 and absf(player.visual.rotation.x) < 0.01, "and it settles upright again (%.3f)" % fx.lean.length())
	else:
		check(not fx.wobble and most_tumble == 0.0 and player.visual.rotation.x == 0.0 and player.visual.rotation.z == 0.0, "Serious: no wobble, the robot never tilts")

	print("== the detector: sweeps, warm spots, digging")
	var det: Node = player.get_node("Detector")
	var terrain_mat: ShaderMaterial = load("res://materials/terrain_painterly.tres")
	var fork_find: Node3D = world.get_node("GeneratedLevel/Finds/Find_fork_scrap")
	var far_find: Node3D = world.get_node("GeneratedLevel/Finds/Find_clearing_gears")
	check(fork_find.is_in_group("detectable") and not det.sweeping(), "buried finds are detectable; no scan until the button is pressed")
	player.global_position = fork_find.global_position + Vector3(1.6, 0.3, -1.0)
	for i in 10:
		await physics_frame
	var sweeps_before: int = det.sweeps
	var det_ev := InputEventAction.new()
	det_ev.action = "detector"
	det_ev.pressed = true
	Input.parse_input_event(det_ev)
	for i in 4:                      # the key lands just before a frame's _process: give the detector a frame of its own
		await process_frame
	check(det.sweeping() and det.sweeps == sweeps_before + 1, "the detector button sends one scan out")
	var near_spot: Dictionary = det.spots[0]
	var far_spot: Dictionary = {}
	for sp in det.spots:
		if (sp["distance"] as float) > 40.0:
			far_spot = sp
	check(float(near_spot["distance"]) < 2.5 and (near_spot["pos"] as Vector3).distance_to(fork_find.global_position) < 0.01 and float(near_spot["radius"]) <= 0.5,
		"close by (%.1f m) the fix is exact and tight" % float(near_spot["distance"]))
	check(not far_spot.is_empty() and float(far_spot["radius"]) > 8.0, "far away (%.0f m) the warm spot is big and vague (radius %.1f)" % [float(far_spot.get("distance", 0.0)), float(far_spot.get("radius", 0.0))])
	for i in 20:
		await process_frame
	check(float(terrain_mat.get_shader_parameter("scan_amount")) > 0.9 and float(terrain_mat.get_shader_parameter("scan_spots_on")) > 0.5, "during the sweep the ground shows the robot view and warm spots")
	for i in 60 * 2:
		await process_frame
	check(float(terrain_mat.get_shader_parameter("scan_amount")) < 0.01, "between sweeps the normal look is back")
	var far_pos_before: Vector3 = far_spot["pos"]
	for i in 60 * 3:
		await process_frame
	check(det.sweeps == sweeps_before + 1, "no scan goes out by itself (no timer)")
	Input.parse_input_event(det_ev.duplicate())
	for i in 4:
		await process_frame
	check(det.sweeps == sweeps_before + 2, "each press is another scan")
	var far_again: Dictionary = {}
	for sp in det.spots:
		if (sp["distance"] as float) > 40.0:
			far_again = sp
	check(not far_again.is_empty() and (far_again["pos"] as Vector3).distance_to(far_pos_before) > 0.05, "a far fix lands somewhere a little different each sweep")
	check(det.signal_bars == 5, "five signal bars right next to a find (%d)" % det.signal_bars)
	var dig_scrap_before: int = Game.count("scrap_metal")
	var dig_energy: float = Energy.current
	player.global_position = fork_find.global_position + Vector3(0.4, 0.3, 0.0)
	for i in 10:
		await physics_frame
	var dig_ev := InputEventAction.new()
	dig_ev.action = "interact"
	dig_ev.pressed = true
	Input.parse_input_event(dig_ev)
	for i in 4:
		await process_frame
	check(fork_find.dug and fork_find.get_node("Hole").visible and not fork_find.is_in_group("detectable"), "interact digs: a hole, and the detector stops sensing it")
	for i in 90:
		await process_frame
	check(fork_find.recovered and Game.count("scrap_metal") == dig_scrap_before + 1 and dig_energy - Energy.current >= 0.99, "the find comes up into the inventory (digging costs a little energy)")
	check(Game.get_flag("dug:" + String(fork_find.get_path()).trim_prefix("/root/")), "and it stays dug in the save")
	for i in 60 * 6:
		await process_frame
	check(float(terrain_mat.get_shader_parameter("scan_amount")) < 0.01 and float(terrain_mat.get_shader_parameter("scan_spots_on")) < 0.5, "a few seconds after a scan the world looks normal again")

	print("== button pictures and tool cards")
	var glyphs: Node = root.get_node("Glyphs")
	var card_hud: CanvasLayer = world.get_node("HUD")
	var cards: CanvasLayer = card_hud.tool_card
	glyphs.pad = false
	check(glyphs.label("interact") == "E" and glyphs.label("use_tool") == "Left click" and glyphs.label("detector") == "R" and glyphs.label("move") == "WASD",
		"keyboard names (%s, %s, %s)" % [glyphs.label("interact"), glyphs.label("use_tool"), glyphs.label("detector")])
	glyphs.pad = true
	check(glyphs.label("interact") == "X" and glyphs.label("use_tool") == "RT" and glyphs.label("detector") == "LB" and glyphs.label("inventory") == "Menu" and glyphs.label("pause") == "View" and glyphs.label("cycle_tool") == "RB",
		"pad names (%s, %s, %s, %s, %s, %s)" % [glyphs.label("interact"), glyphs.label("use_tool"), glyphs.label("detector"), glyphs.label("inventory"), glyphs.label("pause"), glyphs.label("cycle_tool")])
	glyphs.pad = false
	var pad_tap := InputEventJoypadButton.new()
	pad_tap.button_index = JOY_BUTTON_A
	pad_tap.pressed = true
	Input.parse_input_event(pad_tap)
	var pad_up := pad_tap.duplicate() as InputEventJoypadButton
	pad_up.pressed = false
	Input.parse_input_event(pad_up)
	for i in 4:
		await process_frame
	check(glyphs.pad and card_hud.tool_label.text.contains("RT"), "touching the pad switches prompts to pad buttons (%s)" % card_hud.tool_label.text)
	var key_e := InputEventKey.new()
	key_e.physical_keycode = KEY_F12
	key_e.pressed = true
	Input.parse_input_event(key_e)
	var key_up := key_e.duplicate() as InputEventKey
	key_up.pressed = false
	Input.parse_input_event(key_up)
	for i in 4:
		await process_frame
	check(not glyphs.pad, "a key switches them back")
	cards._queue.clear()                 # the cards queued (unseen) by the sections above
	load("res://scripts/ui/tool_card.gd").suppressed = false
	Game.set_flag("card:hover", false)
	Game.tool_added.emit("hover")
	for i in 4:
		await process_frame
	check(cards.card_open() and paused and cards._title.text == "Hover pack", "a newly built tool shows its card, and the game waits")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	for i in 4:
		await process_frame
	check(not cards.card_open() and not paused and Game.get_flag("card:hover"), "Got it (Enter / A) closes it and play goes on")
	card_hud.queue_card("hover")
	for i in 4:
		await process_frame
	check(not cards.card_open(), "each card shows only once")
	card_hud.toggle_pause()
	await process_frame
	var pause_menu_node: CanvasLayer = card_hud.get_node("PauseMenu")
	(pause_menu_node.find_child("ControlsButton", true, false) as Button).pressed.emit()
	await process_frame
	check(card_hud.help_menu.is_open() and card_hud.help_menu.tab == "Controls", "the pause menu opens Help and controls")
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	Input.parse_input_event(back)
	for i in 4:
		await process_frame
	check(not card_hud.help_menu.is_open() and pause_menu_node.visible and paused, "Esc goes back to the pause menu")
	card_hud.toggle_pause()
	await process_frame
	load("res://scripts/ui/tool_card.gd").suppressed = true

	print("== tool feel: smasher combo, cutter heat, laser trace")
	var feel_settings: Node = root.get_node("Settings")
	var feel_level: String = feel_settings.difficulty
	feel_settings.difficulty = "medium"
	var feel_rig: Node3D = player.get_node("Visual/ArmRight/ToolRig")
	for t in ["smasher", "cutter", "laser"]:
		Game.add_tool(t)
	var feel_forward: Vector3 = -player.visual.global_transform.basis.z
	feel_forward.y = 0.0
	feel_forward = feel_forward.normalized()
	var make_target := func(effects: Array, hp: float, size: Vector3, at: Vector3) -> StaticBody3D:
		var body: StaticBody3D = load("res://scripts/interact/breakable.gd").new()
		body.set("effects", PackedStringArray(effects))
		body.set("health", hp)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position.y = size.y * 0.5
		body.add_child(shape)
		world.add_child(body)
		body.global_position = at
		return body
	Energy.current = 100.0
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	await process_frame
	var crate_c: StaticBody3D = make_target.call(["smash"], 500.0, Vector3(0.8, 0.8, 0.8), player.global_position + feel_forward * 1.2)
	for i in 3:
		await physics_frame
	for hit in 3:
		feel_rig.press()
		feel_rig.release()
		for i in 12:
			await process_frame
	check(feel_rig.combo == 3 and absf((500.0 - crate_c.health) - 34.0 * (1.0 + 1.2 + 1.4)) < 0.5,
		"smasher: three quick presses build a combo (x%d, %.1f damage)" % [feel_rig.combo, 500.0 - crate_c.health])
	for i in 45:
		await process_frame
	feel_rig.press()
	feel_rig.release()
	check(feel_rig.combo == 1, "a pause breaks the combo")
	crate_c.queue_free()
	Game.data["equipped_tool"] = "cutter"
	Game.inventory_changed.emit()
	await process_frame
	var thicket: StaticBody3D = make_target.call(["cut"], 500.0, Vector3(0.8, 1.0, 0.8), player.global_position + feel_forward * 1.1)
	for i in 3:
		await physics_frame
	var cuts_before: int = feel_rig.clean_cuts
	var tuning: Script = load("res://scripts/game/tuning.gd")
	feel_rig.press()
	for i in 300:                                      # hold until the heat is in the green
		await process_frame
		if feel_rig.heat >= tuning.v("cutter_clean_from") + 0.02:
			break
	var heat_at_release: float = feel_rig.heat
	feel_rig.release()
	check(feel_rig.clean_cuts == cuts_before + 1 and 500.0 - thicket.health > 60.0, "cutter: let go in the green (heat %.2f) for a clean cut (%.0f cut)" % [heat_at_release, 500.0 - thicket.health])
	for i in 200:
		await process_frame
	feel_rig.press()
	for i in 60 * 6:                                   # hold until it overheats (not a fixed time: the lock may end first)
		await process_frame
		if feel_rig.overheated > 0.0:
			break
	check(feel_rig.overheated > 0.0 and not feel_rig.holding, "hold too long and it overheats")
	feel_rig.release()
	feel_rig.press()
	check(not feel_rig.holding, "too hot to start again straight away")
	for i in 60 * 3:
		await process_frame
	feel_rig.press()
	check(feel_rig.holding, "cooled down: it cuts again")
	feel_rig.release()
	thicket.queue_free()
	var vine_bar: StaticBody3D = make_target.call(["burn"], 60.0, Vector3(3.0, 0.4, 0.4), player.global_position + feel_forward * 6.0 + Vector3(0, 0.5, 0))
	await physics_frame
	var trace: Vector2i = vine_bar.trace_progress()
	check(trace.y == 5, "a 3 m vine burns in 5 segments (%d)" % trace.y)
	vine_bar.burn_at(vine_bar.trace_point(0), 0.35, player.global_position, 30.0)
	check(vine_bar.trace_progress().x == 1 and vine_bar.health < 60.0, "the beam burns the segment it rests on")
	for k in range(1, 5):
		vine_bar.burn_at(vine_bar.trace_point(k), 0.35, player.global_position, 30.0)
	await process_frame
	check(not is_instance_valid(vine_bar) or vine_bar.is_queued_for_deletion(), "swept along the whole vine, it burns through")
	Game.data["equipped_tool"] = "laser"
	Game.inventory_changed.emit()
	await process_frame
	feel_rig.press()
	for i in 10:
		await process_frame
	check(feel_rig.laser_firing(), "the laser fires while the button is held")
	feel_rig.release()
	await process_frame
	check(not feel_rig.laser_firing(), "and stops when it is let go")
	feel_settings.difficulty = feel_level

	print("== finds: weeds to cut, a crate to smash, a wreck to salvage")
	var inventory_before_finds: Dictionary = (Game.data["inventory"] as Dictionary).duplicate()
	var finds_root: Node = world.get_node("GeneratedLevel/Finds")
	var crate_find: Node3D = finds_root.get_node("Find_clearing_crate")
	var weeds_find: Node3D = finds_root.get_node("Find_clearing_weeds")
	var wreck_find: Node3D = finds_root.get_node("Find_clearing_wreck")
	check(crate_find.is_in_group("detectable") and weeds_find.is_in_group("detectable") and wreck_find.is_in_group("detectable"),
		"the detector senses the crate, the weeds and the wreck")
	var hit_from: Vector3 = crate_find.global_position + Vector3(1.5, 0, 0)
	check(not weeds_find.apply("smash", 50.0, hit_from), "weeds shrug off the smasher")
	var blades_before: int = Game.count("blade_strip")
	for i in 2:
		weeds_find.apply("cut", 26.0, hit_from)
	await process_frame
	check(Game.count("blade_strip") == blades_before + 1 and not is_instance_valid(weeds_find), "cut away, the weeds give up what they hid")
	var scrap_in_crate: int = Game.count("scrap_metal")
	for i in 2:
		crate_find.apply("smash", 34.0, hit_from)
	await process_frame
	check(Game.count("scrap_metal") == scrap_in_crate + 2, "the crate smashes open: 2 scrap")
	var servos_before: int = Game.count("servo_motor")
	var lenses_before: int = Game.count("optic_lens")
	for i in 4:
		wreck_find.apply("cut", 26.0, hit_from)
	await process_frame
	check(is_instance_valid(wreck_find) and wreck_find.salvaged and not wreck_find.is_in_group("detectable") and Game.count("servo_motor") == servos_before + 1 and Game.count("optic_lens") == lenses_before,
		"salvaged with the cutter: a servo motor, and the wreck stays, stripped")
	check(not wreck_find.apply("cut", 26.0, hit_from), "nothing more in a stripped wreck")
	var spare_wreck: StaticBody3D = load("res://scenes/props/wreck.tscn").instantiate()
	spare_wreck.set("drops", {"servo_motor": 1})
	spare_wreck.set("bonus", {"optic_lens": 1})
	spare_wreck.set("break_flag", "salvaged:test_wreck")
	world.add_child(spare_wreck)
	spare_wreck.global_position = wreck_find.global_position + Vector3(0, 0, 4.0)
	await process_frame
	var seam: Vector2i = spare_wreck.trace_progress()
	for k in seam.y:
		spare_wreck.burn_at(spare_wreck.trace_point(k), 0.35, hit_from, 30.0)
	await process_frame
	check(seam.y >= 3 and spare_wreck.salvaged and Game.count("optic_lens") == lenses_before + 1 and Game.count("servo_motor") == servos_before + 2,
		"salvaged with the laser along its %d-part seam: the servo and a bonus optic lens" % seam.y)
	spare_wreck.queue_free()
	Game.data["inventory"] = inventory_before_finds      # the sections below count parts from zero
	Game.inventory_changed.emit()

	print("== playtest fixes (2026-09-30)")
	var fix_hud: CanvasLayer = world.get_node("HUD")
	var fix_glyphs: Node = root.get_node("Glyphs")
	fix_glyphs.pad = true
	check(fix_glyphs.label("ui_cancel") == "B" and fix_glyphs.label("help") == "D-pad down", "pad: B closes things, D-pad down opens help (%s, %s)" % [fix_glyphs.label("ui_cancel"), fix_glyphs.label("help")])
	fix_glyphs.pad = false
	check(fix_glyphs.label("help") == "F1" and fix_glyphs.label("ui_cancel") == "Esc", "keyboard: F1 help, Esc closes (%s, %s)" % [fix_glyphs.label("help"), fix_glyphs.label("ui_cancel")])
	for i in 30:
		await physics_frame
	paused = true                                    # a menu is open...
	Input.action_press("jump")                       # ...and A / Space closes it
	for i in 5:
		await process_frame
	paused = false
	var ground_y: float = player.global_position.y
	for i in 20:
		await physics_frame
	check(player.global_position.y < ground_y + 0.1, "the press that closes a menu doesn't make the robot jump")
	Input.action_release("jump")
	await physics_frame
	await physics_frame
	Input.action_press("jump")
	var top_y := ground_y
	for i in 20:
		await physics_frame
		top_y = maxf(top_y, player.global_position.y)
	Input.action_release("jump")
	check(top_y > ground_y + 0.3, "a fresh press jumps as usual (%.2f m)" % (top_y - ground_y))
	for i in 60:
		await physics_frame
	fix_hud.show_message("Test", "A story card.")
	for i in 60 * 20:
		await process_frame
	check(fix_hud.message_open(), "a story card stays up (20 s later) until it is closed")
	fix_hud.show_message("Next", "A newer card.")
	check(fix_hud.message_title.text == "Next", "a new one replaces it")
	var close_ev := InputEventAction.new()
	close_ev.action = "ui_cancel"
	close_ev.pressed = true
	Input.parse_input_event(close_ev)
	for i in 4:
		await process_frame
	check(not fix_hud.message_open() and not fix_hud.pause_menu.visible, "B / Esc closes it (and doesn't pause)")
	var scan_cards: CanvasLayer = fix_hud.tool_card
	Game.set_flag("card:detector", false)
	scan_cards._queue.clear()
	world.set("_told_scan", false)
	Game.set_flag("house_door_broken", true)
	player.global_position = Vector3(0.0, 0.3, -1.0)          # just outside the house
	for i in 3:
		await process_frame
	check(scan_cards._queue.has("detector"), "stepping out of the house queues the Detector card")
	scan_cards._queue.clear()
	var sweep_det: Node = player.get_node("Detector")
	sweep_det.scan()
	for i in 18:
		await process_frame
	check(sweep_det.wave_radius() > 0.0 and sweep_det.wave_radius() < 12.0, "the sweep ring starts slow near the robot (%.1f m after 0.3 s)" % sweep_det.wave_radius())
	var old_part: Node3D = world.get_node("GeneratedLevel/Collectibles").get_child(0) if world.get_node("GeneratedLevel/Collectibles").get_child_count() > 0 else null
	check(old_part == null or old_part.is_in_group("detectable"), "loose parts are detectable too")
	Game.set_flag("hint_ready:smasher", false)
	var had_smasher: bool = Game.has_tool("smasher")
	Game.data["tools"].erase("smasher")
	Game.add_item("hammer_head")
	Game.add_item("actuator_arm")
	await process_frame
	check(fix_hud.message_open() and fix_hud.message_title.text == "Ready to build" and fix_hud.message_text.text.contains("Smasher"), "with both parts, a card says the Smasher can be built (%s)" % fix_hud.message_text.text)
	fix_hud.close_message()
	if had_smasher:
		Game.data["tools"].append("smasher")

	print("== the forest's parts are inside things that belong there")
	var cache_items := {"spring": "servo_motor", "ruin_far": "optic_lens", "hollow_tree": "power_cell",
		"under_giant": "circuit_board", "garden_nook": "gear_train", "pine_end": "antenna_coil"}
	var cache_inventory: Dictionary = (Game.data["inventory"] as Dictionary).duplicate()
	var caches_ok := 0
	for spot in cache_items:
		var cache: Node3D = world.get_node_or_null("GeneratedLevel/Finds/Find_%s" % spot)
		if cache == null:
			check(false, "a cache at %s" % spot)
			continue
		var before: int = Game.count(cache_items[spot])
		var meshes := cache.find_children("*", "MeshInstance3D", true, false).size()
		var refuses: bool = not cache.apply("cut", 26.0, cache.global_position + Vector3(1, 0, 0))
		for i in 4:
			if is_instance_valid(cache) and not cache.is_queued_for_deletion():
				cache.apply("smash", 34.0, cache.global_position + Vector3(1, 0, 0))
		if meshes >= 3 and refuses and Game.count(cache_items[spot]) == before + 1:
			caches_ok += 1
		else:
			check(false, "%s: %d meshes, refuses the cutter %s, gave %s" % [spot, meshes, refuses, cache_items[spot]])
	check(caches_ok == 6, "six caches (pump, camera, birdbox, junction box, hose reel, weather station): each smashes open with its part")
	Game.data["inventory"] = cache_inventory
	Game.inventory_changed.emit()

	print("== the build screen attaches tools (no fight kit)")
	var bpanel: Control = world.get_node("HUD/InventoryPanel")
	Game.add_tool("smasher")
	Game.add_tool("laser")
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	bpanel.toggle()
	await process_frame
	var attach_laser: Button = null
	for child in bpanel.items_list.get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text.begins_with("Laser"):
			attach_laser = child
	check(attach_laser != null and bpanel.find_child("KitRow", true, false) == null, "tools are buttons on the build screen, and the fight kit row is gone")
	if attach_laser != null:
		attach_laser.pressed.emit()
	await process_frame
	check(Game.data["equipped_tool"] == "laser", "pressing one attaches it (%s)" % Game.data["equipped_tool"])
	bpanel.toggle()
	Game.data["equipped_tool"] = "smasher"
	Game.inventory_changed.emit()
	await process_frame

	print("== F1 help: controls, testing notes, the map")
	var notes: Dictionary = load("res://scripts/ui/help_menu.gd").load_notes()
	var notes_ok: bool = notes.has("sprint") and (notes.get("items", []) as Array).size() >= 5
	for item in notes.get("items", []):
		notes_ok = notes_ok and item.has("title") and item.has("try") and item.has("ask")
	check(notes_ok, "playtest/testing_notes.json: a sprint and %d items, each with try and ask" % (notes.get("items", []) as Array).size())
	var help_hud: CanvasLayer = world.get_node("HUD")
	var help: CanvasLayer = help_hud.help_menu
	var help_ev := InputEventAction.new()
	help_ev.action = "help"
	help_ev.pressed = true
	Input.parse_input_event(help_ev)
	for i in 4:
		await process_frame
	check(help.is_open() and paused and help.tab == "Controls", "F1 / D-pad down opens Help on Controls, and the game waits")
	var next_tab := InputEventAction.new()
	next_tab.action = "cycle_tool"
	next_tab.pressed = true
	Input.parse_input_event(next_tab)
	for i in 3:
		await process_frame
	check(help.tab == "Testing notes" and help._content.get_child_count() >= 3, "LB / RB / Q switch to the testing notes")
	Input.parse_input_event(next_tab.duplicate())
	for i in 3:
		await process_frame
	var map_px: Vector2 = help.map_pixel(Vector3(0, 0, -8.6))
	check(help.tab == "Map" and absf(map_px.x - (46 + 42 * 9)) < 0.01 and absf(map_px.y - (46 + (96 - 8.6) * 9)) < 0.01, "and to the map, with the robot placed on it (door at %s px)" % map_px)
	var shut := InputEventAction.new()
	shut.action = "ui_cancel"
	shut.pressed = true
	Input.parse_input_event(shut)
	for i in 4:
		await process_frame
	check(not help.is_open() and not paused, "B / Esc closes it and play goes on")

	print("== resting through the night at a charger")
	var rest_hud: CanvasLayer = world.get_node("HUD")
	var rest_charger: Node3D = world.get_node("HouseCharger")
	var rest_day: int = Clock.day
	Clock.time = 0.9                                   # 21:36
	rest_charger.set("stored", 60.0)
	Energy.current = 20.0
	player.global_position = rest_charger.global_position + Vector3(1.2, 0.2, 0)
	for i in 3:
		await physics_frame
	rest_charger.dock(player)
	await process_frame
	check(rest_hud.asking() and paused, "docking at night asks: rest until morning?")
	rest_hud.answer(true)
	for i in 150:
		await process_frame
	check(Clock.day == rest_day + 1 and absf(Clock.time - 0.30) < 0.02 and Energy.current > 79.0, "yes: it's morning, day %d, battery %.0f" % [Clock.day, Energy.current])
	check(rest_hud.message_title.text.begins_with("Morning"), "and a card says so (%s)" % rest_hud.message_title.text)
	rest_hud.close_message()
	rest_charger.undock()
	Clock.time = 0.9
	rest_charger.set("stored", 60.0)
	rest_charger.dock(player)
	await process_frame
	check(rest_hud.asking(), "asked again the next night")
	rest_hud.answer(false)
	await process_frame
	check(not paused and Clock.time > 0.85 and bool(player.docked), "no: it just docks, still night")
	rest_charger.undock()
	Clock.time = 0.5
	rest_charger.dock(player)
	await process_frame
	check(not rest_hud.asking(), "by day docking asks nothing")
	rest_charger.undock()

	print("== F10 / F9 tuning, detector pillars, headlight tilt")
	var tune: Script = load("res://scripts/game/tuning.gd")
	tune.reset()
	var overlay_w: CanvasLayer = world.get_node("CoordOverlay")
	overlay_w.log_root = "res://.godot/test_playtest"
	var tune_log := "res://.godot/test_playtest/playtest/tuning.md"
	if FileAccess.file_exists(tune_log):
		DirAccess.remove_absolute(tune_log)
	var f10 := InputEventAction.new()
	f10.action = "tune_tools"
	f10.pressed = true
	Input.parse_input_event(f10)
	for i in 3:
		await process_frame
	var panel_t: CanvasLayer = overlay_w.tuning
	check(panel_t.is_open() and panel_t.panel_name == "tools" and not paused, "F10 opens the tool tuning panel, and the game keeps going")
	panel_t.set_slider("cutter_heat_seconds", 3.0)
	check(absf(tune.v("cutter_heat_seconds") - 3.0) < 0.001 and tune.is_tuned("cutter_heat_seconds"), "a slider changes the value live")
	Input.parse_input_event(f10.duplicate())
	for i in 3:
		await process_frame
	var logged := FileAccess.get_file_as_string(tune_log)
	check(not panel_t.is_open() and logged.contains("- **tune_1**") and logged.contains("cutter_heat_seconds") and logged.contains("=3.0*"), "closing it logs every value (tune_1, changed ones marked *)")
	check(tune.summary("tools", true).begins_with("cutter_heat_seconds"), "F3 can list just the changed values (%s)" % tune.summary("tools", true))
	tune.reset()
	var det2: Node = player.get_node("Detector")
	check(det2.strength(3.0) > det2.strength(40.0) + 0.3, "near finds glow clearly brighter than far ones (%.2f vs %.2f)" % [det2.strength(3.0), det2.strength(40.0)])
	player.global_position = world.get_node("GeneratedLevel/Finds/Find_gate_scrap").global_position + Vector3(0, 0.3, 2.0)
	for i in 10:
		await physics_frame
	det2._time = 100.0
	det2.scan()
	for i in 90:
		await process_frame
	check(det2.pillars_shown() >= 1, "far finds show as light pillars (%d)" % det2.pillars_shown())
	var pillar: MeshInstance3D = null
	for child in det2.get_children():
		if child is MeshInstance3D and child.visible:
			pillar = child
	var ground_ok := false
	if pillar != null:
		var bottom: float = pillar.global_position.y - pillar.scale.y * 0.5
		for sp in det2.spots:
			if absf((sp["pos"] as Vector3).x - pillar.global_position.x) < 0.01:
				ground_ok = absf(bottom - (sp["pos"] as Vector3).y) < 0.05
	check(ground_ok, "a pillar rises from the ground where the find is")
	var fx_head: Node3D = player.get_node("Visual/Head")
	var arm: Node3D = player.camera_arm
	var arm_before: float = arm.rotation.x
	arm.rotation.x = -0.35
	for i in 60:
		await physics_frame
	var level_x: float = fx_head.rotation.x
	arm.rotation.x = 0.3
	for i in 60:
		await physics_frame
	check(fx_head.rotation.x > level_x + 0.2 and fx_head.rotation.x < level_x + 0.35, "looking up tilts the head (and headlight) up a little (%.2f rad)" % (fx_head.rotation.x - level_x))
	arm.rotation.x = arm_before
	overlay_w.log_root = ""

	print("== pickups")
	var loose: Node = world.get_node("GeneratedLevel/Collectibles")
	if loose.get_child_count() == 0:
		loose = world.get_node("GeneratedHub/Collectibles")      # the forest's parts are all in caches now
	var pickup: Node3D = loose.get_child(0)
	var pickup_path := String(pickup.get_path())
	var pickup_item: String = pickup.item_id
	var pickup_count: int = Game.count(pickup_item) + 1
	player.global_position = pickup.global_position + Vector3(0, 0.2, 0)
	for i in 5:
		await physics_frame
	check(Game.count(pickup_item) == pickup_count, "touching a part puts it in the inventory (%s)" % pickup_item)
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
	check(Game.count(pickup_item) == pickup_count, "inventory kept through the shutdown")
	world.free()

	print("== the opening cutscene (New Game only)")
	for run in ["watch", "skip"]:
		Game.new_game()
		Game.play_intro = true
		world = load("res://scenes/world.tscn").instantiate()
		root.add_child(world)
		for i in 5:
			await process_frame
		player = world.get_node("Player")
		charger = world.get_node("HouseCharger")
		var intro: Node = world.get_node_or_null("OpeningCutscene")
		var board: Node3D = world.get_node("FallenBoard")
		check(intro != null and not Game.play_intro, "%s: New Game starts the cutscene" % run)
		check(player.shut_down and not world.get_node("HUD").visible and not player.camera.current, "%s: the robot sleeps, HUD hidden, a film camera" % run)
		check(board.global_position.y > 3.9 and player.iris_open == 0.0, "%s: a board lies across the roof, the iris is shut" % run)
		var saw_bird := false
		var saw_blink := false
		var intro_frames := 0
		if run == "skip":
			for i in 90:
				await process_frame
			var skip_ev := InputEventAction.new()
			skip_ev.action = "pause"
			skip_ev.pressed = true
			Input.parse_input_event(skip_ev)
		while is_instance_valid(intro) and not intro.done and intro_frames < 60 * 40:
			saw_bird = saw_bird or is_instance_valid(intro.bird)
			saw_blink = saw_blink or str(charger.bar_state()) == str([0, 0])
			await process_frame
			intro_frames += 1
		if run == "watch":
			check(saw_bird and saw_blink, "watch: the bird came, the charge bar showed one blinking ring (%d frames, %.1f s)" % [intro_frames, intro_frames / 60.0])
		else:
			check(intro_frames < 30, "skip: Esc ends it at once (%d frames)" % intro_frames)
		for i in 70:
			await process_frame
		check(board.global_position.y < 0.2 and board.global_position.distance_to(Vector3(1.45, 0.03, -1.4)) < 0.05, "%s: the board ends on the ground by the south wall" % run)
		check(not player.shut_down and player.camera.current and world.get_node("HUD").visible and Clock.running, "%s: control back: robot awake, own camera, HUD, clock" % run)
		check(absf(charger.stored - 60.0) < 1.0 and player.iris_open > 0.99 and Game.get_flag("intro_seen"), "%s: charger as the game expects, iris open, flag set" % run)
		check(not is_instance_valid(intro) and world.get_node_or_null("OpeningCutscene") == null, "%s: the cutscene is gone" % run)
		for i in 60:
			await process_frame
		check(Game.beat_seen("wake"), "%s: then the wake-up message" % run)
		world.free()

	print("== playtest notes (F3 / F4 ask for a note)")
	var log_dir := "res://.godot/test_playtest"
	for f in ["playtest/saves.md", "playtest/perf.md", "playtest/shots/save_77.jpg"]:
		if FileAccess.file_exists(log_dir.path_join(f)):
			DirAccess.remove_absolute(log_dir.path_join(f))
	var stand_in := Node3D.new()           # the overlay only needs a "player" to read a position from
	stand_in.add_to_group("player")
	root.add_child(stand_in)
	stand_in.global_position = Vector3(4.0, 0.0, -20.0)
	var overlay: CanvasLayer = load("res://scenes/ui/coord_overlay.tscn").instantiate()
	overlay.log_root = log_dir
	root.add_child(overlay)
	await process_frame
	var f3 := InputEventAction.new()
	f3.action = "save_position"
	f3.pressed = true
	Input.parse_input_event(f3)
	await process_frame
	check(overlay.note_open() and paused, "F3 opens the note box and pauses the game")
	var note_edit: LineEdit = overlay.get("_note_edit")
	note_edit.text = "  a tree floats here, like save_99  "
	note_edit.text_submitted.emit(note_edit.text)
	var saves_text := FileAccess.get_file_as_string(log_dir.path_join("playtest/saves.md"))
	check(not overlay.note_open() and not paused, "Enter closes the box and unpauses")
	check(saves_text.contains("- **save_1** —") and saves_text.contains("X    +4.0") and saves_text.contains("\n  - **Note:** a tree floats here, like save_99\n"),
		"the save and its trimmed note are on consecutive lines")
	Input.parse_input_event(f3)
	await process_frame
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	saves_text = FileAccess.get_file_as_string(log_dir.path_join("playtest/saves.md"))
	check(not overlay.note_open() and not paused and saves_text.contains("- **save_2** —"), "Esc still saves (save_2: a note naming save_99 doesn't skip numbers)")
	check(saves_text.split("\n", false)[-1].begins_with("- **save_2**"), "Esc writes no note line")
	paused = true
	Input.parse_input_event(f3)
	await process_frame
	check(not overlay.note_open(), "F3 does nothing while the game is paused by a menu")
	paused = false
	var f4 := InputEventAction.new()
	f4.action = "log_performance"
	f4.pressed = true
	Input.parse_input_event(f4)
	await process_frame
	check(not overlay.note_open(), "F4 measures first, no box yet")
	var perf_frames := 0
	while not overlay.note_open() and perf_frames < 60 * 8:
		await process_frame
		perf_frames += 1
	check(overlay.note_open() and paused and perf_frames >= 60 * 4, "F4 asks for its note after the 5 s sample (%d frames)" % perf_frames)
	note_edit.text = "fps drops by the ford"
	note_edit.text_submitted.emit(note_edit.text)
	var perf_text := FileAccess.get_file_as_string(log_dir.path_join("playtest/perf.md"))
	check(perf_text.contains("- **perf_1** —") and perf_text.contains(Engine.get_architecture_name()) and perf_text.contains("\n  - **Note:** fps drops by the ford"),
		"perf_1 carries the machine and the note")
	var fake_screen := Image.create(1920, 1080, false, Image.FORMAT_RGB8)
	fake_screen.fill(Color(0.3, 0.5, 0.2))
	var shot_rel: String = overlay.save_shot(fake_screen, "save_77")
	var shot := Image.load_from_file(ProjectSettings.globalize_path(log_dir.path_join(shot_rel))) if shot_rel != "" else null
	check(shot_rel == "playtest/shots/save_77.jpg" and shot != null and shot.get_width() == 1280 and shot.get_height() == 720,
		"F3's screenshot is saved as a 1280-wide jpg next to the logs (%s)" % shot_rel)
	overlay.free()
	stand_in.free()
	print("== the main menu: testing notes, help")
	var title_menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(title_menu)
	for i in 3:
		await process_frame
	var menu_notes: Dictionary = load("res://scripts/ui/help_menu.gd").load_notes()
	var listed: int = title_menu.notes_panel.find_child("Items", true, false).get_child_count()
	check(listed == (menu_notes.get("items", []) as Array).size(), "the testing notes are on the main menu (%d items)" % listed)
	var bar_text := ""
	for l in title_menu.find_child("HelpBar", true, false).find_children("*", "Label", true, false):
		bar_text += (l as Label).text + " "
	check(bar_text.contains("F1") and bar_text.contains("D-pad down"), "the main menu says F1 / D-pad down opens help (%s)" % bar_text.strip_edges())
	(title_menu.get_node("%NotesButton") as Button).pressed.emit()
	await process_frame
	check(title_menu.help_menu.is_open() and title_menu.help_menu.tab == "Testing notes", "Testing notes opens the full notes")
	title_menu.help_menu.close()
	(title_menu.get_node("%HelpButton") as Button).pressed.emit()
	await process_frame
	check(title_menu.help_menu.is_open() and title_menu.help_menu.tab == "Controls" and not title_menu.help_menu._tab_buttons["Map"].visible, "Help and controls opens help (no map before the game)")
	title_menu.help_menu.close()
	title_menu.queue_free()
	await process_frame
	_remove_test_files()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "PROBLEMS FOUND", failures])
	quit(0 if failures == 0 else 1)
