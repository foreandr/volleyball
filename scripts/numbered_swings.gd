extends RefCounted

# Deterministic pose envelopes give each number the same motion on every visit.
static func make(source: Animation, number: int, rig: Skeleton3D=null) -> Animation:
	var clip := source.duplicate() as Animation
	var rng := RandomNumberGenerator.new()
	rng.seed=524287*number
	var hit := int(source.get_meta("swing_hit_frame"))
	var offset_frames := int(source.get_meta("swing_frame_offset",0))
	var peak := offset_frames+rng.randf_range(19.,28.)
	var release := rng.randf_range(3.,7.)
	for joint in ["upperarm_r","lowerarm_r","hand_r"]:
		var path := NodePath("Armature/Skeleton3D:"+str(joint))
		var track := source.find_track(path,Animation.TYPE_ROTATION_3D)
		if track<0: continue
		var width := Vector3(40,54,40) if joint=="upperarm_r" else Vector3(30,18,22)
		if joint=="hand_r": width=Vector3.ZERO # The hand inherits the spin-specific, constrained wrist track.
		var draw := rotation(rng,width)
		var drive := rotation(rng,width*.58)
		rotation(rng,width*1.12) # Preserve the seeded draw and drive for the next joint.
		clip.remove_track(clip.find_track(path,Animation.TYPE_ROTATION_3D))
		var out := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(out,path)
		for frame in range(ceili(source.length*60.)+1):
			var time := minf(frame/60.,source.length)
			var gather := smoothstep(offset_frames+10.,peak,frame)*(1.-smoothstep(peak,hit-release,frame))
			var whip := smoothstep(peak-2.,hit-release,frame)*(1.-smoothstep(hit-release,hit-1.,frame))
			var offset := Quaternion.IDENTITY.slerp(draw,gather)*Quaternion.IDENTITY.slerp(drive,whip)
			clip.rotation_track_insert_key(out,time,source.rotation_track_interpolate(track,time)*offset)
	if rig!=null and hit>offset_frames+16:
		align_draw_palm(clip,rig,offset_frames,hit)
	if hit>=0:
		var hand := clip.find_track(NodePath("Armature/Skeleton3D:hand_r"),Animation.TYPE_ROTATION_3D)
		if hand>=0:
			for key in clip.track_get_key_count(hand):
				var relative_frame := clip.track_get_key_time(hand,key)*60.-hit
				var weight := smoothstep(-9.,-2.,relative_frame)*(1.-smoothstep(0.,11.,relative_frame))
				if weight>0.:
					var rotation: Quaternion=clip.track_get_key_value(hand,key)
					clip.track_set_key_value(hand,key,rotation*Quaternion(Vector3.BACK,deg_to_rad(75.)*weight))
	return clip

static func align_draw_palm(clip: Animation, rig: Skeleton3D, start: int, hit: int) -> void:
	var session=preload("res://scripts/animation_edit_session.gd").new(clip,rig)
	var forearm := rig.find_bone("lowerarm_r")
	var track := clip.find_track(NodePath("Armature/Skeleton3D:lowerarm_r"),Animation.TYPE_ROTATION_3D)
	var point := func(bone: String) -> Vector3: return rig.get_bone_global_pose(rig.find_bone(bone)).origin
	for f in range(start+9,hit-2):
		session.sample(f)
		preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
		var wrist: Vector3=point.call("hand_r")
		var axis: Vector3=point.call("lowerarm_r").direction_to(wrist)
		var fingers := wrist.direction_to(point.call("middle_01_r"))
		var edge: Vector3=point.call("pinky_01_r")-point.call("index_01_r")
		var normal := fingers.cross(edge).normalized().slide(axis)
		var down := Vector3.DOWN.slide(axis)
		var can_roll := minf(normal.length_squared(),down.length_squared())>.00001
		var weight := smoothstep(start+8.,start+17.,f)*(1.-smoothstep(hit-9.,hit-2.,f))
		var roll := normal.signed_angle_to(down,axis)*weight if can_roll else 0.
		var local_axis := rig.get_bone_global_pose(forearm).basis.inverse()*axis
		var rotation := rig.get_bone_pose_rotation(forearm)*Quaternion(local_axis.normalized(),roll)
		clip.rotation_track_insert_key(track,f/60.,rotation.normalized())
		rig.set_bone_pose_rotation(forearm,rotation.normalized())
		fingers=wrist.direction_to(point.call("middle_01_r"))
		edge=point.call("pinky_01_r")-point.call("index_01_r")
		normal=fingers.cross(edge).normalized()
		if normal.y>-.15 and fingers.slide(Vector3.UP).length()>.001:
			var hand := rig.find_bone("hand_r")
			var hand_axis := rig.get_bone_global_pose(hand).basis.inverse()*fingers
			var residual := normal.signed_angle_to(Vector3.DOWN.slide(fingers),fingers)
			var hand_rotation := rig.get_bone_pose_rotation(hand)*Quaternion(hand_axis.normalized(),clampf(residual,-.62,.62)*weight)
			clip.rotation_track_insert_key(session.rotation_tracks[hand],f/60.,hand_rotation.normalized())

static func rotation(rng: RandomNumberGenerator,width: Vector3) -> Quaternion:
	var angles := Vector3(rng.randf_range(-1.,1.),rng.randf_range(-1.,1.),rng.randf_range(-1.,1.))*width
	return Quaternion.from_euler(angles*PI/180.)
