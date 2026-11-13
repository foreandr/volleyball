extends RefCounted

const CONTACT_HEIGHT := 1.83
const CONTACT_FORWARD := 0.23
const CONTACT_RADIUS := 0.40
const GREEN_CONTACT_ALLOWANCE := 0.17
const RELEASE_TIME := 0.125

static func contact_center(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var center := Vector3.ZERO
	for side in ["l","r"]:
		center += rig.get_bone_global_pose(rig.find_bone("index_03_"+side)).origin
		center += rig.get_bone_global_pose(rig.find_bone("thumb_03_"+side)).origin
	return rig.to_global(center*0.25+Vector3(0,0.075,0.07))

static func apply(actor: Node3D, target: Vector3, blend: float, push := Vector3.ZERO, cushion := 0.0, torso_follow := 0.0, face_save := false, ball_direction := Vector3.ZERO, set_extension := -1.0) -> void:
	if blend <= 0.0: return
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	var original := pose.duplicate()
	var lean_weight := 0.0 if face_save else blend
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,-0.18*lean_weight)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.075*lean_weight)
	var target_local := rig.to_local(target)
	var head: Vector3 = author.point(pose,"Head")
	var offset := target_local-head
	var side_lean := clampf(offset.x/0.48,-1.0,1.0)
	var forward_lean := clampf((offset.z-0.24)/0.42,-1.0,1.0)
	author.rotate_world(pose,"spine_01",Vector3.BACK,-side_lean*0.17*lean_weight)
	author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.13*lean_weight)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,forward_lean*0.19*lean_weight)
	head = author.point(pose,"Head")
	var aim := target_local-head
	var diamond := head+Vector3(clampf(aim.x,-0.28 if face_save else -0.22,0.28 if face_save else 0.22),clampf(aim.y-0.075,-0.10 if face_save else 0.12,0.20 if face_save else 0.27),clampf(aim.z-0.07,0.16 if face_save else 0.09,0.35))
	var local_push := rig.global_basis.inverse()*push
	var horizontal_push := local_push.slide(Vector3.UP)
	var backset := smoothstep(0.0,0.65,-horizontal_push.normalized().z)
	if set_extension > 0.0 and backset > 0.0:
		var arch := deg_to_rad(12.0)*backset*smoothstep(0.0,1.0,set_extension)*blend
		author.rotate_world(pose,"spine_01",Vector3.RIGHT,-arch*0.45)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,-arch*0.55)
	var turn := 0.0
	torso_follow *= blend
	if torso_follow > 0.0 and horizontal_push.length_squared() > 0.0001:
		var set_yaw := atan2(horizontal_push.x,horizontal_push.z)
		var facing := PI if horizontal_push.z < -absf(horizontal_push.x) else 0.0
		turn = clampf(angle_difference(facing,set_yaw),-0.82,0.82)*torso_follow
		author.rotate_world(pose,"spine_02",Vector3.UP,turn*0.42)
		author.rotate_world(pose,"spine_03",Vector3.UP,turn*0.58)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,clampf(local_push.z,-0.17,0.17)*0.55*torso_follow)
	diamond += local_push-Vector3.UP*0.055*cushion
	var elbow_limit := lerpf(152.0,176.0,clampf(push.length()/0.24,0.0,1.0))-12.0*cushion
	if set_extension >= 0.0:
		elbow_limit = lerpf(143.0,178.0,set_extension)-8.0*cushion
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		var hand: String = "hand_"+side
		var wrist := diamond+Vector3(sign_*0.14,-0.08,-0.015).rotated(Vector3.UP,turn*0.65)
		var upper: String = "upperarm_"+side
		var lower: String = "lowerarm_"+side
		var pole := Vector3(sign_*0.9,-0.55,0.30)
		if not face_save and blend < 1.0:
			var shoulder: Vector3 = author.point(pose,upper)
			var elbow: Vector3 = author.point(pose,lower)
			var start: Vector3 = author.point(pose,hand)
			var start_pole := (elbow-shoulder).slide((start-shoulder).normalized())
			pole = start_pole.normalized().slerp(pole.normalized(),smoothstep(0.0,0.46,blend))
			# Lead with the hands through the space in front of the chest.
			wrist = start.lerp(wrist,blend)+Vector3.BACK*sin(PI*blend)*0.16/rig.global_basis.y.length()
		if set_extension > 0.0 and not local_push.is_zero_approx():
			var shoulder: Vector3 = author.point(pose,upper)
			var elbow: Vector3 = author.point(pose,lower)
			var hand_point: Vector3 = author.point(pose,hand)
			var length := shoulder.distance_to(elbow)+elbow.distance_to(hand_point)
			var aim_weight := smoothstep(0.0,1.0,set_extension)
			var direction := (wrist-shoulder).normalized().slerp(local_push.normalized(),lerpf(0.65,0.96,backset)*aim_weight)
			wrist = shoulder+direction*lerpf(wrist.distance_to(shoulder),length*0.997,aim_weight)
		author.limb(pose,upper,lower,hand,wrist,pole,1.0,elbow_limit)
		for digit in ["thumb","index","middle","ring","pinky"]:
			for joint in ["01","02","03"]:
				var finger := rig.find_bone("%s_%s_%s" % [digit,joint,side])
				if finger >= 0: pose[finger].basis = rig.get_bone_rest(finger).basis
		var hand_bone := rig.find_bone(hand)
		var base: Transform3D = author.world_pose(pose,hand_bone)
		var fingers: Vector3 = author.point(pose,"middle_01_"+side)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)
		var target_fingers := Vector3(-sign_*0.52,0.82,0.23)
		var follow := smoothstep(0.04,0.20,push.length())
		target_fingers = target_fingers.lerp(local_push.normalized(),0.46*follow)
		# Index side stays inward and back so the pinky edge cups forward.
		var target_across := Vector3(-sign_*0.72,-0.30,-0.54)
		if face_save and not ball_direction.is_zero_approx():
			var incoming := (rig.global_basis.inverse()*ball_direction).normalized()
			var palm_normal := Vector3(clampf(incoming.x,-0.45,0.45),clampf(incoming.y,-0.18,0.40),maxf(0.55,incoming.z)).normalized()
			target_fingers = target_fingers.slide(palm_normal).normalized()
			target_across = palm_normal.cross(target_fingers)*sign_
		author.set_world_basis(pose,hand,hand_basis(target_fingers,target_across)*hand_basis(fingers,across).inverse()*base.basis)
		shape_digit(author,pose,"index",side,diamond+Vector3(sign_*0.018,0.065,0.025))
		shape_digit(author,pose,"thumb",side,diamond+Vector3(sign_*0.016,-0.047,0.045))
		shape_outer_fingers(author,pose,side,diamond+Vector3(0,0.075,0.07))
	for bone in rig.get_bone_count():
		var before: Quaternion = original[bone].basis.orthonormalized().get_rotation_quaternion().normalized()
		var after: Quaternion = pose[bone].basis.orthonormalized().get_rotation_quaternion().normalized()
		var bone_name := rig.get_bone_name(bone)
		var solved := not face_save and (bone_name.begins_with("spine_") or bone_name.begins_with("upperarm_") or bone_name.begins_with("lowerarm_"))
		rig.set_bone_pose_rotation(bone,after if solved else before.slerp(after,blend).normalized())

