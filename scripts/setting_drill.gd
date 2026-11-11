extends Node3D

const SetterJump = preload("res://scripts/setter_jump.gd")
const Trace = preload("res://scripts/setting_trace.gd")
const StaminaRing = preload("res://scripts/player_stamina_ring.gd")
const Stamina = preload("res://scripts/player_stamina.gd")
const Player = preload("res://scripts/volleyball_player.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const Contact = preload("res://scripts/forearm_contact.gd")
const Dive = preload("res://scripts/forward_reception_dive.gd")
const KneeSlide = preload("res://scripts/side_knee_slide.gd")
const HAND_RING_RADIUS := 0.65
const BumpSetting = preload("res://scripts/bump_setting.gd")
const Net = preload("res://scripts/net_collision.gd")
const BallTimingRing = preload("res://scripts/ball_timing_ring.gd")
const BallPreview = preload("res://scripts/animation_ball_preview.gd")
const RECEIVER_START := Vector3(-1.8,0.04,-2.85)
# Distance and local offset of the serve from the ready platform.
const RECEPTIONS := [
	[1,Vector3(0.42,0,0)],
	[2,Vector3(-0.85,0,0)],
	[1,Vector3(0,0,0.42)],
	[3,Vector3(1.42,0,0)],
	[2,Vector3(0.59,0,0.59)],
	[3,Vector3(0,0,1.42)],
	[1,Vector3(-0.42,0,0)],
	[2,Vector3(0.85,0,0)],
	[3,Vector3(-1.42,0,0)],
]
const SOURCE := Vector3(0.6,2.8,12.3)
const SERVE_TIME := 1.55
const PASS_APEX := 4.0
const SET_HEIGHT := 2.0
const REGION_RADIUS := 0.65
const TARGETS := [Vector3(0.8,SET_HEIGHT,1.15),Vector3(-1.45,SET_HEIGHT,0.3),Vector3(1.85,SET_HEIGHT,0.1),Vector3(-0.3,SET_HEIGHT,1.8),Vector3(4.85,SET_HEIGHT,0.5)]

var receiver: Node3D
var setter: Node3D
var status: Label
var cpu_stamina_ring: MeshInstance3D
var cpu_stamina := Stamina.new()
var ball: MeshInstance3D
var region: MeshInstance3D
var region_style := StandardMaterial3D.new()
var contact: Vector3
var contact_frame: float
var receive_duration: float
var ready_pose: Array[Transform3D]
var clasp: Array[Transform3D]
var slide_pose: Array[Transform3D]
var slide_start: Vector3
var receiver_yaw: float
var receive_offset: Vector3
var receive_tier: int
var receive_side: String
var dive_heading: Vector3
var dive_aim: Vector3
var serve_velocity: Vector3
var pass_velocity: Vector3
var arrival: float
var timing_arrival: float
var landing: float
var clock := 0.0
var rep := 0
var receiving := false
var bump: MeshInstance3D
var bump_enabled := false
var jump := SetterJump.new()
var ready_range: MeshInstance3D
var range_style := StandardMaterial3D.new()
var timing_cue: Node3D
var arm_swing_weight := 0.0
var trace := Trace.new()
var trace_input := Vector2.ZERO
var trace_sprint := false
var torso_lean_degrees := -30.0
var torso_before_lean := {}
var trace_move_scale := 1.0

func configure(player: Node3D, readout: Label, use_bump: bool, build := "") -> void:
	setter = player
	status = readout
	receiver = Player.new()
	receiver.name = "CPUReceiver"
	receiver.player_number = 2
	receiver.team_color = Color("35b59b")
	receiver.position = RECEIVER_START
	var facing: Vector3 = SOURCE-receiver.position
	receiver_yaw = atan2(facing.x,facing.z)
	receiver.rotation.y = receiver_yaw
	add_child(receiver)
	receiver.get_node("DirectionArrows").hide()
	cpu_stamina_ring = StaminaRing.new()
	receiver.add_child(cpu_stamina_ring)
	receiver.play_action("forearm")
	var clip: Animation = receiver.animator.get_animation("custom_forearm/clip")
	contact_frame = float(clip.get_meta("contact_time"))
	receive_duration = clip.length
	receiver.animator.seek(0.0,true)
	ready_pose = snapshot()
	receiver.animator.seek(contact_frame,true)
	clasp = snapshot()
	ball = MeshInstance3D.new()
	ball.mesh = BallPreview.make_ball()
	var ball_style := StandardMaterial3D.new()
	ball_style.vertex_color_use_as_albedo = true
	ball_style.roughness = 0.7
	ball_style.cull_mode = BaseMaterial3D.CULL_DISABLED
	ball.material_override = ball_style
	add_child(ball)
	region = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = REGION_RADIUS-0.045
	ring.outer_radius = REGION_RADIUS
	region.mesh = ring
	region_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	region.material_override = region_style
	region.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(region)
	bump = BumpSetting.new()
	add_child(bump)
	bump.configure(setter,clip)
	bump_enabled = use_bump
	bump.forearm_setting = true
	bump.hand_setting = not use_bump
	ready_range = MeshInstance3D.new()
	var outline := TorusMesh.new()
	outline.inner_radius = 1.965
	outline.outer_radius = 2.0
	ready_range.mesh = outline
	range_style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ready_range.material_override = range_style
	ready_range.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ready_range)
	timing_cue = BallTimingRing.new()
	ready_range.add_child(timing_cue)
	trace.open(build)
	reset_feed()

