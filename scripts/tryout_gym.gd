extends "res://scripts/preview_court.gd"

const Contacts = preload("res://scripts/gym_physics.gd")
const FRONT_BENCH_X := 11.8
var rear_extension := 0.0
var brace_transforms: Array[Transform3D]=[]
var digits: Array[Array] = []
var benches: Array[MeshInstance3D] = []

func box(label_: String,size_: Vector3,center: Vector3,style: Material) -> MeshInstance3D:
	var part := super.box(label_,size_,center,style)
	if label_ in ["Runoff","North wall","South wall","Side masonry","Ceiling","Bleacher bench","Folding support","LeftPostPadding","RightPostPadding"]:
		var shape := BoxShape3D.new()
		shape.size = size_
		Contacts.solid(part,shape,Contacts.GYM)
	if label_=="Bleacher bench": benches.append(part)
	return part

func _ready() -> void:
	super()
	# One continuous collider matches the visible maple instead of leaving a
	# six-centimetre gap above the lower runoff collider.
	var deck := Node3D.new()
	add_child(deck)
	deck.position = Vector3(0,0.01,4)
	var deck_shape := BoxShape3D.new()
	deck_shape.size = Vector3(9,0.06,18)
	Contacts.solid(deck,deck_shape,Contacts.GYM)
	var maple := ShaderMaterial.new()
	maple.shader = preload("res://assets/gym/maple.gdshader")
	maple.set_shader_parameter("crest",preload("res://assets/gym/falcon.svg"))
	get_node("Runoff").material_override = maple
	for i in 30: get_node("Floorboard%d" % i).material_override = maple
	var block := ShaderMaterial.new()
	block.shader = preload("res://assets/gym/masonry.gdshader")
	var paint := material("385545")
	var wood := ShaderMaterial.new()
	wood.shader=preload("res://assets/gym/bleacher_wood.gdshader")
	var steel := material("535951")
	var white := material("e7dfc9")
	box("North wall",Vector3(34,9,0.3),Vector3(0,4.4,19.8),block)
	box("South wall",Vector3(34,9,0.3),Vector3(0,4.4,-16-rear_extension),block)
	box("Ceiling",Vector3(34,0.2,36+rear_extension),Vector3(0,9,2-rear_extension*.5),white)
	for side in [-1,1]:
		box("Side masonry",Vector3(0.25,9,36+rear_extension),Vector3(side*16.3,4.4,2-rear_extension*.5),block)
		for row in 4:
			var x: float = side*(FRONT_BENCH_X+row*0.69)
			box("Bleacher bench",Vector3(0.65,0.15,27),Vector3(x,0.48+row*0.37,3),wood)
			var height := .48+row*.37
			box("Seat front lip",Vector3(.037,.036,26.98),Vector3(x-side*.312,height+.048,3),wood)
			box("Seat underframe",Vector3(.06,.085,26.96),Vector3(x,height-.115,3),steel)
			for z in [-9,-5,-1,3,7,11,15]:
				box("Bleacher foot plate",Vector3(.30,.028,.22),Vector3(x,.018,z),steel)
				brace(Vector3(x,.10,z),Vector3(x,height-.1,z+.75),.045,steel)
				box("Folding support",Vector3(0.1,0.45+row*0.37,0.1),Vector3(x,(0.45+row*0.37)/2,z),steel)
	for dir in [-1,1]:
		var z := 19.57 if dir==1 else -15.8-rear_extension
		box("Painted stripe",Vector3(32.5,0.42,0.08),Vector3(0,3.1,z),paint)
		for i in 5:
			var x := (i-2)*3.4
			box("Championship felt",Vector3(1.5,2.3,0.07),Vector3(x,5.5,z-dir*0.10),paint)
			var label := Label3D.new()
			label.text = "VARSITY\n\u25c6\n%d" % (2006+i*3)
			label.font_size = 40
			label.pixel_size = 0.0068
			label.position = Vector3(x,5.5,z-dir*0.16)
			if dir==1: label.rotation.y = PI
			add_child(label)
	for z in [-13,-8,-3,2,7,12,17]:
		box("Roof steel",Vector3(32.6,0.2,0.18),Vector3(0,8.55,z),steel)
		box("Truss lower chord",Vector3(32.4,.09,.10),Vector3(0,7.91,z),steel)
		for bay in 10:
			var x := -16.2+bay*3.24
			brace(Vector3(x,8.52,z),Vector3(x+1.62,7.94,z),.06,steel)
			brace(Vector3(x+1.62,7.94,z),Vector3(x+3.24,8.52,z),.06,steel)
		for x in [-5,5]:
			box("Fixture suspension",Vector3(.035,.14,.035),Vector3(x,8.46,z),steel)
			box("Fluorescent bank",Vector3(2.8,0.1,0.32),Vector3(x,8.38,z),material("fff3cc"))


	var padding := material("314e41")
	for i in 12:
		box("Wall pad",Vector3(0.88,1.95,0.16),Vector3((i-5.5)*0.92,1.0,19.43),padding)
	box("Scoreboard",Vector3(3.8,1.45,0.18),Vector3(0,3.85,19.41),material("26352e"))
	wall_text("SETS       GOAL",Vector3(0,4.19,19.29),0.003,Color.FLORAL_WHITE)
	for x in [1.11,.70,-.70,-1.11]: add_digit(float(x))
	update_board(0)
	for x in [-8.2,8.2]:
		box("Gym exit",Vector3(2.1,2.4,0.14),Vector3(x,1.2,19.42),material("656f61"))
		box("Door rail",Vector3(1.8,0.06,0.12),Vector3(x,1.1,19.3),steel)
		wall_text("EXIT",Vector3(x,2.67,19.32),0.003,Color.PALE_GREEN)
	build_gallery(steel,paint)
	var steel_web := MultiMesh.new()
	steel_web.transform_format=MultiMesh.TRANSFORM_3D
	steel_web.mesh=BoxMesh.new()
	steel_web.instance_count=brace_transforms.size()
	for i in brace_transforms.size(): steel_web.set_instance_transform(i,brace_transforms[i])
	var webs := MultiMeshInstance3D.new()
	webs.multimesh=steel_web
	webs.material_override=steel
	add_child(webs)
	brace_transforms.clear()
	for side in [-1,1]:
		var crest := Sprite3D.new()
		crest.texture = preload("res://assets/gym/falcon.svg")
		crest.pixel_size = .0065
		crest.position = Vector3(side*16.02,4.35,2.1)
		crest.rotation.y = -side*PI*.5
		crest.shaded = true
		add_child(crest)
	wall_text("F A L C O N S",Vector3(0,7.47,19.45),.010,Color("264939"))
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0,3,2)
	probe.size = Vector3(33,11,38+rear_extension)
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.65
	add_child(probe)

