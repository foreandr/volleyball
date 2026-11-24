extends Control

const Court = preload("res://scripts/preview_court.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const Hands = preload("res://scripts/hand_setting_pose.gd")
const TARGETS := ["Left side","Middle","Pipe","Right side"]
const TEMPOS := ["Normal","High","Fast"]
const Xbox = preload("res://scripts/xbox_controls.gd")
const BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_A,JOY_BUTTON_B]
const KEYS := [KEY_J,KEY_I,KEY_K,KEY_L]
const PINS := [Vector3(3.75,2.15,3.0),Vector3(0.55,0.54,3.3),Vector3(0,0.54,-2.3),Vector3(-3.75,2.15,3.0)]
const BASE := Vector3(0,0.04,1.35)
const ORDER := [0,3,2,1]
const CONTACT := 1.65
const DURATION := [1.05,1.65,0.68]
const APEX := [1.1,2.5,0.32]
const LINES := ["Welcome to the team, %s. I’m Coach Ellis.","You’re trying out at setter. Watch the four targets. I’ll toss the first ones right to you.","Two to each spot. First stay planted, then jump set. After that, I’ll make you move."]
const TOSS_SPOTS := [Vector3(-2.5,0.04,-1.2),Vector3(2.8,0.04,-1.8),Vector3(2.7,0.04,2.45),Vector3(-2.9,0.04,2.4)]
var coach_motion := preload("res://scripts/tryout_coach.gd").new()
var station := -1
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

var landing := MeshInstance3D.new()
var ball := MeshInstance3D.new()
var panel := PanelContainer.new()
var title := Label.new()
var message := Label.new()
var controls_row := HFlowContainer.new()
var prompt_phase := ""
var hint := Label.new()
var skip := TextureProgressBar.new()
var finish := Button.new()
var rep := 0
var held := -1
var last_flick := 0
var flick_at := -10.0
var source := Vector3.ZERO
var catch_point := Vector3.ZERO
var target := 0
var tempo := 0
var success := false
var feedback := ""
var flight_time := 1.0
var contact_sound := AudioStreamPlayer.new()

func athlete(at: Vector3,color: String) -> Node3D:
	var actor := Player.new()
	actor.team_color = Color(color)
	actor.position = at
	world.add_child(actor)
	actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.get_node("DirectionArrows").hide()
	return actor

func _ready() -> void:
	MenuPresentation.set_music(false)
	add_child(world)
	world.add_child(preload("res://scripts/tryout_gym.gd").new())
	preload("res://scripts/tryout_gym.gd").light_gym(world)
	get_viewport().msaa_3d = Viewport.MSAA_4X
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
	for i in 4:
		var basket := preload("res://scripts/tryout_target.gd").new()
		basket.position = PINS[i]
		basket.is_net = i in [0,3]
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
	contact_sound.stream = preload("res://assets/audio/set_touch.wav")
	add_child(contact_sound)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.53
	ring.outer_radius = 0.58
	landing.mesh = ring
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("7effdf")
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	landing.material_override = paint
	world.add_child(landing)
	landing.hide()
	squat.configure(world)
	build_hud()
	build_settings()
	rep = CareerSession.progress()
	match CareerSession.stage():
		"intro": begin("intro")
		"complete": complete()
		_: start_practice()

func seat_teammates() -> void:
	var seats := [[-1,1,-3.0],[1,0,-1.1],[-1,1,0.9],[1,0,1.4],[-1,2,3.3],[1,1,4.2],[-1,0,5.5],[1,2,6.0],[-1,2,7.8],[1,1,8.0]]
	for i in seats.size():
		var seat: Array = seats[i]
		var side := int(seat[0])
		var row := int(seat[1])
		var athlete_ := athlete(Vector3(side*(6.8+row*.69),0,float(seat[2])),["245447","a34d31","334357"][i%3])
		athlete_.set_height_cm(172+(i*7)%29)
		athlete_.rotation.y = -side*PI/2
		athlete_.play_action("base/Sitting_Talking",0)
		athlete_.animator.seek(i*.31,true)
		var rig: Skeleton3D = athlete_.skeleton
		var hips := rig.to_global(rig.get_bone_global_pose(rig.find_bone("pelvis")).origin)
		athlete_.position.y += .48+row*.37+.16-hips.y
		athlete_.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE

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
	finish.text = "Return to My Career"
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
	meter.visible = next=="pass"
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
			entries.append_array([[JOY_BUTTON_RIGHT_STICK,"Hold / release jump"],["LT","Focus"],["RT","Sprint"],[JOY_BUTTON_START,"Settings"]])
	Xbox.prompts(controls_row,entries)

func leave() -> void:
	get_tree().change_scene_to_file("res://scenes/story.tscn")

func start_practice() -> void:
	demonstration = false
	demo_index = 0
	reset_feed()

func jump_rep() -> bool:
	return not demonstration and (rep/8)%2 == 1

func called() -> int:
	return ORDER[demo_index if demonstration else (rep%8)/2]