func update_timing_cue(after_pass := -INF) -> void:
	timing_cue.update_timing(after_pass,timing_arrival,BumpSetting.GREEN_START,BumpSetting.GREEN_END,is_finite(bump.touch_time),BallTimingRing.OUTER_RADIUS if bump_enabled else HAND_RING_RADIUS)

func set_bump_mode(enabled: bool) -> void:
	if bump_enabled == enabled: return
	bump_enabled = enabled
	bump.hand_setting = not enabled
	reset_feed()

func setter_movement_scale() -> float:
	return bump.movement_scale(clock-0.45-SERVE_TIME,timing_arrival,ball.global_position)

func setter_is_diving() -> bool:
	return bump.low_save.active and not bump.low_save.finished(clock-0.45-SERVE_TIME)

func queue_jump(direction: Vector2) -> void:
	if jump.active or setter_is_diving() or (not bump_enabled and is_finite(bump.touch_time) and not is_finite(bump.release_time)): return
	jump.begin(setter,direction)
	trace.write("jump",clock,{"position":setter.position,"direction":jump.heading},true)

func restore_torso_lean(actor: Node3D) -> void:
	if not torso_before_lean.has(actor): return
	var rig: Skeleton3D = actor.skeleton
	var rotations: Dictionary = torso_before_lean[actor]
	for bone in rotations: rig.set_bone_pose_rotation(bone,rotations[bone])
	torso_before_lean.erase(actor)

func apply_torso_lean(actor: Node3D) -> void:
	if is_zero_approx(torso_lean_degrees): return
	var rig: Skeleton3D = actor.skeleton
	var rotations := {}
	for name_ in ["spine_01","spine_02"]:
		var bone := rig.find_bone(name_)
		if bone < 0: continue
		var parent := rig.get_bone_parent(bone)
		var axis := rig.get_bone_global_pose(parent).basis.inverse()*Vector3.RIGHT
		var base := rig.get_bone_pose_rotation(bone)
		rotations[bone] = base
		rig.set_bone_pose_rotation(bone,Quaternion(axis.normalized(),deg_to_rad(torso_lean_degrees)*0.5)*base)
	torso_before_lean[actor] = rotations

func step_jump(delta: float) -> void:
	if jump.active: jump.step(setter,delta,trace_input)
	bump.setter_jumping = jump.active

func can_aim_set() -> bool:
	return true

func court_facing_weight() -> float:
	return 0.0

func set_key() -> int:
	return KEY_Q if bump_enabled else KEY_E

func queue_set() -> void:
	var previous_press: float = bump.pressed_at
	bump.queue_bump(clock-0.45-SERVE_TIME)
	trace.write("q_tap" if bump_enabled else "e_tap",clock,{
		"accepted":previous_press != bump.pressed_at,"press_after_cpu_contact":bump.pressed_at,
		"seconds_to_green_reference":timing_arrival-(clock-0.45-SERVE_TIME),
		"snapshot":trace_snapshot(clock-0.45-SERVE_TIME),
	},true)

