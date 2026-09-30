extends Breakable

# Something that survived out here with a part still inside (owner, 2026-09-30:
# "a world of crates makes little sense ... what would survive in this world
# that's smashable and have the item of value inside"). Each model belongs to
# its place and holds its part for a reason:
#   pump       the pump that kept the spring running   -> its motor (servo)
#   camera     a fallen security camera at the hatch   -> its lens
#   birdbox    a birdbox a magpie lined with shiny bits -> a power cell
#   junction   a junction box bolted under the Giant    -> a circuit board
#   hose_reel  the greenhouse's hose reel               -> its winding gears
#   weather    a weather station in the pines           -> its antenna coil
#   toolbox    a toolbox someone dropped and never found -> whatever was in it
# Built from primitives here (look and collision), so a design only names the
# model. Smash it open; like every Breakable with drops, the detector senses it.

const MODELS := {
	"pump": {"name": "the old pump", "health": 50.0, "debris": Color(0.3, 0.42, 0.38),
		"notice": "A rusted pump that kept the spring running. Its casing is cracked: a good smash would open it."},
	"camera": {"name": "the camera", "health": 30.0, "debris": Color(0.35, 0.36, 0.38),
		"notice": "A security camera that watched the hatch. It's still looking. A smash would crack it open."},
	"birdbox": {"name": "the birdbox", "health": 20.0, "debris": Color(0.45, 0.32, 0.2),
		"notice": "A fallen birdbox. Something shiny glints through the hole: magpies. The old wood would give way."},
	"junction": {"name": "the junction box", "health": 70.0, "debris": Color(0.3, 0.33, 0.3),
		"notice": "A junction box bolted under the Giant. Cables still run into it. It will take some bashing."},
	"hose_reel": {"name": "the hose reel", "health": 35.0, "debris": Color(0.25, 0.45, 0.2),
		"notice": "The greenhouse's hose reel. Its winding gear is stuck fast inside the drum."},
	"toolbox": {"name": "the toolbox", "health": 40.0, "debris": Color(0.7, 0.18, 0.12),
		"notice": "A rusted toolbox, lid seized shut. A good bash would pop it."},
	"weather": {"name": "the weather station", "health": 30.0, "debris": Color(0.85, 0.85, 0.8),
		"notice": "A weather station, still counting the wind. Its little white box would crack open."},
}

@export var model: String = "pump"

var _materials := {}

func _ready() -> void:
	var info: Dictionary = MODELS.get(model, MODELS["pump"])
	effects = PackedStringArray(["smash"])
	display_name = info["name"]
	hit_notice = info["notice"]
	debris_colour = info["debris"]
	chunk_count = 6
	if health == 100.0:                      # Breakable's default: take the model's
		health = info["health"]
	_build()
	super._ready()

func _mat(key: String, colour: Color, metal: float = 0.2, rough: float = 0.8, glow: Color = Color.BLACK) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metal
	m.roughness = rough
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 0.8
	_materials[key] = m
	return m

