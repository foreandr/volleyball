extends "res://scripts/jump_float_serve.gd"

const SetterJump = preload("res://scripts/setter_jump.gd")

const TOSS_STEP := 0.36
const APPROACH_START := TOSS_STEP+0.36
const SPIN_TAKEOFF := APPROACH_START+0.70
const SPIN_CONTACT := SPIN_TAKEOFF+0.43
const JUMP_HEIGHT := 1.12
const SPIN_LAND := SPIN_TAKEOFF+SetterJump.FULL_AIR_TIME*sqrt(JUMP_HEIGHT/SetterJump.FULL_HEIGHT)*1.09
const APPROACH_SAMPLE_RATE := 120.0

var sidespin := 0.0
var released_sidespin := 0.0
var approach := SetterJump.new()
var approach_positions: PackedVector3Array = []
var approach_sample_origin: Vector3
var approach_poses: Array[Array] = []

func configure(actor: Node3D, start := START, yaw := 0.0) -> void:
	approach.load_lead_arm_clip()
	super.configure(actor,start,yaw)
	apex = 3.70
	update_path_preview()

func contact_time() -> float:
	return SPIN_CONTACT

func toss_release_time() -> float:
	return TOSS_STEP

func takeoff_time() -> float:
	return SPIN_TAKEOFF

func front_start_limit() -> float:
	return -7.70

func recovery_end() -> float:
	return SPIN_LAND+0.11

func can_run_after_contact() -> bool:
	return is_finite(contact_clock) and swing_time >= SPIN_LAND

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
	var rig: Skeleton3D = player.skeleton
	var setup := float_approach(APPROACH_START,SPIN_TAKEOFF,SPIN_LAND,JUMP_HEIGHT,1.17,APPROACH_START,TOSS_STEP)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,setup[bone].basis.get_rotation_quaternion())
	approach.active = false
	approach.load_bend_extra = deg_to_rad(85.0)*0.36
	approach.load_arm_extra = 0.48*0.85
	var intercept := player.position+forward*2.14+Vector3.UP*3.0
	approach.begin(player,Vector2(-forward.x,forward.z),intercept,SPIN_TAKEOFF-APPROACH_START-SetterJump.LEAD_STEP_TIME,JUMP_HEIGHT,3)
	var sample_count := ceili((recovery_end()-APPROACH_START)*APPROACH_SAMPLE_RATE)
	for index in range(sample_count+1):
		if index > 0: approach.step(player,1.0/APPROACH_SAMPLE_RATE,Vector2.ZERO)
		approach_positions.append(player.position)
		var sample: Array[Transform3D] = []
		for bone in rig.get_bone_count(): sample.append(rig.get_bone_pose(bone))
		approach_poses.append(sample)
	player.position = serve_start

func float_step_pose(time: float) -> Array:
	if time < APPROACH_START or approach_poses.is_empty():
		return float_approach(time,SPIN_TAKEOFF,SPIN_LAND,JUMP_HEIGHT,1.17,APPROACH_START,TOSS_STEP)
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
	super.reset()
	ball.rotation = Vector3.ZERO

func spin_toss_ball(previous: float, time: float, rate: float) -> void:
	var air_time := maxf(0.0,time-maxf(previous,TOSS_STEP))/rate
	if air_time > 0.0:
		ball.rotate(Vector3.UP.cross(forward).normalized(),TAU*3.5*air_time)

func toss_palm(pose: Array, _rig: Skeleton3D, author: RefCounted, _time: float) -> Vector3:
	return author.point(pose,"hand_r").lerp(author.point(pose,"middle_01_r"),0.72)

func position_toss_hands(pose: Array, rig: Skeleton3D, author: RefCounted, time: float, weight: float) -> void:
	var rise := smoothstep(0.09,TOSS_STEP,time)
	var scale_: float = rig.global_basis.get_scale().y
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var wrist := shoulder+Vector3(0.07,-0.37+0.61*rise,0.37+0.07*rise)/scale_
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",wrist,Vector3(-0.55,-0.65,0.13),weight)
	orient_palm(pose,rig,author,"r",Vector3.BACK,Vector3.RIGHT,0.72*weight)
	var roll := smoothstep(TOSS_STEP-0.08,TOSS_STEP+0.05,time)
	author.rotate_world(pose,"hand_r",Vector3.RIGHT,deg_to_rad(-20.0)*roll*weight)
	var left_shoulder: Vector3 = author.point(pose,"upperarm_l")
	var off_hand := left_shoulder+Vector3(0.11,-0.51,0.07)/scale_
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",off_hand,Vector3(0.60,-0.20,0.25),weight)

