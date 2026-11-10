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
var entry_pose: Array[Transform3D] = []
var ready: Array[Transform3D] = []
var clasp: Array[Transform3D] = []

func plan(actor: Node3D, path: Callable, time: float, end: float, clip: Animation) -> bool:
	if active: return true
	var lookahead := minf(time+Dive.WINDUP,end)
	if lookahead <= time: return false
	var first: Vector3 = path.call(time)
	var last: Vector3 = path.call(lookahead)
	for low_save in [false,true]:
		var height := PANCAKE_HEIGHT if low_save else DIVE_HEIGHT
		if first.y <= height or last.y > height: continue
		var low := time
		var high := lookahead
		for iteration in range(12):
			var middle := (low+high)*0.5
			var point: Vector3 = path.call(middle)
			if point.y > height: low = middle
			else: high = middle
		if high-time < MIN_WINDUP: continue
		var point: Vector3 = path.call(high)
		var offset := (point-actor.position).slide(Vector3.UP)
		var distance := offset.length()
		var minimum := 1.80 if low_save else 1.28
		var toward_speed := (first-point).dot(offset.normalized())/maxf(high-time,0.001)
		var extra := clampf(toward_speed*0.035,0.0,0.32)
		var maximum := (2.55 if low_save else 1.88)+extra
		if distance < minimum or distance > maximum or offset.normalized().dot(actor.basis.z)<0.62: continue
		pancake = low_save
		active = true
		aim = point
		start = actor.position
		heading = offset.normalized()
		contact_time = high
		start_time = time
		start_yaw = actor.rotation.y
		entry_pose.clear()
		var rig: Skeleton3D = actor.skeleton
		for bone in rig.get_bone_count(): entry_pose.append(rig.get_bone_pose(bone))
		ready = sample_clip(actor.skeleton,clip,0.0)
		clasp = sample_clip(actor.skeleton,clip,float(clip.get_meta("contact_time")))
		return true
	return false

func sample(actor: Node3D, time: float, release: float) -> void:
	var pose_time := Dive.WINDUP+(time-contact_time)
	if time < contact_time:
		pose_time = Dive.WINDUP*clampf(inverse_lerp(start_time,contact_time,time),0.0,1.0)
	actor.pose_reception_dive(ready,clasp,start,heading,pose_time,aim,release-contact_time+Dive.WINDUP,pancake)
	var entry_weight := smoothstep(0.0,minf(ENTRY_BLEND,contact_time-start_time),time-start_time)
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
