extends Node3D

const FPS := 30.0
const CONTACT := 10.0 / FPS
const NET_Z := -1.17
const NET_HEIGHT := 2.43
const HOLD := 0.55
const VIEWS := [Vector3(-3.6, 3.8, 5.8), Vector3(6.3, 2.75, 0.65), Vector3(4.5, 2.85, 5.5)]
const STAGE := Vector3(-0.37, 1.62, -0.62)
const JERSEY := Color("#202b48")
const SHORTS := Color("#18213a")
const TRIM := Color("#e6f572")
const SKIN := Color("#c18d70")
const SOCK := Color("#e6e9ee")
const HAIR := Color("#503829")

var frames: Array = []
var segments: Array[Dictionary] = []
var joints: Array[Vector3] = []
var camera: Camera3D
var ball: MeshInstance3D
var ball_contact: Vector3
var time := 0.0
var duration := 0.0
var running := true
var speed := 1.0
var view := 0
var timeline: HSlider
var clock: Label
var play_button: Button
var angles: OptionButton

func _ready() -> void:
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://spike_frames.json"))
	for frame in source:
		var points := PackedVector3Array()
		for value in frame:
			points.append(Vector3(value[0], value[1], value[2]))
		frames.append(points)
	duration = (frames.size() - 1) / FPS
	joints.resize(frames[0].size())
	ball_contact = frames[10][23] + Vector3(-0.08, 0.0, -0.08)
	make_court()
	make_hitter()
	make_hud()
	set_view(0)
	show_pose(0.0)
	if "--check" in OS.get_cmdline_user_args():
		run_check()
	elif "--capture" in OS.get_cmdline_user_args():
		await capture_review()

func _process(delta: float) -> void:
	if running:
		time = fmod(time + delta * speed, duration + HOLD)
		show_pose(time)

func show_pose(at: float) -> void:
	var frame := minf(at * FPS, frames.size() - 1)
	var lower := floori(frame)
	var upper := mini(lower + 1, frames.size() - 1)
	for i in joints.size():
		joints[i] = frames[lower][i].lerp(frames[upper][i], frame - lower)
	for part in segments:
		var start: Vector3 = joints[part.from]
		var end: Vector3 = joints[part.to]
		var difference := end - start
		var up := difference.normalized()
		var across := joints[10] - joints[6]
		if part.kind == "hips":
			across = joints[17] - joints[13]
		if absf(across.normalized().dot(up)) > 0.94:
			across = Vector3.BACK if absf(up.z) < 0.94 else Vector3.RIGHT
		var back := across.cross(up).normalized()
		var right := up.cross(back)
		var mesh: Node3D = part.mesh
		mesh.transform = Transform3D(
			Basis(right * part.width, up * difference.length() * 1.10, back * part.depth),
			(start + end) * 0.5
		)
	update_ball(at)
	timeline.set_value_no_signal(minf(at, duration))
	clock.text = "%04.2f / %.2f s" % [minf(at, duration), duration]

func update_ball(at: float) -> void:
	var dt := at - CONTACT
	if dt < 0.0:
		var offset := Vector3(-0.35, 0.55, -0.16)
		ball.position = ball_contact + offset * (-dt / CONTACT)
	else:
		var flight := 0.48
		var t := minf(dt, flight)
		var landing := Vector3(1.65, 0.11, -5.65)
		ball.position = ball_contact.lerp(landing, t / flight) + Vector3.UP * 4.9 * t * (flight - t)
		if dt > flight:
			var bounce := minf(dt - flight, 0.65)
			ball.position += Vector3(-0.8 * bounce, absf(sin(bounce * 13.0)) * exp(-bounce * 5.0) * 0.28, -1.65 * bounce)
	ball.rotation = Vector3(at * 12.0, at * 5.0, at * -6.0)