func seat_teammates(create_player: Callable, profile: Callable = Callable()) -> Array:
	var occupied := []
	var seats := [[-1,1,-3.0],[1,0,-1.1],[-1,1,0.9],[1,0,1.4],[-1,2,3.3],[1,1,4.2],[-1,0,5.5],[1,2,6.0],[-1,2,7.8],[1,1,8.0]]
	for i in seats.size():
		var seat: Array = seats[i]
		var side := int(seat[0])
		var row := int(seat[1])
		var athlete_: Node3D = create_player.call(Vector3(side*(FRONT_BENCH_X+row*.69),0,float(seat[2])),["245447","a34d31","334357"][i%3])
		if profile.is_valid(): profile.call(athlete_,20+i)
		athlete_.set_height_cm(172+(i*7)%29)
		preload("res://scripts/practice_kit.gd").apply(athlete_,false,20+i)
		athlete_.rotation.y = -side*PI/2
		athlete_.play_action("base/Sitting_Talking",0)
		athlete_.animator.seek(i*.31,true)
		var idx := (4 if side==1 else 0)+row
		var constraint := preload("res://scripts/bleacher_seat.gd").new()
		constraint.configure(athlete_,benches[idx],benches[idx-1] if row>0 else null,side,float(seat[2]))
		occupied.append(constraint)
	return occupied

func brace(a: Vector3,b: Vector3,width: float,_style: Material) -> void:
	var basis := Basis(Quaternion(Vector3.UP,(b-a).normalized()))*Basis.from_scale(Vector3(width,a.distance_to(b),width))
	brace_transforms.append(Transform3D(basis,(a+b)*.5))

func build_gallery(steel: Material,paint: Material) -> void:
	var glass := material("bacece")
	glass.emission_enabled = true
	glass.emission = Color("bbdde9")
	glass.emission_energy_multiplier = 0.55
	var tube := material("f9eed4")
	tube.emission_enabled = true
	tube.emission = Color("fff1d6")
	tube.emission_energy_multiplier = 2.3
	for side in [-1,1]:
		for bay in 10:
			var z := -12.0+bay*3.15
			box("Clerestory frame",Vector3(0.15,1.9,2.9),Vector3(side*16.09,6.65,z),steel)
			for pane in 3:
				box("Daylight glazing",Vector3(0.06,1.72,0.86),Vector3(side*15.98,6.65,z+(pane-1)*0.93),glass)
	for z in [-13,-8,-3,2,7,12,17]:
		box("Truss chord",Vector3(32.5,.08,.08),Vector3(0,7.85,z),steel)
		for i in 18:
			var x := -16.2+i*1.8
			brace(Vector3(x,7.85,z),Vector3(x+.9,8.55,z),.055,steel)
			brace(Vector3(x+.9,8.55,z),Vector3(x+1.8,7.85,z),.055,steel)
		for x in [-5,5]:
			box("Fixture diffuser",Vector3(2.66,.045,.26),Vector3(x,8.30,z),tube)
	for i in 2:
		var x := -6.4 if i==0 else 6.4
		box("Backboard",Vector3(1.8,1.05,.12),Vector3(x,3.45,18.95),material("d7d3bd"))
		for side in [-1,1]:
			box("Backboard square",Vector3(.045,.42,.025),Vector3(x+side*.29,3.46,18.86),paint)
		box("Backboard square",Vector3(.62,.045,.025),Vector3(x,3.66,18.86),paint)
		var rim := MeshInstance3D.new()
		var hoop := TorusMesh.new()
		hoop.inner_radius = .215
		hoop.outer_radius = .237
		rim.mesh = hoop
		rim.material_override = material("db633a")
		rim.position = Vector3(x,3.05,18.6)
		add_child(rim)

