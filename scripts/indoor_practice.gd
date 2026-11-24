extends Control

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
const SET_LOAD := .26
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
var skip_time := 0.0
var camera_lead := Vector3.ZERO
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
var demonstration := false
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
	setter.apply_profile(CareerSession.profile())
	setter.play_action("idle")
	coach = athlete(Vector3(-2.5,0.04,-1.2),"48574d")
	coach.play_action("idle")
	preload("res://scripts/practice_kit.gd").apply(setter,false)
	preload("res://scripts/practice_kit.gd").apply(coach,true)
	coach_motion.dress(coach)
	seat_teammates()
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
	for a in rotation_drill.roster: energy[a]=preload("res://scripts/player_stamina.gd").new()
	var rings := preload("res://scripts/tryout_player_ring.gd").new()
	rings.game=self
	add_child(rings)
	squat.configure(world)
	free_squat.configure(world)
	free_jump.front_limit=14.0
	build_hud()
	build_score_strip()
	build_settings()
	start_drill()

func finish_intro() -> bool:
	return true

func reset_drill() -> void:
	trace("drill_reset",{})
	get_tree().reload_current_scene()

func start_drill() -> void:
	start_practice()

func seat_teammates() -> void:
	var seats := [[-1,1,-3.0],[1,0,-1.1],[-1,1,0.9],[1,0,1.4],[-1,2,3.3],[1,1,4.2],[-1,0,5.5],[1,2,6.0],[-1,2,7.8],[1,1,8.0]]
	for i in seats.size():
		var seat: Array = seats[i]
		var side := int(seat[0])
		var row := int(seat[1])
		var athlete_ := athlete(Vector3(side*(6.8+row*.69),0,float(seat[2])),["245447","a34d31","334357"][i%3])
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
	skip.hide()

func begin(next: String) -> void:
	trace("phase",{"next":next})
	update_prompts(next)
	meter.hide()
	phase = next
	elapsed = 0
	held = -1

func update_prompts(next: String) -> void:
	var group := next if next in ["intro","complete","ground"] else "practice"
	if group==prompt_phase: return
	prompt_phase = group
	var entries := []
	match group:
		"intro": entries = [[JOY_BUTTON_A,"Hold to skip"]]
		"complete": entries = [[JOY_BUTTON_A,"Continue"]]
		"ground": entries = [[JOY_BUTTON_LEFT_SHOULDER,"Next toss"],[JOY_BUTTON_START,"Settings"]]
		_:
			for i in BUTTONS.size(): entries.append([BUTTONS[i],TARGETS[i]])
			entries.append_array([["RS","Set height"],[JOY_BUTTON_LEFT_STICK,"Show / hide arc"],[JOY_BUTTON_RIGHT_STICK,"R3 hold / release jump" if Xbox.physical(JOY_BUTTON_RIGHT_STICK)==JOY_BUTTON_RIGHT_STICK else "Hold / release jump"],["LT","Focus"],["RT","Sprint"],[JOY_BUTTON_START,"Settings"]])
	Xbox.prompts(controls_row,entries)

func leave() -> void:
	get_tree().change_scene_to_file("res://scenes/story.tscn")

func start_practice() -> void:
	demonstration = false
	demo_index = 0
	reset_feed()

func jump_rep() -> bool:
	return demo_index%2==1 if demonstration else rotation_drill.round_index==1

func called() -> int:
	return ORDER[demo_index if demonstration else rotation_drill.attempts]

func reset_feed() -> void:
	refresh_scores()
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
	message.text = TARGETS[called()]+"    /    "+("Jump set" if jump_rep() else "Standing set")
	if not demonstration:
		var made := 0
		for attempt in scorecard:
			if attempt.setter==rotation_drill.turn and attempt.made: made+=1
		title.text="%s   /   ZONE %d   /   %s   /   %d/9 MADE" % [setter.display_name,[1,6,5][rotation_drill.round_index],TARGETS[called()],made]
		if called()==2: message.text = "72   /   Back set"
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
	var radius := (.035 if choice==2 else 0.)+.32*(1.-set_alignment(actor,choice))
	var angle := rotation_drill.random.randf()*TAU
	return Vector3(cos(angle),0,sin(angle))*radius*sqrt(rotation_drill.random.randf())

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

