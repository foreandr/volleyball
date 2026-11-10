extends "res://scripts/setting_drill.gd"

const Court = preload("res://scripts/preview_court.gd")
const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Footwork = preload("res://scripts/directional_footwork.gd")
const PIN := Vector3(3.55,0.065,2.3)
const RECEIVE_START := Vector3(3.05,0.04,-3.10)
const ATTACK_SERVE_SOURCE := Vector3(3.05,2.8,8.5)
const CPU_HOME := Vector3(-0.55,0.04,1.15)
const PIN_HEIGHT := 2.75
const SET_APEX := 5.0

enum Stage { SERVE, PASS, SET, HIT, MISS }
const SWING_CHARGE_TIME := 0.65
const SWING_REACH := 1.55
const SWING_CONTACT_HEIGHT := 2.45
const SWING_FOLLOW_TIME := 0.30
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
var swing_started := -INF
var swing_released := -INF
var swing_aim := Vector3(0.0,Flight.FLOOR,9.5)
var swing_contact: Vector3
var swing_power := 0.0
var swing_net_hit := {}
var swing_target: MeshInstance3D

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
	bump.show()
	bump.hand_setting = false
	bump.quick_hand_receive = false
	bump.catch_only = false
	bump.destination = Vector2(-0.55,2.2)
	bump.height = 3.8
	serve_target = RECEIVE_START+Vector3(0.0,1.13,-0.17)
	serve_velocity = (serve_target-ATTACK_SERVE_SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	ball.position = ATTACK_SERVE_SOURCE
	region.position = PIN
	region.hide()
	swing_started = -INF
	swing_released = -INF
	swing_net_hit.clear()
	if swing_target == null:
		swing_target = region.duplicate()
		add_child(swing_target)
	swing_target.hide()
	timing_cue.hide()
	status.text = "Receive  |  Q forearms, I / E hands"
	trace.begin_feed({"mode":"attacking","source":ATTACK_SERVE_SOURCE,"serve_velocity":serve_velocity,"pin":PIN})

func set_key() -> int:
	return KEY_Q if stage == Stage.SERVE else KEY_NONE

func can_aim_set() -> bool:
	return stage == Stage.SERVE and not is_finite(bump.touch_time)

func queue_hand_receive() -> void:
	if stage != Stage.SERVE or is_finite(bump.touch_time): return
	if is_finite(bump.pressed_at):
		if bump.hand_setting or is_finite(bump.pose_started_at): return
		bump.reset()
	bump.hand_setting = true
	bump.quick_hand_receive = true
	queue_set()

func receive_cue_time() -> float:
	if not bump.hand_setting: return SERVE_TIME
	var height := RECEIVE_START.y+HandPose.CONTACT_HEIGHT*setter.scale.y+HandPose.CONTACT_RADIUS
	var latest := descending_time(ATTACK_SERVE_SOURCE,serve_velocity,height)
	if not jump.active: return latest
	var earliest := descending_time(ATTACK_SERVE_SOURCE,serve_velocity,height+jump.height)
	if earliest < 0.0: return latest
	var jump_start := clock-stage_start-jump.elapsed
	for iteration in range(10):
		var midpoint := (earliest+latest)*0.5
		var progress := clampf((midpoint-jump_start-jump.LOAD_TIME)/jump.air_time,0.0,1.0)
		var hand_height := height+4.0*jump.height*progress*(1.0-progress)
		if flight_point(ATTACK_SERVE_SOURCE,serve_velocity,midpoint).y > hand_height:
			earliest = midpoint
		else:
			latest = midpoint
	return latest

func court_facing_weight() -> float:
	return 0.5 if stage == Stage.PASS or stage == Stage.SET else 0.0

func can_aim_swing() -> bool:
	return stage == Stage.SET

func aim_swing(point: Vector3) -> void:
	swing_aim = Vector3(clampf(point.x,-4.4,4.4),Flight.FLOOR,clampf(point.z,4.3,12.9))
	swing_target.position = Vector3(swing_aim.x,0.065,swing_aim.z)

func swing_input(pressed: bool) -> void:
	if stage != Stage.SET: return
	if not pressed:
		if is_finite(swing_started) and not is_finite(swing_released): swing_released = clock
		return
	if is_finite(swing_started) and not is_finite(swing_released): return
	swing_started = clock
	swing_released = -INF
	status.text = "Charging swing"
	trace.write("swing_start",clock,{"player":setter.position,"aim":swing_aim},true)

func swing_charge() -> float:
	return clampf((minf(clock,swing_released if is_finite(swing_released) else clock)-swing_started)/SWING_CHARGE_TIME,0.0,1.0)

func queue_set() -> void:
	if stage != Stage.SERVE: return
	bump.queue_bump(clock-stage_start)
	trace.write("attack_input",clock,{"stage":stage,"technique":"hands" if bump.hand_setting else "forearms","aim":bump.destination,"height":bump.height,"position":setter.position,"ball":ball.position},true)

func setter_is_diving() -> bool:
	if not bump.low_save.active: return false
	if stage == Stage.SERVE: return not bump.low_save.finished(clock-stage_start)
	return stage == Stage.PASS and not bump.low_save.finished(bump.touch_time+clock-stage_start)

func queue_jump(direction: Vector2) -> void:
	if jump.active or setter_is_diving() or stage == Stage.HIT: return
	jump.begin(setter,direction)
	trace.write("jump",clock,{"position":setter.position,"direction":jump.heading},true)

func setter_movement_scale() -> float:
	if stage == Stage.SERVE:
		return bump.movement_scale(clock-stage_start,receive_cue_time(),ball.position)
	return 1.0

func step(delta: float) -> void:
	clock += delta
	var time := clock-stage_start
	var previous := maxf(0.0,time-delta)
	receiver.animator.advance(delta)
	match stage:
		Stage.SERVE: play_serve(time,previous,delta)
		Stage.PASS:
			if not bump.hand_setting:
				var receive_time: float = bump.touch_time+time
				if setter_is_diving():
					bump.low_save.sample(setter,receive_time,bump.touch_time)
				elif not bump.low_save.active:
					bump.follow_forearm(receive_time,serve_velocity+Vector3.DOWN*Flight.GRAVITY*bump.touch_time)
			play_cpu_set(time,delta)
		Stage.SET:
			cpu_set.update_hand_push(cpu_set.release_time+time,cpu_set.release_time+time-cpu_set.touch_time)
			play_pin_ball(time)
		Stage.HIT: play_spike(time)
		Stage.MISS:
			if time >= 0.85: reset_feed()
	if stage == Stage.SERVE or stage == Stage.SET: trace.check_contact(bump.contact_check)
	if clock >= trace.next_sample: trace.sample(clock,trace_snapshot(clock-stage_start))

func trace_snapshot(time: float) -> Dictionary:
	var velocity := Vector3.ZERO
	match stage:
		Stage.SERVE: velocity = serve_velocity+Vector3.DOWN*Flight.GRAVITY*time
		Stage.PASS,Stage.SET,Stage.HIT: velocity = pass_motion+Vector3.DOWN*Flight.GRAVITY*time
	var platform: Vector3 = bump.platform_center()
	return {
		"stage":stage,"result":status.text,"ball_position":ball.position,"ball_velocity":velocity,
		"player_position":setter.position,"cpu_position":receiver.position,
		"ball_to_player":ball.position.distance_to(setter.position),
		"ball_to_cpu":ball.position.distance_to(receiver.position),
		"ball_to_platform":ball.position.distance_to(platform),
		"contact_check":bump.contact_check,"jumping":jump.active,
		"reach":bump.reach,"reach_step":bump.reach_step,"rear_setup":bump.rear_setup,"reach_progress":bump.reach_progress,
	}

func play_serve(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(ATTACK_SERVE_SOURCE,serve_velocity,t)
	var end := Flight.landing_time(ATTACK_SERVE_SOURCE,serve_velocity)
	ball.position = path.call(minf(time,end))
	var cue := receive_cue_time()
	timing_cue.update_timing(time,cue,BumpSetting.GREEN_START,BumpSetting.GREEN_END)
	bump.update_aim()
	bump.update_attempt(time,previous,end,path,serve_velocity+Vector3.DOWN*Flight.GRAVITY*time,delta,cue)
	if is_finite(bump.touch_time):
		if bump.hand_setting and not is_finite(bump.release_time):
			ball.position = bump.touch.lerp(bump.platform_center(),smoothstep(0.0,0.05,time-bump.touch_time))
			return
		pass_origin = bump.release_point if bump.hand_setting else bump.touch
		pass_motion = bump.outgoing
		var head_height := CPU_HOME.y+HandPose.CONTACT_HEIGHT*receiver.scale.y
		cpu_contact_time = descending_time(pass_origin,pass_motion,head_height)
		if cpu_contact_time <= 0.0:
			miss("Pass was too low to set")
			return
		cpu_contact_point = flight_point(pass_origin,pass_motion,cpu_contact_time)
		if cpu_contact_point.z >= 3.75 or (not bump.net_hit.is_empty() and bump.net_hit.time < cpu_contact_time):
			miss("Pass went past the setter")
			return
		bump.hide()
		var incoming := (pass_origin-cpu_contact_point).slide(Vector3.UP).normalized()
		cpu_stand = Court.clamp_setter(Vector3(cpu_contact_point.x,CPU_HOME.y,cpu_contact_point.z)-incoming*HandPose.CONTACT_FORWARD*receiver.scale.z)
		stage = Stage.PASS
		stage_start = clock
		status.text = "CPU setting to the pin"
		trace.write("player_pass",clock,{"point":pass_origin,"velocity":pass_motion,"cpu_contact":cpu_contact_point,
			"grade":bump.grade,"reach":bump.reach,"contact":bump.contact_check},true)
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
			bump.hand_setting = false
			trace.closest_check.clear()
			trace.closest_margin = INF
			status.text = "Space to jump  |  Hold left-click to spike"
			region.show()
			aim_swing(swing_aim)
			swing_target.show()
			trace.write("cpu_set",clock,{"point":pass_origin,"velocity":pass_motion,"pin_arrival":pin_arrival},true)
		return
	ball.position = flight_point(pass_origin,pass_motion,minf(time,cpu_contact_time))
	var travel := (cpu_stand-receiver.position).limit_length(3.2*delta)
	receiver.position += travel
	var toward_ball := (ball.position-receiver.position).slide(Vector3.UP)
	if toward_ball.length_squared() < 0.09 and travel.is_zero_approx():
		toward_ball = (pass_origin-cpu_contact_point).slide(Vector3.UP)
	if not toward_ball.is_zero_approx():
		receiver.rotation.y = rotate_toward(receiver.rotation.y,atan2(toward_ball.x,toward_ball.z),delta*9.0)
	cpu_feet.step(receiver.basis.inverse()*travel/maxf(delta*3.2,0.001),delta,1.4,true)
	var lead := cpu_contact_time-time
	if lead <= 0.22:
		HandPose.apply(receiver,cpu_contact_point,1.0-smoothstep(0.0,0.22,lead))
	if time >= cpu_contact_time:
		if receiver.position.distance_to(cpu_stand)>0.60:
			miss("CPU could not reach the pass")
			return
		cpu_set.height = SET_APEX
		var ideal := set_toward_pin(cpu_contact_point)
		var target := flight_point(cpu_contact_point,ideal,Flight.landing_time(cpu_contact_point,ideal))
		cpu_set.destination = Vector2(target.x,target.z)
		cpu_set.begin_hand_contact(cpu_contact_point,time)

func play_pin_ball(time: float) -> void:
	ball.position = flight_point(pass_origin,pass_motion,minf(time,flight_end))
	timing_cue.update_timing(time,pin_arrival,BumpSetting.GREEN_START,BumpSetting.GREEN_END)
	if is_finite(swing_started) and jump.active:
		var charge := swing_charge()
		status.text = "Swing power  |  %d%%" % roundi(charge*100.0)
		var toward_ball := ball.position-setter.global_position
		var airborne := setter.position.y > jump.start.y+0.08
		var in_reach := toward_ball.slide(Vector3.UP).length() <= SWING_REACH and toward_ball.y >= 1.35 and toward_ball.y <= SWING_CONTACT_HEIGHT
		if airborne and in_reach and time >= pin_arrival-0.24:
			hit_spike(charge)
			return
		var load := smoothstep(0.0,0.20,clock-swing_started)
		pose_bow_draw(load)
	if time >= flight_end: miss("Spike missed")

func hit_spike(charge: float) -> void:
	swing_contact = ball.position
	swing_power = charge
	pass_origin = swing_contact
	var target := swing_aim-pass_origin
	var duration := maxf(0.24,target.slide(Vector3.UP).length()/lerpf(11.0,29.0,charge))
	pass_motion = target/duration+Vector3.UP*Flight.GRAVITY*duration*0.5
	flight_end = duration
	swing_net_hit = Net.first_hit(func(t): return flight_point(pass_origin,pass_motion,t),0.0,duration)
	stage = Stage.HIT
	stage_start = clock
	region.hide()
	timing_cue.hide()
	status.text = "Spike  |  %d%% power" % roundi(charge*100.0)
	pose_bow_draw(1.0)
	trace.write("spike",clock,{"point":swing_contact,"aim":swing_aim,"velocity":pass_motion,"power":charge,"net":not swing_net_hit.is_empty()},true)

func play_spike(time: float) -> void:
	var end := flight_end if swing_net_hit.is_empty() else float(swing_net_hit.end_time)
	if not swing_net_hit.is_empty() and time >= swing_net_hit.time:
		ball.position = Net.after_hit(swing_net_hit,minf(time,end))
		status.text = "Spike hit the net"
	else:
		ball.position = flight_point(pass_origin,pass_motion,minf(time,end))
	if time < SWING_FOLLOW_TIME:
		pose_bow_draw(1.0-smoothstep(0.11,SWING_FOLLOW_TIME,time))
	if time >= end+0.48 and not jump.active: reset_feed()

func pose_bow_draw(weight: float) -> void:
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	author.rotate_world(pose,"spine_03",Vector3.UP,-0.32*weight)
	var right_shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw_hand := right_shoulder+Vector3(0.04,0.34,-0.15)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",
		draw_hand,Vector3(-0.85,0.52,-0.74),weight,108.0)
	var left_shoulder: Vector3 = author.point(pose,"upperarm_l")
	var guide_hand := left_shoulder+Vector3(0.06,0.43,0.64)
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",
		guide_hand,Vector3(0.26,-0.55,0.15),weight,174.0)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func miss(message: String) -> void:
	stage = Stage.MISS
	stage_start = clock
	status.text = message
	swing_target.hide()
	trace.write("attack_miss",clock,{"ball":ball.position,"player":setter.position,"closest_check":trace.closest_check},true)

func set_toward_pin(origin: Vector3) -> Vector3:
	var rise := sqrt(2.0*Flight.GRAVITY*(SET_APEX-origin.y))
	var duration := (rise+sqrt(2.0*Flight.GRAVITY*(SET_APEX-PIN_HEIGHT)))/Flight.GRAVITY
	return (PIN-origin).slide(Vector3.UP)/duration+Vector3.UP*rise

func descending_time(origin: Vector3, velocity: Vector3, height: float) -> float:
	var square := velocity.y*velocity.y+2.0*Flight.GRAVITY*(origin.y-height)
	return (velocity.y+sqrt(square))/Flight.GRAVITY if square >= 0.0 else -1.0
