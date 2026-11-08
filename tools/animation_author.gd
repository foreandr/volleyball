extends RefCounted
## Shared authoring: model-space body targets, local-space skeletal output.
const PREFIX := "Armature/Skeleton3D:"
var rig: Skeleton3D
var baseline: Array = []
var feet := {}
var recipe: Dictionary

func _init(skeleton: Skeleton3D, starting_pose: Animation) -> void:
	rig = skeleton
	for bone in rig.get_bone_count():
		var local := rig.get_bone_rest(bone)
		var path := NodePath(PREFIX+rig.get_bone_name(bone))
		var position := starting_pose.find_track(path,Animation.TYPE_POSITION_3D)
		var rotation := starting_pose.find_track(path,Animation.TYPE_ROTATION_3D)
		if position >= 0: local.origin = starting_pose.position_track_interpolate(position,0)
		if rotation >= 0: local.basis = Basis(starting_pose.rotation_track_interpolate(rotation,0))
		baseline.append(local)
	for side in ["l","r"]: feet[side] = world_pose(baseline,rig.find_bone("foot_"+side))

func bake(description: Dictionary, pose_provider := Callable()) -> Animation:
	recipe = description
	var clip := Animation.new()
	clip.resource_name = recipe.name
	clip.length = recipe.duration
	clip.loop_mode = Animation.LOOP_LINEAR
	var position_tracks := []
	var rotation_tracks := []
	for bone in rig.get_bone_count():
		var path := NodePath(PREFIX+rig.get_bone_name(bone))
		var position := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(position,path)
		position_tracks.append(position)
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation,path)
		rotation_tracks.append(rotation)
	for frame in range(ceili(clip.length*60)+1):
		var time := minf(clip.length,float(frame)/60)
		var pose: Array = pose_provider.call(time) if pose_provider.is_valid() else pose_at(time)
		for bone in rig.get_bone_count():
			clip.position_track_insert_key(position_tracks[bone],time,pose[bone].origin)
			clip.rotation_track_insert_key(rotation_tracks[bone],time,pose[bone].basis.get_rotation_quaternion().normalized())
	clip.set_meta("contact_time",recipe.contact_time)
	clip.set_meta("baseline","Goalkeeper Idle.fbx")
	return clip

func bake_overrides(source: Animation, pose_provider: Callable, bones: Array[String]) -> Animation:
	var clip: Animation = source.duplicate(true)
	var tracks := {}
	for name_ in bones:
		var path := NodePath(PREFIX+name_)
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D]:
			var track := clip.find_track(path,type)
			if track >= 0: clip.remove_track(track)
	for name_ in bones:
		var bone := rig.find_bone(name_)
		var path := NodePath(PREFIX+name_)
		var position := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(position,path)
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation,path)
		tracks[bone] = [position,rotation]
	for frame in range(ceili(clip.length*60)+1):
		var time := minf(clip.length,float(frame)/60)
		var pose: Array = pose_provider.call(time)
		for bone in tracks:
			clip.position_track_insert_key(tracks[bone][0],time,pose[bone].origin)
			clip.rotation_track_insert_key(tracks[bone][1],time,pose[bone].basis.get_rotation_quaternion().normalized())
	return clip

func parameters(time: float) -> Dictionary:
	var phases: Array = recipe.phases
	var a: Dictionary = phases[0]
	var b: Dictionary = phases[1]
	for index in range(phases.size()-1):
		if time >= phases[index].time:
			a = phases[index]
			b = phases[index+1]
	var weight := smoothstep(float(a.time),float(b.time),time)
	var values := {}
	for key in a:
		if key == "time": continue
		if a[key] is Array:
			values[key] = Vector3(a[key][0],a[key][1],a[key][2]).lerp(Vector3(b[key][0],b[key][1],b[key][2]),weight)
		else: values[key] = lerpf(float(a[key]),float(b[key]),weight)
	return values

