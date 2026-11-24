extends Control

@export var solo_setting := false

const Court = preload("res://scripts/preview_court.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const Hands = preload("res://scripts/hand_setting_pose.gd")
const TARGETS := ["10","32","72"]
const TEMPOS := ["Medium","High"]
const Xbox = preload("res://scripts/xbox_controls.gd")
const BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B]
const KEYS := [KEY_J,KEY_I,KEY_L]
const PINS := [Vector3(4.75,2.65,3.0),Vector3(1.05,2.65,3.3),Vector3(-4.75,2.65,3.0)]
# Midway between the centers of zones 2 (x=-3) and 3 (x=0).
const BASE := Vector3(-1.5,0.04,1.35)
const ORDER := [0,2,1]
var forehead_arrival := 1.0
var catch_start_local := Vector3.ZERO
const CATCH_GIVE := .115
const SET_RECEIVE_TIME := .050
const SET_PUSH_TIME := .033
var receive_local := Vector3.ZERO
var push_axis := Vector3.UP
var camp_receive_spot := BASE
var camp_velocity := Vector3.ZERO
var plant_time := -1.0
var plant_start_yaw := 0.0
const PLANT_DURATION := .64
var forehead_target := Vector3.ZERO
var contact_time := 1.0
const DURATION := [1.25,1.62]
const APEX := [1.92,3.22]
const LINES := ["Welcome to the team, %s. I’m Coach Ellis.","You’re trying out at setter. Watch the three targets. I’ll toss the first ones right to you.","Three calls from each coach station. Keep your spot. I’ll toss above your forehead, including on the jump sets."]
var coach_motion := preload("res://scripts/tryout_coach.gd").new()
var last_toss := -10.0
var next_release := 0.0
var coach_goal := Vector3.ZERO
var focused := false
var active_pad := -1
var floor_speed := 0.0
var phase := ""
var elapsed := 0.0
var clock := 0.0
var spectator_prompt := PanelContainer.new()
var spectator_text := Label.new()
var spectator_icon := TextureRect.new()
var timing_note := Label.new()
var timing_until := 0.0
const ON_TIME := .065
const HAND_CUSHION := .18
var pending_release := false
var input_hold := 0.0
var contact_local := Vector3.ZERO
var measured_release := false
var spectator_progress := ProgressBar.new()
var skip_time := 0.0
var camera_lead := Vector3.ZERO
var replay_inspector := preload("res://scripts/practice_replay.gd").new()

func toggle_practice_replay() -> void:
	replay_inspector.toggle()

var camera := Camera3D.new()
var world := Node3D.new()
var setter: Node3D
var targets: Array[Node3D] = []
var squat := preload("res://scripts/tryout_squat.gd").new()
const Contact = preload("res://scripts/gym_physics.gd")
var rotation_drill := preload("res://scripts/tryout_rotation.gd").new()
var contacts := Contact.new()
var gym := preload("res://scripts/tryout_gym.gd").new()
var seats_in_use: Array[RefCounted] = []
var last_contact := -100.0
var cushion := 0.0
var drop_velocity := Vector3.ZERO
var old_palms := {}
var jump := preload("res://scripts/setter_jump.gd").new()
var cpu_setting := false
var cpu_jump_lead := .40
var cpu_release_delay := 0.
var cpu_jump_started := false

func plan_cpu_timing() -> void:
	cpu_jump_started=false
	cpu_jump_lead=.40
	cpu_release_delay=0.
	if not automatic_setter() or demonstration: return
	var rng=rotation_drill.random
	cpu_jump_lead=rng.randf_range(.31,.46)
	if rng.randf()>.32:
		cpu_release_delay=rng.randf_range(.012,.055)*(-1. if rng.randf()<.5 else 1.)

var demonstration := false

func automatic_setter() -> bool:
	return cpu_setting or demonstration or rotation_drill.turn!=0
var demo_index := 0
var pressed_at := 0.0
var endpoint := Vector3.ZERO
var settings := preload("res://scripts/tryout_pause.gd").new()
var yaw := 0.0
var elevation := 27.0
var distance := 12.0
var meter := ProgressBar.new()

var coach: Node3D

var ball := MeshInstance3D.new()
var panel := PanelContainer.new()
var title := Label.new()
var message := Label.new()
var controls_row := HFlowContainer.new()
var prompt_phase := ""
var hint := Label.new()
var skip := TextureProgressBar.new()
var finish := Button.new()
var retry := Button.new()
var score_strip := HBoxContainer.new()
var score_labels: Array[Label]=[]
var score_cue := AudioStreamPlayer.new()
var scorecard: Array=[]
var placement_error := 10.
var rep := 0
var held := -1
var selected_tempo := 1
var previous_time_scale := 1.0
var slow_motion := false
var stick_latched := false
var preview_until := 0.0
var source := Vector3.ZERO
var catch_point := Vector3.ZERO
var target := 0
var free_squat := preload("res://scripts/tryout_squat.gd").new()
var free_jump := preload("res://scripts/setter_jump.gd").new()
var free_target := -1
var free_press := 0.0
var lateral_steps := {}
var cue_until := 0.0
var graded_fill := 0.0
var first_contact := -100.0
var set_grade_until := 0.0
var set_error := 0.0
var energy := {}
var toss_curve := 1.0
var toss_spin := Vector3.ZERO
var preview_enabled := true
var tempo := 0
var success := false
var feedback := ""
var flight_time := 1.0

func athlete(at: Vector3,color: String) -> Node3D:
	var actor := Player.new()
	actor.team_color = Color(color)
	actor.position = at
	world.add_child(actor)
	actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.get_node("DirectionArrows").hide()
	var turn_steps := preload("res://scripts/ground_turn_steps.gd").new()
	turn_steps.name="GroundTurnSteps"
	turn_steps.actor=actor
	actor.skeleton.add_child(turn_steps)
	actor.skeleton.add_child(preload("res://scripts/practice_joint_limits.gd").new())
	return actor

var original_render_scale := 1.0
var original_msaa := Viewport.MSAA_DISABLED

func _ready() -> void:
	original_render_scale=get_viewport().scaling_3d_scale
	original_msaa=get_viewport().msaa_3d
	MenuPresentation.set_music(false)
	add_child(world)
	world.add_child(gym)
	preload("res://scripts/tryout_gym.gd").light_gym(world)
	get_viewport().msaa_3d = Viewport.MSAA_8X
	get_viewport().scaling_3d_scale=1.35
	camera.fov = 52
	world.add_child(camera)
	camera.current = true
	setter = athlete(Vector3(-0.8,0.04,1.1),"e97937")
	var profile := CareerSession.profile()
	if solo_setting and profile.is_empty(): profile=preload("res://scripts/player_profile.gd").load_profile()
	setter.apply_profile(profile)
	setter.play_action("idle")
	coach = athlete(Vector3(-2.5,0.04,-1.2),"48574d")
	coach.play_action("idle")
	preload("res://scripts/practice_kit.gd").apply(setter,false)
	preload("res://scripts/practice_kit.gd").apply(coach,true)
	setter.set_meta("school_photo",SchoolHeadshots.request(setter.attributes))
	coach_motion.dress(coach)
	if not solo_setting: seat_teammates()
	for i in PINS.size():
		var basket := preload("res://scripts/tryout_target.gd").new()
		basket.position = PINS[i]
		basket.is_net = true
		basket.depth = 0.88 if basket.is_net else 0.50
		world.add_child(basket)
		targets.append(basket)
	var mesh := SphereMesh.new()
	mesh.radius = 0.105
	mesh.height = 0.21
	ball.mesh = mesh
	var leather := ShaderMaterial.new()
	var cover := Shader.new()
	cover.code = """shader_type spatial;
	void fragment() {
		vec3 n = normalize(vec3(sin(UV.y*3.14159)*cos(UV.x*6.28318), cos(UV.y*3.14159), sin(UV.y*3.14159)*sin(UV.x*6.28318)));
		float stripe = fract(UV.x*3.0 + n.y*0.40);
		ALBEDO = mix(vec3(0.91,0.83,0.64),vec3(0.08,0.22,0.35),smoothstep(0.62,0.64,stripe));
		ROUGHNESS = 0.53;
	}"""
	leather.shader = cover
	ball.material_override = leather
	world.add_child(ball)
	rotation_drill.configure(self)
	add_child(replay_inspector)
	for a in rotation_drill.roster: energy[a]=a.stamina
	var rings := preload("res://scripts/tryout_player_ring.gd").new()
	rings.game=self
	add_child(rings)
	squat.configure(world)
	free_squat.configure(world)
	free_jump.front_limit=14.0
	build_hud()
	build_score_strip()
	build_settings()
	var commands := preload("res://scripts/tryout_command_overlay.gd").new()
	commands.game = self
	add_child(commands)
	start_drill()

func finish_intro() -> bool:
	return true

func reset_drill() -> void:
	trace("drill_reset",{})
	MenuPresentation.load_scene(scene_file_path)

func start_drill() -> void:
	start_practice()

