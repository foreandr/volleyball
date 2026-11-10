extends RefCounted

const CONTACT_HEIGHT := 1.89
const CONTACT_FORWARD := 0.21
const CONTACT_RADIUS := 0.30

static func contact_center(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var left := rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_l")).origin)
	var right := rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_r")).origin)
	return (left+right)*0.5+Vector3.UP*0.105*actor.scale.y+actor.global_basis.z.normalized()*0.035

static func apply(actor: Node3D, target: Vector3, outgoing: Vector3, extension: float, blend: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var direction := rig.global_basis.orthonormalized().inverse()*outgoing.normalized()
	var twist := clampf(atan2(direction.x,maxf(0.18,direction.z)),-0.80,0.80)
	author.rotate_world(pose,"spine_02",Vector3.UP,twist*(0.20+0.24*extension)*blend)
	author.rotate_world(pose,"spine_03",Vector3.UP,twist*(0.12+0.16*extension)*blend)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,lerpf(-0.12,0.16,extension)*blend)
	var center := rig.to_local(target)
	var overhead := author.point(pose,"Head") as Vector3
	# Present two hands above the forehead, then extend through the outgoing line.
	center.x = clampf(center.x,overhead.x-0.34,overhead.x+0.34)
	center.y = clampf(center.y,overhead.y+0.16,overhead.y+0.40)
	center.z = clampf(center.z,overhead.z-0.04,overhead.z+0.46)
	center += direction*0.22*extension
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var hand: String = "hand_"+side
		var middle: String = "middle_01_"+side
		var wrist := center+Vector3(sign_*0.115,-0.105,-0.035)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,wrist,Vector3(sign_*0.85,-0.42,0.38),blend,164.0)
		var fingers: Vector3 = author.point(pose,hand)+Vector3(-sign_*0.13,0.30,0.16)+direction*0.18*extension
		var bone := rig.find_bone(hand)
		var current: Transform3D = author.world_pose(pose,bone)
		author.aim_joint(pose,hand,middle,fingers)
		var aimed: Transform3D = author.world_pose(pose,bone)
		author.set_world_basis(pose,hand,current.basis.slerp(aimed.basis,blend))
		for digit in ["thumb","index","middle","ring","pinky"]:
			for joint in ["01","02","03"]:
				var finger := rig.find_bone("%s_%s_%s" % [digit,joint,side])
				if finger >= 0:
					pose[finger].basis = pose[finger].basis.slerp(rig.get_bone_rest(finger).basis,blend)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
