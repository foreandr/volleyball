extends "res://scripts/jump_float_serve.gd"

const MatchAttack = preload("res://scripts/match_attack.gd")
const SetterJump = preload("res://scripts/setter_jump.gd")

const TOSS_STEP := 0.42
const APPROACH_START := TOSS_STEP+0.36
const SPIN_TAKEOFF := APPROACH_START+0.56
const SPIN_CONTACT := SPIN_TAKEOFF+0.55
const JUMP_HEIGHT := 1.12
const MAX_SERVE_SPEED := 1.55
const APPROACH_SAMPLE_RATE := 120.0
const SPIKE_APPROACH_STEPS := 3
const SPIKE_GLIDE := 0.27

var sidespin := 0.0
var serve_speed := MAX_SERVE_SPEED
var jump_height := JUMP_HEIGHT
var jump_carry_enabled := true
var active_jump_height := JUMP_HEIGHT
var active_jump_carry := true
const DEFAULT_FORWARD_LEAN := -15.0
var forward_lean_degrees := DEFAULT_FORWARD_LEAN
var active_forward_lean_degrees := 0.0
var released_sidespin := 0.0
var released_lift := 0.0
var approach := SetterJump.new()
var spike_pose_driver := MatchAttack.new()
var approach_positions: PackedVector3Array = []
var approach_sample_origin: Vector3
var approach_sample_forward: Vector3
var approach_poses: Array[Array] = []

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	approach.load_lead_arm_clip()
	super.configure(actor,start,yaw)
	apex = 3.70
	update_path_preview()

func _exit_tree() -> void:
	spike_pose_driver.free()

func contact_time() -> float:
	return SPIN_CONTACT

func toss_release_time() -> float:
	return TOSS_STEP

func takeoff_time() -> float:
	return SPIN_TAKEOFF

func front_start_limit() -> float:
	return -7.70

func jump_landing_time() -> float:
	return SPIN_TAKEOFF+approach.flight_duration(active_jump_height,true)

func recovery_end() -> float:
	return jump_landing_time()+0.11

func can_run_after_contact() -> bool:
	return is_finite(contact_clock) and swing_time >= jump_landing_time()

func float_body_scale() -> float:
	return 1.62

func uses_float_arm_pose() -> bool:
	return false

func prepare_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := 1.0-smoothstep(TOSS_STEP,TOSS_STEP+0.21,time)
	if weight > 0.0: position_toss_hands(pose,rig,author,time,weight)

func prepare_serve_reset() -> void:
	if not approach_poses.is_empty(): return
	approach_sample_origin = serve_start
	approach_sample_forward = forward
	var rig: Skeleton3D = player.skeleton
	var setup := float_approach(APPROACH_START,SPIN_TAKEOFF,jump_landing_time(),active_jump_height,1.17,APPROACH_START,TOSS_STEP)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,setup[bone].basis.get_rotation_quaternion())
	approach.active = false
	approach.back_limit = serve_start.z
	approach.load_bend_extra = deg_to_rad(85.0)*0.36
	approach.load_arm_extra = 0.48*0.85
	var intercept := player.position+forward*2.14+Vector3.UP*3.0
	approach.begin(player,Vector2(-forward.x,forward.z),intercept,SPIN_TAKEOFF-APPROACH_START-SetterJump.LEAD_STEP_TIME,active_jump_height,SPIKE_APPROACH_STEPS,false,1.0,false,SPIKE_GLIDE)
	if active_jump_carry: approach.approach_lunge += forward*maxf(0.0,active_jump_height-0.75)*0.90
	approach.approach_lunge -= forward*SERVE_CONTACT_LEAD
	prepare_spike_driver()
	var sample_count := ceili((recovery_end()-APPROACH_START)*APPROACH_SAMPLE_RATE)
	for index in range(sample_count+1):
		if index > 0: approach.step(player,1.0/APPROACH_SAMPLE_RATE,Vector2.ZERO)
		var time := APPROACH_START+index/APPROACH_SAMPLE_RATE
		if time <= SPIN_TAKEOFF:
			spike_pose_driver.lift_arms_during_plant()
		else:
			sample_spike_swing(time)
		approach_positions.append(player.position)
		var sample: Array[Transform3D] = []
		for bone in rig.get_bone_count(): sample.append(rig.get_bone_pose(bone))
		approach_poses.append(sample)
	player.position = serve_start