func mark_trace() -> bool:
	if trace.file == null: return false
	trace.write("player_marker",clock,{"snapshot":trace_snapshot(clock-0.45-SERVE_TIME),"previous_feed":trace.feed-1,"closest_check":trace.closest_check},true)
	return true

func _exit_tree() -> void:
	trace.close(clock)

func update_ball_ring() -> void:
	ready_range.position = Vector3(ball.position.x,0.058,ball.position.z)
	var radius := HAND_RING_RADIUS if not bump_enabled and clock >= 0.45+SERVE_TIME else BallTimingRing.OUTER_RADIUS
	var outline := ready_range.mesh as TorusMesh
	if not is_equal_approx(outline.outer_radius,radius):
		outline.inner_radius = radius-0.035
		outline.outer_radius = radius
	var distance := (ball.position-setter.position).slide(Vector3.UP).length()
	range_style.albedo_color = Color("6beeb3") if distance <= radius else Color("657f9b")

func apply_setter_arms(phase: float, moving: bool, delta: float) -> void:
	var rig: Skeleton3D = setter.skeleton
	if not bump_enabled:
		var chest := rig.find_bone("spine_01")
		var pitch_axis := (rig.get_bone_global_pose(chest).basis.inverse()*Vector3.RIGHT).normalized()
		rig.set_bone_pose_rotation(chest,rig.get_bone_pose_rotation(chest)*Quaternion(pitch_axis,-0.10))
	var distance := (ball.position-setter.position).slide(Vector3.UP).length()
	var weight := smoothstep(1.85,2.15,distance) if moving else 0.0
	arm_swing_weight = move_toward(arm_swing_weight,weight,delta*7.0)
	if arm_swing_weight <= 0.0: return
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var shoulder := rig.find_bone("upperarm_"+side)
		var elbow := rig.find_bone("lowerarm_"+side)
		var upper: Quaternion = rig.get_bone_pose_rotation(shoulder)
		var lower: Quaternion = rig.get_bone_pose_rotation(elbow)
		var swing := (0.14+sin(TAU*phase)*0.43*sign_)*arm_swing_weight
		var axis: Vector3 = rig.get_bone_global_pose(shoulder).basis.inverse()*Vector3.RIGHT
		rig.set_bone_pose_rotation(shoulder,upper*Quaternion(axis.normalized(),swing))
		axis = rig.get_bone_global_pose(elbow).basis.inverse()*Vector3.RIGHT
		rig.set_bone_pose_rotation(elbow,lower*Quaternion(axis.normalized(),-0.18*arm_swing_weight))


