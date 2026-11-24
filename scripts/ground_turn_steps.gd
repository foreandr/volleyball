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
var hip_lag := 0.0
var planted_weight := 1.0

var right_pivot_local := Vector3.ZERO
var pivot_point := Vector3.ZERO
var scripted := false
var sequence := -1.0
var finish_yaw := 0.0

func set_sequence(fraction: float, enabled: bool, heading := 0.0) -> void:
	finish_yaw=heading
	if fraction<0.:
		contacts.clear()
		step_active=false
		hip_lag=0.
	scripted=enabled
	sequence=fraction

func _process_modification() -> void:
	if not actor: return
	var rig := get_skeleton()
	var current := actor.global_transform
	var dt := clampf(get_process_delta_time(),.001,.08)
	# atan2 remains continuous through a half-turn and across mirrored courts.
	var angle := angle_difference(atan2(previous.basis.z.x,previous.basis.z.z),atan2(current.basis.z.x,current.basis.z.z))
	var travel := (current.origin-previous.origin).slide(Vector3.UP).length()
	previous=current
	if scripted and sequence<0.: return
	if not initialized or actor.position.y>.065 or travel>maxf(.045,dt*1.3) or absf(angle)>.70:
		initialized=true
		contacts.clear()
		step_active=false
		hip_lag=0.
		return
	var rotating := absf(angle)>deg_to_rad(.10)
	if contacts.is_empty() and not rotating and not scripted: return
	var desired: Array[Transform3D]=[]
	for side in ["l","r"]:
		desired.append(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("foot_"+side)))
	var author: RefCounted=actor.get_pose_author()
	if contacts.is_empty():
		contacts.assign(desired)
		if scripted:
			var toes: Vector3=author.point(author.baseline,"ball_r")
			right_pivot_local=author.feet["r"].affine_inverse()*toes
			pivot_point=desired[1]*right_pivot_local
		swing=1 # Right plant, then bring the left foot around.
		planted_weight=1.
		progress=0.
		step_duration=clampf(.72/maxf(.01,absf(angle)/dt),.18,.28)
	if scripted:
		swing=1 if sequence<.38 else 0
		progress=clampf(sequence/.38 if swing==1 else (sequence-.38)/.62,0.,1.)
	elif progress == 0. and not step_active:
		var offset := (desired[swing].origin - contacts[swing].origin).slide(Vector3.UP).length()
		if swing==0 or (rotating and offset >= .035):
			step_active = true
			planted_weight=1.
		elif not rotating:
			planted_weight=move_toward(planted_weight,0.,dt/.14)
			if planted_weight<=0.:
				contacts.clear()
				return
	if step_active and not scripted:
		progress=minf(1.,progress+dt/step_duration)
	if swing==1:
		hip_lag=clampf(hip_lag-angle*.45,-.24,.24)
	else:
		hip_lag=lerpf(hip_lag,0.,minf(1.,dt/maxf(dt,step_duration*(1.-progress))))
	var landing := desired[swing]
	var advance := clampf(angle/dt,-3.,3.)*.09
	landing.origin=current.origin+(landing.origin-current.origin).rotated(Vector3.UP,advance)
	if scripted:
		var side := "r" if swing==1 else "l"
		var ready_right: Transform3D=rig.global_transform*author.feet["r"]
		var ready_left: Transform3D=rig.global_transform*author.feet["l"]
		if swing==1:
			landing=ready_right
			# Plant under the finishing hip so the left leg can open to its full width.
			var remaining := angle_difference(actor.rotation.y,finish_yaw)
			var toe := landing*right_pivot_local
			var final_toe := current.origin+(toe-current.origin).rotated(Vector3.UP,remaining)
			landing.origin+=final_toe-toe
		else:
			# Keep the ball of the right foot planted while the ankle and knee follow the hips.
			var support := ready_right
			support.basis=Basis(Vector3.UP,hip_lag)*support.basis
			support.origin=pivot_point-support.basis*right_pivot_local
			support.origin.y-=preload("res://scripts/practice_joint_limits.gd").sole_floor_gap(rig,"r",support)
			contacts[1]=support
			landing=ready_left
			var stance_axis := current.basis.x.slide(Vector3.UP).normalized()
			var ready_span := (ready_left.origin-ready_right.origin).dot(stance_axis)
			var current_span := (landing.origin-support.origin).dot(stance_axis)
			landing.origin+=stance_axis*(ready_span*1.12-current_span)
		landing.origin.y-=preload("res://scripts/practice_joint_limits.gd").sole_floor_gap(rig,side,landing)
		if swing==1:
			pivot_point=landing*right_pivot_local
	var moving := contacts[swing].interpolate_with(landing,smoothstep(0.,1.,progress))
	var arc := sin(PI*progress)
	arc *= arc
	moving.origin.y+=((.125 if swing==0 else .078) if scripted else (.052 if swing==0 else .035))*arc
	if swing==0:
		var outward := (landing.origin-current.origin).slide(Vector3.UP).normalized()
		moving.origin+=outward*(.095 if scripted else .027)*arc
	var pose: Array=[]
	for i in rig.get_bone_count(): pose.append(rig.get_bone_pose(i))
	var pelvis := rig.find_bone("pelvis")
	author.rotate_world(pose,"pelvis",Vector3.UP,hip_lag*planted_weight)
	rig.set_bone_pose_rotation(pelvis,pose[pelvis].basis.orthonormalized().get_rotation_quaternion())
	for i in 2:
		var side := "l" if i==0 else "r"
		var thigh := "thigh_"+side
		var calf := "calf_"+side
		var foot := "foot_"+side
		var planted := moving if i==swing else contacts[i]
		var goal := rig.global_transform.affine_inverse()*desired[i].interpolate_with(planted,planted_weight)
		var hip: Vector3=author.point(pose,thigh)
		var axis: Vector3=(author.point(pose,foot)-hip).normalized()
		var knee: Vector3=(author.point(pose,calf)-hip).slide(axis)
		if knee.length_squared()<.00001: knee=Vector3.BACK
		author.limb(pose,thigh,calf,foot,goal.origin,knee.normalized(),1.,180.,true)
		author.set_world_basis(pose,foot,goal.basis.orthonormalized())
		for bone in [thigh,calf,foot]:
			var id := rig.find_bone(bone)
			rig.set_bone_pose_rotation(id,pose[id].basis.orthonormalized().get_rotation_quaternion())
	if progress>=1. and not scripted:
		contacts[swing]=moving
		swing=1-swing
		progress=0.
		step_duration=.32 if swing==0 else .22
		step_active=false