func move_setter(delta: float,actor: Node3D=setter,off_ball := false) -> bool:
	var motion := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	motion += Vector2(int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)))
	if motion.length()<0.16: motion = Vector2.ZERO
	var direction := Vector3(-motion.x,0,-motion.y).limit_length(1) if off_ball else Vector3.ZERO
	var focus := axis(Xbox.trigger(true))>0.25 or Input.is_key_pressed(KEY_CTRL)
	var sprint := axis(Xbox.trigger(false))>0.25 or Input.is_key_pressed(KEY_SHIFT)
	if not off_ball and focus!=focused:
		focused = focus
		trace("focus",{"active":focus})
		message.text = ("Focused on ball   /   " if focus else "")+TARGETS[called()]
	sprint=sprint and energy[actor].can_sprint()
	if sprint and not direction.is_zero_approx(): energy[actor].spend(delta*25)
	var speed := (4.1 if sprint else 2.35) if focus else (6.2 if sprint else 4.3)
	actor.position = rotation_drill.move_actor(actor,direction*delta*speed)
	if not off_ball: actor.position.z = minf(actor.position.z,3.65)
	var at_net := absf(actor.position.z-4.)<1.55 and absf(direction.x)>absf(direction.z)*1.35 and not sprint
	var facing := ball.position-actor.position if focus else (coach.position-actor.position if phase=="walk" and direction.is_zero_approx() else direction)
	if at_net and not focus: facing=Vector3(0,0,1 if actor.position.z<4 else -1)
	var choice := free_target if off_ball else held
	if focus and choice>=0:
		face_set(actor,choice,delta)
	elif Vector2(facing.x,facing.z).length()>0.05:
		actor.rotation.y = rotate_toward(actor.rotation.y,atan2(facing.x,facing.z),delta*(3.33 if focus else 4.5))
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

func _process(delta: float) -> void:
	score_strip.visible=phase not in ["intro","complete","net_guide"] and not settings.visible and not demonstration
	if settings.visible or phase=="net_guide": return
	if phase=="complete":
		clock+=delta
		rotation_drill.huddle(delta)
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
		var old: float=before[actor]
		var heading: float=focus_headings.get(actor,actor.rotation.y)
		var change := angle_difference(old,heading)
		var limit := 3.33 if focus_headings.has(actor) or (actor==setter and focused) else 4.5
		if focus_headings.has(actor): limit=minf(limit,sqrt(2.*20.*absf(change)))
		var desired := clampf(change/maxf(.0001,dt),-limit,limit)
		var velocity := move_toward(float(angular_speed.get(actor,0.)),desired,dt*20.)
		if focus_headings.has(actor) and (absf(change)<.001 or (velocity*change>0. and absf(velocity*dt)>=absf(change))):
			actor.rotation.y=heading
			velocity=0.
		else: actor.rotation.y=old+velocity*dt
		angular_speed[actor]=velocity