func register_student(actor: Node3D, variant: int) -> void:
	var names := ["Jordan Reyes","Micah Bell","Noah Park","Eli Chen","Kai Singh","Luca Costa","Sam Rivera","Jules Martin","Rin Ito","Ari Kim","Alex Lewis","Sol Evans","Toby Wright","Casey Lee","Morgan Cole","Jamie Hall","Reese Gray","Dev Patel"]
	var index := variant - 1 if variant < 20 else variant - 12
	var values := {"name":names[index],"age":15 + index % 4,"hometown":["Hamilton","Burlington","Toronto","Oshawa","Kingston"][index % 5],"handedness":"Left" if index % 4 == 1 else "Right"}
	if variant >= 20: values.height_cm = 172 + ((variant - 20) * 7) % 29
	actor.apply_profile(values)
	actor.set_meta("school_photo",SchoolHeadshots.request(actor.attributes,variant,actor.team_color))

func seat_teammates() -> void:
	var seats := [[-1,1,-3.0],[1,0,-1.1],[-1,1,0.9],[1,0,1.4],[-1,2,3.3],[1,1,4.2],[-1,0,5.5],[1,2,6.0],[-1,2,7.8],[1,1,8.0]]
	for i in seats.size():
		var seat: Array = seats[i]
		var side := int(seat[0])
		var row := int(seat[1])
		var athlete_ := athlete(Vector3(side*(6.8+row*.69),0,float(seat[2])),["245447","a34d31","334357"][i%3])
		register_student(athlete_,20+i)
		athlete_.set_height_cm(172+(i*7)%29)
		preload("res://scripts/practice_kit.gd").apply(athlete_,false,20+i)
		athlete_.rotation.y = -side*PI/2
		athlete_.play_action("base/Sitting_Talking",0)
		athlete_.animator.seek(i*.31,true)
		var idx := (4 if side==1 else 0)+row
		var constraint := preload("res://scripts/bleacher_seat.gd").new()
		constraint.configure(athlete_,gym.benches[idx],gym.benches[idx-1] if row>0 else null,side,float(seat[2]))
		seats_in_use.append(constraint)

func build_hud() -> void:
	panel.anchor_top = 1
	panel.anchor_bottom = 1
	panel.offset_left = 20
	panel.offset_bottom = -22
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel",MenuPresentation.box(Color("112534ed"),Color("6de4d1"),4))
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title.add_theme_color_override("font_color",Color("7be3d3"))
	column.add_child(title)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 395
	message.add_theme_font_size_override("font_size",20)
	column.add_child(message)
	hint.add_theme_font_size_override("font_size",13)
	hint.add_theme_color_override("font_color",Color("c1d0ce"))
	column.add_child(hint)
	column.add_child(controls_row)
	controls_row.custom_minimum_size.x = 480
	meter.custom_minimum_size = Vector2(180,5)
	meter.add_theme_stylebox_override("fill",MenuPresentation.box(Color("69dfc7"),Color("69dfc7"),0))
	meter.add_theme_stylebox_override("background",StyleBoxEmpty.new())
	meter.hide()
	meter.show_percentage = false
	column.add_child(meter)
	retry.text="Restart tryout"
	retry.pressed.connect(reset_drill)
	column.add_child(retry)
	retry.hide()
	finish.text = "Continue story"
	finish.pressed.connect(leave)
	column.add_child(finish)
	finish.hide()
	var img := Image.create(54,54,false,Image.FORMAT_RGBA8)
	for y in 54:
		for x in 54:
			var r := Vector2(x-26.5,y-26.5).length()
			img.set_pixel(x,y,Color(1,1,1,clampf(minf(r-19,25-r),0,1)))
	var ring := ImageTexture.create_from_image(img)
	skip.texture_under = ring
	skip.tint_under = Color("445a68")
	skip.texture_progress = ring
	skip.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	skip.tint_progress = Color("72e2cf")
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -86
	skip.offset_top = -88
	skip.offset_right = -32
	skip.offset_bottom = -34
	add_child(skip)
	add_child(spectator_prompt)
	spectator_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectator_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	spectator_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	spectator_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	spectator_prompt.offset_bottom = -24
	spectator_prompt.add_theme_stylebox_override("panel",MenuPresentation.box(Color("112534f5"),Color("6de4d1"),3))
	var skip_column := VBoxContainer.new()
	spectator_prompt.add_child(skip_column)
	spectator_text.add_theme_font_size_override("font_size",20)
	var row := HBoxContainer.new()
	skip_column.add_child(row)
	var hold := Label.new()
	hold.text = "Hold"
	hold.add_theme_font_size_override("font_size",20)
	row.add_child(hold)
	spectator_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spectator_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spectator_icon.custom_minimum_size = Vector2(42,34)
	row.add_child(spectator_icon)
	row.add_child(spectator_text)
	add_child(timing_note)
	timing_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timing_note.offset_top = 160
	timing_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	timing_note.add_theme_font_size_override("font_size",22)
	timing_note.add_theme_constant_override("outline_size",5)
	timing_note.hide()
	spectator_progress.custom_minimum_size.y = 5
	spectator_progress.show_percentage = false
	spectator_progress.max_value = 1
	skip_column.add_child(spectator_progress)
	spectator_prompt.hide()
	skip.hide()

func begin(next: String) -> void:
	trace("phase",{"next":next})
	update_prompts(next)
	meter.hide()
	phase = next
	elapsed = 0
	held = -1

func update_prompts(next: String) -> void:
	var group := "spectate" if rotation_drill.turn == 1 and next not in ["intro","complete"] else next if next in ["intro","complete","ground"] else "practice"
	if group==prompt_phase: return
	prompt_phase = group
	var entries := []
	match group:
		"spectate": entries = [[JOY_BUTTON_A,"Hold to skip"]]
		"intro": entries = [[JOY_BUTTON_A,"Hold to skip"]]
		"complete": entries = [[JOY_BUTTON_A,"Continue"]]
		"ground": entries = [[JOY_BUTTON_LEFT_SHOULDER,"Next toss"],[JOY_BUTTON_START,"Settings"]]
		_:
			if solo_setting: entries.append([BUTTONS[0],"Hold to set to 4"])
			else:
				for i in BUTTONS.size(): entries.append([BUTTONS[i],TARGETS[i]])
			entries.append_array([["RS","Set height"],[JOY_BUTTON_LEFT_STICK,"Show / hide arc"],[JOY_BUTTON_A,"Hold / release jump"],["LT","Focus"],["RT","Sprint"],[JOY_BUTTON_START,"Settings"]])
	if solo_setting:
		if cpu_setting: entries=[[BUTTONS[0],"CPU set to 4"],[JOY_BUTTON_START,"Settings"]]
		entries.push_front(["View","Take control" if cpu_setting else "Watch CPU set"])
	Xbox.prompts(controls_row,entries)

func camp_title() -> String:
	return "SET TO TARGET   /   CPU SETTER" if cpu_setting else "SET TO TARGET   /   PLAYER SETTER"

func switch_camp_control() -> void:
	cpu_setting = not cpu_setting
	squat.cancel()
	focused=false
	held=-1
	pending_release=false
	prompt_phase=""
	if phase in ["feed","pass","set_contact","forehead_catch"]:
		rotation_drill.free_ball(Vector3.ZERO)
		reset_feed()
	else:
		update_prompts(phase)
	title.text=camp_title()

func leave() -> void:
	MenuPresentation.load_scene("res://scenes/drills.tscn" if solo_setting else "res://scenes/story.tscn")

func start_practice() -> void:
	cpu_setting = solo_setting
	coach_motion.whistle_cue.signal_drill(coach)
	if not solo_setting: rotation_drill.advance_turn()
	rotation_drill.stage_start()
	skip_time = 0
	demonstration = false
	demo_index = 0
	reset_feed()
	if rotation_drill.turn == 1: say(coach, "%s, you're up first." % setter.display_name,4.0)

func jump_rep() -> bool:
	if solo_setting: return rep%2==1
	return demo_index%2==1 if demonstration else rotation_drill.round_index==1

func called() -> int:
	if solo_setting: return 0 # Outside pin, position four.
	return ORDER[demo_index if demonstration else rotation_drill.attempts]

func choose_camp_toss() -> Vector3:
	var rng = rotation_drill.random
	var start := Vector3(setter.position.x,BASE.y,setter.position.z)
	for attempt in 64:
		var spot := Vector3(rng.randf_range(-5.85,5.85),BASE.y,rng.randf_range(-5.85,1.8))
		var distance := start.distance_to(spot)
		if distance<1.5 or distance>4.65: continue
		var clear := true
		for obstacle in [coach,rotation_drill.basket]:
			var center := Vector3(obstacle.position.x,BASE.y,obstacle.position.z)
			if Geometry3D.get_closest_point_to_segment(center,start,spot).distance_to(center)<1.35:
				clear=false
				break
		if clear: return spot
	return start

