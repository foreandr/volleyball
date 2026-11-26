extends "res://scripts/attacking_camp.gd"

const TECHNIQUES := [preload("res://scripts/spin_serve.gd"),preload("res://scripts/jump_float_serve.gd"),preload("res://scripts/standing_float_serve.gd"),preload("res://scripts/underhand_serve.gd")]
const FACE := [JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_X,JOY_BUTTON_Y]
const LABELS := ["Spin","Float","Standing float","Underhand"]
const HOMES := [Vector3(-2.9,.04,9.2),Vector3(0,.04,10.),Vector3(2.9,.04,9.2)]
var serves := []
var passers: Array[Node3D]=[]
const JUMP_SERVE_VERTICAL := 57.*.0254
const JUMP_TOSS_APEX := [6.4,5.1]
const SERVE_EARLY := -.22
const SERVE_LATE := .075
const SERVE_PERFECT := .055
var toss_airborne := false
var toss_style := 2
var hit_style := 2
var release_time := INF
var serve_clock := 0.
var flight_age := 0.
var destination := Vector3.ZERO
var pass_start := Vector3.ZERO
var pass_clock := 0.
const SETTER_HOME := Vector3(1.4,.04,5.2)
const PASS_HEIGHT := 1.08
var receiving_setter: Node3D
var bucket: Node3D
var serve_station := Vector3(0,.04,-8.2)
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
	jump_height=JUMP_SERVE_VERTICAL
	hitter=setter
	cpu_hitter=false
	attack_jump.attack_arm_lift=true
	attack_jump.back_limit=-10.5
	attack_jump.load_lead_arm_clip()
	world.add_child(hand_impact)
	hand_impact.bus=StorySession.IMPACT_BUS
	hand_impact.stream=preload("res://assets/audio/hand_impacts.tres")
	coach.hide()
	rotation_drill.basket.hide()
	for item in rotation_drill.stock: item.hide()
	for target in targets: target.hide()
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
		var platform := Reception.new()
		world.add_child(platform)
		platform.configure(passer,preload("res://assets/animations/straight_pass_02.res"))
		platform.set_custom_backward(backward)
		platform.allow_knee_reach=true
		platform.receive_front_limit=13.8
		platform.hide()
		receptions.append(platform)
	receiving_jump.front_limit=13.
	receiving_jump.back_limit=BallNet.NET_Z+.25
	receiving_setter=athlete(SETTER_HOME,"286881")
	register_student(receiving_setter,6)
	preload("res://scripts/practice_kit.gd").apply(receiving_setter,false,6)
	bucket=targets[0]
	bucket.position=Vector3(-3.85,2.65,5.1)
	bucket.show()
	for i in TECHNIQUES.size():
		var driver=TECHNIQUES[i].new()
		world.add_child(driver)
		driver.configure(setter,Vector3(0,.04,[-8.2,-6.6,-6.1,-6.1][i]))
		driver.hide()
		serves.append(driver)
	title.text="SERVING"
	update_prompts("ready")
	apply_camera.call_deferred()
	next_serve()

func update_prompts(_next: String) -> void:
	if prompt_phase=="serving": return
	prompt_phase="serving"
	Xbox.prompts(controls_row,[["A","Spin"],["B","Jump float"],["X","Standing float"],["Y","Underhand"],["LS","Aim"]])

func apply_camera() -> void:
	place_practice_camera(Vector3(0,1.5,-4.4),distance*.48+2.)

func update_serve_aim(delta: float) -> void:
	var stick := Vector2(axis(JOY_AXIS_LEFT_X),axis(JOY_AXIS_LEFT_Y))
	if stick.length()>.16:
		var right := camera.global_basis.x.slide(Vector3.UP).normalized()
		var forward := -camera.global_basis.z.slide(Vector3.UP).normalized()
		destination+=(right*stick.x-forward*stick.y)*5.*delta
		destination.x=clampf(destination.x,-4.5,4.5)
		destination.z=clampf(destination.z,BallNet.NET_Z+.2,BallNet.NET_Z+9.)
	var shot=serves[hit_style]
	for driver in serves:
		driver.visible=driver==shot
		driver.ball.hide()
		driver.aim_ring.hide()
	if toss_style<2:
		shot.preview_origin=endpoint if toss_airborne else setter.position+setter.basis.z*2.15+Vector3.UP*(attack_contact_height()-setter.position.y)
	shot.apex=maxf(shot.preview_origin.y+.3,4.3 if hit_style==0 else 4.9)
	shot.target=destination
	shot.update_path_preview()

