extends RefCounted

const Contact = preload("res://scripts/gym_physics.gd")
var planted := {}
var actor: Node3D
var bench: MeshInstance3D
var side := 1
var court_z := 0.0
var foot_height := 0.0

func configure(player: Node3D,seat: MeshInstance3D,below: MeshInstance3D,aisle_side: int,z: float) -> void:
	actor = player
	bench = seat
	side = aisle_side
	court_z = z
	foot_height = below.global_position.y+below.mesh.size.y*.5 if below else .045
	update()
	for name_ in ["pelvis","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r"]:
		var i: int = actor.skeleton.find_bone(name_)
		planted[i] = actor.skeleton.get_bone_pose(i)

func update() -> void:
	var rig: Skeleton3D = actor.skeleton
	if not planted.is_empty():
		for i in planted: rig.set_bone_pose(i,planted[i])
		return
	var author: RefCounted = actor.get_pose_author()
	var front: float = bench.global_position.x-side*bench.mesh.size.x*.5
	var top: float = bench.global_position.y+bench.mesh.size.y*.5
	var hip := Contact.joint(actor,"pelvis")
	var knees := (Contact.joint(actor,"calf_l")+Contact.joint(actor,"calf_r"))*.5
	# Seat from the leading edge. This leaves clearance behind both shins.
	var translation := Vector3(front-side*.16-knees.x,top+.10*actor.scale.y-hip.y,court_z-hip.z)
	actor.global_position += translation
	var pose: Array = []
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	for leg in ["l","r"]:
		var foot: String = "foot_"+leg
		var ankle := Contact.joint(actor,foot)
		ankle.x = front-side*.22
		ankle.y = foot_height+.11*actor.scale.y
		var old_basis: Basis = author.world_pose(pose,rig.find_bone(foot)).basis
		author.limb(pose,"thigh_"+str(leg),"calf_"+str(leg),foot,rig.to_local(ankle),Vector3(0,0,1))
		author.set_world_basis(pose,foot,old_basis)
		for name_ in ["thigh_"+str(leg),"calf_"+str(leg),foot]:
			var idx := rig.find_bone(name_)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())
