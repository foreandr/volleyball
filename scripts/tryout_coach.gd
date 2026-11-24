extends RefCounted

# The toss is solved on the same skeleton and palm landmarks as the standing float serve.
const Serve = preload("res://scripts/standing_float_serve.gd")
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
		var sign_ := 1.0 if author.point(pose,"upperarm_"+side).x>center.x else -1.0
		var wrist := center+Vector3(sign_*.085,-.080,-.065)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*.86,-.72,.12))
		pose_helper.orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.RIGHT*sign_,1.0)
	for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
	var palms: Vector3 = (author.point(pose,"middle_01_l")+author.point(pose,"middle_01_r"))*0.5
	return rig.to_global(center).lerp(rig.to_global(palms)+Vector3.UP*.095,drive)

func dress(actor: Node3D) -> void:
	var rig: Skeleton3D = actor.skeleton
	actor.animation_slots["idle"]="base/Idle"
	actor.play_action("idle",0.)
	actor.animator.advance(.18)
	var author: RefCounted=actor.get_pose_author()
	for i in rig.get_bone_count(): author.baseline[i]=rig.get_bone_pose(i)
	var head := rig.find_bone("Head")
	var mount := BoneAttachment3D.new()
	mount.bone_name=rig.get_bone_name(head)
	rig.add_child(mount)
	var hat := Node3D.new()
	mount.add_child(hat)
	hat.transform=rig.get_bone_global_rest(head).affine_inverse()*Transform3D(Basis.IDENTITY,Vector3(0,1.744,-.021))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color=Color("244c3d")
	cloth.roughness=.94
	cloth.cull_mode=BaseMaterial3D.CULL_DISABLED
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 10:
		for i in 48:
			for uv: Vector2 in [Vector2(i,j),Vector2(i+1,j),Vector2(i,j+1),Vector2(i,j+1),Vector2(i+1,j),Vector2(i+1,j+1)]:
				var angle := uv.x*TAU/48.
				var h := uv.y*PI/20.
				var r := cos(h)
				surface.add_vertex(Vector3(.098*r*sin(angle),.094*sin(h)-.018*r*(1.-cos(angle)),.119*r*cos(angle)))
	for i in 24:
		for uv: Vector2 in [Vector2(i,0),Vector2(i+1,0),Vector2(i,1),Vector2(i,1),Vector2(i+1,0),Vector2(i+1,1)]:
			var x := uv.x/12.-1.
			var z := lerpf(.060+.050*(1.-x*x),.090+.085*sqrt(maxf(0.,1.-x*x)),uv.y)
			surface.add_vertex(Vector3(x*.102,-.004-.021*x*x-.010*uv.y,z))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=cloth
	hat.add_child(mesh)
	var thread := ImmediateMesh.new()
	thread.surface_begin(Mesh.PRIMITIVE_LINES)
	for panel in 6:
		var angle := panel*PI/3.
		for j in 12:
			for k in [j,j+1]:
				var h := float(k)*PI/24.
				var radius := cos(h)
				thread.surface_add_vertex(Vector3(.099*radius*sin(angle),.095*sin(h)-.018*radius*(1.-cos(angle)),.120*radius*cos(angle)))
	thread.surface_end()
	var stitching := MeshInstance3D.new()
	stitching.mesh=thread
	var seam := StandardMaterial3D.new()
	seam.albedo_color=Color("516859")
	stitching.material_override=seam
	hat.add_child(stitching)
	var crest := Label3D.new()
	crest.text="F"
	crest.font_size=48
	crest.pixel_size=.00063
	crest.outline_size=2
	crest.modulate=Color("d4d7ba")
	crest.position=Vector3(0,.032,.115)
	crest.rotation.x=-.29
	hat.add_child(crest)

func fetch_pose(actor: Node3D,center: Vector3,reach: float,carry: float) -> void:
	var rig: Skeleton3D=actor.skeleton
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=author.baseline.duplicate()
	var local := rig.to_local(center)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.24*reach*(1.-carry))
	for side in ["r","l"]:
		var weight := reach if side=="r" else smoothstep(.04,.64,carry)
		var sign_ := signf(author.point(pose,"upperarm_"+side).x)
		var wrist := local+Vector3(sign_*.085,-.080,-.065)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*.86,-.72,.12),weight)
		pose_helper.orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.RIGHT*sign_,weight)
	for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