func contact_deadline() -> float:
	return flight_time+.12

func next_serve() -> void:
	for driver in serves: driver.hide()
	clear_attack_input()
	attack_jump.active=false
	approach_started=false
	swing_time=-1.
	toss_airborne=false
	phase="serve_ready"
	serve_clock=0.
	release_time=INF
	var ready=serves[2]
	ready.serve_start=serve_station
	ready.reset()
	ball.position=ready.ball.position
	ball.show()
	for i in passers.size():
		receptions[i].reset()
		passers[i].position=HOMES[i]
		passers[i].play_action("idle")
	receiving_jump.active=false
	receiving_setter.position=SETTER_HOME
	receiving_setter.rotation.y=PI
	receiving_setter.play_action("idle")
	message.text="Hold to serve"

func _input(event: InputEvent) -> void:
	if get_tree().paused or replay_inspector.active: return
	if settings.visible or event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index==Xbox.physical(JOY_BUTTON_START)):
		super._input(event)
		return
	if not event is InputEventJoypadButton: return
	var style := -1
	for i in FACE.size():
		if event.button_index==Xbox.physical(FACE[i]): style=i
	if style<0: return
	active_pad=event.device
	handle_serve_button(style,event.pressed)
	get_viewport().set_input_as_handled()

func handle_serve_button(style: int,pressed: bool) -> void:
	if pressed and phase=="serve_ready":
		toss_style=style
		hit_style=style
		serves[style].serve_start=serve_station
		serves[style].reset()
		receiver=randi_range(0,2)
		destination=HOMES[receiver]+Vector3(randf_range(-.55,.55),.065,1.1)
		phase="serve_toss"
		message.text=LABELS[style]
	elif phase=="serve_toss":
		if pressed and toss_style<2 and style<2:
			hit_style=style
			release_time=INF
			message.text=LABELS[toss_style]+" toss / "+LABELS[style]+" hit"
		elif not pressed and style==hit_style and not is_finite(release_time):
			release_time=serve_clock

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
	if serves.is_empty() or settings.visible or get_tree().paused: return
	for i in passers.size():
		passers[i].stamina.recover(delta)
		if i!=receiver or phase not in ["serve_flight","serve_pass"]:
			passers[i].animator.advance(delta)
	if phase not in ["serve_pass","serve_bucket"]:
		receiving_setter.animator.advance(delta)
	hitter.stamina.recover(delta)
	receiving_setter.stamina.recover(delta)
	if phase=="serve_ready":
		walk_server(delta)
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
				var shot=serves[hit_style]
				shot.origin=Contact.palm(setter,"r") if toss_style<2 else ball.position
				shot.apex=maxf(shot.origin.y+.3,4.3 if hit_style==0 else 4.9)
				shot.target=destination+Vector3(0,0,-error*8.)
				shot.planned_duration=shot.flight_duration(shot.origin)
				shot.velocity=shot.launch_velocity(shot.origin,shot.planned_duration)
				shot.begin_serve_curve()
				plan_serve_reception(shot)
				shot.net_hit=BallNet.first_hit(shot.flight_point,0.,shot.planned_duration)
				shot.ball.basis=ball.basis
				flight_age=0.
				phase="serve_flight"
				message.text=("Perfect" if absf(error)<=SERVE_PERFECT else ("Early" if error<0. else "Late"))+" / "+LABELS[hit_style]
				if toss_style>=2: hand_sound.play()
	elif phase in ["serve_flight","serve_pass","serve_bucket","serve_caught","serve_miss"]:
		serves[hit_style].hide()
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
			advance_missed_ball(delta,true)
			flight_age+=delta
			if flight_age>1.4: next_serve()
		elif phase in ["serve_pass","serve_bucket","serve_caught"]:
			step_reception_rally(delta)
		else:
			var shot=serves[hit_style]
			flight_age+=delta
			shot.advance_serve_curve(flight_age)
			shot.spin_serve_ball(delta)
			ball.basis=shot.ball.basis
			var t := minf(flight_age,shot.planned_duration)
			var previous := ball.position
			ball.position=BallNet.after_hit(shot.net_hit,t) if not shot.net_hit.is_empty() and t>=shot.net_hit.time else shot.flight_point(t)
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
		if HOMES[i].distance_squared_to(predicted)<HOMES[receiver].distance_squared_to(predicted): receiver=i
	var platform := receptions[receiver]
	var passer := passers[receiver]
	var above := receive_arrival(shot,passer.height_cm*.011)
	var high_point: Vector3=shot.flight_point(above)
	var travel := (high_point-passer.position).slide(Vector3.UP)
	platform.hand_setting=hit_style in [1,2] and high_point.z>BallNet.NET_Z and travel.length()<.55+3.3*maxf(0.,above-.22)
	if platform.hand_setting: receive_at=above
	elif not platform_clips.is_empty(): platform.set_receive_clip(platform_clips.pick_random())
	platform.quick_hand_receive=platform.hand_setting
	platform.passing_skill_override=passer.attributes.get("Hand reception" if platform.hand_setting else "Forearm reception",65)
	platform.destination=Vector2(SETTER_HOME.x,SETTER_HOME.z)
	platform.height=4.1
	platform.quick_low_save=true
	platform.green_forearm_allowance=.24
	platform.green_hand_allowance=.18

