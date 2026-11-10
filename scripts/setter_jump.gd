extends RefCounted

const Court = preload("res://scripts/preview_court.gd")
const LOAD_TIME := 0.24
const AIR_TIME := 0.91
const LAND_TIME := 0.16
const HEIGHT := 1.016
var active := false
var elapsed := 0.0
var start: Vector3
var heading: Vector3
var stride := 0.0

func begin(actor: Node3D, input: Vector2) -> void:
	if active: return
	active = true
	elapsed = 0.0
	start = actor.position
	var travel := Vector3(-input.x,0,input.y)
	stride = 0.17+0.31*travel.length()
	heading = travel.normalized() if not travel.is_zero_approx() else actor.basis.z.normalized()
	actor.play_action("idle")

func step(actor: Node3D, delta: float) -> void:
	elapsed += delta
	var flight := clampf((elapsed-LOAD_TIME)/AIR_TIME,0.0,1.0)
	var first := smoothstep(0.015,0.12,elapsed)
	var second := smoothstep(0.12,0.225,elapsed)
	var distance := stride*(0.34*first+0.66*second+0.38*flight)
	actor.position = Court.clamp_setter(start+heading*distance+Vector3.UP*(4.0*HEIGHT*flight*(1.0-flight)))
	actor.animator.advance(delta)
	var landing := elapsed-LOAD_TIME-AIR_TIME
	if landing >= LAND_TIME:
		active = false
		return
	var load := smoothstep(0.02,0.19,elapsed)*(1.0-smoothstep(0.19,LOAD_TIME+0.055,elapsed))
	var impact := smoothstep(-0.025,0.04,landing)*(1.0-smoothstep(0.04,LAND_TIME,landing))
	var arm_drive := smoothstep(0.17,0.34,elapsed)*(1.0-smoothstep(0.40,LOAD_TIME+AIR_TIME,elapsed))
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
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.16*load+0.13*impact-0.10*arm_drive)
	var travel := actor.basis.inverse()*heading*stride/scale_
	var stagger := 0.34*(first-second)
	var tuck := sin(PI*clampf((elapsed-LOAD_TIME)/AIR_TIME,0.0,1.0))
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
		author.rotate_world(pose,upper_arm,Vector3.RIGHT,1.52*load-0.95*arm_drive)
		author.rotate_world(pose,forearm,Vector3.RIGHT,-0.25*arm_drive)
		var shoulder: Vector3 = author.point(pose,upper_arm)
		var elbow: Vector3 = author.point(pose,forearm)
		var wrist: Vector3 = author.point(pose,"hand_"+side)
		var extension := 0.52*smoothstep(0.02,0.16,(shoulder.z-elbow.z)*scale_)
		if extension > 0.0:
			var forearm_pose: Transform3D = author.world_pose(pose,rig.find_bone(forearm))
			var straighten := Quaternion((wrist-elbow).normalized(),(elbow-shoulder).normalized())
			author.set_world_basis(pose,forearm,Basis(Quaternion.IDENTITY.slerp(straighten,extension))*forearm_pose.basis)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