func pose_at(time: float) -> Array:
	var values := parameters(time)
	var pose := baseline.duplicate()
	var pelvis := rig.find_bone("pelvis")
	var parent := rig.get_bone_parent(pelvis)
	# Bone translations must be converted from model coordinates to parent space.
	pose[pelvis].origin += world_pose(pose,parent).basis.inverse()*values.hips
	rotate_world(pose,"spine_02",Vector3.RIGHT,deg_to_rad(values.torso_lean*0.55))
	rotate_world(pose,"spine_03",Vector3.RIGHT,deg_to_rad(values.torso_lean*0.45))
	rotate_world(pose,"neck_01",Vector3.RIGHT,deg_to_rad(values.head_pitch-values.torso_lean*0.8))
	for name_ in recipe.get("joint_offsets",{}):
		var angles: Array = recipe.joint_offsets[name_]
		for axis in range(3):
			rotate_world(pose,name_,[Vector3.RIGHT,Vector3.UP,Vector3.BACK][axis],deg_to_rad(float(angles[axis])*values.platform))
	var shoulder_center := (point(pose,"upperarm_l")+point(pose,"upperarm_r"))*0.5
	for side in ["l","r"]:
		var sign_ := 1.0 if side == "l" else -1.0
		if values.platform > 0.0001:
			var knee_pole := point(baseline,"calf_"+side)-point(baseline,"thigh_"+side)
			limb(pose,"thigh_"+side,"calf_"+side,"foot_"+side,feet[side].origin,knee_pole)
			set_world_basis(pose,"foot_"+side,feet[side].basis)
			var wrist: Vector3 = values["wrist_"+side]
			var target := shoulder_center+wrist
			var current_pole := (point(pose,"lowerarm_"+side)-point(pose,"upperarm_"+side)).normalized()
			var pole_rotation := Quaternion(current_pole,values["elbow_"+side].normalized())
			var elbow_pole: Vector3 = Quaternion.IDENTITY.slerp(pole_rotation,values.platform)*current_pole
			limb(pose,"upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,elbow_pole,values.platform,float(values.get("elbow_extension",180)))
		if values.grip > 0.0001:
			var hand: String = "hand_"+side
			var fingers: String = "index_01_"+side
			var before := world_pose(pose,rig.find_bone(hand)).basis
			var arm_axis := (point(pose,hand)-point(pose,"lowerarm_"+side)).normalized()
			var index_vector := point(pose,fingers)-point(pose,hand)
			var pinky_vector := point(pose,"pinky_01_"+side)-point(pose,hand)
			var palm_normal := index_vector.cross(pinky_vector).normalized()*(-1.0 if side == "l" else 1.0)
			var projected := (palm_normal-arm_axis*palm_normal.dot(arm_axis)).normalized()
			var palm_direction: Vector3 = values["palm_"+side]
			var down := (palm_direction-arm_axis*palm_direction.dot(arm_axis)).normalized()
			var roll: float = projected.signed_angle_to(down,arm_axis)*values.grip
			var upper_axis := (point(pose,"lowerarm_"+side)-point(pose,"upperarm_"+side)).normalized()
			var forearm_basis := world_pose(pose,rig.find_bone("lowerarm_"+side)).basis
			rotate_world(pose,"upperarm_"+side,upper_axis,roll*float(values.get("upperarm_roll_share",0.35)))
			set_world_basis(pose,"lowerarm_"+side,Basis(arm_axis,roll)*forearm_basis)
			var direction := (Basis(Vector3.RIGHT,deg_to_rad(values.wrist_flex))*Vector3(0,arm_axis.y,arm_axis.z)).normalized()
			aim_joint(pose,hand,fingers,point(pose,hand)+direction)
			index_vector = point(pose,fingers)-point(pose,hand)
			pinky_vector = point(pose,"pinky_01_"+side)-point(pose,hand)
			var normal := index_vector.cross(pinky_vector).normalized()*(-1.0 if side == "l" else 1.0)
			var palm := (palm_direction-direction*palm_direction.dot(direction)).normalized()
			rotate_world(pose,hand,direction,normal.signed_angle_to(palm,direction))
			var desired := world_pose(pose,rig.find_bone(hand)).basis
			set_world_basis(pose,hand,Basis(before.get_rotation_quaternion().slerp(desired.get_rotation_quaternion(),values.grip)))
			for finger in ["index","middle","ring","pinky"]:
				for segment in range(1,4):
					var bone := rig.find_bone("%s_%02d_%s" % [finger,segment,side])
					var bent := rig.get_bone_rest(bone).basis*Basis(Vector3.RIGHT,deg_to_rad(values["curl_"+side]))
					pose[bone].basis = Basis(baseline[bone].basis.get_rotation_quaternion().slerp(bent.get_rotation_quaternion(),values.grip))
	if values.grip > 0.0001: pose_thumbs(pose,values.grip,values.wrist_flex)
	return pose

func pose_thumbs(pose: Array, strength: float, flex: float) -> void:
	var axis := ((point(pose,"hand_l")-point(pose,"lowerarm_l"))+(point(pose,"hand_r")-point(pose,"lowerarm_r"))).normalized()
	axis = (Basis(Vector3.RIGHT,deg_to_rad(flex))*Vector3(0,axis.y,axis.z)).normalized()
	for side in ["l","r"]:
		for segment in [1,2]:
			var name_: String = "thumb_0"+str(segment)+"_"+side
			var bone := rig.find_bone(name_)
			var children := rig.get_bone_children(bone)
			if children.is_empty(): continue
			var child := str(rig.get_bone_name(children[0]))
			var before := world_pose(pose,bone).basis
			aim_joint(pose,name_,child,point(pose,name_)+axis)
			var desired := world_pose(pose,bone).basis
			set_world_basis(pose,name_,Basis(before.get_rotation_quaternion().slerp(desired.get_rotation_quaternion(),strength)))

func world_pose(pose: Array, bone: int) -> Transform3D:
	var parent := rig.get_bone_parent(bone)
	return pose[bone] if parent < 0 else world_pose(pose,parent)*pose[bone]

func point(pose: Array, bone: String) -> Vector3:
	return world_pose(pose,rig.find_bone(bone)).origin

func set_world_basis(pose: Array, bone: String, basis: Basis) -> void:
	var index := rig.find_bone(bone)
	var parent := rig.get_bone_parent(index)
	var parent_basis := Basis.IDENTITY if parent < 0 else world_pose(pose,parent).basis
	pose[index].basis = (parent_basis.inverse()*basis).orthonormalized()

func rotate_world(pose: Array, bone: String, axis: Vector3, angle: float) -> void:
	set_world_basis(pose,bone,Basis(axis,angle)*world_pose(pose,rig.find_bone(bone)).basis)

func aim_joint(pose: Array, joint: String, end: String, target: Vector3) -> void:
	var origin := point(pose,joint)
	var from := (point(pose,end)-origin).normalized()
	var to := (target-origin).normalized()
	var rotation := Quaternion(from,to)
	set_world_basis(pose,joint,Basis(rotation)*world_pose(pose,rig.find_bone(joint)).basis)

func limb(pose: Array, start: String, middle: String, end: String, target: Vector3, pole: Vector3, blend := 1.0, extension_limit := 180.0) -> void:
	var origin := point(pose,start)
	var old_middle := point(pose,middle)
	var old_end := point(pose,end)
	var old_upper_basis := world_pose(pose,rig.find_bone(start)).basis
	var old_lower_basis := world_pose(pose,rig.find_bone(middle)).basis
	var reference_normal := (old_middle-origin).cross(old_end-old_middle).normalized()
	if reference_normal.length_squared() < 0.01: reference_normal = pole.cross(old_end-origin).normalized()
	var reference_upper := limb_frame(old_middle-origin,reference_normal)
	var reference_lower := limb_frame(old_end-old_middle,reference_normal)
	var upper := origin.distance_to(old_middle)
	var lower := old_middle.distance_to(old_end)
	var from_axis := (old_end-origin).normalized()
	var to_axis := (target-origin).normalized()
	var axis: Vector3 = Quaternion.IDENTITY.slerp(Quaternion(from_axis,to_axis),blend)*from_axis
	var maximum := minf(upper+lower-0.001,sqrt(maxf(0.00001,upper*upper+lower*lower-2*upper*lower*cos(deg_to_rad(extension_limit)))))
	var target_distance := clampf(origin.distance_to(target),absf(upper-lower)+0.001,maximum)
	var start_angle := acos(clampf((upper*upper+lower*lower-origin.distance_squared_to(old_end))/(2.0*upper*lower),-1,1))
	var target_angle := acos(clampf((upper*upper+lower*lower-target_distance*target_distance)/(2.0*upper*lower),-1,1))
	var elbow_angle := lerpf(start_angle,target_angle,blend)
	var distance := sqrt(maxf(0.00001,upper*upper+lower*lower-2.0*upper*lower*cos(elbow_angle)))
	var along := (upper*upper+distance*distance-lower*lower)/(2.0*distance)
	var bend := (pole-axis*axis.dot(pole)).normalized()
	var elbow := origin+axis*along+bend*sqrt(maxf(0,upper*upper-along*along))
	var end_point := origin+axis*distance
	var normal := (elbow-origin).cross(end_point-elbow).normalized()
	set_world_basis(pose,start,limb_frame(elbow-origin,normal)*reference_upper.inverse()*old_upper_basis)
	set_world_basis(pose,middle,limb_frame(end_point-elbow,normal)*reference_lower.inverse()*old_lower_basis)

func limb_frame(direction: Vector3, normal: Vector3) -> Basis:
	var x := direction.normalized()
	var y := (normal-x*normal.dot(x)).normalized()
	if y.length_squared() < 0.01: y = x.cross(Vector3.UP).normalized()
	return Basis(x,y,x.cross(y)).orthonormalized()

