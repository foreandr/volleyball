extends RefCounted
const FPS := 60.0
const PREFIX := "Armature/Skeleton3D:"
var source: Animation
var rig: Skeleton3D
var edits: Dictionary = {}
var position_edits: Dictionary = {}
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

func source_position(bone: int, frame: float) -> Vector3:
	var track: int = position_tracks[bone]
	return source.position_track_interpolate(track,time_at(frame)) if track >= 0 else rig.get_bone_rest(bone).origin

func position_offset_at(bone: int, frame: float) -> Vector3:
	var name_ := str(rig.get_bone_name(bone))
	if not position_edits.has(name_): return Vector3.ZERO
	var keys: Dictionary = position_edits[name_]
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
	var a: Vector3 = keys.get(before,Vector3.ZERO)
	var b: Vector3 = keys.get(after,Vector3.ZERO)
	return a if before == after else a.lerp(b,smoothstep(float(before),float(after),frame))

func state() -> Dictionary:
	return {"rotations":edits.duplicate(true),"positions":position_edits.duplicate(true)}

func restore(value: Dictionary) -> void:
	edits = value.rotations.duplicate(true)
	position_edits = value.positions.duplicate(true)

func propagate(bones: Array[int], source_frame: int, first: int, last: int) -> void:
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
	for name_ in position_edits:
		var bone := rig.find_bone(name_)
		var path := NodePath(PREFIX+name_)
		var track := copy.find_track(path,Animation.TYPE_POSITION_3D)
		if track >= 0: copy.remove_track(track)
		track = copy.add_track(Animation.TYPE_POSITION_3D)
		copy.track_set_path(track,path)
		for frame in range(last_frame+1): copy.position_track_insert_key(track,time_at(frame),source_position(bone,frame)+position_offset_at(bone,frame))
	return copy