func step_practice(delta: float) -> void:
	setter.animator.advance(delta)
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
	rotation_drill.tick(delta)
	# Leave the three targets in frame while easing toward the live ball.
	var lead := (ball.position-Vector3(0,1.6,1.0))*Vector3(0.10,0.08,0.055)
	camera_lead = camera_lead.lerp(lead.limit_length(0.5),1.0-exp(-3.2*delta))
	apply_camera()
	squat.update(setter,delta)
	squat.ring.hide()
	if jump.active: jump.step(setter,delta,Vector2.ZERO)
	elif not demonstration and rotation_drill.turn==0 and not squat.charging and phase!="cart": move_setter(delta)
	if (jump.active or squat.charging or phase=="cart") and held>=0 and rotation_drill.turn==0 and axis(Xbox.trigger(true))>.25: face_set(setter,held,delta)
	match phase:
		"cart":
			var incoming_ready := not jump.active and not squat.charging and rotation_drill.walk(setter,BASE,delta,5.2)
			if held>=0: Hands.apply(setter,catch_point,.55)
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
			if demonstration or rotation_drill.turn!=0: face_set(setter,called(),delta)
			if held>=0: Hands.apply(setter,catch_point,.55)
			ball.position = coach_motion.toss(coach,clampf((clock-maxf(clock-elapsed,next_release-.30))/.30,0,1))
			# Measure the athlete who actually arrived, including their rig scale.
			var head := Contact.joint(setter,"Head")
			catch_point.y=BASE.y+head.y-setter.position.y+.20+(.52 if jump_rep() else 0.)
			catch_point.x=head.x
			catch_point.z=head.z
			if elapsed>=.30 and clock>=next_release and rotation_drill.floor_clear():
				last_toss = clock
				next_release = clock+2.0
				if not demonstration: rotation_drill.tosses+=1
				source = ball.position
				toss_curve=[.55,1.35,2.65][rotation_drill.tosses%3]*rotation_drill.random.randf_range(.91,1.09)
				var apex := maxf(source.y,catch_point.y)+toss_curve
				contact_time=sqrt(2.*(apex-source.y)/9.81)+sqrt(2.*(apex-catch_point.y)/9.81)
				toss_spin=Vector3([-8.0,1.4,7.5][rotation_drill.tosses%3],rotation_drill.random.randf_range(-3,3),rotation_drill.random.randf_range(-2,2))
				trace("coach_release",{"from":str(source),"to":str(catch_point),"arc":toss_curve,"spin":str(toss_spin)})
				cue_until=clock+1.05
				change_feed_phase("pass")
		"pass":
			ball.rotation+=toss_spin*delta
			if demonstration or rotation_drill.turn!=0:
				face_set(setter,called(),delta)
			if (demonstration or rotation_drill.turn!=0) and jump_rep() and not jump.active and elapsed>=contact_time-.40 and elapsed<contact_time-.22:
				energy[setter].spend(5)
				jump.begin_set_jump(setter,.07,.52)
				jump.height=.52
				jump.air_time=jump.flight_duration(.52,true)
				jump.release()
			var previous := ball.position
			ball.position = source.lerp(catch_point,elapsed/contact_time)+Vector3.UP*(4.905*elapsed*(contact_time-elapsed))
			var incoming := ball.position-previous
			var obstacle := contacts.sweep(world,contacts.ball_shape,previous,incoming,Contact.GYM|Contact.EQUIPMENT|64)
			if not obstacle.is_empty():
				ball.position = previous+incoming*float(obstacle.fraction)
				miss("Toss deflected off the gym equipment.")
				drop_velocity = (incoming/maxf(.001,delta)).bounce(obstacle.normal)*.45
				return
			if elapsed<0.16: coach_motion.toss(coach,1.0)
			ball.position.y = maxf(0.15,ball.position.y)
			if (demonstration or rotation_drill.turn!=0) and held<0 and elapsed>=contact_time-SET_LOAD:
				held = called()
				pressed_at = clock
			if held>=0:
				if held==2 and called()==2 and not demonstration and rotation_drill.turn==0 and not focused:
					var opposite := (setter.position-PINS[2]).slide(Vector3.UP)
					setter.rotation.y=lerp_angle(setter.rotation.y,atan2(opposite.x,opposite.z),minf(1,delta*9))
				meter.value = set_fill()*100
				Hands.apply(setter,ball.position,0.35+0.65*smoothstep(contact_time-.55,contact_time-.10,elapsed))
				if Vector3(0,ball.position.y-setter.position.y,0).length()<setter.height_cm*.013: Contact.track_hands(setter,ball.position)
			if held<0 and not demonstration and rotation_drill.turn==0:
				var head := Contact.joint(setter,"Head")+Vector3.UP*.10
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
			if collided and last_contact<0:
				first_contact = clock
				last_contact = clock
				cushion = clampf(previous.distance_to(ball.position)/maxf(delta,.001)*.012,.02,.10)
				trace("palm_contact",{"held":held,"give_m":cushion})
				if held<0:
					miss("Loose ball off the hands.")
					drop_velocity += setter.basis.z*.85
					return
			if collided: last_contact = clock
			if held>=0 and clock-last_contact<.11:
				Hands.apply(setter,ball.position-Vector3.UP*cushion,1.0,Vector3.ZERO,cushion)
			if (demonstration or rotation_drill.turn!=0) and elapsed>=contact_time: release(called())
			elif elapsed>contact_time+0.25: miss("The toss dropped. Hold the target, then release at contact.")
		"set":
			ball.rotate_x(delta*4.0)
			var t := clampf(elapsed/flight_time,0,1)
			var desired := arc(source,endpoint,t,APEX[tempo])
			var motion := desired-ball.position
			var hit := contacts.sweep(world,contacts.ball_shape,ball.position,motion,Contact.GYM|Contact.EQUIPMENT|64)
			ball.position += motion*float(hit.get("fraction",1.0))
			if not hit.is_empty():
				for net in targets:
					if ball.position.distance_to(net.position)<net.mouth_radius+.14: net.impact(ball.position,motion/maxf(delta,.001))
				if absf(ball.position.z-4)<.18: rotation_drill.net_reaction(ball.position,motion/maxf(delta,.001))
				miss("Ball deflected off the gym equipment.")
				drop_velocity = (motion/maxf(delta,.001)).bounce(hit.normal)*.45
				return
			if elapsed<0.22: Hands.apply(setter,source,1.0-elapsed/0.22,(endpoint-source).normalized()*0.22,0.0,0.3,false,Vector3.ZERO,1.0,endpoint-source,0.5,true)
			if t>=1:
				if endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10: targets[target].impact(ball.position,motion/maxf(delta,.001))
				if success and not demonstration:
					if rotation_drill.turn==0:
						gym.update_board(rep+1)
					for i in seats_in_use.size():
						seats_in_use[i].celebrate(i,rep%8==0)
					trace("bleacher_applause",{"completed":rep})
				begin("result")
				message.text = feedback
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
				if rotation_drill.attempts==2: next_release = maxf(next_release,last_toss+3.5)
				var entry := {"setter":rotation_drill.turn,"target":called(),"station":rotation_drill.station,"made":success,"error":placement_error}
				scorecard.append(entry)
				if not save_scorecard():
					scorecard.pop_back()
					return
				show_attempt_feedback(rotation_drill.turn,success)
				if scorecard.size()>=27:
					complete()
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
	message.text = LINES[0] % CareerSession.profile().name if line==0 else LINES[line]
	hint.hide()
	var holding := Input.is_key_pressed(KEY_SPACE) or (pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(JOY_BUTTON_A)))
	skip_time = minf(1,skip_time+delta) if holding else 0.0
	skip.visible = true
	skip.value = skip_time*100
	if skip_time>=1 or elapsed>=12.6:
		if finish_intro():
			skip.hide()
			start_practice()