static func shape_outer_fingers(author: RefCounted, pose: Array, side: String, ball_center: Vector3) -> void:
	var inside: Vector3 = author.point(pose,"index_01_"+side)
	var outside: Vector3 = author.point(pose,"pinky_01_"+side)
	var spread := (outside-inside).normalized()
	var digits := ["middle","ring","pinky"]
	var spacing := [0.005,0.012,0.020]
	for index in digits.size():
		var first: String = digits[index]+"_01_"+side
		var second: String = digits[index]+"_02_"+side
		var third: String = digits[index]+"_03_"+side
		var joint: Vector3 = author.point(pose,second)
		author.aim_joint(pose,first,second,joint+spread*spacing[index])
		joint = author.point(pose,second)
		var tip: Vector3 = author.point(pose,third)
		var direction := (tip-joint).normalized()
		var curl := (ball_center-tip).slide(direction).normalized()
		author.aim_joint(pose,second,third,tip+curl*0.014)

static func shape_digit(author: RefCounted, pose: Array, digit: String, side: String, tip: Vector3) -> void:
	var first := "%s_01_%s" % [digit,side]
	var second := "%s_02_%s" % [digit,side]
	var third := "%s_03_%s" % [digit,side]
	author.limb(pose,first,second,third,tip,Vector3(0,0,1),1.0,166.0)

static func hand_basis(fingers: Vector3, across: Vector3) -> Basis:
	var axis := fingers.normalized()
	var side := across.slide(axis).normalized()
	return Basis(axis,side,axis.cross(side))