func shape_float_strike(pose: Array, rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var weight := smoothstep(SPIN_TAKEOFF+0.06,SPIN_TAKEOFF+0.23,time)*(1.0-smoothstep(SPIN_CONTACT+0.25,SPIN_LAND+0.09,time))
	if weight <= 0.0: return
	var extension := smoothstep(SPIN_CONTACT-0.17,SPIN_CONTACT,time)
	var follow := smoothstep(SPIN_CONTACT,SPIN_CONTACT+0.29,time)
	var scale_: float = rig.global_basis.get_scale().y
	var tilt := smoothstep(SPIN_TAKEOFF+0.13,SPIN_CONTACT-0.015,time)*(1.0-smoothstep(SPIN_CONTACT+0.04,SPIN_LAND-0.05,time))
	var crunch := smoothstep(SPIN_CONTACT-0.11,SPIN_CONTACT+0.15,time)*(1.0-smoothstep(SPIN_CONTACT+0.20,SPIN_LAND,time))
	author.rotate_world(pose,"spine_01",Vector3.BACK,deg_to_rad(-24.0)*tilt)
	author.rotate_world(pose,"spine_03",Vector3.BACK,deg_to_rad(-10.0)*tilt)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.42*crunch)
	var coil := weight*(1.0-extension)
	author.rotate_world(pose,"spine_03",Vector3.UP,-0.48*coil+0.40*extension*(1.0-0.65*follow))
	var kick := smoothstep(SPIN_TAKEOFF+0.04,SPIN_CONTACT-0.09,time)*(1.0-smoothstep(SPIN_CONTACT,SPIN_CONTACT+0.24,time))
	for side in ["l","r"]:
		var knee: Vector3 = author.point(pose,"calf_"+side)
		var ankle: Vector3 = author.point(pose,"foot_"+side)
		var direction := (ankle-knee).normalized().slerp(Vector3(0.04,-0.35,-1.0).normalized(),kick*(0.54 if side == "r" else 0.35))
		author.aim_joint(pose,"calf_"+side,"foot_"+side,knee+direction)
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var contact := shoulder+Vector3(-0.055,0.67,0.33)/scale_
	var shot_direction := Vector3(0.20*sidespin,0.0,1.0).normalized()
	SpikeArm.apply(pose,author,contact,weight,extension,follow,1.0,0.72,0.84,0.12,0.0,0.0,shot_direction,0.0,0.22/scale_,true)
	var guide_drop := smoothstep(SPIN_CONTACT-0.18,SPIN_CONTACT+0.14,time)
	SpikeArm.apply_guide_arm(pose,author,Vector3(0.08,0.45,0.48)/scale_,Vector3(0.35,-0.55,0.18),guide_drop,weight,166.0)

func finish_float_wrist(pose: Array, _rig: Skeleton3D, author: RefCounted, time: float) -> void:
	var snap := smoothstep(SPIN_CONTACT-0.07,SPIN_CONTACT+0.12,time)*(1.0-smoothstep(SPIN_CONTACT+0.21,SPIN_LAND,time))
	SpikeArm.align_wrist_to_forearm(pose,author,0.82*smoothstep(TOSS_STEP,TOSS_STEP+0.22,time))
	author.rotate_world(pose,"hand_r",Vector3.RIGHT,deg_to_rad(24.0)*snap)

func set_sidespin(value: float) -> void:
	sidespin = value
	update_path_preview()

func preview_lane_count() -> int:
	return 1

func preview_lane_offset(_lane: int, progress: float, launch: Vector3) -> Vector3:
	return spin_offset(progress,launch,sidespin)

func begin_serve_curve() -> void:
	released_sidespin = sidespin

func advance_serve_curve(_time: float) -> void:
	pass

func serve_curve_offset(time: float, duration: float) -> Vector3:
	return spin_offset(clampf(time/maxf(duration,0.001),0.0,1.0),velocity,released_sidespin)

func spin_offset(progress: float, launch: Vector3, curve: float) -> Vector3:
	var side := Vector3.UP.cross(launch.slide(Vector3.UP).normalized())
	var envelope := 4.0*progress*(1.0-progress)
	return -side*curve*1.15*envelope+Vector3.UP*0.44*envelope*progress

func spin_serve_ball(delta: float) -> void:
	var axis := Vector3.UP.cross(velocity.slide(Vector3.UP).normalized())+Vector3.UP*released_sidespin
	ball.rotate(axis.normalized(),TAU*8.0*delta)