func step_serve_reception(shot,previous: Vector3,delta: float) -> void:
	var platform := receptions[receiver]
	var passer := passers[receiver]
	var path := func(t: float) -> Vector3:
		if not shot.net_hit.is_empty() and t>=shot.net_hit.time: return BallNet.after_hit(shot.net_hit,t)
		return shot.flight_point(t)
	var predicted: Vector3=path.call(receive_at)
	var incoming := (ball.position-previous)/maxf(.001,delta)
	if flight_age<receive_at-.31:
		move_receiver(passer,Vector3(predicted.x,.04,predicted.z+.52),delta)
		passer.rotation.y=PI
		return
	if not is_finite(platform.pressed_at):
		passer.play_action("idle")
		platform.queue_bump(flight_age)
	passer.animator.advance(delta)
	platform.allow_auto_dive=(predicted-platform.ready_contact()).slide(Vector3.UP).length()>1.15 or flight_age>receive_at
	platform.update_attempt(flight_age,flight_age-delta,shot.planned_duration,path,incoming,delta,receive_at,shot.reception_spin_rps())
	if not is_finite(platform.touch_time): return
	if platform.hand_setting and not is_finite(platform.release_time):
		ball.position=platform.platform_center()
		return
	pass_start=platform.release_point if platform.hand_setting else platform.touch
	var velocity := platform.outgoing
	var height: float=receiving_setter.height_cm*.0118
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
	set_at=pass_duration
	pass_clock=0.
	ball.position=pass_start
	passer.stamina.spend(passer.stamina.DIVE_COST if platform.low_save.active else 1.,"Receive")
	phase="serve_pass"

func move_receiver(actor: Node3D,goal: Vector3,delta: float) -> void:
	var travel := (goal-actor.position).slide(Vector3.UP)
	var step := travel.limit_length(4.8*delta)
	actor.position+=step
	actor.play_ground_gait(step.length()/maxf(delta,.001))
	if travel.length()>.08:
		actor.rotation.y=rotate_toward(actor.rotation.y,atan2(travel.x,travel.z),delta*10.)
	actor.animator.advance(delta)

