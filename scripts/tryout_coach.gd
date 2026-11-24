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
	var dip := sin(PI*clampf(t/0.55,0,1))
	var drive := smoothstep(0.40,1.0,t)
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,0.12*dip-0.08*drive)
	var center: Vector3 = author.point(pose,"pelvis")+Vector3(0,0.12-0.16*dip+0.46*drive,0.33+0.20*drive)
	for side in ["l","r"]:
		var sign_ := 1.0 if author.point(pose,"upperarm_"+side).x>center.x else -1.0
		var wrist := center+Vector3(sign_*0.11,-0.06,-0.06)
		author.limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,wrist,Vector3(sign_*0.65,-0.9,-0.25))
		pose_helper.orient_palm(pose,rig,author,side,Vector3.BACK,Vector3.LEFT if side=="l" else Vector3.RIGHT,0.85)
	for i in rig.get_bone_count(): rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
	var palms: Vector3 = (author.point(pose,"middle_01_l")+author.point(pose,"middle_01_r"))*0.5
	return rig.to_global(palms)+Vector3.UP*0.095

func dress(actor: Node3D) -> void:
	var rig: Skeleton3D = actor.skeleton
	var head := rig.find_bone("Head")
	var mount := BoneAttachment3D.new()
	mount.bone_name=rig.get_bone_name(head)
	rig.add_child(mount)
	var hat := Node3D.new()
	mount.add_child(hat)
	hat.transform=rig.get_bone_global_rest(head).affine_inverse()*Transform3D(Basis.IDENTITY,Vector3(0,1.744,-.021))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color=Color("214438")
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
			var z := lerpf(.060+.050*(1.-x*x),.094+.104*sqrt(maxf(0.,1.-x*x)),uv.y)
			surface.add_vertex(Vector3(x*.102,-.004-.021*x*x-.010*uv.y,z))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=cloth
	hat.add_child(mesh)

func fetch_pose(actor: Node3D,point: Vector3,weight: float) -> void:
	var rig: Skeleton3D=actor.skeleton
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=author.baseline.duplicate()
	author.rotate_world(pose,"spine_01",Vector3.RIGHT,.19*weight)
	author.limb(pose,"upperarm_r","lowerarm_r","hand_r",rig.to_local(point),Vector3(-.45,-1,0),weight)
	for bone in ["spine_01","upperarm_r","lowerarm_r","hand_r"]:
		var i := rig.find_bone(bone)
		rig.set_bone_pose_rotation(i,pose[i].basis.orthonormalized().get_rotation_quaternion())