func miss(reason: String) -> void:
	success = false
	trace("miss",{"reason":reason})
	drop_velocity = (catch_point-source)/contact_time+Vector3.UP*9.81*(contact_time/2.0-elapsed)
	feedback = reason
	begin("drop")
	message.text = reason

func timing_window() -> float:
	return .085+.135*clampf(float(setter.attributes.get("Hand setting",40))/100.,0,1)

# Predict arrival in flight, then anchor the cue to the hands cushioning the ball.
func release_offset() -> float:
	if first_contact>=0: return clock-first_contact-.045
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
	set_error=release_offset()
	set_grade_until=clock+.65
	trace("release",{"target":TARGETS[index],"held_s":clock-pressed_at,"alignment":set_alignment(setter,index),"timing_error":set_error,"air_m":setter.position.y-BASE.y})
	held = -1
	var skill := float(setter.attributes.get("Hand setting",40))/100
	var gap := Vector2(setter.position.x-catch_point.x,setter.position.z-catch_point.z).length()
	var airborne := setter.position.y-BASE.y
	var technique_feedback := ""
	if not demonstration and rotation_drill.turn==0:
		if jump_rep() and airborne<.20: technique_feedback="Jump set requested. Jump before contact."
		elif not jump_rep() and airborne>.12: technique_feedback="Standing set requested. Stay planted."
		if first_contact<0 or clock-last_contact>minf(.17,timing_window()):
			miss("No hand contact. Get under the ball before release.")
			return
		if absf(set_error)>timing_window() or gap>0.72+0.36*skill:
			miss("Missed contact. Hold the target and release above your forehead.")
			return
	energy[setter].spend(2)
	target = index
	tempo = chosen_tempo() if not demonstration and rotation_drill.turn==0 else 1
	source = ball.position
	flight_time = DURATION[tempo]
	var error := 0.0 if demonstration else set_error*(3.6-skill)+gap*0.22
	endpoint = PINS[target]+Vector3(error,0,error*0.4)
	if not demonstration:
		endpoint+=facing_scatter(setter,target)
	if rotation_drill.turn!=0 and not demonstration:
		var scatter := .22 if rotation_drill.random.randf()<.60 else 1.65
		endpoint += Vector3(rotation_drill.random.randf_range(-scatter,scatter),0,rotation_drill.random.randf_range(-scatter,scatter))
	elif not demonstration:
		# Poor releases can carry past the pin into the tape or court.
		var late := clampf((absf(set_error)-.065)/.135,0,1)
		endpoint.z += 1.5*late
	placement_error=endpoint.distance_to(PINS[target])
	success = technique_feedback.is_empty() and target==called() and endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10
	feedback = TARGETS[target]+"   /   Target made" if success else "Missed the called target. Try it again."
	if not technique_feedback.is_empty(): feedback=technique_feedback
	trace("set",{"technique":technique_feedback,"requested":TARGETS[called()],"actual":TARGETS[target],"made":success,"error_m":error})
	Hands.apply(setter,source,1.0,(endpoint-source).normalized()*.22,0,.3,false,Vector3.ZERO,1.,endpoint-source,.6,true)
	begin("set")

