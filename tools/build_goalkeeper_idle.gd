extends SceneTree
var src: Skeleton3D
var dst: Skeleton3D
var mapping := {"pelvis":"Hips","spine_01":"Spine","spine_02":"Spine1","spine_03":"Spine2","neck_01":"Neck","Head":"Head"}

func _initialize() -> void:
	var imported := preload("res://assets/animations/source/goalkeeper_idle.fbx").instantiate()
	src = imported.find_child("Skeleton3D",true,false)
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	dst = model.find_child("Skeleton3D",true,false)
	for side in ["l","r"]:
		var prefix := "Left" if side == "l" else "Right"
		for pair in [["clavicle","Shoulder"],["upperarm","Arm"],["lowerarm","ForeArm"],["hand","Hand"],["thigh","UpLeg"],["calf","Leg"],["foot","Foot"],["ball","ToeBase"]]: mapping[pair[0]+"_"+side] = prefix+pair[1]
		for finger in ["thumb","index","middle","ring","pinky"]:
			for segment in range(1,4): mapping["%s_%02d_%s" % [finger,segment,side]] = prefix+"Hand"+finger.capitalize()+str(segment)
	var names := {}
	for bone in src.get_bone_count():
		var name_ := str(src.get_bone_name(bone)).get_slice("_",1)
		names[name_] = bone
	var source_player: AnimationPlayer = imported.find_child("AnimationPlayer",true,false)
	var source := source_player.get_animation(source_player.get_animation_list()[0])
	var clip := Animation.new()
	clip.resource_name = "Goalkeeper Idle"
	clip.length = source.length
	clip.loop_mode = Animation.LOOP_LINEAR
	var positions := []
	var rotations := []
	for bone in dst.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:"+dst.get_bone_name(bone))
		var p := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(p,path)
		positions.append(p)
		var q := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(q,path)
		rotations.append(q)
	var order: Array[int] = []
	for bone in dst.get_bone_count(): hierarchy_order(bone,order)
	var frames := ceili(source.length*30)
	for frame in range(frames+1):
		var time := minf(source.length,float(frame)/30.0)
		var src_pose := sample(src,source,"Skeleton3D:",time)
		var local_pose: Array = []
		for bone in dst.get_bone_count(): local_pose.append(dst.get_bone_rest(bone))
		for bone in order:
			var name_ := str(dst.get_bone_name(bone))
			if not mapping.has(name_) or not names.has(mapping[name_]): continue
			var source_bone: int = names[mapping[name_]]
			var source_rest := src.get_bone_global_rest(source_bone).basis.orthonormalized()
			var source_now := global_pose(src,src_pose,source_bone).basis.orthonormalized()
			var desired := source_now*source_rest.inverse()*dst.get_bone_global_rest(bone).basis.orthonormalized()
			var parent := dst.get_bone_parent(bone)
			var parent_basis := Basis.IDENTITY if parent < 0 else global_pose(dst,local_pose,parent).basis
			local_pose[bone].basis = (parent_basis.inverse()*desired).orthonormalized()
			if name_ == "pelvis":
				var offset := global_pose(src,src_pose,source_bone).origin-src.get_bone_global_rest(source_bone).origin
				local_pose[bone].origin += parent_basis.inverse()*(offset*0.951)
		for bone in dst.get_bone_count():
			clip.position_track_insert_key(positions[bone],time,local_pose[bone].origin)
			clip.rotation_track_insert_key(rotations[bone],time,local_pose[bone].basis.get_rotation_quaternion())
	clip.set_meta("source","Goalkeeper Idle.fbx supplied by user")
	print("Goalkeeper idle retargeted: ",ResourceSaver.save(clip,"res://assets/animations/goalkeeper_idle.tres"))
	imported.free()
	model.free()
	quit()

func sample(rig: Skeleton3D, clip: Animation, prefix: String, time: float) -> Array:
	var pose: Array = []
	for bone in rig.get_bone_count():
		var local := rig.get_bone_rest(bone)
		var path := NodePath(prefix+rig.get_bone_name(bone))
		var p := clip.find_track(path,Animation.TYPE_POSITION_3D)
		var q := clip.find_track(path,Animation.TYPE_ROTATION_3D)
		if p >= 0: local.origin = clip.position_track_interpolate(p,time)
		if q >= 0: local.basis = Basis(clip.rotation_track_interpolate(q,time))
		pose.append(local)
	return pose

func global_pose(rig: Skeleton3D, pose: Array, bone: int) -> Transform3D:
	var parent := rig.get_bone_parent(bone)
	return pose[bone] if parent < 0 else global_pose(rig,pose,parent)*pose[bone]

func hierarchy_order(bone: int, order: Array[int]) -> void:
	if bone in order: return
	var parent := dst.get_bone_parent(bone)
	if parent >= 0: hierarchy_order(parent,order)
	order.append(bone)
