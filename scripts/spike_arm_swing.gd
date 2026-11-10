extends RefCounted

const SWING_NAME := "06 Low Bow"
const DEFAULT_DRAW_DELAY := 0.05
const DEFAULT_ELBOW_CLEARANCE := 0.12

static func follow_heading(target: Vector3, origin: Vector3, facing := 0.0) -> float:
	var direction := target-origin
	return clampf(angle_difference(facing,atan2(direction.x,direction.z)),-0.95,0.95)

static func apply(pose: Array, author: RefCounted, ball: Vector3, weight: float, extension: float, follow: float, draw_progress: float, arm_lift: float, line_weight: float, palm_finish: float, elbow_clearance: float, previous_roll: float, roll_step: float, shot_direction: Vector3, compact_finish: float) -> float:
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw := Vector3(-0.04,0.40,0.08).lerp(Vector3(0.02,0.05,-0.12),draw_progress)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06-shot_direction*0.11
	var raised_draw := draw.lerp(Vector3(-0.08,0.40,0.22),arm_lift)
	var target := (shoulder+raised_draw).lerp(wrist_target,extension)
	target += Vector3(-0.05,0.14,-0.10)*sin(PI*extension)
	var finish := follow
	var same_side := line_weight < 0.5
	target = follow_through_target(pose,author,shoulder,target,hip_finish(pose,author,same_side),finish,same_side,compact_finish)
	var elbow_pole := Vector3(-1.0,0.16,-0.84).lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,158.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,164.0 if same_side else 172.0,finish)
	elbow_pole = elbow_pole.lerp(finish_elbow_pole(same_side),finish)
	var base := pose
	if finish > 0.0:
		pose = base.duplicate()
	var solve_weight := 1.0 if finish > 0.0 else weight
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,solve_weight,elbow_limit)
	drop_low_bow_elbow(pose,author,weight*draw_progress*(1.0-arm_lift)*(1.0-smoothstep(0.0,0.48,extension)),elbow_clearance)
	var wrist_alignment := lerpf(0.90,0.68,smoothstep(0.04,0.70,extension))
	wrist_alignment = lerpf(wrist_alignment,0.96,smoothstep(0.0,0.86,follow))
	align_wrist_to_forearm(pose,author,wrist_alignment*solve_weight)
	var release_turn := 0.38*smoothstep(0.35,0.98,extension)
	if line_weight >= 0.5:
		# Start the across-body roll on forward extension, after the arm leaves the draw.
		release_turn = 0.70*smoothstep(0.24,0.86,extension)
	var palm_progress := maxf(release_turn,follow)
	var face_weight := smoothstep(0.07,0.48,extension)*(1.0-smoothstep(0.03,0.60,follow))
	var roll := roll_finish_palm(pose,author,palm_finish,palm_progress,line_weight >= 0.5,previous_roll,roll_step,shot_direction,face_weight,ball)
	if finish > 0.0:
		blend_arm(base,pose,author,weight)
	open_strike_hand(base,author,weight*lerpf(0.70,0.94,smoothstep(0.12,0.85,extension)))
	return roll

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

static func blend_arm(base: Array, target: Array, author: RefCounted, weight: float, side := "r") -> void:
	# Fade local joint rotations so the IK pole cannot twist the elbow as the wrist comes to rest.
	for joint in ["upperarm","lowerarm","hand"]:
		var index: int = author.rig.find_bone(joint+"_"+side)
		var from: Quaternion = base[index].basis.get_rotation_quaternion()
		var to: Quaternion = target[index].basis.get_rotation_quaternion()
		base[index].basis = Basis(from.slerp(to,weight))

