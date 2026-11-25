extends RefCounted

# Deterministic pose envelopes give each number the same motion on every visit.
static func make(source: Animation, number: int, rig: Skeleton3D=null) -> Animation:
	var clip := source.duplicate() as Animation
	var rng := RandomNumberGenerator.new()
	rng.seed=524287*number
	var hit := int(source.get_meta("swing_hit_frame"))
	var offset_frames := int(source.get_meta("swing_frame_offset",0))
	var peak := offset_frames+rng.randf_range(19.,28.)
	var release := rng.randf_range(3.,7.)
	for joint in ["upperarm_r","lowerarm_r","hand_r"]:
		var path := NodePath("Armature/Skeleton3D:"+str(joint))
		var track := source.find_track(path,Animation.TYPE_ROTATION_3D)
		if track<0: continue
		var width := Vector3(40,54,40) if joint=="upperarm_r" else Vector3(30,18,22)
		if joint=="hand_r": width=Vector3.ZERO # The hand inherits the spin-specific, constrained wrist track.
		var draw := rotation(rng,width)
		var drive := rotation(rng,width*.58)
		rotation(rng,width*1.12) # Preserve the seeded draw and drive for the next joint.
		clip.remove_track(clip.find_track(path,Animation.TYPE_ROTATION_3D))
		var out := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(out,path)
		for frame in range(ceili(source.length*60.)+1):
			var time := minf(frame/60.,source.length)
			var gather := smoothstep(offset_frames+10.,peak,frame)*(1.-smoothstep(peak,hit-release,frame))
			var whip := smoothstep(peak-2.,hit-release,frame)*(1.-smoothstep(hit-release,hit-1.,frame))
			var offset := Quaternion.IDENTITY.slerp(draw,gather)*Quaternion.IDENTITY.slerp(drive,whip)
			clip.rotation_track_insert_key(out,time,source.rotation_track_interpolate(track,time)*offset)
	if rig!=null and hit>offset_frames+16:
		align_draw_palm(clip,rig,offset_frames,hit)
	if hit>=0:
		var hand := clip.find_track(NodePath("Armature/Skeleton3D:hand_r"),Animation.TYPE_ROTATION_3D)
		if hand>=0:
			for key in clip.track_get_key_count(hand):
				var relative_frame := clip.track_get_key_time(hand,key)*60.-hit
				var weight := smoothstep(-9.,-2.,relative_frame)*(1.-smoothstep(0.,11.,relative_frame))
				if weight>0.:
					var rotation: Quaternion=clip.track_get_key_value(hand,key)
					clip.track_set_key_value(hand,key,rotation*Quaternion(Vector3.BACK,deg_to_rad(75.)*weight))
	if rig!=null and hit>=0 and clip.has_meta("editor_ball_frames"):
		align_contact(clip,rig,hit)
		buffer_fast_poses(clip,rig,hit)
	return clip