func reset_feed() -> void:
	if solo_setting:
		camp_receive_spot=choose_camp_toss()
		plant_time=-1.
		setter.skeleton.get_node("GroundTurnSteps").set_sequence(-1.,cpu_setting)
		camp_velocity=Vector3.ZERO
	refresh_scores()
	pending_release = false
	measured_release = false
	placement_error=10.
	success=false
	set_grade_until=0.0
	for i in targets.size(): targets[i].beacon.visible=i==called()
	last_contact = -100
	first_contact = -100
	cushion = 0
	old_palms.clear()
	begin("cart" if not demonstration else "walk")
	coach_goal = rotation_drill.basket.position+rotation_drill.FEED_SPOT
	squat.cancel()
	if jump.active:
		jump.active=false
		setter.position.y=BASE.y
	if demonstration: setter.position = BASE
	setter.rotation.y = atan2(coach.position.x-BASE.x,coach.position.z-BASE.z)
	setter.play_action("idle")
	catch_point = BASE + Vector3.UP*(1.93*setter.height_cm/180.0 + (0.52 if jump_rep() else 0.0))
	coach.show()
	coach.rotation.y = atan2(catch_point.x-coach.position.x,catch_point.z-coach.position.z)
	ball.visible = demonstration or rotation_drill.issued!=null
	apply_camera()
	if demonstration: title.text="COACH DEMO   /   %d OF 3" % (demo_index+1)
	message.text = ("Position 4" if solo_setting else TARGETS[called()])+"    /    "+("Jump set" if jump_rep() else "Standing set")
	if not demonstration:
		var made := 0
		for attempt in scorecard:
			if attempt.setter==rotation_drill.turn and attempt.made: made+=1
		title.text="ZONE %d   /   %s   /   %d/9 MADE" % [[1,6,5][rotation_drill.round_index],TARGETS[called()],made]
		if called()==2: message.text = "72   /   Back set"
	if solo_setting: title.text=camp_title()
	panel.visible=demonstration or rotation_drill.turn==0
	hint.text = ""
	hint.hide()
	meter.value = 0

func apply_camera() -> void:
	var pivot := Vector3(0,1.35,1.0)+camera_lead
	var angle := deg_to_rad(elevation)
	var arm := Vector3(sin(yaw)*cos(angle),sin(angle),-cos(yaw)*cos(angle))*distance
	var obstruction := contacts.sweep(world,contacts.camera_shape,pivot,arm,Contact.GYM)
	camera.position = pivot+arm*float(obstruction.get("fraction",1.0))
	camera.look_at(pivot)

func build_settings() -> void:
	settings.configure(self)
	settings.visibility_changed.connect(func(): rotation_drill.pause_balls(settings.visible))

func arc(a: Vector3,b: Vector3,t: float,height: float) -> Vector3:
	var u := clampf(t,0,1)
	return a.lerp(b,u)+Vector3.UP*4.0*height*u*(1.0-u)

func pad() -> int:
	var pads := Input.get_connected_joypads()
	return active_pad if active_pad in pads else (-1 if pads.is_empty() else pads[0])

func axis(which: JoyAxis) -> float:
	var id := pad()
	return Input.get_joy_axis(id,which) if id >= 0 else 0.0

func set_heading(actor: Node3D,choice: int) -> float:
	var aim: Vector3=(PINS[choice]-actor.position).slide(Vector3.UP).normalized()
	if choice==2: aim=(-aim+Vector3.BACK*.85).normalized()
	return atan2(aim.x,aim.z)

func set_alignment(actor: Node3D,choice: int) -> float:
	var angle := absf(angle_difference(actor.rotation.y,set_heading(actor,choice)))
	return 1.-smoothstep(deg_to_rad(18. if choice==2 else 8.),deg_to_rad(140.),angle)

func facing_scatter(actor: Node3D,choice: int) -> Vector3:
	var radius := (.035 if choice==2 else 0.)+.65*(1.-set_alignment(actor,choice))
	var angle := rotation_drill.random.randf()*TAU
	return Vector3(cos(angle),0,sin(angle))*radius*sqrt(rotation_drill.random.randf())

func track_feed_or_target(dt: float) -> void:
	if not automatic_setter() and axis(Xbox.trigger(true))<=.25 and not Input.is_key_pressed(KEY_CTRL): return
	if held>=0:
		face_set(setter,held,dt)
		return
	var offset := (ball.position-setter.position).slide(Vector3.UP)
	if offset.length()>.12: focus_headings[setter]=atan2(offset.x,offset.z)

func face_set(actor: Node3D,choice: int,dt: float) -> void:
	var heading := set_heading(actor,choice)
	focus_headings[actor]=heading
	actor.rotation.y=rotate_toward(actor.rotation.y,heading,dt*(10./3.))

func select_height(stick: Vector2) -> void:
	if stick.length()<.32:
		stick_latched=false
		return
	if maxf(absf(stick.x),absf(stick.y))<.55: return
	var choice := 1 if stick.y < -absf(stick.x) else 0
	if not stick_latched or choice!=selected_tempo:
		selected_tempo=choice
		preview_until=clock+2.
		preview_enabled=true
	stick_latched=true

func chosen_tempo() -> int:
	return selected_tempo

var still_seconds := 0.0

func move_setter(delta: float,actor: Node3D=setter,off_ball := false) -> bool:
	var motion := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	motion += Vector2(int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)))
	if motion.length()<0.16: motion = Vector2.ZERO
	var direction := Vector3(-motion.x,0,-motion.y).limit_length(1) if off_ball else Vector3.ZERO
	if solo_setting and not off_ball:
		var right := camera.global_basis.x.slide(Vector3.UP).normalized()
		direction=(right*motion.x+right.cross(Vector3.UP)*motion.y).limit_length(1)
	var focus := axis(Xbox.trigger(true))>0.25 or Input.is_key_pressed(KEY_CTRL)
	var sprint := axis(Xbox.trigger(false))>0.25 or Input.is_key_pressed(KEY_SHIFT)
	if not off_ball and focus!=focused:
		focused = focus
		trace("focus",{"active":focus})
		message.text = ("Focused on ball   /   " if focus else "")+TARGETS[called()]
	sprint=sprint and energy[actor].can_sprint()
	if sprint and not direction.is_zero_approx(): energy[actor].spend(delta*25)
	var speed := (4.1 if sprint else 2.35) if focus else (6.2 if sprint else 4.3)
	var previous_position := actor.position
	actor.position = rotation_drill.move_actor(actor,direction*delta*speed)
	if solo_setting and not off_ball: camp_velocity=(actor.position-previous_position)/maxf(.001,delta)
	if not off_ball: actor.position.z = minf(actor.position.z,3.65)
	var at_net := absf(actor.position.z-4.)<1.55 and absf(direction.x)>absf(direction.z)*1.35 and not sprint
	var focus_point := ball.position if ball.visible else coach.position
	var facing := focus_point-actor.position if focus else (coach.position-actor.position if phase=="walk" and direction.is_zero_approx() else direction)
	if at_net and not focus: facing=Vector3(0,0,1 if actor.position.z<4 else -1)
	var choice := free_target if off_ball else held
	if not off_ball and phase in ["feed","pass"] and focus:
		pass # The live feed updates focus after moving the ball this frame.
	elif focus and choice>=0:
		face_set(actor,choice,delta)
	elif Vector2(facing.x,facing.z).length()>0.05:
		actor.rotation.y = rotate_toward(actor.rotation.y,atan2(facing.x,facing.z),delta*(3.33 if focus else 4.5))
	var resting := direction.is_zero_approx() and not focus and not free_squat.charging and not free_jump.active and choice < 0 and (off_ball or phase == "ground")
	still_seconds = still_seconds + delta if resting else 0.0
	if still_seconds >= 3.0:
		actor.play_action("base/Idle",0.65)
	elif solo_setting and not focus and not at_net:
		actor.play_ground_gait(camp_velocity.length())
	else:
		actor.play_action("base/Idle" if at_net else ("idle" if direction.is_zero_approx() or focus else ("base/Sprint" if sprint else "run")))

	if (at_net or focus) and not direction.is_zero_approx():
		var local := actor.basis.orthonormalized().inverse()*direction
		if focus or absf(local.x)>.3:
			if not lateral_steps.has(actor): lateral_steps[actor]=preload("res://scripts/right_side_steps.gd").new(actor)
			var steps: RefCounted=lateral_steps[actor]
			steps.advance(Vector2(-local.x,local.z),delta*(1.65 if focus and sprint else 1.))
			steps.apply_pose(.78 if at_net else 1.)
	return not direction.is_zero_approx()

var angular_speed := {}
var focus_headings := {}

var changing_turn := false

var cpu_goals := {}

func cpu_goal(id: int) -> int:
	if not cpu_goals.has(id):
		for entry in scorecard:
			if entry.setter==id and entry.has("cpu_goal"):
				cpu_goals[id]=entry.cpu_goal
				return cpu_goals[id]
		cpu_goals[id]=rotation_drill.random.randi_range(2,4)
	return cpu_goals[id]

func cpu_aims_inside(id: int) -> bool:
	var remaining := 9
	var needed := cpu_goal(id)
	for entry in scorecard:
		if entry.setter == id:
			remaining -= 1
			if entry.made: needed -= 1
	return remaining > 0 and rotation_drill.random.randi_range(1,remaining) <= needed

