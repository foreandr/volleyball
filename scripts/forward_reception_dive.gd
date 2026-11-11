extends RefCounted

const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const WINDUP := 0.33
const LEG_KICK_OFFSET := -0.15
const LEG_LOWER_DURATION := 0.42
const CONTACT_POSE_TIME := 0.40
const POSE_DURATION := 1.28
const GET_UP_EXTENSION := 0.14
const DURATION := POSE_DURATION-CONTACT_POSE_TIME+WINDUP+GET_UP_EXTENSION

# Time from load, hip drop and body pitch, from the side-view reference.
const KEYS := [
	[0.00,0.00,0.0],
	[0.14,0.12,11.0],
	[0.28,0.22,48.0],
	[0.40,0.37,80.0],
	[0.55,0.46,84.0],
	[0.72,0.46,84.0],
	[0.92,0.42,59.0],
	[1.10,0.24,28.0],
	[1.28,0.00,0.0],
]

static func sample(actor: Node3D, author: RefCounted, ready: Array[Transform3D], clasp: Array[Transform3D], start: Vector3, heading: Vector3, time: float, ball_point: Vector3, release_time: float, pancake := false, travel_scale := 1.0, track_platform := false, wide_arm := "", slide_heading := Vector3.ZERO) -> void:
	var kick_time := time-WINDUP-LEG_KICK_OFFSET
	var kick := smoothstep(0.0,0.13,kick_time)*(1.0-smoothstep(0.22,0.22+LEG_LOWER_DURATION,kick_time))
	# Start later while preserving the reach at the intended ball contact.
	time = time*CONTACT_POSE_TIME/WINDUP if time < WINDUP else time-WINDUP+CONTACT_POSE_TIME
	time -= GET_UP_EXTENSION*smoothstep(0.82,POSE_DURATION+GET_UP_EXTENSION,time)
	var rig: Skeleton3D = actor.skeleton
	var brace_start := maxf(0.41,release_time-WINDUP+CONTACT_POSE_TIME)
	var since_brace := time-brace_start
	var slide := 0.42*smoothstep(0.14,0.52,since_brace)
	var travel := 0.23*smoothstep(0.02,0.20,time)+1.35*smoothstep(0.16,0.61,time)+slide
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
	if pancake:
		travel += 0.70*smoothstep(0.13,0.39,time)
	else:
		# Stay in the lunge through the pass, then let the chest tip into the slide.
		var lunge := smoothstep(0.16,0.39,time)*(1.0-smoothstep(0.0,0.15,since_brace))
		pitch -= deg_to_rad(29.0)*lunge
		drop += 0.09*lunge
		if track_platform:
			drop -= 0.065*smoothstep(0.14,0.31,time)*(1.0-smoothstep(0.40,0.60,time))
	travel *= travel_scale
	actor.position = start+(heading if wide_arm.is_empty() or slide_heading.is_zero_approx() else slide_heading)*travel
	var facing_yaw := atan2(heading.x,heading.z)
	if not wide_arm.is_empty() and not slide_heading.is_zero_approx():
		var ball_yaw := atan2(slide_heading.x,slide_heading.z)
		var turn := clampf(angle_difference(facing_yaw,ball_yaw)*0.55,-deg_to_rad(52.0),deg_to_rad(52.0))
		facing_yaw += turn*smoothstep(0.04,0.33,time)
	actor.rotation.y = facing_yaw
	var pose := ready.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var scale_: float = rig.global_basis.get_scale().y
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop/scale_
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,pitch)
	var extension := smoothstep(0.19,0.39,time)
	if not pancake:
		extension = smoothstep(-0.025,0.13,since_brace)
		kick *= extension
	var landing := smoothstep(0.0,0.14,since_brace)
	if pancake:
		var low := smoothstep(0.23,0.40,time)*(1.0-smoothstep(0.82,POSE_DURATION,time))
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.18*low)
		author.rotate_world(pose,"neck_01",Vector3.RIGHT,-0.38*low)
	var chest_settle := landing*(1.0-smoothstep(0.38,0.55,since_brace))
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*0.07*chest_settle/scale_
	var get_up := smoothstep(0.82,POSE_DURATION,time)
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,-0.22*extension*(1.0-get_up))
	author.rotate_world(pose,"neck_01",Vector3.RIGHT,-0.24*extension*(1.0-get_up)-0.36*chest_settle)
	author.rotate_world(pose,"Head",Vector3.RIGHT,-pitch*0.24)
	var head: Vector3 = author.point(pose,"Head")
	var head_lift := maxf(0.0,0.24-0.02*chest_settle-(rig.global_transform*head).y)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3.UP*head_lift/scale_
	var brace := landing*(1.0-smoothstep(0.49,0.77,since_brace))
	var push := smoothstep(0.14,0.40,since_brace)
	var release_hands := smoothstep(0.34,0.47,since_brace)*(1.0-smoothstep(0.47,0.65,since_brace))
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = author.world_pose(ready,rig.find_bone(foot_name))
		var ankle := foot.origin-Vector3.BACK*travel/scale_
		if side == "r":
			var plant := smoothstep(0.015,0.15,time)
			ankle.z += (0.42 if pancake else 0.66)*plant
			ankle.y += 0.09*sin(PI*plant)
		var trail := foot.origin-Vector3.BACK*(0.69 if side == "l" else 0.81)
		trail.x = foot.origin.x*0.48
		trail.y += kick*(0.60 if side == "l" else 0.52)
		trail.z += kick*0.20
		ankle = ankle.lerp(trail,extension).lerp(foot.origin,get_up)
		var lateral := 0.09 if side == "l" else -0.09
		var calf: String = "calf_"+side
		var pole := Vector3(lateral,0.18,1.0).lerp(Vector3(lateral,-0.75,0.10),kick)
		author.limb(pose,"thigh_"+side,calf,foot_name,ankle,pole)
		var ready_shin: Vector3 = foot.origin-author.point(ready,calf)
		var posed_shin: Vector3 = author.point(pose,foot_name)-author.point(pose,calf)
		var ankle_swing := Quaternion(ready_shin.normalized(),posed_shin.normalized())
		var toe_rotation := Quaternion.IDENTITY.slerp(ankle_swing,extension*(1.0-get_up))
		author.set_world_basis(pose,foot_name,Basis(toe_rotation)*foot.basis)
	var grip: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var reach := smoothstep(0.11,0.31,time)
	if not pancake:
		reach = smoothstep(0.06,0.25,time)
	reach *= 1.0-smoothstep(0.0,0.13,since_brace)
	if pancake and reach > 0.0:
		var target := rig.global_transform.affine_inverse()*Vector3(ball_point.x,0.06,ball_point.z)-Vector3.BACK*0.095
		author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,Vector3(-0.30,-0.55,0.10),reach,174.0)
		flatten_palm(pose,author,rig,reach)
	elif not wide_arm.is_empty() and reach > 0.0:
		var side := 1.0 if wide_arm == "l" else -1.0
		var lift := smoothstep(0.0,0.12,since_brace)
		var target := rig.to_local(ball_point)+Vector3(0,-0.09+0.31*lift,0)
		author.limb(pose,"upperarm_"+wide_arm,"lowerarm_"+wide_arm,"hand_"+wide_arm,target,
			Vector3(side*0.85,-0.32,0.16),reach,172.0)
	elif reach > 0.0:
		var bias := Vector3.ZERO if track_platform else Vector3(0,-0.14,0.18)
		var target := rig.global_transform.affine_inverse()*ball_point+bias
		var head_height: float = author.point(pose,"Head").y
		if not pancake:
			var shoulder_height: float = (author.point(pose,"upperarm_l").y+author.point(pose,"upperarm_r").y)*0.5
			head_height = minf(head_height-(0.09 if track_platform else 0.17),shoulder_height-(0.04 if track_platform else 0.12))
		target.y = clampf(target.y,0.13,maxf(0.13,head_height))
		PlatformPose.connect_arms(pose,author,grip.lerp(target,reach),reach,0.0)
		var turn := Quaternion(PlatformPose.platform_axis(clasp,author),PlatformPose.platform_axis(pose,author))
		for side in ["l","r"]:
			var wrist: String = "hand_"+side
			var bone := rig.find_bone(wrist)
			var current: Transform3D = author.world_pose(pose,bone)
			var reference: Transform3D = author.world_pose(clasp,bone)
			author.set_world_basis(pose,wrist,current.basis.slerp(Basis(turn)*reference.basis,reach))
		for bone in rig.get_bone_count():
			var name_ := str(rig.get_bone_name(bone))
			if name_.begins_with("thumb") or name_.begins_with("index") or name_.begins_with("middle") or name_.begins_with("ring") or name_.begins_with("pinky"):
				pose[bone].basis = pose[bone].basis.slerp(clasp[bone].basis,reach)
	if brace > 0.0:
		for side in ["l","r"]:
			var hand: String = "hand_"+side
			var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
			# The palms travel back relative to the shoulders as the body slides past them.
			var palm := Vector3(shoulder.x+(0.13 if side == "l" else -0.13),0.10+0.09*release_hands,shoulder.z+lerpf(0.19,-0.38,push))
			author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,palm,Vector3(0.8 if side == "l" else -0.8,0.4,-0.25),brace)
	if pancake:
		for side in ["l","r"]:
			var hand: String = "hand_"+side
			var wrist: Vector3 = author.point(pose,hand)
			var height: float = (rig.global_transform*wrist).y
			if height < 0.055:
				wrist.y += (0.055-height)/scale_
				author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,wrist,Vector3(0.65 if side == "l" else -0.65,0.4,-0.25))
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

static func flatten_palm(pose: Array, author: RefCounted, rig: Skeleton3D, weight: float) -> void:
	var wrist := rig.find_bone("hand_r")
	var fingers := rig.find_bone("middle_01_r")
	var index := rig.find_bone("index_01_r")
	var pinky := rig.find_bone("pinky_01_r")
	if mini(fingers,mini(index,pinky)) < 0: return
	var hand: Transform3D = author.world_pose(pose,wrist)
	var forward: Vector3 = (author.point(pose,"middle_01_r")-hand.origin).normalized()
	var across: Vector3 = (author.point(pose,"index_01_r")-author.point(pose,"pinky_01_r")).slide(forward).normalized()
	var palm := Basis(across,forward.cross(across),forward)
	author.set_world_basis(pose,"hand_r",hand.basis.slerp(palm.inverse()*hand.basis,weight))