func reset_feed() -> void:
	begin("walk")
	station = (station+1)%TOSS_SPOTS.size()
	coach_goal = TOSS_SPOTS[station]
	squat.cancel()
	jump.active = false
	last_flick = 0
	flick_at = -10
	setter.position = BASE
	setter.rotation.y = atan2(coach.position.x-BASE.x,coach.position.z-BASE.z)
	setter.play_action("idle")
	catch_point = BASE + Vector3.UP*(1.93*setter.height_cm/180.0 + (0.52 if jump_rep() else 0.0))
	if not demonstration and rep>=16: catch_point.z += 1.25 if rep%2==0 else -1.25
	coach.show()
	coach.rotation.y = atan2(catch_point.x-coach.position.x,catch_point.z-coach.position.z)
	ball.show()
	landing.position = Vector3(catch_point.x,0.075,catch_point.z)
	landing.show()
	apply_camera()
	title.text = "COACH DEMO    /    %d OF 4" % (demo_index+1) if demonstration else "SETTER TRYOUT    /    %02d OF 32    •    %s" % [rep+1,"MOVING" if rep>=16 else "STATIONARY"]
	message.text = TARGETS[called()]+"    /    "+("Jump set" if jump_rep() else "Standing set")
	hint.text = ""
	hint.hide()
	meter.value = 0

func apply_camera() -> void:
	var pivot := Vector3(0,1.35,1.0)+camera_lead
	var angle := deg_to_rad(elevation)
	camera.position = pivot+Vector3(sin(yaw)*cos(angle),sin(angle),-cos(yaw)*cos(angle))*distance
	camera.position.x = clampf(camera.position.x,-10.8,10.8)
	camera.position.y = minf(camera.position.y,8.2)
	camera.position.z = clampf(camera.position.z,-10.3,14.0)
	camera.look_at(pivot)

func build_settings() -> void:
	settings.configure(self)

func arc(a: Vector3,b: Vector3,t: float,height: float) -> Vector3:
	var u := clampf(t,0,1)
	return a.lerp(b,u)+Vector3.UP*4.0*height*u*(1.0-u)

func pad() -> int:
	var pads := Input.get_connected_joypads()
	return active_pad if active_pad in pads else (-1 if pads.is_empty() else pads[0])

func axis(which: JoyAxis) -> float:
	var id := pad()
	return Input.get_joy_axis(id,which) if id >= 0 else 0.0

func move_setter(delta: float) -> void:
	var motion := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	motion += Vector2(int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)))
	if motion.length()<0.16: motion = Vector2.ZERO
	var direction := Vector3(-motion.x,0,-motion.y).limit_length(1) if rep>=16 else Vector3.ZERO
	var focus := axis(Xbox.trigger(true))>0.25 or Input.is_key_pressed(KEY_CTRL)
	var sprint := axis(Xbox.trigger(false))>0.25 or Input.is_key_pressed(KEY_SHIFT)
	if focus!=focused:
		focused = focus
		trace("focus",{"active":focus})
		message.text = ("Focused on ball   /   " if focus else "")+TARGETS[called()]
	var speed := 2.35 if focus else (6.2 if sprint else 4.3)
	setter.position = Court.clamp_setter(setter.position+direction*delta*speed,3.65,-4.85)
	var facing := ball.position-setter.position if focus else (coach.position-setter.position if phase=="walk" and direction.is_zero_approx() else direction)
	if Vector2(facing.x,facing.z).length()>0.05:
		setter.rotation.y = lerp_angle(setter.rotation.y,atan2(facing.x,facing.z),minf(1,delta*14))
	setter.play_action("idle" if direction.is_zero_approx() or focus else "run")