func change_setter(skipping: bool) -> void:
	changing_turn = true
	skip.hide()
	var curtain := ColorRect.new()
	curtain.color = Color.BLACK
	curtain.modulate.a = 0
	curtain.z_index = 99
	add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade := create_tween()
	fade.tween_property(curtain,"modulate:a",1.0,0.35)
	await fade.finished
	if skipping:
		var previous := scorecard.duplicate(true)
		var done := 0
		for entry in scorecard:
			if entry.setter == 1: done += 1
		for i in range(done,9):
			var made := cpu_aims_inside(1)
			scorecard.append({"setter":1,"cpu_goal":cpu_goal(1),"target":ORDER[i%3],"station":i/3,"made":made,"error":0.22 if made else 1.65})
		if not save_scorecard():
			scorecard.assign(previous)
			curtain.queue_free()
			changing_turn = false
			return
		rotation_drill.free_ball(Vector3.DOWN)
	rotation_drill.advance_turn()
	for i in 3:
		rotation_drill.roster[i].position = BASE if i == rotation_drill.turn else rotation_drill.WAIT[(i-rotation_drill.turn+3)%3]
	jump.active = false
	skip_time = 0
	camera_lead = Vector3.ZERO
	prompt_phase = ""
	reset_feed()
	fade = create_tween()
	fade.tween_property(curtain,"modulate:a",0.0,0.45)
	await fade.finished
	curtain.queue_free()
	changing_turn = false

func _process(delta: float) -> void:
	spectator_prompt.visible = rotation_drill.turn == 1 and phase not in ["intro","net_guide","complete"] and not demonstration and not settings.visible and not changing_turn
	if changing_turn: return
	update_speech(delta)
	timing_note.visible = clock < timing_until and phase != "complete" and not settings.visible
	score_strip.visible=not solo_setting and phase not in ["intro","net_guide"] and not settings.visible and (not demonstration or phase=="complete")
	if settings.visible or phase=="net_guide": return
	if coach_motion.whistle_cue.step_whistle(coach,delta): return
	if phase=="complete":
		clock+=delta
		rotation_drill.huddle(delta)
		return
	if rotation_drill.turn == 1 and phase != "intro" and not demonstration:
		var holding := Input.is_key_pressed(KEY_SPACE) or (pad() >= 0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
		skip_time = minf(1,skip_time + delta) if holding else 0.0
		spectator_icon.visible = not Xbox.keyboard_prompts()
		if spectator_icon.visible: spectator_icon.texture = Xbox.glyph(JOY_BUTTON_A)
		spectator_text.text = "to start your turn" if spectator_icon.visible else "[Space] to start your turn"
		spectator_progress.value = skip_time
		if skip_time >= 1:
			change_setter(true)
			return
	var before := {}
	for actor in rotation_drill.roster+[coach]+rotation_drill.workers.map(func(w): return w.actor):
		before[actor]=actor.rotation.y
	focus_headings.clear()
	step_practice(delta)
	# Compose all AI, input and animation requests first. Enforce a single
	# turn budget per actor even when several actions change in one frame.
	var dt := minf(delta,.05)
	for actor: Node3D in before:
		if actor==setter and cpu_setting and plant_time>=0.: continue
		var old: float=before[actor]
		var heading: float=focus_headings.get(actor,actor.rotation.y)
		var change := angle_difference(old,heading)
		var limit := 3.33 if focus_headings.has(actor) or (actor==setter and focused) else 4.5
		if actor==setter and automatic_setter() and (held>=0 or phase=="set") and focus_headings.has(actor):
			limit=Hands.CPU_SQUARE_RATE
			if phase=="pass":
				var remaining := maxf(.08,contact_time+cpu_release_delay-elapsed-(.05 if held==2 else .18))
				limit=clampf(absf(change)/remaining,limit,3.45 if held==2 else 4.3)
		if focus_headings.has(actor): limit=minf(limit,sqrt(2.*20.*absf(change)))
		var desired := clampf(change/maxf(.0001,dt),-limit,limit)
		var velocity := move_toward(float(angular_speed.get(actor,0.)),desired,dt*20.)
		if focus_headings.has(actor) and (absf(change)<.001 or (velocity*change>0. and absf(velocity*dt)>=absf(change))):
			actor.rotation.y=heading
			velocity=0.
		else: actor.rotation.y=old+velocity*dt
		angular_speed[actor]=velocity

func receive_stance(yaw_angle: float) -> Vector3:
	var local_head := setter.to_local(Contact.joint(setter,"Head"))
	var offset := (local_head.slide(Vector3.UP)+Vector3.BACK*.19).rotated(Vector3.UP,yaw_angle)
	return camp_receive_spot-offset

func catch_pocket() -> Vector3:
	return Contact.joint(setter,"Head")+Vector3.UP*.235+setter.global_basis.z*.19

func extended_receive_point() -> Vector3:
	return catch_pocket()+Vector3.UP*CATCH_GIVE+setter.global_basis.z*.085

func receive_hand_lift(arrival: float) -> float:
	if solo_setting and elapsed<arrival:
		var distance_to_head := ball.position.distance_to(catch_pocket())
		if elapsed<arrival*.5: return 0.
		return maxf(1.-smoothstep(.85,2.25,distance_to_head),1.-smoothstep(.12,.46,arrival-elapsed))*smoothstep(0.,.14,maxf(0.,clock-pressed_at))
	var remaining := arrival-elapsed
	var held_time := maxf(0.,clock-pressed_at)
	var lift := .48*smoothstep(0.,.50,held_time)+.52*(1.-smoothstep(.035,.34,remaining))
	return lift*smoothstep(0.,.12,held_time)

func shape_catch_hands(lift := 1.) -> void:
	if lift<=0.: return
	var receive := extended_receive_point()
	var contact_weight := 1. if phase!="pass" else 1.-smoothstep(.035,.18,ball.position.distance_to(receive))
	var hand_target := receive.lerp(ball.position,contact_weight)
	Hands.apply(setter,hand_target,lift,Vector3.ZERO,0.,0.,false,Vector3.ZERO,0.,Vector3.INF,0.,true,-1.,null,Vector3.ZERO,true)
	if contact_weight>0. and lift>=.99: Contact.track_hands(setter,hand_target,true,contact_weight,96.)

func player_jump_carry() -> Vector3:
	if phase!="pass" or camp_velocity.length()<.25: return camp_velocity
	# Intersect the descending toss with the forehead along this charged jump.
	var last_gap := ball.position.y-catch_pocket().y
	for frame in range(1,ceili(jump.air_time*120.)):
		var t := frame/120.
		var flight := t/jump.air_time
		var toss_t := elapsed+t
		var toss := source.lerp(forehead_target,toss_t/forehead_arrival)+Vector3.UP*(4.905*toss_t*(forehead_arrival-toss_t))
		var head := forehead_target.y+.055+4.*jump.height*flight*(1.-flight)
		var gap := toss.y-head
		if last_gap>=0. and gap<=0. and t>.05:
			var offset := (toss-catch_pocket()).slide(Vector3.UP)
			var needed := offset/t
			if needed.dot(camp_velocity)>0.:
				return camp_velocity.move_toward(needed,minf(.85,camp_velocity.length()*.25))
			break
		last_gap=gap
	return camp_velocity

func move_to_camp_toss(delta: float) -> void:
	var footwork = setter.skeleton.get_node("GroundTurnSteps")
	var target_yaw := set_heading(setter,called())
	var stance := receive_stance(target_yaw)
	var offset := (stance-setter.position).slide(Vector3.UP)
	var moving_jump := jump_rep() and rep%4==3 and not cpu_jump_started
	if moving_jump:
		var remaining := maxf(.08,contact_time+cpu_release_delay-elapsed-.07)
		var pace := minf(6.2,offset.length()/remaining)
		camp_velocity=camp_velocity.move_toward(offset.normalized()*pace,14.*delta)
		setter.position=rotation_drill.move_actor(setter,(camp_velocity*delta).limit_length(offset.length()))
		setter.play_ground_gait(camp_velocity.length())
		if camp_velocity.length()>4.75: setter.stamina.spend(delta*25.)
		focus_headings[setter]=target_yaw if remaining<.95 else atan2(offset.x,offset.z)
		return
	if plant_time<0. and offset.length()>.16:
		var available := maxf(.15,contact_time-elapsed-PLANT_DURATION-(cpu_jump_lead if jump_rep() else .08))
		var max_pace := 6.2 if offset.length()/available>3.8 else 4.0
		var pace := minf(max_pace,sqrt(2.*14.*offset.length()))
		camp_velocity=camp_velocity.move_toward(offset.normalized()*pace,14.*delta)
		setter.position=rotation_drill.move_actor(setter,(camp_velocity*delta).limit_length(offset.length()))
		setter.play_ground_gait(camp_velocity.length())
		if camp_velocity.length()>4.75: setter.stamina.spend(delta*25.)
		focus_headings[setter]=atan2(offset.x,offset.z)
		return
	if plant_time<0.:
		plant_time=0.
		plant_start_yaw=setter.rotation.y
		setter.play_action("idle",.18)
	plant_time=minf(PLANT_DURATION,plant_time+delta)
	var fraction := plant_time/PLANT_DURATION
	var turn := .22*smoothstep(0.,.38,fraction)+.78*smoothstep(.30,1.,fraction)
	setter.rotation.y=lerp_angle(plant_start_yaw,target_yaw,turn)
	footwork.set_sequence(fraction,true,target_yaw)

func standing_set_load(depth: float) -> void:
	if depth<=0.: return
	var rig: Skeleton3D=setter.skeleton
	var author: RefCounted=setter.get_pose_author()
	var pose: Array=[]
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	var ankles := [author.point(pose,"foot_l"),author.point(pose,"foot_r")]
	var hips := rig.find_bone("pelvis")
	var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(hips))
	pose[hips].origin+=parent.basis.inverse()*(rig.global_basis.inverse()*Vector3.DOWN*.065*depth)
	rig.set_bone_pose_position(hips,pose[hips].origin)
	for i in 2:
		var side := "l" if i==0 else "r"
		var thigh := "thigh_"+side
		var calf := "calf_"+side
		author.limb(pose,thigh,calf,"foot_"+side,ankles[i],Vector3.BACK,1.,180.,true)
		for joint in [thigh,calf]:
			var id := rig.find_bone(joint)
			rig.set_bone_pose_rotation(id,pose[id].basis.get_rotation_quaternion())

