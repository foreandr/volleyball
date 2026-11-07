extends Node3D
var camera: Camera3D
var ball: MeshInstance3D
var players: Array[Node3D] = []

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("579bd0")
	sky_material.sky_horizon_color = Color("c8e7f2")
	sky_material.ground_horizon_color = Color("c8e7f2")
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("fff0d8")
	settings.ambient_light_energy = 0.25
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	add_child(sun)
	box(Vector3(160,0.2,160),Vector3(0,-0.12,0),Color("d9bd85"))
	box(Vector3(8,0.025,16),Vector3(0,0,0),Color("e9d09d"))
	var blue := Color("2579a8")
	for x in [-4.0,4.0]: box(Vector3(0.055,0.025,16.05),Vector3(x,0.024,0),blue)
	for z in [-8.0,8.0]: box(Vector3(8.05,0.025,0.055),Vector3(0,0.024,z),blue)
	for x in [-4.65,4.65]:
		box(Vector3(0.18,2.7,0.18),Vector3(x,1.35,0),Color("2799be"))
		box(Vector3(0.3,1.3,0.3),Vector3(x,0.65,0),Color("287da2"))
	# Transparent gaps are real geometry, so the far half remains visible.
	var cords := ImmediateMesh.new()
	cords.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(46):
		var x := -4.5+float(index)*0.2
		cords.surface_add_vertex(Vector3(x,1.43,0))
		cords.surface_add_vertex(Vector3(x,2.43,0))
	for index in range(6):
		var y := 1.43+float(index)*0.2
		cords.surface_add_vertex(Vector3(-4.5,y,0))
		cords.surface_add_vertex(Vector3(4.5,y,0))
	cords.surface_end()
	var net := MeshInstance3D.new()
	net.mesh = cords
	net.material_override = material(Color("253d46"))
	add_child(net)
	for y in [1.43,2.43]: box(Vector3(9.35,0.065,0.04),Vector3(0,y,0),Color("fff8e6"))
	for x in [-4.5,4.5]: box(Vector3(0.035,1.8,0.035),Vector3(x,2.3,0),Color("eb6d58"))
	ball = MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 0.105
	sphere.height = 0.21
	ball.mesh = sphere
	ball.material_override = material(Color("ffd95c"))
	ball.position = Vector3(-1.6,1.0,4.3)
	add_child(ball)
	for index in range(4):
		var athlete := preload("res://scripts/volleyball_player.gd").new()
		athlete.name = ["Blue1","Blue2","Red1","Red2"][index]
		athlete.team_color = Color("2c8fe5") if index < 2 else Color("dc5653")
		athlete.player_number = index%2+1
		athlete.position = [Vector3(-1.9,0.025,4.6),Vector3(1.7,0.025,2.4),Vector3(-1.7,0.025,-2.4),Vector3(1.9,0.025,-4.6)][index]
		athlete.rotation.y = PI if index < 2 else 0.0
		add_child(athlete)
		players.append(athlete)
	camera = preload("res://scripts/court_camera.gd").new()
	camera.name = "CourtCamera"
	camera.ball_target = ball
	add_child(camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	var back := Button.new()
	back.text = "Menu"
	back.position = Vector2(24,24)
	back.custom_minimum_size = Vector2(95,40)
	back.pressed.connect(open_menu)
	hud.add_child(back)

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color.darkened(0.28)
	result.roughness = 0.9
	return result

func box(size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	result.mesh = shape
	result.position = point
	result.material_override = material(color)
	add_child(result)
	return result

func open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: open_menu()
