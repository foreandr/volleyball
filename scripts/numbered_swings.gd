extends RefCounted

# Deterministic pose envelopes give each number the same motion on every visit.
static func make(source: Animation, number: int) -> Animation:
	var clip := source.duplicate() as Animation
	var rng := RandomNumberGenerator.new()
	rng.seed=524287*number
	var hit := int(source.get_meta("swing_hit_frame"))
	var peak := rng.randf_range(19.,28.)
	var release := rng.randf_range(3.,7.)
	for joint in ["upperarm_r","lowerarm_r","hand_r"]:
		var path := NodePath("Armature/Skeleton3D:"+str(joint))
		var track := source.find_track(path,Animation.TYPE_ROTATION_3D)
		if track<0: continue
		var width := Vector3(40,54,40) if joint=="upperarm_r" else Vector3(30,18,22)
		if joint=="hand_r": width=Vector3(22,24,18)
		var draw := rotation(rng,width)
		var drive := rotation(rng,width*.58)
		var finish := rotation(rng,width*1.12)
		clip.remove_track(clip.find_track(path,Animation.TYPE_ROTATION_3D))
		var out := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(out,path)
		for frame in range(ceili(source.length*60.)+1):
			var time := minf(frame/60.,source.length)
			var gather := smoothstep(10.,peak,frame)*(1.-smoothstep(peak,hit-release,frame))
			var whip := smoothstep(peak-2.,hit-release,frame)*(1.-smoothstep(hit-release,hit-1.,frame))
			var follow := smoothstep(hit+1.,hit+10.,frame)
			var offset := Quaternion.IDENTITY.slerp(draw,gather)*Quaternion.IDENTITY.slerp(drive,whip)*Quaternion.IDENTITY.slerp(finish,follow)
			clip.rotation_track_insert_key(out,time,source.rotation_track_interpolate(track,time)*offset)
	return clip

static func rotation(rng: RandomNumberGenerator,width: Vector3) -> Quaternion:
	var angles := Vector3(rng.randf_range(-1.,1.),rng.randf_range(-1.,1.),rng.randf_range(-1.,1.))*width
	return Quaternion.from_euler(angles*PI/180.)
