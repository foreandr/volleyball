extends RefCounted
const FPS := 60.0
const PREFIX := "Armature/Skeleton3D:"
var revision := 0
var source: Animation
var rig: Skeleton3D
var edits: Dictionary = {}
var position_edits: Dictionary = {}
var rotation_tracks: Dictionary = {}
var position_tracks: Dictionary = {}
var last_frame := 0
var sample_times := PackedFloat64Array()
var frame_rate := FPS

func _init(clip: Animation, skeleton: Skeleton3D) -> void:
	rig = skeleton
	replace_source(clip)

func replace_source(clip: Animation) -> void:
	source = clip
	revision += 1
	edits.clear()
	position_edits.clear()
	var frame_count := int(source.get_meta("editor_frame_count",0))
	last_frame = frame_count-1 if frame_count >= 2 else ceili(source.length*FPS)
	sample_times=source.get_meta("editor_sample_times",PackedFloat64Array())
	frame_rate = last_frame/source.length if frame_count >= 2 else FPS
	for bone in rig.get_bone_count():
		var path := NodePath(PREFIX+rig.get_bone_name(bone))
		rotation_tracks[bone] = source.find_track(path,Animation.TYPE_ROTATION_3D)
		position_tracks[bone] = source.find_track(path,Animation.TYPE_POSITION_3D)

func time_at(frame: float) -> float:
	if not sample_times.is_empty():
		var index := clampf(frame,0,last_frame)
		var lo := floori(index)
		return lerpf(sample_times[lo],sample_times[mini(lo+1,last_frame)],index-lo)
	return clampf(frame/frame_rate,0,source.length)

func frame_at_time(time: float) -> float:
	if sample_times.is_empty(): return time*frame_rate
	var hi := clampi(sample_times.bsearch(time),1,last_frame)
	return hi-1+clampf(inverse_lerp(sample_times[hi-1],sample_times[hi],time),0.,1.)

func source_rotation(bone: int, frame: float) -> Quaternion:
	var track: int = rotation_tracks[bone]
	return source.rotation_track_interpolate(track,time_at(frame)) if track >= 0 else rig.get_bone_rest(bone).basis.get_rotation_quaternion()

func offset_at(bone: int, frame: float) -> Quaternion:
	var keys: Dictionary = edits.get(str(rig.get_bone_name(bone)),{})
	var bounded := clampf(frame,0.0,float(last_frame))
	var before := floori(bounded)
	var a: Quaternion = keys.get(before,Quaternion.IDENTITY)
	var b: Quaternion = keys.get(mini(before+1,last_frame),Quaternion.IDENTITY)
	return a.slerp(b,bounded-before).normalized()

func source_position(bone: int, frame: float) -> Vector3:
	var track: int = position_tracks[bone]
	return source.position_track_interpolate(track,time_at(frame)) if track >= 0 else rig.get_bone_rest(bone).origin

func position_offset_at(bone: int, frame: float) -> Vector3:
	var keys: Dictionary = position_edits.get(str(rig.get_bone_name(bone)),{})
	var bounded := clampf(frame,0.0,float(last_frame))
	var before := floori(bounded)
	var a: Vector3 = keys.get(before,Vector3.ZERO)
	var b: Vector3 = keys.get(mini(before+1,last_frame),Vector3.ZERO)
	return a.lerp(b,bounded-before)

func state() -> Dictionary:
	return {"source":source,"rotations":edits.duplicate(true),"positions":position_edits.duplicate(true)}

func restore(value: Dictionary) -> void:
	if value.has("source"): replace_source(value.source)
	revision += 1
	edits = value.rotations.duplicate(true)
	position_edits = value.positions.duplicate(true)

func propagate(bones: Array[int], source_frame: int, first: int, last: int) -> void:
	revision += 1
	for bone in bones:
		var name_ := str(rig.get_bone_name(bone))
		var rotation := source_rotation(bone,source_frame)*offset_at(bone,source_frame)
		var position := source_position(bone,source_frame)+position_offset_at(bone,source_frame)
		var rotations := {}
		var positions := {}
		var moved := false
		# Sample the untouched timeline first so propagation cannot change earlier frames.
		for frame in range(last_frame+1):
			rotations[frame] = offset_at(bone,frame)
			positions[frame] = position_offset_at(bone,frame)
		for frame in range(maxi(0,first),mini(last,last_frame)+1):
			rotations[frame] = (source_rotation(bone,frame).inverse()*rotation).normalized()
			positions[frame] = position-source_position(bone,frame)
		for value in positions.values():
			if value.length_squared() > 0.0000000001: moved = true; break
		edits[name_] = rotations
		if moved: position_edits[name_] = positions

func sample(frame: float) -> void:
	for bone in rig.get_bone_count():
		var position: int = position_tracks[bone]
		rig.set_bone_pose_position(bone,source_position(bone,frame)+position_offset_at(bone,frame))
		rig.set_bone_pose_rotation(bone,(source_rotation(bone,frame)*offset_at(bone,frame)).normalized())
	rig.force_update_all_bone_transforms()

func set_offset(bone: int, frame: int, value: Quaternion) -> void:
	revision += 1
	var name_ := str(rig.get_bone_name(bone))
	if not edits.has(name_): edits[name_] = {}
	edits[name_][clampi(frame,0,last_frame)] = value.normalized()

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
		for tick in range(ceili(copy.length*FPS)+1):
			var time := minf(copy.length,tick/FPS)
			var frame := frame_at_time(time)
			copy.rotation_track_insert_key(track,time,(source_rotation(bone,frame)*offset_at(bone,frame)).normalized())
	for name_ in position_edits:
		var bone := rig.find_bone(name_)
		var path := NodePath(PREFIX+name_)
		var track := copy.find_track(path,Animation.TYPE_POSITION_3D)
		if track >= 0: copy.remove_track(track)
		track = copy.add_track(Animation.TYPE_POSITION_3D)
		copy.track_set_path(track,path)
		for tick in range(ceili(copy.length*FPS)+1):
			var time := minf(copy.length,tick/FPS)
			var frame := frame_at_time(time)
			copy.position_track_insert_key(track,time,source_position(bone,frame)+position_offset_at(bone,frame))
	return copy