func step_practice(delta: float) -> void:
	setter.skeleton.set_meta("fast_set_push",phase=="set_contact" and elapsed+delta>SET_RECEIVE_TIME or phase=="set" and elapsed<.04)
	setter.animator.advance(delta)
	setter.skeleton.set_meta("fixed_setting_hands",true)
	var follow := smoothstep(0.,.060,elapsed)*(1.-smoothstep(.14,.32,elapsed)) if phase=="set" else 0.
	setter.skeleton.set_meta("wrist_follow",follow)
	if not jump.active and not jump_rep():
		if phase=="pass":
			standing_set_load(smoothstep(contact_time-.24,contact_time,elapsed))
		elif phase=="set_contact":
			standing_set_load(1.-smoothstep(SET_RECEIVE_TIME,SET_RECEIVE_TIME+SET_PUSH_TIME,elapsed))
	coach.animator.advance(delta)
	for seat in seats_in_use:
		seat.actor.animator.advance(delta)
		seat.update()
		seat.watch(ball.position if ball.visible else coach.position+Vector3.UP*1.5,delta)
		seat.applause(delta)
	for a in energy:
		energy[a].recover(delta)
		a.exertion_total=energy[a].spent_total
	clock += delta
	elapsed += delta
	if phase == "intro":
		play_intro(delta)
		return
	var stick := Vector2(axis(JOY_AXIS_RIGHT_X),axis(JOY_AXIS_RIGHT_Y))
	stick+=Input.get_vector("ui_left","ui_right","ui_up","ui_down") if (Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN)) else Vector2.ZERO
	select_height(stick)
	if not solo_setting: rotation_drill.tick(delta)
	# Leave the three targets in frame while easing toward the live ball.
	var lead := (ball.position-Vector3(0,1.6,1.0))*Vector3(0.10,0.08,0.055)
	camera_lead = camera_lead.lerp(lead.limit_length(0.5),1.0-exp(-3.2*delta))
	apply_camera()
	if solo_setting and squat.charging:
		camp_velocity=camp_velocity.move_toward(Vector3.ZERO,3.5*delta)
		setter.position=rotation_drill.move_actor(setter,camp_velocity*delta)
	squat.update(setter,delta)
	squat.ring.hide()
	if jump.active: jump.step(setter,delta,Vector2.ZERO)
	elif not automatic_setter() and not squat.charging and (solo_setting or phase!="cart"): move_setter(delta)
	if (jump.active or squat.charging or phase=="cart") and held>=0 and not automatic_setter() and axis(Xbox.trigger(true))>.25: face_set(setter,held,delta)
	match phase:
		"cart":
			var incoming_ready := not jump.active and not squat.charging and (solo_setting or rotation_drill.walk(setter,BASE,delta,5.2))
			if held>=0 and not solo_setting: Hands.apply(setter,catch_point,.18*smoothstep(0.,.5,clock-pressed_at))
			var coach_ready := rotation_drill.station_ready(delta)
			coach_goal = rotation_drill.basket.position+rotation_drill.FEED_SPOT
			if coach_ready and incoming_ready and rotation_drill.floor_clear() and rotation_drill.take_ball():
				setter.rotation.y = atan2(coach.position.x-setter.position.x,coach.position.z-setter.position.z)
				change_feed_phase("feed")
				coach.rotation.y = atan2(catch_point.x-coach.position.x,catch_point.z-coach.position.z)
		"walk":
			var step := coach_goal-coach.position
			if step.length()>0.05:
				coach.rotation.y = atan2(step.x,step.z)
				coach.play_action("base/Walk")
				coach.position = coach.position.move_toward(coach_goal,delta*1.9)
				ball.position = coach.position+Vector3.UP*1.12+coach.basis.z*0.28
			else:
				coach.rotation.y = atan2(catch_point.x-coach.position.x,catch_point.z-coach.position.z)
				coach.play_action("idle")
				change_feed_phase("feed")
		"feed":
			setter.animator.advance(0.0)
			if cpu_setting: setter.play_action("idle")
			if held>=0 and not solo_setting: Hands.apply(setter,catch_point,.18*smoothstep(0.,.5,clock-pressed_at))
			ball.position = coach_motion.toss(coach,clampf((clock-maxf(clock-elapsed,next_release-.30))/.30,0,1))
			track_feed_or_target(delta)
			# Measure the athlete who actually arrived, including their rig scale.
			var head := Contact.joint(setter,"Head")
			forehead_target=head+Vector3.UP*.17+setter.global_basis.z*.048
			forehead_target.y-=maxf(0,setter.position.y-BASE.y)
			if solo_setting:
				forehead_target.x=camp_receive_spot.x
				forehead_target.z=camp_receive_spot.z
			catch_point=forehead_target+Vector3.UP*(.09+(.52 if jump_rep() else 0.))
			if elapsed>=.30 and clock>=next_release and rotation_drill.floor_clear():
				last_toss = clock
				next_release = clock+2.0
				if not demonstration: rotation_drill.tosses+=1
				source = ball.position
				toss_curve=[1.35,2.65,3.95][rotation_drill.tosses%3]*rotation_drill.random.randf_range(.91,1.09)
				if solo_setting:
					var run_distance := (camp_receive_spot-setter.position).slide(Vector3.UP).length()
					var air_time := run_distance/4.8+.45+PLANT_DURATION+(.48 if jump_rep() else .30)
					toss_curve=maxf(3.2,9.81*air_time*air_time/8.)
				var apex := maxf(source.y,catch_point.y)+toss_curve
				if solo_setting: apex=minf(apex,8.15) # Leave clearance under the gym roof steel.
				forehead_arrival=sqrt(2.*(apex-source.y)/9.81)+sqrt(2.*(apex-forehead_target.y)/9.81)
				contact_time=sqrt(2.*(apex-source.y)/9.81)+sqrt(2.*(apex-catch_point.y)/9.81)
				toss_spin=Vector3([-8.0,1.4,7.5][rotation_drill.tosses%3],rotation_drill.random.randf_range(-3,3),rotation_drill.random.randf_range(-2,2))
				trace("coach_release",{"from":str(source),"to":str(catch_point),"arc":toss_curve,"spin":str(toss_spin)})
				cue_until=clock+1.05
				plan_cpu_timing()
				change_feed_phase("pass")
		"pass":
			ball.rotation+=toss_spin*delta
			if cpu_setting and not jump.active: move_to_camp_toss(delta)
			if automatic_setter() and jump_rep() and not cpu_jump_started and not jump.active and elapsed>=contact_time-cpu_jump_lead and elapsed<contact_time:
				cpu_jump_started=true
				energy[setter].spend(5)
				jump.begin_set_jump(setter,.07,.52)
				jump.height=.52
				jump.air_time=jump.flight_duration(.52,true)
				if cpu_setting and rep%4==3:
					var air_remaining := maxf(.08,contact_time+cpu_release_delay-elapsed-jump.load_duration())
					var aim := set_heading(setter,called())
					var stance := receive_stance(aim)
					jump.carry_velocity=((stance-setter.position).slide(Vector3.UP)/air_remaining).limit_length(camp_velocity.length()+.4)
				jump.release()
			if held>=0 and first_contact>=0 and not automatic_setter():
				if clock-first_contact <= HAND_CUSHION:
					ball.position=setter.to_global(contact_local)-Vector3.UP*cushion*smoothstep(0,HAND_CUSHION,clock-first_contact)
					Hands.apply(setter,ball.position,1.0)
					Contact.track_hands(setter,ball.position)
					return
				miss("Held through contact. Release as the ball reaches your hands.")
				return
			var previous := ball.position
			var flight_t := minf(elapsed,forehead_arrival) if cpu_setting else elapsed
			ball.position = source.lerp(forehead_target,flight_t/forehead_arrival)+Vector3.UP*(4.905*flight_t*(forehead_arrival-flight_t))
			if cpu_setting:
				var release_time := contact_time+cpu_release_delay
				var receive := extended_receive_point()
				var settle := smoothstep(release_time-.16,release_time,elapsed)
				var correction := receive-ball.position
				var lateral := correction.slide(Vector3.UP).limit_length(.22)
				ball.position+=(lateral+Vector3.UP*correction.y)*settle
			var incoming := ball.position-previous
			var obstacle := contacts.sweep(world,contacts.ball_shape,previous,incoming,Contact.GYM|Contact.EQUIPMENT|64|rotation_drill.CART_WALL)
			if not obstacle.is_empty():
				ball.position = previous+incoming*float(obstacle.fraction)
				miss("Toss deflected off the gym equipment.")
				drop_velocity = (incoming/maxf(.001,delta)).bounce(obstacle.normal)*.45
				return
			if elapsed<0.16: coach_motion.toss(coach,1.0)
			ball.position.y = maxf(0.15,ball.position.y)
			var turn_gap := angle_difference(setter.rotation.y,set_heading(setter,called()))
			var turn_lead := Hands.preparation_lead(turn_gap,called()==2 and not cpu_setting)
			if cpu_setting: turn_lead=maxf(turn_lead,.48)
			if automatic_setter() and held<0 and elapsed>=.07 and (contact_time+cpu_release_delay-elapsed<=turn_lead or (incoming.y<0 and ball.position.distance_to(catch_point)<=2.10)):
				held = called()
				pressed_at = clock
			if not cpu_setting: track_feed_or_target(delta)
			elif jump.active: focus_headings[setter]=set_heading(setter,called())
			if cpu_setting:
				if held>=0: shape_catch_hands(receive_hand_lift(contact_time+cpu_release_delay))
				if elapsed>=contact_time+cpu_release_delay: release(called())
				return
			if held>=0:
				meter.value = set_fill()*100
				shape_catch_hands(receive_hand_lift(contact_time))
			if held<0 and not automatic_setter():
				var head := Contact.joint(setter,"Head")+Vector3.UP*.10+setter.global_basis.z*.048
				var closest := Geometry3D.get_closest_point_to_segment(head,previous,ball.position)
				if head.distance_to(closest)<.205 and incoming.y<0:
					var normal := (closest-head).normalized()
					miss("Loose ball off the head.")
					drop_velocity=(incoming/maxf(delta,.001)).bounce(normal)*.33
					trace("head_contact",{})
					return
			var collided := false
			for side in ["l","r"]:
				for landmark in ["hand_","index_03_","thumb_03_","middle_02_"]:
					var bone: String = landmark+side
					var hand := Contact.joint(setter,bone)
					if Contact.touched(previous,ball.position,old_palms.get(bone,hand),hand): collided = true
					old_palms[bone] = hand
			if held>=0 and not automatic_setter() and incoming.y<0:
				# Cover the space between the palms as well as individual fingers.
				var pocket := Contact.joint(setter,"Head")+setter.global_basis.z*.095+Vector3.UP*.24
				var closest := Geometry3D.get_closest_point_to_segment(pocket,previous,ball.position)
				if closest.distance_to(pocket)<.19:
					collided=true
					ball.position=closest
			if collided and last_contact<0:
				contact_local=setter.to_local(ball.position)
				first_contact = clock
				last_contact = clock
				cushion = clampf(previous.distance_to(ball.position)/maxf(delta,.001)*.012,.02,.10)
				trace("palm_contact",{"held":held,"give_m":cushion,"ball":str(ball.position),"head":str(Contact.joint(setter,"Head"))})
				if held<0:
					miss("Loose ball off the hands.")
					drop_velocity += setter.basis.z*.85
					return
			if collided: last_contact = clock
			if pending_release and collided:
				release(held)
				return
			if held>=0 and clock-last_contact<.11:
				Hands.apply(setter,ball.position-Vector3.UP*cushion,1.0,Vector3.ZERO,cushion)
			if automatic_setter() and elapsed>=contact_time+cpu_release_delay: release(called())
			elif elapsed>forehead_arrival+0.25: miss("The toss dropped. Hold the target, then release at contact.")
		"set_contact":
			var pocket := catch_pocket()
			if elapsed<=SET_RECEIVE_TIME:
				var t := clampf(elapsed/SET_RECEIVE_TIME,0.,1.)
				ball.position=setter.to_global(receive_local).lerp(pocket,1.-pow(1.-t,2.))
				shape_catch_hands()
				var pads := (Contact.palm(setter,"l")+Contact.palm(setter,"r"))*.5
				ball.position=ball.position.lerp(pads+Vector3.UP*.060,smoothstep(0.,.035,elapsed))
			else:
				var extension := smoothstep(0.,SET_PUSH_TIME,elapsed-SET_RECEIVE_TIME)
				Hands.apply(setter,pocket,1.,push_axis*.23*extension,0.,0.,false,Vector3.ZERO,extension,endpoint-pocket,0.,true,-1.,null,Vector3.ZERO,true)
				# Carry the ball on the finger pads until elbow extension is complete.
				Contact.track_hands(setter,pocket,true,1.-extension)
				var fingers := (Contact.palm(setter,"l")+Contact.palm(setter,"r"))*.5
				ball.position=fingers+Vector3.UP*.060
				if elapsed>=SET_RECEIVE_TIME+SET_PUSH_TIME:
					source=ball.position
					begin("set")
		"forehead_catch":
			var give := 1.-pow(1.-clampf(elapsed/.19,0.,1.),3.)
			ball.position=setter.to_global(catch_start_local).lerp(catch_pocket(),give)
			shape_catch_hands()
			if elapsed>=1.5:
				rotation_drill.free_ball(Vector3.ZERO)
				begin("between")
		"set":
			if automatic_setter() and elapsed<=Hands.CPU_FOLLOW_TIME: face_set(setter,target,delta)
			ball.rotate_x(delta*4.0)
			var t := clampf(elapsed/flight_time,0,1)
			var desired := arc(source,endpoint,t,APEX[tempo])
			var motion := desired-ball.position
			var hit := contacts.sweep(world,contacts.ball_shape,ball.position,motion,Contact.GYM|Contact.EQUIPMENT|64|rotation_drill.CART_WALL)
			ball.position += motion*float(hit.get("fraction",1.0))
			if not hit.is_empty():
				for net in targets:
					if ball.position.distance_to(net.position)<net.mouth_radius+.14: net.impact(ball.position,motion/maxf(delta,.001))
				if absf(ball.position.z-4)<.18: rotation_drill.net_reaction(ball.position,motion/maxf(delta,.001))
				var rebound := (motion/maxf(delta,.001)).bounce(hit.normal)*.45
				if targets[target].rim_bodies.has(hit.get("rid")):
					drop_velocity = rebound
					ball.position += Vector3(hit.normal)*0.004
					begin("rim")
					return
				miss("Ball deflected off the gym equipment.")
				drop_velocity = rebound
				return
			if elapsed<0.22: Hands.apply(setter,source,1.0-elapsed/0.22,push_axis*0.22,0.0,0.3,false,Vector3.ZERO,1.0,endpoint-source,0.5,true)
			if t>=1:
				if endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10: targets[target].impact(ball.position,motion/maxf(delta,.001))
				finish_set()
		"rim":
			var remaining := minf(delta,0.1)
			while remaining > 0.0001:
				var dt := minf(remaining,1.0/120)
				remaining -= dt
				var start := ball.position
				drop_velocity.y -= 9.81*dt
				var motion := drop_velocity*dt
				var hit := contacts.sweep(world,contacts.ball_shape,start,motion,Contact.GYM|Contact.EQUIPMENT|64|rotation_drill.CART_WALL)
				ball.position += motion*float(hit.get("fraction",1.0))
				var net: Node3D = targets[target]
				if net.crossed_mouth(start,ball.position):
					endpoint = ball.position
					placement_error = endpoint.distance_to(net.position)
					success = target == called()
					feedback = "Rim and in" if success else "Wrong target"
					net.impact(ball.position,drop_velocity)
					finish_set()
					return
				if not hit.is_empty():
					drop_velocity = drop_velocity.bounce(hit.normal)*0.45
					ball.position += Vector3(hit.normal)*0.004
				if ball.position.y < net.position.y-0.15 or elapsed > 1.6:
					var velocity := drop_velocity
					miss("Rim and out")
					drop_velocity = velocity
					return
		"drop":
			if not demonstration:
				rotation_drill.free_ball(drop_velocity)
				begin("between")
				message.text = feedback
			else:
				drop_velocity.y-=9.81*delta
				ball.position+=drop_velocity*delta
				if ball.position.y<.16: begin("result")
		"result":
			if success: ball.position = endpoint-Vector3.UP*minf(targets[target].depth-.12,elapsed*3.1)
			if elapsed>.08 and (not demonstration or not jump.active):
				if demonstration:
					demo_index+=1
					if demo_index>=ORDER.size(): demonstration=false
					reset_feed()
				else:
					rotation_drill.free_ball(Vector3.DOWN*.4 if success else (endpoint-source).normalized()*2.9)
					begin("between")
		"between":
			if elapsed>.025 and not jump.active and not free_jump.active:
				if solo_setting:
					rep+=1
					rotation_drill.attempts=rep%3
					reset_feed()
					return
				if rotation_drill.attempts==2: next_release = maxf(next_release,last_toss+3.5)
				var entry := {"setter":rotation_drill.turn,"target":called(),"station":rotation_drill.station,"made":success,"error":placement_error}
				if rotation_drill.turn!=0: entry["cpu_goal"]=cpu_goal(rotation_drill.turn)
				scorecard.append(entry)
				if not save_scorecard():
					scorecard.pop_back()
					return
				show_attempt_feedback(rotation_drill.turn,success)
				if scorecard.size()>=27:
					complete()
					return
				var current_count := 0
				for attempt in scorecard:
					if attempt.setter == rotation_drill.turn: current_count += 1
				if current_count == 9:
					change_setter(false)
					return
				rotation_drill.advance_turn()
				reset_feed()

	rotation_drill.prepare_next_ball(delta)

