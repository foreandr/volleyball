extends RefCounted

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Court = preload("res://scripts/preview_court.gd")
const LOAD_TIME := 0.24
const APPROACH_LOAD_TIME := 0.36
const FULL_AIR_TIME := 1.02
const LAND_TIME := 0.16
const FULL_HEIGHT := 1.27
const TAP_HEIGHT := 0.18
const AIR_TRAVEL_FRACTION := 0.38
const AIR_STEER_SPEED := 1.00
const AIR_STEER_ACCELERATION := 5.0
var active := false
var load_bend_extra := 0.0
var load_arm_extra := 0.0
var front_limit := 2.5
var elapsed := 0.0
var held := false
var hold_time := 0.0
var max_height := FULL_HEIGHT
var height := FULL_HEIGHT
var air_time := FULL_AIR_TIME
var start: Vector3
var heading: Vector3
var stride := 0.0
var air_velocity := Vector3.ZERO
var air_offset := Vector3.ZERO
const LEAD_STEP_TIME := 0.24
var lead_time := 0.0
var lead_distance := 0.0
var approach_plant := false
var assisted_load_time := APPROACH_LOAD_TIME
var assisted_height := 0.0
var approach_lunge := Vector3.ZERO
var right_foot_start: Vector3
var left_foot_start: Vector3
var right_plant: Vector3
var left_plant: Vector3

func begin(actor: Node3D, input: Vector2, ball_target := Vector3.INF, plant_time := APPROACH_LOAD_TIME, jump_height := 0.0, three_step := false) -> void:
	if active: return
	active = true
	held = true
	hold_time = 0.0
	height = TAP_HEIGHT
	elapsed = 0.0
	air_velocity = Vector3.ZERO
	air_offset = Vector3.ZERO
	start = actor.position
	var travel := Vector3(-input.x,0,input.y)
	stride = 0.17+0.31*travel.length()
	heading = travel.normalized() if not travel.is_zero_approx() else actor.basis.z.normalized()
	approach_lunge = Vector3.ZERO
	approach_plant = ball_target.is_finite()
	assisted_load_time = plant_time
	assisted_height = jump_height
	lead_time = LEAD_STEP_TIME if three_step else 0.0
	lead_distance = 0.0
	if approach_plant:
		var ball_offset := (ball_target-start).slide(Vector3.UP)
		if three_step: lead_distance = clampf(ball_offset.length()-1.12,0.40,0.90)
		stride = minf(0.40,minf(stride,maxf(0.08,ball_offset.length()*0.60)))
		var rig: Skeleton3D = actor.skeleton
		right_foot_start = rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_r")).origin)
		left_foot_start = rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_l")).origin)
		right_plant = right_foot_start+heading*(lead_distance+stride*0.68)
		var toward_ball := (ball_target-right_plant).slide(Vector3.UP).normalized()
		var reach := (ball_target-start-heading*(stride+lead_distance)).slide(Vector3.UP)
		approach_lunge = reach.normalized()*clampf(reach.length()-0.055,0.0,0.95)
		if toward_ball.is_zero_approx(): toward_ball = heading.slide(Vector3.UP).normalized()
		left_plant = right_plant+toward_ball*0.43+Vector3.UP.cross(toward_ball)*0.19
		right_plant.y = minf(right_foot_start.y,left_foot_start.y)
		left_plant.y = right_plant.y
	actor.play_action("idle")

func release() -> void:
	held = false

func horizontal_velocity() -> Vector3:
	return air_velocity+heading*(stride*AIR_TRAVEL_FRACTION/air_time)

func load_duration() -> float:
	return assisted_load_time+lead_time if approach_plant else LOAD_TIME

func flight_duration(jump_height: float, assisted: bool) -> float:
	return FULL_AIR_TIME*sqrt(jump_height/FULL_HEIGHT)*(1.09 if assisted else 1.0)

