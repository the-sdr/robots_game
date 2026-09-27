# Measures every asset the level map can place (bounds, low-branch spread)
# into level_design/build/assets.json. Re-run after adding an asset code:
#   <godot> --headless --path . -s tools/level_measure_assets.gd
extends SceneTree
const ASSETS := {
	"CommonTree_1": "res://assets/quaternius_nature/CommonTree_1.gltf",
	"CommonTree_3": "res://assets/quaternius_nature/CommonTree_3.gltf",
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
		walk(load(ASSETS[k]).instantiate(), Transform3D(), d)
		result[k] = {"path": ASSETS[k], "min": [d.lo.x, d.lo.y, d.lo.z], "max": [d.hi.x, d.hi.y, d.hi.z], "spread_below_house_roof": d.low_r, "spread_below_3m": d.r3, "mesh_instances": d.meshes}
	var f := FileAccess.open("res://level_design/build/assets.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	for k in result: print(k, " meshes ", result[k].mesh_instances, " min ", result[k].min, " max ", result[k].max)
	quit()