func build_score_strip() -> void:
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
		card.add_child(label)
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
		var surname: String=rotation_drill.roster[i].display_name.get_slice(" ",rotation_drill.roster[i].display_name.count(" "))
		score_labels[i].text="%s   %d/%d" % [surname.to_upper(),hits,taken]
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
	for net in targets: net.beacon.hide()
	begin("complete")
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
	if phase=="net_guide": return
	if event is InputEventKey and event.echo: return
	if get_tree().paused: return
	if settings.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START) and event.pressed):
			settings.hide()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton: active_pad = event.device
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
	if rotation_drill.turn!=0 and not demonstration:
		free_input(event)
		return
	if demonstration:
		if event is InputEventJoypadButton: trace("input_in_demo",{"id":event.button_index})
		return
	if (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_LEFT_SHOULDER) or event is InputEventKey and event.keycode==KEY_ENTER) and event.is_pressed() and phase=="ground":
		reset_feed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_RIGHT_STICK) or event is InputEventKey and event.keycode==KEY_SPACE:
		if event.is_pressed():
			var allowed := not jump.active and not squat.charging
			trace("squat_press",{"accepted":allowed})
			if allowed:
				energy[setter].spend(5)
				squat.begin(setter)
				message.text = "Release in green to jump"
		elif squat.charging:
			message.text = squat.release(setter,jump)
			trace("jump_release",{"seconds":squat.seconds,"quality":message.text,"height":jump.height})
		get_viewport().set_input_as_handled()
		return
	var index := -1
	if event is InputEventJoypadButton:
		for i in BUTTONS.size():
			if event.button_index==Xbox.physical(BUTTONS[i]): index = i
	elif event is InputEventKey: index = KEYS.find(event.keycode)
	if index<0: return
	if phase not in ["cart","walk","feed","pass"]:
		trace("target_unavailable",{"target":TARGETS[index],"down":event.is_pressed()})
		if phase=="ground": message.text = "Call the next toss"
	elif event.is_pressed():
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
	if (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_RIGHT_STICK)) or (event is InputEventKey and event.keycode==KEY_SPACE):
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
