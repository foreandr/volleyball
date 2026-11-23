extends "res://scripts/preview_court.gd"

func _ready() -> void:
	super()
	get_node("Runoff").material_override = material("aa8157")
	var block := material("d7cdb5")
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
			label.text = "VARSITY\nVOLLEYBALL\n%d" % (2006+i*3)
			label.font_size = 40
			label.pixel_size = 0.0038
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
	for i in 30:
		for joint in 5:
			var z := -4.0+joint*3.55+fmod(i*1.17,2.4)
			box("Board joint",Vector3(0.295,0.002,0.009),Vector3(-4.35+i*0.3,0.041,z),wood)

func wall_text(text: String,at: Vector3,scale_: float,color: Color) -> void:
	var letters := Label3D.new()
	letters.text = text
	letters.font_size = 64
	letters.pixel_size = scale_
	letters.modulate = color
	letters.position = at
	letters.rotation.y = PI
	add_child(letters)
