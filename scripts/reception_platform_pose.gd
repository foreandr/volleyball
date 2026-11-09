extends RefCounted

const HAND_GAP := 0.065
const ELBOW_ANGLE := 168.0

static func connect_arms(pose: Array, author: RefCounted, desired: Vector3, weight: float, shoulder_advance := 0.022, forward := Vector3.BACK) -> void:
	if weight <= 0.001: return
	var rig: Skeleton3D = author.rig
	var original := pose.duplicate()
	if shoulder_advance > 0.0:
		for side in ["l","r"]:
			var arm: String = "upperarm_"+side
			var shoulder: Vector3 = author.point(pose,arm)
			author.aim_joint(pose,"clavicle_"+side,arm,shoulder+Vector3.BACK*shoulder_advance*weight)
	var left: Vector3 = author.point(pose,"upperarm_l")
	var right: Vector3 = author.point(pose,"upperarm_r")
	var left_hand := Vector3.UP.cross(forward)*HAND_GAP*0.5
	var right_hand := -left_hand
	# Solve one wrist center that both arms can reach at the same extension.
	var a := left-left_hand
	var b := right-right_hand
	var span := a.distance_to(b)
	if span <= 0.001: return
	var axis := (b-a)/span
	var left_range := arm_range(pose,author,"l")
	var right_range := arm_range(pose,author,"r")
	var along := (left_range*left_range-right_range*right_range+span*span)/(2.0*span)
	var center := a+axis*along
	var radius := sqrt(maxf(0.0,left_range*left_range-along*along))
	desired += forward*maxf(0.0,0.24-(desired-center).dot(forward))
	var aim := (desired-center).slide(axis).normalized()
	var grip := center+aim*radius
	for side in ["l","r"]:
		var arm: String = "upperarm_"+side
		var elbow: String = "lowerarm_"+side
		var hand: String = "hand_"+side
		var old_hand: Transform3D = author.world_pose(original,rig.find_bone(hand))
		var target := grip+(left_hand if side == "l" else right_hand)
		var pole := Vector3.UP.cross(forward)*(-0.62 if side == "l" else 0.62)+Vector3.DOWN*0.24+forward*0.46
		var upper_before: Transform3D = author.world_pose(pose,rig.find_bone(arm))
		var lower_before: Transform3D = author.world_pose(pose,rig.find_bone(elbow))
		var wrist_before: Vector3 = author.point(pose,hand)
		author.limb(pose,arm,elbow,hand,old_hand.origin.lerp(target,weight),pole,1.0,174.0)
		var elbow_after: Vector3 = author.point(pose,elbow)
		var wrist_after: Vector3 = author.point(pose,hand)
		# Retain the rig's authored axial twist. The IK bend plane can flip it through the shirt.
		var upper_swing := Quaternion((lower_before.origin-upper_before.origin).normalized(),(elbow_after-upper_before.origin).normalized())
		var lower_swing := Quaternion((wrist_before-lower_before.origin).normalized(),(wrist_after-elbow_after).normalized())
		author.set_world_basis(pose,arm,Basis(upper_swing)*upper_before.basis)
		author.set_world_basis(pose,elbow,Basis(lower_swing)*lower_before.basis)
	# Carry the authored clasp through a shared rotation instead of twisting each hand.
	var turn := Quaternion(platform_axis(original,author),platform_axis(pose,author))
	for side in ["l","r"]:
		var hand: String = "hand_"+side
		var old_hand: Transform3D = author.world_pose(original,rig.find_bone(hand))
		author.set_world_basis(pose,hand,Basis(turn)*old_hand.basis)

static func platform_axis(pose: Array, author: RefCounted) -> Vector3:
	var wrists: Vector3 = author.point(pose,"hand_l")+author.point(pose,"hand_r")
	var elbows: Vector3 = author.point(pose,"lowerarm_l")+author.point(pose,"lowerarm_r")
	return (wrists-elbows).normalized()

static func arm_range(pose: Array, author: RefCounted, side: String) -> float:
	var shoulder: Vector3 = author.point(pose,"upperarm_"+side)
	var elbow: Vector3 = author.point(pose,"lowerarm_"+side)
	var wrist: Vector3 = author.point(pose,"hand_"+side)
	var upper := shoulder.distance_to(elbow)
	var lower := elbow.distance_to(wrist)
	return sqrt(upper*upper+lower*lower-2.0*upper*lower*cos(deg_to_rad(ELBOW_ANGLE)))