func make_court() -> void:
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("#121a29")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("#c7d6f4")
	lighting.ambient_light_energy = 0.58
	environment.environment = lighting
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-51, -27, 0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-29, 155, 0)
	fill.light_color = Color("#9fbcff")
	fill.light_energy = 0.35
	add_child(fill)
	box(Vector3(0, -0.14, NET_Z), Vector3(25, 0.24, 27), Color("#285879"))
	box(Vector3(0, -0.035, NET_Z), Vector3(9, 0.07, 18), Color("#b96142"))
	for x in [-4.5, 4.5]:
		box(Vector3(x, 0.004, NET_Z), Vector3(0.05, 0.008, 18.05), SOCK)
	for z in [-9.0, -3.0, 0.0, 3.0, 9.0]:
		box(Vector3(0, 0.004, NET_Z + z), Vector3(9.05, 0.008, 0.05), SOCK)
	for x in [-4.95, 4.95]:
		box(Vector3(x, 1.0, NET_Z), Vector3(0.22, 2.0, 0.22), Color("#2e63a2"))
		box(Vector3(x, 2.22, NET_Z), Vector3(0.075, 0.44, 0.075), Color("#afbdd0"))
	for x in [-4.5, 4.5]:
		for i in 6:
			box(Vector3(x, NET_HEIGHT + (i + 0.5) * 0.12, NET_Z), Vector3(0.029, 0.12, 0.029), SOCK if i % 2 == 0 else Color("#cd5148"))
	var net_color := Color("#45495a")
	for i in 91:
		box(Vector3(-4.5 + i * 0.1, NET_HEIGHT - 0.51, NET_Z), Vector3(0.008, 0.93, 0.008), net_color)
	for i in 10:
		box(Vector3(0, NET_HEIGHT - 0.11 - i * 0.1, NET_Z), Vector3(9, 0.009, 0.009), net_color)
	box(Vector3(0, NET_HEIGHT - 0.025, NET_Z), Vector3(9.9, 0.05, 0.034), SOCK)
	box(Vector3(0, NET_HEIGHT - 1.02, NET_Z), Vector3(9.9, 0.036, 0.03), SOCK)
	for x in [-10.5, 10.5]:
		for row in 4:
			box(Vector3(x + signf(x) * row * 0.65, row * 0.29, NET_Z), Vector3(0.62, 0.22 + row * 0.58, 20), Color("#1d344c").lightened(row * 0.035))
	camera = Camera3D.new()
	camera.fov = 40
	camera.current = true
	add_child(camera)

func make_hitter() -> void:
	body(0, 2, 0.41, 0.235, JERSEY, "torso")
	body(0, 1, 0.405, 0.245, SHORTS, "hips")
	body(2, 3, 0.13, 0.13, JERSEY)
	body(3, 4, 0.115, 0.11, SKIN)
	body(4, 21, 0.188, 0.198, SKIN, "head")
	body(4, 21, 0.19, 0.20, HAIR, "hair")
	for arm in [6, 10]:
		body(arm, arm + 1, 0.127, 0.127, SKIN)
		body(arm, arm + 1, 0.151, 0.148, JERSEY, "sleeve")
		body(arm + 1, arm + 2, 0.092, 0.092, SKIN)
		body(arm + 2, 22 if arm == 6 else 23, 0.09, 0.053, SKIN)
	for leg in [13, 17]:
		body(leg, leg + 1, 0.169, 0.167, SKIN)
		body(leg, leg + 1, 0.184, 0.18, SHORTS, "sleeve")
		body(leg + 1, leg + 2, 0.12, 0.12, SKIN)
		body(leg + 1, leg + 2, 0.125, 0.125, SOCK, "sock")
		body(leg + 2, 24 if leg == 13 else 25, 0.132, 0.104, SOCK)
	var sphere := SphereMesh.new()
	sphere.radius = 0.105
	sphere.height = 0.21
	ball = mesh_node(sphere, Color("#f4d757"))
	for axis in [Vector3.ZERO, Vector3(0.7, 0.0, 1.05), Vector3(-0.65, 1.0, 0.4)]:
		var band := TorusMesh.new()
		band.inner_radius = 0.103
		band.outer_radius = 0.107
		band.rings = 24
		band.ring_segments = 5
		var stripe := mesh_node(band, Color("#303d70"))
		stripe.reparent(ball, false)
		stripe.rotation = axis

