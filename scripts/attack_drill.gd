extends "res://scripts/setting_drill.gd"

const Court = preload("res://scripts/preview_court.gd")
const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Footwork = preload("res://scripts/directional_footwork.gd")
const PIN := Vector3(3.55,0.065,2.85)
const RECEIVE_START := Vector3(3.05,0.04,-3.10)
const ATTACK_SERVE_SOURCE := Vector3(3.05,2.8,8.5)
const CPU_HOME := Vector3(-0.55,0.04,1.65)
const PIN_HEIGHT := 2.75
const SET_APEX := 5.0
const SET_TOPSPIN_RPS := 2.2

enum Stage { SERVE, PASS, SET, HIT, MISS }
const SWING_CHARGE_TIME := 0.65
const SWING_REACH := 1.55
const SWING_CONTACT_HEIGHT := 2.22
const PALM_RADIUS := 0.065
const SWING_FOLLOW_TIME := 0.30
var stage := Stage.SERVE
var swing_practice := true
var torso_rotation_scale := 2.0
var leg_kickback_scale := 2.0
var swing_button_down := false
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
var swing_charge_started := -INF
var swing_released := -INF
var swing_drive_started := -INF
var swing_drive_duration := 0.15
var previous_palm := Vector3.INF
var swing_hand_speed := 0.0
var swing_impact_speed := 0.0
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
	ball.rotation = Vector3.ZERO
	region.position = PIN
	region.hide()
	swing_started = -INF
	swing_charge_started = -INF
	swing_released = -INF
	swing_drive_started = -INF
	previous_palm = Vector3.INF
	swing_net_hit.clear()
	if swing_target == null:
		swing_target = region.duplicate()
		add_child(swing_target)
	swing_target.hide()
	timing_cue.hide()
	if swing_practice:
		start_swing_practice()
		return
	status.text = "Receive  |  Q forearms, I / E hands"
	trace.begin_feed({"mode":"attacking","source":ATTACK_SERVE_SOURCE,"serve_velocity":serve_velocity,"pin":PIN})

func set_swing_practice(enabled: bool) -> void:
	swing_practice = enabled
	swing_button_down = false
	reset_feed()

func start_swing_practice() -> void:
	stage = Stage.SET
	bump.hide()
	setter.position = PIN+Vector3(0.35,RECEIVE_START.y-PIN.y,-0.48)
	jump.begin(setter,Vector2(0.0,0.65))
	for frame in range(16): jump.step(setter,1.0/60.0,Vector2.ZERO)
	jump.release()
	receiver.rotation.y = atan2(PIN.x-CPU_HOME.x,PIN.z-CPU_HOME.z)
	var source := receiver.to_global(Vector3(0.0,HandPose.CONTACT_HEIGHT,HandPose.CONTACT_FORWARD))
	var velocity := set_toward_pin(source)
	var lead := 0.72
	var preroll := descending_time(source,velocity,PIN_HEIGHT)-lead
	pass_origin = flight_point(source,velocity,preroll)
	pass_motion = velocity+Vector3.DOWN*Flight.GRAVITY*preroll
	pin_arrival = lead
	flight_end = Flight.landing_time(pass_origin,pass_motion)
	ball.position = pass_origin
	region.show()
	aim_swing(swing_aim)
	swing_target.show()
	if swing_button_down: swing_started = clock
	status.text = "Hold left-click to swing"
	trace.begin_feed({"mode":"swing_practice","source":pass_origin,"velocity":pass_motion,"pin":PIN})

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
	swing_button_down = pressed
	if stage != Stage.SET: return
	if not pressed:
		if is_finite(swing_started) and not is_finite(swing_released): swing_released = clock
		return
	if is_finite(swing_started) and not is_finite(swing_released): return
	swing_started = clock
	swing_charge_started = -INF
	swing_released = -INF
	swing_drive_started = -INF
	previous_palm = Vector3.INF
	status.text = "Swing queued"
	trace.write("swing_start",clock,{"player":setter.position,"aim":swing_aim},true)

func swing_charge() -> float:
	return clampf((minf(clock,swing_released if is_finite(swing_released) else clock)-swing_charge_started)/(0.48 if swing_practice else SWING_CHARGE_TIME),0.0,1.0)

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
	restore_torso_lean(receiver)
	receiver.animator.advance(delta)
	apply_torso_lean(receiver)
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
			if not swing_practice:
				cpu_set.update_hand_push(cpu_set.release_time+time,cpu_set.release_time+time-cpu_set.touch_time)
			play_pin_ball(time,previous,delta)
		Stage.HIT: play_spike(time)
		Stage.MISS:
			if time >= (0.26 if swing_practice else 0.85): reset_feed()
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

