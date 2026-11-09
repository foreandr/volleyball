extends RefCounted

const DURATION := 0.72

static func sample(actor: Node3D, author: RefCounted, from_pose: Array[Transform3D], ready: Array[Transform3D], start: Vector3, side: String, time: float) -> void:
	var rig: Skeleton3D = actor.skeleton
	var sign_ := 1.0 if side == "l" else -1.0
	var lateral := actor.basis.x.normalized()*sign_
	var slide := 0.28*smoothstep(0.0,0.32,time)
	actor.position = start+lateral*slide
	var down := smoothstep(0.0,0.24,time)
	var recover := smoothstep(0.36,DURATION,time)
	var pose := from_pose.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	var hip: Vector3 = author.point(pose,"thigh_"+side)
	var knee: Vector3 = author.point(pose,"calf_"+side)
	var thigh_length := hip.distance_to(knee)
	var knee_offset := Vector3(sign_*0.18,0.0,0.16)
	var scale_: float = rig.global_basis.get_scale().y
	var floor: float = rig.to_local(Vector3(actor.position.x,0.0,actor.position.z)).y
	knee_offset.y = -sqrt(maxf(0.0,thigh_length*thigh_length-knee_offset.length_squared()))
	var drop := hip.y+knee_offset.y-floor-0.105/scale_
	pose[pelvis].origin -= author.world_pose(pose,parent).basis.inverse()*Vector3.UP*drop*down
	hip = author.point(pose,"thigh_"+side)
	var from_knee: Vector3 = author.point(pose,"calf_"+side)
	author.aim_joint(pose,"thigh_"+side,"calf_"+side,from_knee.lerp(hip+knee_offset,down))
	knee = author.point(pose,"calf_"+side)
	var foot_name := "foot_"+side
	var ankle: Vector3 = author.point(pose,foot_name)
	var ready_ankle: Vector3 = author.point(ready,foot_name)
	author.aim_joint(pose,"calf_"+side,foot_name,ankle.lerp(Vector3(knee.x+sign_*0.05,ready_ankle.y,knee.z-0.34),down))
	var trail := "r" if side == "l" else "l"
	var trail_foot: String = "foot_"+trail
	var trail_ankle: Vector3 = author.point(from_pose,trail_foot)-Vector3.RIGHT*sign_*slide/scale_
	var trail_ready: Vector3 = author.point(ready,trail_foot)
	trail_ankle.y = maxf(trail_ankle.y,trail_ready.y)
	var trail_hip: Vector3 = author.point(pose,"thigh_"+trail)
	var trail_knee: Vector3 = author.point(pose,"calf_"+trail)
	var leg_length: float = trail_hip.distance_to(trail_knee)+trail_knee.distance_to(author.point(pose,trail_foot))-0.003
	var vertical := trail_ankle.y-trail_hip.y
	var reach := sqrt(maxf(0.0,leg_length*leg_length-vertical*vertical))
	var flat := (trail_ankle-trail_hip).slide(Vector3.UP).limit_length(reach)
	trail_ankle = trail_hip+flat+Vector3.UP*vertical
	author.limb(pose,"thigh_"+trail,"calf_"+trail,trail_foot,trail_ankle,Vector3(0,0.25,1))
	for bone in rig.get_bone_count():
		var sampled: Transform3D = pose[bone]
		pose[bone] = sampled.interpolate_with(ready[bone],recover)
	# Keep both soles level and above the court throughout the recovery blend.
	for foot_side in [side,trail]:
		var foot_bone: String = "foot_"+foot_side
		var calf_bone: String = "calf_"+foot_side
		var foot_index := rig.find_bone(foot_bone)
		var neutral: Transform3D = author.world_pose(ready,foot_index)
		var current: Vector3 = author.point(pose,foot_bone)
		if current.y < neutral.origin.y:
			var joint: Vector3 = author.point(pose,calf_bone)
			var shin := current-joint
			var rise := neutral.origin.y-joint.y
			var horizontal := shin.slide(Vector3.UP).normalized()*sqrt(maxf(0.0,shin.length_squared()-rise*rise))
			author.aim_joint(pose,calf_bone,foot_bone,joint+horizontal+Vector3.UP*rise)
		author.set_world_basis(pose,foot_bone,neutral.basis)
		var toe := rig.find_bone("ball_"+foot_side)
		if toe >= 0: pose[toe] = ready[toe]
	for bone in rig.get_bone_count():
		var sampled: Transform3D = pose[bone]
		rig.set_bone_pose_position(bone,sampled.origin)
		rig.set_bone_pose_rotation(bone,sampled.basis.get_rotation_quaternion())
