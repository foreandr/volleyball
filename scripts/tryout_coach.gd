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
	var cap := SphereMesh.new()
	cap.radius = 0.127
	cap.height = 0.19
	var crown := attach(rig,rig.get_bone_name(head),cap,Color("20342f"))
	crown.global_position = rig.to_global(rig.get_bone_global_pose(head).origin)+Vector3.UP*0.166
	var bill := BoxMesh.new()
	bill.size = Vector3(0.17,0.012,0.12)
	var brim := attach(rig,rig.get_bone_name(head),bill,Color("20342f"))
	brim.global_position = crown.global_position+actor.basis.z*0.105

func attach(rig: Skeleton3D,bone: String,mesh: Mesh,color: Color) -> MeshInstance3D:
	var socket := BoneAttachment3D.new()
	socket.bone_name = bone
	rig.add_child(socket)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = color
	part.material_override = fabric
	socket.add_child(part)
	return part