func reset_feed() -> void:
	if trace.feed > 0:
		trace.write("feed_end",clock,{"result":status.text,"closest_check":trace.closest_check},true)
	clock = 0.0
	receiving = false
	bump.reset()
	update_timing_cue()
	var reception: Array = RECEPTIONS[rep % RECEPTIONS.size()]
	receive_tier = reception[0]
	receive_offset = reception[1]
	receive_side = "l" if receive_offset.x >= 0.0 else "r"
	var facing := Basis(Vector3.UP,receiver_yaw)
	dive_heading = facing*receive_offset.normalized()
	dive_aim = RECEIVER_START+facing*receive_offset+Vector3.UP*0.42
	receiver.play_action("forearm")
	receiver.animator.pause()
	pose_receive(0.0)
	contact = platform_contact()
	if is_knee_slide():
		slide_pose = snapshot()
		slide_start = receiver.position
	serve_velocity = (contact-SOURCE)/SERVE_TIME+Vector3.UP*Flight.GRAVITY*SERVE_TIME*0.5
	receiver.position = RECEIVER_START
	receiver.rotation.y = receiver_yaw
	var target: Vector3 = TARGETS[rep % TARGETS.size()]
	var rise := sqrt(2.0*Flight.GRAVITY*(PASS_APEX-contact.y))
	arrival = rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-SET_HEIGHT)/Flight.GRAVITY)
	pass_velocity = (target-contact).slide(Vector3.UP)/arrival+Vector3.UP*rise
	landing = Flight.landing_time(contact,pass_velocity)
	var set_height: float = bump.ready_contact().y-setter.position.y+RECEIVER_START.y
	timing_arrival = rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-set_height-bump.contact_radius())/Flight.GRAVITY)
	var set_arrival := rise/Flight.GRAVITY+sqrt(2.0*(PASS_APEX-set_height)/Flight.GRAVITY)
	var stance_offset := 0.62 if bump_enabled else 0.21
	var stand := flight_point(contact,pass_velocity,set_arrival)+pass_velocity.slide(Vector3.UP).normalized()*stance_offset
	region.position = Vector3(stand.x,0.065,stand.z)
	region_style.albedo_color = Color("49d6ff")
	region.show()
	ball.position = SOURCE
	receiver.play_action("idle")
	status.text = "Serve incoming"
	trace.begin_feed({
		"mode":"bump" if bump_enabled else "hand","cpu_move":receiver_move_name(),
		"cpu_tier":receive_tier,"serve_start":SOURCE,"serve_velocity":serve_velocity,
		"cpu_contact":contact,"cpu_pass_velocity":pass_velocity,
		"setter_region":region.position,"setter_start":setter.position,
		"cpu_contact_clock":0.45+SERVE_TIME,"set_timing_clock":0.45+SERVE_TIME+timing_arrival,
	})

func step(delta: float) -> void:
	var previous := clock-0.45-SERVE_TIME
	clock += delta
	bump.update_aim()
	var elapsed := clock-0.45
	if elapsed < 0.0: return
	var after_pass := elapsed-SERVE_TIME
	var start := -Dive.WINDUP if is_forward_dive() else -contact_frame
	var finish := Dive.DURATION-Dive.WINDUP if is_forward_dive() else receive_duration-contact_frame
	if is_knee_slide(): finish = KneeSlide.DURATION
	if after_pass >= start and after_pass < finish:
		if not receiving:
			receiving = true
			if is_forward_dive(): cpu_stamina.spend(Stamina.DIVE_COST)
			receiver.play_action("forearm")
			receiver.animator.pause()
		pose_receive(after_pass)
		if not is_forward_dive() and not is_knee_slide() and after_pass > 0.0: recover_receiver_arms(after_pass)
	elif receiving:
		receiving = false
		receiver.position = RECEIVER_START
		receiver.rotation.y = receiver_yaw
		receiver.play_action("idle")
	if not receiving or not is_forward_dive(): cpu_stamina.recover(delta)
	cpu_stamina_ring.set_fraction(cpu_stamina.value/100.0)
	if after_pass < 0.0:
		timing_cue.update_timing(elapsed,SERVE_TIME,BallPreview.GREEN_START,BallPreview.GREEN_END)
		ball.position = flight_point(SOURCE,serve_velocity,elapsed)
		sample_trace(after_pass)
		return
	if not region.visible or status.text == "Serve incoming":
		region.show()
		status.text = "Get your platform under the ball" if bump_enabled else "Move under the pass"
	ball.position = flight_point(contact,pass_velocity,minf(after_pass,landing))
	if previous < 0.0:
		trace.write("cpu_contact",clock,{"point":contact,"outgoing_velocity":pass_velocity,"move":receiver_move_name()},true)
	step_bump(after_pass,maxf(0.0,previous),delta)

