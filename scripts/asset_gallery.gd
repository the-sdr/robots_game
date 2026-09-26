extends Node3D

const NATURE_DIR := "res://assets/quaternius_nature/"
const BUILDINGS_DIR := "res://assets/quaternius_buildings/Finished Textured Buildings/FBX/"
const PARTS_DIR := "res://assets/quaternius_buildings/Base Modular Parts/FBX/"

const ROW_SPACING := 6.0
const DEFAULT_ITEM_SPACING := 4.0

const MANIFEST := [
	{"row": "Canopy Trees - Common", "dir": NATURE_DIR, "ext": ".gltf", "items": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]},
	{"row": "Canopy Trees - Twisted", "dir": NATURE_DIR, "ext": ".gltf", "items": ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"]},
	{"row": "Conifers / Dead", "dir": NATURE_DIR, "ext": ".gltf", "items": ["Pine_1", "Pine_3", "DeadTree_1", "DeadTree_3"]},
	{"row": "Undergrowth", "dir": NATURE_DIR, "ext": ".gltf", "items": ["Bush_Common", "Bush_Common_Flowers", "Fern_1"]},
	{"row": "Ground Cover", "dir": NATURE_DIR, "ext": ".gltf", "items": ["Grass_Common_Short", "Grass_Wispy_Tall", "Clover_1", "Clover_2", "Flower_3_Group", "Flower_4_Group"]},
	{"row": "Detail & Path", "dir": NATURE_DIR, "ext": ".gltf", "items": ["Mushroom_Common", "Mushroom_Laetiporus", "Rock_Medium_1", "Rock_Medium_2", "Pebble_Round_1", "RockPath_Round_Wide", "RockPath_Square_Wide"]},
	{"row": "Small Houses (starting building candidates)", "dir": BUILDINGS_DIR, "ext": ".fbx", "items": ["1Story", "1Story_GableRoof", "1Story_RoundRoof", "1Story_Sign"], "spacing": 14.0, "scale": 2.5},
	{"row": "Doors & Windows", "dir": PARTS_DIR, "ext": ".fbx", "items": ["Door1", "Door2", "Door3", "Door4", "Door5", "Door_Double", "Door_Window", "Window", "Window_Double"], "spacing": 6.0, "scale": 2.5},
]

func _ready() -> void:
	for row_index in MANIFEST.size():
		var row_data: Dictionary = MANIFEST[row_index]
		var items: Array = row_data["items"]
		var dir: String = row_data["dir"]
		var ext: String = row_data["ext"]
		var spacing: float = row_data.get("spacing", DEFAULT_ITEM_SPACING)
		var row_z := float(row_index) * ROW_SPACING

		add_child(_make_label(row_data["row"], Vector3(-spacing, 2.8, row_z), 64, Color(0.6, 0.85, 1.0)))

		for item_index in items.size():
			var item_name: String = items[item_index]
			var path := dir + item_name + ext
			if not ResourceLoader.exists(path):
				push_warning("Missing asset: %s" % path)
				continue

			var scene: PackedScene = load(path)
			var instance := scene.instantiate()
			add_child(instance)
			var x := float(item_index) * spacing
			instance.position = Vector3(x, 0, row_z)
			var item_scale: float = row_data.get("scale", 1.0)
			instance.scale = Vector3.ONE * item_scale

			add_child(_make_label(item_name, Vector3(x, 2.0, row_z + 1.2), 40, Color(1, 1, 0.6)))

func _make_label(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 10
	return label
