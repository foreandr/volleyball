extends "res://scripts/attacking_camp.gd"

const TECHNIQUES := [preload("res://scripts/spin_serve.gd"),preload("res://scripts/jump_float_serve.gd"),preload("res://scripts/standing_float_serve.gd"),preload("res://scripts/underhand_serve.gd")]
const FACE := [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y]
const LABELS := ["Spin","Float","Standing float","Underhand"]
const HOMES := [Vector3(-2.9,.04,9.2),Vector3(0,.04,10.),Vector3(2.9,.04,9.2)]
var serves := []
var serve_contact_offsets: Array[Vector3]=[]
var passers: Array[Node3D]=[]
const JUMP_SERVE_VERTICAL := 57.*.0254
const JUMP_TOSS_APEX := [6.4,5.1]
const SERVE_EARLY := -.26
const SERVE_LATE := .075
const SERVE_PERFECT := .055
var toss_airborne := false
var toss_style := 2
var hit_style := 2
var release_time := INF
const SERVE_HOLD_SECONDS := .25
var pending_serve := -1
var held_seconds := 0.0
var serve_clock := 0.
var flight_age := 0.
var destination := Vector3(0,.065,10.)
var serve_arc_offset := 0.0
var float_clearance := .20
var pass_start := Vector3.ZERO
var pass_clock := 0.
const SETTER_HOME := Vector3(3.45,.04,11.1)
const SETTER_BASE := Vector3(1.4,.04,5.2)
# Receive in rotation one. The front row can hit in its reception lanes.
const ATTACK_POINTS := [Vector3(3.55,3.05,5.05), Vector3(0,3.05,5.0), Vector3(-3.55,3.05,5.05), Vector3(0,3.05,7.45)]
var attack_slot := 0
var middle_31 := false
var called_slot := 0
var middle_decoy := preload("res://scripts/match_attack.gd").new()
var receiving_team: Array[Node3D]=[]

func add_reception_platform(passer: Node3D,backward: Animation) -> void:
	var platform := Reception.new()
	world.add_child(platform)
	platform.configure(passer,preload("res://assets/animations/straight_pass_02.res"))
	platform.set_custom_backward(backward)
	platform.allow_knee_reach=true
	platform.receive_front_limit=13.8
	platform.hide()
	receptions.append(platform)

func first_contact_player() -> Node3D:
	return cover_players[receiver]

func second_contact_player() -> Node3D:
	return passers[1] if first_contact_player()==receiving_setter else receiving_setter

func route_point(slot: int) -> Vector3:
	if slot==1:
		return Vector3(-1.25 if middle_31 else .85,3.05,5.0)
	return Vector3(pipe_lane,ATTACK_POINTS[3].y,ATTACK_POINTS[3].z) if slot==3 else ATTACK_POINTS[slot]

var attack_options: Array[Node3D]=[]
var set_duration := 1.35
const MIDDLE_HOME := Vector3(0,.04,4.72)
const HITTER_HOME := Vector3(-3.75,.04,6.95)
var pin_frame := Node3D.new()
var pin_attack := preload("res://scripts/match_attack.gd").new()
var receiving_middle: Node3D
var floor_linger := -1.
var pin_hitter: Node3D
var wall: Array[Node3D]=[]
var wall_jumps := [null,null,null]
var wall_committed := [false,false,false]
var replay_rally := 0
var return_touched := false
var wall_vertical_inches := 46.
var attack_kmh := 105.
var serve_test_kmh := 0.
var spin_selection := 0 # Top, left, right, float.
var recent_misses := [0.,0.,0.,0.]
var pipe_lane := 0.

func flight_style() -> int:
	return 1 if hit_style==0 and spin_selection==3 else hit_style

func contact_height_for(slot: int) -> float:
	var actor := attack_options[slot]
	var standing: float=actor.height_cm*(.0104 if slot==3 else .0111)
	if slot==1: standing=2.22
	return standing+(pin_attack.jump.max_height-.2032)*actor.stamina.effectiveness()*(.91 if slot==1 else 1.)

func pin_flight_time(slot: int) -> float:
	if slot not in [0,2]: return ONE_FLIGHT
	var reserve: float=attack_options[slot].stamina.fraction()
	if reserve<.35 or recent_misses[slot]>=1.7: return 1.60
	if reserve<.65 or recent_misses[slot]>=.7: return 1.05
	return ONE_FLIGHT
var cover_slot := -1
var cover_clock := 0.
var attack_results := [0.,0.,0.,0.]
var middle_commit := false
var aim_read := false
var closest_attack_gap := INF
var closest_attack_age := 0.
var last_shot_slot := -1
var cover_players: Array[Node3D]=[]

const ZERO_FLIGHT := .34
const ONE_FLIGHT := .65
var pass_in_system := false
const PASS_HEIGHT := 1.08
var receiving_setter: Node3D
var serve_station := Vector3(0,.04,-8.2)
const SetHands = preload("res://scripts/hand_setting_pose.gd")
var receiving_jump := preload("res://scripts/setter_jump.gd").new()
var set_at := 1.25
const SET_VERTICAL := .48
const SET_LOAD := .20
var pass_end := Vector3.ZERO
var receive_at := 0.
var pass_duration := 1.25
const Reception = preload("res://scripts/bump_setting.gd")
var receptions: Array[Reception]=[]
var platform_clips: Array[Animation]=[]
var receiver := 0
var hand_sound := AudioStreamPlayer.new()

func _ready() -> void:
	gym.rear_extension=1.5
	super()

func start_drill() -> void:
	spike_pike_scale=1.45
	jump_height=JUMP_SERVE_VERTICAL
	hitter=setter
	cpu_hitter=false
	attack_jump.attack_arm_lift=true
	attack_jump.back_limit=-10.5
	attack_jump.load_lead_arm_clip()
	world.add_child(hand_impact)
	hand_impact.bus=StorySession.IMPACT_BUS
	hand_impact.stream=preload("res://assets/audio/hand_impacts.tres")
	for prop in [coach,rotation_drill.basket]+rotation_drill.stock+targets:
		prop.hide()
		if prop is CollisionObject3D: prop.collision_layer=0
		for body in prop.find_children("*","CollisionObject3D",true,false):
			body.collision_layer=0
	score_strip.hide()
	hand_sound.bus=StorySession.IMPACT_BUS
	hand_sound.stream=preload("res://assets/audio/hand_impacts.tres")
	add_child(hand_sound)
	for file in ResourceLoader.list_directory("res://assets/animations"):
		if file.begins_with("straight_pass_") and file.get_extension() in ["res","tres"]:
			platform_clips.append(load("res://assets/animations/"+file))
	var backward: Animation
	var copies := preload("res://scripts/volleyball_animations.gd").custom_entries()
	for i in range(copies.size()-1,-1,-1):
		if copies[i].get("source")=="d2_backward_from_d1":
			backward=load(copies[i].path)
			break
	for i in HOMES.size():
		var passer := athlete(HOMES[i],"286881")
		register_student(passer,i+3)
		preload("res://scripts/practice_kit.gd").apply(passer,false,i+3)
		passer.rotation.y=PI
		passer.play_action("idle")
		passer.animator.advance(.57*(i+1))
		passers.append(passer)
		add_reception_platform(passer,backward)
	receiving_jump.front_limit=13.
	receiving_jump.back_limit=BallNet.NET_Z+.25
	receiving_setter=athlete(SETTER_HOME,"286881")
	register_student(receiving_setter,6)
	add_reception_platform(receiving_setter,backward)
	preload("res://scripts/practice_kit.gd").apply(receiving_setter,false,6)
	pin_frame.position.z=2.*BallNet.NET_Z
	pin_frame.rotation.y=PI
	world.add_child(pin_frame)
	pin_hitter=athlete(HITTER_HOME,"286881")
	register_student(pin_hitter,7)
	preload("res://scripts/practice_kit.gd").apply(pin_hitter,false,7)
	pin_hitter.reparent(pin_frame,true)
	pin_frame.add_child(pin_attack)
	pin_attack.configure_for_match(pin_hitter,Label.new())
	pin_attack.chase_late_sets=true
	pin_attack.add_child(pin_attack.status)
	pin_attack.hide()
	pin_attack.struck.connect(return_struck)
	for i in 3:
		var blocker := athlete(Vector3((i-1)*2.75,.04,BallNet.NET_Z-.38),"e97937")
		register_student(blocker,i+8)
		preload("res://scripts/practice_kit.gd").apply(blocker,false,i+8)
		wall.append(blocker)
	receiving_middle=athlete(MIDDLE_HOME,"286881")
	register_student(receiving_middle,11)
	preload("res://scripts/practice_kit.gd").apply(receiving_middle,false,11)
	receiving_middle.rotation.y=PI*.5
	pin_frame.add_child(middle_decoy)
	middle_decoy.configure_for_match(receiving_middle,Label.new())
	middle_decoy.add_child(middle_decoy.status)
	middle_decoy.chase_late_sets=true
	middle_decoy.decoy_swing=true
	middle_decoy.hide()
	attack_options=[passers[2],receiving_middle,pin_hitter,passers[0]]
	add_reception_platform(receiving_middle,backward)
	add_reception_platform(pin_hitter,backward)
	cover_players=[passers[0],passers[1],passers[2],receiving_setter,receiving_middle,pin_hitter]
	receiving_team=[passers[0],passers[1],passers[2],receiving_middle,pin_hitter,receiving_setter]
	passers[1].shirt_fabric.set_shader_parameter("fabric",Color("49a6ce"))
	for i in TECHNIQUES.size():
		var driver=TECHNIQUES[i].new()
		world.add_child(driver)
		driver.configure(setter,Vector3(0,.04,[-8.2,-6.6,-6.1,-6.1][i]))
		serve_contact_offsets.append(driver.preview_origin-driver.serve_start)
		driver.hide()
		serves.append(driver)
	build_rally_sliders()
	title.text="SERVING"
	update_prompts("ready")
	apply_camera.call_deferred()
	next_serve()

