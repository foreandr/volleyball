extends RefCounted

const Dive = preload("res://scripts/forward_reception_dive.gd")
const Flight = preload("res://scripts/pass_flight.gd")
const PANCAKE_HEIGHT := Flight.FLOOR+0.045
const DIVE_HEIGHT := 0.46
const MIN_WINDUP := 0.15
const ENTRY_BLEND := 0.11
var active := false
var pancake := false
var aim: Vector3
var start: Vector3
var heading: Vector3
var contact_time: float
var start_time: float
var start_yaw: float
var travel_scale := 1.0
var entry_blend := ENTRY_BLEND
var tracks_platform := false
var platform_aim := Vector3.ZERO
var wide_arm := ""
var entry_pose: Array[Transform3D] = []
var ready: Array[Transform3D] = []
var clasp: Array[Transform3D] = []

func plan(actor: Node3D, path: Callable, time: float, end: float, clip: Animation, quick_save := false, allow_pancake := true, pancake_requires_chase := false, approach_velocity := Vector3.ZERO, emergency := false) -> bool:
	if active: return true
	var lookahead := minf(time+Dive.WINDUP,end)
	if lookahead <= time: return false
	var first: Vector3 = path.call(time)
	var last: Vector3 = path.call(lookahead)
	for low_save in [false,true]:
		if low_save and not allow_pancake: continue
		var height := PANCAKE_HEIGHT if low_save else DIVE_HEIGHT
		if first.y <= height or last.y > height: continue
		var low := time
		var high := lookahead
		for iteration in range(12):
			var middle := (low+high)*0.5
			var point: Vector3 = path.call(middle)
			if point.y > height: low = middle
			else: high = middle
		var point: Vector3 = path.call(high)
		var offset := (point-actor.position).slide(Vector3.UP)
		var distance := offset.length()
		var momentum := smoothstep(2.6,7.7,approach_velocity.dot(offset.normalized())) if quick_save and not low_save else 0.0
		var windup := lerpf(0.085,0.060,momentum) if quick_save else MIN_WINDUP
		if high-time < (0.045 if emergency else windup): continue
		if low_save and pancake_requires_chase and (point-first).slide(Vector3.UP).dot(offset.normalized()) <= 0.35*(high-time): continue
		var local := actor.basis.inverse()*offset
		var wide: bool = quick_save and not low_save and distance > 1.38 and absf(local.x) > absf(local.z)*0.64
		var minimum := (0.58 if low_save else 0.72) if quick_save else (1.80 if low_save else 1.28)
		var toward_speed := (first-point).dot(offset.normalized())/maxf(high-time,0.001)
		var extra := clampf(toward_speed*0.035,0.0,0.32)
		var maximum := (2.55 if low_save else 1.88)+extra
		if wide: maximum = 2.85+extra
		maximum += 0.80*momentum
		if emergency: maximum += 0.48
		var facing_limit := -0.45 if emergency else (-0.12 if wide else (0.30 if quick_save else 0.62))
		if distance < minimum or distance > maximum or offset.normalized().dot(actor.basis.z) < facing_limit: continue
		pancake = low_save
		wide_arm = actor.animation_side("l" if local.x > 0.0 else "r") if wide else ""
		active = true
		aim = point
		platform_aim = point
		start = actor.position
		heading = offset.normalized() if not wide else actor.basis.z.slide(Vector3.UP).normalized()
		contact_time = high
		start_time = time
		start_yaw = actor.rotation.y
		tracks_platform = quick_save and not low_save
		var reach_ahead := 0.72 if tracks_platform else 0.40
		travel_scale = clampf((distance-reach_ahead)/(1.22 if low_save else 0.74),0.18,lerpf(1.18,2.65,momentum)) if quick_save else 1.0
		if wide: travel_scale = clampf((distance-0.76)/0.78,0.60,2.25+0.35*momentum)
		entry_blend = 0.075 if quick_save else ENTRY_BLEND
		entry_pose.clear()
		var rig: Skeleton3D = actor.skeleton
		for bone in rig.get_bone_count(): entry_pose.append(rig.get_bone_pose(bone))
		ready = sample_clip(actor.skeleton,clip,0.0)
		clasp = sample_clip(actor.skeleton,clip,float(clip.get_meta("contact_time")))
		return true
	return false

func sample(actor: Node3D, time: float, release: float, intercept := Vector3.INF) -> void:
	var pose_time := Dive.WINDUP+(time-contact_time)
	if time < contact_time:
		pose_time = Dive.WINDUP*clampf(inverse_lerp(start_time,contact_time,time),0.0,1.0)
	if tracks_platform and intercept.is_finite(): platform_aim = intercept
	var target := platform_aim if tracks_platform else aim
	actor.pose_reception_dive(ready,clasp,start,heading,pose_time,target,release-contact_time+Dive.WINDUP,pancake,travel_scale,tracks_platform,wide_arm,(aim-start).slide(Vector3.UP).normalized())
	var entry_weight := smoothstep(0.0,minf(entry_blend,contact_time-start_time),time-start_time)
	if entry_weight < 1.0:
		var rig: Skeleton3D = actor.skeleton
		actor.rotation.y = lerp_angle(start_yaw,actor.rotation.y,entry_weight)
		for bone in entry_pose.size():
			var value := entry_pose[bone].interpolate_with(rig.get_bone_pose(bone),entry_weight)
			rig.set_bone_pose_position(bone,value.origin)
			rig.set_bone_pose_rotation(bone,value.basis.get_rotation_quaternion())

func finished(time: float) -> bool:
	return time-contact_time+Dive.WINDUP >= Dive.DURATION

static func sample_clip(rig: Skeleton3D, clip: Animation, time: float) -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		var value := rig.get_bone_pose(bone)
		var path := NodePath("Armature/Skeleton3D:"+rig.get_bone_name(bone))
		var position_track := clip.find_track(path,Animation.TYPE_POSITION_3D)
		var rotation_track := clip.find_track(path,Animation.TYPE_ROTATION_3D)
		if position_track >= 0: value.origin = clip.position_track_interpolate(position_track,time)
		if rotation_track >= 0: value.basis = Basis(clip.rotation_track_interpolate(rotation_track,time))
		pose.append(value)
	return pose

static func palm_center(actor: Node3D) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var wrist := rig.to_global(rig.get_bone_global_pose(rig.find_bone("hand_r")).origin)
	if wrist.y > 0.18: return Vector3.INF
	return wrist+actor.global_basis.z.normalized()*0.095+Vector3.UP*0.105
