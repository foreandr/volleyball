extends RefCounted

const Contact = preload("res://scripts/gym_physics.gd")
var beat := .36
var age := 0.0
var duration := 0.0
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
	for name_ in ["pelvis","thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r","upperarm_l","upperarm_r","lowerarm_l","lowerarm_r"]:
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

		var wrist: String="hand_"+leg
		var knee: Vector3=author.point(pose,"calf_"+leg)
		author.limb(pose,"upperarm_"+leg,"lowerarm_"+leg,wrist,knee+Vector3(0,.10,-.06),Vector3(0,-1,-.25))
		for bone in ["upperarm_"+leg,"lowerarm_"+leg]:
			var idx := rig.find_bone(bone)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())

func celebrate(index: int,block_complete: bool) -> void:
	age = -.10-fmod(index*.137,.36)
	beat = .31+fmod(index*.073,.13)
	duration = beat*(5 if block_complete else 3)

func applause(delta: float) -> void:
	if duration<=0: return
	age += delta
	if age<0: return
	if age>=duration:
		duration = 0
		return
	var phase := fmod(age,beat)/beat
	var closed := smoothstep(.12,.48,phase)*(1.-smoothstep(.51,.92,phase))
	var blend := smoothstep(0,.10,age)*(1.-smoothstep(duration-.12,duration,age))
	var rig: Skeleton3D = actor.skeleton
	var author: RefCounted = actor.get_pose_author()
	var pose: Array = []
	for idx in rig.get_bone_count(): pose.append(rig.get_bone_pose(idx))
	var center: Vector3 = author.point(pose,"spine_03")+Vector3(0,.055,.29)
	for side_ in ["l","r"]:
		var sign_ := 1.0 if side_=="l" else -1.0
		var wrist: String = "hand_"+side_
		var base: Transform3D = author.world_pose(pose,rig.find_bone(wrist))
		var along: Vector3 = author.point(pose,"middle_01_"+side_)-base.origin
		var across: Vector3 = author.point(pose,"index_01_"+side_)-author.point(pose,"pinky_01_"+side_)
		var hands = preload("res://scripts/hand_setting_pose.gd")
		var basis: Basis = hands.hand_basis(Vector3(0,.92,.38),Vector3(0,-.38,.92)*sign_)*hands.hand_basis(along,across).inverse()*base.basis
		var tip := center+Vector3(sign_*lerpf(.21,.015,closed),.012*sign_,0)
		var target: Vector3 = tip-basis*(base.basis.inverse()*along)
		author.limb(pose,"upperarm_"+side_,"lowerarm_"+side_,wrist,target,Vector3(sign_*.75,-.7,0),blend)
		author.set_world_basis(pose,wrist,author.world_pose(pose,rig.find_bone(wrist)).basis.slerp(basis,blend))
		for name_ in ["upperarm_"+side_,"lowerarm_"+side_,wrist]:
			var idx := rig.find_bone(name_)
			rig.set_bone_pose_rotation(idx,pose[idx].basis.orthonormalized().get_rotation_quaternion())