func body(from: int, to: int, width: float, depth: float, color: Color, kind := "") -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.39
	capsule.height = 1.0
	capsule.radial_segments = 16
	capsule.rings = 8
	var pivot := Node3D.new()
	add_child(pivot)
	var mesh := mesh_node(capsule, color)
	mesh.scale = Vector3(1.22, 1.0, 1.22)
	mesh.reparent(pivot, false)
	if kind == "sleeve":
		mesh.position.y = -0.28
		mesh.scale.y = 0.54
	elif kind == "sock":
		mesh.position.y = 0.34
		mesh.scale.y = 0.39
	elif kind == "head":
		mesh.scale.y = 1.76
	elif kind == "hair":
		mesh.position.y = 0.50
		mesh.scale.y = 0.76
	elif kind == "torso":
		mesh.scale.y = 1.28
		var number := Label3D.new()
		number.text = "19"
		number.font_size = 75
		number.pixel_size = 0.0064
		number.position = Vector3(0.0, 0.16, 0.49)
		number.modulate = TRIM
		number.outline_size = 0
		number.no_depth_test = false
		number.double_sided = false
		pivot.add_child(number)
	segments.append({"from": from, "to": to, "width": width, "depth": depth, "mesh": pivot, "kind": kind})

func box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node(mesh, color).position = at + Vector3(3.2, 0.0, 0.0)

var materials := {}
func mesh_node(mesh: Mesh, color: Color) -> MeshInstance3D:
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.89
		materials[color] = material
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = materials[color]
	add_child(item)
	return item

func set_view(index: int) -> void:
	view = index
	angles.select(index)
	camera.position = VIEWS[view]
	camera.look_at(STAGE)

func make_hud() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "POSITION 4  /  SPIKE"
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_shadow_color", Color("#121a29"))
	title.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(title)
	var panel := PanelContainer.new()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 26
	panel.offset_right = -26
	panel.offset_top = -75
	panel.offset_bottom = -22
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#141f30ed")
	style.set_corner_radius_all(10)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	add_button(row, "Replay", func(): time = 0.0; set_running(true); show_pose(time))
	play_button = add_button(row, "Pause", func(): set_running(not running))
	timeline = HSlider.new()
	timeline.max_value = duration
	timeline.step = 0.001
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.value_changed.connect(func(value: float): time = value; set_running(false); show_pose(time))
	row.add_child(timeline)
	clock = Label.new()
	clock.custom_minimum_size.x = 115
	row.add_child(clock)
	var rates := OptionButton.new()
	for rate in ["1×", "½×", "¼×"]:
		rates.add_item(rate)
	rates.item_selected.connect(func(index: int): speed = [1.0, 0.5, 0.25][index])
	row.add_child(rates)
	angles = OptionButton.new()
	for angle in ["Broadcast", "Sideline", "Near pin"]:
		angles.add_item(angle)
	angles.item_selected.connect(set_view)
	row.add_child(angles)

func add_button(row: HBoxContainer, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.x = 68
	button.pressed.connect(action)
	row.add_child(button)
	return button

func set_running(value: bool) -> void:
	running = value
	play_button.text = "Pause" if value else "Play"

func run_check() -> void:
	assert(frames.size() == 39 and frames[0].size() == 26)
	for frame in frames:
		assert(frame.size() == 26)
		for joint in frame:
			assert(joint.is_finite())
	assert(frames[10][23].y > NET_HEIGHT)
	show_pose(CONTACT)
	assert(ball.position.distance_to(joints[23]) < 0.15)
	assert(ball.position.z > NET_Z)
	var net_time := (NET_Z - ball_contact.z) / (-5.65 - ball_contact.z) * 0.48
	show_pose(CONTACT + net_time)
	assert(ball.position.y > NET_HEIGHT + 0.105)
	show_pose(duration)
	assert(ball.position.z < NET_Z and absf(ball.position.x) < 4.5)
	for angle in VIEWS.size():
		set_view(angle)
		assert(camera.transform.is_finite())
	print("39 mocap frames, contact, landing and three camera angles verified")
	get_tree().quit()

func capture_review() -> void:
	set_running(false)
	DirAccess.make_dir_recursive_absolute("res://review")
	for i in 126:
		var angle := 0 if i < 54 else 1
		var sample: float = i if i < 54 else (i - 54) * 0.67
		set_view(angle)
		show_pose(minf(sample / FPS, duration))
		await RenderingServer.frame_post_draw
		var path := "res://review/frame_%03d.png" % i
		get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