func step_reception_rally(delta: float) -> void:
	pass_clock+=delta
	if phase=="serve_caught":
		ball.position.y=move_toward(ball.position.y,bucket.position.y-bucket.depth+.14,delta*2.8)
		if pass_clock>.75: next_serve()
		return
	var previous := ball.position
	if phase=="serve_pass":
		var facing := (bucket.position-pass_end).slide(Vector3.UP).normalized()
		var stance := Vector3(pass_end.x,.04,pass_end.z)-facing*.30
		var lift: float=SET_VERTICAL*receiving_setter.stamina.effectiveness()
		# Descending intersection of the existing pass arc with airborne hand height.
		var arc_term := 4.905*pass_duration*pass_duration
		var rise := pass_end.y-pass_start.y+arc_term
		var u := (rise+sqrt(maxf(0.,rise*rise+4.*arc_term*(pass_start.y-pass_end.y-lift))))/(2.*arc_term)
		var intercept := arc(pass_start,pass_end,u,arc_term*.25)
		var jump_at := pass_duration*u-SET_LOAD-receiving_jump.flight_duration(lift,true)*.5
		var plant := Vector3(intercept.x,.04,intercept.z)-facing*.30
		if not receiving_jump.active:
			move_receiver(receiving_setter,plant if pass_clock<=jump_at+delta else stance,delta)
			if pass_clock>=jump_at and pass_clock-jump_at<=delta and receiving_setter.position.distance_to(plant)<.24 and lift>.20 and receiving_setter.reachable_set(intercept,bucket.position,true).distance_to(bucket.position)<.15:
				receiving_setter.rotation.y=atan2(facing.x,facing.z)
				receiving_jump.begin(receiving_setter,Vector2.ZERO,plant,SET_LOAD,SET_VERTICAL,2,false,1.,true)
				receiving_jump.release()
				receiving_setter.stamina.spend(5,"Jump")
				set_at=pass_duration*u
		if receiving_jump.active: receiving_jump.step(receiving_setter,delta,Vector2.ZERO)
		passers[receiver].animator.advance(delta)
		var platform := receptions[receiver]
		if platform.low_save.active and not platform.low_save.finished(flight_age+pass_clock):
			platform.low_save.sample(passers[receiver],flight_age+pass_clock,platform.touch_time)
		elif not platform.hand_setting and pass_clock<.35: platform.follow_forearm(platform.touch_time+pass_clock,Vector3.ZERO)
		else: passers[receiver].play_action("idle")
		ball.position=arc(pass_start,pass_end,pass_clock/pass_duration,arc_term*.25)
		if pass_clock>set_at-.33:
			receiving_setter.rotation.y=atan2(facing.x,facing.z)
			preload("res://scripts/hand_setting_pose.gd").apply(receiving_setter,ball.position,smoothstep(set_at-.33,set_at-.05,pass_clock))
		if pass_clock>=set_at:
			if (receiving_setter.position-ball.position).slide(Vector3.UP).length()>.85:
				var t := pass_clock/pass_duration
				drop_velocity=(pass_end-pass_start+Vector3.UP*arc_term*(1.-2.*t))/pass_duration
				phase="serve_miss"
				flight_age=0.
				roll_time=-1.
				drop_net_hit.clear()
				drop_net_time=0.
				return
			pass_start=ball.position
			pass_end=receiving_setter.reachable_set(pass_start,bucket.position,receiving_jump.active)
			pass_clock=0.
			phase="serve_bucket"
	else:
		if receiving_jump.active: receiving_jump.step(receiving_setter,delta,Vector2.ZERO)
		else: receiving_setter.animator.advance(delta)
		if pass_clock<.22:
			var push := pass_start.direction_to(pass_end+Vector3.UP*2.)
			preload("res://scripts/hand_setting_pose.gd").apply(receiving_setter,pass_start+push*.18,1.-smoothstep(.07,.22,pass_clock))
		var t := pass_clock/1.35
		ball.position=pass_start.lerp(pass_end,t)+Vector3.UP*8.94*t*(1.-t)
		if bucket.crossed_mouth(previous,ball.position):
			bucket.impact(ball.position,(ball.position-previous)/maxf(delta,.001))
			phase="serve_caught"
			pass_clock=0.
		elif ball.position.y<.11: next_serve()
