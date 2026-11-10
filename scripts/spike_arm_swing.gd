extends RefCounted

const SWING_NAME := "06 Low Bow"
const DEFAULT_DRAW_DELAY := 0.05
const DEFAULT_ELBOW_CLEARANCE := 0.12

static func follow_heading(target: Vector3, origin: Vector3, facing := 0.0) -> float:
	var direction := target-origin
	return clampf(angle_difference(facing,atan2(direction.x,direction.z)),-0.95,0.95)

static func apply(pose: Array, author: RefCounted, ball: Vector3, weight: float, extension: float, follow: float, draw_progress: float, arm_lift: float, line_weight: float, palm_finish: float, elbow_clearance: float) -> void:
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw := Vector3(-0.04,0.40,0.08).lerp(Vector3(0.02,0.05,-0.12),draw_progress)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06
	var raised_draw := draw.lerp(Vector3(-0.08,0.40,0.22),arm_lift)
	var target := (shoulder+raised_draw).lerp(wrist_target,extension)
	target += Vector3(-0.05,0.14,-0.10)*sin(PI*extension)
	var finish := follow
	target = follow_through_target(pose,author,shoulder,target,hip_finish(pose,author,line_weight < 0.5),finish)
	var elbow_pole := Vector3(-1.0,0.16,-0.84).lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,158.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,172.0,finish)
	elbow_pole = elbow_pole.lerp(Vector3(-0.85,0.04,-0.33),finish)
	var base := pose
	if finish > 0.0:
		pose = base.duplicate()
	var solve_weight := 1.0 if finish > 0.0 else weight
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,solve_weight,elbow_limit)
	drop_low_bow_elbow(pose,author,weight*draw_progress*(1.0-arm_lift)*(1.0-smoothstep(0.0,0.48,extension)),elbow_clearance)
	var wrist_alignment := lerpf(0.90,0.68,smoothstep(0.04,0.70,extension))
	wrist_alignment = lerpf(wrist_alignment,0.96,smoothstep(0.0,0.86,follow))
	align_wrist_to_forearm(pose,author,wrist_alignment*solve_weight)
	var palm_progress := maxf(0.38*smoothstep(0.35,0.98,extension),follow)
	roll_finish_palm(pose,author,palm_finish,palm_progress)
	if finish > 0.0:
		blend_right_arm(base,pose,author,weight)
	open_strike_hand(base,author,weight*lerpf(0.70,0.94,smoothstep(0.12,0.85,extension)))

static func open_strike_hand(pose: Array, author: RefCounted, weight: float) -> void:
	# Release the curl inherited from the jump pose without locking the fingers at full extension.
	for finger in ["index","middle","ring","pinky","thumb"]:
		for segment in range(1,4):
			var index: int = author.rig.find_bone("%s_%02d_r" % [finger,segment])
			var current: Quaternion = pose[index].basis.get_rotation_quaternion()
			var relaxed: Quaternion = author.rig.get_bone_rest(index).basis.get_rotation_quaternion()
			pose[index].basis = Basis(current.slerp(relaxed,weight))

static func apply_guide_arm(pose: Array, author: RefCounted, reach: Vector3, reach_pole: Vector3, drop: float, weight: float, reach_limit: float) -> void:
	if weight <= 0.0: return
	var shoulder: Vector3 = author.point(pose,"upperarm_l")
	var elbow: Vector3 = author.point(pose,"lowerarm_l")
	var wrist: Vector3 = author.point(pose,"hand_l")
	var outside: Vector3 = (shoulder-author.point(pose,"upperarm_r")).normalized()
	var up: Vector3 = (author.point(pose,"neck_01")-author.point(pose,"spine_03")).normalized()
	var forward := outside.cross(up).normalized()
	var tuck_pole := (outside.cross(forward)+outside*0.10).normalized()
	var tuck := tuck_pole*shoulder.distance_to(elbow)+forward*elbow.distance_to(wrist)
	var target := shoulder+reach.lerp(tuck,drop)
	author.limb(pose,"upperarm_l","lowerarm_l","hand_l",target,reach_pole.lerp(tuck_pole,drop),weight,lerpf(reach_limit,90.0,drop))

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

