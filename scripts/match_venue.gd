extends "res://scripts/preview_court.gd"

const NAMES := ["Falcons Gym", "Grass Park", "City Stadium"]
const Gym = preload("res://scripts/tryout_gym.gd")
var stadium := false

static func build(world: Node3D, venue: int, attendance: int) -> Node3D:
	var court
	if venue == 0:
		Gym.light_gym(world)
		court = Gym.new()
	else:
		court = new()
		court.stadium = venue == 2
		add_preview_lighting(world)
		var env: WorldEnvironment
		for node in world.get_children():
			if node is WorldEnvironment:
				env=node
				break
		if env:
			var sky := Sky.new()
			var palette := ProceduralSkyMaterial.new()
			palette.sky_top_color = Color("527fa9") if venue == 1 else Color("162744")
			palette.sky_horizon_color = Color("c8dacf") if venue == 1 else Color("748ca6")
			sky.sky_material = palette
			env.environment.sky = sky
			env.environment.background_mode = Environment.BG_SKY
			env.environment.ambient_light_energy = .8
	world.add_child(court)
	if attendance > 0: populate(court,venue,attendance)
	return court

func build_enclosure() -> void:
	var grass := material("688c49")
	if not stadium:
		box("Park grounds",Vector3(350,.08,350),Vector3(0,-.22,4),material("628249"))
	var surface := material("348087") if stadium else grass
	get_node("Runoff").material_override = material("364956") if stadium else material("608047")
	for i in 30: get_node("Floorboard%d" % i).material_override = surface
	var seat := material("385770") if stadium else material("80654c")
	for side in [-1,1]:
		for row in (8 if stadium else 3):
			var x: float = side*(11.8+row*.78)
			var top := .49+row*.39
			box("Terrace",Vector3(.74,top,32),Vector3(x,top*.5,4),seat)
		if stadium:
			for end in [-1,1]:
				var z: float = 4+end*14.6
				box("Floodlight mast",Vector3(.18,9,.18),Vector3(side*12.6,4.5,z),material("788997"))
				var lamp := material("fff6d5")
				lamp.emission_enabled=true
				lamp.emission=Color("fff4ce")
				box("Floodlights",Vector3(2.4,.64,.3),Vector3(side*12.6,9,z),lamp)
	if stadium:
		for end in [-1,1]:
			for row in 5:
				var top := .6+row*.45
				box("End stand",Vector3(22,top,.85),Vector3(0,top*.5,4+end*(14.8+row*.86)),seat)
	else:
		for i in 24:
			var x := (-1 if i%2==0 else 1)*(21+i%4)
			var z := -20.+(i/2)*4.4
			box("Tree trunk",Vector3(.38,2.6,.38),Vector3(x,1.3,z),material("615246"))
			var crown := MeshInstance3D.new()
			var leaf := SphereMesh.new()
			leaf.radius=2.+.18*(i%3)
			leaf.height=5.+.3*(i%3)
			crown.mesh=leaf
			crown.material_override=material("456747" if i%3 else "557651")
			crown.position=Vector3(x,4.,z)
			add_child(crown)

static func populate(court: Node3D, venue: int, count: int) -> void:
	# One seated in-game fan is photographed in three shirt colors. Cards share textures.
	var textures: Array = []
	for n in 3: textures.append(load("res://assets/menu/match/fan%d.png" % n))
	for i in count:
		var side := -1 if i%2==0 else 1
		var seat: int = i/2
		var row := (seat / 16) % (4 if venue == 0 else 3)
		var z := -8.5 + ((seat*7+row*3)%16)*1.48
		var person := Sprite3D.new()
		person.name = "Spectator%d" % i
		person.texture = textures[(seat+side+4)%3]
		person.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		person.double_sided = true
		person.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		person.pixel_size = .0064
		person.position = Vector3(side*(11.62+row*(.69 if venue==0 else .78)),.82+row*.38,z)
		court.add_child(person)