func play_intro(delta: float) -> void:
	ball.hide()
	var line := mini(2,int(elapsed/4.2))
	camera.position = [Vector3(4.2,2.9,-3),Vector3(-0.3,1.85,3.8),Vector3(3.2,4.2,-4.5)][line]+Vector3.RIGHT*0.12*fmod(elapsed,4.2)
	camera.look_at(coach.position+Vector3.UP*1.5 if line==1 else setter.position+Vector3.UP*1.4)
	coach.rotation.y = atan2(setter.position.x-coach.position.x,setter.position.z-coach.position.z)
	title.text = "INDOOR  /  DAY ONE     •     COACH ELLIS"
	message.text = ""
	if line != intro_line:
		intro_line = line
		say(coach, LINES[0] % CareerSession.profile().name if line==0 else LINES[line], 4.2)
	hint.hide()
	var holding := Input.is_key_pressed(KEY_SPACE) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
	skip_time = minf(1,skip_time+delta) if holding else 0.0
	skip.visible = true
	skip.value = skip_time*100
	if skip_time>=1 or elapsed>=12.6:
		if finish_intro():
			speech_left = 0
			skip.hide()
			start_practice()

func finish_set() -> void:
	if success and not demonstration:
		if rotation_drill.turn==0:
			gym.update_board(rep+1)
		for i in seats_in_use.size():
			seats_in_use[i].celebrate(i,rep%8==0)
		trace("bleacher_applause",{"completed":rep})
	begin("result")
	message.text = feedback
	if not success and measured_release: show_timing(set_error)

