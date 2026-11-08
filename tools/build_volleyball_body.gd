extends SceneTree
const RADII := {"upperarm_l":0.85,"upperarm_r":0.85,"lowerarm_l":0.90,"lowerarm_r":0.90}
func _initialize() -> void:
	var model := preload("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var rig: Skeleton3D = model.find_child("Skeleton3D",true,false)
	var original: MeshInstance3D = rig.find_child("SuperHero_Male",true,false)
	var skin := original.skin
	var axes := {}
	for bind in skin.get_bind_count():
		var name_ := str(skin.get_bind_name(bind))
		var bone := rig.find_bone(name_) if not name_.is_empty() else skin.get_bind_bone(bind)
		if bone < 0: continue
		name_ = str(rig.get_bone_name(bone))
		if not RADII.has(name_): continue
		var child := rig.find_bone(name_.replace("upperarm_","lowerarm_").replace("lowerarm_","hand_")) if name_.begins_with("lowerarm_") else rig.find_bone(name_.replace("upperarm_","lowerarm_"))
		var start := rig.get_bone_global_rest(bone).origin
		var direction := (rig.get_bone_global_rest(child).origin-start).normalized()
		axes[bind] = {"origin":start,"axis":direction,"factor":RADII[name_]}
	DirAccess.make_dir_recursive_absolute("res://assets/characters/volleyball")
	for part in ["body","outfit"]:
		var source: ArrayMesh = load("res://assets/outfits/brutus_"+part+".res")
		var result := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size()/vertices.size() if not vertices.is_empty() else 0
			for vertex in vertices.size():
				var point := vertices[vertex]
				var offset := Vector3.ZERO
				for influence in range(int(influences)):
					var index := vertex*int(influences)+influence
					if not axes.has(bones[index]) or weights[index] <= 0: continue
					var limb: Dictionary = axes[bones[index]]
					var along: Vector3 = limb.origin+limb.axis*(point-limb.origin).dot(limb.axis)
					offset += (point-along)*(float(limb.factor)-1.0)*weights[index]
				vertices[vertex] = point+offset
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var recalculated := PackedVector3Array()
			recalculated.resize(vertices.size())
			for triangle in range(0,indices.size(),3):
				var a := indices[triangle]
				var b := indices[triangle+1]
				var c := indices[triangle+2]
				var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
				if normal.dot(normals[a]+normals[b]+normals[c]) < 0: normal = -normal
				recalculated[a] += normal
				recalculated[b] += normal
				recalculated[c] += normal
			for vertex in recalculated.size(): recalculated[vertex] = recalculated[vertex].normalized() if recalculated[vertex].length_squared() > 0 else normals[vertex]
			arrays[Mesh.ARRAY_NORMAL] = recalculated
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for vertex in range(tangents.size()/4):
				var t := Vector3(tangents[vertex*4],tangents[vertex*4+1],tangents[vertex*4+2])
				t = (t-recalculated[vertex]*recalculated[vertex].dot(t)).normalized()
				for axis in range(3): tangents[vertex*4+axis] = t[axis]
			arrays[Mesh.ARRAY_TANGENT] = tangents
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			result.surface_set_material(surface,source.surface_get_material(surface))
		print(part," slimmer mesh: ",ResourceSaver.save(result,"res://assets/characters/volleyball/"+part+".res"))
	model.free()
	quit()
