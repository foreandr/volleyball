extends SkeletonModifier3D

# Applied to the final animated skeleton, including procedural reaches and
# ducking. Angles here are local deviations from the rig's neutral rotation.
var joints: Array[int]=[]
var neutral: Array[Quaternion]=[]
var excursion: Array[float]=[]
var previous: Array[Quaternion]=[]
var max_rate: Array[float]=[]

func _process_modification() -> void:
	var rig := get_skeleton()
	if joints.is_empty():
		for i in rig.get_bone_count():
			var bone := String(rig.get_bone_name(i))
			var cone := 0.
			var rate := 540.
			if bone.begins_with("spine"): cone=38.; rate=210.
			elif bone in ["neck_01","Head"]: cone=55.; rate=250.
			elif bone.begins_with("upperarm") or bone.begins_with("thigh"): cone=160.
			elif bone.begins_with("lowerarm") or bone.begins_with("calf"): cone=165.
			elif bone.begins_with("hand_") or bone.begins_with("foot_"): cone=95.
			else: continue
			joints.append(i)
			neutral.append(rig.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion())
			previous.append(rig.get_bone_pose_rotation(i))
			excursion.append(deg_to_rad(cone))
			max_rate.append(deg_to_rad(rate))
	var dt := clampf(get_process_delta_time(),0.,.05)
	for j in joints.size():
		var q := rig.get_bone_pose_rotation(joints[j]).normalized()
		var span := neutral[j].angle_to(q)
		if span>excursion[j]: q=neutral[j].slerp(q,excursion[j]/span)
		var change := previous[j].angle_to(q)
		if change>max_rate[j]*dt: q=previous[j].slerp(q,max_rate[j]*dt/change)
		rig.set_bone_pose_rotation(joints[j],q)
		previous[j]=q
