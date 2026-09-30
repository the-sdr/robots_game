extends Control

# Tab: what the robot carries and what it can build, anywhere (it crafts on
# itself). Left column: parts. Right column: recipes with have/need counts.

@onready var items_list: VBoxContainer = %ItemsList
@onready var recipes_list: VBoxContainer = %RecipesList
@onready var detail_label: Label = %DetailLabel

@onready var close_button: Button = %CloseButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.inventory_changed.connect(_refresh)
	close_button.pressed.connect(toggle)

# The player is paused while this is open, so Tab and Esc are handled here.
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("pause")):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()
	for child in recipes_list.get_children():
		child.queue_free()
	var inventory: Dictionary = Game.data["inventory"]
	if inventory.is_empty() and Game.data["tools"].is_empty():
		var empty := Label.new()
		empty.text = "Nothing yet."
		items_list.add_child(empty)
	for tool_id in Game.data["tools"]:
		var row := Label.new()
		row.text = "%s  (tool%s)" % [Catalog.tool_name(tool_id), ", attached" if Game.data["equipped_tool"] == tool_id else ""]
		items_list.add_child(row)
	var ids: Array = inventory.keys()
	ids.sort()
	for id in ids:
		var row := Label.new()
		row.text = "%s  x%d" % [Catalog.item_name(id), inventory[id]]
		row.tooltip_text = String(Catalog.ITEMS.get(id, {}).get("description", ""))
		items_list.add_child(row)
	for recipe_id in Catalog.RECIPES:
		var recipe: Dictionary = Catalog.RECIPES[recipe_id]
		var blocker := Game.craft_blocker(recipe_id)
		if blocker == "Not understood yet":
			continue
		var button := Button.new()
		var parts: Array[String] = []
		for id in recipe["needs"]:
			parts.append("%s %d/%d" % [Catalog.item_name(id), Game.count(id), recipe["needs"][id]])
		button.text = "%s   [%s]" % [recipe["name"], ", ".join(parts)]
		button.disabled = blocker != ""
		button.tooltip_text = recipe.get("description", "") if blocker == "" else blocker
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_craft.bind(recipe_id))
		button.mouse_entered.connect(func() -> void: detail_label.text = String(recipe.get("description", "")))
		recipes_list.add_child(button)

func _craft(recipe_id: String) -> void:
	if Game.craft(recipe_id):
		var recipe: Dictionary = Catalog.RECIPES[recipe_id]
		get_tree().call_group("hud", "show_notice", "Built: %s" % recipe["name"])
		detail_label.text = "Built the %s." % recipe["name"]
		_refresh()
