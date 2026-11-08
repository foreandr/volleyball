extends SceneTree
const Author = preload("res://tools/animation_author.gd")
var src: Skeleton3D
var dst: Skeleton3D
var source: Animation
var sampler: RefCounted
var ready: RefCounted
var source_tracks := {}
var source_names := {}
var order: Array[int] = []
var mapping := {"pelvis":"Hips"}
var root_start := Vector3.ZERO
var scale_ := 0.951

func _initialize() -> void:
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	dst = model.find_child("Skeleton3D",true,false)
	ready = Author.new(dst,preload("res://assets/animations/goalkeeper_idle.tres"))
	for side in ["l","r"]:
		var prefix := "Left" if side=="l" else "Right"
		for pair in [["thigh","UpLeg"],["calf","Leg"],["foot","Foot"],["ball","ToeBase"]]: mapping[pair[0]+"_"+side] = prefix+pair[1]
	for bone in dst.get_bone_count(): hierarchy_order(bone)
	for size_ in ["short","medium","long"]:
		var imported: Node3D = load("res://assets/animations/source/side_right_"+size_+".fbx").instantiate()
		src = imported.find_child("Skeleton3D",true,false)
		var player: AnimationPlayer = imported.find_child("AnimationPlayer",true,false)
		source = player.get_animation(player.get_animation_list()[0])
		sampler = Author.new(src,source)
		source_tracks.clear()
		source_names.clear()
		for bone in src.get_bone_count():
			source_names[str(src.get_bone_name(bone)).get_slice("_",1)] = bone
			var path := NodePath("Skeleton3D:"+src.get_bone_name(bone))
			source_tracks[bone] = [source.find_track(path,Animation.TYPE_POSITION_3D),source.find_track(path,Animation.TYPE_ROTATION_3D)]
		root_start = sampler.point(sample(0),str(src.get_bone_name(source_names.Hips)))
		var clip: Animation = ready.bake({"name":"Right step "+size_,"duration":source.length,"contact_time":-1},pose_at)
		clip.remove_meta("contact_time")
		clip.loop_mode = Animation.LOOP_NONE
		var root_curve := PackedFloat32Array()
		for frame in range(ceili(source.length*60)+1):
			var time := minf(source.length,frame/60.0)
			root_curve.append(-(sampler.world_pose(sample(time),source_names.Hips).origin.x-root_start.x)*scale_)
		clip.set_meta("root_right",root_curve)
		clip.set_meta("ready_upper_body",true)
		print(size_," distance ",root_curve[-1],"m: ",ResourceSaver.save(clip,"res://assets/animations/side_right_"+size_+".res",ResourceSaver.FLAG_COMPRESS))
		imported.free()
	model.free()
	quit()

func sample(time: float) -> Array:
	var pose: Array = []
	for bone in src.get_bone_count():
		var local := src.get_bone_rest(bone)
		var tracks: Array = source_tracks[bone]
		if tracks[0]>=0: local.origin = source.position_track_interpolate(tracks[0],time)
		if tracks[1]>=0: local.basis = Basis(source.rotation_track_interpolate(tracks[1],time))
		pose.append(local)
	return pose

func pose_at(time: float) -> Array:
	var input := sample(time)
	var output: Array = ready.baseline.duplicate()
	for bone in order:
		var name_ := str(dst.get_bone_name(bone))
		var parent := dst.get_bone_parent(bone)
		var parent_basis: Basis = Basis.IDENTITY if parent<0 else ready.world_pose(output,parent).basis
		if mapping.has(name_) and source_names.has(mapping[name_]):
			var origin: int = source_names[mapping[name_]]
			var desired: Basis = sampler.world_pose(input,origin).basis.orthonormalized()*src.get_bone_global_rest(origin).basis.orthonormalized().inverse()*dst.get_bone_global_rest(bone).basis.orthonormalized()
			output[bone].basis = (parent_basis.inverse()*desired).orthonormalized()
			if name_=="pelvis":
				var offset: Vector3 = sampler.world_pose(input,origin).origin-src.get_bone_global_rest(origin).origin
				offset.x = 0
				offset.z = 0
				output[bone].origin = dst.get_bone_rest(bone).origin+parent_basis.inverse()*offset*scale_
		elif name_=="spine_01":
			# Cancel captured hip rotation above the waist: retain our ready arms/torso.
			output[bone].basis = parent_basis.inverse()*ready.world_pose(ready.baseline,bone).basis
	return output

func hierarchy_order(bone: int) -> void:
	if bone in order: return
	var parent := dst.get_bone_parent(bone)
	if parent>=0: hierarchy_order(parent)
	order.append(bone)

