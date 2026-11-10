extends RefCounted

const CONTACT_HEIGHT := 1.83
const CONTACT_FORWARD := 0.23
const CONTACT_RADIUS := 0.42
const GREEN_CONTACT_ALLOWANCE := 0.17
const HOLD_TIME := 0.58

static func contact_center(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var center := Vector3.ZERO
	for side in ["l","r"]:
		center += rig.get_bone_global_pose(rig.find_bone("index_03_"+side)).origin
		center += rig.get_bone_global_pose(rig.find_bone("thumb_03_"+side)).origin
	return rig.to_global(center*0.25+Vector3(0,0.075,0.07))

static func apply(actor: Node3D, target: Vector3, blend: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,-0.18)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.075)
	var target_local := rig.to_local(target)
	var head: Vector3 = author.point(pose,"Head")
	var offset := target_local-head
	var side_lean := clampf(offset.x/0.48,-1.0,1.0)
	var forward_lean := clampf((offset.z-0.24)/0.42,-1.0,1.0)
	author.rotate_world(pose,"spine_01",Vector3.BACK,-side_lean*0.17)
	author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.13)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,forward_lean*0.19)
	head = author.point(pose,"Head")
	var aim := target_local-head
	var diamond := head+Vector3(clampf(aim.x,-0.22,0.22),clampf(aim.y-0.075,0.12,0.27),clampf(aim.z-0.07,0.09,0.35))
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var hand: String = "hand_"+side
		var wrist := diamond+Vector3(sign_*0.14,-0.08,-0.015)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,wrist,Vector3(sign_*0.9,-0.55,0.25),1.0,152.0)
		for digit in ["thumb","index","middle","ring","pinky"]:
			for joint in ["01","02","03"]:
				var finger := rig.find_bone("%s_%s_%s" % [digit,joint,side])
				if finger >= 0: pose[finger].basis = rig.get_bone_rest(finger).basis
		var hand_bone := rig.find_bone(hand)
		var base: Transform3D = author.world_pose(pose,hand_bone)
		var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var target_fingers := Vector3(-sign_*0.52,0.82,0.23)
		var target_across := Vector3(-sign_*0.68,-0.38,0.63)
		author.set_world_basis(pose,hand,hand_basis(target_fingers,target_across)*hand_basis(fingers,across).inverse()*base.basis)
		shape_digit(author,pose,"index",side,diamond+Vector3(sign_*0.018,0.065,0.025))
		shape_digit(author,pose,"thumb",side,diamond+Vector3(sign_*0.016,-0.047,0.045))
	for bone in rig.get_bone_count():
		var before: Basis = original[bone].basis
		rig.set_bone_pose_rotation(bone,before.slerp(pose[bone].basis,blend).get_rotation_quaternion())

static func shape_digit(author: RefCounted, pose: Array, digit: String, side: String, tip: Vector3) -> void:
	var first := "%s_01_%s" % [digit,side]
	var second := "%s_02_%s" % [digit,side]
	var third := "%s_03_%s" % [digit,side]
	author.limb(pose,first,second,third,tip,Vector3(0,0,1),1.0,166.0)

static func hand_basis(fingers: Vector3, across: Vector3) -> Basis:
	var axis := fingers.normalized()
	var side := across.slide(axis).normalized()
	return Basis(axis,side,axis.cross(side))
