extends RefCounted

const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const WINDUP := 0.40
const DURATION := 1.28

# Time from load, hip drop and body pitch, from the side-view reference.
const KEYS := [
	[0.00,0.00,0.0],
	[0.14,0.15,18.0],
	[0.28,0.31,49.0],
	[0.40,0.47,73.0],
	[0.55,0.49,82.0],
	[0.72,0.49,82.0],
	[0.92,0.42,59.0],
	[1.10,0.24,28.0],
	[1.28,0.00,0.0],
]

static func sample(actor: Node3D, author: RefCounted, ready: Array[Transform3D], start: Vector3, heading: Vector3, time: float, ball_point: Vector3) -> void:
	var rig: Skeleton3D = actor.skeleton
	var travel := 1.58*smoothstep(0.08,0.60,time)
	var drop := 0.0
	var pitch := 0.0
	for index in range(1,KEYS.size()):
		var a: Array = KEYS[index-1]
		var b: Array = KEYS[index]
		if time > b[0] and index < KEYS.size()-1: continue
		var weight := smoothstep(a[0],b[0],time)
		drop = lerpf(a[1],b[1],weight)
		pitch = deg_to_rad(lerpf(a[2],b[2],weight))
		break
	actor.position = start+heading*travel
	actor.rotation.y = atan2(heading.x,heading.z)
	var pose := ready.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var scale_: float = rig.global_basis.get_scale().y
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop/scale_
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,pitch)
	author.rotate_world(pose,"Head",Vector3.RIGHT,-pitch*0.32)
	var launch := smoothstep(0.12,0.42,time)
	var get_up := smoothstep(0.73,DURATION,time)
	var brace := smoothstep(0.40,0.55,time)*(1.0-smoothstep(0.86,1.18,time))
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = author.world_pose(ready,rig.find_bone(foot_name))
		var trail := foot.origin-Vector3.BACK*(0.63 if side == "l" else 0.78)
		var kick := smoothstep(0.18,0.46,time)*(1.0-smoothstep(0.49,0.72,time))
		trail.y += kick*(0.44 if side == "l" else 0.14)
		var ankle := (foot.origin-Vector3.BACK*minf(travel,0.32)).lerp(trail,launch).lerp(foot.origin,get_up)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,ankle,Vector3(0.20 if side == "l" else -0.20,0.1,1.0))
		author.set_world_basis(pose,foot_name,foot.basis)
	var grip: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var reach := smoothstep(0.11,0.31,time)*(1.0-smoothstep(0.41,0.54,time))
	if reach > 0.0:
		var target := rig.global_transform.affine_inverse()*ball_point+Vector3(0,-0.07,0.18)
		target.y = maxf(0.13,target.y)
		PlatformPose.connect_arms(pose,author,grip.lerp(target,reach),reach,0.0)
	if brace > 0.0:
		for side in ["l","r"]:
			var hand: String = "hand_"+side
			var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
			var palm := Vector3(shoulder.x+(0.13 if side == "l" else -0.13),0.10,shoulder.z+0.30)
			author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,palm,Vector3(0.8 if side == "l" else -0.8,0.4,-0.25),brace)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
