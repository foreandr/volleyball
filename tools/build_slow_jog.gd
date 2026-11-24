extends SceneTree

# A compact jog retains the running footfall pattern with less knee lift,
# torso bounce and arm drive. Each joint moves around its own cycle midpoint.
func _initialize() -> void:
	var library: AnimationLibrary=preload("res://assets/animations/UAL1_Standard.glb")
	var clip: Animation=library.get_animation("Jog_Fwd").duplicate(true)
	for track in clip.get_track_count():
		var count := clip.track_get_key_count(track)
		if count<2: continue
		var kind := clip.track_get_type(track)
		if kind==Animation.TYPE_ROTATION_3D:
			var center: Quaternion=clip.track_get_key_value(track,0)
			for key in range(1,count):
				center=center.slerp(clip.track_get_key_value(track,key),1./(key+1))
			for key in count:
				clip.track_set_key_value(track,key,center.slerp(clip.track_get_key_value(track,key),.70))
		elif kind==Animation.TYPE_POSITION_3D:
			var center := Vector3.ZERO
			for key in count: center+=Vector3(clip.track_get_key_value(track,key))/count
			for key in count: clip.track_set_key_value(track,key,center.lerp(clip.track_get_key_value(track,key),.72))
	clip.resource_name="Slow jog"
	quit(ResourceSaver.save(clip,"res://assets/animations/slow_jog.tres"))