func build_rally_sliders() -> void:
	var grid := GridContainer.new()
	grid.columns=4
	controls_row.get_parent().add_child(grid)
	for spec in [["Block vertical", "block_vertical",1,60,46," in"],["Attack vertical","attack_vertical",1,60,42," in"],["Passing skill","passing_skill",0,100,65,""],["Setting skill","setting_skill",0,100,65,""],["Attack speed","attack_kmh",15,180,105," km/h"],["Serve speed","serve_kmh",0,300,0," km/h"]]:
		var label := Label.new()
		var slider := HSlider.new()
		grid.add_child(label)
		grid.add_child(slider)
		slider.custom_minimum_size.x=104
		slider.min_value=spec[2]
		slider.max_value=spec[3]
		slider.step=1
		slider.value=StorySession.game_options.get_value("serving",spec[1],spec[4])
		var apply := func(value: float):
			label.text=str(spec[0])+"  "+("Auto" if spec[1]=="serve_kmh" and value==0 else str(int(value))+str(spec[5]))
			match spec[1]:
				"block_vertical": wall_vertical_inches=value
				"attack_vertical": pin_attack.jump.max_height=value*.0254+.2032
				"passing_skill":
					for actor in cover_players:
						actor.attributes["Forearm reception"]=value
						actor.attributes["Hand reception"]=value
				"setting_skill":
					for actor in [receiving_setter,passers[1]]: actor.attributes["Hand setting"]=value
				"attack_kmh": attack_kmh=value
				"serve_kmh": serve_test_kmh=value
		apply.call(slider.value)
		slider.value_changed.connect(func(value):
			apply.call(value)
			StorySession.game_options.set_value("serving",spec[1],value)
			StorySession.save_options())

func update_prompts(_next: String) -> void:
	if prompt_phase=="serving": return
	prompt_phase="serving"
	Xbox.prompts(controls_row,[["A","Spin"],["B","Jump float"],["X","Standing float"],["Y","Underhand"],["RS","Pre-aim / hold for height"],["LS","Toss aim / hold for height"],["D-pad Up/Down","Topspin / float"],["D-pad Left/Right","Sidespin"]])

func apply_camera() -> void:
	place_practice_camera(Vector3(0,1.5,-4.4),distance*.48+2.)

func configure_flight(shot,origin: Vector3) -> void:
	shot.test_speed_mps=serve_test_kmh/3.6
	if hit_style==0 and spin_selection!=3: shot.sidespin=[0.,1.,-1.][spin_selection]
	if flight_style() in [1,2]: shot.tape_clearance=float_clearance
	shot.apex=maxf(origin.y+.03,(4.3 if hit_style==0 else 4.9)+serve_arc_offset)

func update_serve_aim(delta: float) -> void:
	var before := phase=="serve_ready"
	var stick := Vector2(axis(JOY_AXIS_RIGHT_X),axis(JOY_AXIS_RIGHT_Y)) if before else Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	var click := JOY_BUTTON_RIGHT_STICK if before else JOY_BUTTON_LEFT_STICK
	var height_mode := pad()>=0 and Input.is_joy_button_pressed(pad(),Xbox.physical(click))
	if height_mode and absf(stick.y)>.16:
		float_clearance=clampf(float_clearance-stick.y*delta*1.25,.03,2.2)
		serve_arc_offset=clampf(serve_arc_offset-stick.y*delta*1.25,-1.7,2.)
	if height_mode: stick.y=0.
	if stick.length()>.16:
		var right := camera.global_basis.x.slide(Vector3.UP).normalized()
		var forward := -camera.global_basis.z.slide(Vector3.UP).normalized()
		destination+=(right*stick.x-forward*stick.y)*5.*delta
		destination.x=clampf(destination.x,-4.5,4.5)
		destination.z=clampf(destination.z,BallNet.NET_Z+.2,BallNet.NET_Z+9.)
	var shot=serves[flight_style()]
	for driver in serves:
		driver.visible=driver==shot
		driver.ball.hide()
		driver.aim_ring.hide()
	if before:
		shot.preview_origin=serve_station+(Vector3(0,attack_contact_height()-serve_station.y,1.6) if hit_style<2 else serve_contact_offsets[hit_style])
	elif toss_style<2:
		shot.preview_origin=endpoint if toss_airborne else setter.position+setter.basis.z*2.15+Vector3.UP*(attack_contact_height()-setter.position.y)
	configure_flight(shot,shot.preview_origin)
	shot.target=destination
	shot.update_path_preview()

func swing_can_contact() -> bool:
	# A descending self-toss can meet the extended hand after the attack clip's normal contact frame.
	return swing_time>=.055 and elapsed<=contact_deadline()+.04 and attack_jump.active

func contact_deadline() -> float:
	return flight_time+.12

func next_serve() -> void:
	replay_rally+=1
	middle_31=randf()<.5
	called_slot=3 if randf()<.22 else randi_range(0,2)
	cover_slot=-1
	last_shot_slot=-1
	middle_commit=false
	middle_decoy.enabled=false
	middle_decoy.jump.active=false
	for driver in serves: driver.hide()
	pin_attack.enabled=false
	pin_attack.jump.active=false
	for actor in attack_options:
		if actor!=pin_hitter and actor.get_parent()==pin_frame: actor.reparent(world,true)
	receiving_middle.position=MIDDLE_HOME
	receiving_middle.rotation.y=PI*.5
	receiving_middle.play_action("idle")
	if pin_hitter.get_parent()!=pin_frame: pin_hitter.reparent(pin_frame,true)
	pin_hitter.position=pin_frame.to_local(HITTER_HOME)
	pin_hitter.rotation.y=0.
	pin_hitter.play_action("idle")
	return_touched=false
	attack_decided=false
	last_block_result.hide()
	for i in wall.size():
		wall_jumps[i]=null
		wall_committed[i]=false
		wall[i].position=Vector3((i-1)*2.75,.04,BallNet.NET_Z-.38)
		wall[i].rotation.y=0.
		wall[i].play_action("idle")
	clear_attack_input()
	attack_jump.active=false
	approach_started=false
	swing_time=-1.
	toss_airborne=false
	phase="serve_ready"
	pending_serve=-1
	serve_clock=0.
	release_time=INF
	var ready=serves[2]
	ready.serve_start=serve_station
	ready.reset()
	ball.position=ready.ball.position
	ball.show()
	for platform in receptions: platform.reset()
	for i in passers.size():
		passers[i].position=HOMES[i]
		passers[i].play_action("idle")
	receiving_jump.active=false
	receiving_setter.position=SETTER_HOME
	receiving_setter.rotation.y=PI
	receiving_setter.play_action("base/Idle",0.)
	receiving_setter.animator.seek(0.,true)
	message.text="Hold to serve"

