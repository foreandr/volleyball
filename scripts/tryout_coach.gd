extends RefCounted

# The toss is solved on the same skeleton and palm landmarks as the standing float serve.
const Serve = preload("res://scripts/standing_float_serve.gd")
var whistle_cue := preload("res://scripts/official_whistle.gd").new()
var toss_hand := ""
var pose_helper := Serve.new()

func dispose() -> void:
	pose_helper.free()

func toss(actor: Node3D,t: float) -> Vector3:
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = author.baseline.duplicate()
	var dip := sin(PI*smoothstep(0.,.55,t))
	var drive := smoothstep(0.40,1.0,t)
	var pelvis := rig.find_bone("pelvis")
	var parent: Transform3D=author.world_pose(pose,rig.get_bone_parent(pelvis))
	pose[pelvis].origin+=parent.basis.inverse()*Vector3(0,-.066*dip,.022*dip)
	for side in ["l","r"]:
		var foot: Vector3=author.point(author.baseline,"foot_"+side)
		author.limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,foot,Vector3.BACK)
	rig.set_bone_pose_position(pelvis,pose[pelvis].origin)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,0.12*dip-0.08*drive)
	var center: Vector3 = author.point(pose,"pelvis")+Vector3(0,0.12-0.16*dip+0.46*drive,0.46+0.10*drive)
	for side in ["l","r"]:
		if toss_hand != "" and side != toss_hand: continue
		var sign_ := 1.0 if author.point(pose,"upperarm_"+side).x>center.x else -1.0
		var wrist := center+Vector3(sign_*.085,-.080,-.065)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*.86,-.72,.12))
		pose_helper.orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.RIGHT*sign_,1.0)
	for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
	var palms: Vector3 = (author.point(pose,"middle_01_l")+author.point(pose,"middle_01_r"))*0.5
	if toss_hand != "": palms = author.point(pose,"middle_01_"+toss_hand)
	return rig.to_global(center).lerp(rig.to_global(palms)+Vector3.UP*.095,drive)