func float_step_pose(time: float) -> Array:
	if time < APPROACH_START or approach_poses.is_empty():
		var pose := float_approach(time,SPIN_TAKEOFF,jump_landing_time(),active_jump_height,1.17,APPROACH_START,TOSS_STEP)
		var load_weight := smoothstep(0.04,0.29,time)*(1.0-smoothstep(TOSS_STEP,APPROACH_START,time))
		if load_weight <= 0.0: return pose
		var rig: Skeleton3D = player.skeleton
		var author: RefCounted = player.get_pose_author()
		var foot_targets: Array[Vector3] = []
		for side in ["l","r"]:
			foot_targets.append(rig.to_global(author.point(pose,"foot_"+side)))
		player.position += (forward*0.065+Vector3.DOWN*0.055)*load_weight
		for index in 2:
			var side := "l" if index == 0 else "r"
			author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,rig.to_local(foot_targets[index]),
				Vector3(0.12 if index == 0 else -0.12,0.2,1.0))
		return pose
	var frame := minf((time-APPROACH_START)*APPROACH_SAMPLE_RATE,approach_poses.size()-1)
	var index := floori(frame)
	var next := mini(index+1,approach_poses.size()-1)
	var weight := frame-index
	player.position = serve_start-approach_sample_origin+approach_positions[index].lerp(approach_positions[next],weight)
	var pose: Array[Transform3D] = []
	var rig: Skeleton3D = player.skeleton
	for bone in rig.get_bone_count():
		var sample: Transform3D = approach_poses[index][bone]
		pose.append(sample.interpolate_with(approach_poses[next][bone],weight))
		rig.set_bone_pose_position(bone,pose[bone].origin)
	return pose

func toss_curve_height() -> float:
	var air_time := SPIN_CONTACT-TOSS_STEP
	return Flight.GRAVITY*air_time*air_time/8.0

func serve_swing_rate(_launch_speed: float) -> float:
	return 1.0

func reset() -> void:
	if active_jump_height != jump_height or active_jump_carry != jump_carry_enabled or active_forward_lean_degrees != forward_lean_degrees or approach_sample_forward != forward:
		approach_poses.clear()
		approach_positions.clear()
	active_forward_lean_degrees = forward_lean_degrees
	active_jump_height = jump_height
	active_jump_carry = jump_carry_enabled
	super.reset()
	ball.rotation = Vector3.ZERO

func spin_toss_ball(previous: float, time: float, rate: float) -> void:
	var air_time := maxf(0.0,time-maxf(previous,TOSS_STEP))/rate
	if air_time > 0.0:
		ball.rotate(Vector3.UP.cross(forward).normalized(),TAU*3.5*air_time)

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	var wrist: Vector3 = author.point(pose,"hand_r")
	var knuckles: Vector3 = author.point(pose,"middle_01_r")
	return wrist.lerp(knuckles,0.68)