func _input(event: InputEvent) -> void:
	if get_tree().paused or replay_inspector.active: return
	if not settings.visible and event is InputEventJoypadButton:
		var directions := [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]
		if phase in ["serve_ready","serve_toss"] and event.button_index in directions and event.pressed:
			spin_selection=directions.find(event.button_index)
			message.text=["Topspin","Left spin","Right spin","Float"][spin_selection]
			update_serve_aim(0.)
			get_viewport().set_input_as_handled()
			return
		for i in FACE.size():
			if event.button_index==Xbox.physical(FACE[i]):
				active_pad=event.device
				handle_serve_button(i,event.pressed)
				get_viewport().set_input_as_handled()
				return
	if settings.visible or event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START)):
		super._input(event)

func handle_serve_button(style: int,pressed: bool) -> void:
	if phase=="serve_ready":
		if pressed:
			pending_serve=style
			held_seconds=0.
			toss_style=style
			hit_style=style
			update_serve_aim(0.)
			message.text=LABELS[style]+"  -  Hold to serve"
		elif pending_serve==style:
			pending_serve=-1
	elif phase=="serve_toss":
		if pressed and toss_style<2 and style<2:
			hit_style=style
			release_time=INF
			message.text=LABELS[toss_style]+" toss / "+LABELS[style]+" hit"
		elif not pressed and style==hit_style and not is_finite(release_time):
			release_time=serve_clock
			trace("serve_release",{"toss":toss_style,"hit":hit_style,"timing_ms":roundi(serve_meter_error()*1000.)})

func serve_meter_position(error: float) -> float:
	return clampf(inverse_lerp(SERVE_EARLY-.08,SERVE_LATE+.025,error),0.,1.)

func serve_meter_error() -> float:
	if toss_style<2 and not toss_airborne: return SERVE_EARLY-1.
	var sample := release_time if is_finite(release_time) else serve_clock
	var strike: float=serves[toss_style].contact_time()
	if toss_airborne: strike=serves[toss_style].toss_release_time()+flight_time
	return sample-(strike-SERVE_LATE)

func shot_landing(_origin: Vector3) -> Vector3:
	return destination

func self_set_step(motion, previous_time: float,delta: float) -> bool:
	var release: float=motion.toss_release_time()
	if serve_clock<release:
		motion.pose(serve_clock)
		ball.transform=motion.ball.transform
		return false
	if not toss_airborne:
		motion.pose(release)
		source=motion.ball.position
		ball.position=source
		endpoint=hitter.position+hitter.basis.z.normalized()*2.15
		endpoint.y=attack_contact_height()
		active_set=endpoint
		var apex := maxf(JUMP_TOSS_APEX[toss_style],maxf(source.y,endpoint.y)+.1)
		flight_time=sqrt(2.*(apex-source.y)/9.81)+sqrt(2.*(apex-endpoint.y)/9.81)
		set_arc_height=9.81*flight_time*flight_time/8.
		manual_shot=1
		aim_center=Vector2(destination.x,destination.z)
		toss_airborne=true
	var previous := ball.position
	elapsed=serve_clock-release
	var progress := elapsed/flight_time
	ball.position=source.lerp(endpoint,progress)+Vector3.UP*4.*set_arc_height*progress*(1.-progress)
	motion.spin_toss_ball(previous_time,serve_clock,1.)
	ball.basis=motion.ball.basis
	phase="set"
	if attack_jump.active: attack_jump.step(hitter,delta,Vector2.ZERO)
	if is_finite(release_time):
		release_at=release_time
		var error := serve_meter_error()
		release_grade=remap(error,SERVE_EARLY,SERVE_LATE,EARLY_LIMIT,LATE_LIMIT)-GRADE_ADVANCE
	var finished := handle_attack_contact(previous,delta)
	var hit := phase=="spike"
	phase="serve_toss"
	if finished and not hit:
		phase="serve_miss"
		roll_time=-1.
		drop_net_hit.clear()
		drop_net_time=0.
		flight_age=0.
	return hit

func walk_server(delta: float) -> void:
	var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	stick+=Vector2(int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)))
	var right := camera.global_basis.x.slide(Vector3.UP).normalized()
	var direction := right*stick.x+right.cross(Vector3.UP)*stick.y
	var amount := clampf((stick.length()-.14)/.86,0.,1.)
	var focus := GroundControls.focus(axis)
	var sprint: bool= GroundControls.sprint(axis) and hitter.stamina.can_sprint()
	var velocity := direction.normalized()*amount*GroundControls.speed(focus,sprint)
	var old := serve_station
	serve_station+=velocity*delta
	serve_station.x=clampf(serve_station.x,-4.5,4.5)
	serve_station.z=clampf(serve_station.z,-10.1,-5.1)
	velocity=(serve_station-old)/maxf(delta,.001)
	if sprint and velocity.length()>.1: hitter.stamina.spend(delta*hitter.stamina.SPRINT_DRAIN,"Sprint")
	hitter.position=serve_station
	GroundControls.face(hitter,Vector3.BACK if focus else velocity,delta)
	hitter.play_ground_gait(0. if focus else velocity.length())
	hitter.animator.advance(delta)
	if not shuffle_steps.has(hitter): shuffle_steps[hitter]=preload("res://scripts/directional_footwork.gd").new(hitter)
	GroundControls.shuffle(hitter,shuffle_steps[hitter],velocity,focus,delta)
	ball.position=Contact.palm(hitter,"l")+Vector3.UP*.10