func step(actor: Node3D, delta: float, input: Vector2) -> void:
	var load_time := load_duration()
	if elapsed < load_time:
		if held: hold_time += minf(delta,load_time-elapsed)
		height = assisted_height if assisted_height > 0.0 else lerpf(TAP_HEIGHT,max_height,clampf(hold_time/LOAD_TIME,0.0,1.0))
		air_time = flight_duration(height,assisted_height > 0.0)
	var previous_flight := clampf(elapsed-load_time,0.0,air_time)
	elapsed += delta
	var air_delta := clampf(elapsed-load_time,0.0,air_time)-previous_flight
	if air_delta > 0.0:
		var steering := Vector3(-input.x,0.0,input.y).limit_length()*AIR_STEER_SPEED
		air_velocity = air_velocity.move_toward(steering,AIR_STEER_ACCELERATION*air_delta)
		air_offset += air_velocity*air_delta
	var flight := clampf((elapsed-load_time)/air_time,0.0,1.0)
	var pose_time := minf(maxf(0.0,elapsed-lead_time),load_time-lead_time)*LOAD_TIME/(load_time-lead_time)+maxf(0.0,elapsed-load_time)
	var first := smoothstep(0.015,0.12,pose_time)
	var second := smoothstep(0.12,0.225,pose_time)
	var lead_progress := smoothstep(0.0,lead_time,elapsed) if lead_time > 0.0 else 0.0
	var distance := lead_distance*lead_progress+stride*(0.34*first+0.66*second+AIR_TRAVEL_FRACTION*flight)
	var base := start+heading*distance+Vector3.UP*(4.0*height*flight*(1.0-flight))
	var lunge := approach_lunge*smoothstep(0.0,0.58,elapsed-load_time)
	var position := base+air_offset+lunge
	actor.position = Court.clamp_setter(position,front_limit)
	if air_delta > 0.0: air_offset += actor.position-position
	actor.animator.advance(delta)
	var landing := elapsed-load_time-air_time
	if landing >= LAND_TIME:
		active = false
		return
	var lead_load := 0.70*smoothstep(0.0,lead_time*0.78,elapsed) if lead_time > 0.0 else 0.0
	var load_in := lerpf(lead_load,1.0,smoothstep(0.02,0.19,pose_time))
	var load := load_in*(1.0-smoothstep(0.19,LOAD_TIME+0.055,pose_time))
	var impact := smoothstep(-0.025,0.04,landing)*(1.0-smoothstep(0.04,LAND_TIME,landing))
	var arm_drive := smoothstep(0.17,0.37,pose_time)*(1.0-smoothstep(LOAD_TIME+air_time*0.56,LOAD_TIME+air_time*0.93,pose_time))
	pose_jump(actor,first,second,load,impact,arm_drive,pose_time,flight,load_in)