static func follow_through_target(pose: Array, author: RefCounted, shoulder: Vector3, contact: Vector3, hip: Vector3, progress: float) -> Vector3:
	var start := contact-shoulder
	var end := hip-shoulder
	var forward := Vector3(-0.10,-0.12,1.0).normalized()
	# Carry the wrist around the shoulder instead of cutting across its reach.
	var from := start.normalized().slerp(forward,progress)
	var toward := forward.slerp(end.normalized(),progress)
	var direction := from.slerp(toward,progress)
	var radius := lerpf(start.length(),end.length(),progress)+0.06*sin(PI*progress)
	var across: Vector3 = author.point(pose,"upperarm_l")-shoulder
	var up: Vector3 = author.point(pose,"neck_01")-author.point(pose,"spine_03")
	var chest_forward := across.cross(up).normalized()
	var clearance := 0.15*smoothstep(0.08,0.58,progress)*(1.0-smoothstep(0.63,1.0,progress))
	# Carry the arm forward of the ribs while preserving reach and both endpoints.
	var offset := (direction*radius+chest_forward*clearance).normalized()*radius
	return shoulder+offset

static func finish_palm_direction(target: Vector3, origin: Vector3, cross_body: bool) -> float:
	var lateral := absf(target.x-origin.x)/maxf(target.z-origin.z,0.1)
	var turn := smoothstep(0.045,0.13,lateral)
	return turn if cross_body else -turn

static func roll_finish_palm(pose: Array, author: RefCounted, direction: float, follow: float) -> void:
	var weight := absf(direction)*smoothstep(0.05,0.84,follow)
	if weight <= 0.0: return
	var wrist: Vector3 = author.point(pose,"hand_r")
	var knuckle: Vector3 = author.point(pose,"middle_01_r")
	var axis := (knuckle-wrist).normalized()
	var pinky: Vector3 = author.point(pose,"pinky_01_r")
	var thumb: Vector3 = author.point(pose,"thumb_01_r")
	var edge := (pinky-thumb).slide(axis).normalized()
	var down := (Vector3.DOWN*signf(direction)).slide(axis)
	var roll := edge.signed_angle_to(down.normalized(),axis)
	# The two edges have no meaningful height difference when the hand points straight down.
	author.rotate_world(pose,"hand_r",axis,roll*weight*smoothstep(0.10,0.34,down.length()))

static func align_finish_wrist(pose: Array, author: RefCounted, progress: float) -> void:
	align_wrist_to_forearm(pose,author,smoothstep(0.25,0.95,progress))

static func align_wrist_to_forearm(pose: Array, author: RefCounted, amount: float) -> void:
	if amount <= 0.0: return
	var wrist: Vector3 = author.point(pose,"hand_r")
	var fingers: Vector3 = author.point(pose,"middle_01_r")
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var relaxed := (wrist-elbow).normalized()
	var direction := (fingers-wrist).normalized().slerp(relaxed,amount)
	author.aim_joint(pose,"hand_r","middle_01_r",wrist+direction)

static func drop_low_bow_elbow(pose: Array, author: RefCounted, weight: float, clearance: float) -> void:
	if weight <= 0.0: return
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var opposite: Vector3 = author.point(pose,"upperarm_l")
	var outside := (shoulder-opposite).slide(Vector3.UP).normalized()
	var forward := Vector3.UP.cross(outside)
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var upper := (elbow-shoulder).normalized()
	var lowered := (outside*(0.10+clearance)+forward*0.03+Vector3.DOWN*0.30).normalized()
	author.aim_joint(pose,"upperarm_r","lowerarm_r",shoulder+upper.slerp(lowered,weight))
	elbow = author.point(pose,"lowerarm_r")
	var wrist: Vector3 = author.point(pose,"hand_r")
	var chest: Vector3 = author.point(pose,"spine_03")
	var draw_target := chest+outside*(0.12+clearance*(0.19/DEFAULT_ELBOW_CLEARANCE))+forward*0.23+Vector3.UP*0.04
	var forearm := (wrist-elbow).normalized()
	var toward_chest := (draw_target-elbow).normalized()
	author.aim_joint(pose,"lowerarm_r","hand_r",elbow+forearm.slerp(toward_chest,weight))
