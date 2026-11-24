extends SkeletonModifier3D

# The support ankle keeps its court-space transform for one step. The opposite
# ankle travels to the new stance, clearing the floor before taking weight.
var actor: Node3D
var previous := Transform3D.IDENTITY
var initialized := false
var contacts: Array[Transform3D] = []
var swing := 0
var progress := 0.0
var step_duration := .22
var step_active := false

func _process_modification() -> void:
	if not actor: return
	var rig := get_skeleton()
	var current := actor.global_transform
	var dt := clampf(get_process_delta_time(),.001,.08)
	# atan2 remains continuous through a half-turn and across mirrored courts.
	var angle := angle_difference(atan2(previous.basis.z.x,previous.basis.z.z),atan2(current.basis.z.x,current.basis.z.z))
	var travel := (current.origin-previous.origin).slide(Vector3.UP).length()
	previous=current
	if not initialized or actor.position.y>.065 or travel>maxf(.045,dt*1.3) or absf(angle)>.70:
		initialized=true
		contacts.clear()
		step_active=false
		return
	var rotating := absf(angle)>deg_to_rad(.10)
	if contacts.is_empty() and not rotating: return
	var desired: Array[Transform3D]=[]
	for side in ["l","r"]:
		desired.append(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("foot_"+side)))
	if contacts.is_empty():
		contacts.assign(desired)
		swing=0 if angle>0 else 1
		progress=0.
		step_duration=clampf(1.0/maxf(.01,absf(angle)/dt),.27,.43)
	if progress == 0. and not step_active:
		var offset := (desired[swing].origin - contacts[swing].origin).slide(Vector3.UP).length()
		if offset >= .065:
			step_active = true
		elif not rotating:
			contacts.clear()
			return
	if step_active: progress=minf(1.,progress+dt/step_duration)
	var landing := desired[swing]
	var advance := clampf(angle/dt,-3.,3.)*.09
	landing.origin=current.origin+(landing.origin-current.origin).rotated(Vector3.UP,advance)
	var moving := contacts[swing].interpolate_with(landing,smoothstep(0.,1.,progress))
	moving.origin.y+=.048*sin(PI*progress)
	var author: RefCounted=actor.get_pose_author()
	var pose: Array=[]
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	for i in 2:
		var side := "l" if i==0 else "r"
		var thigh := "thigh_"+side
		var calf := "calf_"+side
		var foot := "foot_"+side
		var goal := rig.global_transform.affine_inverse()*(moving if i==swing else contacts[i])
		var hip: Vector3=author.point(pose,thigh)
		var axis: Vector3=(author.point(pose,foot)-hip).normalized()
		var knee: Vector3=(author.point(pose,calf)-hip).slide(axis)
		if knee.length_squared()<.00001: knee=Vector3.BACK
		author.limb(pose,thigh,calf,foot,goal.origin,knee.normalized(),1.,180.,true)
		author.set_world_basis(pose,foot,goal.basis.orthonormalized())
		for bone in [thigh,calf,foot]:
			var id := rig.find_bone(bone)
			rig.set_bone_pose_rotation(id,pose[id].basis.orthonormalized().get_rotation_quaternion())
	if progress>=1.:
		contacts[swing]=moving
		swing=1-swing
		progress=0.
		step_duration=clampf(1.0/maxf(.01,absf(angle)/dt),.27,.43)
		step_active=false
