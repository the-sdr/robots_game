# Measures every asset the level map can place (bounds, low-branch spread)
# into level_design/build/assets.json. Re-run after adding an asset code:
#   <godot> --headless --path . -s tools/level_measure_assets.gd
extends SceneTree
const ASSETS := {
	"CommonTree_1": "res://assets/quaternius_nature/CommonTree_1.gltf",
	"CommonTree_2": "res://assets/quaternius_nature/CommonTree_2.gltf",
	"CommonTree_3": "res://assets/quaternius_nature/CommonTree_3.gltf",
	"CommonTree_4": "res://assets/quaternius_nature/CommonTree_4.gltf",
	"Pine_1": "res://assets/quaternius_nature/Pine_1.gltf",
	"Pine_2": "res://assets/quaternius_nature/Pine_2.gltf",
	"Pine_5": "res://assets/quaternius_nature/Pine_5.gltf",
	"TwistedTree_5": "res://assets/quaternius_nature/TwistedTree_5.gltf",
	"CommonTree_5": "res://assets/quaternius_nature/CommonTree_5.gltf",
	"DeadTree_1": "res://assets/quaternius_nature/DeadTree_1.gltf",
	"TwistedTree_2": "res://assets/quaternius_nature/TwistedTree_2.gltf",
	"TwistedTree_4": "res://assets/quaternius_nature/TwistedTree_4.gltf",
	"Rock_Medium_1": "res://assets/quaternius_nature/Rock_Medium_1.gltf",
	"Bush_Common": "res://assets/quaternius_nature/Bush_Common.gltf",
	"Bush_Common_Flowers": "res://assets/quaternius_nature/Bush_Common_Flowers.gltf",
	"Fern_1": "res://assets/quaternius_nature/Fern_1.gltf",
	"Flower_3_Group": "res://assets/quaternius_nature/Flower_3_Group.gltf",
	"Wall_UnevenBrick_Straight": "res://assets/quaternius_medieval/Wall_UnevenBrick_Straight.gltf",
	"Prop_Vine1": "res://assets/quaternius_medieval/Prop_Vine1.gltf",
	"Prop_Vine2": "res://assets/quaternius_medieval/Prop_Vine2.gltf",
	"RockPath_Round_Wide": "res://assets/quaternius_nature/RockPath_Round_Wide.gltf",
	"Building_Small_1": "res://assets/quaternius_city/Building_Small_1.gltf",
	"Building_Medium_2_001": "res://assets/quaternius_city/Building_Medium_2_001.gltf",
	"Building_Large_2": "res://assets/quaternius_city/Building_Large_2.gltf",
	"Rock_Medium_2": "res://assets/quaternius_nature/Rock_Medium_2.gltf",
	"Rock_Medium_3": "res://assets/quaternius_nature/Rock_Medium_3.gltf",
	"RockPath_Round_Small_1": "res://assets/quaternius_nature/RockPath_Round_Small_1.gltf",
	"RockPath_Round_Small_2": "res://assets/quaternius_nature/RockPath_Round_Small_2.gltf",
	"RockPath_Round_Small_3": "res://assets/quaternius_nature/RockPath_Round_Small_3.gltf",
	"Flower_4_Group": "res://assets/quaternius_nature/Flower_4_Group.gltf",
	"Flower_4_Single": "res://assets/quaternius_nature/Flower_4_Single.gltf",
	"Grass_Common_Short": "res://assets/quaternius_nature/Grass_Common_Short.gltf",
	"Grass_Common_Tall": "res://assets/quaternius_nature/Grass_Common_Tall.gltf",
	"Grass_Wispy_Short": "res://assets/quaternius_nature/Grass_Wispy_Short.gltf",
	"Grass_Wispy_Tall": "res://assets/quaternius_nature/Grass_Wispy_Tall.gltf",
	"Plant_1": "res://assets/quaternius_nature/Plant_1.gltf",
	"Plant_7": "res://assets/quaternius_nature/Plant_7.gltf",
	"Mushroom_Common": "res://assets/quaternius_nature/Mushroom_Common.gltf",
	"Mushroom_Laetiporus": "res://assets/quaternius_nature/Mushroom_Laetiporus.gltf",
	"Wall_UnevenBrick_Door_Round": "res://assets/quaternius_medieval/Wall_UnevenBrick_Door_Round.gltf",
	"Stairs_Exterior_Straight": "res://assets/quaternius_medieval/Stairs_Exterior_Straight.gltf",
	"Wall_Arch": "res://assets/quaternius_medieval/Wall_Arch.gltf",
	"Prop_MetalFence_Simple": "res://assets/quaternius_medieval/Prop_MetalFence_Simple.gltf",
	"Prop_MetalFence_Ornament": "res://assets/quaternius_medieval/Prop_MetalFence_Ornament.gltf",
	"Prop_WoodenFence_Single": "res://assets/quaternius_medieval/Prop_WoodenFence_Single.gltf",
	"Prop_Crate": "res://assets/quaternius_medieval/Prop_Crate.gltf",
	"Prop_Wagon": "res://assets/quaternius_medieval/Prop_Wagon.gltf",
	"Wall_Plaster_Straight": "res://assets/quaternius_medieval/Wall_Plaster_Straight.gltf",
	"Roof_Tower_RoundTiles": "res://assets/quaternius_medieval/Roof_Tower_RoundTiles.gltf",
	"DeadTree_2": "res://assets/quaternius_nature/DeadTree_2.gltf",
	"Prop_Bollard": "res://assets/quaternius_city/Prop_Bollard.gltf",
	"Prop_Planter_Single": "res://assets/quaternius_city/Prop_Planter_Single.gltf",
	"Prop_ACUnit": "res://assets/quaternius_city/Prop_ACUnit.gltf",
	"Entrance_Concrete_2x2": "res://assets/quaternius_city/Entrance_Concrete_2x2.gltf",
	"Stairs_Entrance_Concrete": "res://assets/quaternius_city/Stairs_Entrance_Concrete.gltf",
	"Metal_Column_Center": "res://assets/quaternius_city/Metal_Column_Center.gltf",
}
func walk(n: Node, xf: Transform3D, out: Dictionary) -> void:
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		out.meshes += 1
		for s in m.get_surface_count():
			for v in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = t * v
				out.lo = out.lo.min(w); out.hi = out.hi.max(w)
				if w.y < 4.3: out.low_r = max(out.low_r, Vector2(w.x, w.z).length())
				if w.y < 3.0: out.r3 = max(out.r3, Vector2(w.x, w.z).length())
	for c in n.get_children(): walk(c, t, out)
func _initialize() -> void:
	var result := {}
	for k in ASSETS:
		var d := {"lo": Vector3(1e9, 1e9, 1e9), "hi": Vector3(-1e9, -1e9, -1e9), "low_r": 0.0, "r3": 0.0, "meshes": 0}
		if not ResourceLoader.exists(ASSETS[k]):
			print("MISSING ", k, " ", ASSETS[k])
			continue
		walk(load(ASSETS[k]).instantiate(), Transform3D(), d)
		result[k] = {"path": ASSETS[k], "min": [d.lo.x, d.lo.y, d.lo.z], "max": [d.hi.x, d.hi.y, d.hi.z], "spread_below_house_roof": d.low_r, "spread_below_3m": d.r3, "mesh_instances": d.meshes}
	var f := FileAccess.open("res://level_design/build/assets.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	for k in result: print(k, " meshes ", result[k].mesh_instances, " min ", result[k].min, " max ", result[k].max)
	quit()
