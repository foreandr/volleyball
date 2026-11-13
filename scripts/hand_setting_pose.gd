extends RefCounted

const CONTACT_HEIGHT := 1.83
const CONTACT_FORWARD := 0.23
const SET_CONTACT_FORWARD := 0.05
const CONTACT_RADIUS := 0.40
const GREEN_CONTACT_ALLOWANCE := 0.17
const RELEASE_TIME := 0.125
const FRONT_WRIST_FOLLOW_TIME := 0.14
const SET_WRIST_LOAD_PITCH := -16.0
const SET_PALM_LOAD_ANGLE := 48.0

static func contact_center(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var center := Vector3.ZERO
	for side in ["l","r"]:
		center += rig.get_bone_global_pose(rig.find_bone("index_03_"+side)).origin
		center += rig.get_bone_global_pose(rig.find_bone("thumb_03_"+side)).origin
	return rig.to_global(center*0.25+Vector3(0,0.075,0.07))

static func apply(actor: Node3D, target: Vector3, blend: float, push := Vector3.ZERO, cushion := 0.0, torso_follow := 0.0, face_save := false, ball_direction := Vector3.ZERO, set_extension := -1.0, set_offset := Vector3.INF, arch_progress := 0.0, overhead_set := false, wrist_turn := -1.0, wrist_finish: Variant = null, receive_facing := Vector3.ZERO) -> void:
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
	var minimum_depth := 0.16 if face_save else (-0.055 if overhead_set else 0.09)
	var diamond := head+Vector3(clampf(aim.x,-0.28 if face_save else -0.22,0.28 if face_save else 0.22),clampf(aim.y-0.075,-0.10 if face_save else 0.12,0.20 if face_save else 0.27),clampf(aim.z-0.07,minimum_depth,0.35))
	var local_push := rig.global_basis.inverse()*push
	var horizontal_push := local_push.slide(Vector3.UP)
	var set_depth := horizontal_push.normalized().z
	var set_depth_m := 0.0
	if set_offset.is_finite():
		var travel := set_offset.slide(Vector3.UP)
		var body_forward := actor.global_basis.z.slide(Vector3.UP).normalized()
		set_depth_m = body_forward.dot(travel)
		# A side-on stance can leave the rig nearly perpendicular to the target.
		# Use the direction the setter is receiving from to resolve that case.
		var side_on := 1.0-smoothstep(0.10,0.35,absf(body_forward.dot(travel.normalized())))
		if not receive_facing.is_zero_approx():
			set_depth_m = lerpf(set_depth_m,receive_facing.dot(travel),side_on)
		set_depth = set_depth_m/maxf(0.001,travel.length())
	var backset := smoothstep(0.0,0.65,-set_depth)
	var wrist_direction := smoothstep(0.12,0.70,absf(set_depth_m))
	var wrist_distance := smoothstep(0.0,4.0,absf(set_depth_m))
	var frontset := smoothstep(0.12,0.70,set_depth_m)*maxf(set_extension,0.0)
	var back_arch := smoothstep(0.0,4.0,-set_depth_m)
	if arch_progress > 0.0 and back_arch > 0.0:
		var arch := deg_to_rad(48.0)*back_arch*arch_progress*blend
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
		var wrist := diamond+Vector3(sign_*lerpf(0.14,0.11,frontset),-0.08,-0.015).rotated(Vector3.UP,turn*0.65)
		var upper: String = "upperarm_"+side
		var lower: String = "lowerarm_"+side
		var pole := Vector3(sign_*lerpf(0.9,0.45,frontset),-0.55,0.30)
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
			var release_direction := local_push.normalized()
			release_direction = (release_direction+Vector3.FORWARD*0.10*backset).normalized()
			var set_axis := release_direction
			set_axis = (set_axis-Vector3.RIGHT*sign_*(0.30*backset+0.24*frontset)).normalized()
			var direction := (wrist-shoulder).normalized().slerp(set_axis,lerpf(0.65,1.0,backset)*aim_weight)
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
		var target_across := Vector3(-sign_*0.72,-0.30,-0.54)
		var wrist_follow := wrist_direction*maxf(set_extension,0.0)
		if wrist_follow > 0.0:
			# Pitch the palm from the solved forearm so it follows the arm past the head.
			var forearm: Vector3 = base.origin-author.point(pose,lower)
			var forearm_pitch := atan2(forearm.z,forearm.y)
			var neutral_pitch := atan2(target_fingers.z,target_fingers.y)
			var flex := deg_to_rad(8.0+14.0*wrist_distance) if set_depth_m > 0.0 else -deg_to_rad(24.0+36.0*wrist_distance)
			var pitch := angle_difference(neutral_pitch,forearm_pitch+flex)*wrist_follow
			target_fingers = target_fingers.rotated(Vector3.RIGHT,pitch)
			target_across = target_across.rotated(Vector3.RIGHT,pitch)
		elif set_extension < 0.0:
			target_fingers = target_fingers.lerp(local_push.normalized(),0.46*follow)
		if overhead_set and set_extension >= 0.0:
			# Cock the wrists during the lift, then let the release pose take over.
			var load_pitch := deg_to_rad(SET_WRIST_LOAD_PITCH)*(1.0-set_extension)
			target_fingers = target_fingers.rotated(Vector3.RIGHT,load_pitch)
			target_across = target_across.rotated(Vector3.RIGHT,load_pitch)
		var palm_load := 1.0-clampf(set_extension,0.0,1.0) if overhead_set else 0.0
		if palm_load > 0.0:
			var palm_normal := target_fingers.cross(target_across).normalized()*sign_
			var lift_axis := palm_normal.cross(Vector3.UP)
			if not lift_axis.is_zero_approx():
				var lift := maxf(0.0,palm_normal.angle_to(Vector3.UP)-deg_to_rad(SET_PALM_LOAD_ANGLE))*palm_load
				target_fingers = target_fingers.rotated(lift_axis.normalized(),lift)
				target_across = target_across.rotated(lift_axis.normalized(),lift)
		var release_basis := Basis.IDENTITY
		if frontset > 0.0:
			var palm_normal := target_fingers.cross(target_across).normalized()*sign_
			var release_normal := (horizontal_push.normalized()+Vector3.DOWN*0.58).normalized()
			release_basis = Basis(Quaternion(palm_normal,release_normal))*hand_basis(target_fingers,target_across)
			# Start the turnover at the same palms-up pose used on the way in.
			var loaded_fingers := Vector3(-sign_*0.52,0.82,0.23).rotated(Vector3.RIGHT,deg_to_rad(SET_WRIST_LOAD_PITCH))
			var loaded_across := Vector3(-sign_*0.72,-0.30,-0.54).rotated(Vector3.RIGHT,deg_to_rad(SET_WRIST_LOAD_PITCH))
			var loaded_normal := loaded_fingers.cross(loaded_across).normalized()*sign_
			var lift_axis := loaded_normal.cross(Vector3.UP).normalized()
			var lift := loaded_normal.angle_to(Vector3.UP)-deg_to_rad(SET_PALM_LOAD_ANGLE)
			var loaded_basis := Basis(lift_axis,lift)*hand_basis(loaded_fingers,loaded_across)
			var hand_turn := loaded_basis.slerp(release_basis,wrist_direction*(wrist_turn if wrist_turn >= 0.0 else 1.0))
			target_fingers = hand_turn.x
			target_across = hand_turn.y
		if face_save and not ball_direction.is_zero_approx():
			var incoming := (rig.global_basis.inverse()*ball_direction).normalized()
			var palm_normal := Vector3(clampf(incoming.x,-0.45,0.45),clampf(incoming.y,-0.18,0.40),maxf(0.55,incoming.z)).normalized()
			target_fingers = target_fingers.slide(palm_normal).normalized()
			target_across = palm_normal.cross(target_fingers)*sign_
		var hand_orientation := hand_basis(target_fingers,target_across)*hand_basis(fingers,across).inverse()*base.basis
		author.set_world_basis(pose,hand,hand_orientation)
		if wrist_finish != null and frontset > 0.0:
			var current_basis: Basis = pose[hand_bone].basis
			author.set_world_basis(pose,hand,release_basis*hand_basis(fingers,across).inverse()*base.basis)
			wrist_finish[hand_bone] = pose[hand_bone].basis.get_rotation_quaternion()
			pose[hand_bone].basis = current_basis
		var index_tip := diamond+Vector3(sign_*0.018,0.065,0.025)
		var thumb_tip := diamond+Vector3(sign_*0.016,-0.047,0.045)
		var finger_cup := diamond+Vector3(0,0.075,0.07)
		if wrist_follow > 0.0:
			index_tip = index_tip.lerp(author.point(pose,"index_03_"+side),wrist_follow)
			thumb_tip = thumb_tip.lerp(author.point(pose,"thumb_03_"+side),wrist_follow)
			finger_cup = finger_cup.lerp(base.origin+target_fingers*0.16+target_across*0.06,wrist_follow)
		shape_digit(author,pose,"index",side,index_tip)
		shape_digit(author,pose,"thumb",side,thumb_tip)
		shape_outer_fingers(author,pose,side,finger_cup)
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