func position_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float, weight: float) -> void:
	var draw := smoothstep(0.0,0.16,time)*(1.0-smoothstep(0.16,TOSS_STEP,time))
	var rise := pow(clampf(inverse_lerp(0.15,TOSS_STEP,time),0.0,1.0),1.65)
	var scale_: float = rig.global_basis.y.length()
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var left_shoulder: Vector3 = author.point(pose,"upperarm_l")
	var outside := (shoulder-left_shoulder).slide(Vector3.UP).normalized()
	var wrist := shoulder+(Vector3(0.0,-0.39+0.63*rise,0.43+0.04*rise-0.45*draw)+outside*(0.13+0.28*draw))/scale_
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",wrist,Vector3(-0.32,-1.0,0.0),weight,155.0,true)
	var forearm: Vector3 = (author.point(pose,"hand_r")-author.point(pose,"lowerarm_r")).normalized()
	var fingers := Vector3(forearm.x,clampf(forearm.y,-0.15,0.26),forearm.z).normalized()
	orient_palm(pose,rig,author,"r",fingers,Vector3.UP.cross(fingers),weight)
	var off_hand := left_shoulder+Vector3(0.11,-0.51,0.07)/scale_
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",off_hand,Vector3(0.60,-0.20,0.25),weight)

func prepare_spike_driver() -> void:
	spike_pose_driver.setter = player
	spike_pose_driver.jump = approach
	spike_pose_driver.swing_practice = false
	spike_pose_driver.approach_steps = SPIKE_APPROACH_STEPS
	spike_pose_driver.force_contact_tilt = true
	spike_pose_driver.torso_forward_bias_degrees = active_forward_lean_degrees
	spike_pose_driver.swing_started = SPIN_TAKEOFF
	spike_pose_driver.swing_charge_started = SPIN_TAKEOFF
	spike_pose_driver.swing_drive_started = -INF
	spike_pose_driver.swing_drive_duration = 0.18
	spike_pose_driver.swing_power = 1.0
	spike_pose_driver.swing_contact = Vector3.INF
	spike_pose_driver.approach_pressed_at = APPROACH_START
	spike_pose_driver.approach_set_touched_at = APPROACH_START
	spike_pose_driver.approach_expected_hit_at = SPIN_CONTACT
	spike_pose_driver.swing_aim = serve_start+forward*18.0
	spike_pose_driver.swing_contact_aim = spike_pose_driver.swing_aim
	spike_pose_driver.plant_arm_lift_started = false
	spike_pose_driver.swing_palm_roll = 0.0
	spike_pose_driver.approach_arm_transition.clear()
	spike_pose_driver.approach_render_rotations.clear()
	spike_pose_driver.swing_finish_pose.clear()
	spike_pose_driver.finish_hand_axis = Vector3.ZERO
	spike_pose_driver.finish_hand_turn = INF

func sample_spike_swing(time: float) -> void:
	var age := maxf(0.0,time-SPIN_CONTACT)
	var weight := 1.0-smoothstep(0.19,0.44,age)
	if weight <= 0.0: return
	var rig: Skeleton3D = player.skeleton
	var drive_start := SPIN_CONTACT-spike_pose_driver.swing_drive_duration
	var drive := clampf((time-drive_start)/spike_pose_driver.swing_drive_duration,0.0,1.0)
	var extension := spike_pose_driver.smootherstep(0.08,1.0,drive)
	var follow := 1.0-(1.0-clampf(age/0.19,0.0,1.0))**2
	var shoulder := rig.get_bone_global_pose(rig.find_bone("upperarm_r")).origin
	var reach := Vector3(-0.05,0.67,0.33+SERVE_CONTACT_LEAD)/rig.global_basis.y.length()
	var contact := to_local(rig.to_global(shoulder+reach))
	spike_pose_driver.clock = time
	spike_pose_driver.stage_start = SPIN_CONTACT
	spike_pose_driver.stage = MatchAttack.Stage.HIT if age > 0.0 else MatchAttack.Stage.SET
	spike_pose_driver.swing_drive_started = drive_start if time >= drive_start else -INF
	if age > 0.0 and not spike_pose_driver.swing_contact.is_finite():
		spike_pose_driver.approach_arm_transition.assign(approach_poses.back())
		spike_pose_driver.swing_contact = contact
	if age > 0.0: contact = spike_pose_driver.swing_contact
	var lift := spike_pose_driver.smootherstep(0.08,0.26,time-SPIN_TAKEOFF)
	spike_pose_driver.pose_bow_draw(1.0/APPROACH_SAMPLE_RATE,weight,contact,extension,follow,1.0,lift,self)
	if age <= 0.0:
		spike_pose_driver.finish_hand_axis = spike_pose_driver.strike_hand_axis(rig)
		spike_pose_driver.finish_hand_edge = spike_pose_driver.strike_hand_edge(rig,spike_pose_driver.finish_hand_axis)

