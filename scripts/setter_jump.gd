extends RefCounted

const HandPose = preload("res://scripts/hand_setting_pose.gd")
const Court = preload("res://scripts/preview_court.gd")
const LOAD_TIME := 0.24
const FULL_AIR_TIME := 0.91
const LAND_TIME := 0.16
const FULL_HEIGHT := 1.016
const TAP_HEIGHT := 0.18
const AIR_STEER_SPEED := 1.00
const AIR_STEER_ACCELERATION := 5.0
var active := false
var elapsed := 0.0
var held := false
var hold_time := 0.0
var height := FULL_HEIGHT
var air_time := FULL_AIR_TIME
var start: Vector3
var heading: Vector3
var stride := 0.0
var air_velocity := Vector3.ZERO
var air_offset := Vector3.ZERO

func begin(actor: Node3D, input: Vector2) -> void:
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
	actor.play_action("idle")

func release() -> void:
	held = false

func step(actor: Node3D, delta: float, input: Vector2) -> void:
	if elapsed < LOAD_TIME:
		if held: hold_time += minf(delta,LOAD_TIME-elapsed)
		height = lerpf(TAP_HEIGHT,FULL_HEIGHT,clampf(hold_time/LOAD_TIME,0.0,1.0))
		air_time = FULL_AIR_TIME*sqrt(height/FULL_HEIGHT)
	var previous_flight := clampf(elapsed-LOAD_TIME,0.0,air_time)
	elapsed += delta
	var air_delta := clampf(elapsed-LOAD_TIME,0.0,air_time)-previous_flight
	if air_delta > 0.0:
		var steering := Vector3(-input.x,0.0,input.y).limit_length()*AIR_STEER_SPEED
		air_velocity = air_velocity.move_toward(steering,AIR_STEER_ACCELERATION*air_delta)
		air_offset += air_velocity*air_delta
	var flight := clampf((elapsed-LOAD_TIME)/air_time,0.0,1.0)
	var first := smoothstep(0.015,0.12,elapsed)
	var second := smoothstep(0.12,0.225,elapsed)
	var distance := stride*(0.34*first+0.66*second+0.38*flight)
	var base := start+heading*distance+Vector3.UP*(4.0*height*flight*(1.0-flight))
	var position := base+air_offset
	actor.position = Court.clamp_setter(position)
	if air_delta > 0.0: air_offset += actor.position-position
	actor.animator.advance(delta)
	var landing := elapsed-LOAD_TIME-air_time
	if landing >= LAND_TIME:
		active = false
		return
	var load := smoothstep(0.02,0.19,elapsed)*(1.0-smoothstep(0.19,LOAD_TIME+0.055,elapsed))
	var impact := smoothstep(-0.025,0.04,landing)*(1.0-smoothstep(0.04,LAND_TIME,landing))
	var arm_drive := smoothstep(0.17,0.37,elapsed)*(1.0-smoothstep(LOAD_TIME+air_time*0.56,LOAD_TIME+air_time*0.93,elapsed))
	pose_jump(actor,first,second,load,impact,arm_drive)

func pose_jump(actor: Node3D, first: float, second: float, load: float, impact: float, arm_drive: float) -> void:
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
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.16*load+0.13*impact-0.22*arm_drive)
	var travel := actor.basis.inverse()*heading*stride/scale_
	var stagger := 0.34*(first-second)
	var tuck := sin(PI*clampf((elapsed-LOAD_TIME)/air_time,0.0,1.0))
	for side in ["l","r"]:
		var left: bool = side == "l"
		var foot: String = "foot_"+side
		var foot_pose: Transform3D = author.world_pose(original,rig.find_bone(foot))
		var lift := sin(PI*first) if left else sin(PI*second)
		var target := foot_pose.origin+travel*stagger*(1.0 if left else -1.0)+Vector3.UP*(0.085*lift+0.07*tuck)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot,target,Vector3(0.09 if left else -0.09,0.25,1.0))
		author.set_world_basis(pose,foot,foot_pose.basis)
		var upper_arm: String = "upperarm_"+side
		var forearm: String = "lowerarm_"+side
		author.rotate_world(pose,upper_arm,Vector3.RIGHT,1.52*load)
		author.rotate_world(pose,forearm,Vector3.RIGHT,-0.25*arm_drive)
		var shoulder: Vector3 = author.point(pose,upper_arm)
		var elbow: Vector3 = author.point(pose,forearm)
		var wrist: Vector3 = author.point(pose,"hand_"+side)
		var extension := 0.52*smoothstep(0.02,0.16,(shoulder.z-elbow.z)*scale_)
		if extension > 0.0:
			var forearm_pose: Transform3D = author.world_pose(pose,rig.find_bone(forearm))
			var straighten := Quaternion((wrist-elbow).normalized(),(elbow-shoulder).normalized())
			author.set_world_basis(pose,forearm,Basis(Quaternion.IDENTITY.slerp(straighten,extension))*forearm_pose.basis)
		if arm_drive > 0.0:
			var outward := 1.0 if left else -1.0
			var hand: String = "hand_"+side
			var overhead := shoulder+Vector3(-outward*0.065,0.49,0.16)/scale_
			author.limb(pose,upper_arm,forearm,hand,overhead,Vector3(outward*0.50,-0.42,0.52),arm_drive,151.0)
			var base: Transform3D = author.world_pose(pose,rig.find_bone(hand))
			var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
			var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
			var hand_orientation := HandPose.hand_basis(Vector3(-outward*0.24,0.85,0.34),Vector3(-outward*0.72,-0.24,-0.52))
			var rotation := hand_orientation*HandPose.hand_basis(fingers,across).inverse()
			author.set_world_basis(pose,hand,Basis(Quaternion.IDENTITY.slerp(rotation.get_rotation_quaternion(),arm_drive*0.75))*base.basis)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
