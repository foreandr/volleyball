extends SkeletonModifier3D

# Applied to the final animated skeleton, including procedural reaches and
# ducking. Angles here are local deviations from the rig's neutral rotation.
var joints: Array[int]=[]
var neutral: Array[Quaternion]=[]
var excursion: Array[float]=[]
var previous: Array[Quaternion]=[]
var max_rate: Array[float]=[]
var push_arm: Array[bool]=[]

var hand_joints: Array[int]=[]
var editor_bones: Array[Transform3D] = []
var replay_bones: Array[Transform3D] = []

func _process_modification() -> void:
	var rig := get_skeleton()
	if joints.is_empty():
		for i in rig.get_bone_count():
			var bone := String(rig.get_bone_name(i))
			if bone.get_slice("_",0) in ["hand","thumb","index","middle","ring","pinky"]: hand_joints.append(i)
			var cone := 0.
			var rate := 540.
			if bone.begins_with("spine"): cone=38.; rate=210.
			elif bone in ["neck_01","Head"]: cone=55.; rate=250.
			elif bone.begins_with("upperarm") or bone.begins_with("thigh"): cone=160.
			elif bone.begins_with("lowerarm") or bone.begins_with("calf"): cone=165.
			elif bone.begins_with("hand_") or bone.begins_with("foot_"): cone=95.
			else: continue
			joints.append(i)
			push_arm.append(bone.begins_with("upperarm") or bone.begins_with("lowerarm") or bone.begins_with("hand_"))
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
		var rate := deg_to_rad(1800.) if push_arm[j] and rig.get_meta("fast_set_push",false) else max_rate[j]
		if change>rate*dt: q=previous[j].slerp(q,rate*dt/change)
		rig.set_bone_pose_rotation(joints[j],q)
		previous[j]=q

	if rig.get_meta("fixed_setting_hands",false):
		for joint in hand_joints:
			rig.set_bone_pose_rotation(joint,rig.get_bone_rest(joint).basis.get_rotation_quaternion())
	enforce_court_floor(rig)
	if not editor_bones.is_empty():
		for i in rig.get_bone_count(): editor_bones[i]=rig.get_bone_pose(i)
		editor_bones=[]
	if not replay_bones.is_empty():
		for i in rig.get_bone_count(): replay_bones[i] = rig.get_bone_pose(i)
		replay_bones = []

static var sole_hulls := {}

static func sole_floor_gap(rig: Skeleton3D, side: String, ankle: Transform3D) -> float:
	if not rig.has_meta("sole_"+side): return 0.
	var sole: Node3D=rig.get_meta("sole_"+side)
	if not sole: return 0.
	var shoe := sole.get_child(0) as MeshInstance3D
	if not sole_hulls.has(shoe.mesh):
		sole_hulls[shoe.mesh]=shoe.mesh.create_convex_shape(true,false).points
	var frame := ankle*sole.transform*shoe.transform
	var gap := INF
	for local: Vector3 in sole_hulls[shoe.mesh]:
		var point := frame*local
		gap=minf(gap,point.y-floor_height(point))
	return gap

func enforce_court_floor(rig: Skeleton3D) -> void:
	var lift := 0.0
	for side in ["l","r"]:
		var ankle := rig.find_bone("foot_"+side)
		var frame := rig.global_transform*rig.get_bone_global_pose(ankle)
		lift=maxf(lift,-sole_floor_gap(rig,side,frame))
	for bone in ["Head","pelvis","spine_03","calf_l","calf_r","lowerarm_l","lowerarm_r","hand_l","hand_r","middle_03_l","middle_03_r"]:
		var index := rig.find_bone(bone)
		if index < 0: continue
		var point := rig.to_global(rig.get_bone_global_pose(index).origin)
		var radius := 0.09 if bone in ["Head","pelvis","spine_03"] else 0.035
		lift = maxf(lift,floor_height(point)+radius-point.y)
	if lift > 0:
		var root := rig.find_bone("pelvis")
		var parent := rig.get_bone_parent(root)
		var basis := rig.global_basis
		if parent >= 0: basis *= rig.get_bone_global_pose(parent).basis
		rig.set_bone_pose_position(root,rig.get_bone_pose_position(root)+basis.inverse()*(Vector3.UP*lift))

static func floor_height(point: Vector3) -> float:
	return 0.04 if absf(point.x)<=4.5 and point.z>=-5.0 and point.z<=13.0 else -0.02
