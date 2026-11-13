extends RefCounted

const PlatformPose = preload("res://scripts/reception_platform_pose.gd")

static func outward_knee_pole(pole: Vector3, axis: Vector3, outward: Vector3) -> Vector3:
	var out := outward.slide(axis).normalized()
	var bend := pole.slide(axis).normalized()
	if out.is_zero_approx() or bend.dot(out) >= 0.55: return bend
	var forward := bend.slide(out)
	if forward.length_squared() < 0.0001:
		forward = out.cross(axis)
		if forward.z < 0.0: forward = -forward
	return forward.normalized()*sqrt(1.0-0.55*0.55)+out*0.55

static func sample(rig: Skeleton3D, author: RefCounted, step: Vector3, travel: Vector3, weight: float, progress: float, ready: Array[Transform3D], reach: Dictionary, knee_slide: bool, cpu_direction: int, contact: Vector3) -> void:
	var tier: int = reach.tier
	var back: bool = reach.back
	var rear_diagonal: bool = reach.rear_diagonal
	var short_straight_back: bool = reach.short_straight_back
	var forward_lunge: bool = reach.forward_lunge
	var lead: String = reach.lead
	var side_lunge: bool = reach.side_lunge
	var height: float = reach.height
	var centered_back: bool = reach.get("centered_back",false)
	var pose: Array = []
	for bone in rig.get_bone_count(): pose.append(rig.get_bone_pose(bone))
	if tier == 2 and back and not rear_diagonal and not ready.is_empty():
		# Keep the shuffle-to-lunge foot solve on one stance instead of switching authored leg poses mid-step.
		for name_ in ["pelvis","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r","ball_l","ball_r"]:
			var bone := rig.find_bone(name_)
			if bone >= 0:
				pose[bone] = pose[bone].interpolate_with(ready[bone],weight) if centered_back else ready[bone]
	var scale_: float = rig.global_basis.y.length()
	var short_straight := tier == 1 and (forward_lunge or short_straight_back)
	var back_amount := 0.0 if short_straight else clampf(-step.z/0.32,0.0,1.0)
	var side_lean := clampf(step.x/0.32,-1.0,1.0)
	var shoulder_side := 1.0 if lead == "l" else -1.0
	author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.27*weight)
	var side_receive := not back and (side_lunge or (absf(step.x)>0.10 and absf(step.x)>absf(step.z)*0.55))
	if side_receive:
		# Open the shoulders toward the ball and lower the opposite shoulder.
		var roll := 0.56 if tier == 2 else 0.43
		if side_lunge:
			# Roll the ribcage down with the trailing shoulder.
			author.rotate_world(pose,"spine_02",Vector3.BACK,side_lean*0.24*weight)
			author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.10*weight)
			roll -= 0.15
		author.rotate_world(pose,"spine_03",Vector3.BACK,side_lean*roll*weight)
		author.rotate_world(pose,"spine_02",Vector3.UP,side_lean*0.08*weight)
		author.rotate_world(pose,"spine_03",Vector3.UP,side_lean*0.19*weight)
	author.rotate_world(pose,"spine_02",Vector3.RIGHT,-back_amount*0.14*weight)
	author.rotate_world(pose,"spine_03",Vector3.UP,shoulder_side*back_amount*(0.0 if centered_back else (0.18 if tier == 2 else 0.31))*weight)
	var deep := tier == 2 and height < 0.20
	var high := height >= 0.20
	var short_lunge := tier == 1 and not high and (side_receive or back)
	knee_slide = side_lunge and knee_slide
	var straight_back := short_straight_back or (tier == 2 and back and not rear_diagonal)
	var pelvis := rig.find_bone("pelvis")
	var hips: Transform3D = pose[pelvis]
	if high or (back and tier == 2):
		# Clear the incoming path by turning the ribcage, leaving the joined platform out in front.
		var turn := (shoulder_side*0.50 if high else side_lean*0.12)*weight
		if centered_back: turn *= 0.15
		author.rotate_world(pose,"spine_02",Vector3.UP,turn*0.55)
		author.rotate_world(pose,"spine_03",Vector3.UP,turn*0.45)
		if high:
			author.rotate_world(pose,"spine_02",Vector3.RIGHT,-0.19*weight)
			author.rotate_world(pose,"spine_02",Vector3.BACK,shoulder_side*(0.03 if centered_back else 0.15)*weight)
			author.rotate_world(pose,"spine_03",Vector3.BACK,-shoulder_side*(0.0 if centered_back else 0.07)*weight)
	if deep:
		author.rotate_world(pose,"spine_02",Vector3.BACK,-side_lean*0.12*weight)
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,0.14*weight)
	if deep or side_lunge or (high and back):
		var parent := rig.get_bone_parent(pelvis)
		var drop := (0.29 if rear_diagonal else (0.21 if back else (0.22 if forward_lunge else 0.36)))*weight
		if side_lunge:
			# Set pelvis height from the planted trailing ankle and a nearly straight knee.
			var trail := "r" if lead == "l" else "l"
			var hip: Vector3 = author.point(pose,"thigh_"+trail)
			var knee: Vector3 = author.point(pose,"calf_"+trail)
			var foot: Vector3 = author.point(pose,"foot_"+trail)
			var leg_length := hip.distance_to(knee)+knee.distance_to(foot)
			var planted_offset := hip-(foot-travel/scale_)
			var horizontal := Vector2(planted_offset.x,planted_offset.z).length()
			var extension := lerpf(hip.distance_to(foot),leg_length*0.998,weight)
			var hip_height := sqrt(maxf(0.0,extension*extension-horizontal*horizontal))
			drop = clampf(planted_offset.y-hip_height,-0.13*weight,0.43*weight)
		pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop
	if (forward_lunge and tier == 1 and not high) or short_lunge:
		var parent := rig.get_bone_parent(pelvis)
		pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*(0.075 if short_lunge and not short_straight_back else 0.11)*weight
		author.rotate_world(pose,"spine_02",Vector3.RIGHT,(0.04 if short_lunge and not short_straight_back else 0.12)*weight)
	var leg_pose := pose.duplicate()
	leg_pose[pelvis] = hips
	for side in ["l","r"]:
		var foot_name: String = "foot_"+side
		var foot: Transform3D = author.world_pose(leg_pose,rig.find_bone(foot_name))
		var target := foot.origin-travel/scale_
		if side == lead:
			var extension := 0.98 if side_lunge or forward_lunge else (1.18 if deep else 1.32)
			if back and tier == 2: extension = 0.84
			if short_lunge: extension = 0.98 if short_straight_back else 1.08
			target += step/scale_*weight*extension+Vector3.UP*sin(PI*progress)*0.08
			if side_lunge: target.z += 0.28*weight
			if rear_diagonal: target.z += 0.08*weight
			if short_lunge and side_receive: target.z += 0.09*weight
			if forward_lunge: target.z += (0.12 if tier == 2 else 0.07)*weight
			if straight_back: target.z -= (0.12 if tier == 2 else 0.07)*weight
		elif (back and tier == 2) or knee_slide:
			# Slide the trailing shoe along the court once the planted ankle is out of reach.
			var hip: Vector3 = author.point(pose,"thigh_"+side)
			var knee: Vector3 = author.point(pose,"calf_"+side)
			var ankle: Vector3 = author.point(pose,foot_name)
			var leg_length := hip.distance_to(knee)+knee.distance_to(ankle)-0.003
			var vertical := target.y-hip.y
			var ground_range := sqrt(maxf(0.0,leg_length*leg_length-vertical*vertical))
			var ground_offset := Vector3(target.x-hip.x,0.0,target.z-hip.z).limit_length(ground_range)
			target.x = hip.x+ground_offset.x
			target.z = hip.z+ground_offset.z
		var pole: Vector3 = author.point(leg_pose,"calf_"+side)-author.point(leg_pose,"thigh_"+side)
		if (side_lunge or rear_diagonal or (short_lunge and not short_straight_back)) and side == lead:
			# Load the knee over the lead foot as the other leg extends.
			var hip: Vector3 = author.point(pose,"thigh_"+side)
			var knee_over_foot := target+Vector3(shoulder_side*0.08,0.28,0.32)-hip
			pole = pole.normalized().lerp(knee_over_foot.normalized(),weight)
		elif straight_back and tier == 2:
			pole = Vector3(-0.46 if side == "r" else 0.46,0.42,1.0)
		elif short_straight and side == "r":
			pole = pole.normalized()+Vector3.LEFT*0.09*weight
		elif forward_lunge and tier == 2 and side == "r":
			pole = pole.normalized()+Vector3.LEFT*0.09*weight
		var hip: Vector3 = author.point(pose,"thigh_"+side)
		var outward: Vector3 = hip-author.point(pose,"thigh_"+("r" if side == "l" else "l"))
		pole = outward_knee_pole(pole,(target-hip).normalized(),outward)
		author.limb(pose,"thigh_"+side,"calf_"+side,foot_name,target,pole)
		author.set_world_basis(pose,foot_name,foot.basis)
	if high or tier == 2 or side_receive or forward_lunge or back:
		var extension := 0.17 if forward_lunge else (0.10 if side_lunge else 0.05)
		if back and not short_straight: extension = 0.10 if tier == 1 and cpu_direction == 6 else 0.22
		var arms := Vector3(step.x,0.0,step.z).normalized()*extension*weight
		if short_straight: arms = Vector3.BACK*0.17*weight
		if forward_lunge or short_lunge: arms.y = 0.07*weight
		if rear_diagonal: arms.y = 0.10*weight
		if side_lunge and cpu_direction == 3:
			arms += Vector3(0.0,0.17,0.14)*weight
		var center: Vector3 = (author.point(pose,"hand_l")+author.point(pose,"hand_r"))*0.5
		if knee_slide and cpu_direction != 0 and contact.is_finite():
			var target: Vector3 = rig.global_transform.affine_inverse()*contact
			var wrist_target := target+Vector3(0.0,-0.04,0.13)
			arms = arms.lerp(wrist_target-center,weight*0.85)
		elif high:
			var shoulder_height: float = (author.point(pose,"upperarm_l").y+author.point(pose,"upperarm_r").y)*0.5
			arms.y = maxf(0.0,shoulder_height-center.y-0.02)*weight
			if contact.is_finite():
				var ball_point := rig.global_transform.affine_inverse()*contact
				var wrist_target := ball_point+Vector3(0.0,-0.24,0.22)
				arms = arms.lerp(wrist_target-center,weight*0.85)
		elif not back:
			arms.x -= side_lean*0.05*weight
		PlatformPose.connect_arms(pose,author,center+arms,smoothstep(0.0,0.68,weight),0.022,Vector3.RIGHT,false,tier == 2)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	for bone in rig.get_bone_count():
		rig.set_bone_pose_rotation(bone,pose[bone].basis.get_rotation_quaternion())
