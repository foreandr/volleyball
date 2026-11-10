extends RefCounted

const SWING_NAME := "06 Low Bow"

static func follow_heading(target: Vector3, origin: Vector3, facing := 0.0) -> float:
	var direction := target.lerp(Vector3(0.0,target.y,8.5),0.18)-origin
	return clampf(angle_difference(facing,atan2(direction.x,direction.z)),-0.95,0.95)

static func apply(pose: Array, author: RefCounted, ball: Vector3, weight: float, extension: float, follow: float, draw_progress: float, arm_lift: float, line_weight: float) -> void:
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw := Vector3(0.04,0.40,0.08).lerp(Vector3(0.15,0.05,-0.12),draw_progress)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06
	var raised_draw := draw.lerp(Vector3(0.04,0.40,0.22),arm_lift)
	var target := (shoulder+raised_draw).lerp(wrist_target,extension)
	target += Vector3(-0.05,0.14,-0.10)*sin(PI*extension)
	var finish := follow
	target = follow_through_target(shoulder,target,hip_finish(pose,author,line_weight < 0.5),finish)
	var elbow_pole := Vector3(-1.0,0.16,-0.84).lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,158.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,172.0,finish)
	elbow_pole = elbow_pole.lerp(Vector3(-0.85,0.04,-0.33),finish)
	var base := pose
	if finish > 0.0:
		pose = base.duplicate()
	var solve_weight := 1.0 if finish > 0.0 else weight
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,solve_weight,elbow_limit)
	drop_low_bow_elbow(pose,author,weight*draw_progress*(1.0-arm_lift)*(1.0-smoothstep(0.0,0.48,extension)))
	var wrist: Vector3 = author.point(pose,"hand_r")
	var axis: Vector3 = (author.point(pose,"middle_01_r")-wrist).normalized()
	var pinky: Vector3 = author.point(pose,"pinky_01_r")
	var thumb: Vector3 = author.point(pose,"thumb_01_r")
	var edge := (pinky-thumb).slide(axis).normalized()
	var down := Vector3.DOWN.slide(axis)
	var target_edge := down.normalized().rotated(axis,PI*(1.0-line_weight))
	var roll := edge.signed_angle_to(target_edge,axis)
	var roll_weight := solve_weight*smoothstep(0.25,0.85,extension)*(1.0-smoothstep(0.0,0.9,follow))*smoothstep(0.0,0.30,down.length())
	author.rotate_world(pose,"hand_r",axis,roll*roll_weight)
	align_finish_wrist(pose,author,finish)
	if finish > 0.0:
		blend_right_arm(base,pose,author,weight)

static func blend_right_arm(base: Array, target: Array, author: RefCounted, weight: float) -> void:
	# Fade local joint rotations so the IK pole cannot twist the elbow as the wrist comes to rest.
	for bone in ["upperarm_r","lowerarm_r","hand_r"]:
		var index: int = author.rig.find_bone(bone)
		var from: Quaternion = base[index].basis.get_rotation_quaternion()
		var to: Quaternion = target[index].basis.get_rotation_quaternion()
		base[index].basis = Basis(from.slerp(to,weight))

static func hip_finish(pose: Array, author: RefCounted, crosscourt: bool, clearance := 0.06) -> Vector3:
	var hip: Vector3 = author.point(pose,"thigh_r" if crosscourt else "thigh_l")
	var side := -1.0 if crosscourt else 1.0
	return hip+Vector3(side*clearance,0.02,0.09)

static func follow_through_target(shoulder: Vector3, contact: Vector3, hip: Vector3, progress: float) -> Vector3:
	var start := contact-shoulder
	var end := hip-shoulder
	var forward := Vector3(-0.10,-0.12,1.0).normalized()
	# Carry the wrist around the shoulder instead of cutting across its reach.
	var from := start.normalized().slerp(forward,progress)
	var toward := forward.slerp(end.normalized(),progress)
	var direction := from.slerp(toward,progress)
	var radius := lerpf(start.length(),end.length(),progress)+0.06*sin(PI*progress)
	return shoulder+direction*radius

static func align_finish_wrist(pose: Array, author: RefCounted, progress: float) -> void:
	var amount := smoothstep(0.25,0.95,progress)
	if amount <= 0.0: return
	var wrist: Vector3 = author.point(pose,"hand_r")
	var fingers: Vector3 = author.point(pose,"middle_01_r")
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var relaxed := (wrist-elbow).normalized()
	var direction := (fingers-wrist).normalized().slerp(relaxed,amount)
	author.aim_joint(pose,"hand_r","middle_01_r",wrist+direction)

static func drop_low_bow_elbow(pose: Array, author: RefCounted, weight: float) -> void:
	if weight <= 0.0: return
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var opposite: Vector3 = author.point(pose,"upperarm_l")
	var outside := (shoulder-opposite).slide(Vector3.UP).normalized()
	var forward := Vector3.UP.cross(outside)
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var upper := (elbow-shoulder).normalized()
	var lowered := (outside*0.10+forward*0.03+Vector3.DOWN*0.30).normalized()
	author.aim_joint(pose,"upperarm_r","lowerarm_r",shoulder+upper.slerp(lowered,weight))
	elbow = author.point(pose,"lowerarm_r")
	var wrist: Vector3 = author.point(pose,"hand_r")
	var chest: Vector3 = author.point(pose,"spine_03")
	var draw_target := chest+outside*0.12+forward*0.20+Vector3.UP*0.04
	var forearm := (wrist-elbow).normalized()
	var toward_chest := (draw_target-elbow).normalized()
	author.aim_joint(pose,"lowerarm_r","hand_r",elbow+forearm.slerp(toward_chest,weight))