func finish_float_wrist(pose: Array, _rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := smoothstep(TOSS_STEP,TOSS_STEP+0.22,time)*(1.0-smoothstep(TOSS_STEP+0.22,APPROACH_START,time))
	SpikeArm.align_wrist_to_forearm(pose,author,0.82*weight)

func set_forward_lean(value: float) -> void:
	forward_lean_degrees = value
	if elapsed < 0.0 and not running: reset()

func set_serve_speed(value: float) -> void:
	serve_speed = value
	update_path_preview()

func set_jump_height(value: float) -> void:
	jump_height = value
	if elapsed < 0.0 and not running: reset()

func set_jump_carry(enabled: bool) -> void:
	jump_carry_enabled = enabled
	if elapsed < 0.0 and not running: reset()

func set_sidespin(value: float) -> void:
	sidespin = value
	update_path_preview()

func preview_lane_count() -> int:
	return 1

func flight_duration(start: Vector3) -> float:
	return super.flight_duration(start)*0.65/serve_speed

func launch_velocity(start: Vector3, duration: float) -> Vector3:
	return (target-start)/duration+Vector3.UP*(0.5*Flight.GRAVITY*duration)

func preview_lane_offset(_lane: int, progress: float, launch: Vector3) -> Vector3:
	var duration := flight_duration(preview_origin)
	return spin_offset(progress,launch,sidespin,spin_lift(preview_origin,launch,duration,sidespin))

func begin_serve_curve() -> void:
	released_sidespin = sidespin
	released_lift = spin_lift(origin,velocity,planned_duration,released_sidespin)

func advance_serve_curve(_time: float) -> void:
	pass

func serve_curve_offset(time: float, duration: float) -> Vector3:
	return spin_offset(clampf(time/maxf(duration,0.001),0.0,1.0),velocity,released_sidespin,released_lift)

func spin_offset(progress: float, launch: Vector3, curve: float, lift: float) -> Vector3:
	var side := Vector3.UP.cross(launch.slide(Vector3.UP).normalized())
	var envelope := 4.0*progress*(1.0-progress)
	return -side*curve*1.15*envelope+Vector3.UP*lift*envelope*(0.55+0.45*progress)

func spin_lift(start: Vector3, launch: Vector3, duration: float, curve: float) -> float:
	var near := 0.0
	var far := 1.0
	for iteration in 10:
		var progress := (near+far)*0.5
		var point := start+launch*(duration*progress)+spin_offset(progress,launch,curve,0.0)
		if point.z < Net.NET_Z: near = progress
		else: far = progress
	var crossing := (near+far)*0.5
	var time := duration*crossing
	var height := start.y+launch.y*time-0.5*Flight.GRAVITY*time*time
	var shape := 4.0*crossing*(1.0-crossing)*(0.55+0.45*crossing)
	return maxf(0.0,(Net.NET_TOP+BallPreview.RADIUS+0.18-height)/maxf(shape,0.02))

func reception_spin_rps() -> float:
	return 8.0*Vector2(1.0,released_sidespin).length()

func reception_spin_vector() -> Vector3:
	return (Vector3.UP.cross(velocity.slide(Vector3.UP).normalized())+Vector3.UP*released_sidespin)*8.0

func spin_serve_ball(delta: float) -> void:
	var rotation_rate := reception_spin_vector()
	ball.rotate(rotation_rate.normalized(),TAU*rotation_rate.length()*delta)