func miss(reason: String) -> void:
	success = false
	if measured_release: show_timing(set_error)
	trace("miss",{"reason":reason})
	drop_velocity = (forehead_target-source)/forehead_arrival+Vector3.UP*9.81*(forehead_arrival/2.0-elapsed)
	feedback = reason
	begin("drop")
	message.text = reason

func show_timing(offset: float) -> void:
	if automatic_setter(): return
	var percent := roundi(100.0 * absf(offset) / timing_window())
	timing_note.text = "%d%% too %s" % [percent,"early" if offset < 0 else "late"] if percent > 0 else "On time"
	timing_note.reset_size()
	timing_until = clock + 2.2

func timing_window() -> float:
	return .085+.135*clampf(float(setter.effective_rating("Hand setting"))/100.,0,1)

# Predict arrival in flight, then anchor the cue to the hands cushioning the ball.
func release_offset() -> float:
	if first_contact>=0: return clock-first_contact-.055
	return elapsed-contact_time

func set_fill() -> float:
	var age := maxf(0.,clock-pressed_at)
	var ready := .30*(1.-exp(-age*5.))
	if phase!="pass": return ready
	var offset := release_offset()
	var window := timing_window()
	if offset < -window:
		var remaining := -offset-window
		return lerpf(ready,.55,age/(age+remaining))
	return clampf(.70+.15*offset/window,0.,1.)

func release(index: int) -> void:
	if phase!="pass" or held!=index: return
	graded_fill=set_fill()
	if not pending_release:
		var raw_offset := release_offset()
		set_error = raw_offset
		input_hold=clock-pressed_at
		if not automatic_setter():
			set_error = signf(raw_offset)*maxf(0.,absf(raw_offset)-ON_TIME)
			trace("set_button_up",{"raw_offset_s":raw_offset,"held_s":input_hold,"ball":str(ball.position),"head":str(Contact.joint(setter,"Head"))})
		if first_contact < 0 and not automatic_setter() and raw_offset <= ON_TIME and raw_offset >= -(timing_window()+0.065):
			pending_release = true
			measured_release = true
			return
	pending_release = false
	measured_release = true
	set_grade_until=clock+.65
	trace("release",{"target":TARGETS[index],"held_s":input_hold,"alignment":set_alignment(setter,index),"timing_error":set_error,"air_m":setter.position.y-BASE.y})
	held = -1
	var skill := float(setter.effective_rating("Hand setting"))/100
	var gap := Vector2(setter.position.x-catch_point.x,setter.position.z-catch_point.z).length()
	var airborne := setter.position.y-BASE.y
	var technique_feedback := ""
	if not automatic_setter():
		if jump_rep() and airborne<.20: technique_feedback="Jump set requested. Jump before contact."
		elif not jump_rep() and airborne>.12: technique_feedback="Standing set requested. Stay planted."
		if first_contact<0 or clock-last_contact>HAND_CUSHION:
			miss("No hand contact. Get under the ball before release.")
			return
		if set_error < -(timing_window()+0.065) or set_error > timing_window() or gap>0.72+0.36*skill:
			miss("Missed contact. Hold the target and release above your forehead.")
			return
	target = index
	tempo = chosen_tempo() if not automatic_setter() else 1
	source = ball.position
	flight_time = DURATION[tempo]
	var error := 0.0 if demonstration else set_error*(3.6-skill)+gap*0.22
	endpoint = PINS[target]+Vector3(error,0,error*0.4)
	if not demonstration and not cpu_setting:
		endpoint+=facing_scatter(setter,target)
	if cpu_setting:
		# Timing the push early or late displaces the set along its intended line.
		var aim: Vector3=(PINS[target]-setter.position).slide(Vector3.UP).normalized()
		endpoint=PINS[target]+aim*(cpu_release_delay*12.)+facing_scatter(setter,target)
	elif rotation_drill.turn!=0 and not demonstration:
		var angle := rotation_drill.random.randf()*TAU
		var distance := rotation_drill.random.randf_range(.03,.15) if cpu_aims_inside(rotation_drill.turn) else rotation_drill.random.randf_range(.82,1.55)
		endpoint = PINS[target]+Vector3(cos(angle),0,sin(angle))*distance
	elif not demonstration:
		# Poor releases can carry past the pin into the tape or court.
		var late := clampf((absf(set_error)-.065)/.135,0,1)
		endpoint.z += 1.5*late
	endpoint=setter.reachable_set(source,endpoint)
	energy[setter].spend(2)
	placement_error=endpoint.distance_to(PINS[target])
	success = technique_feedback.is_empty() and target==called() and endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10
	feedback = TARGETS[target]+"   /   Target made" if success else "Missed the called target. Try it again."
	if not technique_feedback.is_empty(): feedback=technique_feedback
	if set_error < -timing_window(): show_timing(set_error)
	trace("set",{"technique":technique_feedback,"requested":TARGETS[called()],"actual":TARGETS[target],"made":success,"error_m":error})
	receive_local=setter.to_local(ball.position)
	push_axis=((endpoint-source).slide(Vector3.UP).normalized()*.60+Vector3.UP*.80).normalized()
	shape_catch_hands()
	begin("set_contact")

var bubble := PanelContainer.new()
var words := Label.new()
var speaker: Node3D
var speech_left := 0.0
var intro_line := -1

func say(actor: Node3D, speech: String, seconds: float) -> void:
	speaker = actor
	words.text = speech
	speech_left = seconds
	bubble.reset_size()
	update_speech(0)

func update_speech(delta: float) -> void:
	speech_left = maxf(0, speech_left - delta)
	bubble.visible = speech_left > 0 and not settings.visible
	if not bubble.visible: return
	var target := head_position(speaker) + Vector3.UP * 0.25
	if camera.is_position_behind(target):
		bubble.hide()
		return
	var tip := camera.unproject_position(target)
	bubble.position = (tip - Vector2(bubble.size.x / 2, bubble.size.y + 8)).clamp(Vector2.ZERO, (size - bubble.size).max(Vector2.ZERO))
	bubble.modulate.a = minf(1, speech_left / 0.35)

func head_position(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	return rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)

func portrait(actor: Node3D) -> TextureRect:
	var photo := TextureRect.new()
	photo.texture = actor.get_meta("school_photo")
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.custom_minimum_size = Vector2(50, 50)
	photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var mask := Shader.new()
	mask.code = """shader_type canvas_item;
	void fragment() {
		float r = length(UV - vec2(0.5));
		vec3 photo = texture(TEXTURE, UV).rgb;
		COLOR = vec4(mix(photo,vec3(0.68,0.85,0.83),smoothstep(0.46,0.48,r)),1.0-smoothstep(0.48,0.5,r));
	}"""
	var mat := ShaderMaterial.new()
	mat.shader = mask
	photo.material = mat
	return photo

