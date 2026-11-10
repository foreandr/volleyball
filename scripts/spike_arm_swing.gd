extends RefCounted

const SWING_NAME := "06 Low Bow"

static func apply(pose: Array, author: RefCounted, ball: Vector3, weight: float, extension: float, follow: float, draw_progress: float, arm_lift: float, line_weight: float) -> void:
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw := Vector3(0.04,0.40,0.08).lerp(Vector3(0.15,0.05,-0.12),draw_progress)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06
	var raised_draw := draw.lerp(Vector3(0.04,0.40,0.22),arm_lift)
	var target := (shoulder+raised_draw).lerp(wrist_target,extension)
	target += Vector3(-0.05,0.14,-0.10)*sin(PI*extension)
	var finish := smoothstep(0.20,1.0,follow)
	target = target.lerp(shoulder+Vector3(0.24,-0.35,0.42),finish)
	var elbow_pole := Vector3(-1.0,0.16,-0.84).lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,158.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,145.0,finish)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,weight,elbow_limit)
	drop_low_bow_elbow(pose,author,weight*draw_progress*(1.0-arm_lift)*(1.0-smoothstep(0.0,0.48,extension)))
	var wrist: Vector3 = author.point(pose,"hand_r")
	var axis: Vector3 = (author.point(pose,"middle_01_r")-wrist).normalized()
	var pinky: Vector3 = author.point(pose,"pinky_01_r")
	var thumb: Vector3 = author.point(pose,"thumb_01_r")
	var edge := (pinky-thumb).slide(axis).normalized()
	var down := Vector3.DOWN.slide(axis)
	var target_edge := down.normalized().rotated(axis,PI*(1.0-line_weight))
	var roll := edge.signed_angle_to(target_edge,axis)
	var roll_weight := weight*smoothstep(0.25,0.85,extension)*(1.0-0.65*follow)*smoothstep(0.0,0.30,down.length())
	author.rotate_world(pose,"hand_r",axis,roll*roll_weight)

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