static func align_contact(clip: Animation, rig: Skeleton3D, hit: int) -> void:
	var balls: Array=clip.get_meta("editor_ball_frames")
	var session=preload("res://scripts/animation_edit_session.gd").new(clip,rig)
	var hand := rig.find_bone("hand_r")
	var parent := rig.get_bone_parent(hand)
	var world: Transform3D=clip.get_meta("editor_rig_world",rig.global_transform)
	var point := func(name_: String) -> Vector3: return rig.get_bone_global_pose(rig.find_bone(name_)).origin
	for f in range(maxi(0,hit-1),mini(hit+10,balls.size())):
		var weight := smoothstep(hit-2.,hit,f)*(1.-smoothstep(hit+2.,hit+9.,f))
		session.sample(f)
		preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
		for digit in ["index","middle","ring","pinky","thumb"]:
			for segment in ["01","02","03"]:
				var bone := rig.find_bone(digit+"_"+segment+"_r")
				if bone<0: continue
				var t: int=session.rotation_tracks[bone]
				if t>=0:
					var opened := rig.get_bone_pose_rotation(bone).slerp(rig.get_bone_rest(bone).basis.get_rotation_quaternion(),weight)
					rig.set_bone_pose_rotation(bone,opened)
					clip.rotation_track_insert_key(t,f/60.,opened)
		var wrist: Vector3=point.call("hand_r")
		var fingers: Vector3=point.call("middle_01_r")-wrist
		var normal := fingers.cross(point.call("pinky_01_r")-point.call("index_01_r")).normalized()
		var ball: Vector3=world.affine_inverse()*balls[f].origin
		var radial := wrist.direction_to(ball)
		var tangent := fingers.slide(radial).normalized()
		if tangent.is_zero_approx(): continue
		# Aim the palm surface at the ball center, accounting for its offset from the wrist.
		var angle := asin(clampf(.8*fingers.length()/maxf(.001,wrist.distance_to(ball)),0.,.99))
		var target := radial*cos(angle)-tangent*sin(angle)
		var axis := rig.get_bone_global_pose(parent).basis.orthonormalized()
		var turn := Quaternion((axis.inverse()*normal).normalized(),(axis.inverse()*target).normalized())
		var q := rig.get_bone_pose_rotation(hand)
		clip.rotation_track_insert_key(session.rotation_tracks[hand],f/60.,q.slerp(turn*q,weight).normalized())

	var straight := preload("res://scripts/spike_wrist_motion.gd").straight_right(rig)
	var track: int=session.rotation_tracks[hand]
	var start := int(clip.get_meta("swing_frame_offset",0))+7
	for key in clip.track_get_key_count(track):
		var f := clip.track_get_key_time(track,key)*60.
		var lock := smoothstep(start,start+5.,f)*(1.-smoothstep(hit+2.,hit+12.,f))
		if lock>0.:
			var q: Quaternion=clip.track_get_key_value(track,key)
			clip.track_set_key_value(track,key,q.slerp(straight,lock))
	# Place the recorded ball against the final posed palm during the contact interval.
	var corrected := balls.duplicate()
	var entry_shift := Vector3.ZERO
	var exit_shift := Vector3.ZERO
	for f in range(hit,mini(hit+3,balls.size())):
		session.sample(f)
		preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
		var wrist: Vector3=world*point.call("hand_r")
		var knuckle: Vector3=world*point.call("middle_01_r")
		var edge: Vector3=world.basis*(point.call("pinky_01_r")-point.call("index_01_r"))
		var normal := (knuckle-wrist).cross(edge).normalized()
		var touch := wrist.lerp(knuckle,.8)+normal*.105
		exit_shift=touch-balls[f].origin
		if f==hit: entry_shift=exit_shift
		corrected[f].origin=touch
	for f in range(maxi(0,hit-7),hit):
		corrected[f].origin+=entry_shift*smoothstep(hit-7.,hit,f)
	for f in range(hit+3,mini(hit+14,balls.size())):
		corrected[f].origin+=exit_shift*(1.-smoothstep(hit+2.,hit+14.,f))
	clip.set_meta("editor_ball_frames",corrected)

