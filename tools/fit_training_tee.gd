extends SceneTree

const SOURCE := preload("res://assets/characters/volleyball/training_tee/tee.obj")
const REFERENCE := preload("res://assets/characters/volleyball/practice_jersey.res")

func fit(p: Vector3) -> Vector3:
	# Open the source A-pose sleeves into the volleyball rig's T-pose.
	var sleeve := smoothstep(1.40,2.08,absf(p.x))*smoothstep(4.45,4.92,p.y)
	var x := p.x*.127+signf(p.x)*sleeve*(.119+(6.15-p.y)*.032)
	return Vector3(x,.800+p.y*.114+sleeve*.084,(p.z-.26)*.119-.018)

func _initialize() -> void:
	var ref := REFERENCE.surface_get_arrays(0)
	var ref_pos: PackedVector3Array=ref[Mesh.ARRAY_VERTEX]
	var result := ArrayMesh.new()
	for slot in SOURCE.get_surface_count():
		var arrays := SOURCE.surface_get_arrays(slot)
		var source: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var uv2 := PackedVector2Array()
		var colors := PackedColorArray()
		for i in source.size():
			var p := fit(source[i])
			source[i]=p
			var nearest := PackedInt32Array([-1,-1,-1])
			var gaps := PackedFloat32Array([INF,INF,INF])
			for j in ref_pos.size():
				var d := ref_pos[j].distance_squared_to(p)
				if d>=gaps[2]: continue
				var k := 2
				while k>0 and d<gaps[k-1]:
					gaps[k]=gaps[k-1]
					nearest[k]=nearest[k-1]
					k-=1
				gaps[k]=d
				nearest[k]=j
			var blend := {}
			for k in nearest.size():
				for influence in 4:
					var idx := nearest[k]*4+influence
					var bone: int=ref[Mesh.ARRAY_BONES][idx]
					blend[bone]=blend.get(bone,0.)+float(ref[Mesh.ARRAY_WEIGHTS][idx])/maxf(gaps[k],.00001)
			var ids := blend.keys()
			ids.sort_custom(func(a,b): return blend[a]>blend[b])
			var total := 0.
			for k in mini(ids.size(),4): total+=float(blend[ids[k]])
			for k in 4:
				bones.append(ids[k] if k<ids.size() else 0)
				weights.append(blend[ids[k]]/total if k<ids.size() else 0.)
			uv2.append(Vector2(p.x,p.y))
			colors.append(Color((p.z+.3)/.6,0,0))
		arrays[Mesh.ARRAY_VERTEX]=source
		arrays[Mesh.ARRAY_BONES]=bones
		arrays[Mesh.ARRAY_WEIGHTS]=weights
		arrays[Mesh.ARRAY_TEX_UV2]=uv2
		arrays[Mesh.ARRAY_COLOR]=colors
		# Recompute shading on the fitted sleeve and shoulder panels.
		arrays[Mesh.ARRAY_NORMAL]=null
		arrays[Mesh.ARRAY_TANGENT]=null
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var tool := SurfaceTool.new()
		tool.create_from(temporary,0)
		tool.deindex()
		tool.generate_normals()
		tool.generate_tangents()
		tool.index()
		tool.commit(result)
	var error := ResourceSaver.save(result,"res://assets/characters/volleyball/training_tee/fitted.res",ResourceSaver.FLAG_COMPRESS)
	print("Fitted surfaces ",result.get_surface_count()," vertices ",result.surface_get_array_len(0)," save ",error)
	quit(error)