static func light_gym(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("34434c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d0d8df")
	env.ambient_light_energy = .38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var cinematic := RenderingServer.get_current_rendering_method()=="forward_plus"
	if cinematic:
		env.tonemap_exposure = 0.91
		env.ssao_enabled = true
		env.ssao_radius = 0.85
		env.ssao_intensity = 1.5
		env.ssil_enabled = true
		env.ssil_radius = 2.2
		env.ssil_intensity = 0.7
		env.ssr_enabled = true
		env.ssr_max_steps = 128
		env.glow_enabled = true
		env.glow_intensity = 0.38
		env.glow_strength = 0.7
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0025
		env.volumetric_fog_length = 32
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_albedo = Color("ecdbc3")
	var atmosphere := WorldEnvironment.new()
	atmosphere.environment = env
	world.add_child(atmosphere)
	for z in [-4.0,4.0,11.0]:
		for x in [-5.0,5.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x,7.65,z)
			lamp.light_color = Color("fff0d5") if x>0 else Color("dceafa")
			lamp.omni_range = 13.5
			lamp.omni_attenuation = 1.35
			lamp.light_energy = 1.85
			lamp.light_size=.22
			lamp.shadow_enabled = true
			world.add_child(lamp)
	var bounce := OmniLight3D.new()
	bounce.position = Vector3(0,3.1,-4)
	bounce.light_color = Color("fff2df")
	bounce.light_energy = 0.62
	bounce.omni_range = 10
	world.add_child(bounce)
	var daylight := SpotLight3D.new()
	daylight.position = Vector3(-10.6,6.5,-1)
	daylight.light_energy = 4.0
	daylight.light_color = Color("e6f3ff")
	daylight.spot_angle = 51
	daylight.spot_range = 24
	daylight.shadow_enabled = true
	world.add_child(daylight)
	daylight.look_at(Vector3(2,0,3))

	if cinematic:
		for z in [-3.1,3.2,9.5]:
			var sun := SpotLight3D.new()
			sun.position = Vector3(-10.3,6.7,z)
			sun.spot_angle = 21
			sun.spot_range = 23
			sun.spot_attenuation = 0.25
			sun.light_color = Color("ffdfaa")
			sun.light_energy = 2.25
			sun.light_volumetric_fog_energy = 1.1
			sun.light_projector = preload("res://assets/gym/window_light.svg")
			sun.shadow_enabled = true
			world.add_child(sun)
			sun.look_at(Vector3(2.5,0.2,z+3.8))

func wall_text(text: String,at: Vector3,scale_: float,color: Color) -> void:
	var letters := Label3D.new()
	letters.text = text
	letters.font_size = 64
	letters.pixel_size = scale_
	letters.modulate = color
	letters.position = at
	letters.rotation.y = PI
	add_child(letters)

func add_digit(x: float) -> void:
	var lit := material("ffc968")
	lit.emission_enabled = true
	lit.emission = Color("ffc15c")
	lit.emission_energy_multiplier = 1.8
	var digit := []
	for i in 7:
		var centers := [Vector2(0,.23),Vector2(.13,.115),Vector2(.13,-.115),Vector2(0,-.23),Vector2(-.13,-.115),Vector2(-.13,.115),Vector2.ZERO]
		var at: Vector2 = centers[i]
		var horizontal := i in [0,3,6]
		digit.append(box("LED segment",Vector3(.22 if horizontal else .037,.035 if horizontal else .18,.016),Vector3(x-at.x,3.64+at.y,19.28),lit))
	digits.append(digit)

func update_board(made: int) -> void:
	var patterns := [63,6,91,79,102,109,125,7,127,111]
	var values := [made/10,made%10,0,9]
	for n in digits.size():
		for segment in 7:
			digits[n][segment].visible = (int(patterns[values[n]]) & (1<<segment))!=0
