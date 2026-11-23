extends "res://scripts/preview_court.gd"

func _ready() -> void:
	super()
	var maple := ShaderMaterial.new()
	maple.shader = preload("res://assets/gym/maple.gdshader")
	get_node("Runoff").material_override = maple
	for i in 30: get_node("Floorboard%d" % i).material_override = maple
	var block := ShaderMaterial.new()
	block.shader = preload("res://assets/gym/masonry.gdshader")
	var paint := material("385545")
	var wood := material("98633b")
	var steel := material("535951")
	var white := material("e7dfc9")
	box("North wall",Vector3(24,9,0.3),Vector3(0,4.4,14.8),block)
	box("South wall",Vector3(24,9,0.3),Vector3(0,4.4,-11),block)
	box("Ceiling",Vector3(24,0.2,26),Vector3(0,9,2),white)
	for side in [-1,1]:
		box("Side masonry",Vector3(0.25,9,26),Vector3(side*11.3,4.4,2),block)
		for row in 4:
			var x: float = side*(6.8+row*0.69)
			box("Bleacher bench",Vector3(0.65,0.15,15),Vector3(x,0.48+row*0.37,3),wood)
			for z in [-3,1,5,9]:
				box("Folding support",Vector3(0.1,0.45+row*0.37,0.1),Vector3(x,(0.45+row*0.37)/2,z),steel)
	for dir in [-1,1]:
		var z := 14.57 if dir==1 else -10.8
		box("Painted stripe",Vector3(22.5,0.42,0.08),Vector3(0,3.1,z),paint)
		for i in 5:
			var x := (i-2)*3.4
			box("Championship felt",Vector3(1.5,2.3,0.07),Vector3(x,5.5,z-dir*0.10),paint)
			var label := Label3D.new()
			label.text = "VARSITY\n◆\n%d" % (2006+i*3)
			label.font_size = 40
			label.pixel_size = 0.0068
			label.position = Vector3(x,5.5,z-dir*0.16)
			if dir==1: label.rotation.y = PI
			add_child(label)
	for z in [-8,-3,2,7,12]:
		box("Roof steel",Vector3(22.6,0.2,0.18),Vector3(0,8.55,z),steel)
		for x in [-5,5]:
			box("Fluorescent bank",Vector3(2.8,0.1,0.32),Vector3(x,8.38,z),material("fff3cc"))


	var padding := material("314e41")
	for i in 12:
		box("Wall pad",Vector3(0.88,1.95,0.16),Vector3((i-5.5)*0.92,1.0,14.43),padding)
	box("Scoreboard",Vector3(3.8,1.45,0.18),Vector3(0,3.85,14.41),material("26352e"))
	wall_text("HOME      GUEST",Vector3(0,4.19,14.29),0.003,Color.FLORAL_WHITE)
	wall_text("00     00",Vector3(0,3.63,14.29),0.006,Color.SANDY_BROWN)
	for x in [-8.2,8.2]:
		box("Gym exit",Vector3(2.1,2.4,0.14),Vector3(x,1.2,14.42),material("656f61"))
		box("Door rail",Vector3(1.8,0.06,0.12),Vector3(x,1.1,14.30),steel)
		wall_text("EXIT",Vector3(x,2.67,14.32),0.003,Color.PALE_GREEN)
	build_gallery(steel,paint)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0,3,2)
	probe.size = Vector3(23,11,28)
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.65
	add_child(probe)

func brace(a: Vector3,b: Vector3,width: float,style: Material) -> void:
	var beam := box("Steel web",Vector3(width,a.distance_to(b),width),(a+b)*0.5,style)
	beam.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

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
		for bay in 7:
			var z := -7.0+bay*3.15
			box("Clerestory frame",Vector3(0.15,1.9,2.9),Vector3(side*11.09,6.65,z),steel)
			for pane in 3:
				box("Daylight glazing",Vector3(0.06,1.72,0.86),Vector3(side*10.98,6.65,z+(pane-1)*0.93),glass)
		for x_ in [6.75,8.8]:
			var x: float = side*x_
			for z in [-4.4,10.4]:
				brace(Vector3(x,0.4,z),Vector3(x,2.1,z),0.045,steel)
			brace(Vector3(x,2.1,-4.4),Vector3(x,2.1,10.4),0.045,steel)
	for z in [-8,-3,2,7,12]:
		box("Truss chord",Vector3(22.5,.08,.08),Vector3(0,7.85,z),steel)
		for i in 14:
			var x := -11.2+i*1.6
			brace(Vector3(x,7.85,z),Vector3(x+.8,8.55,z),.055,steel)
			brace(Vector3(x+.8,8.55,z),Vector3(x+1.6,7.85,z),.055,steel)
		for x in [-5,5]:
			box("Fixture diffuser",Vector3(2.66,.045,.26),Vector3(x,8.30,z),tube)
	for i in 2:
		var x := -6.4 if i==0 else 6.4
		box("Backboard",Vector3(1.8,1.05,.12),Vector3(x,3.45,13.95),material("d7d3bd"))
		for side in [-1,1]:
			box("Backboard square",Vector3(.045,.42,.025),Vector3(x+side*.29,3.46,13.86),paint)
		box("Backboard square",Vector3(.62,.045,.025),Vector3(x,3.66,13.86),paint)
		var rim := MeshInstance3D.new()
		var hoop := TorusMesh.new()
		hoop.inner_radius = .215
		hoop.outer_radius = .237
		rim.mesh = hoop
		rim.material_override = material("db633a")
		rim.position = Vector3(x,3.05,13.6)
		add_child(rim)

static func light_gym(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("34434c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d0d8df")
	env.ambient_light_energy = .38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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

func wall_text(text: String,at: Vector3,scale_: float,color: Color) -> void:
	var letters := Label3D.new()
	letters.text = text
	letters.font_size = 64
	letters.pixel_size = scale_
	letters.modulate = color
	letters.position = at
	letters.rotation.y = PI
	add_child(letters)
