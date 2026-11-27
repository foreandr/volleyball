extends SkeletonModifier3D

var scales := {}
var lengths := {}
var shoulders:=PackedInt32Array()
var overhead_lift:=0.

func configure(profile: Dictionary) -> void:
	active=true
	var rig := get_parent() as Skeleton3D
	scales.clear()
	lengths.clear()
	scales[rig.find_bone("Head")]=clampf(profile.head_in/22.,.85,1.18)
	var arm_length := clampf(profile.wingspan_in/(profile.height_cm/2.54),.80,1.20)
	shoulders.clear()
	var natural:=preload("res://scripts/player_profile.gd").natural_reach(profile.height_cm/2.54,profile.wingspan_in)
	overhead_lift=clampf((profile.reach_in-natural)*.0254,-.075,.075)
	for side in ["l","r"]:
		scales[rig.find_bone("hand_"+side)]=clampf(profile.hand_in/8.,.78,1.25)
		scales[rig.find_bone("foot_"+side)]=clampf(profile.foot_in/10.,.82,1.22)
		lengths[rig.find_bone("lowerarm_"+side)]=arm_length
		lengths[rig.find_bone("hand_"+side)]=arm_length
		shoulders.append(rig.find_bone("clavicle_"+side))

func _process_modification() -> void:
	var rig := get_skeleton()
	for clavicle in shoulders:
		if clavicle<0 or is_zero_approx(overhead_lift): continue
		var hand:=rig.find_bone("hand_"+str(rig.get_bone_name(clavicle)).right(1))
		var rise:=rig.get_bone_global_pose(hand).origin.y-rig.get_bone_global_pose(clavicle).origin.y
		var parent:=rig.get_bone_global_pose(rig.get_bone_parent(clavicle))
		var displacement:=parent.basis.inverse()*Vector3.UP*overhead_lift*smoothstep(-.08,.32,rise)
		rig.set_bone_pose_position(clavicle,rig.get_bone_pose_position(clavicle)+displacement)
	for index in scales:
		rig.set_bone_pose_scale(index,rig.get_bone_pose_scale(index)*float(scales[index]))
	for index in lengths:
		rig.set_bone_pose_position(index,rig.get_bone_pose_position(index)*float(lengths[index]))