func _process(delta: float) -> void:
	if settings.visible: return
	setter.animator.advance(delta)
	coach.animator.advance(delta)
	clock += delta
	elapsed += delta
	if phase == "intro":
		play_intro(delta)
		return
	if phase == "complete": return
	# Leave the four targets in frame while easing toward the live ball.
	var lead := (ball.position-Vector3(0,1.6,1.0))*Vector3(0.10,0.08,0.055)
	camera_lead = camera_lead.lerp(lead.limit_length(0.5),1.0-exp(-3.2*delta))
	apply_camera()
	squat.update(setter,delta)
	landing.visible = not squat.ring.visible and phase in ["walk","feed","pass"]
	if jump.active: jump.step(setter,delta,Vector2.ZERO)
	elif not demonstration and not squat.charging: move_setter(delta)
	var stick := axis(JOY_AXIS_RIGHT_Y)
	if absf(stick)>0.45 or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN):
		last_flick = 1 if stick < -0.45 or Input.is_key_pressed(KEY_UP) else 2
		flick_at = clock
	match phase:
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
			ball.position = coach_motion.toss(coach,clampf(elapsed/0.95,0,1))
			if elapsed>=0.95:
				source = ball.position
				trace("coach_release",{"from":str(source),"to":str(catch_point)})
				change_feed_phase("pass")
		"pass":
			ball.position = source.lerp(catch_point,elapsed/CONTACT)+Vector3.UP*(4.905*elapsed*(CONTACT-elapsed))
			if elapsed<0.22: coach_motion.toss(coach,1.0)
			ball.position.y = maxf(0.15,ball.position.y)
			if demonstration and held<0 and elapsed>=0.85:
				held = called()
				pressed_at = clock
			if held>=0:
				meter.value = clampf((clock-pressed_at)/0.65,0,1)*100
				Hands.apply(setter,ball.position,0.35+0.65*smoothstep(0.8,1.55,elapsed))
			if demonstration and elapsed>=CONTACT: release(called())
			elif elapsed>CONTACT+0.25: miss("The toss dropped. Hold the target, then release at contact.")
		"set":
			ball.rotate_x(delta*4.0)
			var t := clampf(elapsed/flight_time,0,1)
			ball.position = arc(source,endpoint,t,APEX[tempo])
			if elapsed<0.22: Hands.apply(setter,source,1.0-elapsed/0.22,(endpoint-source).normalized()*0.22,0.0,0.3,false,Vector3.ZERO,1.0,endpoint-source,0.5,true)
			if t>=1:
				if endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10: targets[target].impact()
				if success and not demonstration:
					if not CareerSession.credit(rep): return
					rep += 1
				begin("result")
				message.text = feedback
		"drop":
			floor_speed += 9.81*delta
			ball.position.y = maxf(0.15,ball.position.y-floor_speed*delta)
			if ball.position.y<=0.151:
				begin("ground")
				trace("floor",{})
				message.text = feedback
		"result":
			if success:
				ball.position = endpoint-Vector3.UP*minf(targets[target].depth-0.08,elapsed*3.1)
			if elapsed>1.0:
				if demonstration:
					demo_index += 1
					if demo_index==4:
						demonstration = false
						if CareerSession.stage()=="intro": CareerSession.checkpoint("tutorial",0)
				if rep>=32: complete()
				elif demonstration or demo_index==4:
					if not demonstration: demo_index = 0
					reset_feed()
				else:
					begin("ground")
					message.text = feedback

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
		if CareerSession.checkpoint("tutorial",0):
			skip.hide()
			start_practice()

func miss(reason: String) -> void:
	success = false
	trace("miss",{"reason":reason})
	floor_speed = maxf(0.2,9.81*(elapsed-CONTACT/2.0)-(catch_point.y-source.y)/CONTACT)
	feedback = reason
	begin("drop")
	message.text = reason

func release(index: int) -> void:
	if phase!="pass" or held!=index: return
	trace("release",{"target":TARGETS[index],"held_s":clock-pressed_at,"timing_error":elapsed-CONTACT,"air_m":setter.position.y-BASE.y})
	held = -1
	var skill := float(CareerSession.profile().get("Hand setting",40))/100
	var gap := Vector2(setter.position.x-catch_point.x,setter.position.z-catch_point.z).length()
	var airborne := setter.position.y-BASE.y
	if not demonstration:
		if jump_rep() and airborne<0.20:
			miss("Jump set requested. Jump before contact.")
			return
		if not jump_rep() and airborne>0.12:
			miss("Stay planted for this set.")
			return
		if clock-pressed_at<0.12 or absf(elapsed-CONTACT)>0.20 or gap>0.72+0.36*skill:
			miss("Missed contact. Hold the target and release above your forehead.")
			return
	target = index
	tempo = last_flick if clock-flick_at<0.35 else 0
	source = ball.position
	flight_time = DURATION[tempo]
	var error := 0.0 if demonstration else (elapsed-CONTACT)*(3.6-skill)+gap*0.22
	endpoint = PINS[target]+Vector3(error,0,error*0.4)
	success = target==called() and endpoint.distance_to(PINS[target])<targets[target].mouth_radius-0.10
	feedback = TARGETS[target]+"   /   Target made" if success else "Missed the called target. Try it again."
	trace("set",{"requested":TARGETS[called()],"actual":TARGETS[target],"made":success,"error_m":error})
	contact_sound.play()
	Hands.apply(setter,source,1.0,endpoint-source)
	begin("set")

func complete() -> void:
	landing.hide()
	begin("complete")
	camera.position = Vector3(0,6,-9)
	camera.look_at(Vector3(0,1.4,2))
	ball.hide()
	coach.hide()
	title.text = "MY CAREER   /   INDOOR SETTER"
	message.text = "Setter tryout complete"
	var badges: Array = CareerSession.data.get_value("badges",CareerSession.athlete_id,[])
	hint.show()
	hint.text = "Badges   •   "+"   /   ".join(badges) if not badges.is_empty() else ""
	finish.show()
	finish.grab_focus()

func trace(kind: String, fields: Dictionary) -> void:
	fields.merge({"phase":phase,"rep":rep+1,"demo":demonstration,"phase_s":elapsed})
	InteractionTrace.record(kind,fields)

func change_feed_phase(next: String) -> void:
	var prepared := held
	begin(next)
	held = prepared

func _exit_tree() -> void:
	coach_motion.dispose()

func _input(event: InputEvent) -> void:
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
	if phase in ["intro","complete"]: return
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
	if phase not in ["walk","feed","pass"]:
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
