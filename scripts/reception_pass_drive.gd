extends RefCounted

const Flight = preload("res://scripts/pass_flight.gd")
const PlatformPose = preload("res://scripts/reception_platform_pose.gd")

static func swing_effort(origin: Vector3, outgoing: Vector3) -> float:
	var duration := Flight.landing_time(origin,outgoing)
	var distance := outgoing.slide(Vector3.UP).length()*duration
	var rise := pow(maxf(0.0,outgoing.y),2)/(2.0*Flight.GRAVITY)
	return clampf(0.12+0.62*smoothstep(4.0,20.0,distance)+0.26*smoothstep(1.0,6.0,rise),0.0,1.0)

static func effort(incoming: Vector3, outgoing: Vector3) -> float:
	var demand := outgoing.length()+0.30*maxf(0.0,(outgoing-incoming).length()-20.0)
	return smoothstep(9.0,28.0,demand)

static func apply(rig: Skeleton3D, author: RefCounted, outgoing: Vector3, power: float, pose_offset: float, struck: bool, incoming := Vector3.ZERO, swing := -1.0) -> void:
	var arms := swing if swing >= 0.0 else smoothstep(0.0,0.65,power)
	var torso := smoothstep(0.22,0.85,power)
	var load := clampf(-pose_offset/0.14,0.0,1.0) if not struck else 0.0
	var drive := smoothstep(0.0,0.15,pose_offset)*(1.0-smoothstep(0.18,0.39,pose_offset)) if struck else 0.0
	var steer := smoothstep(0.0,0.095,pose_offset)*(1.0-smoothstep(0.17,0.39,pose_offset)) if struck else 0.0
	if (load+drive)*power+steer <= 0.001: return
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	var to_rig := rig.global_basis.orthonormalized().inverse()
	var direction := (to_rig*outgoing).normalized()
	var impulse := (to_rig*(outgoing-incoming)).normalized()
	var lift := clampf(direction.y,0.0,1.0)
	# Follow the intended pass and account for how much the incoming ball must turn.
	var flat := direction.slide(Vector3.UP).normalized()
	var rear := smoothstep(0.05,0.85,-flat.z)
	var yaw := clampf(flat.x*0.70+impulse.x*0.12,-0.72,0.72)
	# For a straight back bump, open around the staggered stance even with no lateral aim.
	var stance: Vector3=author.point(original,"foot_l")-author.point(original,"foot_r")
	var pivot_sign := 1.0 if stance.z>=0.0 else -1.0
	if absf(flat.x)>0.08: pivot_sign=signf(flat.x)
	var hip_turn := lerpf(yaw*0.38,pivot_sign*deg_to_rad(29.),rear)*steer
	author.rotate_world(pose,"pelvis",Vector3.UP,hip_turn)
	if absf(hip_turn)>0.0001:
		for side in ["l","r"]:
			var thigh: String="thigh_"+side
			var calf: String="calf_"+side
			var foot: String="foot_"+side
			var planted: Transform3D=author.world_pose(original,rig.find_bone(foot))
			var pole: Vector3=author.point(original,calf)-author.point(original,thigh)
			author.limb(pose,thigh,calf,foot,planted.origin,pole,1.,180.,true)
			author.set_world_basis(pose,foot,planted.basis)
	var pitch := clampf((lift-0.60)*0.23+(impulse.y-0.55)*0.15,-0.16,0.16)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,torso*(0.12*load+lerpf(0.13,-0.21,lift)*drive)-(pitch+rear*0.23)*steer)
	author.rotate_world(pose,"spine_02",Vector3.UP,yaw*steer*0.32)
	author.rotate_world(pose,"spine_03",Vector3.UP,yaw*steer*0.48)
	author.rotate_world(pose,"spine_03",Vector3.BACK,-impulse.x*0.12*steer)
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,-rear*0.16*steer)
	var chest: Vector3 = author.point(pose,"spine_03")
	var hand_center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var sweep := Vector3(flat.x*0.30,0.18+0.20*lift+0.32*rear,flat.z*0.23)
	var target := hand_center+sweep*arms*drive
	target.y = minf(target.y,chest.y+lerpf(0.32,0.55,rear))
	# Keep the joined wrists lined up with the turning shoulders.
	var across: Vector3=(author.point(pose,"upperarm_l")-author.point(pose,"upperarm_r")).normalized()
	var lateral := across.rotated(Vector3.UP,yaw*steer*0.16)
	var elbow_angle := PlatformPose.ELBOW_ANGLE-lerpf(8.,20.,rear)*drive*lerpf(.65,1.,arms)
	PlatformPose.connect_arms(pose,author,target,clampf((load+drive)*1.7*arms+steer*0.65,0.0,1.0),0.0,lateral,false,false,elbow_angle)
	for name_ in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r","spine_02","spine_03","upperarm_l","upperarm_r","lowerarm_l","lowerarm_r","hand_l","hand_r"]:
		var bone := rig.find_bone(name_)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

const FAST_DIG_ELBOW_DURATION := 0.32

static func apply_fast_dig_elbow_bend(rig: Skeleton3D, age: float, degrees := 50., struck_side := "") -> void:
	var recoil := deg_to_rad(degrees)*smoothstep(0.,.045,age)*(1.-smoothstep(.075,FAST_DIG_ELBOW_DURATION,age))
	if recoil<=0.: return
	var chest := rig.get_bone_global_pose(rig.find_bone("spine_03")).origin
	for side in ["l","r"]:
		if struck_side!="" and side!=struck_side: continue
		var bone := rig.find_bone("lowerarm_"+side)
		var parent := rig.get_bone_parent(bone)
		var elbow := rig.get_bone_global_pose(bone).origin
		var upper := (elbow-rig.get_bone_global_pose(parent).origin).normalized()
		var wrist := rig.get_bone_global_pose(rig.find_bone("hand_"+side)).origin
		var forearm := (wrist-elbow).normalized()
		var hinge := upper.cross(forearm)
		if hinge.length_squared()<.0001: hinge=forearm.cross(chest-wrist)
		if hinge.is_zero_approx(): continue
		var bend := minf(recoil,maxf(0.,deg_to_rad(100.)-upper.angle_to(forearm)))
		var parent_basis := rig.get_bone_global_pose(parent).basis.orthonormalized()
		var rotation := Quaternion((parent_basis.inverse()*hinge).normalized(),bend)
		rig.set_bone_pose_rotation(bone,(rotation*rig.get_bone_pose_rotation(bone)).normalized())

static func absorb_with_joined_platform(actor: Node3D, age: float, degrees: float) -> void:
	var recoil := smoothstep(0.,.045,age)*(1.-smoothstep(.09,FAST_DIG_ELBOW_DURATION,age))
	var release := 1.-smoothstep(.17,FAST_DIG_ELBOW_DURATION,age)
	pose_joined_platform(actor,release,174.-degrees*recoil)

static func pose_joined_platform(actor: Node3D, weight: float, extension: float) -> void:
	var rig: Skeleton3D=actor.skeleton
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=[]
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var center: Vector3=(author.point(pose,"hand_l")+author.point(pose,"hand_r"))*.5
	var across: Vector3=(author.point(pose,"upperarm_l")-author.point(pose,"upperarm_r")).normalized()
	PlatformPose.connect_arms(pose,author,center,weight,0.,across,false,false,extension)
	for side in ["l","r"]:
		for part in ["upperarm_","lowerarm_","hand_"]:
			var bone := rig.find_bone(part+side)
			rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