func dress(actor: Node3D) -> void:
	var rig: Skeleton3D = actor.skeleton
	actor.animation_slots["idle"]="base/Idle"
	actor.play_action("idle",0.)
	actor.animator.advance(.18)
	var author: RefCounted=actor.get_pose_author()
	for i in rig.get_bone_count(): author.baseline[i]=rig.get_bone_pose(i)
	whistle_cue.fit_whistle(rig)
	var head := rig.find_bone("Head")
	var mount := BoneAttachment3D.new()
	mount.bone_name=rig.get_bone_name(head)
	rig.add_child(mount)
	var hat := Node3D.new()
	mount.add_child(hat)
	# Measure the skull around the sweatband and crown in the same bind
	# coordinates used by the cap, then attach the fit to the animated head.
	var head_mesh := preload("res://assets/characters/volleyball/body.res")
	var skull: PackedVector3Array=head_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := Vector3(INF,INF,INF)
	var high := -low
	var crown_y := 0.
	for point in skull:
		if absf(point.x)>.125: continue
		crown_y=maxf(crown_y,point.y)
		if point.y<1.720 or point.y>1.752: continue
		low=low.min(point)
		high=high.max(point)
	var center := Vector3(0,1.740,-.021)
	var fit := Vector3.ONE
	if low.is_finite() and high.y>low.y:
		center.z=(low.z+high.z)*.5
		fit=Vector3((high.x-low.x+.006)/.196,(crown_y+.004-center.y)/.094,(high.z-low.z+.008)/.238)
		# Band width alone misses the bulge above the temples. Enclose all scalp
		# points above the sloping band in the actual domed crown profile.
		var envelope:=1.
		for point in skull:
			if point.y<center.y-.043 or absf(point.x)>.125: continue
			var local:= (point-center)/fit
			var radial:=Vector2(local.x/.098,local.z/.119)
			var band_drop:=.018*(1.-radial.normalized().y)*radial.length()
			if local.y < -band_drop: continue
			var rise:=(local.y+band_drop)/.094
			envelope=maxf(envelope,sqrt(radial.length_squared()+rise*rise))
		fit*=envelope*1.025
	hat.transform=rig.get_bone_global_rest(head).affine_inverse()*Transform3D(Basis.IDENTITY.scaled(fit),center)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color=Color("244c3d")
	cloth.roughness=.94
	cloth.vertex_color_use_as_albedo=true
	cloth.cull_mode=BaseMaterial3D.CULL_DISABLED
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color.WHITE)
	for j in 10:
		for i in 48:
			for uv: Vector2 in [Vector2(i,j),Vector2(i+1,j),Vector2(i,j+1),Vector2(i,j+1),Vector2(i+1,j),Vector2(i+1,j+1)]:
				var angle := uv.x*TAU/48.
				# Lift the lower crown over the adjustment strap at the nape.
				var rear := clampf(absf(angle-PI)/.51,0.,1.)
				var arch := .34*sqrt(maxf(0.,1.-rear*rear))
				var h := lerpf(arch,PI*.5,uv.y/10.)
				var r := cos(h)
				surface.add_vertex(Vector3(.098*r*sin(angle),.094*sin(h)-.018*r*(1.-cos(angle)),.119*r*cos(angle)))
	# The sweatband follows the low edge of the crown and encloses the visor seam.
	for i in 48:
		for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
			var angle := (i+corner.x)*TAU/48.
			var drop := corner.y*.012
			surface.set_color(Color(.79,.82,.80))
			surface.add_vertex(Vector3(.098*sin(angle),-.018*(1.-cos(angle))-drop,.119*cos(angle)))
	# A bound visor has a top, shaded underside and a rounded leading edge.
	for i in 48:
		var a := float(i)/24.-1.
		var b := float(i+1)/24.-1.
		for underside in [false,true]:
			for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var x := lerpf(a,b,corner.x)
				var along := corner.y
				var pt := visor_point(x,along)
				if underside: pt.y-=.0042
				surface.set_color(Color(.48,.53,.50) if underside else Color.WHITE)
				surface.add_vertex(pt)
		for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
			var pt := visor_point(lerpf(a,b,corner.x),1.)
			pt.y-=corner.y*.0042
			surface.set_color(Color(.71,.75,.73))
			surface.add_vertex(pt)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=cloth
	hat.add_child(mesh)
	# A metal slide sits on the rear band below the crown opening.
	var slide := MeshInstance3D.new()
	var buckle := BoxMesh.new()
	buckle.size=Vector3(.016,.014,.003)
	slide.mesh=buckle
	var hardware := StandardMaterial3D.new()
	hardware.albedo_color=Color("686c61")
	hardware.metallic=.72
	hardware.roughness=.42
	slide.material_override=hardware
	slide.position=Vector3(.024,-.040,-.117)
	slide.rotation.y=-.24
	hat.add_child(slide)
	var thread := ImmediateMesh.new()
	thread.surface_begin(Mesh.PRIMITIVE_LINES)
	for panel in 6:
		var angle := panel*PI/3.
		for j in 12:
			for k in [j,j+1]:
				var arch := .34 if panel==3 else 0.
				var h := lerpf(arch,PI*.5,float(k)/12.)
				var radius := cos(h)
				thread.surface_add_vertex(Vector3(.099*radius*sin(angle),.095*sin(h)-.018*radius*(1.-cos(angle)),.120*radius*cos(angle)))
	thread.surface_end()
	var stitching := MeshInstance3D.new()
	stitching.mesh=thread
	var seam := StandardMaterial3D.new()
	seam.albedo_color=Color("516859")
	stitching.material_override=seam
	hat.add_child(stitching)
	# Fabric-covered button caps the six panel seams. Embroidered eyelets
	# follow the local crown tangent so they sit flush on each panel.
	var button := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius=.009
	dome.height=.009
	button.mesh=dome
	button.position.y=.095
	button.material_override=cloth
	hat.add_child(button)
	var eyelet := TorusMesh.new()
	eyelet.inner_radius=.0018
	eyelet.outer_radius=.0038
	eyelet.rings=16
	eyelet.ring_segments=6
	for panel in 6:
		var angle := (panel+.5)*PI/3.
		var h := .68
		var rim := MeshInstance3D.new()
		rim.mesh=eyelet
		rim.material_override=seam
		rim.position=Vector3(.098*cos(h)*sin(angle),.094*sin(h)-.018*cos(h)*(1.-cos(angle)),.119*cos(h)*cos(angle))
		var tangent := Vector3(.098*cos(angle),-.018*sin(angle),-.119*sin(angle))
		var uphill := Vector3(-.098*sin(h)*sin(angle),.094*cos(h)+.018*sin(h)*(1.-cos(angle)),-.119*sin(h)*cos(angle))
		var normal := tangent.cross(uphill).normalized()
		rim.position+=normal*.0009
		rim.quaternion=Quaternion(Vector3.UP,normal)
		hat.add_child(rim)
	var crest := Label3D.new()
	crest.text="F"
	crest.font_size=48
	crest.pixel_size=.00063
	crest.outline_size=2
	crest.modulate=Color("d4d7ba")
	crest.position=Vector3(0,.032,.115)
	crest.rotation.x=-.29
	hat.add_child(crest)

static func visor_point(x: float,along: float) -> Vector3:
	var front := .090+.085*sqrt(maxf(0.,1.-x*x))
	var angle := x*1.25
	var root := Vector3(.098*sin(angle),-.018*(1.-cos(angle))-.006,.119*cos(angle))
	var tip := Vector3(x*.102,-.014-.021*x*x,front)
	return root.lerp(tip,along)

func fetch_pose(actor: Node3D,center: Vector3,reach: float,carry: float) -> void:
	var rig: Skeleton3D=actor.skeleton
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=author.baseline.duplicate()
	var local := rig.to_local(center)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.24*reach*(1.-carry))
	for side in ["r","l"]:
		var weight := reach if side==(toss_hand if toss_hand!="" else "r") else (smoothstep(.04,.64,carry) if toss_hand=="" else 0.)
		var sign_ := signf(author.point(pose,"upperarm_"+side).x)
		var wrist := local+Vector3(sign_*.085,-.080,-.065)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*.86,-.72,.12),weight)
		pose_helper.orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.RIGHT*sign_,weight)
	for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
