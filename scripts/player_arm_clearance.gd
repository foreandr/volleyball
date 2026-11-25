extends SkeletonModifier3D

func _process_modification() -> void:
	var rig := get_skeleton()
	if rig:
		resolve(rig,"r")
		resolve(rig,"l")

static func resolve(rig: Skeleton3D, side: String) -> bool:
	var other := "r" if side=="l" else "l"
	var bone_point := func(name_: String) -> Vector3:
		return rig.get_bone_global_pose(rig.find_bone(name_)).origin
	var shoulder: Vector3=bone_point.call("upperarm_"+side)
	var outside: Vector3=(shoulder-bone_point.call("upperarm_"+other)).normalized()
	var width: float=shoulder.distance_to(bone_point.call("upperarm_"+other))
	var head: Vector3=bone_point.call("Head")
	var up: Vector3=(head-bone_point.call("neck_01")).normalized()
	var centers := [head+up*width*.18,bone_point.call("spine_03"),bone_point.call("spine_02"),bone_point.call("spine_01")]
	var radii := [.51,.55,.54,.49]
	var upper := rig.find_bone("upperarm_"+side)
	var changed := false
	for attempt in 12:
		var elbow: Vector3=bone_point.call("lowerarm_"+side)
		var wrist: Vector3=bone_point.call("hand_"+side)
		var tip: Vector3=bone_point.call("middle_03_"+side)
		var chain := [shoulder.lerp(elbow,.55),elbow,wrist,tip]
		var depth := 0.
		var axis := Vector3.ZERO
		var turn := 0.
		for j in centers.size():
			for i in range(chain.size()-1):
				var near := Geometry3D.get_closest_point_to_segment(centers[j],chain[i],chain[i+1])
				var offset: Vector3=near-centers[j]
				var overlap: float=width*radii[j]-offset.length()
				if overlap<=depth: continue
				var lever := near-shoulder
				var push := offset.slide(lever.normalized())
				if push.length()<.01: push=outside.slide(lever.normalized())
				var normal := lever.cross(push)
				if normal.length_squared()<.000001: continue
				depth=overlap
				axis=normal.normalized()
				turn=minf(.18,(overlap+.002)/maxf(.04,lever.length()))
		if depth<.001: break
		changed=true
		var joint := rig.get_bone_global_pose(upper)
		joint.basis=Basis(axis,turn)*joint.basis
		var parent := rig.get_bone_global_pose(rig.get_bone_parent(upper))
		rig.set_bone_pose_rotation(upper,(parent.basis.inverse()*joint.basis).orthonormalized().get_rotation_quaternion())
	return changed