static func recover_same_side_arm(pose: Array, finish: Array, author: RefCounted, weight: float) -> void:
	blend_arm(pose,finish,author,weight)
	var hip: Vector3 = author.point(pose,"thigh_r")
	var left_hip: Vector3 = author.point(pose,"thigh_l")
	var outside := (hip-left_hip).slide(Vector3.UP).normalized()
	# Ease the hanging arm forward beside the hip as the body straightens.
	var arc := sin(PI*weight)
	author.rotate_world(pose,"upperarm_r",outside,0.26*arc)
	var forward := Vector3.UP.cross(outside)
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var elbow: Vector3 = author.point(pose,"lowerarm_r")
	var wrist: Vector3 = author.point(pose,"hand_r")
	var fingertips: Vector3 = author.point(pose,"middle_03_r")
	var knee: Vector3 = author.point(pose,"calf_r")
	var thigh_axis := (knee-hip).slide(outside)
	var flank_angle := 0.0
	var thigh_angle := 0.0
	for point: Vector3 in [elbow.lerp(wrist,0.5),wrist,wrist.lerp(fingertips,0.6),fingertips]:
		var height := clampf((point.y-hip.y)/maxf(0.10,shoulder.y-hip.y),0.0,1.0)
		var flank := hip.lerp(shoulder,height)
		var offset := point-flank
		var side_gap := offset.dot(outside)
		var beside_body := 1.0-smoothstep(0.12,0.28,offset.dot(forward))
		var lever := maxf(0.18,shoulder.y-point.y)
		flank_angle = maxf(flank_angle,(0.055-side_gap)*beside_body/lever)

		var along_thigh := clampf((point-hip).dot(thigh_axis)/maxf(0.001,thigh_axis.length_squared()),0.0,1.0)
		var from_thigh := point-hip.lerp(knee,along_thigh)
		var radius := lerpf(0.19,0.13,along_thigh)
		var depth := from_thigh.slide(outside).length()
		var near_thigh := 1.0-smoothstep(radius,radius+0.06,depth)
		var thigh_gap := sqrt(maxf(0.0,pow(radius+0.04,2.0)-depth*depth))
		thigh_angle = maxf(thigh_angle,(thigh_gap-from_thigh.dot(outside))*near_thigh/lever)
	# Hold the leg clearance through the return even after the wrist clears the ribs.
	var flank_turn := minf(flank_angle,0.25)*smoothstep(0.0,0.24,arc)
	var thigh_turn := minf(thigh_angle,0.46)*smoothstep(0.0,0.045,1.0-weight)
	author.rotate_world(pose,"upperarm_r",forward,-maxf(flank_turn,thigh_turn))

static func hip_finish(pose: Array, author: RefCounted, crosscourt: bool, clearance := 0.06) -> Vector3:
	var hip: Vector3 = author.point(pose,"thigh_r" if crosscourt else "thigh_l")
	if not crosscourt: return hip+Vector3(clearance,0.02,0.09)
	var left_hip: Vector3 = author.point(pose,"thigh_l")
	var outside := (hip-left_hip).slide(Vector3.UP).normalized()
	var forward := Vector3.UP.cross(outside)
	return hip+outside*(clearance+0.045)-forward*0.30+Vector3.UP*0.08

static func finish_elbow_pole(same_side: bool) -> Vector3:
	return Vector3(-0.85,-0.08,-0.09) if same_side else Vector3(-0.85,0.04,-0.33)

