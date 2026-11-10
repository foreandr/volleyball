extends "res://scripts/setting_drill.gd"

const Court = preload("res://scripts/preview_court.gd")
const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Footwork = preload("res://scripts/directional_footwork.gd")
const PIN := Vector3(-3.55,0.065,2.3)
const RECEIVE_START := Vector3(0.65,0.04,-3.10)
const CPU_HOME := Vector3(-0.55,0.04,1.15)
const PIN_HEIGHT := 2.75
const SET_APEX := 4.5

enum Stage { SERVE, PASS, SET, CAUGHT, MISS }
var stage := Stage.SERVE
var stage_start := 0.0
var serve_target: Vector3
var pass_origin: Vector3
var pass_motion: Vector3
var cpu_contact_time := 0.0
var cpu_contact_point: Vector3
var cpu_stand: Vector3
var cpu_set: MeshInstance3D
var cpu_feet: RefCounted
var pin_arrival := 0.0
var flight_end := 0.0

func reset_feed() -> void:
	if trace.feed > 0:
		trace.write("feed_end",clock,{"result":status.text,"closest_check":trace.closest_check},true)
	clock = 0.0
	stage_start = 0.0
	stage = Stage.SERVE
	if cpu_set == null:
		cpu_set = BumpSetting.new()
		add_child(cpu_set)
		cpu_set.configure(receiver,bump.clip)
		cpu_set.hand_setting = true
		cpu_set.hide()
		cpu_feet = Footwork.new(receiver)
	receiver.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	receiver.play_action("idle")
	receiver.position = CPU_HOME
	receiver.rotation.y = PI
	cpu_set.reset()
	jump.active = false
	setter.position = RECEIVE_START
	setter.rotation.y = 0.0
	bump.reset()
	bump.hand_setting = false
	bump.catch_only = false
	bump.destination = Vector2(-0.55,2.2)
	bump.height = 3.8
	serve_target = RECEIVE_START+Vector3(0.0,1.13,0.66)
	serve_velocity = (serve_target-SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	ball.position = SOURCE
	region.position = PIN
	region.hide()
	timing_cue.hide()
	status.text = "Receive the serve  |  Q"
	trace.begin_feed({"mode":"attack_catch","source":SOURCE,"serve_velocity":serve_velocity,"pin":PIN})

func set_key() -> int:
	return KEY_Q if stage == Stage.SERVE else KEY_E

func queue_set() -> void:
	if stage != Stage.SERVE and stage != Stage.SET: return
	bump.queue_bump(clock-stage_start)
	trace.write("attack_input",clock,{"stage":stage,"position":setter.position,"ball":ball.position},true)

func setter_is_diving() -> bool:
	return stage == Stage.SERVE and bump.low_save.active and not bump.low_save.finished(clock-stage_start)

func queue_jump(direction: Vector2) -> void:
	if jump.active or setter_is_diving() or stage == Stage.CAUGHT: return
	jump.begin(setter,direction)
	trace.write("jump",clock,{"position":setter.position,"direction":jump.heading},true)

func setter_movement_scale() -> float:
	if stage == Stage.SERVE:
		return bump.movement_scale(clock-stage_start,SERVE_TIME,ball.position)
	return 1.0

func step(delta: float) -> void:
	clock += delta
	var time := clock-stage_start
	var previous := maxf(0.0,time-delta)
	receiver.animator.advance(delta)
	match stage:
		Stage.SERVE: play_serve(time,previous,delta)
		Stage.PASS: play_cpu_set(time,delta)
		Stage.SET: play_pin_ball(time,previous,delta)
		Stage.CAUGHT:
			HandPose.apply(setter,setter.to_global(bump.hand_anchor),1.0)
			ball.position = bump.platform_center()
			if time >= 0.55 and not jump.active: reset_feed()
		Stage.MISS:
			if time >= 0.85: reset_feed()
	if stage == Stage.SERVE or stage == Stage.SET: trace.check_contact(bump.contact_check)
	if clock >= trace.next_sample: trace.sample(clock,trace_snapshot(clock-stage_start))

func trace_snapshot(time: float) -> Dictionary:
	var velocity := Vector3.ZERO
	match stage:
		Stage.SERVE: velocity = serve_velocity+Vector3.DOWN*Flight.GRAVITY*time
		Stage.PASS,Stage.SET: velocity = pass_motion+Vector3.DOWN*Flight.GRAVITY*time
	var platform: Vector3 = bump.platform_center()
	return {
		"stage":stage,"result":status.text,"ball_position":ball.position,"ball_velocity":velocity,
		"player_position":setter.position,"cpu_position":receiver.position,
		"ball_to_player":ball.position.distance_to(setter.position),
		"ball_to_cpu":ball.position.distance_to(receiver.position),
		"ball_to_platform":ball.position.distance_to(platform),
		"contact_check":bump.contact_check,"jumping":jump.active,
	}

func play_serve(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(SOURCE,serve_velocity,t)
	var end := Flight.landing_time(SOURCE,serve_velocity)
	ball.position = path.call(minf(time,end))
	timing_cue.update_timing(time,SERVE_TIME,BallPreview.GREEN_START,BallPreview.GREEN_END)
	bump.update_attempt(time,previous,end,path,serve_velocity+Vector3.DOWN*Flight.GRAVITY*time,delta,SERVE_TIME)
	if is_finite(bump.touch_time):
		pass_origin = bump.touch
		pass_motion = bump.outgoing
		var head_height := CPU_HOME.y+HandPose.CONTACT_HEIGHT
		cpu_contact_time = descending_time(pass_origin,pass_motion,head_height)
		if cpu_contact_time <= 0.0:
			miss("Pass was too low to set")
			return
		cpu_contact_point = flight_point(pass_origin,pass_motion,cpu_contact_time)
		var incoming := (pass_origin-cpu_contact_point).slide(Vector3.UP).normalized()
		cpu_stand = Court.clamp_setter(Vector3(cpu_contact_point.x,CPU_HOME.y,cpu_contact_point.z)-incoming*HandPose.CONTACT_FORWARD)
		receiver.rotation.y = atan2(incoming.x,incoming.z)
		stage = Stage.PASS
		stage_start = clock
		status.text = "CPU setting to the pin"
		trace.write("player_pass",clock,{"point":pass_origin,"velocity":pass_motion,"cpu_contact":cpu_contact_point},true)
	elif time >= end:
		miss("Serve missed")

func play_cpu_set(time: float, delta: float) -> void:
	if is_finite(cpu_set.touch_time):
		cpu_set.update_hand_push(time,time-cpu_set.touch_time)
		ball.position = cpu_set.platform_center()
		if is_finite(cpu_set.release_time):
			pass_origin = cpu_set.release_point
			pass_motion = cpu_set.outgoing
			pin_arrival = descending_time(pass_origin,pass_motion,PIN_HEIGHT)
			flight_end = Flight.landing_time(pass_origin,pass_motion)
			stage = Stage.SET
			stage_start = clock
			bump.reset()
			bump.hand_setting = true
			bump.catch_only = true
			trace.closest_check.clear()
			trace.closest_margin = INF
			status.text = "Jump at the pin  |  Space, then E"
			region.show()
			trace.write("cpu_set",clock,{"point":pass_origin,"velocity":pass_motion,"pin_arrival":pin_arrival},true)
		return
	ball.position = flight_point(pass_origin,pass_motion,minf(time,cpu_contact_time))
	var travel := (cpu_stand-receiver.position).limit_length(3.2*delta)
	receiver.position += travel
	cpu_feet.step(receiver.basis.inverse()*travel/maxf(delta*3.2,0.001),delta,1.4)
	var lead := cpu_contact_time-time
	if lead <= 0.22:
		HandPose.apply(receiver,cpu_contact_point,1.0-smoothstep(0.0,0.22,lead))
	if time >= cpu_contact_time:
		cpu_set.height = SET_APEX
		var ideal := set_toward_pin(cpu_contact_point)
		var target := flight_point(cpu_contact_point,ideal,Flight.landing_time(cpu_contact_point,ideal))
		cpu_set.destination = Vector2(target.x,target.z)
		cpu_set.begin_hand_contact(cpu_contact_point,time)

func play_pin_ball(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(pass_origin,pass_motion,t)
	ball.position = path.call(minf(time,flight_end))
	timing_cue.update_timing(time,pin_arrival,BumpSetting.GREEN_START,BumpSetting.GREEN_END)
	bump.catch_airborne = setter.position.y > RECEIVE_START.y+0.08
	bump.update_attempt(time,previous,flight_end,path,pass_motion+Vector3.DOWN*Flight.GRAVITY*time,delta,pin_arrival)
	if is_finite(bump.touch_time):
		stage = Stage.CAUGHT
		stage_start = clock
		status.text = "Caught at the pin"
		timing_cue.show_result(bump.grade)
		trace.write("pin_catch",clock,{"point":bump.touch,"grade":bump.grade,"contact":bump.contact_check},true)
	elif time >= flight_end:
		miss("Pin catch missed")

func miss(message: String) -> void:
	stage = Stage.MISS
	stage_start = clock
	status.text = message
	trace.write("attack_miss",clock,{"ball":ball.position,"player":setter.position,"closest_check":trace.closest_check},true)

func set_toward_pin(origin: Vector3) -> Vector3:
	var rise := sqrt(2.0*Flight.GRAVITY*(SET_APEX-origin.y))
	var duration := (rise+sqrt(2.0*Flight.GRAVITY*(SET_APEX-PIN_HEIGHT)))/Flight.GRAVITY
	return (PIN-origin).slide(Vector3.UP)/duration+Vector3.UP*rise

func descending_time(origin: Vector3, velocity: Vector3, height: float) -> float:
	var square := velocity.y*velocity.y+2.0*Flight.GRAVITY*(origin.y-height)
	return (velocity.y+sqrt(square))/Flight.GRAVITY if square >= 0.0 else -1.0