func _process(delta: float) -> void:
	if settings.visible or get_tree().paused or replay_inspector.active:
		pending_serve=-1
		return
	if serves.is_empty(): return
	for i in passers.size():
		passers[i].stamina.recover(delta)
		if pin_attack.enabled and pin_attack.setter==passers[i]: continue
		if i!=receiver or phase not in ["serve_flight","serve_pass"]:
			passers[i].animator.advance(delta)
	if phase not in ["serve_pass","serve_attack"]:
		receiving_setter.animator.advance(delta)
	hitter.stamina.recover(delta)
	receiving_setter.stamina.recover(delta)
	pin_hitter.stamina.recover(delta)
	receiving_middle.stamina.recover(delta)
	var started_in_return := phase=="serve_return"
	if pin_attack.enabled:
		if phase=="serve_attack" and not aim_read and pin_attack.pin_arrival-pass_clock<=.23:
			aim_read=true
			pin_attack.swing_aim=pin_frame.to_local(scoring_target(pass_end))
		pin_attack.tick_attack(delta)
	if not pin_attack.enabled or pin_attack.setter!=pin_hitter: pin_hitter.animator.advance(delta)
	if not middle_decoy.enabled and (not pin_attack.enabled or pin_attack.setter!=receiving_middle): receiving_middle.animator.advance(delta)
	if phase=="serve_ready" or phase=="serve_toss":
		var release: float=serves[toss_style].toss_release_time() if serves[toss_style].has_method("toss_release_time") else .18
		var ready_weight := 1. if phase=="serve_ready" else 1.-smoothstep(release,release+.22,serve_clock)
		for actor in receiving_team:
			if actor!=receiving_setter and actor!=receiving_middle: face_receive_ball(actor,hitter.global_position if phase=="serve_ready" else ball.global_position,delta)
		if ready_weight>.001:
			for i in passers.size():
				var actor := passers[i]
				actor.animator.seek(0.,true)
				receptions[i].knee_bend_depth=.14*ready_weight
				receptions[i].apply_knee_bend()
				receptions[i].knee_bend_depth=0.
				actor.pose_hands_on_knees(ready_weight)
			for actor in [receiving_middle,pin_hitter]:
				actor.animator.seek(0.,true)
				actor.pose_hands_on_knees(ready_weight)
		if phase=="serve_ready" or serve_clock<release:
			receiving_setter.animator.seek(0.,true)
			receiving_setter.pose_set_call(called_slot,middle_31,1.-smoothstep(0.,.18,serve_clock) if phase=="serve_toss" else 1.)
		else:
			receiving_setter.shirt_fabric.set_shader_parameter("signal_lift",0.)
			if receiving_setter.animator.current_animation=="base/Idle": receiving_setter.play_action("idle")
			move_receiver(receiving_setter,SETTER_BASE,delta)
	elif phase=="serve_flight": move_receiver(second_contact_player(),SETTER_BASE,delta)
	if phase in ["serve_flight","serve_pass","serve_attack","serve_return"]:
		for actor in passers:
			if actor!=first_contact_player() and actor!=second_contact_player() and actor!=pin_attack.setter: face_receive_ball(actor,ball.global_position,delta)
	if phase in ["serve_pass","serve_attack","serve_return"]: move_libero_to_cover(delta)
	if phase in ["serve_attack","serve_return"]:
		for slot in attack_options.size():
			var actor := attack_options[slot]
			if (phase=="serve_return" and cover_slot>=0 and actor==cover_players[cover_slot]) or (actor==pin_attack.setter and pin_attack.enabled) or (actor==receiving_middle and middle_decoy.enabled): continue
			var cover := route_point(slot).lerp(pass_end,.28)
			cover.z+=3.6 if slot==3 else 1.95
			cover.y=.04
			if phase=="serve_return" and (cover_slot>=0 or ball.global_position.z<BallNet.NET_Z and drop_velocity.z<0.):
				cover=transition_base(slot)
			var parent := actor.get_parent_node_3d()
			move_receiver(actor,parent.to_local(cover),delta,parent.to_local(ball.global_position)-actor.position)
			face_receive_ball(actor,ball.global_position,delta)
	if phase=="serve_flight" or (phase=="serve_toss" and ready_weight_for_routes()):
		for slot in attack_options.size():
			var actor := attack_options[slot]
			if actor in passers and (phase=="serve_toss" or actor==first_contact_player()): continue
			stage_attacker(actor,slot,delta)
	if middle_decoy.enabled: middle_decoy.tick_attack(delta)
	step_serve_wall(delta)
	if phase=="serve_return":
		if not started_in_return: return
		var previous := ball.global_position
		var was_touched := return_touched
		advance_missed_ball(delta,true)
		if attack_floor_pending and not attack_decided and was_touched: try_cover(previous,delta)
		if not attack_floor_pending: floor_linger+=delta
		if floor_linger>.55: next_serve()
		return
	if phase=="serve_ready":
		walk_server(delta)
		update_serve_aim(delta)
		if pending_serve>=0:
			held_seconds+=delta
			if held_seconds>=SERVE_HOLD_SECONDS:
				pending_serve=-1
				serves[toss_style].serve_start=serve_station
				serves[toss_style].reset()
				phase="serve_toss"
				message.text=LABELS[toss_style]
		return
	var motion=serves[toss_style]
	if phase=="serve_toss":
		update_serve_aim(delta)
		var strike: float=motion.contact_time()
		var previous := serve_clock
		serve_clock+=delta
		var hit := false
		if toss_style<2:
			hit=self_set_step(motion,previous,delta)
		else:
			motion.pose(minf(serve_clock,strike))
			ball.transform=motion.ball.transform
			hit=serve_clock>=strike
		if hit:
			var error := serve_meter_error() if is_finite(release_time) else INF
			if error<SERVE_EARLY or error>SERVE_LATE:
				phase="serve_miss"
				message.text="Late" if error>0. else "Early"
				drop_velocity=Vector3.ZERO
				roll_time=-1.
				drop_net_hit.clear()
				drop_net_time=0.
				flight_age=0.
			else:
				var shot=serves[flight_style()]
				shot.origin=Contact.palm(setter,"r") if toss_style<2 else ball.position
				configure_flight(shot,shot.origin)
				shot.target=destination+Vector3(0,0,-error*8.)
				var quality := 1.-clampf(absf(error)/(absf(SERVE_EARLY) if error<0. else SERVE_LATE),0.,1.)
				if shot.test_speed_mps>0.:
					shot.velocity=shot.aimed_velocity(shot.origin)*lerpf(.84,1.,quality)
				else:
					var duration: float=shot.flight_duration(shot.origin)/lerpf(.86,1.,quality)
					shot.velocity=shot.launch_velocity(shot.origin,duration)
				shot.planned_duration=preload("res://scripts/pass_flight.gd").landing_time(shot.origin,shot.velocity)
				shot.begin_serve_curve()
				plan_serve_reception(shot)
				shot.net_hit=BallNet.first_hit(shot.flight_point,0.,shot.planned_duration)
				shot.ball.basis=ball.basis
				flight_age=0.
				phase="serve_flight"
				message.text=("Perfect" if absf(error)<=SERVE_PERFECT else ("Early" if error<0. else "Late"))+" / "+LABELS[hit_style]
				if toss_style>=2: hand_sound.play()
	elif phase in ["serve_flight","serve_pass","serve_attack","serve_miss"]:
		serves[flight_style()].hide()
		serve_clock+=delta
		if toss_style<2:
			if attack_jump.active: attack_jump.step(hitter,delta,Vector2.ZERO)
			if swing_time>=0. and swing_time<=.65:
				swing_time+=delta
				var state := phase
				phase="spike" if state!="serve_miss" else "drop"
				pose_swing()
				phase=state
		elif serve_clock<=motion.recovery_end(): motion.pose(serve_clock)
		if phase=="serve_miss":
			if receiving_jump.active: receiving_jump.step(second_contact_player(),delta,Vector2.ZERO)
			advance_missed_ball(delta,true)
			flight_age+=delta
			if flight_age>1.4: next_serve()
		elif phase in ["serve_pass","serve_attack"]:
			step_reception_rally(delta)
		else:
			var shot=serves[flight_style()]
			flight_age+=delta
			shot.advance_serve_curve(flight_age)
			shot.spin_serve_ball(delta)
			ball.basis=shot.ball.basis
			var t := minf(flight_age,shot.planned_duration)
			var previous := ball.position
			ball.position=BallNet.after_hit(shot.net_hit,t) if not shot.net_hit.is_empty() and t>=shot.net_hit.time else shot.flight_point(t)
			var motion_step := ball.position-previous
			var surface := contacts.sweep(world,contacts.ball_shape,previous,motion_step,Contact.GYM|Contact.EQUIPMENT)
			if not surface.is_empty():
				ball.position=previous+motion_step*float(surface.fraction)+Vector3(surface.normal)*.004
				drop_velocity=(motion_step/maxf(delta,.001)).bounce(surface.normal)*(.70 if surface.normal.y>.8 else .45)
				drop_net_hit.clear()
				drop_net_time=0.
				roll_time=-1.
				flight_age=0.
				phase="serve_miss"
				trace("serve_gym_contact",{"normal":str(surface.normal),"point":str(ball.position)})
				return
			if ball.position.z>BallNet.NET_Z or shot.net_hit.is_empty():
				step_serve_reception(shot,previous,delta)
			if phase=="serve_flight" and flight_age>shot.planned_duration+.45: next_serve()

func receive_arrival(shot,height: float) -> float:
	var low := 0.
	var high: float=shot.planned_duration
	for i in 12:
		var mid := (low+high)*.5
		if shot.flight_point(mid).y>height: low=mid
		else: high=mid
	return high

func plan_serve_reception(shot) -> void:
	receive_at=receive_arrival(shot,PASS_HEIGHT)
	var predicted: Vector3=shot.flight_point(receive_at)
	receiver=0
	for i in range(1,passers.size()):
		if passers[i].position.distance_squared_to(predicted)<first_contact_player().position.distance_squared_to(predicted): receiver=i
	if receiving_setter.position.distance_to(predicted)+.65<first_contact_player().position.distance_to(predicted): receiver=passers.size()
	var platform := receptions[receiver]
	var passer := first_contact_player()
	var above := receive_arrival(shot,passer.height_cm*.011)
	var high_point: Vector3=shot.flight_point(above)
	var travel := (high_point-passer.position).slide(Vector3.UP)
	platform.hand_setting=flight_style() in [1,2] and high_point.z>BallNet.NET_Z and travel.length()<.55+3.3*maxf(0.,above-.22)
	if platform.hand_setting: receive_at=above
	elif not platform_clips.is_empty(): platform.set_receive_clip(platform_clips.pick_random())
	platform.quick_hand_receive=platform.hand_setting
	platform.passing_skill_override=passer.attributes.get("Hand reception" if platform.hand_setting else "Forearm reception",65)
	platform.destination=Vector2(SETTER_BASE.x,SETTER_BASE.z)
	platform.height=4.1
	platform.quick_low_save=true
	platform.green_forearm_allowance=.30
	platform.green_hand_allowance=.18