func build_score_strip() -> void:
	add_child(bubble)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 4
	var style := MenuPresentation.box(Color("f5f5ef"),Color("304957"),2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	bubble.add_theme_stylebox_override("panel",style)
	words.custom_minimum_size.x = 260
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_theme_color_override("font_color",Color("172b39"))
	bubble.add_child(words)
	var tail := Polygon2D.new()
	tail.color = Color("f5f5ef")
	tail.polygon = PackedVector2Array([Vector2(-8,-3),Vector2(8,-3),Vector2(0,8)])
	bubble.add_child(tail)
	bubble.resized.connect(func(): tail.position = Vector2(bubble.size.x / 2, bubble.size.y - 2))
	bubble.hide()
	var anchor := CenterContainer.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top=12
	anchor.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	anchor.add_child(score_strip)
	for actor in rotation_drill.roster:
		var card := PanelContainer.new()
		card.mouse_filter=Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel",MenuPresentation.box(Color("102431e8"),Color("50636d"),1))
		score_strip.add_child(card)
		var label := Label.new()
		label.custom_minimum_size=Vector2(156,38)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",16)
		var stack := VBoxContainer.new()
		card.add_child(stack)
		stack.add_child(portrait(actor))
		var nameplate := Label.new()
		nameplate.text = actor.display_name
		nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(nameplate)
		card.tooltip_text = "%s / Age %d / %s / %s-handed" % [actor.display_name,actor.attributes.age,actor.attributes.hometown,actor.handedness]
		stack.add_child(label)
		score_labels.append(label)
	add_child(score_cue)

func refresh_scores() -> void:
	for i in score_labels.size():
		var hits := 0
		var taken := 0
		for entry in scorecard:
			if entry.setter==i:
				taken+=1
				if entry.made: hits+=1
		score_labels[i].text="%d/%d made" % [hits,taken]
		score_labels[i].add_theme_color_override("font_color",Color("ffce75") if i==rotation_drill.turn else Color.WHITE)

func show_attempt_feedback(index: int,made: bool) -> void:
	refresh_scores()
	var label := score_labels[index]
	label.modulate=Color("74f6a9") if made else Color("ff9283")
	var tween := create_tween()
	tween.tween_interval(.65)
	tween.tween_property(label,"modulate",Color.WHITE,.35)
	score_cue.stream=preload("res://assets/audio/tryout_made.wav") if made else preload("res://assets/audio/tryout_miss.wav")
	score_cue.play()

func save_scorecard() -> bool:
	if rotation_drill.turn==0 and success: rep+=1
	return true

func rankings() -> Array:
	var table := []
	for i in 3: table.append({"id":i,"made":0,"error":0.})
	for attempt in scorecard:
		var row: Dictionary=table[attempt.setter]
		if attempt.made: row.made+=1
		row.error+=attempt.error
	table.sort_custom(func(a,b):
		if a.made!=b.made: return a.made>b.made
		if a.error!=b.error: return a.error<b.error
		return a.id<b.id)
	return table

func complete() -> void:
	coach_motion.whistle_cue.signal_drill(coach)
	for net in targets: net.beacon.hide()
	begin("complete")
	refresh_scores()
	for actor in rotation_drill.roster+rotation_drill.workers.map(func(w): return w.actor):
		actor.play_action("base/Idle",0.)
		actor.animator.advance(0.)
	camera.position = Vector3(-2.7,2.65,-5.6)
	camera.fov=40.
	camera.look_at(rotation_drill.HUDDLE_CENTER+Vector3.UP*1.04)
	ball.hide()
	coach.show()
	panel.show()
	title.text = "INDOOR PRACTICE"
	message.text = "Practice complete"
	hint.hide()
	finish.show()
	retry.show()
	retry.grab_focus()

func trace(kind: String, fields: Dictionary) -> void:
	fields.merge({"phase":phase,"rep":rep+1,"demo":demonstration,"phase_s":elapsed})
	InteractionTrace.record(kind,fields)

func change_feed_phase(next: String) -> void:
	if next=="feed": cue_until=clock+1.05
	var prepared := held
	begin(next)
	held = prepared

func _exit_tree() -> void:
	get_viewport().scaling_3d_scale=original_render_scale
	get_viewport().msaa_3d=original_msaa
	if slow_motion: Engine.time_scale=previous_time_scale
	coach_motion.dispose()

func _input(event: InputEvent) -> void:
	if changing_turn: return
	if phase=="net_guide": return
	if event is InputEventKey and event.echo: return
	if get_tree().paused: return
	if settings.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START) and event.pressed):
			settings.hide()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		active_pad = event.device
	if (event is InputEventKey and event.keycode==KEY_ESCAPE or event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START)) and event.is_pressed():
		trace("pause",{})
		squat.cancel()
		settings.show()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.button_index==JOY_BUTTON_DPAD_UP and event.pressed and phase!="intro":
		if not slow_motion: previous_time_scale=Engine.time_scale
		slow_motion=not slow_motion
		Engine.time_scale=previous_time_scale*(.35 if slow_motion else 1.)
		get_viewport().set_input_as_handled()
		return
	if phase in ["intro","complete"]: return
	if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_LEFT_STICK) and event.pressed:
		preview_enabled=not preview_enabled
		get_viewport().set_input_as_handled()
		return
	if solo_setting and ((event is InputEventJoypadButton and event.button_index==JOY_BUTTON_BACK) or (event is InputEventKey and event.physical_keycode==KEY_TAB)):
		if event.is_pressed(): switch_camp_control()
		get_viewport().set_input_as_handled()
		return
	if cpu_setting: return
	if rotation_drill.turn!=0 and not demonstration:
		if rotation_drill.turn == 1 and ((event is InputEventJoypadButton and event.button_index == Xbox.physical(JOY_BUTTON_A)) or (event is InputEventKey and event.keycode == KEY_SPACE)): return
		free_input(event)
		return
	if demonstration:
		if event is InputEventJoypadButton: trace("input_in_demo",{"id":event.button_index})
		return
	if (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_LEFT_SHOULDER) or event is InputEventKey and event.keycode==KEY_ENTER) and event.is_pressed() and phase=="ground":
		reset_feed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A) or event is InputEventKey and event.keycode==KEY_SPACE:
		if event.is_pressed():
			var allowed := not jump.active and not squat.charging
			trace("squat_press",{"accepted":allowed})
			if allowed:
				energy[setter].spend(5)
				squat.begin(setter)
				message.text = "Release in green to jump"
		elif squat.charging:
			message.text = squat.release(setter,jump)
			if solo_setting: jump.carry_velocity=player_jump_carry()
			trace("jump_release",{"seconds":squat.seconds,"quality":message.text,"height":jump.height})
		get_viewport().set_input_as_handled()
		return
	var index := -1
	if event is InputEventJoypadButton:
		for i in BUTTONS.size():
			if event.button_index==Xbox.physical(BUTTONS[i]): index = i
	elif event is InputEventKey: index = KEYS.find(event.keycode)
	if index<0: return
	if solo_setting and index!=0: return
	if phase not in ["cart","walk","feed","pass"]:
		trace("target_unavailable",{"target":TARGETS[index],"down":event.is_pressed()})
		if phase=="ground": message.text = "Call the next toss"
	elif event.is_pressed():
		pending_release = false
		held = index
		pressed_at = clock
		message.text = "Preparing   /   "+TARGETS[index]
		trace("prepare",{"target":TARGETS[index]})
	elif held==index:
		if phase=="pass": release(index)
		else:
			trace("released_before_toss",{"target":TARGETS[index]})
			held = -1
			message.text = "Released before the toss"
	else: trace("unmatched_release",{"target":TARGETS[index]})
	get_viewport().set_input_as_handled()

func end_free_motion() -> void:
	free_squat.cancel()
	free_jump.active=false
	free_target=-1
	rotation_drill.roster[0].position.y=BASE.y

func free_motion(dt: float,actor: Node3D) -> bool:
	free_squat.update(actor,dt)
	free_squat.ring.hide()
	if free_jump.active: free_jump.step(actor,dt,Vector2.ZERO)
	if free_target>=0:
		if axis(Xbox.trigger(true))>.25: face_set(actor,free_target,dt)
		var hands: Vector3 = actor.position+Vector3.UP*(actor.height_cm*.0108)+actor.basis.z*.14
		Hands.apply(actor,hands,smoothstep(0,.22,clock-free_press))
	return free_jump.active or free_squat.charging or free_target>=0

func free_input(event: InputEvent) -> void:
	var actor := rotation_drill.roster[0]
	if rotation_drill.unloading.has(actor): return
	if (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_A)) or (event is InputEventKey and event.keycode==KEY_SPACE):
		if event.is_pressed() and not free_squat.charging and not free_jump.active:
			energy[actor].spend(5)
			free_squat.begin(actor)
		elif not event.is_pressed() and free_squat.charging: free_squat.release(actor,free_jump)
		rotation_drill.manual_wait=true
		get_viewport().set_input_as_handled()
		return
	for i in BUTTONS.size():
		if not ((event is InputEventJoypadButton and event.button_index==Xbox.physical(BUTTONS[i])) or (event is InputEventKey and event.keycode==KEYS[i])): continue
		if event.is_pressed():
			free_target=i
			free_press=clock
			rotation_drill.manual_wait=true
		elif free_target==i:
			free_target=-1
			var palms := (Contact.palm(actor,"l")+Contact.palm(actor,"r"))*.5
			var body: RigidBody3D
			if not rotation_drill.human_cargo.is_empty():
				body=rotation_drill.human_cargo.pop_back()
				body.position=palms
				rotation_drill.loose.append(body)
			else:
				for candidate in rotation_drill.loose:
					if not candidate.freeze and candidate.position.distance_to(palms)<.38: body=candidate; break
			if body:
				body.freeze=false
				body.collision_layer=128
				body.sleeping=false
				var duration: float=DURATION[chosen_tempo()]
				body.linear_velocity=(PINS[i]+facing_scatter(actor,i)-body.position)/duration+Vector3.UP*4.905*duration
				energy[actor].spend(2)
			trace("off_turn_set",{"target":TARGETS[i],"contact":body!=null})
		get_viewport().set_input_as_handled()
		return
