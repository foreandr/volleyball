extends RefCounted

const SWING_NAME := "06 Low Bow"

static func apply(pose: Array, author: RefCounted, ball: Vector3, weight: float, extension: float, follow: float, draw_progress: float) -> void:
	var shoulder: Vector3 = author.point(pose,"upperarm_r")
	var draw := Vector3(0.04,0.40,0.08).lerp(Vector3(0.15,0.05,-0.12),draw_progress)
	var wrist_target := ball-(ball-shoulder).normalized()*0.06
	var target := (shoulder+draw).lerp(wrist_target,extension)
	target += Vector3(-0.05,0.14,-0.10)*sin(PI*extension)
	var finish := smoothstep(0.20,1.0,follow)
	target = target.lerp(shoulder+Vector3(0.24,-0.35,0.42),finish)
	var elbow_pole := Vector3(-1.0,0.16,-0.84).lerp(Vector3(-0.75,0.38,-0.28),smoothstep(0.62,1.0,extension))
	var elbow_limit := lerpf(112.0,158.0,smoothstep(0.29,0.98,extension))
	elbow_limit = lerpf(elbow_limit,145.0,finish)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",target,elbow_pole,weight,elbow_limit)
	drop_low_bow_elbow(pose,author,weight*draw_progress*(1.0-smoothstep(0.0,0.48,extension)))

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