func step_serve_reception(shot,previous: Vector3,delta: float) -> void:
	var platform := receptions[receiver]
	var passer := first_contact_player()
	var path := func(t: float) -> Vector3:
		if not shot.net_hit.is_empty() and t>=shot.net_hit.time: return BallNet.after_hit(shot.net_hit,t)
		return shot.flight_point(t)
	var predicted: Vector3=path.call(receive_at)
	var incoming := (ball.position-previous)/maxf(.001,delta)
	if flight_age<receive_at-.31:
		move_receiver(passer,Vector3(predicted.x,.04,predicted.z+.52),delta)
		face_receive_ball(passer,ball.global_position,delta)
		return
	if not is_finite(platform.pressed_at):
		passer.play_action("idle")
		platform.queue_bump(flight_age)
	passer.animator.advance(delta)
	platform.allow_auto_dive=(predicted-platform.ready_contact()).slide(Vector3.UP).length()>1.15 or flight_age>receive_at
	if not is_finite(platform.touch_time):
		var chase: float=(predicted-(SETTER_HOME if receiver==passers.size() else HOMES[receiver])).slide(Vector3.UP).length()/maxf(receive_at,.1)
		var off_center := (predicted-platform.ready_contact()).slide(Vector3.UP).length()
		platform.reception_pressure=.18*smoothstep(6.,20.,incoming.length())+.25*smoothstep(.4,3.2,chase)+.42*smoothstep(.15,1.1,off_center)
	platform.update_attempt(flight_age,flight_age-delta,shot.planned_duration,path,incoming,delta,receive_at,shot.reception_spin_rps())
	if not is_finite(platform.touch_time): return
	if platform.hand_setting and not is_finite(platform.release_time):
		ball.position=platform.platform_center()
		return
	begin_offense(passer,platform)

func begin_offense(passer: Node3D,platform: Reception) -> void:
	pass_start=platform.release_point if platform.hand_setting else platform.touch
	var velocity := platform.outgoing
	var height: float=second_contact_player().height_cm*.0118
	var discriminant := velocity.y*velocity.y-19.62*(height-pass_start.y)
	if discriminant<0.:
		ball.position=pass_start
		drop_velocity=velocity
		phase="serve_miss"
		flight_age=0.
		roll_time=-1.
		drop_net_hit.clear()
		drop_net_time=0.
		return
	pass_duration=(velocity.y+sqrt(discriminant))/9.81
	pass_end=pass_start+velocity*pass_duration+Vector3.DOWN*4.905*pass_duration*pass_duration
	trace("serve_pass_result",{"pass_target":str(pass_end),"setter_travel_m":(pass_end-second_contact_player().global_position).slide(Vector3.UP).length(),"pass_seconds":pass_duration,"pressure":platform.reception_pressure})
	var chase_time := (pass_end-second_contact_player().global_position).slide(Vector3.UP).length()/4.8
	pipe_lane=clampf(passers[0].global_position.x,-3.3,3.3)
	pass_in_system=pass_end.z<=BallNet.NET_Z+3. and chase_time+.25<pass_duration
	var middle_ready := (route_point(1)+Vector3.BACK*1.6-receiving_middle.global_position).slide(Vector3.UP).length()/4.8+.38<pass_duration
	middle_commit=pass_in_system and middle_ready and attack_results[1]>.85 and randf()<clampf(.5+.14*attack_results[1],.5,.92)
	var best := -INF
	for slot in attack_options.size():
		var actor := attack_options[slot]
		if actor==passer and platform.low_save.active: continue
		if slot in [1,3] and not pass_in_system: continue
		if slot==3 and not middle_ready: continue
		if slot==3 and not middle_commit and called_slot!=3: continue
		var staging := route_point(slot)+Vector3.BACK*1.6
		var travel := (staging-actor.global_position).slide(Vector3.UP).length()/4.8
		var recovery := .48 if actor==passer else 0.
		if slot==3 and (actor.global_position-route_point(3)).slide(Vector3.UP).length()>4.8*maxf(0.,pass_duration+ONE_FLIGHT-.55): continue
		if slot==1 and travel>pass_duration+ONE_FLIGHT-.25: continue
		var score := randf()*.85+(.85 if slot==called_slot else 0.)-.50*travel-recovery
		score-=recent_misses[slot]*1.1+.65*(1.-actor.stamina.fraction())
		score+=1.15*lane_space(route_point(slot).x)
		score+=clampf(attack_results[slot]*.40,-.55,.65)
		if middle_commit: score+=[.55,-1.4,.55,1.15][slot]
		if not pass_in_system and slot in [0,2]: score+=.65
		if score>best:
			best=score
			attack_slot=slot

	set_at=pass_duration
	pass_clock=0.
	ball.position=pass_start
	passer.stamina.spend(passer.stamina.DIVE_COST if platform.low_save.active else 1.,"Receive")
	phase="serve_pass"

func ready_weight_for_routes() -> bool:
	var driver=serves[toss_style]
	return serve_clock>=(driver.toss_release_time() if driver.has_method("toss_release_time") else .18)

func face_receive_ball(actor: Node3D,point: Vector3,delta: float) -> void:
	var heading := actor.get_parent_node_3d().to_local(point)-actor.position
	GroundControls.face(actor,heading,delta,9.)

func transition_base(slot: int) -> Vector3:
	var point := route_point(slot)
	if slot==3 and phase in ["serve_flight","serve_toss"]: point.x=passers[0].global_position.x
	if slot in [0,2]: point.x+=signf(point.x)*.85
	point.z=BallNet.NET_Z+(5.5 if slot==3 else 3.3)
	point.y=.04
	return point

func stage_attacker(actor: Node3D,slot: int,delta: float) -> void:
	var point := transition_base(slot)
	if phase=="serve_pass":
		var quick := slot not in [0,2] or (pass_in_system and pin_flight_time(slot)<=ONE_FLIGHT)
		var entry := smoothstep(0.,.4,(.92 if quick else .12)-(set_at-pass_clock))
		point.z=lerpf(point.z,route_point(slot).z+1.6,entry)
		if slot in [0,2]: point.x=lerpf(point.x,route_point(slot).x+signf(point.x)*.45,entry)
	var pin_load := 0.
	if slot in [0,2] and phase=="serve_pass":
		pin_load=smoothstep(0.,.52,.57-(set_at-pass_clock))
		if slot!=attack_slot and pass_in_system and pin_flight_time(slot)<=ONE_FLIGHT: point.z-=.45*pin_load
	if slot==1 and phase in ["serve_toss","serve_flight","serve_pass"]:
		var start := second_contact_player().global_position.slide(Vector3.UP)
		var finish := (pass_end if phase=="serve_pass" else SETTER_BASE).slide(Vector3.UP)
		if start.distance_squared_to(finish)>.01:
			var nearest := Geometry3D.get_closest_point_to_segment(point.slide(Vector3.UP),start,finish)
			if nearest.distance_to(point.slide(Vector3.UP))<.95 or Geometry3D.get_closest_point_to_segment(actor.global_position.slide(Vector3.UP),start,finish).distance_to(actor.global_position.slide(Vector3.UP))<.85:
				var lateral := (finish-start).normalized().cross(Vector3.UP)
				if lateral.dot(actor.global_position.slide(Vector3.UP)-nearest)<0.: lateral=-lateral
				var retreat_depth := point.z
				point=nearest+lateral*1.1
				point.y=.04
				point.z=maxf(point.z,retreat_depth)
	var parent := actor.get_parent_node_3d()
	var facing := parent.to_local(route_point(slot) if pin_load>0. else ball.global_position)-actor.position
	move_receiver(actor,parent.to_local(point),delta,facing)
	if pin_load>0. and slot!=attack_slot: actor.pose_pin_draw(pin_load)

func clear_ground_step(actor: Node3D,step: Vector3) -> Vector3:
	var start := actor.global_position.slide(Vector3.UP)
	var desired := actor.get_parent_node_3d().global_basis*step
	for angle in [0.,.48,-.48,.90,-.90,1.40,-1.40,1.75,-1.75]:
		var candidate := desired.rotated(Vector3.UP,angle)
		var safe := true
		for other in receiving_team:
			if other==actor: continue
			var center := other.global_position.slide(Vector3.UP)
			var separation := start.distance_to(center)
			if separation<.70 and candidate.dot(start-center)>0.: continue
			if Geometry3D.get_closest_point_to_segment(center,start,start+candidate).distance_to(center)<.70:
				safe=false
				break
		if safe: return actor.get_parent_node_3d().global_basis.inverse()*candidate
	return Vector3.ZERO

