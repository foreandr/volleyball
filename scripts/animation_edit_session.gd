extends RefCounted
const FPS := 60.0
const PREFIX := "Armature/Skeleton3D:"
var source: Animation
var rig: Skeleton3D
var edits: Dictionary = {}
var rotation_tracks: Dictionary = {}
var position_tracks: Dictionary = {}
var last_frame := 0

func _init(clip: Animation, skeleton: Skeleton3D) -> void:
	source = clip
	rig = skeleton
	last_frame = ceili(source.length*FPS)
	for bone in rig.get_bone_count():
		var path := NodePath(PREFIX+rig.get_bone_name(bone))
		rotation_tracks[bone] = source.find_track(path,Animation.TYPE_ROTATION_3D)
		position_tracks[bone] = source.find_track(path,Animation.TYPE_POSITION_3D)

func time_at(frame: float) -> float:
	return clampf(frame/FPS,0,source.length)

func source_rotation(bone: int, frame: float) -> Quaternion:
	var track: int = rotation_tracks[bone]
	return source.rotation_track_interpolate(track,time_at(frame)) if track >= 0 else rig.get_bone_rest(bone).basis.get_rotation_quaternion()

func offset_at(bone: int, frame: float) -> Quaternion:
	var name_ := str(rig.get_bone_name(bone))
	if not edits.has(name_): return Quaternion.IDENTITY
	var keys: Dictionary = edits[name_]
	var frames: Array = keys.keys()
	if not keys.has(0): frames.append(0)
	if not keys.has(last_frame): frames.append(last_frame)
	frames.sort()
	var before := 0
	var after := last_frame
	for key in frames:
		if key <= frame: before = key
		if key >= frame:
			after = key
			break
	var a: Quaternion = keys.get(before,Quaternion.IDENTITY)
	var b: Quaternion = keys.get(after,Quaternion.IDENTITY)
	return a if before == after else a.slerp(b,smoothstep(float(before),float(after),frame)).normalized()

func sample(frame: float) -> void:
	for bone in rig.get_bone_count():
		var position: int = position_tracks[bone]
		rig.set_bone_pose_position(bone,source.position_track_interpolate(position,time_at(frame)) if position >= 0 else rig.get_bone_rest(bone).origin)
		rig.set_bone_pose_rotation(bone,(source_rotation(bone,frame)*offset_at(bone,frame)).normalized())
	rig.force_update_all_bone_transforms()

func set_offset(bone: int, frame: int, value: Quaternion) -> void:
	var name_ := str(rig.get_bone_name(bone))
	if not edits.has(name_): edits[name_] = {}
	edits[name_][clampi(frame,0,last_frame)] = value.normalized()
	if frame == 0 or frame == last_frame:
		edits[name_][0] = value.normalized()
		edits[name_][last_frame] = value.normalized()

func set_rotation(bone: int, frame: int, value: Quaternion) -> void:
	set_offset(bone,frame,source_rotation(bone,frame).inverse()*value)

func bake() -> Animation:
	var copy := source.duplicate(true) as Animation
	for name_ in edits:
		var bone := rig.find_bone(name_)
		var path := NodePath(PREFIX+name_)
		var track := copy.find_track(path,Animation.TYPE_ROTATION_3D)
		if track >= 0: copy.remove_track(track)
		track = copy.add_track(Animation.TYPE_ROTATION_3D)
		copy.track_set_path(track,path)
		for frame in range(last_frame+1):
			copy.rotation_track_insert_key(track,time_at(frame),(source_rotation(bone,frame)*offset_at(bone,frame)).normalized())
	return copy
