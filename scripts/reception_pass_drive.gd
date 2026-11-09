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
	var legs := smoothstep(0.52,1.0,power)
	var load := clampf(-pose_offset/0.14,0.0,1.0) if not struck else 0.0
	var drive := smoothstep(0.0,0.15,pose_offset)*(1.0-smoothstep(0.20,0.32,pose_offset)) if struck else 0.0
	var steer := smoothstep(0.0,0.095,pose_offset)*(1.0-smoothstep(0.19,0.32,pose_offset)) if struck else 0.0
	if (load+drive)*power+steer <= 0.001: return
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var rise := legs*(0.115*drive-0.085*load)
	if rise > 0.0:
		for side in ["l","r"]:
			var hip: Vector3 = author.point(original,"thigh_"+side)
			var knee: Vector3 = author.point(original,"calf_"+side)
			var ankle: Vector3 = author.point(original,"foot_"+side)
			var length := hip.distance_to(knee)+knee.distance_to(ankle)-0.006
			var stance := hip-ankle
			var flat := Vector2(stance.x,stance.z).length_squared()
			var available := sqrt(maxf(0.0,length*length-flat))-stance.y
			rise = minf(rise,maxf(0.0,available))
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3.UP*rise

	var to_rig := rig.global_basis.orthonormalized().inverse()
	var direction := (to_rig*outgoing).normalized()
	var impulse := (to_rig*(outgoing-incoming)).normalized()
	var lift := clampf(direction.y,0.0,1.0)
	# Follow the intended pass and account for how much the incoming ball must turn.
	var yaw := clampf(atan2(direction.x,maxf(0.35,direction.z))*0.22+impulse.x*0.22,-0.25,0.25)
	var pitch := clampf((lift-0.60)*0.23+(impulse.y-0.55)*0.15,-0.16,0.16)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,torso*(0.12*load+lerpf(0.13,-0.21,lift)*drive)-pitch*steer)
	author.rotate_world(pose,"spine_02",Vector3.UP,yaw*steer*0.42)
	author.rotate_world(pose,"spine_03",Vector3.UP,yaw*steer*0.58)
	author.rotate_world(pose,"spine_03",Vector3.BACK,-impulse.x*0.12*steer)
	var chest: Vector3 = author.point(pose,"spine_03")
	var sweep := Vector3(clampf(direction.x,-0.55,0.55)*0.14,lerpf(0.09,0.25,lift),lerpf(0.24,0.16,lift))*arms*drive
	for side in ["l","r"]:
		if absf(rise)>0.001:
			var foot_name: String = "foot_"+side
			var foot: Transform3D = author.world_pose(original,rig.find_bone(foot_name))
			var knee_pole: Vector3 = author.point(original,"calf_"+side)-author.point(original,"thigh_"+side)
			author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,foot.origin,knee_pole)
			author.set_world_basis(pose,foot_name,foot.basis)
	var hand_center: Vector3 = (author.point(original,"hand_l")+author.point(original,"hand_r"))*0.5
	var aim_sweep := Vector3(yaw*0.32,pitch*0.64,0.025)*steer
	var target := hand_center+sweep+aim_sweep
	target.z = maxf(target.z,chest.z+0.25)
	target.y = minf(target.y,maxf(hand_center.y,chest.y+0.16))
	PlatformPose.connect_arms(pose,author,target,clampf((load+drive)*1.7*arms+steer*0.65,0.0,1.0),0.0)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