func play_pin_ball(time: float, previous: float, delta: float) -> void:
	var spin_axis := Vector3.UP.cross(pass_motion).normalized()
	if not spin_axis.is_zero_approx(): ball.rotate(spin_axis,TAU*SET_TOPSPIN_RPS*delta)
	ball.position = flight_point(pass_origin,pass_motion,minf(time,flight_end))
	timing_cue.update_timing(time,pin_arrival,BumpSetting.GREEN_START,BumpSetting.GREEN_END)
	if is_finite(swing_started) and jump.active and setter.position.y > jump.start.y+0.02:
		if not is_finite(swing_charge_started): swing_charge_started = clock
		var charge := swing_charge()
		status.text = "Swing power  |  %d%%" % roundi(charge*100.0)
		var airborne := setter.position.y > jump.start.y+0.08
		var duration := lerpf(0.24,0.09,charge)
		var predicted := flight_point(pass_origin,pass_motion,minf(time+duration,flight_end))
		var toward_ball := predicted-setter.global_position
		if not is_finite(swing_drive_started) and airborne and time >= pin_arrival-0.42:
			if toward_ball.slide(Vector3.UP).length() <= SWING_REACH and toward_ball.y <= SWING_CONTACT_HEIGHT:
				swing_drive_started = clock
				swing_drive_duration = duration
				swing_hand_speed = 0.0
		var load := smoothstep(0.0,0.14,clock-swing_charge_started)
		var drive := clock-swing_drive_started if is_finite(swing_drive_started) else -INF
		if drive < 0.0:
			var approach_point := flight_point(pass_origin,pass_motion,clampf(maxf(time+0.12,pin_arrival-0.14),0.0,flight_end))
			pose_bow_draw(load,approach_point)
		else:
			var extension := smoothstep(0.0,swing_drive_duration,drive)
			var follow := smoothstep(swing_drive_duration+0.035,swing_drive_duration+0.16,drive)
			pose_bow_draw(load,ball.position,extension,follow)
		var palm := right_palm()
		if airborne and drive > 0.0 and drive <= swing_drive_duration+0.12 and previous_palm.is_finite():
			swing_impact_speed = palm.distance_to(previous_palm)/maxf(delta,0.001)
			swing_hand_speed = maxf(swing_hand_speed,swing_impact_speed)
			var previous_ball := flight_point(pass_origin,pass_motion,previous)
			var fraction := hand_contact_fraction(previous_ball-previous_palm,ball.position-palm)
			if fraction >= 0.0:
				hit_spike(charge,previous_ball.lerp(ball.position,fraction))
				return
		previous_palm = palm
	if time >= flight_end: miss("Spike missed")

func right_palm() -> Vector3:
	var rig: Skeleton3D = setter.skeleton
	var wrist := rig.get_bone_global_pose(rig.find_bone("hand_r")).origin
	var knuckle := rig.get_bone_global_pose(rig.find_bone("middle_01_r")).origin
	return rig.to_global(wrist.lerp(knuckle,0.75))

func hand_contact_fraction(before: Vector3, after: Vector3) -> float:
	var radius := BallPreview.RADIUS+PALM_RADIUS
	var gap := before.length_squared()-radius*radius
	if gap <= 0.0: return 0.0
	var relative := after-before
	var length_squared := relative.length_squared()
	if length_squared <= 0.000001: return -1.0
	var projection := before.dot(relative)
	var discriminant := projection*projection-length_squared*gap
	if discriminant < 0.0: return -1.0
	var entry := (-projection-sqrt(discriminant))/length_squared
	return entry if entry >= 0.0 and entry <= 1.0 else -1.0

func hit_spike(charge: float, point: Vector3) -> void:
	swing_contact = point
	ball.position = point
	swing_power = charge
	pass_origin = swing_contact
	var target := swing_aim-pass_origin
	var speed := clampf(swing_hand_speed*2.2,1.0,32.0)
	var duration := target.slide(Vector3.UP).length()/speed
	pass_motion = target/duration+Vector3.UP*Flight.GRAVITY*duration*0.5
	flight_end = duration
	swing_net_hit = Net.first_hit(func(t): return flight_point(pass_origin,pass_motion,t),0.0,duration)
	stage = Stage.HIT
	stage_start = clock
	region.hide()
	timing_cue.hide()
	status.text = "Spike  |  %d%% power" % roundi(charge*100.0)
	trace.write("spike",clock,{"point":swing_contact,"aim":swing_aim,"velocity":pass_motion,"power":charge,"palm_speed":swing_impact_speed,"peak_palm_speed":swing_hand_speed,"net":not swing_net_hit.is_empty()},true)

func play_spike(time: float) -> void:
	var end := flight_end if swing_net_hit.is_empty() else float(swing_net_hit.end_time)
	if not swing_net_hit.is_empty() and time >= swing_net_hit.time:
		ball.position = Net.after_hit(swing_net_hit,minf(time,end))
		status.text = "Spike hit the net"
	else:
		ball.position = flight_point(pass_origin,pass_motion,minf(time,end))
	if time < SWING_FOLLOW_TIME:
		pose_bow_draw(1.0-smoothstep(0.11,SWING_FOLLOW_TIME,time),swing_contact,1.0,smoothstep(0.0,0.16,time))
	if time >= end+(0.22 if swing_practice else 0.48) and not jump.active: reset_feed()

