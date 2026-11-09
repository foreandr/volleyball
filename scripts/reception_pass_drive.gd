extends RefCounted

static func effort(incoming: Vector3, outgoing: Vector3) -> float:
	var demand := outgoing.length()+0.30*maxf(0.0,(outgoing-incoming).length()-20.0)
	return smoothstep(9.0,28.0,demand)

static func apply(rig: Skeleton3D, author: RefCounted, outgoing: Vector3, power: float, pose_offset: float, struck: bool) -> void:
	if power <= 0.001: return
	var arms := smoothstep(0.0,0.65,power)
	var torso := smoothstep(0.22,0.85,power)
	var legs := smoothstep(0.52,1.0,power)
	var load := clampf(-pose_offset/0.14,0.0,1.0) if not struck else 0.0
	var drive := smoothstep(0.0,0.15,pose_offset)*(1.0-smoothstep(0.20,0.32,pose_offset)) if struck else 0.0
	if load+drive <= 0.001: return
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

	var direction := (rig.global_basis.orthonormalized().inverse()*outgoing).normalized()
	var lift := clampf(direction.y,0.0,1.0)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,torso*(0.12*load+lerpf(0.13,-0.21,lift)*drive))
	author.rotate_world(pose,"spine_03",Vector3.UP,torso*clampf(direction.x,-0.55,0.55)*0.22*drive)
	var chest: Vector3 = author.point(pose,"spine_03")
	var sweep := Vector3(clampf(direction.x,-0.55,0.55)*0.14,lerpf(0.09,0.25,lift),lerpf(0.24,0.16,lift))*arms*drive
	for side in ["l","r"]:
		if absf(rise)>0.001:
			var foot_name: String = "foot_"+side
			var foot: Transform3D = author.world_pose(original,rig.find_bone(foot_name))
			var knee_pole: Vector3 = author.point(original,"calf_"+side)-author.point(original,"thigh_"+side)
			author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,foot.origin,knee_pole)
			author.set_world_basis(pose,foot_name,foot.basis)
		var hand_name: String = "hand_"+side
		var arm_name: String = "upperarm_"+side
		var elbow_name: String = "lowerarm_"+side
		var hand: Transform3D = author.world_pose(original,rig.find_bone(hand_name))
		var target := hand.origin+sweep
		var shoulder: Vector3 = author.point(pose,arm_name)
		# Keep the platform in front of the sternum as the torso and hips drive.
		target.z = maxf(target.z,maxf(chest.z,shoulder.z)+0.23)
		target.y = minf(target.y,maxf(hand.origin.y,chest.y+0.16))
		var sign_ := 1.0 if side == "l" else -1.0
		var original_pole: Vector3 = author.point(original,elbow_name)-author.point(original,arm_name)
		var clear_pole := Vector3(sign_*0.54,-0.28,0.80)
		var pole := original_pole.normalized().lerp(clear_pole,clampf(0.60+drive*0.40,0.0,1.0))
		author.limb(pose,arm_name,elbow_name,hand_name,target,pole,1.0,174.0)
		author.set_world_basis(pose,hand_name,hand.basis)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