static func align_draw_palm(clip: Animation, rig: Skeleton3D, start: int, hit: int) -> void:
	var session=preload("res://scripts/animation_edit_session.gd").new(clip,rig)
	var forearm := rig.find_bone("lowerarm_r")
	var track := clip.find_track(NodePath("Armature/Skeleton3D:lowerarm_r"),Animation.TYPE_ROTATION_3D)
	var point := func(bone: String) -> Vector3: return rig.get_bone_global_pose(rig.find_bone(bone)).origin
	for f in range(start+9,hit-2):
		session.sample(f)
		preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
		var wrist: Vector3=point.call("hand_r")
		var axis: Vector3=point.call("lowerarm_r").direction_to(wrist)
		var fingers := wrist.direction_to(point.call("middle_01_r"))
		var edge: Vector3=point.call("pinky_01_r")-point.call("index_01_r")
		var normal := fingers.cross(edge).normalized().slide(axis)
		var down := Vector3.DOWN.slide(axis)
		var can_roll := minf(normal.length_squared(),down.length_squared())>.00001
		var weight := smoothstep(start+8.,start+17.,f)*(1.-smoothstep(hit-9.,hit-2.,f))
		var roll := normal.signed_angle_to(down,axis)*weight if can_roll else 0.
		var local_axis := rig.get_bone_global_pose(forearm).basis.inverse()*axis
		var rotation := rig.get_bone_pose_rotation(forearm)*Quaternion(local_axis.normalized(),roll)
		clip.rotation_track_insert_key(track,f/60.,rotation.normalized())
		rig.set_bone_pose_rotation(forearm,rotation.normalized())
		fingers=wrist.direction_to(point.call("middle_01_r"))
		edge=point.call("pinky_01_r")-point.call("index_01_r")
		normal=fingers.cross(edge).normalized()
		if normal.y>-.15 and fingers.slide(Vector3.UP).length()>.001:
			var hand := rig.find_bone("hand_r")
			var hand_axis := rig.get_bone_global_pose(hand).basis.inverse()*fingers
			var residual := normal.signed_angle_to(Vector3.DOWN.slide(fingers),fingers)
			var hand_rotation := rig.get_bone_pose_rotation(hand)*Quaternion(hand_axis.normalized(),clampf(residual,-.62,.62)*weight)
			clip.rotation_track_insert_key(session.rotation_tracks[hand],f/60.,hand_rotation.normalized())

static func rotation(rng: RandomNumberGenerator,width: Vector3) -> Quaternion:
	var angles := Vector3(rng.randf_range(-1.,1.),rng.randf_range(-1.,1.),rng.randf_range(-1.,1.))*width
	return Quaternion.from_euler(angles*PI/180.)

# Stretch only the intervals whose posed joints exceed the preview motion budget.
static func buffer_fast_poses(clip: Animation, rig: Skeleton3D, hit: int) -> void:
	var session=preload("res://scripts/animation_edit_session.gd").new(clip,rig)
	var world: Transform3D=clip.get_meta("editor_rig_world",rig.global_transform)
	var previous := PackedVector3Array()
	var mapping: Array[int]=[0]
	var balls: Array=clip.get_meta("editor_ball_frames")
	var retimed: Array[Transform3D]=[balls[0]]
	var swing_start := int(clip.get_meta("swing_frame_offset",0))+10
	var joints := PackedInt32Array()
	for name_ in ["upperarm_r","lowerarm_r","hand_r","middle_03_r"]:
		joints.append(rig.find_bone(name_))
	for f in balls.size():
		var steps := 1
		if f>=swing_start and f<=hit+18:
			session.sample(f)
			preload("res://scripts/player_arm_clearance.gd").resolve(rig,"r")
			var current := PackedVector3Array()
			for joint in joints: current.append(world*rig.get_bone_global_pose(joint).origin)
			if not previous.is_empty() and farthest_step(previous,current)>.10:
				steps=2
			previous=current
		if f==0: continue
		mapping.append(mapping.back()+steps)
		for step in range(1,steps+1):
			retimed.append(balls[f-1].interpolate_with(balls[f],float(step)/steps))
	clip.length=(retimed.size()-1)/60.
	for track in clip.get_track_count():
		for key in range(clip.track_get_key_count(track)-1,-1,-1):
			var old := clampi(roundi(clip.track_get_key_time(track,key)*60.),0,mapping.size()-1)
			clip.track_set_key_time(track,key,mapping[old]/60.)
	clip.set_meta("editor_ball_frames",retimed)
	clip.set_meta("editor_frame_count",retimed.size())
	clip.set_meta("swing_hit_frame",mapping[hit])
	clip.set_meta("source_frame_map",mapping)
static func farthest_step(a: PackedVector3Array,b: PackedVector3Array) -> float:
	var squared := 0.
	for i in a.size(): squared=maxf(squared,a[i].distance_squared_to(b[i]))
	return sqrt(squared)