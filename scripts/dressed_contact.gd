extends RefCounted

# The animation requests a point and approach direction. Intersect the
# deformed outer garment and take the first surface encountered.
var garment: MeshInstance3D
var skeleton: Skeleton3D
var vertices: PackedVector3Array
var bones: PackedInt32Array
var weights: PackedFloat32Array
var faces := PackedInt32Array()
var contact_vertices := PackedInt32Array()
var bind_bones := PackedInt32Array()
var stride := 4
var frame := -1
var deformed := PackedVector3Array()

func configure(part: MeshInstance3D, rig: Skeleton3D) -> void:
	garment=part
	skeleton=rig
	var arrays := part.mesh.surface_get_arrays(0)
	vertices=arrays[Mesh.ARRAY_VERTEX]
	# The render shader adds fabric ease after skinning. Include its
	# resting envelope so a waist contact reaches the outside of the hem.
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var jacket: bool=part.material_override.get_shader_parameter("jacket")
	for i in vertices.size():
		var x:=absf(uv[i].x)
		var y:=uv[i].y
		var shoulder:=smoothstep(1.455,1.55,y)*(1.-smoothstep(.18,.22,x))
		var ease:=.021 if jacket else lerpf(.022,.004,shoulder)
		if not jacket:
			var armhole:=minf(x-(.165-.026*smoothstep(1.39,1.54,y)+.17*absf(vertices[i].z)),y-1.342+.22*(x-.16))
			if armhole>0.: ease=.0014
		vertices[i]+=normals[i]*ease
	bones=arrays[Mesh.ARRAY_BONES]
	weights=arrays[Mesh.ARRAY_WEIGHTS]
	stride=bones.size()/vertices.size()
	deformed.resize(vertices.size())
	for i in part.skin.get_bind_count():
		var bone := part.skin.get_bind_bone(i)
		if bone<0: bone=rig.find_bone(part.skin.get_bind_name(i))
		bind_bones.append(bone)
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var used: Dictionary={}
	for i in range(0,indices.size(),3):
		var center := (vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.
		var bind_uv := (uv[indices[i]]+uv[indices[i+1]]+uv[indices[i+2]])/3.
		if jacket and (bind_uv.y>1.57 or (absf(bind_uv.x)<.09 and bind_uv.y>1.52)): continue
		if center.y>=.97 and center.y<=1.58 and absf(center.x)<.40:
			faces.append(indices[i])
			faces.append(indices[i+1])
			faces.append(indices[i+2])
			for j in 3: used[indices[i+j]]=true
	contact_vertices=PackedInt32Array(used.keys())

func update() -> void:
	var current := Engine.get_process_frames()
	if frame==current: return
	frame=current
	var transforms: Array[Transform3D]=[]
	for i in bind_bones.size():
		var bone := bind_bones[i]
		transforms.append(skeleton.get_bone_global_pose(bone)*garment.skin.get_bind_pose(i) if bone>=0 else Transform3D.IDENTITY)
	for i in contact_vertices:
		var p := Vector3.ZERO
		for j in stride:
			var k := i*stride+j
			if weights[k]>0.: p+=(transforms[bones[k]]*vertices[i])*weights[k]
		deformed[i]=skeleton.to_global(p)

var hit_normal := Vector3.UP

func contact(landmark: Vector3, outward: Vector3) -> Vector3:
	update()
	var normal := outward.normalized()
	hit_normal=normal
	var origin := landmark+normal*.32
	var end := landmark-normal*.18
	var nearest := INF
	var result := landmark
	for i in range(0,faces.size(),3):
		var hit=Geometry3D.segment_intersects_triangle(origin,end,deformed[faces[i]],deformed[faces[i+1]],deformed[faces[i+2]])
		if hit!=null:
			var distance := origin.distance_squared_to(hit)
			if distance<nearest:
				nearest=distance
				result=hit
				var a:=deformed[faces[i]]
				var face_normal:=(deformed[faces[i+1]]-a).cross(deformed[faces[i+2]]-a).normalized()
				hit_normal=face_normal if face_normal.dot(normal)>0. else -face_normal
	# Allow for the rendered textile thickness and soft tissue of the palm.
	return result+normal*.018 if nearest<INF else landmark
