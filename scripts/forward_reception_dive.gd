extends RefCounted

const RECOVERY_CORRECTION = preload("res://assets/animations/reception_dive_correction.tres")
const TWO_ARM_REACH_EDIT = preload("res://assets/animations/two_arm_dive_reach_edit.tres")
const PlatformPose = preload("res://scripts/reception_platform_pose.gd")
const WINDUP := 0.33
const CONTACT_POSE_TIME := 0.40
const POSE_DURATION := 1.28
const GET_UP_EXTENSION := 0.40
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

static func unscaled_contact_travel(pancake: bool, wide: bool) -> float:
	var travel := 0.23+1.35*smoothstep(0.16,0.61,CONTACT_POSE_TIME)
	if pancake: travel += 0.70
	if wide: travel += 0.14
	return travel

static func sample(actor: Node3D, author: RefCounted, ready: Array[Transform3D], clasp: Array[Transform3D], start: Vector3, heading: Vector3, time: float, ball_point: Vector3, release_time: float, pancake := false, travel_scale := 1.0, track_platform := false, wide_arm := "", slide_heading := Vector3.ZERO) -> void:
	var correction_time := time-WINDUP+float(RECOVERY_CORRECTION.get_meta("contact_time"))
	var reach_edit_time := time/WINDUP*float(TWO_ARM_REACH_EDIT.get_meta("contact_time"))
	# Start later while preserving the reach at the intended ball contact.
	time = time*CONTACT_POSE_TIME/WINDUP if time < WINDUP else time-WINDUP+CONTACT_POSE_TIME
	time -= GET_UP_EXTENSION*smoothstep(0.82,POSE_DURATION+GET_UP_EXTENSION,time)
	var rig: Skeleton3D = actor.skeleton
	var brace_start := maxf(0.41,release_time-WINDUP+CONTACT_POSE_TIME)
	var since_brace := time-brace_start
	var slide := 0.95*smoothstep(0.08,0.56,since_brace)
	var kick := smoothstep(-0.24,-0.08,since_brace)*(1.0-smoothstep(0.19,0.39,since_brace))
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
	if not wide_arm.is_empty():
		# Carry the lateral lunge farther before contact, then rejoin the normal slide.
		travel += 0.14*smoothstep(0.12,0.40,time)*(1.0-smoothstep(0.40,0.62,time))
	if track_platform and time < CONTACT_POSE_TIME:
		var contact_travel := unscaled_contact_travel(pancake,not wide_arm.is_empty())
		var progress := clampf(time/CONTACT_POSE_TIME,0.0,1.0)
		# Carry some sprint momentum into takeoff, with less acceleration just before contact.
		var even_progress := smoothstep(0.0,1.0,progress)+progress*(1.0-progress)*(0.35-0.80*progress)
		travel = lerpf(travel,contact_travel*even_progress,smoothstep(1.1,1.6,travel_scale))
	# The approach boost reaches the ball. Keep it out of the slide after release.
	var travel_after_release := 0.0
	if track_platform and time > brace_start:
		travel_after_release = 1.35*(smoothstep(0.16,0.61,time)-smoothstep(0.16,0.61,brace_start))+slide
	travel = (travel-travel_after_release)*travel_scale+travel_after_release*minf(travel_scale,1.25)
	actor.position = start+(heading if wide_arm.is_empty() or slide_heading.is_zero_approx() else slide_heading)*travel
	var facing_yaw := atan2(heading.x,heading.z)
	if not wide_arm.is_empty() and not slide_heading.is_zero_approx():
		var ball_yaw := atan2(slide_heading.x,slide_heading.z)
		var turn := clampf(angle_difference(facing_yaw,ball_yaw)*0.55,-deg_to_rad(52.0),deg_to_rad(52.0))
		facing_yaw += turn*smoothstep(0.0,0.16,time)
	actor.rotation.y = facing_yaw
	var pose := ready.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var scale_: float = rig.global_basis.y.length()
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop/scale_
	author.rotate_world(pose,"pelvis",Vector3.RIGHT,pitch)
	var extension := smoothstep(0.19,0.39,time)
	if not pancake:
		extension = smoothstep(-0.025,0.13,since_brace)

	var landing := smoothstep(-0.10,0.10,since_brace)
	if pancake:
		var low := smoothstep(0.23,0.40,time)*(1.0-smoothstep(0.82,POSE_DURATION,time))
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.18*low)
		author.rotate_world(pose,"neck_01",Vector3.RIGHT,-0.38*low)
	var chest_settle := landing*(1.0-smoothstep(0.49,0.71,since_brace))
	var get_up := smoothstep(0.59,0.78,since_brace)
	# Keep the hips low until the lead foot can take weight.
	var support_drop := 0.16*smoothstep(0.47,0.63,since_brace)*(1.0-get_up)
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*support_drop/scale_
	author.rotate_world(pose,"spine_03",Vector3.RIGHT,-0.22*extension*(1.0-get_up))
	author.rotate_world(pose,"neck_01",Vector3.RIGHT,-0.24*extension*(1.0-get_up)-0.36*chest_settle)
	author.rotate_world(pose,"Head",Vector3.RIGHT,-pitch*0.24)
	var chest: Vector3 = rig.to_global(author.point(pose,"spine_03"))
	var chest_drop := maxf(0.0,chest.y-0.20)*chest_settle
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*chest_drop/scale_
	var head: Vector3 = author.point(pose,"Head")
	var head_lift := maxf(0.0,0.24-0.02*chest_settle-(rig.global_transform*head).y)
	pose[pelvis].origin += author.world_pose(pose,parent).basis.inverse()*Vector3.UP*head_lift/scale_
	var hands_release := 1.0-smoothstep(0.69,0.83,since_brace)
	var push := smoothstep(0.08,0.53,since_brace)
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = author.world_pose(ready,rig.find_bone(foot_name))
		var ankle := foot.origin-Vector3.BACK*travel/scale_
		if side == "r":
			var plant := smoothstep(0.015,0.15,time)
			ankle.z += (0.42 if pancake else 0.66)*plant
			ankle.y += 0.09*sin(PI*plant)
		var trail := foot.origin-Vector3.BACK*(0.69 if side == "l" else 0.81)
		trail.x = foot.origin.x
		var thigh: String = "thigh_"+side
		var calf: String = "calf_"+side
		var hip: Vector3 = author.point(pose,thigh)
		var knee: Vector3 = author.point(pose,calf)
		var upper_length := hip.distance_to(knee)
		var lower_length := knee.distance_to(author.point(pose,foot_name))
		var thigh_lift := deg_to_rad(20.0 if side == "l" else 17.0)
		var shin_lift := deg_to_rad(80.0 if side == "l" else 76.0)
		var raised_ankle := hip+Vector3(0.0,sin(thigh_lift),-cos(thigh_lift))*upper_length
		raised_ankle += Vector3(0.0,sin(shin_lift),-cos(shin_lift))*lower_length
		trail = trail.lerp(raised_ankle,kick)
		var lead: bool = side == "r"
		var step_start := 0.41 if lead else 0.60
		var plant_time := 0.60 if lead else 0.84
		var step := smoothstep(step_start,plant_time,since_brace)
		var swing := sin(PI*step)
		# Bring one foot under the hips, then step the trailing foot up after the weight transfer.
		ankle = ankle.lerp(trail,maxf(extension,kick)).lerp(foot.origin,step)
		ankle.y += swing*(0.18 if lead else 0.12)/scale_
		var descent := smoothstep(0.19,0.28,since_brace)*(1.0-smoothstep(0.37,0.52,since_brace))
		var leg_axis := (ankle-hip).normalized()
		# Keep the knee hinge on the player's lateral axis throughout the tuck.
		var pole := leg_axis.cross(Vector3.RIGHT).normalized()
		var knee_limit := lerpf(lerpf(180.0,120.0,kick),136.0,descent)
		author.limb(pose,thigh,calf,foot_name,ankle,pole,1.0,knee_limit)
		var ready_shin: Vector3 = foot.origin-author.point(ready,calf)
		var posed_shin: Vector3 = author.point(pose,foot_name)-author.point(pose,calf)
		# Rotate around the lateral axis so the soles stay aligned instead of twisting across one another.
		var ready_pitch := atan2(ready_shin.z,-ready_shin.y)
		var posed_pitch := atan2(posed_shin.z,-posed_shin.y)
		var toe_pitch := -angle_difference(ready_pitch,posed_pitch)*maxf(extension,kick)*(1.0-step)
		toe_pitch = lerpf(toe_pitch,0.22*swing,smoothstep(0.42,0.57,since_brace))
		author.set_world_basis(pose,foot_name,Basis(Vector3.RIGHT,toe_pitch)*foot.basis)
	var brace_pose := pose.duplicate()
	var grip: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
	var reach := smoothstep(0.11,0.31,time)
	if not pancake:
		reach = smoothstep(0.06,0.25,time)
	reach *= 1.0-smoothstep(0.085,0.18,since_brace)
	if pancake and reach > 0.0:
		var target := rig.global_transform.affine_inverse()*Vector3(ball_point.x,0.06,ball_point.z)-Vector3.BACK*0.095
		author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,Vector3(-0.30,-0.55,0.10),reach,174.0)
		flatten_palm(pose,author,rig,reach)
	elif not wide_arm.is_empty() and reach > 0.0:
		var side := 1.0 if wide_arm == "l" else -1.0
		var lift := smoothstep(0.0,0.12,since_brace)
		var upper: String = "upperarm_"+wide_arm
		var shoulder: Vector3 = author.point(pose,upper)
		var ball := rig.to_local(ball_point)
		# Put the forearm under the ball, with the wrist extending just past it.
		var target := ball+(ball-shoulder).normalized()*(0.10/scale_)+Vector3.UP*(-0.055+0.31*lift)/scale_
		author.limb(pose,upper,"lowerarm_"+wide_arm,"hand_"+wide_arm,target,
			Vector3(side*0.38,-0.65,0.24),smoothstep(0.0,0.65,reach),174.0)
	elif reach > 0.0:
		var bias := Vector3(0,-0.055,0.12)/scale_
		var local_ball := rig.to_local(ball_point)
		var target := local_ball+bias
		var head_height: float = author.point(pose,"Head").y
		if not pancake:
			var shoulder_height: float = (author.point(pose,"upperarm_l").y+author.point(pose,"upperarm_r").y)*0.5
			head_height = minf(head_height-(0.09 if track_platform else 0.17),shoulder_height-(0.04 if track_platform else 0.12))
		target.y = clampf(target.y,0.13,maxf(0.13,head_height))
		var entry := pose.duplicate()
		for pass_index in 3:
			if pass_index > 0: pose = entry.duplicate()
			PlatformPose.connect_arms(pose,author,target,reach,0.0,Vector3.RIGHT,true)
			if pass_index == 2 or reach < 0.55: break
			var left := Geometry3D.get_closest_point_to_segment(local_ball,author.point(pose,"lowerarm_l"),author.point(pose,"hand_l"))
			var right := Geometry3D.get_closest_point_to_segment(local_ball,author.point(pose,"lowerarm_r"),author.point(pose,"hand_r"))
			var gap := local_ball-(left+right)*0.5
			target += (gap-Vector3.UP*0.09/scale_).limit_length(0.16/scale_)
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
	if since_brace > 0.0:
		for side in ["l","r"]:
			var delay := 0.055 if side == wide_arm or (pancake and side == "r") else 0.0
			var support := smoothstep(delay,delay+0.085,since_brace)*hands_release
			if support <= 0.0: continue
			var hand: String = "hand_"+side
			var outward := 1.0 if side == "l" else -1.0
			var shoulder: Vector3 = author.point(brace_pose,"upperarm_"+side)
			# The chest moves past the palms as they slide, then the hands push the torso up.
			var ribs: Vector3 = author.point(brace_pose,"spine_02")
			var catch_palm := shoulder+Vector3(outward*0.13,0.0,0.32/scale_)
			var push_palm := Vector3(shoulder.x+outward*0.09,0.0,ribs.z)
			var palm := catch_palm.lerp(push_palm,push)
			palm.y = rig.to_local(Vector3(0.0,0.065,0.0)).y
			# Solve the floor brace from the neutral arm, independent of the moving ball target.
			author.limb(brace_pose,"upperarm_"+side,"lowerarm_"+side,hand,palm,
				Vector3(outward*0.38,0.58,lerpf(-0.16,-0.48,push)),1.0,166.0)
			flatten_palm(brace_pose,author,rig,1.0,side)
			for joint in ["upperarm_"+side,"lowerarm_"+side,hand]:
				var bone := rig.find_bone(joint)
				pose[bone].basis = pose[bone].basis.slerp(brace_pose[bone].basis,support)
	if pancake:
		for side in ["l","r"]:
			var hand: String = "hand_"+side
			var wrist: Vector3 = author.point(pose,hand)
			var height: float = (rig.global_transform*wrist).y
			if height < 0.055:
				wrist.y += (0.055-height)/scale_
				author.limb(pose,"upperarm_"+side,"lowerarm_"+side,hand,wrist,Vector3(0.65 if side == "l" else -0.65,0.4,-0.25))
	if not pancake and wide_arm.is_empty() and reach_edit_time >= 0.0 and reach_edit_time < 13.0/60.0:
		for track in TWO_ARM_REACH_EDIT.get_track_count():
			var bone := rig.find_bone(TWO_ARM_REACH_EDIT.track_get_path(track).get_subname(0))
			var edit: Quaternion = TWO_ARM_REACH_EDIT.rotation_track_interpolate(track,reach_edit_time)
			pose[bone].basis *= Basis(edit)
	# Apply the editor changes as local joint offsets over the live dive.
	for track in RECOVERY_CORRECTION.get_track_count():
		var bone := rig.find_bone(RECOVERY_CORRECTION.track_get_path(track).get_subname(0))
		if bone < 0: continue
		var offset: Quaternion = RECOVERY_CORRECTION.rotation_track_interpolate(track,clampf(correction_time,0.0,RECOVERY_CORRECTION.length))
		pose[bone].basis *= Basis(offset)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_position(bone,pose[bone].origin)
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())

static func flatten_palm(pose: Array, author: RefCounted, rig: Skeleton3D, weight: float, side := "r") -> void:
	var wrist := rig.find_bone("hand_"+side)
	var fingers := rig.find_bone("middle_01_"+side)
	var index := rig.find_bone("index_01_"+side)
	var pinky := rig.find_bone("pinky_01_"+side)
	if mini(fingers,mini(index,pinky)) < 0: return
	var hand: Transform3D = author.world_pose(pose,wrist)
	var forward: Vector3 = (author.point(pose,"middle_01_"+side)-hand.origin).normalized()
	var across: Vector3 = (author.point(pose,"index_01_"+side)-author.point(pose,"pinky_01_"+side)).slide(forward).normalized()
	if side == "l": across = -across
	var palm := Basis(across,forward.cross(across),forward)
	author.set_world_basis(pose,"hand_"+side,hand.basis.slerp(palm.inverse()*hand.basis,weight))