func step_bump(time: float, previous: float, delta: float) -> void:
	var path := func(t): return flight_point(contact,pass_velocity,minf(t,landing))
	var incoming := pass_velocity+Vector3.DOWN*Flight.GRAVITY*time
	var old_grade: int = bump.grade
	var old_move := setter_move_name()
	bump.update_attempt(time,previous,landing,path,incoming,delta,timing_arrival)
	update_timing_cue(time)
	var reset_at := landing
	if is_finite(bump.touch_time):
		var after_touch: float = time-bump.touch_time
		if not bump_enabled and not is_finite(bump.release_time):
			var caught: Vector3 = bump.touch
			ball.position = caught.lerp(bump.platform_center(),smoothstep(0.0,0.08,after_touch))
			reset_at = INF
		else:
			var launch_time: float = bump.touch_time if bump_enabled else bump.release_time
			var origin: Vector3 = bump.touch if bump_enabled else bump.release_point
			var airborne := time-launch_time
			reset_at = launch_time+bump.floor_time
			if not bump.net_hit.is_empty() and airborne >= bump.net_hit.time:
				ball.position = Net.after_hit(bump.net_hit,airborne)
			else:
				ball.position = flight_point(origin,bump.outgoing,minf(airborne,bump.floor_time))
		status.text = BallTimingRing.result_text(bump.grade,"set")
		if after_touch <= BallTimingRing.RESULT_DURATION: timing_cue.show_result(bump.grade)
	elif bump.grade != BallPreview.Grade.WAITING:
		status.text = BallTimingRing.result_text(bump.grade,"set")
	if not bump_enabled and is_finite(bump.release_time) and previous < bump.release_time:
		trace.write("hand_release",clock,{"position":bump.release_point,"velocity":bump.outgoing,"net":bump.net_hit},true)
	trace.check_contact(bump.contact_check)
	if old_move != setter_move_name():
		trace.write("setter_move",clock,trace_snapshot(time),true)
	if old_grade != bump.grade:
		trace.write("set_result",clock,{
			"snapshot":trace_snapshot(time),"closest_check":trace.closest_check,
			"contact_time":bump.touch_time,"contact_point":bump.touch if is_finite(bump.touch_time) else null,
			"outgoing_velocity":bump.outgoing if is_finite(bump.touch_time) else null,
			"spread":bump.contact_spread if is_finite(bump.touch_time) else null,"net":bump.net_hit,
		},true)
	sample_trace(time)
	if time >= reset_at+0.85:
		rep += 1
		reset_feed()

func receiver_move_name() -> String:
	if is_forward_dive(): return "forward_dive"
	if is_knee_slide(): return "knee_slide"
	return "lunge" if receive_tier == 2 else "step"

func setter_move_name() -> String:
	if bump.low_save.active: return "pancake" if bump.low_save.pancake else "forward_dive"
	if not bump.reach.is_empty(): return "lunge" if bump.reach.tier == 2 else "step"
	if is_finite(bump.pose_started_at): return "hand_set" if not bump_enabled else "standing_bump"
	return "ready"

func sample_trace(time: float) -> void:
	if trace.file == null or clock < trace.next_sample: return
	trace.sample(clock,trace_snapshot(time))

func trace_snapshot(time: float) -> Dictionary:
	var position_: Vector3 = ball.global_position
	var velocity := serve_velocity+Vector3.DOWN*Flight.GRAVITY*maxf(0.0,time+SERVE_TIME)
	var phase := "serve"
	if clock < 0.45:
		phase = "pre_serve"
		velocity = Vector3.ZERO
	if time >= 0.0:
		phase = "cpu_pass"
		velocity = pass_velocity+Vector3.DOWN*Flight.GRAVITY*time if time < landing else Vector3.ZERO
	if is_finite(bump.touch_time):
		var launch_time: float = bump.touch_time if bump_enabled else bump.release_time
		phase = "held_ball"
		velocity = Vector3.ZERO
		if is_finite(launch_time):
			phase = "setter_output"
			var airborne := time-launch_time
			velocity = bump.outgoing+Vector3.DOWN*Flight.GRAVITY*airborne if airborne < bump.floor_time else Vector3.ZERO
			if not bump.net_hit.is_empty() and airborne >= bump.net_hit.time:
				phase = "net_rebound"
				velocity = (Net.after_hit(bump.net_hit,airborne+0.001)-Net.after_hit(bump.net_hit,airborne))/0.001
	var platform: Vector3 = bump.platform_center()
	var cpu_platform := platform_contact()
	return {
		"phase":phase,"ball_position":position_,"ball_velocity":velocity,
		"setter_position":setter.global_position,"setter_yaw":setter.global_rotation.y,
		"receiver_position":receiver.global_position,"receiver_yaw":receiver.global_rotation.y,
		"ball_to_setter":position_.distance_to(setter.global_position),
		"ball_to_setter_horizontal":(position_-setter.global_position).slide(Vector3.UP).length(),
		"ball_to_receiver":position_.distance_to(receiver.global_position),
		"ball_to_receiver_horizontal":(position_-receiver.global_position).slide(Vector3.UP).length(),
		"setter_platform":platform,"ball_to_platform":position_.distance_to(platform),
		"receiver_platform":cpu_platform,"ball_to_receiver_platform":position_.distance_to(cpu_platform),
		"move_input":trace_input,"sprint_requested":trace_sprint,"movement_scale":trace_move_scale,
		"setter_move":setter_move_name(),"jumping":jump.active,"reach_step":bump.reach_step,
		"save_target":bump.low_save.aim if bump.low_save.active else null,
		"save_contact_time":bump.low_save.contact_time if bump.low_save.active else null,
		"aim":bump.destination,"aim_apex":bump.height,"grade":bump.grade,"result":status.text,
		"press_after_cpu_contact":bump.pressed_at,"pose_started":bump.pose_started_at,
		"seconds_to_green_reference":timing_arrival-time,"approach_progress":bump.approach_progress,
		"contact_check":bump.contact_check,
	}