func move_receiver(actor: Node3D,goal: Vector3,delta: float,face_direction := Vector3.ZERO,pace := 4.8) -> void:
	var travel := (goal-actor.position).slide(Vector3.UP)
	var step := travel.limit_length(pace*delta)
	if step.length_squared()>.000001: step=clear_ground_step(actor,step)
	actor.position+=step
	var heading := face_direction if not face_direction.is_zero_approx() else travel
	if heading.length()>.08:
		actor.rotation.y=rotate_toward(actor.rotation.y,atan2(heading.x,heading.z),delta*10.)
	actor.play_travel_gait(step/maxf(delta,.001))
	actor.animator.advance(delta)

func step_reception_rally(delta: float) -> void:
	pass_clock+=delta
	if phase=="serve_pass":
		var attack_point := route_point(attack_slot)
		attack_point.y=contact_height_for(attack_slot)
		if pass_in_system and attack_slot!=1 and not middle_decoy.enabled and set_at-pass_clock<.48 and set_at-pass_clock>.22:
			if (receiving_middle.global_position-route_point(1)).slide(Vector3.UP).length()<2.:
				if receiving_middle.get_parent()!=pin_frame: receiving_middle.reparent(pin_frame,true)
				var quick := route_point(1)
				quick.y=contact_height_for(1)
				var launch := (quick-pass_end)/ZERO_FLIGHT+Vector3.UP*4.905*ZERO_FLIGHT
				middle_decoy.jump.front_limit=3.35
				middle_decoy.jump.max_height=pin_attack.jump.max_height
				middle_decoy.start_set(receiving_middle,pin_frame.to_local(pass_end),pin_frame.global_basis.inverse()*launch,pin_frame.to_local(quick),pin_frame.to_local(scoring_target(quick)),pass_clock-set_at,true)
				middle_decoy.pin_arrival=ZERO_FLIGHT
				middle_decoy.approach_intercept=pin_frame.to_local(quick)
				middle_decoy.approach_steps=2
				middle_decoy.begin_attack_jump(Vector2.ZERO,.30,middle_decoy.jump.max_height-.2032)
				middle_decoy.jump.release()
				receiving_middle.stamina.spend(5,"Jump")
		for slot in attack_options.size():
			var actor := attack_options[slot]
			if actor==first_contact_player() and (pass_clock<.32 or receptions[receiver].low_save.active): continue
			if slot==1 and middle_decoy.enabled: continue
			if actor!=pin_attack.setter or not pin_attack.enabled: stage_attacker(actor,slot,delta)
		var facing := (Vector3(-4.5,0.,BallNet.NET_Z)-pass_end).slide(Vector3.UP).normalized()
		var stance := Vector3(pass_end.x,.04,pass_end.z)-facing*.30
		var lift: float=SET_VERTICAL*second_contact_player().stamina.effectiveness()
		# Descending intersection of the existing pass arc with airborne hand height.
		var arc_term := 4.905*pass_duration*pass_duration
		var rise := pass_end.y-pass_start.y+arc_term
		var u := (rise+sqrt(maxf(0.,rise*rise+4.*arc_term*(pass_start.y-pass_end.y-lift))))/(2.*arc_term)
		var crossing_net := pass_end.z<BallNet.NET_Z+.10 and pass_start.z>BallNet.NET_Z+.10
		if crossing_net:
			u=minf(u,inverse_lerp(pass_start.z,pass_end.z,BallNet.NET_Z+.10))
		var intercept := arc(pass_start,pass_end,u,arc_term*.25)
		var jump_at := pass_duration*u-SET_LOAD-receiving_jump.flight_duration(lift,true)*.5
		var plant := Vector3(intercept.x,.04,intercept.z)-facing*.30
		if not receiving_jump.active:
			var chase_goal := plant if pass_clock<=jump_at+delta else stance
			chase_goal.z=maxf(chase_goal.z,BallNet.NET_Z+.22)
			var travel := (chase_goal-second_contact_player().position).slide(Vector3.UP).length()
			var pace := clampf(travel/maxf(.05,set_at-pass_clock-.1),4.8,6.05)
			move_receiver(second_contact_player(),chase_goal,delta,facing,pace)
			plant.z=maxf(plant.z,BallNet.NET_Z+.22)
			var jump_range := 1.25 if crossing_net else .65
			if pass_clock>=jump_at and pass_clock<pass_duration*u-.12 and second_contact_player().position.distance_to(plant)<jump_range and lift>.20:
				second_contact_player().rotation.y=atan2(facing.x,facing.z)
				receiving_jump.begin(second_contact_player(),Vector2.ZERO,second_contact_player().position if crossing_net else plant,SET_LOAD,SET_VERTICAL,2,false,1.,true)
				receiving_jump.release()
				second_contact_player().stamina.spend(5,"Jump")
				set_at=pass_duration*u
		var runner := attack_options[attack_slot]
		var gap := (attack_point+Vector3.BACK*1.6-runner.global_position).slide(Vector3.UP).length()
		var planned := intercept if receiving_jump.active else pass_end
		var can_approach := gap<1.2 if attack_slot!=3 else (attack_point-runner.global_position).slide(Vector3.UP).length()<=4.8*maxf(0.,set_at-pass_clock+ONE_FLIGHT-.50)
		var fast := pass_in_system and planned.z<=BallNet.NET_Z+3. and can_approach and (runner!=first_contact_player() or pass_clock>.48)
		if (attack_slot==1 or fast and (attack_slot!=3 or middle_decoy.enabled)) and not pin_attack.enabled and set_at-pass_clock<(.24 if attack_slot==3 else .48):
			if runner.get_parent()!=pin_frame: runner.reparent(pin_frame,true)
			var planned_duration := ZERO_FLIGHT if attack_slot==1 else pin_flight_time(attack_slot)
			var launch := (attack_point-planned)/planned_duration+Vector3.UP*4.905*planned_duration
			pin_attack.jump.front_limit=.96 if attack_slot==3 else 3.35
			pin_attack.start_set(runner,pin_frame.to_local(planned),pin_frame.global_basis.inverse()*launch,pin_frame.to_local(attack_point),pin_frame.to_local(scoring_target(attack_point)),pass_clock-set_at,true)
			pin_attack.pin_arrival=planned_duration
			if attack_slot==1 and gap<1.2:
				pin_attack.approach_steps=2
				pin_attack.approach_intercept=pin_frame.to_local(attack_point)
				pin_attack.begin_attack_jump(Vector2.ZERO,.32,pin_attack.jump.max_height-.2032)
				pin_attack.jump.release()
		if receiving_jump.active: receiving_jump.step(second_contact_player(),delta,Vector2.ZERO)
		if not pin_attack.enabled or first_contact_player()!=pin_attack.setter:
			first_contact_player().animator.advance(delta)
			var platform := receptions[receiver]
			if platform.low_save.active and not platform.low_save.finished(flight_age+pass_clock):
				platform.low_save.sample(first_contact_player(),flight_age+pass_clock,platform.touch_time)
			elif not platform.hand_setting and pass_clock<.35: platform.follow_forearm(platform.touch_time+pass_clock,Vector3.ZERO)
			elif first_contact_player()!=passers[1]: first_contact_player().play_action("idle")
		ball.position=arc(pass_start,pass_end,pass_clock/pass_duration,arc_term*.25)
		if pass_clock>set_at-.33:
			second_contact_player().rotation.y=atan2(facing.x,facing.z)
			var load_weight := smoothstep(set_at-.33,set_at-.05,pass_clock)
			SetHands.apply(second_contact_player(),ball.position,load_weight,Vector3.ZERO,0.,0.,false,Vector3.ZERO,0.,attack_point-ball.position,load_weight,true,-1.,null,facing,true)
		if pass_clock>=set_at:
			var hands_height: float=second_contact_player().global_position.y+second_contact_player().height_cm*.0118
			if ball.position.z<BallNet.NET_Z or ball.position.y>hands_height+.24 or (second_contact_player().position-ball.position).slide(Vector3.UP).length()>.85:
				trace("serve_set_miss",{"jumped":receiving_jump.active,"ball":str(ball.position),"setter":str(second_contact_player().position)})
				var t := pass_clock/pass_duration
				drop_velocity=(pass_end-pass_start+Vector3.UP*arc_term*(1.-2.*t))/pass_duration
				phase="serve_miss"
				flight_age=0.
				roll_time=-1.
				drop_net_hit.clear()
				drop_net_time=0.
				return
			var pressure := smoothstep(.7,4.5,(ball.position-SETTER_BASE).slide(Vector3.UP).length()/maxf(.25,set_at))
			var accuracy := clampf(second_contact_player().effective_rating("Hand setting")/100.,0.,1.)
			var miss := Vector2.from_angle(randf()*TAU)*sqrt(randf())*(.18+pressure*(.65+1.8*(1.-accuracy)))
			pass_start=ball.position
			pass_end=second_contact_player().reachable_set(pass_start,attack_point+Vector3(miss.x,0.,miss.y),receiving_jump.active)
			pass_clock=0.

			var behind_line := pass_start.z>BallNet.NET_Z+3.
			if attack_slot==3 and (behind_line or not middle_decoy.enabled or receiving_middle.position.y<middle_decoy.jump.start.y+.06):
				attack_slot=0 if pass_start.x>0. else 2
				attack_point=route_point(attack_slot)
				attack_point.y=contact_height_for(attack_slot)
				pass_end=second_contact_player().reachable_set(pass_start,attack_point,receiving_jump.active)
			var selected := attack_options[attack_slot]
			var ready_gap := (route_point(attack_slot)+Vector3.BACK*1.6-selected.global_position).slide(Vector3.UP).length()
			var prepared := pin_attack.enabled and pin_attack.setter==selected and pin_attack.stage==pin_attack.Stage.SET
			if attack_slot==1:
				set_duration=ZERO_FLIGHT if prepared and pin_attack.jump.active and selected.position.y>pin_attack.jump.start.y+.045 else ONE_FLIGHT
			elif prepared:
				set_duration=pin_flight_time(attack_slot)
			elif pass_in_system and not behind_line:
				set_duration=clampf(pin_flight_time(attack_slot)+maxf(0.,ready_gap-.8)/4.8,ONE_FLIGHT,1.60)
			else: set_duration=1.60
			var duration := set_duration
			var velocity := (pass_end-pass_start)/duration+Vector3.UP*4.905*duration
			var target := scoring_target(pass_end)
			pin_attack.drill_speed_mps=attack_kmh/3.6
			var attacker := attack_options[attack_slot]
			if attacker.get_parent()!=pin_frame: attacker.reparent(pin_frame,true)
			pin_attack.jump.front_limit=.96 if attack_slot==3 else 3.35
			if pin_attack.enabled and pin_attack.setter==attacker and pin_attack.stage==pin_attack.Stage.SET:
				pin_attack.pass_origin=pin_frame.to_local(pass_start)
				pin_attack.pass_motion=pin_frame.global_basis.inverse()*velocity
				pin_attack.stage_start=pin_attack.clock
				pin_attack.rally_set_target=pin_frame.to_local(pass_end)
				pin_attack.approach_intercept=pin_frame.to_local(pass_end)
				pin_attack.flight_end=preload("res://scripts/pass_flight.gd").landing_time(pin_attack.pass_origin,pin_attack.pass_motion)
				pin_attack.swing_aim=pin_frame.to_local(target)
			else: pin_attack.start_set(attacker,pin_frame.to_local(pass_start),pin_frame.global_basis.inverse()*velocity,pin_frame.to_local(pass_end),pin_frame.to_local(target),0.,true)
			pin_attack.pin_arrival=duration
			pin_attack.approach_expected_hit_at=pin_attack.stage_start+duration
			trace("serve_attack_set",{"slot":attack_slot,"duration":duration,"hitter_gap_m":ready_gap,"stamina":selected.stamina.fraction(),"contact_height":pass_end.y,"approach_started":prepared,"release_depth_m":pass_start.z-BallNet.NET_Z,"in_system":pass_in_system,"middle_commit":middle_commit})
			aim_read=false
			closest_attack_gap=INF
			closest_attack_age=0.
			phase="serve_attack"
	else:
		if receiving_jump.active: receiving_jump.step(second_contact_player(),delta,Vector2.ZERO)
		else: second_contact_player().animator.advance(delta)
		if pass_clock<SetHands.CPU_FOLLOW_TIME:
			var offset := pass_end-pass_start
			var push := (offset+Vector3.UP*4.905*set_duration*set_duration).normalized()
			var extension := smoothstep(0.,SetHands.RELEASE_TIME,pass_clock)
			var weight := 1.-smoothstep(SetHands.RELEASE_TIME,SetHands.CPU_FOLLOW_TIME,pass_clock)
			SetHands.apply(second_contact_player(),pass_start,weight,push*.23*extension,0.,0.,false,Vector3.ZERO,extension,offset,1.,true,-1.,null,Vector3.ZERO,true)
		var t := pass_clock/set_duration
		ball.position=pass_start.lerp(pass_end,t)+Vector3.UP*4.905*set_duration*set_duration*t*(1.-t)
		var gap := pin_attack.right_palm().distance_to(pin_frame.to_local(ball.global_position))
		if gap<closest_attack_gap:
			closest_attack_gap=gap
			closest_attack_age=pass_clock
		if ball.position.y<.11:
			recent_misses[attack_slot]=minf(3.,recent_misses[attack_slot]+1.)
			trace("serve_attack_miss",{"closest_palm_m":closest_attack_gap,"closest_time_s":closest_attack_age,"slot":attack_slot,"stamina":attack_options[attack_slot].stamina.fraction(),"tempo_seconds":set_duration,"target":str(pass_end)})
			next_serve()

