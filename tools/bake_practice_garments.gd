extends SceneTree

# Cut the training garments in bind space so their edges and skin weights
# survive posing, including on triangles crossing a cuff or waistband.
func _initialize():
	var model=load("res://assets/characters/base/Superhero_Male_FullBody.gltf").instantiate()
	var torso=model.find_child("SuperHero_Male",true,false).mesh
	bake(torso,0,true,"practice_jersey")
	bake(load("res://assets/characters/volleyball/outfit.res"),1,false,"practice_shorts")
	model.free()
	quit()

func cut(p:Vector3,plane:int)->float:
	match plane:
		0:return p.y-1.015
		1:return .392-p.x
		2:return .392+p.x
		3:return 1.563-.055*(1.-smoothstep(.045,.109,absf(p.x)))*smoothstep(-.075,.075,p.z)-p.y
		_:return p.y-.69

func mix_vertex(a:Dictionary,b:Dictionary,t:float)->Dictionary:
	var w={}
	for id in a.w:w[id]=a.w[id]*(1.-t)
	for id in b.w:w[id]=w.get(id,0.)+b.w[id]*t
	return {"p":a.p.lerp(b.p,t),"n":a.n.lerp(b.n,t).normalized(),"w":w}

func bake(mesh:ArrayMesh,slot:int,jersey:bool,label:String):
	var arr=mesh.surface_get_arrays(slot)
	var verts=arr[Mesh.ARRAY_VERTEX]
	var count=arr[Mesh.ARRAY_BONES].size()/verts.size()
	var samples=[]
	for i in verts.size():
		var w={}
		for j in count:
			var k=i*count+j
			if arr[Mesh.ARRAY_WEIGHTS][k]>0.:w[arr[Mesh.ARRAY_BONES][k]]=arr[Mesh.ARRAY_WEIGHTS][k]
		samples.append({"p":verts[i],"n":arr[Mesh.ARRAY_NORMAL][i],"w":w})
	var indices=arr[Mesh.ARRAY_INDEX]
	if indices==null or indices.is_empty():indices=range(verts.size())
	var surface=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0,indices.size(),3):
		var poly=[samples[indices[t]],samples[indices[t+1]],samples[indices[t+2]]]
		for plane in ([0,1,2,3] if jersey else [4]):
			if poly.is_empty():break
			var clipped=[]
			var prev=poly.back()
			for point in poly:
				var a=cut(prev.p,plane)
				var b=cut(point.p,plane)
				if (a>=0)!=(b>=0):clipped.append(mix_vertex(prev,point,a/(a-b)))
				if b>=0:clipped.append(point)
				prev=point
			poly=clipped
		for j in range(1,poly.size()-1):
			for v in [poly[0],poly[j],poly[j+1]]:
				var p:Vector3=v.p
				var n:Vector3=v.n
				var ids=v.w.keys()
				ids.sort_custom(func(a,b):return v.w[a]>v.w[b])
				var bones=PackedInt32Array([0,0,0,0])
				var weights=PackedFloat32Array([0,0,0,0])
				var total=0.
				for k in mini(4,ids.size()):
					bones[k]=ids[k]
					weights[k]=v.w[ids[k]]
					total+=weights[k]
				for k in 4:weights[k]/=maxf(total,.00001)
				surface.set_bones(bones)
				surface.set_weights(weights)
				surface.set_normal(n)
				surface.set_uv2(Vector2(p.x,p.y))
				surface.set_color(Color(clampf((p.z+.3)/.6,0,1),0,0,1))
				# Ease the abdomen into a continuous fabric panel above the shorts.
				var ease=(1.-smoothstep(1.02,1.32,p.y))*(1.-smoothstep(.16,.28,absf(p.x)))
				if jersey:
					p.x*=1.+.11*ease
					p.z+=signf(p.z+.015)*.021*ease
					p.y-=.025*ease
				surface.add_vertex(p)
	surface.index()
	var out=surface.commit()
	print(label," vertices ",out.surface_get_array_len(0)," save ",ResourceSaver.save(out,"res://assets/characters/volleyball/"+label+".res",ResourceSaver.FLAG_COMPRESS))