func _part(mesh: Mesh, material: Material, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.rotation = rot
	add_child(mi)
	return mi

func _box(size: Vector3, material: Material, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part(b, material, at, rot)

func _cyl(radius: float, height: float, material: Material, at: Vector3, rot: Vector3 = Vector3.ZERO, sides: int = 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	return _part(c, material, at, rot)

func _collision(size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	add_child(shape)

func _build() -> void:
	var rust := _mat("rust", Color(0.45, 0.28, 0.16), 0.5, 0.8)
	var dark := _mat("dark", Color(0.16, 0.17, 0.18), 0.6, 0.5)
	match model:
		"pump":
			var paint := _mat("paint", Color(0.25, 0.42, 0.38), 0.3, 0.7)
			_box(Vector3(0.7, 0.5, 0.5), paint, Vector3(0, 0.25, 0))
			_box(Vector3(0.3, 0.2, 0.52), rust, Vector3(0.18, 0.12, 0))                      # rust bloom
			_cyl(0.09, 0.6, dark, Vector3(-0.55, 0.12, 0), Vector3(0, 0, PI * 0.5))           # the pipe to the spring
			_cyl(0.2, 0.04, rust, Vector3(0, 0.56, 0))                                         # the handwheel
			_cyl(0.03, 0.12, dark, Vector3(0, 0.62, 0))
			_collision(Vector3(0.75, 0.55, 0.55), Vector3(0, 0.27, 0))
		"camera":
			var post := _cyl(0.05, 1.5, dark, Vector3(0.35, 0.5, 0), Vector3(0, 0, 0.9))       # leaning where it fell
			post.name = "Post"
			var housing := _mat("housing", Color(0.75, 0.76, 0.72), 0.3, 0.6)
			_box(Vector3(0.5, 0.26, 0.28), housing, Vector3(-0.2, 0.42, 0), Vector3(0, 0, 0.25))
			_box(Vector3(0.56, 0.04, 0.34), housing, Vector3(-0.2, 0.58, 0), Vector3(0, 0, 0.25))   # sun hood
			_cyl(0.08, 0.06, _mat("lens", Color(0.05, 0.08, 0.12), 0.9, 0.1, Color(0.2, 0.5, 0.9)), Vector3(-0.47, 0.35, 0), Vector3(0, 0, PI * 0.5 + 0.25))
			_collision(Vector3(1.0, 0.7, 0.4), Vector3(0, 0.35, 0))
		"birdbox":
			var bark := _mat("bark", Color(0.3, 0.22, 0.15), 0.0, 1.0)
			var wood := _mat("wood", Color(0.5, 0.36, 0.22), 0.0, 0.9)
			_cyl(0.28, 0.45, bark, Vector3(0, 0.225, 0))                                       # the stump it landed on
			_box(Vector3(0.34, 0.4, 0.34), wood, Vector3(0, 0.65, 0), Vector3(0, 0.2, 0.12))
			_box(Vector3(0.44, 0.03, 0.26), wood, Vector3(-0.1, 0.9, 0), Vector3(0, 0.2, 0.62))    # roof
			_box(Vector3(0.44, 0.03, 0.26), wood, Vector3(0.1, 0.88, 0), Vector3(0, 0.2, -0.45))
			_cyl(0.05, 0.02, _mat("hole", Color(0.02, 0.02, 0.02), 0.0, 1.0), Vector3(0.03, 0.7, 0.18), Vector3(PI * 0.5, 0.2, 0))
			_part(_glint_mesh(), _mat("glint", Color(0.9, 0.9, 0.6), 0.9, 0.2, Color(1.0, 0.9, 0.5)), Vector3(0.03, 0.66, 0.16))
			_collision(Vector3(0.6, 0.95, 0.6), Vector3(0, 0.47, 0))
		"junction":
			var steel := _mat("steel", Color(0.32, 0.36, 0.33), 0.6, 0.55)
			_box(Vector3(0.7, 1.0, 0.36), steel, Vector3(0, 0.5, 0))
			_box(Vector3(0.72, 0.08, 0.38), _mat("hazard", Color(0.9, 0.7, 0.1), 0.2, 0.6), Vector3(0, 0.85, 0))
			_box(Vector3(0.05, 0.16, 0.05), dark, Vector3(0.25, 0.5, 0.2))                     # handle
			for i in 3:
				_cyl(0.03, 0.5, dark, Vector3(-0.2 + i * 0.2, 0.0, -0.1), Vector3(0.3, 0, 0))     # cables into the ground
			_collision(Vector3(0.75, 1.0, 0.42), Vector3(0, 0.5, 0))
		"hose_reel":
			var green := _mat("hose", Color(0.2, 0.5, 0.2), 0.0, 0.7)
			for side in [-0.26, 0.26]:
				_box(Vector3(0.05, 0.7, 0.4), rust, Vector3(side, 0.35, 0))
			_cyl(0.26, 0.48, rust, Vector3(0, 0.45, 0), Vector3(0, 0, PI * 0.5))
			for i in 3:
				var coil := TorusMesh.new()
				coil.inner_radius = 0.24
				coil.outer_radius = 0.31
				_part(coil, green, Vector3(-0.15 + i * 0.15, 0.45, 0), Vector3(0, 0, PI * 0.5))
			_cyl(0.025, 0.25, dark, Vector3(0.36, 0.55, 0), Vector3(0, 0, PI * 0.5))            # crank
			_collision(Vector3(0.65, 0.8, 0.7), Vector3(0, 0.4, 0))
		"toolbox":
			var red := _mat("red", Color(0.62, 0.15, 0.1), 0.5, 0.6)
			_box(Vector3(0.6, 0.3, 0.3), red, Vector3(0, 0.12, 0), Vector3(0.08, 0.3, 0.1))       # half sunk, tilted
			_box(Vector3(0.62, 0.05, 0.32), rust, Vector3(0.01, 0.28, 0.01), Vector3(0.08, 0.3, 0.1))
			_cyl(0.02, 0.3, dark, Vector3(0.02, 0.36, 0.02), Vector3(0.08, 0.3, PI * 0.5 + 0.1))       # handle
			_collision(Vector3(0.65, 0.4, 0.4), Vector3(0, 0.18, 0))
		"weather":
			var white := _mat("white", Color(0.88, 0.88, 0.84), 0.0, 0.7)
			_cyl(0.05, 1.7, dark, Vector3(0, 0.85, 0))
			_box(Vector3(0.42, 0.46, 0.36), white, Vector3(0, 0.95, 0.12))                       # the louvred box
			for i in 4:
				_box(Vector3(0.44, 0.02, 0.02), dark, Vector3(0, 0.8 + i * 0.1, 0.31))
			for i in 3:
				var a := TAU * i / 3.0
				_cyl(0.012, 0.3, dark, Vector3(cos(a) * 0.15, 1.72, sin(a) * 0.15), Vector3(0, -a, PI * 0.5))
				var cup := SphereMesh.new()
				cup.radius = 0.05
				cup.height = 0.1
				_part(cup, white, Vector3(cos(a) * 0.3, 1.72, sin(a) * 0.3))
			_collision(Vector3(0.5, 1.2, 0.5), Vector3(0, 0.6, 0.06))

func _glint_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.03
	s.height = 0.06
	return s