func lane_space(x: float) -> float:
	var nearest := INF
	for blocker in wall: nearest=minf(nearest,absf(blocker.global_position.x-x))
	return clampf((nearest-.45)/2.6,0.,1.)

func move_libero_to_cover(delta: float) -> void:
	var libero := passers[1]
	if second_contact_player()==libero and phase=="serve_pass": return
	if cover_slot>=0 and cover_players[cover_slot]==libero: return
	if phase=="serve_pass" and first_contact_player()==libero:
		var reception := receptions[receiver]
		if reception.low_save.active and not reception.low_save.finished(flight_age+pass_clock): return
		if pass_clock<.12: return
	# Zone five is on the receiving side's left, looking toward the net.
	var cover := Vector3(-3.,.04,BallNet.NET_Z+5.9)
	var here := libero.global_position.slide(Vector3.UP)
	var waypoint := cover
	for slot in attack_options.size():
		var start := attack_options[slot].global_position.slide(Vector3.UP)
		var finish := route_point(slot).slide(Vector3.UP)
		if start.distance_squared_to(finish)<.01: continue
		var nearest := Geometry3D.get_closest_point_to_segment(here,start,finish)
		if here.distance_to(nearest)<1.25:
			var away := (here-nearest).normalized()
			if away.length_squared()<.01: away=Vector3.RIGHT
			waypoint=here+away*1.4+Vector3.BACK*.35
			break
		var edge := Geometry3D.get_closest_points_between_segments(here,cover.slide(Vector3.UP),start,finish)
		if edge[0].distance_to(edge[1])<1.15:
			waypoint=Vector3(here.x,.04,maxf(start.z,finish.z)+1.45)
			break
	waypoint.y=.04
	move_receiver(libero,waypoint,delta,ball.global_position-libero.global_position)

func scoring_target(origin: Vector3) -> Vector3:
	var best := -INF
	var target := Vector3(0,.11,-3.)
	for x: float in [-4.1,-3.,-1.5,0.,1.5,3.,4.1]:
		for z: float in [-4.4,-2.,0.,1.5,2.25]:
			var point := Vector3(x,.11,z)
			var u := clampf((BallNet.NET_Z-origin.z)/(point.z-origin.z),0.,1.)
			var crossing := origin.lerp(point,u)
			var gap := INF
			for blocker in wall:
				var at_block := clampf((blocker.global_position.z-origin.z)/(point.z-origin.z),0.,1.)
				var lane := lerpf(origin.x,x,at_block)
				gap=minf(gap,absf(lane-blocker.global_position.x)-.48)
			var margin := crossing.y-BallNet.NET_TOP-BallNet.RADIUS-.13
			if margin<0.: continue
			var score := minf(gap,2.2)+.22*lane_space(x)-5.*maxf(0.,-margin)+randf()*.04
			if score>best:
				best=score
				target=point
	return target

func block_on_flight_segment(previous: Vector3) -> bool:
	if phase!="serve_return" or return_touched or not attack_floor_pending: return false
	return_touched=resolve_block_contact(previous,wall_jumps,-1.)
	return return_touched

