extends SkeletonModifier3D

var scales := {}
var lengths := {}

func configure(profile: Dictionary) -> void:
	active=true
	var rig := get_parent() as Skeleton3D
	scales.clear()
	lengths.clear()
	scales[rig.find_bone("Head")]=clampf(profile.head_in/22.,.85,1.18)
	var arm_length := clampf(profile.wingspan_in/(profile.height_cm/2.54),.80,1.20)
	var lift := clampf(profile.reach_in/96.,.90,1.10)
	for side in ["l","r"]:
		scales[rig.find_bone("hand_"+side)]=clampf(profile.hand_in/8.,.78,1.25)
		scales[rig.find_bone("foot_"+side)]=clampf(profile.foot_in/10.,.82,1.22)
		lengths[rig.find_bone("lowerarm_"+side)]=arm_length
		lengths[rig.find_bone("hand_"+side)]=arm_length*lift

func _process_modification() -> void:
	var rig := get_skeleton()
	for index in scales:
		rig.set_bone_pose_scale(index,rig.get_bone_pose_scale(index)*float(scales[index]))
	for index in lengths:
		rig.set_bone_pose_position(index,rig.get_bone_pose_position(index)*float(lengths[index]))