func pose_jump(actor: Node3D, first: float, second: float, load: float, impact: float, arm_drive: float, pose_time: float, flight: float, load_in: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var hips: Transform3D = author.world_pose(pose,parent)
	var scale_: float = rig.global_basis.get_scale().y
	pose[pelvis].origin -= hips.basis.inverse()*Vector3.UP*(0.15*load+0.14*impact)/scale_
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,(0.16+load_bend_extra)*load+0.13*impact-0.22*arm_drive)
	var travel := actor.basis.inverse()*heading*stride/scale_
	var stagger := 0.34*(first-second)
	var tuck := sin(PI*flight)
	for side in ["l","r"]:
		var left: bool = side == "l"
		var foot: String = "foot_"+side
		var foot_pose: Transform3D = author.world_pose(original,rig.find_bone(foot))
		var lift := sin(PI*first) if left else sin(PI*second)
		var target := foot_pose.origin+travel*stagger*(1.0 if left else -1.0)+Vector3.UP*(0.085*lift+0.07*tuck)
		if approach_plant and pose_time < LOAD_TIME+0.08:
			var step_progress := smoothstep(0.105,0.21,pose_time) if left else smoothstep(0.015,0.105,pose_time)
			var plant_from := left_foot_start if left else right_foot_start
			if left and lead_time > 0.0:
				var lead_progress := smoothstep(0.0,lead_time*0.82,elapsed)
				plant_from += heading*lead_distance*lead_progress+Vector3.UP*0.055*sin(PI*lead_progress)
			var plant_to := left_plant if left else right_plant
			var planted := plant_from.lerp(plant_to,step_progress)
			planted.y += sin(PI*step_progress)*(0.12 if left else 0.09)
			var release_weight := smoothstep(LOAD_TIME,LOAD_TIME+0.08,pose_time)
			target = rig.to_local(planted).lerp(target,release_weight)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot,target,Vector3(0.09 if left else -0.09,0.25,1.0))
		author.set_world_basis(pose,foot,foot_pose.basis)
		var upper_arm: String = "upperarm_"+side
		var forearm: String = "lowerarm_"+side
		var arm_load := load
		if approach_plant:
			# Carry the plant's backswing into the spike instead of pumping overhead first.
			arm_load = load_in*(1.0-smoothstep(LOAD_TIME,LOAD_TIME+0.17,pose_time))
		var jump_drive := 0.0 if approach_plant else arm_drive
		author.rotate_world(pose,upper_arm,Vector3.RIGHT,(1.52+load_arm_extra)*arm_load)
		author.rotate_world(pose,forearm,Vector3.RIGHT,-0.25*jump_drive)
		var shoulder: Vector3 = author.point(pose,upper_arm)
		var elbow: Vector3 = author.point(pose,forearm)
		if approach_plant and arm_load > 0.0:
			var upper_direction := elbow-shoulder
			var tucked_direction := upper_direction
			tucked_direction.x *= 1.0-0.65*arm_load
			var upper_pose: Transform3D = author.world_pose(pose,rig.find_bone(upper_arm))
			var tuck_rotation := Quaternion(upper_direction.normalized(),tucked_direction.normalized())
			author.set_world_basis(pose,upper_arm,Basis(tuck_rotation)*upper_pose.basis)
			elbow = author.point(pose,forearm)
		var wrist: Vector3 = author.point(pose,"hand_"+side)
		var extension := (0.52+0.20*arm_load if approach_plant else 0.52)*smoothstep(0.02,0.16,(shoulder.z-elbow.z)*scale_)
		if extension > 0.0:
			var forearm_pose: Transform3D = author.world_pose(pose,rig.find_bone(forearm))
			var straighten := Quaternion((wrist-elbow).normalized(),(elbow-shoulder).normalized())
			author.set_world_basis(pose,forearm,Basis(Quaternion.IDENTITY.slerp(straighten,extension))*forearm_pose.basis)
		if jump_drive > 0.0:
			var outward := 1.0 if left else -1.0
			var hand: String = "hand_"+side
			var overhead := shoulder+Vector3(-outward*0.065,0.49,0.16)/scale_
			var raised := pose.duplicate()
			author.limb(raised,upper_arm,forearm,hand,overhead,Vector3(outward*0.50,-0.42,0.52),1.0,151.0)
			for joint in [upper_arm,forearm]:
				var bone := rig.find_bone(joint)
				pose[bone].basis = pose[bone].basis.slerp(raised[bone].basis,jump_drive)
			var base: Transform3D = author.world_pose(pose,rig.find_bone(hand))
			var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
			var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
			var hand_orientation := HandPose.hand_basis(Vector3(-outward*0.24,0.85,0.34),Vector3(-outward*0.72,-0.24,-0.52))
			var rotation := hand_orientation*HandPose.hand_basis(fingers,across).inverse()
			author.set_world_basis(pose,hand,Basis(Quaternion.IDENTITY.slerp(rotation.get_rotation_quaternion(),jump_drive*0.75))*base.basis)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