func pose_bow_draw(weight: float, contact: Vector3, extension := 0.0, follow := 0.0) -> void:
	var rig: Skeleton3D = setter.skeleton
	var author: RefCounted = setter.get_pose_author()
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var correction := hip_correction(contact)*smoothstep(0.05,0.38,setter.position.y-jump.start.y)*weight
	correction *= 1.0-smoothstep(0.0,0.8,follow)
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,correction.x)
	author.rotate_world(pose,"pelvis",Vector3.BACK,correction.y)
	var chest_turn := smoothstep(0.0,0.88,extension)
	var aim := rig.to_local(swing_aim)-rig.to_local(setter.global_position)
	var aim_turn := clampf(atan2(aim.x,aim.z),-0.48,0.48)
	var power := swing_power if stage == Stage.HIT else swing_charge()
	var rotation_weight := weight*torso_rotation_scale*lerpf(0.48,1.22,power)
	var turn := lerpf(-0.57,0.42+aim_turn*0.52,chest_turn)+(0.34+aim_turn*0.38)*follow
	author.rotate_world(pose,"spine_01",Vector3.UP,turn*0.20*rotation_weight)
	author.rotate_world(pose,"spine_02",Vector3.UP,turn*0.34*rotation_weight)
	author.rotate_world(pose,"spine_03",Vector3.UP,turn*0.46*rotation_weight)
	var tuck := clampf(smoothstep(0.08,0.45,setter.position.y-jump.start.y)*weight*(1.0-0.75*follow)*leg_kickback_scale,0.0,1.0)
	if tuck > 0.0:
		for side in ["l","r"]:
			var thigh: String = "thigh_"+side
			var calf: String = "calf_"+side
			var foot: String = "foot_"+side
			var hip: Vector3 = author.point(pose,thigh)
			var knee: Vector3 = author.point(pose,calf)
			var ankle: Vector3 = author.point(pose,foot)
			var outward := 1.0 if side == "l" else -1.0
			var thigh_axis := (knee-hip).normalized().slerp(Vector3(0.18*outward,-1.0,0.16).normalized(),tuck)
			var heel_lift := (0.24 if side == "r" else 0.10)+0.78*maxf(0.0,leg_kickback_scale-1.0)
			var shin_axis := (ankle-knee).normalized().slerp(Vector3(0.07*outward,heel_lift,-1.0).normalized(),tuck)
			author.aim_joint(pose,thigh,calf,hip+thigh_axis)
			knee = author.point(pose,calf)
			author.aim_joint(pose,calf,foot,knee+shin_axis)
	var ball_target := rig.to_local(contact)
	var right_shoulder: Vector3 = author.point(pose,"upperarm_r")
	var reach := ball_target-right_shoulder
	var lean_weight := smoothstep(0.12,0.82,extension)*(1.0-smoothstep(0.0,0.72,follow))*weight
	var pitch := clampf((reach.z-0.18)*0.75,-0.24,0.27)*lean_weight
	var roll := clampf(-reach.x*0.70,-0.23,0.23)*lean_weight
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,pitch*0.62)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,pitch*0.38)
	author.rotate_world(pose,"spine_01",Vector3.BACK,roll*0.62)
	author.rotate_world(pose,"spine_02",Vector3.BACK,roll*0.38)
	right_shoulder = author.point(pose,"upperarm_r")
	var draw_hand := right_shoulder+Vector3(0.04,0.34,-0.15)
	var wrist_target := ball_target-(ball_target-right_shoulder).normalized()*0.06
	var through := right_shoulder+Vector3(0.28,-0.28,0.43)
	var target := draw_hand.lerp(wrist_target,extension).lerp(through,follow)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",
		target,Vector3(-0.85,0.52,-0.74),weight,lerpf(108.0,175.0,extension))
	var left_shoulder: Vector3 = author.point(pose,"upperarm_l")
	var guide_drop := 0.78*smoothstep(0.07,1.0,extension)+0.22*follow
	var guide_hand := left_shoulder+Vector3(0.06,0.43,0.64).lerp(Vector3(0.12,-0.46,0.12),guide_drop)
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",
		guide_hand,Vector3(0.26,-0.55,0.15),weight,lerpf(172.0,148.0,guide_drop))
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

func hip_correction(contact: Vector3) -> Vector2:
	var drift: Vector3 = jump.horizontal_velocity()*0.16
	var reach := setter.to_local(contact-drift)-Vector3(-0.24,0.0,0.28)
	var pitch := clampf(reach.z*0.43,-0.20,0.20)
	var roll := clampf(-reach.x*0.46,-0.22,0.22)
	return Vector2(pitch,roll)

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
