extends SkeletonModifier3D

var target: Node3D
var angles := Vector2.ZERO
var previous_origin := Vector3.INF

func _process_modification() -> void:
	var rig := get_skeleton()
	var head := rig.find_bone("Head")
	if head<0: return
	var dt := clampf(get_process_delta_time(),.001,.05)
	var origin := rig.global_position
	var speed := 0. if not previous_origin.is_finite() else (origin-previous_origin).slide(Vector3.UP).length()/dt
	previous_origin=origin
	var desired := Vector2.ZERO
	var parent_id := rig.get_bone_parent(head)
	var parent := rig.get_bone_global_pose(parent_id).basis.orthonormalized()
	var neutral_frame := parent*rig.get_bone_global_rest(parent_id).basis.orthonormalized().inverse()
	var rest := rig.get_bone_rest(head).basis.orthonormalized()
	if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree():
		var local := neutral_frame.inverse()*(rig.to_local(target.global_position)-rig.get_bone_global_pose(head).origin)
		var yaw := atan2(local.x,local.z)
		var pitch := atan2(local.y,Vector2(local.x,local.z).length())
		var weight := (1.-smoothstep(1.6,2.5,absf(yaw)))*(1.-smoothstep(3.6,6.2,speed))
		desired=Vector2(clampf(yaw,-.85,.85),clampf(pitch,-.48,.68))*weight
	angles=angles.move_toward(desired,dt*2.6)
	if angles.length_squared()<.00001: return
	var rotation := Basis(Vector3.UP,angles.x)*Basis(Vector3.RIGHT,-angles.y)
	var aimed := parent.inverse()*neutral_frame*rotation*neutral_frame.inverse()*parent*rest
	var authored := rig.get_bone_pose_rotation(head)
	rig.set_bone_pose_rotation(head,authored.slerp(aimed.orthonormalized().get_rotation_quaternion(),smoothstep(0.,.15,angles.length())*.85))
