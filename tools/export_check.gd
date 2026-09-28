extends SceneTree

# Boots an exported build's game data headlessly and loads the world from it:
#   cd <empty folder> && godot --headless --main-pack "<Robots Beta.exe or .pck>" -s <abs path>/tools/export_check.gd
# Run it from an EMPTY folder: from the project folder res:// falls back to the
# real files and hides what the export left out.

func _initialize() -> void:
	await process_frame
	create_timer(120.0).timeout.connect(func() -> void: print("EXPORT CHECK: TIMEOUT"); quit(2))
	var game: Node = root.get_node("Game")
	game.new_game()
	var world: Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	for i in 30:
		await physics_frame
	var trees: int = world.get_node("GeneratedLevel/Trees").get_child_count()
	var models: bool = world.get_node("GeneratedLevel/Trees").get_child(0).get_child_count() > 1
	var hub: int = world.get_node("GeneratedHub/Props").get_child_count()
	var tools_left_out: bool = not ResourceLoader.exists("res://tools/systems_test.gd")
	var name: String = String(ProjectSettings.get_setting_with_override("application/config/name"))
	var ok: bool = trees > 100 and models and hub > 50 and tools_left_out and name == "Robots Beta"
	print("EXPORT CHECK: %s | name %s | trees %d (models %s) | hub props %d | tools left out %s" % ["OK" if ok else "FAILED", name, trees, models, hub, tools_left_out])
	quit(0 if ok else 1)