func recover_receiver_arms(time: float) -> void:
	var weight := smoothstep(0.13,0.40,time)
	var rig: Skeleton3D = receiver.skeleton
	for side in ["l","r"]:
		for part in ["clavicle_","upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			if bone >= 0:
				var current := rig.get_bone_pose_rotation(bone)
				rig.set_bone_pose_rotation(bone,current.slerp(ready_pose[bone].basis.get_rotation_quaternion(),weight))

func is_forward_dive() -> bool:
	return receive_tier == 3 and receive_offset.z > 0.0

func is_knee_slide() -> bool:
	return receive_tier == 3 and not is_forward_dive()

func pose_receive(time: float) -> void:
	receiver.rotation.y = receiver_yaw
	if is_forward_dive():
		receiver.pose_reception_dive(ready_pose,clasp,RECEIVER_START,dive_heading,time+Dive.WINDUP,dive_aim,Dive.WINDUP)
		return
	if is_knee_slide() and time > 0.0:
		receiver.pose_reception_knee_slide(slide_pose,ready_pose,slide_start,receive_side,time,{"velocity":pass_velocity,"point":contact,"spread":0.0})
		return
	receiver.animator.seek(clampf(contact_frame+time,0.0,receive_duration),true)
	var tier := mini(receive_tier,2)
	var windup := 0.19 if tier == 2 else 0.15
	var progress := clampf(1.0+time/windup,0.0,1.0)
	var weight := smoothstep(0.0,1.0,progress)*(1.0-smoothstep(0.04,receive_duration-contact_frame,time))
	var side_lunge := tier == 2 and absf(receive_offset.x)>0.1
	var forward_lunge := absf(receive_offset.x)<0.1
	var lead := "r" if forward_lunge and tier == 1 else receive_side
	var stride := 0.68 if side_lunge else 0.48
	if is_knee_slide(): stride += 0.43
	var step := receive_offset.normalized()*stride
	var travel := step*weight
	receiver.position = RECEIVER_START+receiver.basis*travel
	receiver.pose_reception_reach(step,travel,weight,progress,ready_pose,{
		"tier":tier,"back":false,"rear_diagonal":false,"short_straight_back":false,
		"forward_lunge":forward_lunge,"lead":lead,"side_lunge":side_lunge,"height":0.0,
	},is_knee_slide(),0,Vector3.INF)

func snapshot() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for bone in receiver.skeleton.get_bone_count():
		pose.append(receiver.skeleton.get_bone_pose(bone))
	return pose

func platform_contact() -> Vector3:
	var rig: Skeleton3D = receiver.skeleton
	var elbows := []
	var wrists := []
	for side in ["l","r"]:
		elbows.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("lowerarm_"+side)).origin))
		wrists.append(rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin))
	return Contact.surface(elbows,wrists,0.055).ball

func flight_point(origin: Vector3, velocity: Vector3, time: float) -> Vector3:
	return origin+velocity*time-Vector3.UP*0.5*Flight.GRAVITY*time*time