static func follow_through_target(pose: Array, author: RefCounted, shoulder: Vector3, contact: Vector3, hip: Vector3, progress: float, same_side: bool, compact_finish: float) -> Vector3:
	var start := contact-shoulder
	var end := hip-shoulder
	var sweep_direction := Vector3(-0.22,-0.32,0.87) if same_side else Vector3(-0.10,-0.12,1.0)
	var forward := sweep_direction.lerp(Vector3(-0.07,-0.60,0.79),compact_finish).normalized()
	# Carry the wrist around the shoulder instead of cutting across its reach.
	var from := start.normalized().slerp(forward,progress)
	var toward := forward.slerp(end.normalized(),progress)
	var direction := from.slerp(toward,progress)
	var radius := lerpf(start.length(),end.length(),progress)+lerpf(0.06,-0.09,compact_finish)*sin(PI*progress)
	var across: Vector3 = author.point(pose,"upperarm_l")-shoulder
	var up: Vector3 = author.point(pose,"neck_01")-author.point(pose,"spine_03")
	var chest_forward := across.cross(up).normalized()
	var clearance := lerpf(0.08 if same_side else 0.15,0.035,compact_finish)*smoothstep(0.08,0.58,progress)*(1.0-smoothstep(0.63,1.0,progress))
	# Carry the arm forward of the ribs while preserving reach and both endpoints.
	var offset := (direction*radius+chest_forward*clearance).normalized()*radius
	var target := shoulder+offset
	if same_side:
		# Keep the wrist outside the ribs as the chest turns and pitches forward.
		var outside := -across.normalized()
		var flank := shoulder.lerp(hip,progress)
		var side_gap := (target-flank).dot(outside)
		var guide := smoothstep(0.08,0.48,progress)*(1.0-smoothstep(0.78,1.0,progress))
		target += outside*maxf(0.0,0.055-side_gap)*guide
	return target

static func compact_finish_weight(target: Vector3, origin: Vector3, same_side: bool) -> float:
	var slope := absf(target.x-origin.x)/maxf(target.z-origin.z,0.1)
	return 1.0-smoothstep(0.30,0.55,slope) if same_side else 1.0-smoothstep(0.065,0.27,slope)

static func finish_palm_weight(target: Vector3, origin: Vector3, cross_body: bool) -> float:
	if cross_body: return 1.0
	var lateral := absf(target.x-origin.x)/maxf(target.z-origin.z,0.1)
	return smoothstep(0.045,0.13,lateral)

static func roll_finish_palm(pose: Array, author: RefCounted, amount: float, follow: float, cross_body: bool, previous_roll := 0.0, roll_step := INF, shot_direction := Vector3.ZERO, face_weight := 0.0, ball := Vector3.ZERO) -> float:
	var weight := amount*smoothstep(0.05,0.84,follow)
	if weight <= 0.0 and face_weight <= 0.0: return 0.0
	var wrist: Vector3 = author.point(pose,"hand_r")
	var knuckle: Vector3 = author.point(pose,"middle_01_r")
	var axis := (knuckle-wrist).normalized()
	var pinky: Vector3 = author.point(pose,"pinky_01_r")
	var thumb: Vector3 = author.point(pose,"thumb_01_r")
	var edge := (pinky-thumb).slide(axis).normalized()
	var pinky_target := (Vector3.DOWN if cross_body else Vector3.UP).slide(axis)
	if not cross_body:
		# Carry the pinky out as the hand approaches vertical so the thumb does not flip.
		var outside: Vector3 = (author.point(pose,"upperarm_r")-author.point(pose,"upperarm_l")).normalized()
		pinky_target += outside.slide(axis)*0.40*(1.0-smoothstep(0.18,0.52,pinky_target.length()))
	var roll := edge.signed_angle_to(pinky_target.normalized(),axis)
	# The two edges have no meaningful height difference when the hand points straight down.
	var visibility := smoothstep(0.015,0.10,pinky_target.length()) if cross_body else smoothstep(0.10,0.34,pinky_target.length())
	var target_roll := roll*weight*visibility
	if face_weight > 0.0:
		var index: Vector3 = author.point(pose,"index_01_r")
		var palm_normal := axis.cross(pinky-index).normalized()
		var toward_ball := (ball-wrist.lerp(knuckle,0.75)).normalized().slide(axis)
		var shot_normal := shot_direction.slide(axis)
		var strike_normal := shot_normal.normalized().lerp(toward_ball.normalized(),smoothstep(0.06,0.24,toward_ball.length()))
		var face_roll := palm_normal.signed_angle_to(strike_normal.normalized(),axis)
		target_roll = lerp_angle(target_roll,face_roll,face_weight*smoothstep(0.04,0.25,strike_normal.length()))
	var applied := rotate_toward(previous_roll,target_roll,roll_step) if is_finite(roll_step) else target_roll
	author.rotate_world(pose,"hand_r",axis,applied)
	return applied

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