func attack_surface_contact(point: Vector3,floor_hit: bool) -> void:
	if phase!="serve_return":
		super.attack_surface_contact(point,floor_hit)
		return
	if attack_decided: return
	attack_decided=true
	trace("serve_return_surface",{"floor":floor_hit,"position":str(point),"block_touch":return_touched,"net_contact":not drop_net_hit.is_empty()})
	var outside := absf(point.x)>4.5 or absf(point.z-BallNet.NET_Z)>9. or not floor_hit
	var scored := return_touched if outside else point.z<BallNet.NET_Z
	if last_shot_slot>=0:
		for i in attack_results.size(): attack_results[i]*=.88
		attack_results[last_shot_slot]+=1. if scored else -.55
	message.text=("Block out" if outside and return_touched else "Point") if scored else "Ball down"

func try_cover(previous: Vector3,delta: float) -> void:
	var now := ball.global_position
	var downward := drop_velocity.y
	var until_floor := (downward+sqrt(maxf(0.,downward*downward+19.62*(now.y-.11))))/9.81
	var landing := now+drop_velocity*until_floor
	if absf(landing.x)>4.5+Contact.BALL_RADIUS or landing.z>BallNet.NET_Z+9.+Contact.BALL_RADIUS: return
	var until_pass := clampf((downward+sqrt(maxf(0.,downward*downward+19.62*(now.y-.95))))/9.81,0.,until_floor)
	var intercept := now+drop_velocity*until_pass+Vector3.DOWN*4.905*until_pass*until_pass
	if intercept.z<BallNet.NET_Z or absf(intercept.x)>4.85 or intercept.z>BallNet.NET_Z+9.35: return
	if cover_slot<0:
		var nearest := INF
		for i in cover_players.size():
			var actor := cover_players[i]
			if (actor==pin_attack.setter and pin_attack.enabled) or (actor==receiving_middle and middle_decoy.enabled) or (actor==second_contact_player() and receiving_jump.active): continue
			var gap := (actor.global_position-intercept).slide(Vector3.UP).length()
			if gap<nearest:
				nearest=gap
				cover_slot=i
		if cover_slot<0: return
		var defender := cover_players[cover_slot]
		if defender.get_parent()!=world: defender.reparent(world,true)
		var platform := receptions[cover_slot]
		platform.reset()
		platform.hand_setting=false
		platform.destination=Vector2(SETTER_BASE.x,SETTER_BASE.z)
		platform.height=4.1
		platform.quick_low_save=true
		platform.allow_auto_dive=true
		platform.passing_skill_override=defender.effective_rating("Forearm reception")
		cover_clock=0.
	var defender := cover_players[cover_slot]
	var platform := receptions[cover_slot]
	var start := cover_clock
	cover_clock+=delta
	if not platform.low_save.active:
		move_receiver(defender,Vector3(intercept.x,.04,intercept.z+.38),delta)
		face_receive_ball(defender,now,delta)
	if until_pass>.38: return
	if not is_finite(platform.pressed_at): platform.queue_bump(start)
	var path := func(t: float) -> Vector3:
		if t<=cover_clock: return previous.lerp(now,clampf((t-start)/maxf(delta,.001),0.,1.))
		var ahead := t-cover_clock
		return now+drop_velocity*ahead+Vector3.DOWN*4.905*ahead*ahead
	platform.update_attempt(cover_clock,start,cover_clock+until_floor,path,drop_velocity,delta,cover_clock+until_pass)
	if not is_finite(platform.touch_time): return
	receiver=cover_slot
	cover_slot=-1
	flight_age=cover_clock
	called_slot=randi_range(0,3)
	wall_committed.fill(false)
	return_touched=false
	trace("block_covered",{"player":defender.player_number,"diving":platform.low_save.active})
	begin_offense(defender,platform)

func return_struck(_actor: Node3D,point: Vector3,velocity: Vector3,_spin: float) -> void:
	if phase!="serve_attack": return
	# A set can drift between the read and palm contact. Keep the chosen lane,
	# extending its depth only when the actual launch would clip the tape.
	if velocity.z<-.01 and point.z>BallNet.NET_Z:
		var t := (BallNet.NET_Z-point.z)/velocity.z
		var clearance := point.y+velocity.y*t-4.905*t*t-BallNet.NET_TOP-BallNet.RADIUS
		if clearance<.06:
			var goal := pin_frame.to_global(pin_attack.swing_contact_aim)
			var speed := velocity.length()
			for depth in 12:
				goal.z=maxf(BallNet.NET_Z-8.8,goal.z-.65)
				var offset := goal-point
				var term := speed*speed-9.81*offset.y
				var disc := term*term-9.81*9.81*offset.length_squared()
				if disc<0.: break
				var duration := sqrt(2.*offset.length_squared()/(term+sqrt(disc)))
				var trial := offset/duration+Vector3.UP*4.905*duration
				t=(BallNet.NET_Z-point.z)/trial.z
				if point.y+trial.y*t-4.905*t*t>=BallNet.NET_TOP+BallNet.RADIUS+.06:
					velocity=trial
					break
	trace("serve_attack_strike",{"slot":attack_slot,"speed_kmh":velocity.length()*3.6,"point":str(point)})
	for defender in wall: defender.block_read(_actor).record_velocity(velocity)
	for i in recent_misses.size(): recent_misses[i]*=.8
	recent_misses[attack_slot]*=.35
	last_shot_slot=attack_slot
	attack_decided=false
	cover_slot=-1
	return_touched=false
	ball.global_position=point
	drop_velocity=velocity
	drop_net_hit.clear()
	drop_net_time=0.
	roll_time=-1.
	floor_linger=0.
	attack_floor_pending=true
	hard_spike_floor_pending=true
	hand_impact.play()
	phase="serve_return"

func step_serve_wall(delta: float) -> void:
	for i in wall.size():
		var actor := wall[i]
		actor.stamina.recover(delta)
		var block: RefCounted=wall_jumps[i]
		if block!=null:
			block.read_air_lane(ball.global_position,wall)
			if not block.step(delta,ball.global_position): wall_jumps[i]=null
			continue
		var middle_up := receiving_middle.global_position.y>MIDDLE_HOME.y+.04 and (middle_decoy.jump.active or (pin_attack.setter==receiving_middle and pin_attack.jump.active))
		var committing := middle_commit and pass_in_system and middle_up and i==1 and phase=="serve_pass"
		var reading_set := phase=="serve_attack" or committing
		var recovering := (phase=="serve_pass" and last_shot_slot>=0) or (phase=="serve_return" and return_touched and not attack_decided and drop_velocity.z>0.)
		if not reading_set and not recovering:
			actor.animator.advance(delta)
			continue
		var goal := (i-1)*2.75
		if reading_set:
			var lead := clampi(roundi(pass_end.x/2.75)+1,0,2)
			var pattern: RefCounted=actor.block_read(attack_options[attack_slot])
			var shade: float=pattern.shade(pass_end.z-BallNet.NET_Z,pin_attack.pin_arrival-pass_clock)
			goal=route_point(1).x if committing else clampf(pass_end.x+shade+(i-lead)*.74,-4.35,4.35)
		else:
			# Read the hitter in this blocker's lane before the setter reveals the next target.
			var lane_slot: int=[2,1,0][i]
			var lane_read: RefCounted=actor.block_read(attack_options[lane_slot])
			goal+=clampf(lane_read.shade(route_point(lane_slot).z-BallNet.NET_Z)*lane_read.confidence,-.45,.45)
		var gap := goal-actor.position.x
		var step := clampf(gap,-3.6*delta,3.6*delta)
		actor.position.x+=step
		if not shuffle_steps.has(actor): shuffle_steps[actor]=preload("res://scripts/directional_footwork.gd").new(actor)
		actor.animator.advance(delta)
		shuffle_steps[actor].block_step(Vector3.RIGHT*step/maxf(delta,.001),gap,0.,not wall_committed[i],false,delta)
		var reachable := 1.35 if i==1 and attack_slot==1 else .82
		if reading_set and not wall_committed[i] and absf(gap)<reachable and (committing or pin_attack.pin_arrival-pass_clock<=.51):
			block=PracticeBlock.new()
			block.aggressive_press=true
			block.track_near_ball=true
			block.net_heading=0.
			block.jump_height=wall_vertical_inches*.0254*actor.stamina.effectiveness()
			block.begin(actor)
			actor.stamina.spend(5,"Block")
			wall_committed[i]=true
			wall_jumps[i]=block
